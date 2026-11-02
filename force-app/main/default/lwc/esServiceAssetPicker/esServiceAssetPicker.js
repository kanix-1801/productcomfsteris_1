/** 
 * @description ES Service Product Configurator: "Choose Assets" picker (modal).
 * Loads all assets once (the quote's account and its related accounts), then searches,
 * filters, sorts, and selects in the browser.
 * Filtering happens in two steps:
 * 1. Search: the search bar (all columns) and the five criteria fields (Product Line,
      Sub Product Line, Product Type, Manufacturer, Model) decide which assets come back.
   2. Column filters: narrow the search results further. Typing in the search bar or any
      criteria field clears the column filters, so they always refine the current search.
   All matching is "contains", ignores case, and every word typed must match.
*/
import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import getAssets from '@salesforce/apex/EsServiceAssetSelectionController.getAssets';

const PAGE_SIZE = 100;
const SEARCH_DEBOUNCE_MS = 250;

// Table columns, in order. Each column can be sorted and filtered.
const COLUMNS = [
    { field: 'serialNumber', label: 'Serial Number', width: '9rem' },
    { field: 'name', label: 'Asset Name', width: '13rem' },
    { field: 'pfcl', label: 'PFCL', width: '10rem' },
    { field: 'status', label: 'Asset Status', width: '8rem' },
    { field: 'accountName', label: 'Account', width: '13rem' },
    { field: 'address', label: 'Address', width: '16rem' },
    { field: 'installDate', label: 'Install Date', width: '8rem' },
    { field: 'productLine', label: 'Product Line', width: '10rem' },
    { field: 'subProductLine', label: 'Sub Product Line', width: '11rem' },
    { field: 'productType', label: 'Product Type', width: '10rem' },
    { field: 'manufacturer', label: 'Manufacturer', width: '10rem' },
    { field: 'model', label: 'Model', width: '9rem' }
];

// Search criteria fields shown above the table.
const CRITERIA = [
    { field: 'productLine', label: 'Product Line' },
    { field: 'subProductLine', label: 'Sub Product Line' },
    { field: 'productType', label: 'Product Type' },
    { field: 'manufacturer', label: 'Manufacturer' },
    { field: 'model', label: 'Model' }
];

const emptyMap = (list) => Object.fromEntries(list.map((c) => [c.field, '']));
const tokenize = (text) => String(text || '').toLowerCase().split(/\s+/).filter(Boolean);

export default class EsServiceAssetPicker extends LightningModal {
    @api quoteId;
    @api bundleName = 'ES Service Agreement';
    @api selectedIds = []; // Asset Ids already selected

    loading = true;
    loadError;
    truncated = false;
    maxRows;
    relatedAccountCount = 0;

    allRows = [];
    quoteAccountId;
    selected = new Set();
    selectionVersion = 0; // bumps on every selection change so getters re-render

    // What's typed (shown in the inputs) and what's applied (after the typing pause).
    searchText = '';
    criteriaText = emptyMap(CRITERIA);
    columnText = emptyMap(COLUMNS);
    applied = { search: '', criteria: emptyMap(CRITERIA), columns: emptyMap(COLUMNS) };

    showSelectedOnly = false;
    sortField = null; // null = default order
    sortDirection = 'asc';
    visibleCount = PAGE_SIZE;
    selectAllWarning = false;

    searchTimer;
    pinned = new Set(); // selection at open; drives "selected first" so rows don't jump while clicking
    // Not reactive on purpose (properties are mutated, the field is never reassigned),
    // so filling the cache during render doesn't trigger another render.
    _cache = { key: null, searchKey: null, searchRows: [], rows: [] };

    // ---------- Load ----------

    async connectedCallback() {
        this.selected = new Set(this.selectedIds || []);
        this.pinned = new Set(this.selected);
        try {
            const result = await getAssets({ quoteId: this.quoteId });
            this.quoteAccountId = result?.quoteAccountId;
            this.truncated = !!result?.truncated;
            this.maxRows = result?.maxRows;
            this.relatedAccountCount = result?.relatedAccountCount || 0;
            this.allRows = (result?.rows || []).map((r) => this.prepareRow(r));
        } catch (e) {
            this.loadError = e?.body?.message || e?.message || 'Could not load assets.';
        } finally {
            this.loading = false;
        }
    }

