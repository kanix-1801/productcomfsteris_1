import { LightningElement, api, wire } from 'lwc';

import getChildAccountContacts
    from '@salesforce/apex/ChildAccountContactController.getChildAccountContacts';

import { refreshApex } from '@salesforce/apex';

import { ShowToastEvent }
    from 'lightning/platformShowToastEvent';

const COLUMNS = [
    {
        label: 'Contact Name',
        fieldName: 'contactUrl',
        type: 'url',
        sortable: true,
        wrapText: true,
        typeAttributes: {
            label: {
                fieldName: 'contactName'
            },
            target: '_self',
            tooltip: {
                fieldName: 'contactName'
            }
        }
    },
    {
        label: 'Customer Location',
        fieldName: 'accountUrl',
        type: 'url',
        sortable: true,
        wrapText: true,
        typeAttributes: {
            label: {
                fieldName: 'accountName'
            },
            target: '_self',
            tooltip: {
                fieldName: 'accountName'
            }
        }
    },
    {
        label: 'Email',
        fieldName: 'email',
        type: 'email',
        sortable: true
    },
    {
        label: 'Phone',
        fieldName: 'phone',
        type: 'phone',
        sortable: true
    },
    {
        label: 'Mobile',
        fieldName: 'mobilePhone',
        type: 'phone',
        sortable: true
    }
];

export default class ChildAccountContacts extends LightningElement {

    @api recordId;

    columns = COLUMNS;
    contacts = [];

    displayComponent = false;
    resultLimitReached = false;
    totalContactCount = 0;

    isLoading = true;
    errorMessage;

    sortedBy = 'contactName';
    sortDirection = 'asc';

    wiredResponse;

    @wire(getChildAccountContacts, {
        accountId: '$recordId'
    })
    wiredChildAccountContacts(result) {
        this.wiredResponse = result;

        const { data, error } = result;

        if (data) {
            this.handleData(data);
        } else if (error) {
            this.handleError(error);
        }
    }

    handleData(data) {
        this.errorMessage = undefined;

        this.displayComponent =
            Boolean(data.displayComponent);

        this.resultLimitReached =
            Boolean(data.resultLimitReached);

        this.totalContactCount =
            data.totalContactCount || 0;

        this.contacts =
            (data.contacts || []).map(contact => ({
                ...contact,

                contactUrl:
                    `/lightning/r/Contact/` +
                    `${contact.contactId}/view`,

                accountUrl:
                    `/lightning/r/Account/` +
                    `${contact.accountId}/view`
            }));

        this.isLoading = false;
    }

    handleError(error) {
        this.displayComponent = true;
        this.contacts = [];
        this.errorMessage = this.reduceError(error);
        this.isLoading = false;
    }

    get shouldDisplayComponent() {
        return this.displayComponent || this.hasError;
    }

    get hasSuccessfulResponse() {
        return (
            !this.isLoading &&
            !this.hasError &&
            this.displayComponent
        );
    }

    get hasContacts() {
        return this.contacts.length > 0;
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    get title() {
        return (
            `Child Account Contacts ` +
            `(${this.totalContactCount})`
        );
    }

    async handleRefresh() {
        this.isLoading = true;

        try {
            await refreshApex(this.wiredResponse);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message:
                        'Child Account Contacts refreshed.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleSort(event) {
        const {
            fieldName,
            sortDirection
        } = event.detail;

        this.sortedBy = fieldName;
        this.sortDirection = sortDirection;

        this.contacts =
            [...this.contacts].sort(
                this.createSortFunction(
                    fieldName,
                    sortDirection
                )
            );
    }

    createSortFunction(fieldName, sortDirection) {
        const direction =
            sortDirection === 'asc' ? 1 : -1;

        return (firstRecord, secondRecord) => {
            const firstValue =
                this.getSortValue(
                    firstRecord,
                    fieldName
                );

            const secondValue =
                this.getSortValue(
                    secondRecord,
                    fieldName
                );

            if (firstValue > secondValue) {
                return direction;
            }

            if (firstValue < secondValue) {
                return -direction;
            }

            return 0;
        };
    }

    getSortValue(record, fieldName) {
        let value;

        if (fieldName === 'contactUrl') {
            value = record.contactName;
        } else if (fieldName === 'accountUrl') {
            value = record.accountName;
        } else {
            value = record[fieldName];
        }

        if (value === null || value === undefined) {
            return '';
        }

        return typeof value === 'string'
            ? value.toLowerCase()
            : value;
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body
                .map(item => item.message)
                .join(', ');
        }

        if (typeof error?.body?.message === 'string') {
            return error.body.message;
        }

        if (typeof error?.message === 'string') {
            return error.message;
        }

        return 'An unexpected error occurred.';
    }
}