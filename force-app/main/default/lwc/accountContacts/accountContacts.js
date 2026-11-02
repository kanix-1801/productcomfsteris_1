import { LightningElement, api, wire } from 'lwc';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import { NavigationMixin } from 'lightning/navigation';

const DEFAULT_VISIBLE_ROWS = 5;

export default class AccountContacts extends NavigationMixin(LightningElement) {
    @api recordId;

    contacts = [];
    error;
    showAll = false;

    columns = [
        {
            label: 'Contact Name',
            fieldName: 'contactUrl',
            type: 'url',
            typeAttributes: {
                label: { fieldName: 'name' },
                target: '_self'
            }
        },
        { label: 'Role / Persona', fieldName: 'rolePersona' },
        { label: 'Department', fieldName: 'department' },
        { label: 'BU Focus', fieldName: 'buFocus' },
        { label: 'Engagement', fieldName: 'engagement' },
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
        relatedListId: 'Contacts',
        fields: [
            'Contact.Name',
            'Contact.Title',
            'Contact.Department'
        ]
    })
    wiredContacts({ data, error }) {
        if (data) {
            this.contacts = data.records.map(row => ({
                id: row.id,
                name: row.fields.Name?.value,
                contactUrl: '/' + row.id,
                rolePersona: row.fields.Title?.value,
                department: row.fields.Department?.value,
                buFocus: '',
                engagement: ''
            }));

            this.error = undefined;
        } else if (error) {
            this.contacts = [];
            this.error = error;
            console.error('CONTACT ERROR => ', JSON.stringify(error));
        }
    }

    get visibleContacts() {
        return this.showAll
            ? this.contacts
            : this.contacts.slice(0, DEFAULT_VISIBLE_ROWS);
    }

    get hasRecords() {
        return this.contacts?.length > 0;
    }

    get hasMoreRecords() {
        return this.contacts.length > DEFAULT_VISIBLE_ROWS;
    }

    get showMoreLabel() {
        return this.showAll ? 'Show Less' : 'Show More';
    }

    handleShowMore() {
        this.showAll = !this.showAll;
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: row.id,
                objectApiName: 'Contact',
                actionName
            }
        });
    }

    handleNewContact() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Contact',
                actionName: 'new'
            },
            state: {
                defaultFieldValues: `AccountId=${this.recordId}`
            }
        });
    }
}