    // Adds display values and lower-case text for matching.
    prepareRow(r) {
        const row = { ...r, installDateLabel: r.installDate ? this.formatDate(r.installDate) : '' };
        const lc = {};
        COLUMNS.forEach((c) => {
            let value = row[c.field];
            // Install Date matches both the displayed date and yyyy-mm-dd.
            if (c.field === 'installDate') value = [row.installDateLabel, row.installDate].filter(Boolean).join(' ');
            lc[c.field] = String(value ?? '').toLowerCase();
        });
        row.lc = lc;
        row.searchText = Object.values(lc).filter(Boolean).join(' ');
        return row;
    }

    disconnectedCallback() {
        clearTimeout(this.searchTimer);
    }

    // ---------- Derived data ----------

    // Step 1: search bar + criteria. Cached separately so column filters stay quick.
    get searchRows() {
        const key = [this.allRows.length, JSON.stringify(this.applied.search), JSON.stringify(this.applied.criteria)].join('|');
        if (key === this._cache.searchKey) {
            return this._cache.searchRows;
        }
        const searchTokens = tokenize(this.applied.search);
        const criteria = CRITERIA.map((c) => ({ field: c.field, tokens: tokenize(this.applied.criteria[c.field]) })).filter(
            (c) => c.tokens.length
        );
        let rows = this.allRows;
        if (searchTokens.length) {
            rows = rows.filter((r) => searchTokens.every((t) => r.searchText.includes(t)));
        }
        if (criteria.length) {
            rows = rows.filter((r) => criteria.every((c) => c.tokens.every((t) => r.lc[c.field].includes(t))));
        }
        this._cache.searchRows = rows;
        this._cache.searchKey = key;
        return rows;
    }

    // Step 2: column filters, "show selected only", then sort.
    get filteredRows() {
        const searchRows = this.searchRows;
        const key = [
            this._cache.searchKey,
            JSON.stringify(this.applied.columns),
            this.showSelectedOnly,
            this.sortField,
            this.sortDirection,
            this.showSelectedOnly ? this.selectionVersion : 0
        ].join('|');
        if (key === this._cache.key) return this._cache.rows;
        const columnFilters = COLUMNS.map((c) => ({ field: c.field, tokens: tokenize(this.applied.columns[c.field]) })).filter(
            (c) => c.tokens.length
        );
        let rows = searchRows;
        if (columnFilters.length) {
            rows = rows.filter((r) => columnFilters.every((c) => c.tokens.every((t) => r.lc[c.field].includes(t))));
        }
        if (this.showSelectedOnly) rows = rows.filter((r) => this.selected.has(r.id));
        this._cache.rows = [...rows].sort((a, b) => this.compare(a, b));
        this._cache.key = key;
        return this._cache.rows;
    }

    compare(a, b) {
        if (!this.sortField) {
            // Default: selected first, then the quote's account, then by account and serial number.
            const sa = this.pinned.has(a.id) ? 0 : 1;
            const sb = this.pinned.has(b.id) ? 0 : 1;
            if (sa !== sb) {
                return sa - sb;
            }
            const qa = a.accountId && a.accountId === this.quoteAccountId ? 0 : 1;
            const qb = b.accountId && b.accountId === this.quoteAccountId ? 0 : 1;
            if (qa !== qb) {
                return qa - qb;
            }
            return this.cmp(a.accountName, b.accountName) || this.cmp(a.serialNumber, b.serialNumber);
        }
        const result = this.cmp(a[this.sortField], b[this.sortField]);
        return this.sortDirection === 'asc' ? result : -result;
    }

    cmp(x, y) {
        if (x === y) {
            return 0;
        }
        if (x === null || x === undefined || x === '') {
            return 1; // blanks last
        }
        if (y === null || y === undefined || y === '') {
            return -1;
        }
        return String(x).localeCompare(String(y), undefined, { numeric: true, sensitivity: 'base' });
    }

    get filtered() {
        return this.filteredRows;
    }

