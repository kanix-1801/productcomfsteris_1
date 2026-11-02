import { LightningElement, api, wire } from 'lwc';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import { NavigationMixin } from 'lightning/navigation';

export default class AccountCases extends NavigationMixin(LightningElement) {
    @api recordId;

    cases = [];
    error;

    columns = [
        {
            label: 'Case',
            fieldName: 'caseUrl',
            type: 'url',
            typeAttributes: {
                label: { fieldName: 'caseNumber' },
                target: '_self'
            }
        },
        { label: 'Contact Name', fieldName: 'contactName' },
        { label: 'Status', fieldName: 'status' },
        { label: 'Date Opened', fieldName: 'createdDate', type: 'date' },
        { label: 'Subject', fieldName: 'subject' },
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

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: 'Cases',
        fields: [
            'Case.CaseNumber',
            'Case.Contact.Name',
            'Case.Status',
            'Case.CreatedDate',
            'Case.Subject'
        ],
        sortBy: ['Case.CreatedDate']
    })
    wiredCases({ data, error }) {
        if (data) {
            this.cases = data.records.map(row => ({
                id: row.id,
                caseNumber: row.fields.CaseNumber?.value,
                caseUrl: '/' + row.id,
                contactName: row.fields.Contact?.displayValue,
                status: row.fields.Status?.value,
                createdDate: row.fields.CreatedDate?.value,
                subject: row.fields.Subject?.value
            }));

            this.error = undefined;
        } else if (error) {
            this.cases = [];
            this.error = error;
            console.error('CASE ERROR => ', JSON.stringify(error));
        }
    }

    get hasRecords() {
        return this.cases?.length > 0;
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: row.id,
                objectApiName: 'Case',
                actionName
            }
        });
    }

    handleNewCase() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Case',
                actionName: 'new'
            },
            state: {
                defaultFieldValues: `AccountId=${this.recordId}`
            }
        });
    }
}