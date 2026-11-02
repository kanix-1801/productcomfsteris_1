import { LightningElement, api } from 'lwc';

/**
 * GW-4348 / GW-5996 - Order(s) Created confirmation for Create Order in Receiving.
 */
export default class CreateOrderConfirmation extends LightningElement {
    _orders = [];

    @api
    get orders() {
        return this._orders;
    }
    set orders(value) {
        this._orders = Array.isArray(value) ? value : [];
    }

    get hasOrders() {
        return (this._orders || []).length > 0;
    }

    handleWorkOrderClick(event) {
        event.preventDefault();
        const workOrderId = event.currentTarget?.dataset?.workOrderId;
        if (!workOrderId) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('openworkorder', {
                detail: { workOrderId },
                bubbles: true,
                composed: true
            })
        );
    }
}