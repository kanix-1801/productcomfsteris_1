import { LightningElement, api, wire } from 'lwc';
import getGroupedRecords from '@salesforce/apex/CBMHoldsRelatedListController.getGroupedRecords';

//Constant for table headers properties
const COLUMNS = [
    { label: 'Hold Codes', fieldName: 'holdCodes', type: 'text', wrapText: true },
    { label: 'Line Number', fieldName: 'lineNumber', type: 'text', wrapText: true },
    { label: 'Item Number', fieldName: 'itemNumber', type: 'text', wrapText: true },
    { label: 'Product Description', fieldName: 'productDescription', type: 'text', wrapText: false },
    { label: 'Quantity', fieldName: 'quantity', type: 'text', wrapText: true }
];

export default class CBMHoldsRelatedList extends LightningElement {
    @api recordId;

    columns = COLUMNS;
    records = [];// Will be populated from wire
    error;
    isLoading = true;

    // Wire to get hold data
    @wire(getGroupedRecords, { recordId: '$recordId' })
    wiredGroupedRecords({ data, error }) {
        this.isLoading = false;

        if (data) {
            let sortedRecords = [...data];
            sortedRecords.sort((a, b) => {
                return (
                    (parseFloat(a.lineNumber) || 0) -
                    (parseFloat(b.lineNumber) || 0)
                );
            });
            this.records = sortedRecords;
            this.error = undefined;
        } else if (error) {
            this.records = [];
            this.error = error;
        }
    }

    //return if records exists
    get hasRecords() {
        return this.records.length > 0;
    }

    // This getter calculates the list size dynamically
    get recordSize() {
        return this.records ? this.records.length : 0;
    }

    //return if error
    get hasError() {
        return Boolean(this.error);
    }

    //return error message
    get errorMessage() {
        return this.error?.body?.message || this.error?.message || 'An unexpected error occurred.';
    }
}