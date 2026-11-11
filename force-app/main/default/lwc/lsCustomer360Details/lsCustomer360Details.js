import { LightningElement, api, wire } from 'lwc';
import { getFieldDisplayValue, getFieldValue, getRecord } from 'lightning/uiRecordApi';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import getHeaderView from '@salesforce/apex/LSAccountHeaderController.getHeaderView';
import NAME_FIELD from '@salesforce/schema/Account.Name';
import PHONE_FIELD from '@salesforce/schema/Account.Phone';
import INDUSTRY_FIELD from '@salesforce/schema/Account.Industry';
import ACCOUNT_SOURCE_FIELD from '@salesforce/schema/Account.AccountSource';
import TYPE_FIELD from '@salesforce/schema/Account.Type';
import PARENT_ID_FIELD from '@salesforce/schema/Account.ParentId';
import PARENT_NAME_FIELD from '@salesforce/schema/Account.Parent.Name';

const ACCESS_FULL = 'Full';
const LIMITED_FIELDS = [
    NAME_FIELD,
    PHONE_FIELD,
    INDUSTRY_FIELD,
    ACCOUNT_SOURCE_FIELD,
    TYPE_FIELD,
    PARENT_ID_FIELD,
    PARENT_NAME_FIELD
];

const CONTACT_COLUMNS = [
    { label: 'Name', fieldName: 'recordUrl', type: 'url', typeAttributes: { label: { fieldName: 'name' }, target: '_self' } },
    { label: 'Title', fieldName: 'title' },
    { label: 'Email', fieldName: 'email', type: 'email' },
    { label: 'Phone', fieldName: 'phone', type: 'phone' }
];

const OPPORTUNITY_COLUMNS = [
    { label: 'Opportunity Name', fieldName: 'recordUrl', type: 'url', typeAttributes: { label: { fieldName: 'name' }, target: '_self' } },
    { label: 'Stage', fieldName: 'stage' },
    { label: 'Amount', fieldName: 'amount', type: 'currency' },
    { label: 'Close Date', fieldName: 'closeDate', type: 'date' }
];

const HISTORY_COLUMNS = [
    { label: 'Date', fieldName: 'createdDate', type: 'date', typeAttributes: { year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' } },
    { label: 'Field', fieldName: 'field' },
    { label: 'User', fieldName: 'createdBy' },
    { label: 'Original Value', fieldName: 'oldValue' },
    { label: 'New Value', fieldName: 'newValue' }
];

/**
 * @author PWC Developer
 * @date 2026/11/06
 *
 * @description
 * GCL-100 - Center pane on LS Customer 360 Three Column.
 * The Customer owner and Account Team members see the full Account layout.
 * Anyone else on a Customer account sees the read-only Details card only.
 */
export default class LsCustomer360Details extends LightningElement {
    @api recordId;

    accessLoaded = false;
    isFull = false;
    accountResult;

    contactColumns = CONTACT_COLUMNS;
    opportunityColumns = OPPORTUNITY_COLUMNS;
    historyColumns = HISTORY_COLUMNS;
    contactRows = [];
    opportunityRows = [];
    historyRows = [];

    @wire(getHeaderView, { accountId: '$recordId' })
    wiredAccess({ data, error }) {
        if (!this.recordId) {
            this.isFull = true;
            this.accessLoaded = true;
            return;
        }

        if (data) {
            this.isFull = data.accessLevel === ACCESS_FULL;
            this.accessLoaded = true;
        } else if (error) {
            this.isFull = true;
            this.accessLoaded = true;
        }
    }

    @wire(getRecord, { recordId: '$limitedRecordId', fields: LIMITED_FIELDS })
    wiredAccount(result) {
        this.accountResult = result;
    }

    @wire(getRelatedListRecords, {
        parentRecordId: '$fullRecordId',
        relatedListId: 'Contacts',
        fields: ['Contact.Name', 'Contact.Title', 'Contact.Email', 'Contact.Phone']
    })
    wiredContacts({ data }) {
        this.contactRows = data ? this.toContactRows(data.records) : [];
    }

    @wire(getRelatedListRecords, {
        parentRecordId: '$fullRecordId',
        relatedListId: 'Opportunities',
        fields: ['Opportunity.Name', 'Opportunity.StageName', 'Opportunity.Amount', 'Opportunity.CloseDate']
    })
    wiredOpportunities({ data }) {
        this.opportunityRows = data ? this.toOpportunityRows(data.records) : [];
    }

    @wire(getRelatedListRecords, {
        parentRecordId: '$fullRecordId',
        relatedListId: 'Histories',
        fields: ['AccountHistory.CreatedDate', 'AccountHistory.Field', 'AccountHistory.CreatedBy.Name', 'AccountHistory.OldValue', 'AccountHistory.NewValue']
    })
    wiredHistory({ data }) {
        this.historyRows = data ? this.toHistoryRows(data.records) : [];
    }

    get fullRecordId() {
        return this.accessLoaded && this.isFull ? this.recordId : undefined;
    }

    get limitedRecordId() {
        return this.accessLoaded && !this.isFull ? this.recordId : undefined;
    }

    get isLoading() {
        if (!this.accessLoaded) {
            return true;
        }
        if (this.isFull) {
            return false;
        }
        return Boolean(this.recordId) && !this.accountResult?.data && !this.accountResult?.error;
    }

    get errorMessage() {
        if (this.isFull) {
            return '';
        }
        return this.accountResult?.error?.body?.message || '';
    }

    get accountName() {
        return this.value(NAME_FIELD);
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

    value(field) {
        return getFieldValue(this.accountResult?.data, field) || '';
    }

    displayValue(field) {
        return getFieldDisplayValue(this.accountResult?.data, field) || this.value(field);
    }

    toContactRows(records) {
        return (records || []).map((record) => ({
            id: record.id,
            recordUrl: `/lightning/r/Contact/${record.id}/view`,
            name: this.fieldValue(record, 'Name'),
            title: this.fieldValue(record, 'Title'),
            email: this.fieldValue(record, 'Email'),
            phone: this.fieldValue(record, 'Phone')
        }));
    }

    toOpportunityRows(records) {
        return (records || []).map((record) => ({
            id: record.id,
            recordUrl: `/lightning/r/Opportunity/${record.id}/view`,
            name: this.fieldValue(record, 'Name'),
            stage: this.fieldValue(record, 'StageName'),
            amount: this.fieldValue(record, 'Amount'),
            closeDate: this.fieldValue(record, 'CloseDate')
        }));
    }

    toHistoryRows(records) {
        return (records || []).map((record) => ({
            id: record.id,
            createdDate: this.fieldValue(record, 'CreatedDate'),
            field: this.fieldDisplay(record, 'Field'),
            createdBy: this.fieldValue(record, 'CreatedBy.Name') || this.fieldValue(record, 'CreatedBy'),
            oldValue: this.fieldDisplay(record, 'OldValue'),
            newValue: this.fieldDisplay(record, 'NewValue')
        }));
    }

    fieldValue(record, fieldName) {
        const field = record?.fields?.[fieldName];
        if (field) {
            return field.displayValue || field.value || '';
        }
        const leaf = fieldName.split('.').pop();
        const nested = record?.fields?.[leaf];
        return nested?.displayValue || nested?.value || '';
    }

    fieldDisplay(record, fieldName) {
        const field = record?.fields?.[fieldName];
        if (!field) {
            return '';
        }
        return field.displayValue || field.value || '';
    }
}