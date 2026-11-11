import { LightningElement, api, wire } from 'lwc';
import { getFieldDisplayValue, getFieldValue, getRecord } from 'lightning/uiRecordApi';
import getHeaderView from '@salesforce/apex/LSAccountHeaderController.getHeaderView';
import NAME_FIELD from '@salesforce/schema/Account.Name';
import ACCOUNT_NUMBER_FIELD from '@salesforce/schema/Account.AccountNumber';
import WEBSITE_FIELD from '@salesforce/schema/Account.Website';
import CUSTOMER_CLASS_FIELD from '@salesforce/schema/Account.CustomerClassCode__c';
import PARENT_ID_FIELD from '@salesforce/schema/Account.ParentId';
import PARENT_NAME_FIELD from '@salesforce/schema/Account.Parent.Name';
import GPO_NAME_FIELD from '@salesforce/schema/Account.GPO_Account__r.Name';
import BILLING_STREET_FIELD from '@salesforce/schema/Account.BillingStreet';
import BILLING_CITY_FIELD from '@salesforce/schema/Account.BillingCity';
import BILLING_STATE_FIELD from '@salesforce/schema/Account.BillingState';
import BILLING_POSTAL_FIELD from '@salesforce/schema/Account.BillingPostalCode';
import BILLING_COUNTRY_FIELD from '@salesforce/schema/Account.BillingCountryCode';

const ACCESS_BASE = 'Base';
const FIELDS = [
    NAME_FIELD,
    ACCOUNT_NUMBER_FIELD,
    WEBSITE_FIELD,
    CUSTOMER_CLASS_FIELD,
    PARENT_ID_FIELD,
    PARENT_NAME_FIELD,
    GPO_NAME_FIELD,
    BILLING_STREET_FIELD,
    BILLING_CITY_FIELD,
    BILLING_STATE_FIELD,
    BILLING_POSTAL_FIELD,
    BILLING_COUNTRY_FIELD
];

/**
 * @author PWC Developer
 * @date 2026/11/06
 *
 * @description
 * GCL-100 - Left account card for the LS Customer 360 record page.
 * A user who is not the owner and not on the Account Team sees five fields only.
 * The owner and Account Team members keep the full card.
 */
export default class LsCustomer360LeftCard extends LightningElement {
    @api recordId;

    accessLoaded = false;
    isFull = false;
    accountResult;

    @wire(getHeaderView, { accountId: '$recordId' })
    wiredAccess({ data, error }) {
        if (!this.recordId) {
            this.isFull = true;
            this.accessLoaded = true;
            return;
        }

        if (data) {
            this.isFull = data.accessLevel !== ACCESS_BASE;
            this.accessLoaded = true;
        } else if (error) {
            this.isFull = true;
            this.accessLoaded = true;
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredAccount(result) {
        this.accountResult = result;
    }

    get isLoading() {
        if (this.recordId && !this.accessLoaded) {
            return true;
        }
        return Boolean(this.recordId) && !this.accountResult?.data && !this.accountResult?.error;
    }

    get errorMessage() {
        return this.accountResult?.error?.body?.message || '';
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
        const website = (this.website || '').trim();
        if (!website || /^javascript:/i.test(website)) {
            return null;
        }
        return /^https?:\/\//i.test(website) ? website : `https://${website}`;
    }

    get billingCountry() {
        return this.displayValue(BILLING_COUNTRY_FIELD);
    }

    get billingStreet() {
        return this.value(BILLING_STREET_FIELD);
    }

    get billingCity() {
        return this.value(BILLING_CITY_FIELD);
    }

    get billingState() {
        return this.displayValue(BILLING_STATE_FIELD);
    }

    get billingPostalCode() {
        return this.value(BILLING_POSTAL_FIELD);
    }

    value(field) {
        return getFieldValue(this.accountResult?.data, field) || '';
    }

    displayValue(field) {
        return getFieldDisplayValue(this.accountResult?.data, field) || this.value(field);
    }
}