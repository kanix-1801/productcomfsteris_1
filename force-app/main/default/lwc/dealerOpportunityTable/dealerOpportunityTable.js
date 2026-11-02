import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

const STAGE_CLASS = {
    Discovery: 'stage-discovery',
    Evaluation: 'stage-evaluation',
    Proposal: 'stage-proposal',
    Commit: 'stage-commit',
    'Closed Won': 'stage-closed-won',
    'Closed Lost': 'stage-closed-lost',
    Cancelled: 'stage-cancelled',
    'Closed-No Bid': 'stage-cancelled'
};

export default class DealerOpportunityTable extends NavigationMixin(LightningElement) {
    @api records = [];
    @api variant = 'workspace';
    @api emptyMessage = 'No opportunities found.';
    @api sortField = 'Name';
    @api sortDirection = 'ASC';

    get hasRows() {
        return this.displayRows.length > 0;
    }

    get showShipDate() {
        return this.variant === 'pastdue';
    }

    get showCreatedDate() {
        return this.variant === 'recent';
    }

    get showCloseDate() {
        return this.variant === 'recent' || this.variant === 'workspace';
    }

    get tableClass() {
        return this.variant === 'workspace' ? 'opportunity-table table-workspace' : 'opportunity-table';
    }

    get columns() {
        const columns = [
            { field: 'Name', label: 'Opportunity Name' },
            { field: 'EndCustomerName__c', label: 'Customer' },
            { field: 'DealerAccountName__c', label: 'Dealer Account' },
            { field: 'StageName', label: 'Stage' }
        ];
        if (this.showShipDate) {
            columns.push({ field: 'Expected_Ship_Date__c', label: 'Expected Ship Date', sortable: false });
        }
        if (this.showCreatedDate) {
            columns.push({ field: 'CreatedDate', label: 'Created Date', sortable: false });
        }
        if (this.showCloseDate) {
            columns.push({ field: 'CloseDate', label: 'Close Date' });
        }
        columns.push({ field: 'Amount', label: 'Amount', amount: true });
        const canSort = this.variant === 'workspace';
        return columns.map((column) => {
            const sortable = canSort && column.sortable !== false;
            let sortLabel = '';
            if (sortable) {
                sortLabel = this.sortField === column.field
                    ? (this.sortDirection === 'DESC' ? '↓' : '↑')
                    : '↕';
            }
            return {
                ...column,
                sortable,
                sortLabel,
                headerClass: column.amount ? 'amount-column' : ''
            };
        });
    }

    get displayRows() {
        return (this.records || []).map((row) => ({
            ...row,
            stageClass: `stage-pill ${STAGE_CLASS[row.stageName] || 'stage-cancelled'}`,
            amountLabel: formatAmount(row.amount, row.currencyCode),
            closeLabel: formatDate(row.closeDate),
            createdLabel: formatDate(row.createdDate),
            shipLabel: formatDate(row.expectedShipDate),
            endCustomerName: row.endCustomerName || '—',
            dealerAccountName: row.dealerAccountName || '—'
        }));
    }

    requestSort(event) {
        this.dispatchEvent(new CustomEvent('sort', {
            detail: { field: event.currentTarget.dataset.field }
        }));
    }

    openOpportunity(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: event.currentTarget.dataset.id,
                objectApiName: 'Opportunity',
                actionName: 'view'
            }
        });
    }
}

function formatAmount(amount, currencyCode) {
    if (amount === null || amount === undefined) {
        return '—';
    }
    return new Intl.NumberFormat('en-US', {
        style: 'currency',
        currency: currencyCode || 'USD',
        maximumFractionDigits: 0
    }).format(amount);
}

function formatDate(value) {
    if (!value) {
        return '—';
    }
    const [year, month, day] = value.split('-');
    return `${month}/${day}/${year}`;
}