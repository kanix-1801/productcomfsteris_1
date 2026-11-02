import { LightningElement, api } from 'lwc';

/**
 * GW-4348 / GW-5996 - Review Order(s) summary for Create Order in Receiving.
 * Groups are built by the parent (Product Line / PO / Ship-To).
 */
export default class CreateOrderSummary extends LightningElement {
    _groups = [];

    @api
    get groups() {
        return this._groups;
    }
    set groups(value) {
        this._groups = Array.isArray(value) ? value : [];
    }

    get hasGroups() {
        return (this._groups || []).length > 0;
    }
}