import { LightningElement, api, wire } from 'lwc';
import getOrderLines from '@salesforce/apex/OrderLineRelatedListController.getOrderLines';
import getOrderLineCount from '@salesforce/apex/OrderLineRelatedListController.getOrderLineCount';

export default class OrderLineRelatedList extends LightningElement {
    @api recordId;
    @api objectApiName;

    orderLines = [];
    allOrderLines = [];
    totalCount = 0;
    isModalOpen = false;

    sortedBy;
    sortedDirection = 'asc';


    get parentObject() {
        return this.objectApiName;
    }

    get showViewAll() {
        return this.totalCount > 10;
    }

    /* ORDER PAGE COLUMNS */
    get orderColumns() {
        return [
            {
                label: 'Product',
                fieldName: 'productUrl',
                type: 'url',
                typeAttributes: {
                    label: { fieldName: 'productName' },
                    target: '_blank'
                },
                sortable: true
            },
            { label: 'Order Line Number', fieldName: 'orderLineNumber', sortable: true},
            { label: 'Quantity', fieldName: 'quantity', type: 'number',sortable: true },
            { label: 'Unit Price', fieldName: 'unitPriceUSD', type: 'text',sortable: true },
            { label: 'Extended Price', fieldName: 'extendedPrice', type: 'currency',sortable: true },
            { label: 'Subcase', fieldName: 'subcaseUrl',type : 'url',
                typeAttributes: {
                    label: { fieldName: 'subcaseNumber' },
                    target: '_blank'
                }, sortable: true },
            { label: 'Order Line Type', fieldName: 'orderLineType',sortable: true },
            { label: 'Order Line Status', fieldName: 'orderLineStatus',sortable: true },
            { label: 'Request Date', fieldName: 'requestDate', type: 'date',sortable: true },
            { label: 'Scheduled Date', fieldName: 'scheduledDate', type: 'date-local',sortable: true }
        ];
    }

    /* CASE PAGE COLUMNS */
    get caseColumns() {
        return [
            { label: 'Order Line Number', fieldName: 'orderLineNumber', type: 'number',sortable: true},
            { label: 'Item Number', fieldName: 'itemNumber',sortable: true },
            { label: 'Product Description', fieldName: 'productDescription' ,sortable: true},
            { label: 'Request Date', fieldName: 'requestDate', type: 'date' ,sortable: true},
            { label: 'Scheduled Date', fieldName: 'scheduledDate', type: 'date',sortable: true },
            { label: 'Actual Shipment Date', fieldName: 'ActualShipmentDate', type: 'date',sortable: true },
            { label: 'Quantity', fieldName: 'quantity', type: 'number',sortable: true },
            { label: 'Unit Price', fieldName: 'unitPrice', type: 'currency',sortable: true },
            { label: 'Order Line Status', fieldName: 'orderLineStatus' ,sortable: true},
            { label: 'Warehouse', fieldName: 'Warehouse' ,sortable: true},
            { label: 'Sales Rep', fieldName: 'SalesRep' ,sortable: true}
        ];
    }

    get columns() {
        return this.objectApiName === 'Case'
            ? this.caseColumns
            : this.orderColumns;
    }

    @wire(getOrderLines, {
        parentRecordId: '$recordId',
        parentObject: '$parentObject',
        limitSize: 10
    })
        
    wiredOrderLines({ data }) {
        if (data) {
            this.orderLines = data.map(row => ({
                ...row,
                unitPriceUSD: row.unitPrice !== null
                    ? `USD ${Number(row.unitPrice).toFixed(2)}`
                    : ''
            }));
        }
    }


    @wire(getOrderLineCount, {
        parentRecordId: '$recordId',
        parentObject: '$parentObject'
    })
    wiredCount({ data }) {
        if (data) this.totalCount = data;
    }

    openModal() {
        getOrderLines({
        parentRecordId: this.recordId,
        parentObject: this.objectApiName,
        limitSize: 1000
    }).then(result => {
        // APPLY ACTIVE SORTING TO VIEW ALL DATA
        this.allOrderLines = this.sortedBy
            ? this.sortData(result, this.sortedBy, this.sortedDirection)
            : result;

        this.isModalOpen = true;
    });
    }


    closeModal() {
        this.isModalOpen = false;
    }

    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;

    this.sortedBy = fieldName;
    this.sortedDirection = sortDirection;

    this.orderLines = this.sortData(
        this.orderLines,
        fieldName,
        sortDirection
    );
    console.log(this.orderLines);

    if (this.isModalOpen) {
        console.log(this.isModalOpen);
        this.allOrderLines = this.sortData(
            this.allOrderLines,
            fieldName,
            sortDirection
        );
        console.log(this.allOrderLines);
    }
    }


    /* =========================
     * GENERIC SORT FUNCTION
     * ========================= */
    sortData(data, fieldName, direction) {
        if (!data) return [];

        const isAsc = direction === 'asc';

        return [...data].sort((a, b) => {
            let valueA = a[fieldName];
            let valueB = b[fieldName];

            if (valueA === null || valueA === undefined) return isAsc ? -1 : 1;
            if (valueB === null || valueB === undefined) return isAsc ? 1 : -1;

            // Numbers
            if (typeof valueA === 'number' && typeof valueB === 'number') {
                return isAsc ? valueA - valueB : valueB - valueA;
            }

            // Dates
            if (valueA instanceof Date || valueB instanceof Date) {
                return isAsc
                    ? new Date(valueA) - new Date(valueB)
                    : new Date(valueB) - new Date(valueA);
            }

            // Strings
            return isAsc
                ? valueA.toString().localeCompare(valueB.toString())
                : valueB.toString().localeCompare(valueA.toString());
        });
    }
            
        get hasOrderLines() {
            return this.orderLines && this.orderLines.length > 0;
        }

        get hasViewAllLines() {
            return this.allOrderLines && this.allOrderLines.length > 0;
        }

}