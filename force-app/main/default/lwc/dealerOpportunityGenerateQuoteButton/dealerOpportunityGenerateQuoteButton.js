import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import { RefreshEvent } from 'lightning/refresh';
import { clearPendingNavigationTab } from 'c/generateQuoteNavigation';
import hasDealerQuoteAccess from '@salesforce/apex/DealerPortalAccessController.hasDealerQuoteAccess';

const RECORD_ID_PATTERN = /^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/;

/**
 * @description Dealer Portal (LWR) launcher. Shows Generate Quote only when DealerManagerPS is assigned.
 *              Dealer launch opens Sales Connection in a new tab once the quote URL is ready.
 */
export default class DealerOpportunityGenerateQuoteButton extends LightningElement {
    @api recordId;
    @api buttonLabel = 'Generate Quote';

    @track showQuotePanel = false;
    pageRecordId;
    dealerAccessLoaded = false;
    dealerQuoteAccessGranted = false;

    @wire(hasDealerQuoteAccess)
    wiredDealerQuoteAccess({ data, error }) {
        if (error) {
            this.dealerQuoteAccessGranted = false;
            this.dealerAccessLoaded = true;
            return;
        }

        if (data !== undefined) {
            this.dealerQuoteAccessGranted = data === true;
            this.dealerAccessLoaded = true;
        }
    }

    @wire(CurrentPageReference)
    wiredPageReference(pageReference) {
        const stateRecordId = pageReference?.state?.recordId;
        if (stateRecordId) {
            this.pageRecordId = stateRecordId;
        }
    }

    get effectiveRecordId() {
        return normalizeRecordId(this.recordId) || normalizeRecordId(this.pageRecordId);
    }

    get showLaunchButton() {
        return this.dealerAccessLoaded && this.dealerQuoteAccessGranted && !this.showQuotePanel;
    }

    handleOpenGenerateQuote() {
        if (!this.effectiveRecordId) {
            return;
        }
        this.showQuotePanel = true;
    }

    handleCloseQuickAction(event) {
        const shouldRefresh = event?.detail?.refresh !== false;
        this.showQuotePanel = false;
        clearPendingNavigationTab();

        if (shouldRefresh && this.effectiveRecordId) {
            getRecordNotifyChange([{ recordId: this.effectiveRecordId }]);
            this.dispatchEvent(new RefreshEvent());
        }
    }
}

function normalizeRecordId(value) {
    if (value === null || value === undefined) {
        return null;
    }

    const trimmed = String(value).trim();
    if (!trimmed || trimmed.includes('{!')) {
        return null;
    }

    return RECORD_ID_PATTERN.test(trimmed) ? trimmed : null;
}