import { LightningElement } from 'lwc';

const FLOW_FINISHED_STATUSES = new Set(['FINISHED', 'FINISHED_SCREEN']);

/**
 * #GC-3598 Experience Cloud button that launches CreateDealerOpportunity.
 * Place beside the standard New Opportunity action on My Opportunities.
 */
export default class CreateDealerOpportunityButton extends LightningElement {
    isOpen = false;

    get keepPickerInSiteBundle() {
        return false;
    }

    handleOpen() {
        this.isOpen = true;
    }

    handleClose() {
        this.isOpen = false;
    }

    handleFlowStatusChange(event) {
        const status = event.detail && event.detail.status;
        if (FLOW_FINISHED_STATUSES.has(status)) {
            this.isOpen = false;
        }
    }
}