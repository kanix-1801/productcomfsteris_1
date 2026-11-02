import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';

import LAST_REFRESHED_DATE from '@salesforce/schema/Opportunity.Last_Refreshed_Date_Time_From_Oracle__c';
import WARNING_MESSAGE from '@salesforce/label/c.Warning_Message_For_Oracle_Pricing';

const FIELDS = [LAST_REFRESHED_DATE];

export default class PricingRefreshWarningBanner extends LightningElement {
    @api recordId;

    @wire(getRecord, {
        recordId: '$recordId',
        fields: FIELDS
    })
    opportunity;

    get showBanner() {
        const lastRefreshed =
            this.opportunity.data?.fields.Last_Refreshed_Date_Time_From_Oracle__c?.value;

        if (!lastRefreshed) {
            return false;
        }

        const refreshDate = new Date(lastRefreshed);
        const today = new Date();

        const diffDays = (today - refreshDate) / (1000 * 60 * 60 * 24);

        return diffDays > 30;
    }

    get warningMessage() {
        return WARNING_MESSAGE;
    }
}