import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getSiblings from '@salesforce/apex/RelatedCasesByRegistrationCtrl.getSiblings';
import getAllByRegistration from '@salesforce/apex/RelatedCasesByRegistrationCtrl.getAllByRegistration';

export default class RelatedCasesSameReg extends NavigationMixin(LightningElement) {
    @api recordId;

    // Card (compact)
    loading = true;
    collapsed = false;
    rows = [];

    // Modal (View All)
    showModal = false;
    loadingAll = false;
    allRows = [];

    // Datatable columns in the exact order you requested
    columns = [
        {
            label: 'Case Number',
            fieldName: 'url',
            type: 'url',
            typeAttributes: { label: { fieldName: 'CaseNumber' }, target: '_blank' }
        },
        { label: 'Subject', fieldName: 'Subject' },
        { label: 'Want Date', fieldName: 'Customer_Want_Date__c', type: 'date' },
        { label: 'First Scheduled Ship Date', fieldName: 'FirstNonPreInstallScheduledShipDate__c', type: 'date' },
        { label: 'Stage', fieldName: 'Status' } // Fix A: Stage is Case.Status
    ];

    // --- Card data ---
    @wire(getSiblings, { caseId: '$recordId' })
    wiredRows({ data, error }) {
        this.loading = false;
        if (data) {
            this.rows = data.map(r => ({ ...r, url: '/' + r.Id }));
        } else {
            this.rows = [];
        }
    }

    // --- UI helpers for card ---
    get hasRows() { return (this.rows?.length || 0) > 0; }
    get title() {
        const n = this.rows?.length || 0;
        return `Related Orders with Same Registration Number (${n})`;
    }
    get chevronIcon() { return this.collapsed ? 'utility:chevrondown' : 'utility:chevronright'; }
    toggleCollapse = () => { this.collapsed = !this.collapsed; };

    // --- View All modal ---
    openViewAll = async () => {
        this.showModal = true;
        this.loadingAll = true;
        try {
            const data = await getAllByRegistration({ caseId: this.recordId });
            this.allRows = (data || []).map(r => ({ ...r, url: '/' + r.Id }));
        } catch (e) {
            this.allRows = [];
        } finally {
            this.loadingAll = false;
        }
    };

    closeModal = () => {
        this.showModal = false;
        this.allRows = [];
    };

    get hasAllRows() { return (this.allRows?.length || 0) > 0; }
}