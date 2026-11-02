import { api } from 'lwc';
import LightningModal from 'lightning/modal';

export default class ConfigPocModal extends LightningModal {
    @api quantity;
    @api assetName;
    draftQuantity;
    draftAssetName;

    connectedCallback() {
        this.draftQuantity = this.quantity;
        this.draftAssetName = this.assetName;
    }

    handleQuantity(event) {
        this.draftQuantity = event.detail.value;
    }

    handleAssetName(event) {
        this.draftAssetName = event.detail.value;
    }

    handleCancel() {
        this.close({ cancelled: true });
    }

    handleSave() {
        this.close({ quantity: this.draftQuantity, assetName: this.draftAssetName });
    }
}