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
import PENDING_EPP_CONVERSION_QUOTE_CLOSURE from '@salesforce/schema/Opportunity.PendingEppConversionQuoteClosure__c';
import getBannerContext from '@salesforce/apex/OppEppConversionQuoteBannerController.getBannerContext';
import closeAllOpenQuotes from '@salesforce/apex/OppEppConversionQuoteBannerController.closeAllOpenQuotes';
import dismissBanner from '@salesforce/apex/OppEppConversionQuoteBannerController.dismissBanner';
import reconcileStaleBanner from '@salesforce/apex/OppEppConversionQuoteBannerController.reconcileStaleBanner';

const BANNER_TITLE = 'Capital Opportunity converted to EPP';
const TOAST_AUTO_DISMISS_MS = 5000;

export default class OpportunityEppConversionQuoteBanner extends LightningElement {
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
    pendingEppConversionFlag;
    toastDismissTimeoutId;

    @wire(MessageContext)
    wiredMessageContext(context) {
        this.messageContext = context;
        this.trySubscribeRefreshChannel();
    }

    @wire(getRecord, { recordId: '$recordId', fields: [PENDING_EPP_CONVERSION_QUOTE_CLOSURE] })
    wiredOpportunityRecord(result) {
        if (!result.data) {
            return;
        }

        this.pendingEppConversionFlag =
            getFieldValue(result.data, PENDING_EPP_CONVERSION_QUOTE_CLOSURE) === true;
        if (this.pendingEppConversionFlag !== this.lastKnownShowBanner) {
            this.lastKnownShowBanner = this.pendingEppConversionFlag;
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
            if (
                this.pendingEppConversionFlag === true &&
                result.data.showBanner !== true &&
                this.recordId
            ) {
                reconcileStaleBanner({ opportunityId: this.recordId })
                    .then(() => this.refreshOpportunityRecord())
                    .catch(() => {});
            }
        } else if (result.error) {
            this.bannerContext = null;
            this.quoteRows = [];
            this.showTimedToast('Error loading banner', this.reduceErrors(result.error), 'error');
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

        this.clearToastDismissTimeout();
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
            this.showTimedToast(
                'Success',
                'Related open quotes were updated to Closed status in Sales Connection and Salesforce.',
                'success'
            );
            this.refreshOpportunityRecord();
        } catch (error) {
            this.showTimedToast('Error closing quotes', this.reduceErrors(error), 'error');
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
            this.showTimedToast('Error dismissing banner', this.reduceErrors(error), 'error');
        } finally {
            this.isDismissing = false;
        }
    }

    showTimedToast(title, message, variant) {
        this.clearToastDismissTimeout();
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant,
                mode: 'dismissable'
            })
        );
        this.toastDismissTimeoutId = window.setTimeout(() => {
            this.toastDismissTimeoutId = null;
        }, TOAST_AUTO_DISMISS_MS);
    }

    clearToastDismissTimeout() {
        if (this.toastDismissTimeoutId) {
            window.clearTimeout(this.toastDismissTimeoutId);
            this.toastDismissTimeoutId = null;
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