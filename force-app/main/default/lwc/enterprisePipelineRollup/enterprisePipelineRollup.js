import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getEnterprisePipeline from '@salesforce/apex/EnterprisePipelineController.getEnterprisePipeline';

const OPPORTUNITY_COLUMNS = [
    {
        label: 'Opportunity',
        fieldName: 'opportunityUrl',
        type: 'url',
        sortable: true,
        typeAttributes: {
            label: { fieldName: 'opportunityName' },
            target: '_blank'
        }
    },
    {
        label: 'Customer Location',
        fieldName: 'accountUrl',
        type: 'url',
        sortable: true,
        typeAttributes: {
            label: { fieldName: 'accountName' },
            target: '_blank'
        }
    },
    {
        label: 'Stage',
        fieldName: 'stageName',
        type: 'text',
        sortable: true
    },
    {
        label: 'Amount',
        fieldName: 'amount',
        type: 'currency',
        sortable: true,
        cellAttributes: { alignment: 'left' }
    },
    {
        label: 'Close Date',
        fieldName: 'closeDate',
        type: 'date-local',
        sortable: true
    },
    {
        label: 'Owner',
        fieldName: 'ownerName',
        type: 'text',
        sortable: true
    }
];

const STAGE_COLUMNS = [
    {
        label: 'Stage',
        fieldName: 'stageName',
        type: 'text'
    },
    {
        label: 'Opportunities',
        fieldName: 'opportunityCount',
        type: 'number',
        cellAttributes: { alignment: 'left' }
    },
    {
        label: 'Amount',
        fieldName: 'totalAmount',
        type: 'currency',
        cellAttributes: { alignment: 'left' }
    }
];

export default class EnterprisePipelineRollup extends LightningElement {
    @api recordId;

    pipelineSummary;
    wiredPipelineResult;
    isRefreshing = false;
    sortedBy = 'closeDate';
    defaultSortDirection = 'asc';
    sortDirection = 'asc';

    opportunityColumns = OPPORTUNITY_COLUMNS;
    stageColumns = STAGE_COLUMNS;

    @wire(getEnterprisePipeline, { accountId: '$recordId' })
    wiredEnterprisePipeline(result) {
        this.wiredPipelineResult = result;
        const { data, error } = result;

        if (data) {
            this.pipelineSummary = data;
        } else if (error) {
            this.pipelineSummary = null;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error loading enterprise pipeline',
                    message: this.reduceErrors(error),
                    variant: 'error'
                })
            );
        }
    }

    get isEligible() {
        return this.pipelineSummary?.isEligible === true;
    }

    get childAccountCount() {
        return this.pipelineSummary?.childAccountCount ?? 0;
    }

    get opportunityCount() {
        return this.pipelineSummary?.opportunityCount ?? 0;
    }

    get totalPipelineAmount() {
        return this.pipelineSummary?.totalPipelineAmount ?? 0;
    }

    get hasChildAccounts() {
        return this.childAccountCount > 0;
    }

    get hasOpportunities() {
        return this.opportunityCount > 0;
    }

    get hasStageSummaries() {
        return (this.pipelineSummary?.stageSummaries?.length ?? 0) > 0;
    }

    get opportunityRows() {
        return (this.pipelineSummary?.opportunities ?? []).map((row) => ({
            ...row,
            opportunityUrl: `/${row.opportunityId}`,
            accountUrl: row.accountId ? `/${row.accountId}` : null
        }));
    }

    get stageRows() {
        return this.pipelineSummary?.stageSummaries ?? [];
    }

    get ineligibleMessage() {
        const accountType = this.pipelineSummary?.accountType;
        return accountType
            ? `Enterprise pipeline roll-up is available only for IDN and GPO Accounts. This Account type is ${accountType}.`
            : 'Enterprise pipeline roll-up is available only for IDN and GPO Accounts.';
    }

    get emptyRelationshipMessage() {
        return 'No related customer locations were found for this enterprise Account.';
    }

    get emptyPipelineMessage() {
        return 'No open Opportunities were found across related customer locations.';
    }

    async handleRefresh() {
        if (this.isRefreshing || !this.wiredPipelineResult) {
            return;
        }

        this.isRefreshing = true;

        try {
            await refreshApex(this.wiredPipelineResult);
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error refreshing enterprise pipeline',
                    message: this.reduceErrors(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isRefreshing = false;
        }
    }

    handleSort(event) {
        this.sortedBy = event.detail.fieldName;
        this.sortDirection = event.detail.sortDirection;
    }

    reduceErrors(error) {
        if (!error) {
            return 'Unknown error';
        }

        if (Array.isArray(error.body)) {
            return error.body.map((item) => item.message).join(', ');
        }

        if (typeof error.body?.message === 'string') {
            return error.body.message;
        }

        if (typeof error.message === 'string') {
            return error.message;
        }

        return 'Unknown error';
    }
}