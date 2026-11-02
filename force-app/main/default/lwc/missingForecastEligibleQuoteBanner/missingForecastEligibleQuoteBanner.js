import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import { RefreshEvent } from 'lightning/refresh';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import {
    subscribe,
    unsubscribe,
    MessageContext
} from 'lightning/messageService';
import GENERATE_QUOTE_REFRESH from '@salesforce/messageChannel/generateQuoteRefresh__c';
import isBannerVisible from '@salesforce/apex/MissingForecastEligibleBannerController.isBannerVisible';
import MISSING_FORECAST_ELIGIBLE_QUOTE_MESSAGE from '@salesforce/label/c.MissingForecastEligibleQuoteMessage';

export default class MissingForecastEligibleQuoteBanner extends LightningElement {
    @api recordId;

    refreshSubscription;
    messageContext;
    wiredBannerResult;
    showBanner = false;

    @wire(MessageContext)
    wiredMessageContext(context) {
        this.messageContext = context;
        this.trySubscribeRefreshChannel();
    }

    @wire(isBannerVisible, { opportunityId: '$recordId' })
    wiredBannerVisibility(result) {
        this.wiredBannerResult = result;

        if (result.data !== undefined) {
            this.showBanner = result.data === true;
        } else if (result.error) {
            this.showBanner = false;
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

    refreshBannerState() {
        if (!this.recordId) {
            return;
        }

        if (this.wiredBannerResult) {
            refreshApex(this.wiredBannerResult);
        }

        getRecordNotifyChange([{ recordId: this.recordId }]);
        this.dispatchEvent(new RefreshEvent());
    }

    get bannerMessage() {
        return MISSING_FORECAST_ELIGIBLE_QUOTE_MESSAGE;
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