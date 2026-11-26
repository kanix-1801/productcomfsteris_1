/**
 * @description Shared table / search helpers for the asset pickers (esServiceAssetPicker and, GW-6456,
 * imsAssetPicker). Both load every asset once and search, filter and sort in the browser.
 * All matching is "contains", ignores case, and every word typed must match.
 */

// Rows added to the table per scroll step
export const PAGE_SIZE = 100;
// Pause after typing before a search is applied
export const SEARCH_DEBOUNCE_MS = 250;

// { field: '' } for every entry of a column / criteria list
export const emptyMap = (list) => Object.fromEntries(list.map((c) => [c.field, '']));

// Lower-cased words of what was typed
export const tokenize = (text) =>
    String(text || '')
        .toLowerCase()
        .split(/\s+/)
        .filter(Boolean);

/**
 * Adds lower-case text for matching: row.lc[field] per column and row.searchText (all columns).
 * Install Date matches both the displayed date (installDateLabel) and yyyy-mm-dd.
 */
export function addSearchText(row, columns) {
    const lc = {};
    columns.forEach((c) => {
        let value = row[c.field];
        if (c.field === 'installDate') value = [row.installDateLabel, row.installDate].filter(Boolean).join(' ');
        lc[c.field] = String(value ?? '').toLowerCase();
    });
    row.lc = lc;
    row.searchText = Object.values(lc).filter(Boolean).join(' ');
    return row;
}

/**
 * Search bar (all columns) + criteria fields.
 * @param rows rows prepared with addSearchText
 * @param search text typed in the search bar
 * @param criteriaList [{ field }] criteria fields
 * @param criteriaValues { field: text }
 */
export function filterBySearch(rows, search, criteriaList, criteriaValues) {
    const searchTokens = tokenize(search);
    const criteria = criteriaList
        .map((c) => ({ field: c.field, tokens: tokenize(criteriaValues[c.field]) }))
        .filter((c) => c.tokens.length);
    let result = rows;
    if (searchTokens.length) {
        result = result.filter((r) => searchTokens.every((t) => r.searchText.includes(t)));
    }
    if (criteria.length) {
        result = result.filter((r) => criteria.every((c) => c.tokens.every((t) => (r.lc[c.field] || '').includes(t))));
    }
    return result;
}

/**
 * Column filters (refine the search results).
 * @param rows rows prepared with addSearchText
 * @param columnList [{ field }] columns
 * @param columnValues { field: text }
 */
export function filterByColumns(rows, columnList, columnValues) {
    const filters = columnList
        .map((c) => ({ field: c.field, tokens: tokenize(columnValues[c.field]) }))
        .filter((c) => c.tokens.length);
    if (!filters.length) return rows;
    return rows.filter((r) => filters.every((c) => c.tokens.every((t) => (r.lc[c.field] || '').includes(t))));
}

// Compares two values: blanks last, numbers inside text in numeric order, case ignored
export function compareValues(x, y) {
    if (x === y) {
        return 0;
    }
    if (x === null || x === undefined || x === '') {
        return 1;
    }
    if (y === null || y === undefined || y === '') {
        return -1;
    }
    return String(x).localeCompare(String(y), undefined, { numeric: true, sensitivity: 'base' });
}

// yyyy-mm-dd -> local display date, e.g. "Jan 5, 2026" (parsed as a local date so the day does not shift)
export function formatDate(value) {
    const [y, m, d] = String(value).split('-').map(Number);
    if (!y) return String(value);
    return new Intl.DateTimeFormat(undefined, { year: 'numeric', month: 'short', day: 'numeric' }).format(
        new Date(y, m - 1, d)
    );
}

// Thousands separators, e.g. 1284 -> "1,284"
export const formatCount = (n) => new Intl.NumberFormat().format(n || 0);
