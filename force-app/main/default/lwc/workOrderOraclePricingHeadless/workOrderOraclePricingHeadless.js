import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import fetchAndApplyOraclePricing from '@salesforce/apex/OraclePricingService.fetchAndApplyOraclePricing';

/**
 * Headless record action ({@code actionType Action}): runs Oracle pricing with toasts only — no modal.
 */
export default class WorkOrderOraclePricingHeadless extends LightningElement {
    @api recordId;

    _recordIdFromPage;
    _pricingRequestInFlight = false;
    _invokePromise;

    @wire(CurrentPageReference)
    wiredPageReference(pageRef) {
        if (!pageRef) {
            return;
        }
        const state = pageRef.state || {};
        const attrs = pageRef.attributes || {};
        const fromState = state.recordId;
        const fromAttrs = attrs.recordId;
        this._recordIdFromPage = fromState || fromAttrs || this._recordIdFromPage;
    }

    get effectiveWorkOrderId() {
        return this.recordId || this._recordIdFromPage;
    }

    /**
     * Headless quick action entry point — no UI is shown.
     *
     * @returns {Promise<void>}
     */
    @api invoke() {
        if (this._invokePromise) {
            return this._invokePromise;
        }
        this._invokePromise = new Promise((resolve) => {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(resolve, 0);
        })
            .then(() => this.runOraclePricing())
            .finally(() => {
                this._invokePromise = undefined;
            });
        return this._invokePromise;
    }

    runOraclePricing() {
        const woId = this.effectiveWorkOrderId;
        if (!woId) {
            const msg =
                'Could not determine the Work Order. Open this action from a Work Order record page ' +
                '(not the list view or a utility bar).';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Oracle pricing',
                    message: msg,
                    variant: 'error',
                    mode: 'sticky'
                })
            );
            return Promise.resolve();
        }

        if (this._pricingRequestInFlight) {
            return Promise.resolve();
        }
        this._pricingRequestInFlight = true;

        return fetchAndApplyOraclePricing({ workOrderId: woId })
            .then((result) => {
                if (result.success) {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Oracle pricing',
                            message: result.message,
                            variant: 'success'
                        })
                    );
                } else {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Oracle pricing',
                            message: result.message,
                            variant: 'error',
                            mode: 'sticky'
                        })
                    );
                }
            })
            .catch((error) => {
                const message =
                    error?.body?.message || error?.message || 'Oracle pricing request failed.';
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Oracle pricing error',
                        message,
                        variant: 'error',
                        mode: 'sticky'
                    })
                );
            })
            .finally(() => {
                this._pricingRequestInFlight = false;
            });
    }
}