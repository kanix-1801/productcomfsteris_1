import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import { RefreshEvent } from 'lightning/refresh';
import { CurrentPageReference } from 'lightning/navigation';
import {
    publish,
    MessageContext
} from 'lightning/messageService';
import GENERATE_QUOTE_REFRESH from '@salesforce/messageChannel/generateQuoteRefresh__c';
import getQuotes from '@salesforce/apex/UpdateForecastEligibleQuoteController.getQuotes';
import saveForecastEligibleQuotes from '@salesforce/apex/UpdateForecastEligibleQuoteController.saveForecastEligibleQuotes';

const AT_LEAST_ONE_FORECAST_ELIGIBLE_MESSAGE =
    'At least one Quote must be selected as Forecast Eligible.';

export default class UpdateForecastEligibleQuotes extends LightningElement {
    @api recordId;

    @track quoteRows = [];
    isLoading = true;
    isSaving = false;
    pageRecordId;
    initialized = false;
    messageContext;

    @wire(MessageContext)
    wiredMessageContext(context) {
        this.messageContext = context;
    }

    @wire(CurrentPageReference)
    wiredPageReference(pageRef) {
        if (pageRef?.state?.recordId) {
            this.pageRecordId = pageRef.state.recordId;
        }
        this.tryInitialize();
    }

    connectedCallback() {
        this.tryInitialize();
    }

    get effectiveRecordId() {
        return this.recordId || this.pageRecordId;
    }

    tryInitialize() {
        if (this.initialized || !this.effectiveRecordId) {
            return;
        }

        this.initialized = true;
        this.loadQuotes();
    }

    get hasQuotes() {
        return this.quoteRows.length > 0;
    }

    get isProceedDisabled() {
        return this.isLoading || this.isSaving || !this.hasQuotes;
    }

    get proceedButtonLabel() {
        return this.isSaving ? 'Saving...' : 'Proceed';
    }

    async loadQuotes() {
        if (!this.effectiveRecordId) {
            this.isLoading = false;
            return;
        }

        this.isLoading = true;

        try {
            const result = await getQuotes({ opportunityId: this.effectiveRecordId });
            this.quoteRows = (result || []).map((quote) => this.buildRowViewModel(quote));
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
            this.closePanel(false);
        } finally {
            this.isLoading = false;
        }
    }

    buildRowViewModel(quote) {
        return {
            id: quote.id,
            quoteNumber: quote.quoteNumber || '',
            quoteName: quote.quoteName || '',
            status: quote.status || '—',
            approvalStatus: quote.approvalStatus || '—',
            lastModifiedDate: this.formatDateTime(quote.lastModifiedDate),
            quoteTotalWithoutFreight: this.formatCurrency(quote.quoteTotalWithoutFreight),
            forecastEligible: quote.forecastEligible === true
        };
    }

    handleForecastEligibleChange(event) {
        const quoteId = event.currentTarget?.dataset?.id;
        const isChecked = event.detail?.checked === true;

        if (!quoteId) {
            return;
        }

        this.quoteRows = this.quoteRows.map((quote) => {
            if (!this.isSameRecordId(quote.id, quoteId)) {
                return quote;
            }

            return {
                ...quote,
                forecastEligible: isChecked
            };
        });
    }

    handleCancel() {
        this.closePanel(false);
    }

    async handleProceed() {
        if (!this.effectiveRecordId || !this.hasQuotes) {
            return;
        }

        if (!this.hasSelectedForecastEligibleQuote()) {
            this.showToast('Error', AT_LEAST_ONE_FORECAST_ELIGIBLE_MESSAGE, 'error');
            return;
        }

        this.isSaving = true;

        try {
            const updates = this.buildSavePayload();

            await saveForecastEligibleQuotes({
                opportunityId: this.effectiveRecordId,
                updatesJson: JSON.stringify(updates)
            });

            this.showToast('Success', 'Forecast Eligible quotes were updated.', 'success');
            this.closePanel(true);
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    buildSavePayload() {
        const payloadById = new Map();

        this.template.querySelectorAll('lightning-input[data-id]').forEach((input) => {
            const quoteId = input.dataset?.id;
            if (!quoteId) {
                return;
            }

            payloadById.set(String(quoteId).toLowerCase(), {
                quoteId,
                forecastEligible: input.checked === true
            });
        });

        if (payloadById.size > 0) {
            return Array.from(payloadById.values());
        }

        return this.quoteRows.map((quote) => ({
            quoteId: quote.id,
            forecastEligible: quote.forecastEligible === true
        }));
    }

    hasSelectedForecastEligibleQuote() {
        return this.quoteRows.some((quote) => quote.forecastEligible === true);
    }

    isSameRecordId(firstId, secondId) {
        if (!firstId || !secondId) {
            return false;
        }

        return String(firstId).toLowerCase() === String(secondId).toLowerCase();
    }

    notifyRecordPageRefresh() {
        if (!this.messageContext || !this.effectiveRecordId) {
            return;
        }

        publish(this.messageContext, GENERATE_QUOTE_REFRESH, {
            recordId: this.effectiveRecordId
        });
    }

    notifyOpportunityRecordRefresh() {
        if (!this.effectiveRecordId) {
            return;
        }

        getRecordNotifyChange([{ recordId: this.effectiveRecordId }]);
        this.dispatchEvent(new RefreshEvent());
    }

    closePanel(refreshRecordPage = false) {
        if (refreshRecordPage) {
            this.notifyOpportunityRecordRefresh();
            this.notifyRecordPageRefresh();
        }

        window.setTimeout(() => {
            this.dispatchEvent(new CloseActionScreenEvent());
        }, 0);
    }

    formatCurrency(value) {
        if (value === null || value === undefined || value === '') {
            return '—';
        }

        const amount = Number(value);
        if (Number.isNaN(amount)) {
            return value;
        }

        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        }).format(amount);
    }

    formatDateTime(dateValue) {
        if (!dateValue) {
            return '—';
        }

        try {
            const dateTimeValue = new Date(dateValue);
            return new Intl.DateTimeFormat('en-US', {
                year: 'numeric',
                month: 'numeric',
                day: 'numeric',
                hour: 'numeric',
                minute: '2-digit',
                hour12: true
            }).format(dateTimeValue);
        } catch (error) {
            return dateValue;
        }
    }

    reduceError(error) {
        if (!error) {
            return 'Unknown error';
        }

        if (Array.isArray(error.body)) {
            return error.body.map((entry) => entry.message).join(', ');
        }

        if (error.body && typeof error.body.message === 'string') {
            return error.body.message;
        }

        if (typeof error.message === 'string') {
            return error.message;
        }

        return 'Unexpected error occurred';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}