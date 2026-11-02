import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getBannerContext
    from '@salesforce/apex/OpportunityOliBannerController.getBannerContext';

import dismissBanner
    from '@salesforce/apex/OpportunityOliBannerController.dismissBanner';

const BANNER_TYPE_WARNING = 'warning';

export default class OpportunityOliBanner extends LightningElement {
    @api recordId;

    bannerContext;
    isDismissing = false;
    wiredBannerContextResult;

    /**
     * Loads banner state from Apex.
     */
    @wire(getBannerContext, {
        opportunityId: '$recordId'
    })
    wiredBannerContext(result) {
        this.wiredBannerContextResult = result;

        const { data, error } = result;

        if (data) {
            this.bannerContext = data;
        } else if (error) {
            this.bannerContext = null;

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error loading banner',
                    message: this.reduceErrors(error),
                    variant: 'error'
                })
            );
        }
    }

    /**
     * Determines whether banner should be rendered.
     */
    get isVisible() {
        return this.bannerContext?.showBanner === true;
    }

    /**
     * Determines whether current banner is Warning type.
     */
    get isWarningBanner() {
        return this.bannerContext?.bannerType === BANNER_TYPE_WARNING;
    }

    /**
     * Warning icon is displayed only for Warning banner.
     */
    get showBannerIcon() {
        return this.isWarningBanner;
    }

    /**
     * Returns CSS classes based on banner type.
     */
    get bannerClass() {
        const baseClass =
            'slds-notify slds-notify_alert banner-container';

        return this.isWarningBanner
            ? `${baseClass} banner-warning`
            : `${baseClass} banner-success`;
    }

    /**
     * Banner message returned by Apex.
     */
    get bannerMessage() {
        return this.bannerContext?.message ?? '';
    }

    /**
     * Each product returned by Apex is already one complete
     * product name extracted from {...}.
     *
     * Example Apex response:
     *
     * [
     *   '00005703CONVERSION INSTRUCTIONS, -B651 NL DI-W. TANK, DE/G',
     *   '00015782DSAFETY RING, 40 X 1.75'
     * ]
     *
     * DO NOT split on comma, hyphen, colon, slash, etc.
     */
    get productLines() {
        const productNames =
            this.bannerContext?.productNames ?? [];

        return productNames.map((name, index) => ({
            key: `product-${index}`,
            name
        }));
    }

    /**
     * Product lines are displayed only for Warning banner.
     */
    get hasProductLines() {
        return (
            this.isWarningBanner &&
            this.productLines.length > 0
        );
    }

    /**
     * Accessibility text.
     */
    get assistiveText() {
        if (!this.bannerMessage) {
            return '';
        }

        if (this.hasProductLines) {
            const productNames =
                this.productLines
                    .map((product) => product.name)
                    .join(', ');

            return `${this.bannerMessage} ${productNames}`;
        }

        return this.bannerMessage;
    }

    /**
     * Disable Dismiss button while request is in progress.
     */
    get dismissDisabled() {
        return this.isDismissing;
    }

    /**
     * Handles banner dismissal.
     */
    async handleDismiss() {
        if (!this.recordId || this.isDismissing) {
            return;
        }

        this.isDismissing = true;

        try {
            await dismissBanner({
                opportunityId: this.recordId
            });

            /*
             * Hide banner immediately on UI.
             */
            this.bannerContext = {
                ...this.bannerContext,
                showBanner: false
            };

            /*
             * Refresh Apex cache so UI remains synchronized
             * with Opportunity banner fields.
             */
            if (this.wiredBannerContextResult) {
                await refreshApex(
                    this.wiredBannerContextResult
                );
            }
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

    /**
     * Converts Salesforce/Apex error objects into readable text.
     */
    reduceErrors(error) {
        if (!error) {
            return 'Unknown error';
        }

        if (Array.isArray(error.body)) {
            return error.body
                .map((item) => item.message)
                .filter((message) => message)
                .join(', ');
        }

        if (
            error.body &&
            typeof error.body.message === 'string'
        ) {
            return error.body.message;
        }

        if (typeof error.message === 'string') {
            return error.message;
        }

        return 'Unknown error';
    }
}