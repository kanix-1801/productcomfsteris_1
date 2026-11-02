/**
 * @description ES Service Product Configurator: "Assets Selected" card on the bundle screen.
 * The selection applies to every service product in the bundle and is stored on the
 * bundle line as Selected_Assets__c (a JSON list of Asset Ids) through the configuration.
 */
import { LightningElement, api, wire } from 'lwc';
import { publish, subscribe, unsubscribe, MessageContext, APPLICATION_SCOPE } from 'lightning/messageService';
import CONFIGURATOR_CHANNEL from '@salesforce/messageChannel/lightning__productConfigurator_notification';
import getAttributeIds from '@salesforce/apex/EsServiceProductConfigController.getAttributeIds';
import getSavedSelection from '@salesforce/apex/EsServiceAssetSelectionController.getSavedSelection';
import getAssetsByIds from '@salesforce/apex/EsServiceAssetSelectionController.getAssetsByIds';
import getLineProductId from '@salesforce/apex/EsServiceAssetSelectionController.getLineProductId';
import AssetPicker from 'c/esServiceAssetPicker';

const SELECTION_FIELD = 'Selected_Assets__c';
const CARD_TITLE = 'Assets Selected';
const BUNDLE_NAME = 'ES Service Agreement';

export default class EsServiceAssetLauncher extends LightningElement {
    @api rootLineId;     // configuratorContext > transactionLineId
    @api transactionId;  // configuratorContext > transactionId (the Quote)
    cardTitle = CARD_TITLE;

    // configuratorContext > currentTransactionLineId: the line the configurator opened on.
    @api currentLineId;

    // S01_DataManager > Product Details > Id. Used to tell the bundle screen from a child screen.
    @api
    get productId() {
        return this._productId;
    }
    set productId(value) {
        this._productId = value;
        if (!value) {
            return;
        }
        // Without a saved bundle line to look up, the first product is the bundle, but only
        // when the configurator opened on the bundle itself.
        if (!this.rootProductId && !this.currentKey && this.openedOnBundle) {
            this.rootProductId = value;
        }
        if (value === this.rootProductId) {
            this.currentKey = null;
        }
    }

    _productId;
    rootProductId; // the bundle's product
    currentKey;    // from the configurator's navigate messages

    get openedOnBundle() {
        return !this.currentLineId || this.currentLineId === this.rootLineId;
    }

    async loadRootProduct() {
        if (!this.rootLineId || !this.rootLineId.startsWith('0QL')) return;
        try {
            const id = await getLineProductId({ lineId: this.rootLineId });
            if (id) {
                this.rootProductId = id;
                if (this._productId === id) {
                    this.currentKey = null;
                }
            }
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('[ESPC] bundle product lookup failed', e);
        }
    }

    selectedIds = [];
    selectedRows = [];
    loading = false;
    error;
    attributeId;
    subscription;

    @wire(MessageContext) messageContext;

    connectedCallback() {
        if (!this.subscription) {
            this.subscription = subscribe(
                this.messageContext,
                CONFIGURATOR_CHANNEL,
                (message) => this.handleMessage(message),
                { scope: APPLICATION_SCOPE }
            );
        }
        this.loadAttributeId();
        this.loadSavedSelection();
        this.loadRootProduct();
    }

    disconnectedCallback() {
        unsubscribe(this.subscription);
        this.subscription = null;
    }

    handleMessage(message) {
        if (message?.action === 'navigate' && Array.isArray(message.key) && message.key.length) {
            this.currentKey = [...message.key];
        }
    }

    // Only on the bundle screen, never on a child product's screen.
    get showCard() {
        if (this.currentKey) {
            return this.currentKey.length === 1;
        }
        if (this.rootProductId && this._productId) {
            return this._productId === this.rootProductId;
        }
        return this.openedOnBundle;
    }

    async loadAttributeId() {
        try {
            const ids = await getAttributeIds({ fieldNames: [SELECTION_FIELD] });
            this.attributeId = ids?.[SELECTION_FIELD];
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('[ESPC] attribute Id lookup failed', e);
        }
    }

    async loadSavedSelection() {
        if (!this.rootLineId || !this.rootLineId.startsWith('0QL')) {
            return; // unsaved bundle line
        }
        this.loading = true;
        try {
            const raw = await getSavedSelection({ lineId: this.rootLineId });
            const ids = this.parseIds(raw);
            if (ids.length) {
                this.selectedIds = ids;
                this.selectedRows = await getAssetsByIds({ assetIds: ids });
            }
        } catch (e) {
            this.error = e?.body?.message || e?.message || 'Could not load the saved assets.';
        } finally {
            this.loading = false;
        }
    }

    parseIds(raw) {
        if (!raw) return [];
        try {
            const value = JSON.parse(raw);
            return Array.isArray(value) ? value.filter(Boolean) : [];
        } catch (e) {
            return [];
        }
    }

    // ---------- Card ----------

    get count() {
        return this.selectedIds.length;
    }

    get hasAssets() {
        return this.selectedRows.length > 0;
    }

    get previewRows() {
        return this.selectedRows.map((r) => ({ ...r, key: r.id }));
    }

    async handleEdit() {
        this.error = null;
        const result = await AssetPicker.open({
            size: 'large',
            label: 'Choose Assets',
            quoteId: this.transactionId,
            bundleName: BUNDLE_NAME,
            selectedIds: [...this.selectedIds]
        });
        if (!result) return; // cancelled

        if (!this.attributeId) {
            this.error = `Missing context attribute Id for ${SELECTION_FIELD}. Check the context definition.`;
            return;
        }
        const ids = result.ids || [];
        const payload = {
            action: 'valueChanged',
            data: [
                {
                    key: [this.rootLineId],
                    field: 'ContextFields',
                    attributeId: this.attributeId,
                    fieldName: SELECTION_FIELD,
                    value: ids.length ? JSON.stringify(ids) : null
                }
            ]
        };
        // eslint-disable-next-line no-console
        console.log('[ESPC] assets selected', ids.length, JSON.stringify(payload).slice(0, 500));
        publish(this.messageContext, CONFIGURATOR_CHANNEL, payload);

        this.selectedIds = ids;
        const sorted = [...(result.rows || [])].sort((a, b) =>
            String(a.serialNumber || '').localeCompare(String(b.serialNumber || ''), undefined, { numeric: true })
        );
        this.selectedRows = sorted;
    }
}