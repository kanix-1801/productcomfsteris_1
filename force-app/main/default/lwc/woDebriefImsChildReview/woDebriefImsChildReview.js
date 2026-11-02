import { LightningElement, api, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import getChildDebriefAccess from '@salesforce/apex/WoDebriefIMSchildWOController.getChildDebriefAccess';

export default class WoDebriefImsChildReview extends LightningElement {
    @api recordId;

    @track accessMode = 'pending';
    @track workOrderNumber = '';
    _accessRequest = 0;

    connectedCallback() {
        this._checkAccess();
    }

    async _checkAccess() {
        const requestId = ++this._accessRequest;
        if (!this.recordId) {
            this.accessMode = 'denied';
            return;
        }
        try {
            const result = await getChildDebriefAccess({ workOrderId: this.recordId });
            if (requestId !== this._accessRequest) {
                return;
            }
            this.workOrderNumber = result?.workOrderNumber ?? '';
            this.accessMode = result?.allowed === true ? 'allowed' : 'denied';
        } catch (error) {
            if (requestId !== this._accessRequest) {
                return;
            }
            this.accessMode = 'denied';
        }
    }

    get isPending() {
        return this.accessMode === 'pending';
    }

    get isDenied() {
        return this.accessMode === 'denied';
    }

    get isAllowed() {
        return this.accessMode === 'allowed';
    }

    get deniedMessage() {
        const woNumber = this.workOrderNumber || 'this work order';
        return `Work Order ${woNumber} has no Parent Work Order. Use Work Order Review - IMS Site Visit. This action is only for child work orders.`;
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}