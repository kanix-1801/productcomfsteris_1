import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import HAS_SAMPLE_ACTIVITY
    from '@salesforce/schema/Opportunity.HasSampleActivity__c';

import SAMPLE_ACTIVITY_BANNER_MESSAGE
    from '@salesforce/label/c.Sample_Activity_Banner_Message';

const FIELDS = [
    HAS_SAMPLE_ACTIVITY
];

export default class OpportunitySampleActivityBanner extends LightningElement {
    @api recordId;

    opportunity;
    isDismissed = false;

    @wire(getRecord, {
        recordId: '$recordId',
        fields: FIELDS
    })
    wiredOpportunity({ data, error }) {
        if (data) {
            this.opportunity = data;

            /*
             * Important:
             * A newly loaded/reopened record should display
             * the banner again when HasSampleActivity__c = true.
             */
            this.isDismissed = false;
        } else if (error) {
            this.opportunity = null;

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error loading banner',
                    message: this.reduceErrors(error),
                    variant: 'error'
                })
            );
        }
    }

    get isVisible() {
        if (!this.opportunity) {
            return false;
        }

        const hasSampleActivity = getFieldValue(
            this.opportunity,
            HAS_SAMPLE_ACTIVITY
        );

        return hasSampleActivity === true &&
            this.isDismissed === false;
    }

    get bannerMessage() {
        return SAMPLE_ACTIVITY_BANNER_MESSAGE;
    }

    get assistiveText() {
        return this.bannerMessage;
    }

    handleDismiss() {
        this.isDismissed = true;
    }

    reduceErrors(error) {
        if (!error) {
            return 'Unknown error';
        }

        if (Array.isArray(error.body)) {
            return error.body
                .map((item) => item.message)
                .join(', ');
        }

        if (typeof error.body?.message === 'string') {
            return error.body.message;
        }

        if (typeof error.message === 'string') {
            return error.message;
        }

        return 'Unknown error';
    }
}