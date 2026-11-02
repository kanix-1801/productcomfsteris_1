import { LightningElement, api, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecord, getRecordNotifyChange, getFieldValue } from 'lightning/uiRecordApi';
import { RefreshEvent } from 'lightning/refresh';
import GenerateQuote from 'c/generateQuote';
import TRAIL_OPPORTUNITY from '@salesforce/schema/Trial__c.Opportunity__c';

export default class GenerateTrialQuoteAction extends LightningElement {
    @api recordId;

    quoteComponent = GenerateQuote;
    trailRecord;

    @wire(getRecord, { recordId: '$recordId', fields: [TRAIL_OPPORTUNITY] })
    wiredTrailRecord(result) {
        this.trailRecord = result;
    }

    get opportunityRecordId() {
        return getFieldValue(this.trailRecord?.data, TRAIL_OPPORTUNITY);
    }

    get isReady() {
        return !this.trailRecord?.loading && this.opportunityRecordId;
    }

    get hasError() {
        return this.trailRecord?.error;
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