import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { publish, subscribe, unsubscribe, MessageContext, APPLICATION_SCOPE } from 'lightning/messageService';
import CONFIGURATOR_CHANNEL from '@salesforce/messageChannel/lightning__productConfigurator_notification';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import PocModal from 'c/configPocModal';

// Custom context field format, captured from the standard option card's own message:
// { field: 'ContextFields', attributeId: <context attribute Id>, fieldName: <field>, value }
// NOTE: the attribute Id is org-specific (sandbox and prod will differ).
const ASSET_FIELD_NAME = 'Asset_Name__c';
const ASSET_ATTRIBUTE_ID = '11nOu00000ODPpBIAX';
const QTY_CONTEXT_FIELD = 'Quantity';

// Record fields, used only to pre-fill from the saved QuoteLineItem (not available for unsaved lines).
const RECORD_FIELDS = ['QuoteLineItem.Quantity', 'QuoteLineItem.Asset_Name__c'];

export default class ConfigPocLauncher extends LightningElement {
    // Root line: map to configuratorContext > transactionLineId
    @api lineId;
    // No longer used (the flow value doesn't change on navigation). Kept so the
    // existing flow mapping doesn't block the deploy.
    @api currentLineId;
    @api buttonLabel = 'Edit custom values';
    // Optional: only show the button for this product code (e.g. ES_CHAMBER_CLEAN).
    @api targetProductCode;
    // Optional: map to the Data Manager's Product Details > ProductCode.
    @api currentProductCode;

    // Outputs for the flow (e.g. a Display Text on the option's screen).
    @api displayAssetName;
    @api isTargetLine;
    lastOutputs;

    // Path to the line being viewed, taken from the configurator's "navigate" messages,
    // e.g. [rootLineId, optionLineId] after clicking an option's gear icon.
    currentKey;

    // Values sent this session, per line.
    sentValues = {};

    subscription;

    @wire(MessageContext) messageContext;

    @wire(getRecord, { recordId: '$targetLineId', fields: RECORD_FIELDS })
    line;

    connectedCallback() {
        if (!this.subscription) {
            this.subscription = subscribe(
                this.messageContext,
                CONFIGURATOR_CHANNEL,
                (message) => this.handleMessage(message),
                { scope: APPLICATION_SCOPE }
            );
        }
    }

    disconnectedCallback() {
        unsubscribe(this.subscription);
        this.subscription = null;
    }

    handleMessage(message) {
        // eslint-disable-next-line no-console
        console.log('[POC] heard', JSON.stringify(message));
        if (message?.action === 'navigate' && Array.isArray(message.key) && message.key.length) {
            this.currentKey = [...message.key];
            // eslint-disable-next-line no-console
            console.log('[POC] current line key', JSON.stringify(this.currentKey));
            this.syncOutputs();
        }
    }

    // Push display values to the flow whenever the current line or its values change.
    renderedCallback() {
        this.syncOutputs();
    }

    syncOutputs() {
        const onTarget = this.showButton;
        const v = this.sentValues[this.targetLineId] || {};
        const assetName = onTarget ? v.assetName ?? '' : '';
        const snapshot = JSON.stringify([onTarget, assetName]);
        if (snapshot === this.lastOutputs) return;
        this.lastOutputs = snapshot;
        this.dispatchEvent(new FlowAttributeChangeEvent('isTargetLine', onTarget));
        this.dispatchEvent(new FlowAttributeChangeEvent('displayAssetName', assetName));
    }

    get key() {
        return this.currentKey?.length ? this.currentKey : [this.lineId];
    }

    get targetLineId() {
        const k = this.key;
        return k[k.length - 1];
    }

    // Show only when drilled into an option (and, if configured, only for one product).
    get showButton() {
        if (this.key.length < 2) return false;
        if (this.targetProductCode) return this.currentProductCode === this.targetProductCode;
        return true;
    }

    get savedValues() {
        const f = this.line?.data?.fields;
        return { quantity: f?.Quantity?.value, assetName: f?.Asset_Name__c?.value };
    }

    async handleClick() {
        const key = [...this.key];
        const lineKey = this.targetLineId;
        const start = { ...this.savedValues, ...(this.sentValues[lineKey] || {}) };

        const result = await PocModal.open({
            size: 'small',
            label: this.buttonLabel,
            quantity: start.quantity,
            assetName: start.assetName
        });
        if (!result || result.cancelled) return;

        const data = [];
        const quantity = Number(result.quantity);
        if (result.quantity !== '' && result.quantity != null && quantity !== Number(start.quantity)) {
            data.push({ key, field: QTY_CONTEXT_FIELD, value: quantity });
        }
        if ((result.assetName ?? '') !== (start.assetName ?? '')) {
            data.push({
                key,
                field: 'ContextFields',
                attributeId: ASSET_ATTRIBUTE_ID,
                fieldName: ASSET_FIELD_NAME,
                value: result.assetName
            });
        }
        if (!data.length) return;

        // One message per field, so a problem with one can't block the other.
        data.forEach((change) => {
            const payload = { action: 'valueChanged', data: [change] };
            // eslint-disable-next-line no-console
            console.log('[POC] publishing', JSON.stringify(payload));
            publish(this.messageContext, CONFIGURATOR_CHANNEL, payload);
        });

        this.sentValues = {
            ...this.sentValues,
            [lineKey]: { ...start, quantity: result.quantity, assetName: result.assetName }
        };
        this.syncOutputs();
    }
}