import { LightningElement, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import OPPORTUNITY_ICON from '@salesforce/resourceUrl/DealerOpportunityIcon';
import PIPELINE_ICON from '@salesforce/resourceUrl/DealerPipelineIcon';
import ACTIVE_ICON from '@salesforce/resourceUrl/DealerActiveIcon';
import getWorkspace from '@salesforce/apex/DealerOpportunityController.getWorkspace';

const STAGE_TABS = [
    'All',
    'Discovery',
    'Evaluation',
    'Proposal',
    'Commit',
    'Closed Won',
    'Closed Lost'
];

export default class DealerOpportunityWorkspace extends NavigationMixin(LightningElement) {
    opportunityIconUrl = OPPORTUNITY_ICON;
    pipelineIconUrl = PIPELINE_ICON;
    activeIconUrl = ACTIVE_ICON;
    workspace;
    errorMessage;
    selectedStage = 'All';
    search = '';
    sortField = 'Name';
    sortDirection = 'ASC';
    pastDueOnly = false;
    pageNumber = 1;
    isDealerFlowOpen = false;

    get keepPickerInSiteBundle() {
        return false;
    }

    @wire(CurrentPageReference)
    setPageReference(pageReference) {
        const pastDue = pageReference?.state?.pastDue === 'true';
        if (pastDue !== this.pastDueOnly) {
            this.pastDueOnly = pastDue;
            this.pageNumber = 1;
            this.loadWorkspace();
        }
    }

    connectedCallback() {
        this.loadWorkspace();
    }

    loadWorkspace() {
        getWorkspace({ filterJson: JSON.stringify(this.filter) })
            .then((workspace) => {
                this.workspace = workspace;
                this.errorMessage = null;
            })
            .catch((error) => {
                this.errorMessage = error?.body?.message || 'Unable to load opportunities.';
            });
    }

    get filter() {
        return {
            search: this.search,
            stageName: this.selectedStage === 'All' ? null : this.selectedStage,
            pastDueOnly: this.pastDueOnly,
            pageNumber: this.pageNumber,
            pageSize: 25,
            sortField: this.sortField,
            sortDirection: this.sortDirection
        };
    }

    get summary() {
        return this.workspace?.summary || {};
    }

    get opportunities() {
        return this.workspace?.opportunities || [];
    }

    get openPipelineLabel() {
        return compactCurrency(this.summary.openPipelineValue);
    }

    get openCountLabel() {
        return String(this.summary.openCount || 0);
    }

    get closedWonLabel() {
        return compactCurrency(this.summary.closedWonValue);
    }

    get stageTabs() {
        const counts = new Map((this.summary.stages || []).map((stage) => [stage.stageName, stage.recordCount]));
        return STAGE_TABS.map((stageName) => ({
            stageName,
            label: stageName === 'All' ? 'All' : stageName,
            recordCount: stageName === 'All' ? this.summary.totalCount || 0 : counts.get(stageName) || 0,
            className: stageName === this.selectedStage ? 'stage-tab stage-tab-active' : 'stage-tab'
        }));
    }

    get pageLabel() {
        const total = this.workspace?.totalCount || 0;
        if (total === 0) {
            return '0 opportunities';
        }
        const start = ((this.pageNumber - 1) * 25) + 1;
        const end = Math.min(this.pageNumber * 25, total);
        return `${start}–${end} of ${total}`;
    }

    get isFirstPage() {
        return this.pageNumber <= 1;
    }

    get isLastPage() {
        const total = this.workspace?.totalCount || 0;
        return this.pageNumber * 25 >= total;
    }

    selectStage(event) {
        this.selectedStage = event.currentTarget.dataset.stage;
        this.pastDueOnly = false;
        this.pageNumber = 1;
        this.loadWorkspace();
    }

    handleSearch(event) { this.updateFilter('search', event.target.value); }

    handleSort(event) {
        const fieldName = event.detail.field;
        if (this.sortField === fieldName) {
            this.sortDirection = this.sortDirection === 'ASC' ? 'DESC' : 'ASC';
        } else {
            this.sortField = fieldName;
            this.sortDirection = 'ASC';
        }
        this.pageNumber = 1;
        this.loadWorkspace();
    }

    updateFilter(fieldName, value) {
        this[fieldName] = value;
        this.pageNumber = 1;
        this.loadWorkspace();
    }

    previousPage() {
        if (!this.isFirstPage) {
            this.pageNumber -= 1;
            this.loadWorkspace();
        }
    }

    nextPage() {
        if (!this.isLastPage) {
            this.pageNumber += 1;
            this.loadWorkspace();
        }
    }

    openDealerFlow() {
        this.isDealerFlowOpen = true;
    }

    closeDealerFlow() {
        this.isDealerFlowOpen = false;
    }

    closeDealerFlowFromBackdrop() {
        this.closeDealerFlow();
    }

    stopDealerFlowClose(event) {
        event.stopPropagation();
    }

    handleDealerFlowStatusChange(event) {
        const status = event.detail && event.detail.status;
        if (status !== 'FINISHED' && status !== 'FINISHED_SCREEN') {
            return;
        }
        const recordId = outputValue(event.detail, 'createdOpportunityId');
        this.isDealerFlowOpen = false;
        if (!recordId) {
            this.loadWorkspace();
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: 'Opportunity',
                actionName: 'view'
            }
        });
    }

}

function outputValue(detail, name) {
    const outputs = detail && detail.outputVariables;
    if (!outputs) {
        return null;
    }
    const match = outputs.find((item) => item.name === name);
    return match && match.value ? match.value : null;
}

function compactCurrency(amount) {
    const value = Number(amount || 0);
    if (Math.abs(value) >= 1000) {
        const thousands = value / 1000;
        const digits = Math.abs(thousands) >= 10 ? 0 : 1;
        return `$${thousands.toFixed(digits).replace(/\.0$/, '')}K`;
    }
    return new Intl.NumberFormat('en-US', {
        style: 'currency',
        currency: 'USD',
        maximumFractionDigits: 0
    }).format(value);
}