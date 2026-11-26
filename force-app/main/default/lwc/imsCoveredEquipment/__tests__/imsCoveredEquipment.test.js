import { createElement } from 'lwc';
import ImsCoveredEquipment from 'c/imsCoveredEquipment';
import { publish, subscribe } from 'lightning/messageService';
import LightningModal from 'lightning/modal';
import getAttributeIds from '@salesforce/apex/EsServiceProductConfigController.getAttributeIds';
import getAssignmentContext from '@salesforce/apex/ImsAssetAssignmentController.getAssignmentContext';

jest.mock(
    '@salesforce/apex/EsServiceProductConfigController.getAttributeIds',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/ImsAssetAssignmentController.getAssignmentContext',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/ImsAssetAssignmentController.getEligibleAssets',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/ImsAssetAssignmentController.getGroupAssets',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/messageChannel/lightning__productConfigurator_notification',
    () => ({ default: 'configuratorChannel' }),
    { virtual: true }
);

const ROOT = '0QL000000000001AAA';
const CHILD = '0QL000000000002AAA';
const CONTEXT = {
    quoteId: '0Q0000000000001',
    opportunityId: '006000000000001',
    opportunityName: '9382 Cleveland Clinic',
    opportunityDeviceCount: 1284,
    groups: [
        { name: 'Main Campus', deviceCount: 1200 },
        { name: 'East Wing', deviceCount: 84 }
    ],
    savedSelection: null
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
const count = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`).textContent;
const fmt = (n) => new Intl.NumberFormat().format(n);

async function render(props = {}, context = CONTEXT) {
    getAttributeIds.mockResolvedValue({ ImsAssetSelection__c: 'attr-1' });
    getAssignmentContext.mockResolvedValue(context);
    const element = createElement('c-ims-covered-equipment', { is: ImsCoveredEquipment });
    Object.assign(element, {
        transactionId: '0Q0000000000001',
        rootTransactionLineId: ROOT,
        currentProductName: 'SERVICE AGREEMENT',
        allowedProducts: 'FIXED FEE SERVICE AGREEMENT,SERVICE AGREEMENT',
        ...props
    });
    document.body.appendChild(element);
    await flush();
    await flush();
    return element;
}

const lastPublishedValue = () => JSON.parse(publish.mock.calls[publish.mock.calls.length - 1][2].data[0].value);

describe('c-ims-covered-equipment', () => {
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
    });

    it('shows the default: every group included', async () => {
        const element = await render();
        expect(getAssignmentContext).toHaveBeenCalledWith({ quoteId: '0Q0000000000001', lineId: ROOT });
        expect(element.shadowRoot.querySelector('.ce-sub').textContent).toBe(
            `Opportunity 9382 Cleveland Clinic · ${fmt(1284)} devices on the list`
        );
        expect(count(element, 'opportunity-count')).toBe(fmt(1284));
        expect(count(element, 'added-count')).toBe('0');
        expect(count(element, 'total-count')).toBe(fmt(1284));
    });

    it('restores the selection saved on the line', async () => {
        const saved = {
            version: 1,
            opportunityId: CONTEXT.opportunityId,
            includeOpportunityAssets: true,
            groups: ['Main Campus'],
            removedAssetIds: ['02i000000000001'],
            addedAssetIds: ['02i000000000009', '02i000000000008']
        };
        const element = await render({}, { ...CONTEXT, savedSelection: JSON.stringify(saved) });
        expect(count(element, 'opportunity-count')).toBe(fmt(1199));
        expect(count(element, 'added-count')).toBe('2');
        expect(count(element, 'total-count')).toBe(fmt(1201));
    });

    it('is hidden for products that are not allowed', async () => {
        const element = await render({ currentProductName: 'SOMETHING ELSE' });
        expect(element.shadowRoot.querySelector('.ce-card')).toBeNull();
    });

    it('the toggle writes the selection into the configuration for the line on screen', async () => {
        const element = await render();
        const toggle = element.shadowRoot.querySelector('[data-id="include-toggle"]');
        toggle.checked = false;
        toggle.dispatchEvent(new CustomEvent('change'));
        await flush();

        expect(publish).toHaveBeenCalledTimes(1);
        const message = publish.mock.calls[0][2];
        expect(message.action).toBe('valueChanged');
        expect(message.data[0]).toMatchObject({
            key: [ROOT],
            field: 'ContextFields',
            attributeId: 'attr-1',
            fieldName: 'ImsAssetSelection__c'
        });
        expect(lastPublishedValue()).toMatchObject({
            includeOpportunityAssets: false,
            groups: ['Main Campus', 'East Wing'],
            counts: { opportunity: 0, added: 0, total: 0 }
        });
        expect(count(element, 'total-count')).toBe('0');
        expect(element.shadowRoot.querySelector('.slds-badge')).not.toBeNull();
    });

    it('follows the configurator to a child line', async () => {
        const element = await render();
        const onMessage = subscribe.mock.calls[0][2];
        getAssignmentContext.mockResolvedValue({ ...CONTEXT, savedSelection: null });
        onMessage({ action: 'navigate', key: [ROOT, CHILD] });
        await flush();
        expect(getAssignmentContext).toHaveBeenLastCalledWith({ quoteId: '0Q0000000000001', lineId: CHILD });

        const toggle = element.shadowRoot.querySelector('[data-id="include-toggle"]');
        toggle.checked = false;
        toggle.dispatchEvent(new CustomEvent('change'));
        expect(publish.mock.calls[0][2].data[0].key).toEqual([ROOT, CHILD]);
    });

    it('Manage runs both steps and stores what they return', async () => {
        LightningModal.open
            .mockResolvedValueOnce({ groups: ['East Wing'], includeOpportunityAssets: true })
            .mockResolvedValueOnce({ removedAssetIds: ['02i000000000001'], addedAssetIds: ['02i000000000009'] });
        const element = await render();
        element.shadowRoot.querySelector('[data-id="manage"]').click();
        await flush();
        await flush();

        expect(LightningModal.open).toHaveBeenCalledTimes(2);
        expect(LightningModal.open.mock.calls[1][0]).toMatchObject({
            groups: ['East Wing'],
            includeOpportunityAssets: true,
            quoteId: '0Q0000000000001'
        });
        expect(lastPublishedValue()).toMatchObject({
            groups: ['East Wing'],
            removedAssetIds: ['02i000000000001'],
            addedAssetIds: ['02i000000000009'],
            counts: { opportunity: 83, added: 1, total: 84 }
        });
    });

    it('Cancel in step 1 changes nothing', async () => {
        LightningModal.open.mockResolvedValueOnce(null);
        const element = await render();
        element.shadowRoot.querySelector('[data-id="manage"]').click();
        await flush();
        expect(LightningModal.open).toHaveBeenCalledTimes(1);
        expect(publish).not.toHaveBeenCalled();
    });

    it('without the context attribute it shows an error instead of publishing', async () => {
        getAttributeIds.mockResolvedValue({});
        getAssignmentContext.mockResolvedValue(CONTEXT);
        const element = createElement('c-ims-covered-equipment', { is: ImsCoveredEquipment });
        Object.assign(element, { transactionId: '0Q0000000000001', rootTransactionLineId: ROOT });
        document.body.appendChild(element);
        await flush();
        await flush();
        const toggle = element.shadowRoot.querySelector('[data-id="include-toggle"]');
        toggle.checked = false;
        toggle.dispatchEvent(new CustomEvent('change'));
        await flush();
        expect(publish).not.toHaveBeenCalled();
        expect(element.shadowRoot.querySelector('.ce-error').textContent).toContain('Missing context attribute Id');
    });
});