    get displayRows() {
        // eslint-disable-next-line no-unused-expressions
        this.selectionVersion; // re-render checkboxes when selection changes
        const rows = this.filtered.slice(0, this.visibleCount);
        const showDivider = !this.sortField && !this.showSelectedOnly;
        let dividerShown = false;
        return rows.map((r, i) => {
            const isSelected = this.selected.has(r.id);
            const dividerBefore =
                showDivider && !dividerShown && !this.pinned.has(r.id) && i > 0 && this.pinned.has(rows[i - 1].id);
            if (dividerBefore) {
                dividerShown = true;
            }
            return {
                ...r,
                isSelected,
                dividerBefore,
                dividerKey: `divider-${r.id}`,
                rowClass: isSelected ? 'row row-selected' : 'row',
                checkboxLabel: `Select ${r.serialNumber || r.name}`
            };
        });
    }

    get columns() {
        return COLUMNS.map((c) => {
            const active = this.sortField === c.field;
            const filterValue = this.columnText[c.field];
            return {
                ...c,
                style: `width: ${c.width}`,
                ariaSort: active ? (this.sortDirection === 'asc' ? 'ascending' : 'descending') : 'none',
                iconName: active && this.sortDirection === 'desc' ? 'utility:arrowup' : 'utility:arrowdown',
                iconClass: active ? 'sort-icon sort-icon-active' : 'sort-icon',
                filterKey: `filter-${c.field}`,
                filterValue,
                filterLabel: `Filter ${c.label}`,
                filterClass: filterValue ? 'column-filter column-filter-active' : 'column-filter'
            };
        });
    }

    get criteriaFields() {
        return CRITERIA.map((c) => ({
            ...c,
            inputId: `criteria-${c.field}`,
            value: this.criteriaText[c.field]
        }));
    }

    get columnCount() {
        return COLUMNS.length + 1;
    }

    get hasSearch() {
        return !!this.searchText.trim() || CRITERIA.some((c) => this.criteriaText[c.field].trim());
    }

    get hasColumnFilters() {
        return COLUMNS.some((c) => this.columnText[c.field].trim());
    }

    get selectedCount() {
        // eslint-disable-next-line no-unused-expressions
        this.selectionVersion;
        return this.selected.size;
    }

    get filteredCount() {
        return this.filtered.length;
    }

    get shownCount() {
        return Math.min(this.visibleCount, this.filteredCount);
    }

    get totalCount() {
        return this.allRows.length;
    }

    get hiddenSelectedCount() {
        // eslint-disable-next-line no-unused-expressions
        this.selectionVersion;
        return this.filtered.slice(this.visibleCount).filter((r) => this.selected.has(r.id)).length;
    }

    get showWarning() {
        return this.selectAllWarning && this.hiddenSelectedCount > 0;
    }

    get allFilteredSelected() {
        // eslint-disable-next-line no-unused-expressions
        this.selectionVersion;
        const rows = this.filtered;
        return rows.length > 0 && rows.every((r) => this.selected.has(r.id));
    }

    get someFilteredSelected() {
        // eslint-disable-next-line no-unused-expressions
        this.selectionVersion;
        return this.filtered.some((r) => this.selected.has(r.id));
    }

    get sortDescription() {
        if (this.sortField) {
            const col = COLUMNS.find((c) => c.field === this.sortField);
            return `sorted by ${col.label} (${this.sortDirection === 'asc' ? 'ascending' : 'descending'})`;
        }
        return 'selected first, then the quote’s account, then by account and serial number';
    }

    get scopeDescription() {
        const n = this.relatedAccountCount;
        if (!n) return 'the quote’s account';
        return `the quote’s account and ${n} related account${n === 1 ? '' : 's'}`;
    }

    get saveLabel() {
        return `Save Selection (${this.selectedCount})`;
    }

    get showEmpty() {
        return this.filteredCount === 0;
    }

    get emptyMessage() {
        if (this.showSelectedOnly) {
            return 'No selected assets match.';
        }
        if (this.applied.search || CRITERIA.some((c) => this.applied.criteria[c.field])) {
            return this.searchRows.length ? 'No assets match the column filters.' : 'No assets match your search.';
        }
        if (COLUMNS.some((c) => this.applied.columns[c.field])) {
            return 'No assets match the column filters.';
        }
        return 'No assets found for the quote’s account or its related accounts.';
    }

