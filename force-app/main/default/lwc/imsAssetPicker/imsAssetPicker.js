/**
 * @description GW-6456 - IMS Covered Equipment, step 2 (modal): "Choose Assets".
 * Loads once: the chosen inventory groups' devices (Source = Opportunity, listed first) and the assets on the
 * quote's account and its related accounts (Source = Account). When the opportunity's devices are included they
 * start selected (minus the ones removed before); assets added before start selected too.
 * Search, criteria and column filters work as in esServiceAssetPicker (shared c/assetPickerUtils).
 * Closes with { removedAssetIds, addedAssetIds } (differences against the groups, not the full list), or nothing
 * on Cancel.
 */
import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import getEligibleAssets from '@salesforce/apex/ImsAssetAssignmentController.getEligibleAssets';
import {
    PAGE_SIZE,
    SEARCH_DEBOUNCE_MS,
    emptyMap,
    addSearchText,
    filterBySearch,
    filterByColumns,
    compareValues,
    formatCount
} from 'c/assetPickerUtils';

const SOURCE_OPPORTUNITY = 'Opportunity';

// Table columns, in order. Each can be sorted and filtered.
const COLUMNS = [
    { field: 'source', label: 'Source', width: '7.5rem' },
    { field: 'serialNumber', label: 'Serial Number', width: '9rem' },
    { field: 'name', label: 'Asset Name', width: '13rem' },
    { field: 'pfcl', label: 'PFCL', width: '10rem' },
    { field: 'productLine', label: 'Product Line', width: '10rem' },
    { field: 'manufacturer', label: 'Manufacturer', width: '10rem' },
    { field: 'model', label: 'Model', width: '9rem' },
    { field: 'accountName', label: 'Account', width: '13rem' }
];

// Item-number segments searched above the table
const CRITERIA = [
    { field: 'productLine', label: 'Product Line' },
    { field: 'subProductLine', label: 'Sub Product Line' },
    { field: 'productType', label: 'Device Type' },
    { field: 'manufacturer', label: 'Manufacturer' },
    { field: 'model', label: 'Model' }
];

// Everything the search bar and criteria match against (columns + the two segments not shown as columns)
const SEARCH_FIELDS = [...COLUMNS, { field: 'subProductLine' }, { field: 'productType' }];

export default class ImsAssetPicker extends LightningModal {
    @api quoteId;
    @api opportunityId;
    @api opportunityName;
    @api productName = 'SERVICE AGREEMENT';
    @api groups = [];
    @api includeOpportunityAssets;
    @api removedAssetIds = [];
    @api addedAssetIds = [];

    loading = true;
    loadError;
    truncated = false;
    maxRows;
    relatedAccountCount = 0;
    quoteAccountId;

    allRows = [];
    opportunityIds = new Set(); // assets that came from the groups
    selected = new Set();
    selectionVersion = 0; // bumps on every selection change so getters re-render

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
    // Not reactive on purpose (mutated, never reassigned), so filling it during render doesn't re-render.
    _cache = { key: null, searchKey: null, searchRows: [], rows: [] };

    // ---------- Load ----------

    async connectedCallback() {
        try {
            const result = await getEligibleAssets({
                quoteId: this.quoteId,
                opportunityId: this.opportunityId,
                groups: this.includeOpportunityAssets ? this.groups || [] : []
            });
            this.quoteAccountId = result?.quoteAccountId;
            this.truncated = !!result?.truncated;
            this.maxRows = result?.maxRows;
            this.relatedAccountCount = result?.relatedAccountCount || 0;
            this.allRows = (result?.rows || []).map((r) => addSearchText({ ...r }, SEARCH_FIELDS));
            this.opportunityIds = new Set(
                this.allRows.filter((r) => r.source === SOURCE_OPPORTUNITY).map((r) => r.id)
            );
            this.selected = this.initialSelection();
        } catch (e) {
            this.loadError = e?.body?.message || e?.message || 'Could not load assets.';
        } finally {
            this.loading = false;
        }
    }

