import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import getTaskProducts from '@salesforce/apex/FreeGoodTaskController.getTaskProducts';
import TASK_TYPE_FIELD from '@salesforce/schema/Task.Type';

/**
 * @author PWC Developer
 * @date 2026/08/18
 *
 * @description
 * GC-3230 - Free Goods Products tab on the Task record page. Loads every Free Goods Task Product
 * linked to the Task through TaskId__c and displays Product, Quantity, Account and audit fields.
 * Content is shown only when Task.Type is Free Goods (also enforced by the page visibility rule).
 */
const FREE_GOODS_TASK_TYPE = 'Free Goods';

const COLUMNS = [
    {
        label: 'Product',
        fieldName: 'productUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'productName' }, target: '_blank' },
        wrapText: true,
        sortable: true
    },
    { label: 'Product Code', fieldName: 'productCode', type: 'text', wrapText: true, sortable: true },
    { label: 'Line Description', fieldName: 'lineDescription', type: 'text', wrapText: true, sortable: true },
    {
        label: 'Quantity',
        fieldName: 'quantity',
        type: 'number',
        sortable: true,
        // Auto widths size to the values, which are short enough to clip the header text.
        initialWidth: 120,
        // Number columns right align by default, which reads as an empty cell next to the
        // left aligned columns either side of it.
        cellAttributes: { alignment: 'left' }
    },
    {
        label: 'Sales Price',
        fieldName: 'salesPrice',
        type: 'currency',
        sortable: true,
        cellAttributes: { alignment: 'left' }
    },
    { label: 'Consumption Frequency', fieldName: 'consumptionFrequency', type: 'text', sortable: true },
    { label: 'Status', fieldName: 'status', type: 'text', sortable: true },
    { label: 'Confidence Level', fieldName: 'confidenceLevel', type: 'text', sortable: true },
    {
        label: 'Expected Ship Date / Consumption Start',
        fieldName: 'expectedShipDate',
        type: 'date',
        sortable: true
    },
    { label: 'Contract', fieldName: 'contractValue', type: 'text', sortable: true },
    { label: 'Comments', fieldName: 'comments', type: 'text', wrapText: true, sortable: true },
    {
        label: 'Account',
        fieldName: 'accountUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'accountName' }, target: '_blank' },
        wrapText: true,
        sortable: true
    },
    {
        label: 'Created Date',
        fieldName: 'createdDate',
        type: 'date',
        typeAttributes: {
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        },
        sortable: true
    },
    { label: 'Created By', fieldName: 'createdByName', type: 'text', sortable: true }
];

export default class FreeGoodsTaskProducts extends NavigationMixin(LightningElement) {
    // Task record the page is displaying.
    @api recordId;

    @track productRows = [];
    @track error;
    @track isLoading = true;
    columns = COLUMNS;

    @wire(getRecord, { recordId: '$recordId', fields: [TASK_TYPE_FIELD] })
    taskRecord;

    /**
     * Content is only relevant for Free Goods Tasks.
     */
    get isFreeGoodsTask() {
        const taskType = getFieldValue(this.taskRecord?.data, TASK_TYPE_FIELD);
        return taskType === FREE_GOODS_TASK_TYPE;
    }

    /**
     * Loads the Free Goods Task Product rows for the current Task.
     */
    @wire(getTaskProducts, { taskId: '$recordId' })
    wiredProducts({ error, data }) {
        this.isLoading = false;

        if (data) {
            this.productRows = data.map(row => ({
                ...row,
                productUrl: row.productId ? `/lightning/r/Product2/${row.productId}/view` : null,
                accountUrl: row.accountId ? `/lightning/r/Account/${row.accountId}/view` : null
            }));
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.productRows = [];
        }
    }

    get hasRecords() {
        return this.isFreeGoodsTask && this.productRows && this.productRows.length > 0;
    }

    get showEmptyState() {
        return this.isFreeGoodsTask && !this.isLoading && !this.error && !this.hasRecords;
    }

    get productCountLabel() {
        const count = this.productRows ? this.productRows.length : 0;
        return count === 1 ? '1 Product' : `${count} Products`;
    }
}