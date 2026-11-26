import { createElement } from 'lwc';
import ImsInventoryGroupPreview from 'c/imsInventoryGroupPreview';
import getGroupAssets from '@salesforce/apex/ImsAssetAssignmentController.getGroupAssets';

jest.mock(
    '@salesforce/apex/ImsAssetAssignmentController.getGroupAssets',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const page = (start, n) => Array.from({ length: n }, (_, i) => ({ id: `a${start + i}`, serialNumber: `SN-${start + i}` }));
// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('c-ims-inventory-group-preview', () => {
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
    });

    it('loads the first page, then more on scroll, and stops at a short page', async () => {
        getGroupAssets.mockResolvedValueOnce(page(0, 50)).mockResolvedValueOnce(page(50, 10));
        const element = createElement('c-ims-inventory-group-preview', { is: ImsInventoryGroupPreview });
        element.opportunityId = '006000000000001';
        element.groupName = 'Main Campus';
        document.body.appendChild(element);
        await flush();

        const table = element.shadowRoot.querySelector('lightning-datatable');
        expect(getGroupAssets).toHaveBeenCalledWith({ opportunityId: '006000000000001', groupName: 'Main Campus', offset: 0 });
        expect(table.data).toHaveLength(50);
        expect(table.enableInfiniteLoading).toBe(true);

        table.dispatchEvent(new CustomEvent('loadmore'));
        await flush();
        expect(getGroupAssets).toHaveBeenLastCalledWith({ opportunityId: '006000000000001', groupName: 'Main Campus', offset: 50 });
        expect(table.data).toHaveLength(60);
        expect(table.enableInfiniteLoading).toBe(false);
    });

    it('shows a placeholder until a group is chosen', async () => {
        const element = createElement('c-ims-inventory-group-preview', { is: ImsInventoryGroupPreview });
        document.body.appendChild(element);
        await flush();
        expect(getGroupAssets).not.toHaveBeenCalled();
        expect(element.shadowRoot.querySelector('.preview-placeholder')).not.toBeNull();
    });
});
