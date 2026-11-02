import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import getVisibilityConfig from '@salesforce/apex/AccountPageVisibilityController.getVisibilityConfig';


import NAME_FIELD from '@salesforce/schema/Account.Name';
import WEBSITE_FIELD from '@salesforce/schema/Account.Website';
import BILLING_STREET_FIELD from '@salesforce/schema/Account.BillingStreet';
import BILLING_CITY_FIELD from '@salesforce/schema/Account.BillingCity';
import BILLING_STATE_FIELD from '@salesforce/schema/Account.BillingState';
import BILLING_POSTAL_CODE_FIELD from '@salesforce/schema/Account.BillingPostalCode';
import BILLING_COUNTRY_FIELD from '@salesforce/schema/Account.BillingCountry';
import ACCOUNT_NUMBER_FIELD from '@salesforce/schema/Account.AccountNumber';
import PARENT_NAME_FIELD from '@salesforce/schema/Account.Parent.Name';
import HOUSE_ACCOUNT_FIELD from '@salesforce/schema/Account.IsHouseAccount__c';

const FIELDS = [
    NAME_FIELD,
    WEBSITE_FIELD,
    BILLING_STREET_FIELD,
    BILLING_CITY_FIELD,
    BILLING_STATE_FIELD,
    BILLING_POSTAL_CODE_FIELD,
    BILLING_COUNTRY_FIELD,
    ACCOUNT_NUMBER_FIELD,
    PARENT_NAME_FIELD,
    HOUSE_ACCOUNT_FIELD
];
const PAGE_NAME = 'Customer360';

export default class AccountDetailedPage extends NavigationMixin(LightningElement) {
    @api recordId;

    get effectiveRecordId() {
        return this.recordId || this.getRecordIdFromUrl();
    }
    

    @wire(getRecord, {
        recordId: '$effectiveRecordId',
        fields: FIELDS
    })
    account;
    configByComponent = {};

    @wire(getVisibilityConfig, {
        accountId: '$effectiveRecordId',
        pageName: PAGE_NAME
    })
    wiredVisibilityConfig({ data, error }) {
        if (data) {
            this.configByComponent = {};

            data.configs.forEach((item) => {
                this.configByComponent[item.componentApiName] = item;
            });
        } else if (error) {
            this.configByComponent = {};
            // eslint-disable-next-line no-console
            console.error('Account header visibility error', error);
        }
    }

    get showAccountHeader() {
        return this.isVisible('AccountHeader');
    }

    isVisible(componentName) {
        return this.configByComponent[componentName]?.isVisible === true;
    }

    get isLoading() {
        return !!this.effectiveRecordId && !this.account?.data && !this.account?.error;
    }

    get hasAccount() {
        return !!this.account?.data;
    }

    get hasError() {
        return !!this.account?.error;
    }

    get errorMessage() {
        return this.account?.error?.body?.message || 'Unable to load account details.';
    }

    get accountName() {
        return getFieldValue(this.account.data, NAME_FIELD) || '';
    }

    get country() {
        return getFieldValue(this.account.data, BILLING_COUNTRY_FIELD) || '';
    }

    // GC-3464: billing address identifiers are display-only on the Account Header.
    get billingStreet() {
        return getFieldValue(this.account.data, BILLING_STREET_FIELD) || '';
    }

    get billingCity() {
        return getFieldValue(this.account.data, BILLING_CITY_FIELD) || '';
    }

    get billingState() {
        return getFieldValue(this.account.data, BILLING_STATE_FIELD) || '';
    }

    get billingPostalCode() {
        return getFieldValue(this.account.data, BILLING_POSTAL_CODE_FIELD) || '';
    }

   get customerNumber() {
        return getFieldValue(this.account.data, ACCOUNT_NUMBER_FIELD) || '';
    }

    get parentAccountName() {
        return getFieldValue(this.account.data, PARENT_NAME_FIELD) || '';
    }

    get gpoAffiliation() {
        return 'Medbuy';
    }

    get customerClassCode() {
        return 'HealthCare';
    }

    get website() {
        return getFieldValue(this.account.data, WEBSITE_FIELD) || '';
    }

    get websiteUrl() {
        if (!this.website) {
            return '';
        }

        return this.website.startsWith('http') ? this.website : `https://${this.website}`;
    }

    get hasWebsite() {
        return !!this.website;
    }
    get isHouseAccount() {
        return getFieldValue(this.account.data, HOUSE_ACCOUNT_FIELD);
    }

    getRecordIdFromUrl() {
        const match = window.location.pathname.match(/\/Account\/([a-zA-Z0-9]{15,18})/);
        return match ? match[1] : null;
    }

    handleViewAccountHierarchy() {
        const accountId = this.effectiveRecordId;
        if (!accountId) {
            return;
        }

        const hierarchyPageReference = {
            componentDef: 'sfa:hierarchyFullView',
            attributes: {
                recordId: accountId,
                sObjectName: 'Account'
            },
            state: {}
        };

        const encodedReference = encodeURIComponent(
            btoa(JSON.stringify(hierarchyPageReference))
        );

        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: `/one/one.app#${encodedReference}`
            }
        });
    }
}