import { LightningElement, api, wire } from 'lwc';

import getEnterpriseActivities
    from '@salesforce/apex/EnterpriseActivityController.getEnterpriseActivities';

import { refreshApex } from '@salesforce/apex';

import { ShowToastEvent }
    from 'lightning/platformShowToastEvent';

const COLUMNS = [
    {
        label: 'Subject',
        fieldName: 'activityUrl',
        type: 'url',
        sortable: true,
        wrapText: true,
        typeAttributes: {
            label: {
                fieldName: 'subject'
            },
            target: '_self',
            tooltip: {
                fieldName: 'subject'
            }
        }
    },
    {
        label: 'Activity Type',
        fieldName: 'activityType',
        type: 'text',
        sortable: true
    },
    {
        label: 'Customer Location',
        fieldName: 'accountUrl',
        type: 'url',
        sortable: true,
        wrapText: true,
        typeAttributes: {
            label: {
                fieldName: 'relatedAccountName'
            },
            target: '_self',
            tooltip: {
                fieldName: 'relatedAccountName'
            }
        }
    },
    {
        label: 'Activity Date',
        fieldName: 'activityDateTime',
        type: 'date',
        sortable: true,
        typeAttributes: {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        }
    },
    {
        label: 'Status',
        fieldName: 'displayStatus',
        type: 'text',
        sortable: true
    },
    {
        label: 'Assigned To',
        fieldName: 'ownerName',
        type: 'text',
        sortable: true
    },
    {
        label: 'Contact/Lead',
        fieldName: 'whoName',
        type: 'text',
        sortable: true
    },
    {
        label: 'Location',
        fieldName: 'location',
        type: 'text',
        sortable: true
    }
];

export default class EnterpriseActivities
    extends LightningElement {

    @api recordId;

    columns = COLUMNS;

    activities = [];

    displayComponent = false;
    isEnterpriseView = false;
    resultLimitReached = false;

    relatedAccountCount = 0;
    totalActivityCount = 0;
    taskCount = 0;
    eventCount = 0;

    isLoading = true;
    errorMessage;

    sortedBy = 'activityDateTime';
    sortDirection = 'desc';

    wiredResponse;

    @wire(getEnterpriseActivities, {
        accountId: '$recordId'
    })
    wiredEnterpriseActivities(result) {
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

        this.isEnterpriseView =
            Boolean(data.isEnterpriseView);

        this.resultLimitReached =
            Boolean(data.resultLimitReached);

        this.relatedAccountCount =
            data.relatedAccountCount || 0;

        this.totalActivityCount =
            data.totalActivityCount || 0;

        this.taskCount =
            data.taskCount || 0;

        this.eventCount =
            data.eventCount || 0;

        this.activities =
            (data.activities || []).map(
                activity => ({
                    ...activity,

                    activityUrl:
                        `/lightning/r/` +
                        `${activity.activityType}/` +
                        `${activity.activityId}/view`,

                    accountUrl:
                        `/lightning/r/Account/` +
                        `${activity.relatedAccountId}/view`,

                    displayStatus:
                        activity.activityType === 'Task'
                            ? activity.status
                            : 'Scheduled'
                })
            );

        this.isLoading = false;
    }

    handleError(error) {
        this.displayComponent = true;
        this.activities = [];
        this.errorMessage =
            this.reduceError(error);
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

    get hasActivities() {
        return this.activities.length > 0;
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    get title() {
        return (
            `Enterprise Activities ` +
            `(${this.totalActivityCount})`
        );
    }

    get footerSummary() {
        const accountLabel =
            this.relatedAccountCount === 1
                ? 'location'
                : 'locations';

        return (
            `${this.totalActivityCount} Activities ` +
            `across ${this.relatedAccountCount} ` +
            `${accountLabel}`
        );
    }

    async handleRefresh() {
        this.isLoading = true;

        try {
            await refreshApex(
                this.wiredResponse
            );

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message:
                        'Enterprise Activities refreshed.',
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

        this.activities =
            [...this.activities].sort(
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
            sortDirection === 'asc'
                ? 1
                : -1;

        return (
            firstRecord,
            secondRecord
        ) => {
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