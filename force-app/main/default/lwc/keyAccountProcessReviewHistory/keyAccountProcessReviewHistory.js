/**
 * @description
 * GC-2615 - Displays Account-scoped Key Account Process Review history.
 * Customer and Address Accounts show direct reviews; IDNs show reviews for AAR children.
 */
import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getProcessReviewHistory
    from '@salesforce/apex/KeyAccountProcessReviewHistoryController.getProcessReviewHistory';

const COLUMNS = [
    {
        label: 'Process Review',
        fieldName: 'reviewUrl',
        type: 'url',
        sortable: true,
        initialWidth: 160,
        wrapText: true,
        typeAttributes: {
            label: { fieldName: 'reviewName' },
            target: '_self',
            tooltip: { fieldName: 'reviewName' }
        }
    },
    {
        label: 'Customer Account / Facility',
        fieldName: 'accountUrl',
        type: 'url',
        sortable: true,
        initialWidth: 250,
        wrapText: true,
        typeAttributes: {
            label: { fieldName: 'accountName' },
            target: '_self',
            tooltip: { fieldName: 'accountName' }
        }
    },
    {
        label: 'Assessment Date',
        fieldName: 'assessmentDate',
        type: 'date-local',
        sortable: true,
        initialWidth: 160,
        wrapText: true
    },
    {
        label: 'Department',
        fieldName: 'department',
        type: 'text',
        sortable: true,
        initialWidth: 180,
        wrapText: true
    },
    {
        label: 'Clinical User',
        fieldName: 'clinicalUser',
        type: 'text',
        sortable: true,
        initialWidth: 180,
        wrapText: true
    },
    {
        label: 'Customer Champion',
        fieldName: 'customerChampionUrl',
        type: 'url',
        sortable: true,
        initialWidth: 210,
        wrapText: true,
        typeAttributes: {
            label: { fieldName: 'customerChampionName' },
            target: '_self',
            tooltip: { fieldName: 'customerChampionName' }
        }
    },
    {
        label: 'Ship-To / Address',
        fieldName: 'shipToAddressUrl',
        type: 'url',
        sortable: true,
        initialWidth: 220,
        wrapText: true,
        typeAttributes: {
            label: { fieldName: 'shipToAddressName' },
            target: '_self',
            tooltip: { fieldName: 'shipToAddressName' }
        }
    },
    {
        label: 'Completed',
        fieldName: 'completed',
        type: 'boolean',
        sortable: true,
        initialWidth: 130,
        wrapText: true,
    }
];

export default class KeyAccountProcessReviewHistory extends LightningElement {
    @api recordId;

    columns = COLUMNS;
    reviews = [];
    totalReviewCount = 0;
    relatedAccountCount = 0;
    isIdnView = false;
    resultLimitReached = false;
    isLoading = true;
    errorMessage;
    sortedBy = 'assessmentDate';
    sortDirection = 'desc';
    wiredResponse;

    @wire(getProcessReviewHistory, { accountId: '$recordId' })
    wiredProcessReviewHistory(result) {
        this.wiredResponse = result;
        const { data, error } = result;

        if (data) {
            this.errorMessage = undefined;
            this.totalReviewCount = data.totalReviewCount || 0;
            this.relatedAccountCount = data.relatedAccountCount || 0;
            this.isIdnView = Boolean(data.isIdnView);
            this.resultLimitReached = Boolean(data.resultLimitReached);
            this.reviews = (data.reviews || []).map((review) => this.toDatatableRow(review));
            this.isLoading = false;
        } else if (error) {
            this.reviews = [];
            this.errorMessage = this.reduceError(error);
            this.isLoading = false;
        }
    }

    toDatatableRow(review) {
        return {
            reviewId: review.Id,
            reviewName: review.Name,
            reviewUrl: this.buildRecordUrl('KeyAccountProcessReview__c', review.Id),
            assessmentDate: review.AssessmentDate__c,
            accountId: review.CustomerAccountOrfacility__c,
            accountName: review.CustomerAccountOrfacility__r?.Name,
            accountUrl: this.buildRecordUrl('Account', review.CustomerAccountOrfacility__c),
            department: review.Department__c,
            clinicalUser: review.ClinicalUser__c,
            customerChampionName: review.CustomerChampion__r?.Name,
            customerChampionUrl: this.buildRecordUrl('Contact', review.CustomerChampion__c),
            shipToAddressName: review.ShipToAddress__r?.Name,
            shipToAddressUrl: this.buildRecordUrl('Account', review.ShipToAddress__c),
            completed: review.Completed__c
        };
    }

    buildRecordUrl(objectApiName, recordId) {
        return recordId ? `/lightning/r/${objectApiName}/${recordId}/view` : undefined;
    }

    get title() {
        return `Key Account Process Reviews (${this.totalReviewCount})`;
    }

    get hasReviews() {
        return this.reviews.length > 0;
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    get showEmptyState() {
        return !this.isLoading && !this.hasError && !this.hasReviews;
    }

    get scopeSummary() {
        if (!this.isIdnView) {
            return 'Process Reviews associated with this Account.';
        }

        const accountLabel = this.relatedAccountCount === 1 ? 'AAR child Account' : 'AAR child Accounts';
        return `Process Reviews across ${this.relatedAccountCount} ${accountLabel}.`;
    }

    async handleRefresh() {
        this.isLoading = true;

        try {
            await refreshApex(this.wiredResponse);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Key Account Process Review history refreshed.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        this.sortedBy = fieldName;
        this.sortDirection = sortDirection;
        this.reviews = [...this.reviews].sort(
            this.createSortFunction(fieldName, sortDirection)
        );
    }

    createSortFunction(fieldName, sortDirection) {
        const direction = sortDirection === 'asc' ? 1 : -1;

        return (firstRecord, secondRecord) => {
            const firstValue = this.normalizeSortValue(
                this.getSortValue(firstRecord, fieldName)
            );
            const secondValue = this.normalizeSortValue(
                this.getSortValue(secondRecord, fieldName)
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
        const linkedFieldLabels = {
            reviewUrl: 'reviewName',
            accountUrl: 'accountName',
            customerChampionUrl: 'customerChampionName',
            shipToAddressUrl: 'shipToAddressName'
        };
        return record[linkedFieldLabels[fieldName] || fieldName];
    }

    normalizeSortValue(value) {
        if (value === null || value === undefined) {
            return '';
        }
        return typeof value === 'string' ? value.toLowerCase() : value;
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unable to load Process Review history.';
    }
}