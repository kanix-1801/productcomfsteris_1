import { LightningElement, api } from 'lwc';

/**
 * GW-3400 - Shared item editor for quantity, codes slot, photos slot, and primary action.
 */
export default class RepairCenterItemEditor extends LightningElement {
    /** @type {string} add | modify | clone */
    @api mode = 'add';
    /** @type {number|string} */
    @api quantity;
    @api disabled = false;
    @api quantityDisabled = false;
    @api showPrevious = false;
    @api doneLabel = 'Done';
    @api previousLabel = 'Previous';
    @api quantityHint = '';
    /** GW-5677 - Shows the Additional Services Requested slot beside quantity. */
    @api showServices = false;

    get quantityValue() {
        return this.quantity == null ? '' : String(this.quantity);
    }

    get isQuantityDisabled() {
        return this.disabled === true || this.quantityDisabled === true;
    }

    get hasQuantityHint() {
        return Boolean(this.quantityHint);
    }

    /**
     * GW-5677 - Side-by-side layout when Additional Services Requested is shown.
     * @return {string} CSS class for the quantity, services, and actions row
     */
    get editorTopClass() {
        return this.showServices === true
            ? 'item-editor__top item-editor__top_with-services'
            : 'item-editor__top';
    }

    /**
     * GW-3400 - Forwards quantity changes to the host.
     * @param {Event} event input change
     */
    handleQuantityChange(event) {
        const raw = event.target.value;
        const parsed = raw === '' ? null : Number(raw);
        this.dispatchEvent(
            new CustomEvent('quantitychange', {
                detail: { quantity: Number.isFinite(parsed) ? parsed : null }
            })
        );
    }

    /**
     * GW-3400 - Returns to the previous wizard step.
     */
    handlePrevious() {
        this.dispatchEvent(new CustomEvent('previous'));
    }

    /**
     * GW-3400 - Confirms the current item (draft save on the host).
     */
    handleDone() {
        this.dispatchEvent(new CustomEvent('done'));
    }
}