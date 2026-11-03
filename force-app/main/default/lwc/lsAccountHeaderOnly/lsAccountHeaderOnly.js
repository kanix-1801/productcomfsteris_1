import { LightningElement, api, wire } from 'lwc';
import { getFieldDisplayValue, getFieldValue, getRecord } from 'lightning/uiRecordApi';
import getHeaderView from '@salesforce/apex/LSAccountHeaderController.getHeaderView';
import NAME_FIELD from '@salesforce/schema/Account.Name';
import ACCOUNT_NUMBER_FIELD from '@salesforce/schema/Account.AccountNumber';
import WEBSITE_FIELD from '@salesforce/schema/Account.Website';
import PHONE_FIELD from '@salesforce/schema/Account.Phone';
import INDUSTRY_FIELD from '@salesforce/schema/Account.Industry';
import ACCOUNT_SOURCE_FIELD from '@salesforce/schema/Account.AccountSource';
import TYPE_FIELD from '@salesforce/schema/Account.Type';
import CUSTOMER_CLASS_FIELD from '@salesforce/schema/Account.CustomerClassCode__c';
import PARENT_ID_FIELD from '@salesforce/schema/Account.ParentId';
import PARENT_NAME_FIELD from '@salesforce/schema/Account.Parent.Name';
import OWNER_NAME_FIELD from '@salesforce/schema/Account.Owner.Name';
import GPO_NAME_FIELD from '@salesforce/schema/Account.GPO_Account__r.Name';
import BILLING_STREET_FIELD from '@salesforce/schema/Account.BillingStreet';
import BILLING_CITY_FIELD from '@salesforce/schema/Account.BillingCity';
import BILLING_STATE_FIELD from '@salesforce/schema/Account.BillingState';
import BILLING_POSTAL_CODE_FIELD from '@salesforce/schema/Account.BillingPostalCode';
import BILLING_COUNTRY_FIELD from '@salesforce/schema/Account.BillingCountry';

// GCL-100 - Identifying fields only. Child records are not part of this header.
function messageFrom(error) {
    const body = error?.body;
    if (Array.isArray(body)) {
        return body.map((item) => item?.message).filter(Boolean).join(' ');
    }
    if (typeof body?.message === 'string') {
        return body.message;
    }
    return error?.message || '';
}

function isClassAccessDenied(error) {
    const message = messageFrom(error).toLowerCase();
    return message.includes('apex class') && message.includes('access');
}

function inAppBuilder() {
    try {
        const href = window.location.href || '';
        const referrer = document.referrer || '';
        return href.includes('flexipageEditor')
            || href.includes('appBuilder.app')
            || referrer.includes('flexipageEditor')
            || referrer.includes('appBuilder.app');
    } catch (e) {
        return false;
    }
}

const HEADER_FIELDS = [
    NAME_FIELD,
    ACCOUNT_NUMBER_FIELD,
    WEBSITE_FIELD,
    PHONE_FIELD,
    INDUSTRY_FIELD,
    ACCOUNT_SOURCE_FIELD,
    TYPE_FIELD,
    CUSTOMER_CLASS_FIELD,
    PARENT_ID_FIELD,
    PARENT_NAME_FIELD,
    OWNER_NAME_FIELD,
    GPO_NAME_FIELD,
    BILLING_STREET_FIELD,
    BILLING_CITY_FIELD,
    BILLING_STATE_FIELD,
    BILLING_POSTAL_CODE_FIELD,
    BILLING_COUNTRY_FIELD
];

/**
 * @author PWC Developer
 * @date 2026/10/30
 *
 * @description
 * GCL-100 - Read-only Account header for a Life Sciences rep who is outside the
 * assigned territory. Apex decides access from the Account owner and Account Team.
 * Field values are read through the UI API so field-level security stays in force.
 */
export default class LsAccountHeaderOnly extends LightningElement {
    @api recordId;

    headerOnly = false;
    accessLoaded = false;
    accessError;
    accountResult;
    inBuilder = false;

    connectedCallback() {
        this.inBuilder = inAppBuilder();
    }

    @wire(getHeaderView, { accountId: '$recordId' })
    wiredHeader({ data, error }) {
        if (!this.recordId) {
            this.accessLoaded = true;
            this.headerOnly = false;
            return;
        }

        if (data) {
            this.headerOnly = data.showHeaderOnly === true;
            this.accessError = undefined;
            this.accessLoaded = true;
        } else if (error) {
            this.headerOnly = false;
            // Class access is granted only to LS Inside Sales. Other personas on the
            // same Account page must not see an error banner.
            this.accessError = isClassAccessDenied(error)
                ? undefined
                : messageFrom(error) || 'Unable to load the account header.';
            this.accessLoaded = true;
        }
    }

    get headerRecordId() {
        if (this.inBuilder && this.recordId) {
            return this.recordId;
        }
        return this.headerOnly ? this.recordId : undefined;
    }

    @wire(getRecord, { recordId: '$headerRecordId', fields: HEADER_FIELDS })
    wiredAccount(result) {
        this.accountResult = result;
    }

    get showHeaderOnly() {
        if (this.inBuilder && this.hasAccount) {
            return true;
        }
        return this.headerOnly && this.hasAccount;
    }

    get showBuilderPlaceholder() {
        return this.inBuilder && this.accessLoaded && !this.showHeaderOnly && !this.errorMessage;
    }

    get isLoading() {
        if (!this.recordId || this.accessError) {
            return false;
        }
        if (!this.accessLoaded) {
            return true;
        }
        return this.headerOnly && !this.accountResult?.data && !this.accountResult?.error;
    }

    get hasAccount() {
        return Boolean(this.accountResult?.data);
    }

    get errorMessage() {
        if (this.accessError) {
            return this.accessError;
        }
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

    get country() {
        return this.displayValue(BILLING_COUNTRY_FIELD);
    }

    get hasCountry() {
        return Boolean(this.country);
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