    // Group devices (when included) minus the removed ones, plus the assets added before
    initialSelection() {
        const removed = new Set(this.removedAssetIds || []);
        const selected = new Set(this.addedAssetIds || []);
        if (this.includeOpportunityAssets) {
            this.opportunityIds.forEach((id) => {
                if (!removed.has(id)) selected.add(id);
            });
        }
        return selected;
    }

    disconnectedCallback() {
        clearTimeout(this.searchTimer);
    }

    // ---------- Derived data ----------

    get searchRows() {
        const key = [this.allRows.length, JSON.stringify(this.applied.search), JSON.stringify(this.applied.criteria)].join('|');
        if (key === this._cache.searchKey) return this._cache.searchRows;
        this._cache.searchRows = filterBySearch(this.allRows, this.applied.search, CRITERIA, this.applied.criteria);
        this._cache.searchKey = key;
        return this._cache.searchRows;
    }

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
        let rows = filterByColumns(searchRows, COLUMNS, this.applied.columns);
        if (this.showSelectedOnly) rows = rows.filter((r) => this.selected.has(r.id));
        this._cache.rows = [...rows].sort((a, b) => this.compare(a, b));
        this._cache.key = key;
        return this._cache.rows;
    }

    compare(a, b) {
        if (!this.sortField) {
            // Default: opportunity devices first, then the quote's account, then by account and serial number
            const oa = this.opportunityIds.has(a.id) ? 0 : 1;
            const ob = this.opportunityIds.has(b.id) ? 0 : 1;
            if (oa !== ob) return oa - ob;
            const qa = a.accountId && a.accountId === this.quoteAccountId ? 0 : 1;
            const qb = b.accountId && b.accountId === this.quoteAccountId ? 0 : 1;
            if (qa !== qb) return qa - qb;
            return compareValues(a.accountName, b.accountName) || compareValues(a.serialNumber, b.serialNumber);
        }
        const result = compareValues(a[this.sortField], b[this.sortField]);
        return this.sortDirection === 'asc' ? result : -result;
    }

    get displayRows() {
        // eslint-disable-next-line no-unused-expressions
        this.selectionVersion; // re-render checkboxes when the selection changes
        return this.filteredRows.slice(0, this.visibleCount).map((r) => {
            const isSelected = this.selected.has(r.id);
            const isOpportunity = this.opportunityIds.has(r.id);
            let rowClass = 'row';
            if (isSelected) rowClass += ' row-selected';
            else if (isOpportunity && this.includeOpportunityAssets) rowClass += ' row-removed';
            return {
                ...r,
                isSelected,
                rowClass,
                sourceClass: isOpportunity ? 'badge badge-opportunity' : 'badge badge-account',
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
        return CRITERIA.map((c) => ({ ...c, inputId: `criteria-${c.field}`, value: this.criteriaText[c.field] }));
    }

    get subtitle() {
        const opp = this.opportunityName ? `Opportunity ${this.opportunityName}` : 'the opportunity';
        return `${this.productName} · when "Include the opportunity's devices" is on, devices on ${opp} start selected. `
            + 'Untick any you don’t want and search to add others.';
    }

    get hasSearch() {
        return !!this.searchText.trim() || CRITERIA.some((c) => this.criteriaText[c.field].trim());
    }

    get hasColumnFilters() {
        return COLUMNS.some((c) => this.columnText[c.field].trim());
    }

    get isCustomSort() {
        return !!this.sortField;
    }

    get selectedCount() {
        // eslint-disable-next-line no-unused-expressions
        this.selectionVersion;
        return this.selected.size;
    }

    get selectedCountLabel() {
        return formatCount(this.selectedCount);
    }

    get filteredCount() {
        return this.filteredRows.length;
    }

    get showEmpty() {
        return this.filteredCount === 0;
    }

    get emptyMessage() {
        if (this.showSelectedOnly) return 'No selected assets match.';
        if (this.applied.search || CRITERIA.some((c) => this.applied.criteria[c.field])) {
            return this.searchRows.length ? 'No assets match the column filters.' : 'No assets match your search.';
        }
        if (COLUMNS.some((c) => this.applied.columns[c.field])) return 'No assets match the column filters.';
        return 'No assets found for the opportunity, the quote’s account or its related accounts.';
    }

    get hiddenSelectedCount() {
        // eslint-disable-next-line no-unused-expressions
        this.selectionVersion;
        return this.filteredRows.slice(this.visibleCount).filter((r) => this.selected.has(r.id)).length;
    }

    get showWarning() {
        return this.selectAllWarning && this.hiddenSelectedCount > 0;
    }

    get allFilteredSelected() {
        // eslint-disable-next-line no-unused-expressions
        this.selectionVersion;
        const rows = this.filteredRows;
        return rows.length > 0 && rows.every((r) => this.selected.has(r.id));
    }

    get someFilteredSelected() {
        // eslint-disable-next-line no-unused-expressions
        this.selectionVersion;
        return this.filteredRows.some((r) => this.selected.has(r.id));
    }

    // Footer: "Showing 11 of 2,310 assets for the quote's account and 2 related accounts – opportunity devices first"
    get showingText() {
        const n = this.relatedAccountCount;
        const scope = n ? `the quote’s account and ${n} related account${n === 1 ? '' : 's'}` : 'the quote’s account';
        const order = this.sortField ? 'custom order' : 'opportunity devices first';
        return `Showing ${formatCount(Math.min(this.visibleCount, this.filteredCount))} of ${formatCount(this.filteredCount)} `
            + `matching (${formatCount(this.allRows.length)} assets for ${scope}) – ${order}`;
    }

    // Footer: "1,283 of 1,284 opportunity devices + 1 added = 1,284 covered"
    get coveredCounts() {
        // eslint-disable-next-line no-unused-expressions
        this.selectionVersion;
        const include = !!this.includeOpportunityAssets;
        let opportunity = 0;
        let added = 0;
        this.selected.forEach((id) => {
            if (include && this.opportunityIds.has(id)) opportunity++;
            else added++;
        });
        return { opportunity, added, total: opportunity + added };
    }

    get coveredText() {
        const c = this.coveredCounts;
        if (!this.includeOpportunityAssets) return `${formatCount(c.added)} added = ${formatCount(c.total)} covered`;
        return `${formatCount(c.opportunity)} of ${formatCount(this.opportunityIds.size)} opportunity devices + `
            + `${formatCount(c.added)} added = ${formatCount(c.total)} covered`;
    }

    get saveLabel() {
        return `Save Selection (${this.selectedCountLabel})`;
    }

    get saveDisabled() {
        return this.loading || !!this.loadError;
    }

    renderedCallback() {
        const all = this.template.querySelector('input[data-id="select-all"]');
        if (all) all.indeterminate = !this.allFilteredSelected && this.someFilteredSelected;
    }

    // ---------- Search, criteria, column filters ----------

    scheduleApply() {
        clearTimeout(this.searchTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
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

    // A change to the search clears the column filters (they refine the current search only)
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
        this.sortField = null;
        this.sortDirection = 'asc';
        this.resetScroll();
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

    // Applies to the rows matching the current search / filters only
    handleSelectAll(event) {
        const rows = this.filteredRows;
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
        this.close(null);
    }

    // Differences against the groups: unticked group devices are "removed", everything else ticked is "added"
    handleSave() {
        const include = !!this.includeOpportunityAssets;
        const removedAssetIds = include ? [...this.opportunityIds].filter((id) => !this.selected.has(id)) : [];
        const addedAssetIds = [...this.selected].filter((id) => !(include && this.opportunityIds.has(id)));
        this.close({ removedAssetIds, addedAssetIds, counts: this.coveredCounts });
    }
}