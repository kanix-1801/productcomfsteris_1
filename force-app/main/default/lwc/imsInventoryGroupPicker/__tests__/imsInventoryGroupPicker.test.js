import { createElement } from 'lwc';
import ImsInventoryGroupPicker from 'c/imsInventoryGroupPicker';

jest.mock(
    '@salesforce/apex/ImsAssetAssignmentController.getGroupAssets',
    () => ({ default: jest.fn().mockResolvedValue([]) }),
    { virtual: true }
);

const GROUPS = [
    { name: 'Main Campus', deviceCount: 1200, uploadedOn: '2026-11-01T10:00:00.000Z' },
    { name: 'East Wing', deviceCount: 84, uploadedOn: '2026-11-02T10:00:00.000Z' }
];

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render(props = {}) {
    const element = createElement('c-ims-inventory-group-picker', { is: ImsInventoryGroupPicker });
    Object.assign(element, { opportunityId: '006000000000001', opportunityName: 'Cleveland', groups: GROUPS, ...props });
    const closed = jest.fn();
    element.addEventListener('close', (e) => closed(e.detail));
    document.body.appendChild(element);
    await flush();
    return { element, closed };
}

const groupBox = (element, name) => element.shadowRoot.querySelector(`input[data-name="${name}"]`);
const footerButton = (element, label) =>
    [...element.shadowRoot.querySelectorAll('lightning-button')].find((b) => b.label === label);

describe('c-ims-inventory-group-picker', () => {
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    });

    it('checks every group when nothing was chosen before', async () => {
        const { element, closed } = await render();
        expect(groupBox(element, 'Main Campus').checked).toBe(true);
        expect(groupBox(element, 'East Wing').checked).toBe(true);
        footerButton(element, 'Next - Asset Assignment').click();
        expect(closed).toHaveBeenCalledWith({ groups: ['Main Campus', 'East Wing'], includeOpportunityAssets: true });
    });

    it('keeps the groups chosen before and returns changes', async () => {
        const { element, closed } = await render({ selectedGroups: ['East Wing'] });
        expect(groupBox(element, 'Main Campus').checked).toBe(false);
        const box = groupBox(element, 'Main Campus');
        box.checked = true;
        box.dispatchEvent(new CustomEvent('change'));
        await flush();
        footerButton(element, 'Next - Asset Assignment').click();
        expect(closed).toHaveBeenCalledWith({ groups: ['Main Campus', 'East Wing'], includeOpportunityAssets: true });
    });

    it('cannot go next with no group while the devices are included', async () => {
        const { element } = await render({ selectedGroups: ['East Wing'] });
        const box = groupBox(element, 'East Wing');
        box.checked = false;
        box.dispatchEvent(new CustomEvent('change'));
        await flush();
        expect(footerButton(element, 'Next - Asset Assignment').disabled).toBe(true);
    });

    it('returns null on Cancel', async () => {
        const { element, closed } = await render();
        footerButton(element, 'Cancel').click();
        expect(closed).toHaveBeenCalledWith(null);
    });

    it('preview shows the chosen group', async () => {
        const { element } = await render();
        element.shadowRoot.querySelector('button[data-name="East Wing"]').click();
        await flush();
        const preview = element.shadowRoot.querySelector('c-ims-inventory-group-preview');
        expect(preview.groupName).toBe('East Wing');
        expect(preview.deviceCount).toBe(84);
    });
});
