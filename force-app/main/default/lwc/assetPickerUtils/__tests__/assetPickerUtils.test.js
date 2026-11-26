import {
    tokenize,
    emptyMap,
    addSearchText,
    filterBySearch,
    filterByColumns,
    compareValues,
    formatCount
} from 'c/assetPickerUtils';

const COLUMNS = [{ field: 'serialNumber' }, { field: 'name' }, { field: 'manufacturer' }, { field: 'model' }];
const CRITERIA = [{ field: 'manufacturer' }, { field: 'model' }];

const rows = [
    { id: '1', serialNumber: 'SN-100', name: 'Scope A', manufacturer: 'OLYMPUS', model: 'GIF-H190' },
    { id: '2', serialNumber: 'SN-200', name: 'Scope B', manufacturer: 'PENTAX', model: 'EG-2990i' },
    { id: '3', serialNumber: 'SN-300', name: 'Light Source', manufacturer: 'OLYMPUS', model: 'CLV-190' }
].map((r) => addSearchText({ ...r }, COLUMNS));

describe('c-asset-picker-utils', () => {
    it('tokenizes and builds empty maps', () => {
        expect(tokenize('  Olympus   GIF ')).toEqual(['olympus', 'gif']);
        expect(tokenize(null)).toEqual([]);
        expect(emptyMap(CRITERIA)).toEqual({ manufacturer: '', model: '' });
    });

    it('search bar needs every word, in any column', () => {
        expect(filterBySearch(rows, 'olympus scope', CRITERIA, emptyMap(CRITERIA)).map((r) => r.id)).toEqual(['1']);
        expect(filterBySearch(rows, '', CRITERIA, emptyMap(CRITERIA))).toHaveLength(3);
    });

    it('criteria match their own field only', () => {
        const criteria = { manufacturer: 'olymp', model: '190' };
        expect(filterBySearch(rows, '', CRITERIA, criteria).map((r) => r.id)).toEqual(['1', '3']);
        expect(filterBySearch(rows, '', CRITERIA, { manufacturer: 'SN-100', model: '' })).toHaveLength(0);
    });

    it('column filters refine the rows', () => {
        expect(filterByColumns(rows, COLUMNS, { ...emptyMap(COLUMNS), name: 'scope' }).map((r) => r.id)).toEqual([
            '1',
            '2'
        ]);
        expect(filterByColumns(rows, COLUMNS, emptyMap(COLUMNS))).toBe(rows);
    });

    it('sorts blanks last and numbers in numeric order', () => {
        expect(['SN-10', '', 'SN-9', null].sort(compareValues)).toEqual(['SN-9', 'SN-10', '', null]);
        expect(compareValues('a', 'A')).toBe(0);
    });

    it('formats counts', () => {
        expect(formatCount(1284)).toBe(new Intl.NumberFormat().format(1284));
        expect(formatCount(undefined)).toBe('0');
    });
});
