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
import IS_OPPORTUNITY_CLOSED from '@salesforce/schema/Opportunity.IsOpportunityClosed__c';
import getBannerContext from '@salesforce/apex/OppClosedLostQuoteBannerController.getBannerContext';
import closeAllOpenQuotes from '@salesforce/apex/OppClosedLostQuoteBannerController.closeAllOpenQuotes';
import dismissBanner from '@salesforce/apex/OppClosedLostQuoteBannerController.dismissBanner';

const BANNER_TITLE = 'Opportunity moved to Closed Lost';

export default class OpportunityClosedLostQuoteBanner extends LightningElement {
    @api recordId;

    bannerContext;
    quoteRows = [];
    wiredBannerContextResult;
    refreshSubscription;
    messageContext;
    isClosing = false;
    isDismissing = false;
    showConfirmModal = false;
    lastKnownShowBanner;

    @wire(MessageContext)
    wiredMessageContext(context) {
        this.messageContext = context;
        this.trySubscribeRefreshChannel();
    }

    @wire(getRecord, { recordId: '$recordId', fields: [IS_OPPORTUNITY_CLOSED] })
    wiredOpportunityRecord(result) {
        if (!result.data) {
            return;
        }

        const showBanner = getFieldValue(result.data, IS_OPPORTUNITY_CLOSED) === true;
        if (showBanner !== this.lastKnownShowBanner) {
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
                forecastEligibleLabel: quoteRow.forecastEligible ? 'Yes' : 'No'
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
        return this.bannerContext?.showBanner === true && this.quoteRows.length > 0;
    }

    get hasQuoteRows() {
        return this.quoteRows.length > 0;
    }

    get bannerTitle() {
        return BANNER_TITLE;
    }

    get bannerMessage() {
        return this.bannerContext?.message ?? '';
    }

    get confirmMessage() {
        return this.bannerContext?.confirmMessage ?? '';
    }

    get isBusy() {
        return this.isClosing || this.isDismissing;
    }

    get modalMessageClass() {
        return this.isClosing ? 'modal-message modal-message_loading' : 'modal-message';
    }

    handleYesClick() {
        this.showConfirmModal = true;
    }

    handleNoClick() {
        this.dismissBannerAction();
    }

    handleConfirmCancel() {
        if (this.isBusy) {
            return;
        }

        this.showConfirmModal = false;
    }

    handleModalKeyDown(event) {
        if (event.key === 'Escape' && !this.isBusy) {
            this.handleConfirmCancel();
        }
    }

    async handleConfirmCloseQuotes() {
        if (!this.recordId || this.isBusy) {
            return;
        }

        this.isClosing = true;

        try {
            await closeAllOpenQuotes({ opportunityId: this.recordId });
            this.showConfirmModal = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Related open quotes were updated to Closed status.',
                    variant: 'success'
                })
            );
            this.refreshOpportunityRecord();
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error closing quotes',
                    message: this.reduceErrors(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isClosing = false;
        }
    }

    async dismissBannerAction() {
        if (!this.recordId || this.isBusy) {
            return;
        }

        this.isDismissing = true;

        try {
            await dismissBanner({ opportunityId: this.recordId });
            this.showConfirmModal = false;
            this.refreshOpportunityRecord();
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error dismissing banner',
                    message: this.reduceErrors(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isDismissing = false;
        }
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