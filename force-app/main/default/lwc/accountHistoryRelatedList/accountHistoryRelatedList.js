import { LightningElement, api, wire } from 'lwc';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';

export default class AccountHistoryRelatedList extends LightningElement {
    @api recordId;

    columns = [
        { label: 'Date', fieldName: 'createdDate', type: 'date' },
        { label: 'User', fieldName: 'createdBy' },
        { label: 'Field', fieldName: 'field' },
        { label: 'Original Value', fieldName: 'oldValue' },
        { label: 'New Value', fieldName: 'newValue' }
    ];

    historyData = [];

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: 'Histories',
        fields: [
            'AccountHistory.Id',
            'AccountHistory.CreatedDate',
            'AccountHistory.CreatedBy.Name',
            'AccountHistory.Field',
            'AccountHistory.OldValue',
            'AccountHistory.NewValue'
        ],
        sortBy: ['AccountHistory.CreatedDate DESC']
    })
    wiredHistory({ data, error }) {
        if (data) {
            this.historyData = data.records.map(record => {
                const fields = record.fields;

                return {
                    id: record.id,
                    createdDate: fields.CreatedDate?.value,
                    createdBy: fields.CreatedBy?.displayValue || fields.CreatedBy?.value,
                    field: fields.Field?.displayValue || fields.Field?.value,
                    oldValue: fields.OldValue?.displayValue || fields.OldValue?.value,
                    newValue: fields.NewValue?.displayValue || fields.NewValue?.value
                };
            });
        } else if (error) {
            console.error('Account History error:', error);
        }
    }
}