import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import STATUS_FIELD from '@salesforce/schema/ReturnOrder.Status';
import getStatusPicklistValues from '@salesforce/apex/ReturnOrderPathController.getStatusPicklistValues';

const FIELDS = [STATUS_FIELD];

export default class ReturnOrderPath extends LightningElement {
    @api recordId;

    currentStatus;
    statusOptions = [];
    recordError;
    picklistError;
    recordLoaded = false;
    picklistLoaded = false;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data, error }) {
        if (data) {
            this.currentStatus = getFieldValue(data, STATUS_FIELD);
            this.recordError = undefined;
            this.recordLoaded = true;
        } else if (error) {
            this.recordError = error;
            this.recordLoaded = true;
        }
    }

    @wire(getStatusPicklistValues)
    wiredStatusPicklist({ data, error }) {
        if (data) {
            this.statusOptions = data.map((entry) => ({
                label: entry.label,
                value: entry.value
            }));
            this.picklistError = undefined;
            this.picklistLoaded = true;
        } else if (error) {
            this.picklistError = error;
            this.picklistLoaded = true;
        }
    }

    get isLoading() {
        return !this.recordLoaded || !this.picklistLoaded;
    }

    get hasPath() {
        return this.statusOptions.length > 0;
    }

    get showEmptyState() {
        return this.recordLoaded && this.picklistLoaded && !this.hasPath;
    }

    get errorMessage() {
        const error = this.recordError || this.picklistError;
        if (!error) {
            return null;
        }
        return error.body?.message || error.message || 'Unable to load return order status path.';
    }

    get pathSteps() {
        if (!this.statusOptions.length) {
            return [];
        }

        const currentIndex = this.getStatusIndex(this.currentStatus);

        return this.statusOptions.map((option, index) => {
            const isComplete = currentIndex > -1 && index < currentIndex;
            const isCurrent = option.value === this.currentStatus;

            let className = 'path-nav-item';
            if (isComplete) {
                className += ' path-complete';
            } else if (isCurrent) {
                className += ' path-current';
            } else {
                className += ' path-incomplete';
            }

            return {
                ...option,
                className,
                showCheck: isComplete
            };
        });
    }

    getStatusIndex(statusValue) {
        return this.statusOptions.findIndex((option) => option.value === statusValue);
    }
}