    renderedCallback() {
        const all = this.template.querySelector('input[data-id="select-all"]');
        if (all) {
            all.indeterminate = !this.allFilteredSelected && this.someFilteredSelected;
        }
    }

    // ---------- Search, criteria, column filters ----------

    // Apply what's typed after a short pause.
    scheduleApply() {
        clearTimeout(this.searchTimer);
        this.searchTimer = setTimeout(() => this.applyNow(), SEARCH_DEBOUNCE_MS);
    }

    applyNow() {
        clearTimeout(this.searchTimer);
        this.applied = {
            search: this.searchText.trim(),
            criteria: { ...this.criteriaText },
            columns: { ...this.columnText }
        };
        this.resetScroll();
    }

    // A change to the search clears the column filters (they refine the current search only).
    clearColumnFilters() {
        if (this.hasColumnFilters) this.columnText = emptyMap(COLUMNS);
    }

    handleSearch(event) {
        this.searchText = event.target.value;
        this.clearColumnFilters();
        this.scheduleApply();
    }

    handleCriteria(event) {
        const field = event.target.dataset.field;
        this.criteriaText = { ...this.criteriaText, [field]: event.target.value };
        this.clearColumnFilters();
        this.scheduleApply();
    }

    handleColumnFilter(event) {
        const field = event.target.dataset.field;
        this.columnText = { ...this.columnText, [field]: event.target.value };
        this.scheduleApply();
    }

    handleClearSearch() {
        this.searchText = '';
        this.criteriaText = emptyMap(CRITERIA);
        this.columnText = emptyMap(COLUMNS);
        this.applyNow();
    }

    handleClearColumnFilters() {
        this.columnText = emptyMap(COLUMNS);
        this.applyNow();
    }

    handleShowSelectedOnly(event) {
        this.showSelectedOnly = event.target.checked;
        this.resetScroll();
    }

    handleSort(event) {
        const field = event.currentTarget.dataset.field;
        if (this.sortField === field) {
            this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortField = field;
            this.sortDirection = 'asc';
        }
        this.resetScroll();
    }

    handleDefaultSort() {
        this.pinned = new Set(this.selected);
        this._cache.key = null;
        this.sortField = null;
        this.sortDirection = 'asc';
        this.resetScroll();
    }

    get isCustomSort() {
        return !!this.sortField;
    }

    resetScroll() {
        this.visibleCount = PAGE_SIZE;
        const wrap = this.template.querySelector('.table-wrap');
        if (wrap) wrap.scrollTop = 0;
    }

    handleScroll(event) {
        const el = event.target;
        if (el.scrollTop + el.clientHeight >= el.scrollHeight - 200 && this.visibleCount < this.filteredCount) {
            this.visibleCount += PAGE_SIZE;
        }
    }

    // ---------- Selection ----------

    handleRowToggle(event) {
        const id = event.target.dataset.id;
        if (event.target.checked) this.selected.add(id);
        else this.selected.delete(id);
        this.selectAllWarning = false;
        this.selectionVersion++;
    }

    handleSelectAll(event) {
        const rows = this.filtered;
        if (event.target.checked) {
            rows.forEach((r) => this.selected.add(r.id));
            this.selectAllWarning = rows.length > this.visibleCount;
        } else {
            rows.forEach((r) => this.selected.delete(r.id));
            this.selectAllWarning = false;
        }
        this.selectionVersion++;
    }

    handleClearAll(event) {
        event.preventDefault();
        this.selected.clear();
        this.selectAllWarning = false;
        this.selectionVersion++;
    }

    // ---------- Close ----------

    handleCancel() {
        this.close();
    }

    handleSave() {
        const ids = [...this.selected];
        const byId = new Map(this.allRows.map((r) => [r.id, r]));
        const rows = ids.map((id) => byId.get(id)).filter(Boolean);
        this.close({ ids, rows });
    }

    formatDate(value) {
        // value is yyyy-mm-dd
        const [y, m, d] = String(value).split('-').map(Number);
        if (!y) return String(value);
        return new Intl.DateTimeFormat(undefined, { year: 'numeric', month: 'short', day: 'numeric' }).format(
            new Date(y, m - 1, d)
        );
    }
}