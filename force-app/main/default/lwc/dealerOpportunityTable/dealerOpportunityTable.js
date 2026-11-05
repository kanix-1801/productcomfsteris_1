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

const COLUMNS = {
    recent: [
        { field: 'Name', label: 'Opportunity Name', type: 'name' },
        { field: 'EndCustomerName__c', label: 'End Customer Name', type: 'text', value: 'endCustomerName' },
        { field: 'StageName', label: 'Opportunity Stage', type: 'stage' },
        { field: 'Amount', label: 'Opportunity Amount', type: 'amount' },
        { field: 'Expected_Ship_Date__c', label: 'Expected Ship Date', type: 'text', value: 'shipLabel' },
        { field: 'CreatedDate', label: 'Created Date', type: 'text', value: 'createdLabel' }
    ],
    pastdue: [
        { field: 'Name', label: 'Opportunity Name', type: 'name' },
        { field: 'EndCustomerName__c', label: 'End Customer Name', type: 'text', value: 'endCustomerName' },
        { field: 'StageName', label: 'Opportunity Stage', type: 'stage' },
        { field: 'Expected_Ship_Date__c', label: 'Expected Ship Date', type: 'text', value: 'shipLabel' },
        { field: 'Amount', label: 'Opportunity Amount', type: 'amount' }
    ],
    workspace: [
        { field: 'Name', label: 'Opportunity Name', type: 'name' },
        { field: 'EndCustomerName__c', label: 'Customer', type: 'text', value: 'endCustomerName' },
        { field: 'DealerAccountName__c', label: 'Dealer Account', type: 'text', value: 'dealerAccountName' },
        { field: 'StageName', label: 'Stage', type: 'stage' },
        { field: 'CloseDate', label: 'Close Date', type: 'text', value: 'closeLabel' },
        { field: 'Amount', label: 'Amount', type: 'amount' }
    ]
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

    get tableClass() {
        return this.variant === 'workspace' ? 'opportunity-table table-workspace' : 'opportunity-table';
    }

    get columns() {
        const canSort = this.variant === 'workspace';
        return this.columnDefinitions.map((column) => {
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
                headerClass: column.type === 'amount' ? 'amount-column' : ''
            };
        });
    }

    get columnDefinitions() {
        return COLUMNS[this.variant] || COLUMNS.workspace;
    }

    get displayRows() {
        return (this.records || []).map((row) => {
            const formatted = {
                name: row.name,
                endCustomerName: row.endCustomerName || '—',
                dealerAccountName: row.dealerAccountName || '—',
                stageName: row.stageName,
                stageClass: `stage-pill ${STAGE_CLASS[row.stageName] || 'stage-cancelled'}`,
                amountLabel: formatAmount(row.amount, row.currencyCode),
                closeLabel: formatDate(row.closeDate),
                createdLabel: formatDate(row.createdDate),
                shipLabel: formatDate(row.expectedShipDate)
            };
            return {
                opportunityId: row.opportunityId,
                cells: this.columnDefinitions.map((column) => buildCell(row.opportunityId, column, formatted))
            };
        });
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

function buildCell(opportunityId, column, formatted) {
    const isName = column.type === 'name';
    const isStage = column.type === 'stage';
    const isAmount = column.type === 'amount';
    const value = isName
        ? formatted.name
        : isStage
            ? formatted.stageName
            : isAmount
                ? formatted.amountLabel
                : formatted[column.value];
    return {
        key: `${opportunityId}-${column.field}`,
        opportunityId,
        value: value || '—',
        title: value || '',
        isName,
        isStage,
        isPlain: !isName && !isStage,
        stageClass: formatted.stageClass,
        cellClass: isAmount ? 'amount-column' : ''
    };
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