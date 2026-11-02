import { LightningElement, api, wire } from 'lwc';

import getChildAccountOpportunities
    from '@salesforce/apex/ChildAccountOpportunityController.getChildAccountOpportunities';

import { refreshApex } from '@salesforce/apex';

import { ShowToastEvent }
    from 'lightning/platformShowToastEvent';

const COLUMNS = [
    {
        label: 'Opportunity Name',
        fieldName: 'opportunityUrl',
        type: 'url',
        sortable: true,
        wrapText: true,
        typeAttributes: {
            label: {
                fieldName: 'opportunityName'
            },
            target: '_self',
            tooltip: {
                fieldName: 'opportunityName'
            }
        }
    },
    {
        label: 'Customer Name',
        fieldName: 'accountUrl',
        type: 'url',
        sortable: true,
        wrapText: true,
        typeAttributes: {
            label: {
                fieldName: 'accountName'
            },
            target: '_self',
            tooltip: {
                fieldName: 'accountName'
            }
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
        typeAttributes: {
            currencyDisplayAs: 'symbol'
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
        fieldName: 'ownerName',
        type: 'text',
        sortable: true
    }
];

export default class ChildAccountOpportunities
    extends LightningElement {

    @api recordId;

    columns = COLUMNS;

    opportunities = [];

    displayComponent = false;
    resultLimitReached = false;

    childAccountCount = 0;
    totalOpportunityCount = 0;

    isLoading = true;
    errorMessage;

    sortedBy = 'closeDate';
    sortDirection = 'asc';

    wiredResponse;

    @wire(getChildAccountOpportunities, {
        accountId: '$recordId'
    })
    wiredChildOpportunities(result) {
        this.wiredResponse = result;

        const { data, error } = result;

        if (data) {
            this.handleData(data);
        } else if (error) {
            this.handleError(error);
        }
    }

    handleData(data) {
        this.errorMessage = undefined;

        this.displayComponent =
            Boolean(data.displayComponent);

        this.resultLimitReached =
            Boolean(data.resultLimitReached);

        this.childAccountCount =
            data.childAccountCount || 0;

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
                        `${opportunity.accountId}/view`
                })
            );

        this.isLoading = false;
    }

    handleError(error) {
        /*
         * Display the section when an error occurs so the user can see
         * the actual issue rather than having the component disappear.
         */
        this.displayComponent = true;
        this.opportunities = [];
        this.errorMessage = this.reduceError(error);
        this.isLoading = false;
    }

    get shouldDisplayComponent() {
        return this.displayComponent || this.hasError;
    }

    get hasSuccessfulResponse() {
        return (
            !this.isLoading &&
            !this.hasError &&
            this.displayComponent
        );
    }

    get hasOpportunities() {
        return this.opportunities.length > 0;
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    get title() {
        return (
            `Child Account Opportunities ` +
            `(${this.totalOpportunityCount})`
        );
    }

    async handleRefresh() {
        this.isLoading = true;

        try {
            await refreshApex(this.wiredResponse);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message:
                        'Child Account Opportunities refreshed.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.handleError(error);
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

    createSortFunction(
        fieldName,
        sortDirection
    ) {
        const direction =
            sortDirection === 'asc' ? 1 : -1;

        return (firstRecord, secondRecord) => {
            const firstValue =
                this.normalizeSortValue(
                    firstRecord[fieldName]
                );

            const secondValue =
                this.normalizeSortValue(
                    secondRecord[fieldName]
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

    normalizeSortValue(value) {
        if (
            value === null ||
            value === undefined
        ) {
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

        if (
            typeof error?.body?.message === 'string'
        ) {
            return error.body.message;
        }

        if (
            typeof error?.message === 'string'
        ) {
            return error.message;
        }

        return 'An unexpected error occurred.';
    }
}