import { LightningElement, api, wire } from 'lwc';
import getSiblings from '@salesforce/apex/RelatedCasesByRegistrationCtrl.getSiblingsByRegistration';
import { NavigationMixin } from 'lightning/navigation';

export default class RelatedOrdersSameReg extends NavigationMixin(LightningElement) {
    @api recordId;
    @api registrationFieldApiName = 'RegistrationNumber__c';
    @api maxRows = 5;
    @api wantDateApiName = 'CBM_Want_Date__c';
    @api firstShipDateApiName = 'First_Scheduled_Ship_Date__c';
    @api stageApiName = 'Stage__c';

    loading = true;
    rows = [];
    collapsed = false;

    @wire(getSiblings, {
        recordId: '$recordId',
        registrationFieldApiName: '$registrationFieldApiName',
        maxRows: '$maxRows',
        wantDateApiName: '$wantDateApiName',
        firstShipDateApiName: '$firstShipDateApiName',
        stageApiName: '$stageApiName'
    })
    wiredRows({ data, error }) {
        this.loading = false;
        if (data) {
            this.rows = data;
        } else if (error) {
            this.rows = [];
            // Optionally log error
        }
    }

    get hasRows() {
        return (this.rows && this.rows.length > 0);
    }

    get title() {
        const count = this.rows?.length || 0;
        return `Related Orders with Same Registration Number (${count})`;
    }

    get chevronIcon() {
        return this.collapsed ? 'utility:chevrondown' : 'utility:chevronright';
    }

    toggleCollapse = () => {
        this.collapsed = !this.collapsed;
    };

    handleViewAll = () => {
        // Option A: Navigate to Case object home (simple)
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Case', actionName: 'list' },
            state: { filterName: 'Recent' }
        });
        // Option B (recommended): deep‑link to a specific list view by ID.
        // Provide me a ListViewId and I’ll wire it in here.
    };

    openRow = (event) => {
        const recId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: recId, objectApiName: 'Case', actionName: 'view' }
        });
    };
}