/**
 * @description ES Service Product Configurator: summary card on the child product's configurator screen,
 * with an Edit button that opens the Asset & PM Visits modal.
 */

import { LightningElement, api, wire } from 'lwc';
import { publish, subscribe, unsubscribe, MessageContext, APPLICATION_SCOPE } from 'lightning/messageService';
import CONFIGURATOR_CHANNEL from '@salesforce/messageChannel/lightning__productConfigurator_notification';
import getAttributeIds from '@salesforce/apex/EsServiceProductConfigController.getAttributeIds';
import getLineContext from '@salesforce/apex/EsServiceProductConfigController.getLineContext';
import EsServiceProductConfigModal from 'c/esServiceProductConfigModal';

// Quote line fields written into the configuration (each needs a context attribute + mapping).
const FIELDS = {
    ASSET: 'Asset__c',
    ASSET_NAME: 'AssetName__c',
    PFCL: 'PFCL__c',
    PFCL_NAME: 'PFCL_Name__c',
    VISITS: 'Requested_Number_of_PM_Visits__c'
};

// Fields shown in the summary card, in order (three per row). To add one, add an entry
// here; `key` is the property name in the line's values (see saveAsset / saveVisits and
// the Apex LineValues class).
const SUMMARY_FIELDS = [
    { key: 'assetName', label: 'Asset' },
    { key: 'pfclName', label: 'PFCL' },
    { key: 'requestedVisits', label: 'Requested PM Visits' }
];

const EMPTY = '—';

// TEMPORARY DEMO PRICING: when visits are saved, also set the line's UnitPrice directly
// through the configurator's message channel. Bypasses the pricing engine. Turn off
// (set to false) once the PFCL Pricing decision table is in place.
const DEMO_PRICING_ENABLED = true;
const DEMO_PRICE_BY_VISITS = { 1: 1000, 2: 2000, 3: 3000, 4: 4000 };

// Used only if the runtime lookup can't read context attributes in this org.
// Format: { 'Asset__c': '11n...', 'AssetName__c': '11n...', ... }
const FALLBACK_ATTRIBUTE_IDS = {};

export default class EsServiceProductConfigLauncher extends LightningElement {
    @api rootLineId;         // configuratorContext > transactionLineId
    @api transactionId;      // configuratorContext > transactionId (the Quote)
    @api productName;        // S01_DataManager > Product Details > Name
    @api productCode;        // S01_DataManager > Product Details > ProductCode
    // S01_DataManager > Product Details > Id. Changes as the rep moves between screens.
    @api
    get productId() {
        return this._productId;
    }
    set productId(value) {
        this._productId = value;
        if (!value) return;
        // The product shown when the configurator first opens is the bundle (root).
        if (!this.rootProductId && !this.currentKey) {
            this.rootProductId = value;
        }
        // Back on the bundle screen: forget the child line we were on.
        if (value === this.rootProductId) {
            this.currentKey = null;
        }
    }
    @api targetProductCodes; // optional, comma-separated, e.g. ES_CHAMBER_CLEAN
    cardTitle = 'Asset & PM Visits'; // fixed; not configurable

