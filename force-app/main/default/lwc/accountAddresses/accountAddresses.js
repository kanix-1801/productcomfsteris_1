import { LightningElement, api } from 'lwc';
import getAddresses from '@salesforce/apex/AccountAddressesController.getAddresses';
import { NavigationMixin } from 'lightning/navigation';


const COLUMNS = [
    { label: 'Street Address', fieldName: 'street' },
    { label: 'Address Type', fieldName: 'addressType' },
    { label: 'City', fieldName: 'city' },
    { label: 'State', fieldName: 'state' },
    { label: 'Postal Code', fieldName: 'postalCode' },
    {
            type: 'action',
            typeAttributes: {
                rowActions: [
                    { label: 'View', name: 'view' },
                    { label: 'Edit', name: 'edit' }
                ]
            }
        }

];

export default class AccountAddresses extends NavigationMixin(LightningElement) {
    @api recordId;

    columns = COLUMNS;
    addresses = [];
    error;

    connectedCallback() {
        this.loadAddresses();
    }

    async loadAddresses() {
        try {
            this.addresses = await getAddresses({
                accountId: this.recordId
            });

            this.error = undefined;
        } catch (error) {
            this.addresses = [];
            this.error = error;
        }
    }

    get hasRecords() {
        return this.addresses.length > 0;
    }

    get hasError() {
        return this.error !== undefined;
    }
    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: row.id,
                objectApiName: 'Address',
                actionName
            }
        });
    }
}