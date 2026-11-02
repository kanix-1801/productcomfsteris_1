import { LightningElement, api, wire, track } from 'lwc';
import getRelatedOrderLines from '@salesforce/apex/OrderLineTaskController.getRelatedOrderLines';
import { NavigationMixin } from 'lightning/navigation';
// 1. Import getRecord and getFieldValue
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
// 2. Import Task Fields (Replace Phase__c with your actual API name)
import WHAT_ID_FIELD from '@salesforce/schema/Task.WhatId';
import PHASE_FIELD from '@salesforce/schema/Task.Phase__c'; 

const COLUMNS = [

        { 
        label: 'Order Line Number', 
        fieldName: 'recordLink', 
        type: 'url', 
        typeAttributes: { label: { fieldName: 'OrderItemNumber' }, target: '_blank' } 
    },
    { label: 'Line Number', fieldName: 'OrderLineNumber__c', type: 'text', sortable: true },
    { label: 'Product', fieldName: 'ProductName', type: 'text', sortable: true },
{ label: 'Scheduled Date', fieldName: 'ScheduledDate__c', type: 'date-local', sortable: true },
{ label: 'Request Date', fieldName: 'RequestDate__c', type: 'date-local', sortable: true },
{ label: 'Actual Shipment Date', fieldName: 'ActualShipmentDate__c', type: 'date-local', sortable: true },
{ label: 'Is Active?', fieldName: 'Active__c', type: 'boolean', sortable: true }
];
export default class TaskOrderLines extends NavigationMixin(LightningElement) {
    @api recordId; // Automatically gets Task ID
    @track orderLines = [];
    @track error;
    @track isLoading = true;
    columns = COLUMNS;

    //  Wire the Task record to check visibility conditions
    @wire(getRecord, { recordId: '$recordId', fields: [WHAT_ID_FIELD, PHASE_FIELD] })
    taskRecord;

    
    get isComponentVisible() {
        const data = this.taskRecord?.data;
        if (!data) {
            return false;
        }
        const whatId = getFieldValue(data, WHAT_ID_FIELD);
        const phase = getFieldValue(data, PHASE_FIELD);
        return !!whatId && !!phase; // both must be truthy (not null/undefined)
    }
       
    @wire(getRelatedOrderLines, { taskId: '$recordId' })
    wiredLines({ error, data }) {
        
        if (data) {
            // Process data to flatten the Product Name and create a record link
            this.orderLines = data.map(item => {
                return {
                    ...item,
                    ProductName: item.Product2 ? item.Product2.Name : '',
                    recordLink: `/lightning/r/OrderItem/${item.Id}/view`
                };
            });
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.orderLines = undefined;
        }
        this.isLoading = false;
    }

    get hasRecords() {
        return this.orderLines && this.orderLines.length > 0;
    }
}