    currentKey;              // from the configurator's "navigate" messages
    rootProductId;           // the bundle's product, captured when the configurator opens
    _productId;
    sessionValues = {};      // values saved this session, per line
    recordValues = {};       // values loaded from saved QuoteLineItem records, per line
    loadingLines = {};       // lines whose saved values are being loaded
    attributeIds = { ...FALLBACK_ATTRIBUTE_IDS };
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
        this.loadAttributeIds();
    }

    disconnectedCallback() {
        unsubscribe(this.subscription);
        this.subscription = null;
    }

    async loadAttributeIds() {
        try {
            const ids = await getAttributeIds({ fieldNames: Object.values(FIELDS) });
            this.attributeIds = { ...this.attributeIds, ...(ids || {}) };
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('[ESPC] attribute Id lookup failed; using fallback', e);
        }
    }

    handleMessage(message) {
        if (message?.action === 'navigate' && Array.isArray(message.key) && message.key.length) {
            this.currentKey = [...message.key];
            if (this.key.length >= 2) {
                this.loadRecordValues(this.lineId);
            }
        }
    }

    get key() {
        return this.currentKey?.length ? this.currentKey : [this.rootLineId];
    }

    get lineId() {
        const k = this.key;
        return k[k.length - 1];
    }

    // Only on a child product (after the gear icon), never on the bundle screen,
    // optionally only for listed products. Works for any child added to the bundle.
    get showButton() {
        if (this.key.length < 2) {
            return false;
        }
        if (this.rootProductId && this._productId === this.rootProductId) {
            return false;
        }
        if (!this.targetProductCodes) {
            return true;
        }
        const targets = this.targetProductCodes.split(',').map((c) => c.trim());
        return targets.includes(this.productCode);
    }

    // ---------- Summary ----------

    get lineValues() {
        const lineId = this.lineId;
        return { ...(this.recordValues[lineId] || {}), ...(this.sessionValues[lineId] || {}) };
    }

    get summaryItems() {
        const values = this.lineValues;
        const loading = !!this.loadingLines[this.lineId];
        return SUMMARY_FIELDS.map((f) => {
            const raw = values[f.key];
            const empty = raw === null || raw === undefined || raw === '';
            return {
                key: f.key,
                label: f.label,
                value: loading && empty ? '…' : empty ? EMPTY : String(raw)
            };
        });
    }

    // Saved values for lines that already exist as records (loaded once per line).
    async loadRecordValues(lineId) {
        if (!lineId || this.recordValues[lineId] || this.loadingLines[lineId]) {
            return;
        }
        if (!lineId.startsWith('0QL')) {
            this.recordValues = { ...this.recordValues, [lineId]: {} }; // unsaved line: nothing stored yet
            return;
        }
        this.loadingLines = { ...this.loadingLines, [lineId]: true };
        try {
            const ctx = await getLineContext({ quoteId: this.transactionId, lineId });
            this.recordValues = { ...this.recordValues, [lineId]: ctx?.line || {} };
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('[ESPC] could not load saved values', e);
        } finally {
            const next = { ...this.loadingLines };
            delete next[lineId];
            this.loadingLines = next;
        }
    }

    // ---------- Modal ----------

    async handleClick() {
        const key = [...this.key];
        const lineId = this.lineId;
        await EsServiceProductConfigModal.open({
            size: 'small',
            label: 'Asset & PM Visit Details',
            productName: this.productName,
            productId: this.productId,
            quoteId: this.transactionId,
            lineId,
            cached: this.lineValues,
            saveAssetHandler: (values) => this.saveAsset(key, lineId, values),
            saveVisitsHandler: (values) => this.saveVisits(key, lineId, values)
        });
    }

    // Called by the modal; returns { error } when the update couldn't be sent.
    saveAsset(key, lineId, values) {
        const sent = this.send(key, [
            [FIELDS.ASSET, values.assetId || null],
            [FIELDS.ASSET_NAME, values.assetName || null],
            [FIELDS.PFCL, values.pfclId || null],
            [FIELDS.PFCL_NAME, values.pfclName || null]
        ]);
        if (!sent.error) {
            this.cache(lineId, {
                assetId: values.assetId,
                assetName: values.assetName,
                pfclId: values.pfclId,
                pfclName: values.pfclName
            });
        }
        return sent;
    }

    saveVisits(key, lineId, values) {
        const sent = this.send(key, [[FIELDS.VISITS, values.requestedVisits]]);
        if (!sent.error) {
            this.cache(lineId, { requestedVisits: values.requestedVisits });
            this.sendDemoPrice(key, values.requestedVisits);
        }
        return sent;
    }

    // DEMO ONLY: sets UnitPrice using the configurator's standard UnitPrice field.
    sendDemoPrice(key, visits) {
        if (!DEMO_PRICING_ENABLED) {
            return;
        }
        const price = DEMO_PRICE_BY_VISITS[visits];
        if (price === undefined) {
            return;
        }
        const payload = { action: 'valueChanged', data: [{ key, field: 'UnitPrice', value: price }] };
        // eslint-disable-next-line no-console
        console.log('[ESPC] demo price', JSON.stringify(payload));
        publish(this.messageContext, CONFIGURATOR_CHANNEL, payload);
    }

    // Publishes custom context field updates in the format the option card uses.
    send(key, pairs) {
        const missing = pairs.map(([f]) => f).filter((f) => !this.attributeIds[f]);
        if (missing.length) {
            return { error: `Missing context attribute Id for: ${missing.join(', ')}` };
        }
        const payload = {
            action: 'valueChanged',
            data: pairs.map(([fieldName, value]) => ({
                key,
                field: 'ContextFields',
                attributeId: this.attributeIds[fieldName],
                fieldName,
                value
            }))
        };
        // eslint-disable-next-line no-console
        console.log('[ESPC] publishing', JSON.stringify(payload));
        publish(this.messageContext, CONFIGURATOR_CHANNEL, payload);
        return {};
    }

    cache(lineId, values) {
        this.sessionValues = {
            ...this.sessionValues,
            [lineId]: { ...(this.sessionValues[lineId] || {}), ...values }
        };
    }
}