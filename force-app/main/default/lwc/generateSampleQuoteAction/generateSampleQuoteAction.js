import { LightningElement, api, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecord, getRecordNotifyChange, getFieldValue } from 'lightning/uiRecordApi';
import { RefreshEvent } from 'lightning/refresh';
import GenerateQuote from 'c/generateQuote';
import SAMPLE_OPPORTUNITY from '@salesforce/schema/Sample__c.RelatedOpportunity__c';

export default class GenerateSampleQuoteAction extends LightningElement {
    @api recordId;

    quoteComponent = GenerateQuote;
    sampleRecord;

    @wire(getRecord, { recordId: '$recordId', fields: [SAMPLE_OPPORTUNITY] })
    wiredSampleRecord(result) {
        this.sampleRecord = result;
    }

    get opportunityRecordId() {
        return getFieldValue(this.sampleRecord?.data, SAMPLE_OPPORTUNITY);
    }

    get isReady() {
        return !this.sampleRecord?.loading && this.opportunityRecordId;
    }

    get hasError() {
        return this.sampleRecord?.error;
    }

    handleCloseQuickAction(event) {
        const shouldRefresh = event.detail?.refresh !== false;

        if (shouldRefresh && this.recordId) {
            getRecordNotifyChange([{ recordId: this.recordId }]);

            if (this.opportunityRecordId) {
                getRecordNotifyChange([{ recordId: this.opportunityRecordId }]);
            }

            this.dispatchEvent(new RefreshEvent());
        }

        window.setTimeout(() => {
            this.dispatchEvent(new CloseActionScreenEvent());
        }, 0);
    }
}