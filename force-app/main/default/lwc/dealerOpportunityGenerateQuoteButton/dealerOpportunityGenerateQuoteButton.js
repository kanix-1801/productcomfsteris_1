import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import { RefreshEvent } from 'lightning/refresh';
import { openPendingNavigationTab, clearPendingNavigationTab } from 'c/generateQuoteNavigation';

const RECORD_ID_PATTERN = /^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/;

/**
 * @description Dealer Portal (LWR) — brand action button that opens Generate Quote in dealer mode,
 *              equivalent to the Opportunity.Generate_Quote quick action via generateQuoteAction.
 */
export default class DealerOpportunityGenerateQuoteButton extends LightningElement {
    @api recordId;
    @api buttonLabel = 'Generate Quote';

    @track showQuotePanel = false;
    pageRecordId;

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
        return Boolean(this.effectiveRecordId) && !this.showQuotePanel;
    }

    get showMissingRecordMessage() {
        return !this.effectiveRecordId && !this.showQuotePanel;
    }

    handleOpenGenerateQuote() {
        if (!this.effectiveRecordId) {
            return;
        }
        openPendingNavigationTab();
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