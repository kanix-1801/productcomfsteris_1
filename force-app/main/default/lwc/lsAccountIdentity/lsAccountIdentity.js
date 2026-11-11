import { LightningElement, api, wire } from 'lwc';
import { getFieldDisplayValue, getFieldValue, getRecord } from 'lightning/uiRecordApi';
import NAME_FIELD from '@salesforce/schema/Account.Name';
import ACCOUNT_NUMBER_FIELD from '@salesforce/schema/Account.AccountNumber';
import WEBSITE_FIELD from '@salesforce/schema/Account.Website';
import CUSTOMER_CLASS_FIELD from '@salesforce/schema/Account.CustomerClassCode__c';
import PARENT_ID_FIELD from '@salesforce/schema/Account.ParentId';
import PARENT_NAME_FIELD from '@salesforce/schema/Account.Parent.Name';
import GPO_NAME_FIELD from '@salesforce/schema/Account.GPO_Account__r.Name';

const FIELDS = [
    NAME_FIELD,
    ACCOUNT_NUMBER_FIELD,
    WEBSITE_FIELD,
    CUSTOMER_CLASS_FIELD,
    PARENT_ID_FIELD,
    PARENT_NAME_FIELD,
    GPO_NAME_FIELD
];

/**
 * @author PWC Developer
 * @date 2026/11/05
 *
 * @description
 * GCL-100 - Left pane of the Life Sciences Customer 360 page.
 * The same card is shown for Full and Base.
 */
export default class LsAccountIdentity extends LightningElement {
    @api recordId;

    accountResult;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredAccount(result) {
        this.accountResult = result;
    }

    get isLoading() {
        return Boolean(this.recordId) && !this.accountResult?.data && !this.accountResult?.error;
    }

    get hasAccount() {
        return Boolean(this.accountResult?.data);
    }

    get errorMessage() {
        return this.accountResult?.error?.body?.message;
    }

    get accountName() {
        return this.value(NAME_FIELD);
    }

    get customerNumber() {
        return this.value(ACCOUNT_NUMBER_FIELD);
    }

    get gpoAffiliation() {
        return this.value(GPO_NAME_FIELD);
    }

    get customerClass() {
        return this.displayValue(CUSTOMER_CLASS_FIELD);
    }

    get parentAccountName() {
        return this.value(PARENT_NAME_FIELD);
    }

    get hasParentAccount() {
        return Boolean(this.value(PARENT_ID_FIELD));
    }

    get parentAccountUrl() {
        const parentId = this.value(PARENT_ID_FIELD);
        return parentId ? `/lightning/r/Account/${parentId}/view` : null;
    }

    get website() {
        return this.value(WEBSITE_FIELD);
    }

    get hasWebsite() {
        return Boolean(this.safeWebsiteUrl);
    }

    get safeWebsiteUrl() {
        const website = this.website.trim();
        if (!website || /^javascript:/i.test(website)) {
            return null;
        }
        return /^https?:\/\//i.test(website) ? website : `https://${website}`;
    }

    value(field) {
        return getFieldValue(this.accountResult?.data, field) || '';
    }

    displayValue(field) {
        return getFieldDisplayValue(this.accountResult?.data, field) || this.value(field);
    }
}