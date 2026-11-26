import { createElement } from 'lwc';
import ImsAssetPicker from 'c/imsAssetPicker';
import getEligibleAssets from '@salesforce/apex/ImsAssetAssignmentController.getEligibleAssets';

jest.mock(
    '@salesforce/apex/ImsAssetAssignmentController.getEligibleAssets',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const OPP = (id, extra = {}) => ({ id, source: 'Opportunity', serialNumber: `SN-${id}`, name: `Asset ${id}`, ...extra });
const ACC = (id, extra = {}) => ({ id, source: 'Account', serialNumber: `SN-${id}`, name: `Asset ${id}`, ...extra });

const RESULT = {
    rows: [OPP('o1'), OPP('o2'), OPP('o3'), ACC('a1', { manufacturer: 'PENTAX' }), ACC('a2')],
    relatedAccountCount: 2,
    truncated: false,
    maxRows: 10000,
    quoteAccountId: '001000000000001'
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render(props) {
    getEligibleAssets.mockResolvedValue(RESULT);
    const element = createElement('c-ims-asset-picker', { is: ImsAssetPicker });
    Object.assign(element, { quoteId: '0Q0000000000001', opportunityId: '006000000000001', groups: ['Main'], ...props });
    const closed = jest.fn();
    element.addEventListener('close', (e) => closed(e.detail));
    document.body.appendChild(element);
    await flush();
    await flush();
    return { element, closed };
}

const checkbox = (element, id) => element.shadowRoot.querySelector(`input[data-id="${id}"]`);
const clickSave = (element) =>
    [...element.shadowRoot.querySelectorAll('lightning-button')].find((b) => b.label.startsWith('Save')).click();

describe('c-ims-asset-picker', () => {
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
    });

    it('asks Apex for the chosen groups when the devices are included', async () => {
        await render({ includeOpportunityAssets: true });
        expect(getEligibleAssets).toHaveBeenCalledWith({
            quoteId: '0Q0000000000001',
            opportunityId: '006000000000001',
            groups: ['Main']
        });
    });

    it('pre-selects group devices minus removed, plus added, opportunity devices first', async () => {
        const { element } = await render({
            includeOpportunityAssets: true,
            removedAssetIds: ['o2'],
            addedAssetIds: ['a2']
        });
        expect(checkbox(element, 'o1').checked).toBe(true);
        expect(checkbox(element, 'o2').checked).toBe(false);
        expect(checkbox(element, 'a1').checked).toBe(false);
        expect(checkbox(element, 'a2').checked).toBe(true);
        const firstRowIds = [...element.shadowRoot.querySelectorAll('tbody input[type="checkbox"]')].map(
            (i) => i.dataset.id
        );
        expect(firstRowIds.slice(0, 3)).toEqual(['o1', 'o2', 'o3']);
        expect(element.shadowRoot.querySelector('[data-id="covered-text"]').textContent).toBe(
            '2 of 3 opportunity devices + 1 added = 3 covered'
        );
    });

    it('saves the differences against the group', async () => {
        const { element, closed } = await render({ includeOpportunityAssets: true });
        const o3 = checkbox(element, 'o3');
        o3.checked = false;
        o3.dispatchEvent(new CustomEvent('change'));
        const a1 = checkbox(element, 'a1');
        a1.checked = true;
        a1.dispatchEvent(new CustomEvent('change'));
        await flush();
        clickSave(element);
        expect(closed).toHaveBeenCalledWith({
            removedAssetIds: ['o3'],
            addedAssetIds: ['a1'],
            counts: { opportunity: 2, added: 1, total: 3 }
        });
    });

    it('with the devices not included, everything ticked is "added" and nothing is removed', async () => {
        const { element, closed } = await render({ includeOpportunityAssets: false, addedAssetIds: ['a2'] });
        expect(getEligibleAssets).toHaveBeenCalledWith(expect.objectContaining({ groups: [] }));
        clickSave(element);
        expect(closed).toHaveBeenCalledWith({
            removedAssetIds: [],
            addedAssetIds: ['a2'],
            counts: { opportunity: 0, added: 1, total: 1 }
        });
    });

    it('select all applies to the filtered rows only', async () => {
        const { element, closed } = await render({ includeOpportunityAssets: true });
        const clear = [...element.shadowRoot.querySelectorAll('button.link-button')].find(
            (b) => b.textContent === 'Clear selection'
        );
        clear.click();
        jest.useFakeTimers();
        try {
            const search = element.shadowRoot.querySelector('input[aria-label="Search all columns"]');
            search.value = 'pentax';
            search.dispatchEvent(new CustomEvent('input'));
            jest.runAllTimers(); // search debounce
        } finally {
            jest.useRealTimers();
        }
        await flush();
        expect(element.shadowRoot.querySelectorAll('tbody tr')).toHaveLength(1);
        const all = element.shadowRoot.querySelector('input[data-id="select-all"]');
        all.checked = true;
        all.dispatchEvent(new CustomEvent('change'));
        clickSave(element);
        expect(closed).toHaveBeenCalledWith(
            expect.objectContaining({ removedAssetIds: ['o1', 'o2', 'o3'], addedAssetIds: ['a1'] })
        );
    });

    it('shows the Apex error and disables save', async () => {
        getEligibleAssets.mockRejectedValue({ body: { message: 'Boom' } });
        const element = createElement('c-ims-asset-picker', { is: ImsAssetPicker });
        document.body.appendChild(element);
        await flush();
        await flush();
        expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toBe('Boom');
        const save = [...element.shadowRoot.querySelectorAll('lightning-button')].find((b) => b.label.startsWith('Save'));
        expect(save.disabled).toBe(true);
    });
});
