import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import NAME_FIELD from '@salesforce/schema/Account.Name';
import ACCOUNT_SOURCE_FIELD from '@salesforce/schema/Account.AccountSource';
import TYPE_FIELD from '@salesforce/schema/Account.Type';
import INDUSTRY_FIELD from '@salesforce/schema/Account.Industry';
import PHONE_FIELD from '@salesforce/schema/Account.Phone';
import PARENT_ID_FIELD from '@salesforce/schema/Account.ParentId';
import PARENT_NAME_FIELD from '@salesforce/schema/Account.Parent.Name';

const FIELDS = [
    NAME_FIELD,
    ACCOUNT_SOURCE_FIELD,
    TYPE_FIELD,
    INDUSTRY_FIELD,
    PHONE_FIELD,
    PARENT_ID_FIELD,
    PARENT_NAME_FIELD
];

export default class AccountInformationSection extends LightningElement {
    @api recordId;

    sectionOpen = true;
    isLoading = true;
    isEditing = false;
    loadError;
    account;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredAccount({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.account = data;
            this.loadError = undefined;
        } else if (error) {
            this.loadError = error;
            this.account = undefined;
        }
    }

    get name() {
        return getFieldValue(this.account, NAME_FIELD);
    }

    get accountSource() {
        return getFieldValue(this.account, ACCOUNT_SOURCE_FIELD);
    }

    get phone() {
        return getFieldValue(this.account, PHONE_FIELD);
    }

    get type() {
        return getFieldValue(this.account, TYPE_FIELD);
    }

    get industry() {
        return getFieldValue(this.account, INDUSTRY_FIELD);
    }

    get parentId() {
        return getFieldValue(this.account, PARENT_ID_FIELD);
    }

    get parentName() {
        return getFieldValue(this.account, PARENT_NAME_FIELD);
    }

    get parentUrl() {
        return this.parentId ? `/${this.parentId}` : null;
    }

    get hasParent() {
        return !!this.parentId;
    }

    get sectionClass() {
        return this.sectionOpen
            ? 'slds-section slds-is-open'
            : 'slds-section';
    }

    get chevronClass() {
        return this.sectionOpen
            ? 'slds-section__title-action-icon slds-button__icon slds-button__icon_left slds-section__title-action-icon_rotate'
            : 'slds-section__title-action-icon slds-button__icon slds-button__icon_left';
    }

    toggleSection() {
        this.sectionOpen = !this.sectionOpen;
    }

    handleEditClick() {
        this.isEditing = true;
    }

    handleCancel() {
        this.isEditing = false;
    }

    handleSave(event) {
        event.preventDefault();

        const inputs = [...this.template.querySelectorAll('lightning-input-field')];

        const allValid = inputs.reduce((valid, field) => {
            return field.reportValidity() && valid;
        }, true);

        if (!allValid) {
            return;
        }

        this.isEditing = false;

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message: 'Account information validated (demo — not saved).',
                variant: 'success'
            })
        );
    }
}