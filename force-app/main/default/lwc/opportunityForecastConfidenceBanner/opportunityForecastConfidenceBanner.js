import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { getRecord, getFieldValue, getRecordNotifyChange } from 'lightning/uiRecordApi';
import { RefreshEvent } from 'lightning/refresh';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import {
    publish,
    subscribe,
    unsubscribe,
    MessageContext
} from 'lightning/messageService';
import GENERATE_QUOTE_REFRESH from '@salesforce/messageChannel/generateQuoteRefresh__c';
import getBannerContext from '@salesforce/apex/OppForecastConfBannerController.getBannerContext';
import propagateSelectedQuotes from '@salesforce/apex/OppForecastConfBannerController.propagateSelectedQuotes';
import FORECAST_CONFIDENCE_LEVEL from '@salesforce/schema/Opportunity.ForecastConfidenceLevel__c';
import SHOW_PROPAGATE_BANNER from '@salesforce/schema/Opportunity.ShowForecastConfidencePropagateBanner__c';
import PENDING_QUOTE_FORECAST_CONFIDENCE from '@salesforce/schema/Opportunity.PendingQuoteForecastConfidence__c';

const OPPORTUNITY_BANNER_FIELDS = [
    FORECAST_CONFIDENCE_LEVEL,
    SHOW_PROPAGATE_BANNER,
    PENDING_QUOTE_FORECAST_CONFIDENCE
];

const BANNER_TITLE = 'Forecast confidence has been updated';

export default class OpportunityForecastConfidenceBanner extends LightningElement {
    _recordId;
    sessionDismissed = false;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        if (value !== this._recordId) {
            this._recordId = value;
            this.sessionDismissed = false;
        }
    }

    bannerContext;
    quoteRows = [];
    wiredBannerContextResult;
    refreshSubscription;
    messageContext;
    isPropagating = false;
    showPropagateModal = false;
    lastKnownShowBanner;

    @wire(MessageContext)
    wiredMessageContext(context) {
        this.messageContext = context;
        this.trySubscribeRefreshChannel();
    }

    @wire(getRecord, { recordId: '$recordId', fields: OPPORTUNITY_BANNER_FIELDS })
    wiredOpportunityRecord(result) {
        if (!result.data) {
            return;
        }

        const showBanner = getFieldValue(result.data, SHOW_PROPAGATE_BANNER) === true;
        if (showBanner !== this.lastKnownShowBanner) {
            if (showBanner === true) {
                this.sessionDismissed = false;
            }
            this.lastKnownShowBanner = showBanner;
            this.refreshBannerState();
        }
    }

    @wire(getBannerContext, { opportunityId: '$recordId' })
    wiredBannerContext(result) {
        this.wiredBannerContextResult = result;

        if (result.data) {
            this.bannerContext = result.data;
            this.quoteRows = (result.data.quotes ?? []).map((quoteRow) => ({
                ...quoteRow,
                selected: quoteRow.selected === true
            }));
            this.lastKnownShowBanner = result.data.showBanner === true;
        } else if (result.error) {
            this.bannerContext = null;
            this.quoteRows = [];
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error loading banner',
                    message: this.reduceErrors(result.error),
                    variant: 'error'
                })
            );
        }
    }

    connectedCallback() {
        this.trySubscribeRefreshChannel();
    }

    disconnectedCallback() {
        if (this.refreshSubscription) {
            unsubscribe(this.refreshSubscription);
            this.refreshSubscription = null;
        }
    }

    trySubscribeRefreshChannel() {
        if (this.refreshSubscription || !this.messageContext || !this.recordId) {
            return;
        }

        this.refreshSubscription = subscribe(
            this.messageContext,
            GENERATE_QUOTE_REFRESH,
            (message) => this.handleRefreshMessage(message)
        );
    }

    handleRefreshMessage(message) {
        if (message?.recordId && message.recordId === this.recordId) {
            this.refreshBannerState();
        }
    }

    get isVisible() {
        return (
            !this.sessionDismissed &&
            this.bannerContext?.showBanner === true &&
            this.quoteRows.length > 0
        );
    }

    get bannerTitle() {
        return BANNER_TITLE;
    }

    get bannerMessage() {
        return this.bannerContext?.message ?? '';
    }

    get opportunityForecastConfidence() {
        return this.bannerContext?.opportunityForecastConfidence ?? '';
    }

    get pendingQuoteForecastConfidence() {
        return this.bannerContext?.pendingQuoteForecastConfidence ?? '';
    }

    get selectedQuoteIds() {
        return this.quoteRows
            .filter((quoteRow) => quoteRow.selected)
            .map((quoteRow) => quoteRow.id);
    }

    get allSelected() {
        return this.quoteRows.length > 0 && this.selectedQuoteIds.length === this.quoteRows.length;
    }

    get isBusy() {
        return this.isPropagating;
    }

    get propagateDisabled() {
        return this.isBusy || this.selectedQuoteIds.length === 0;
    }

    handleOpenModal() {
        this.showPropagateModal = true;
    }

    handleCloseModal() {
        if (this.isBusy) {
            return;
        }

        this.showPropagateModal = false;
    }

    handleModalKeyDown(event) {
        if (event.key === 'Escape' && !this.isBusy) {
            this.handleCloseModal();
        }
    }

    handleSelectAllChange(event) {
        const isSelected = event.target.checked;
        this.quoteRows = this.quoteRows.map((quoteRow) => ({
            ...quoteRow,
            selected: isSelected
        }));
    }

    handleQuoteSelectionChange(event) {
        const quoteId = event.target.dataset.id;
        const isSelected = event.target.checked;

        this.quoteRows = this.quoteRows.map((quoteRow) =>
            quoteRow.id === quoteId
                ? { ...quoteRow, selected: isSelected }
                : quoteRow
        );
    }

    async handlePropagate() {
        if (!this.recordId || this.propagateDisabled) {
            return;
        }

        this.isPropagating = true;

        try {
            await propagateSelectedQuotes({
                opportunityId: this.recordId,
                quoteIds: this.selectedQuoteIds
            });

            this.showPropagateModal = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Forecast confidence was updated on the selected quotes.',
                    variant: 'success'
                })
            );

            this.refreshOpportunityRecord();
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error propagating forecast confidence',
                    message: this.reduceErrors(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isPropagating = false;
        }
    }

    handleDismiss() {
        if (!this.recordId || this.isBusy) {
            return;
        }

        this.sessionDismissed = true;
        this.showPropagateModal = false;
    }

    refreshOpportunityRecord() {
        if (!this.recordId) {
            return;
        }

        getRecordNotifyChange([{ recordId: this.recordId }]);
        this.dispatchEvent(new RefreshEvent());
        this.publishGenerateQuoteRefresh();
        this.refreshBannerState();
    }

    refreshBannerState() {
        if (this.wiredBannerContextResult) {
            refreshApex(this.wiredBannerContextResult);
        }
    }

    publishGenerateQuoteRefresh() {
        if (!this.messageContext || !this.recordId) {
            return;
        }

        publish(this.messageContext, GENERATE_QUOTE_REFRESH, {
            recordId: this.recordId
        });
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