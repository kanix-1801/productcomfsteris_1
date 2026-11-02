import { LightningElement, api, wire } from 'lwc';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import { RefreshEvent } from 'lightning/refresh';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import {
    subscribe,
    unsubscribe,
    MessageContext
} from 'lightning/messageService';
import GENERATE_QUOTE_REFRESH from '@salesforce/messageChannel/generateQuoteRefresh__c';
import dismissNotification from '@salesforce/apex/QuoteForecastChangeBannerController.dismissNotification';

const BANNER_TITLE = 'Forecast information has changed';
const BANNER_MESSAGE =
    'One or more associated quotes have been updated. Please review your Forecast Eligible quotes and Opportunity forecast amount.';
const CONFIRM_MESSAGE =
    'Please confirm that all actions have been completed before dismissing this message';

export default class QuoteForecastChangeBanner extends LightningElement {
    @api recordId;

    refreshSubscription;
    messageContext;

    showConfirmModal = false;
    modalAction = null;

    get isModalBusy() {
        return this.modalAction !== null;
    }

    get isYesLoading() {
        return this.modalAction === 'yes';
    }

    get isCancelLoading() {
        return this.modalAction === 'cancel';
    }

    @wire(MessageContext)
    wiredMessageContext(context) {
        this.messageContext = context;
        this.trySubscribeRefreshChannel();
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
            this.refreshOpportunityRecord();
        }
    }

    refreshOpportunityRecord() {
        if (!this.recordId) {
            return;
        }

        getRecordNotifyChange([{ recordId: this.recordId }]);
        this.dispatchEvent(new RefreshEvent());
    }

    get bannerTitle() {
        return BANNER_TITLE;
    }

    get bannerMessage() {
        return BANNER_MESSAGE;
    }

    get confirmMessage() {
        return CONFIRM_MESSAGE;
    }

    get modalMessageClass() {
        return this.isYesLoading ? 'modal-message modal-message_loading' : 'modal-message';
    }

    get dismissDisabled() {
        return this.isModalBusy;
    }

    handleDismissClick() {
        this.showConfirmModal = true;
    }

    handleConfirmCancel() {
        if (this.isModalBusy) {
            return;
        }

        this.modalAction = 'cancel';
        this.showConfirmModal = false;
        this.modalAction = null;
    }

    handleModalKeyDown(event) {
        if (event.key === 'Escape' && !this.isModalBusy) {
            this.handleConfirmCancel();
        }
    }

    async handleConfirmYes() {
        if (!this.recordId || this.isModalBusy) {
            return;
        }

        this.modalAction = 'yes';

        try {
            await dismissNotification({ opportunityId: this.recordId });
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
            this.modalAction = null;
        }
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