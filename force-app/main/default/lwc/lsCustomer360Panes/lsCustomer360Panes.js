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
import PHONE_FIELD from '@salesforce/schema/Account.Phone';
import INDUSTRY_FIELD from '@salesforce/schema/Account.Industry';
import ACCOUNT_SOURCE_FIELD from '@salesforce/schema/Account.AccountSource';
import TYPE_FIELD from '@salesforce/schema/Account.Type';
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
    PHONE_FIELD,
    INDUSTRY_FIELD,
    ACCOUNT_SOURCE_FIELD,
    TYPE_FIELD,
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
 * GCL-100 - Single Life Sciences Customer 360 view.
 * The limited panes apply only to the Customer record type.
 * The left account header is shown for the Customer page.
 * The Details pane is added only when the user is not the owner and not an Account Team member.
 */
export default class LsCustomer360Panes extends LightningElement {
    @api recordId;
    @api pane = 'Left';

    accessLevel;
    accessLoaded = false;
    accountResult;

    @wire(getHeaderView, { accountId: '$recordId' })
    wiredAccess({ data, error }) {
        if (!this.recordId) {
            this.accessLoaded = true;
            this.accessLevel = undefined;
            return;
        }

        if (data) {
            this.accessLevel = data.accessLevel;
            this.accessLoaded = true;
        } else if (error) {
            this.accessLevel = undefined;
            this.accessLoaded = true;
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredAccount(result) {
        this.accountResult = result;
    }

    get isLeft() {
        return this.pane !== 'Center';
    }

    get isCenter() {
        return this.pane === 'Center';
    }

    get showCard() {
        if (!this.recordId) {
            return true;
        }
        return this.hasAccount || this.isLoading;
    }

    get isLoading() {
        return Boolean(this.recordId) && !this.accountResult?.data && !this.accountResult?.error;
    }

    get errorMessage() {
        return this.accountResult?.error?.body?.message || '';
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

    get phone() {
        return this.value(PHONE_FIELD);
    }

    get industry() {
        return this.displayValue(INDUSTRY_FIELD);
    }

    get accountSource() {
        return this.displayValue(ACCOUNT_SOURCE_FIELD);
    }

    get accountType() {
        return this.displayValue(TYPE_FIELD);
    }

    get isBase() {
        return this.accessLoaded && this.accessLevel === ACCESS_BASE;
    }

    get hasAccount() {
        return Boolean(this.accountResult?.data);
    }

    value(field) {
        return getFieldValue(this.accountResult?.data, field) || '';
    }

    displayValue(field) {
        return getFieldDisplayValue(this.accountResult?.data, field) || this.value(field);
    }
}