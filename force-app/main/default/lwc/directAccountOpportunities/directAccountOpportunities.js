import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDirectOpportunities
    from '@salesforce/apex/OpportunityRelatedListController.getDirectOpportunities';

const COLUMNS = [
    {
        label: 'Opportunity Name',
        fieldName: 'opportunityUrl',
        type: 'url',
        sortable: true,
        wrapText: true,
        typeAttributes: {
            label: { fieldName: 'opportunityName' },
            target: '_self',
            tooltip: { fieldName: 'opportunityName' }
        }
    },
    {
        label: 'Customer Name',
        fieldName: 'accountUrl',
        type: 'url',
        sortable: true,
        wrapText: true,
        typeAttributes: {
            label: { fieldName: 'accountName' },
            target: '_self',
            tooltip: { fieldName: 'accountName' }
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
        cellAttributes: {
            alignment: 'right'
        },
        typeAttributes: {
            currencyDisplayAs: 'symbol',
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        }
    },
    {
        label: 'Close Date',
        fieldName: 'closeDate',
        type: 'date-local',
        sortable: true,
        typeAttributes: {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit'
        }
    },
    {
        label: 'Opportunity Owner',
        fieldName: 'ownerUrl',
        type: 'url',
        sortable: true,
        wrapText: true,
        typeAttributes: {
            label: { fieldName: 'ownerName' },
            target: '_self',
            tooltip: { fieldName: 'ownerName' }
        }
    }
];

export default class DirectAccountOpportunities
    extends NavigationMixin(LightningElement) {

    @api recordId;

    columns = COLUMNS;
    opportunities = [];
    totalOpportunityCount = 0;
    errorMessage;
    isLoading = true;
    sortedBy = 'closeDate';
    sortDirection = 'asc';
    wiredResponse;

    @wire(getDirectOpportunities, {
        accountId: '$recordId'
    })
    wiredDirectOpportunities(result) {
        this.wiredResponse = result;
        const { data, error } = result;

        if (data) {
            this.processData(data);
        } else if (error) {
            this.processError(error);
        }
    }

    processData(data) {
        this.errorMessage = undefined;
        this.totalOpportunityCount =
            data.totalOpportunityCount || 0;

        this.opportunities =
            (data.opportunities || []).map(
                opportunity => ({
                    ...opportunity,
                    opportunityUrl:
                        `/lightning/r/Opportunity/` +
                        `${opportunity.opportunityId}/view`,
                    accountUrl:
                        `/lightning/r/Account/` +
                        `${opportunity.accountId}/view`,
                    ownerUrl:
                        `/lightning/r/User/` +
                        `${opportunity.ownerId}/view`
                })
            );

        this.isLoading = false;
    }

    processError(error) {
        this.opportunities = [];
        this.totalOpportunityCount = 0;
        this.errorMessage = this.reduceError(error);
        this.isLoading = false;
    }

    get title() {
        return `Opportunities (${this.totalOpportunityCount})`;
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    get hasSuccessfulResponse() {
        return !this.isLoading && !this.hasError;
    }

    get hasOpportunities() {
        return this.opportunities.length > 0;
    }

    handleNewOpportunity() {
        if (!this.recordId) {
            return;
        }

        const defaultFieldValues =
            encodeDefaultFieldValues({
                AccountId: this.recordId
            });

        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Opportunity',
                actionName: 'new'
            },
            state: {
                defaultFieldValues
            }
        });
    }

    async handleRefresh() {
        if (!this.wiredResponse) {
            return;
        }

        this.isLoading = true;

        try {
            await refreshApex(this.wiredResponse);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Opportunities refreshed.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.processError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleSort(event) {
        const {
            fieldName,
            sortDirection
        } = event.detail;

        this.sortedBy = fieldName;
        this.sortDirection = sortDirection;

        this.opportunities =
            [...this.opportunities].sort(
                this.createSortFunction(
                    fieldName,
                    sortDirection
                )
            );
    }

    createSortFunction(fieldName, sortDirection) {
        const direction =
            sortDirection === 'asc' ? 1 : -1;

        return (firstRecord, secondRecord) => {
            const firstValue =
                this.getSortValue(
                    firstRecord,
                    fieldName
                );

            const secondValue =
                this.getSortValue(
                    secondRecord,
                    fieldName
                );

            if (firstValue > secondValue) {
                return direction;
            }

            if (firstValue < secondValue) {
                return -direction;
            }

            return 0;
        };
    }

    getSortValue(record, fieldName) {
        let value;

        if (fieldName === 'opportunityUrl') {
            value = record.opportunityName;
        } else if (fieldName === 'accountUrl') {
            value = record.accountName;
        } else if (fieldName === 'ownerUrl') {
            value = record.ownerName;
        } else {
            value = record[fieldName];
        }

        if (value === null || value === undefined) {
            return '';
        }

        return typeof value === 'string'
            ? value.toLowerCase()
            : value;
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body
                .map(item => item.message)
                .join(', ');
        }

        return (
            error?.body?.message ||
            error?.message ||
            'Unable to load Opportunities.'
        );
    }
}