import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMissingReturnOrderItemOptions from '@salesforce/apex/ReceivingController.getMissingReturnOrderItemOptions';
import stageReceivingPhoto from '@salesforce/apex/ReceivingController.stageReceivingPhoto';
import deleteReceivingPhoto from '@salesforce/apex/ReceivingController.deleteReceivingPhoto';
import submitMissingReturnOrder from '@salesforce/apex/ReceivingController.submitMissingReturnOrder';

/**
 * GW-6057 - Resolve Missing Return Order form used by Receiving.
 */
export default class ResolveMissingReturnOrder extends LightningElement {
    itemOptions = [];
    itemsReceived = [];
    serialNumber = '';
    model = '';
    quantityReceived;
    notes = '';
    photos = [];
    errorMessage;
    isBusy = false;

    @wire(getMissingReturnOrderItemOptions)
    wiredItemOptions({ data, error }) {
        if (data) {
            this.itemOptions = data.map((option) => ({
                label: option.label,
                value: option.value
            }));
        } else if (error) {
            this.itemOptions = [];
            this.errorMessage = this.normalizeError(error);
        }
    }

    get hasPhotos() {
        return this.photos.length > 0;
    }

    get isSubmitDisabled() {
        return (
            this.isBusy ||
            !this.itemsReceived.length ||
            !this.photos.length
        );
    }

    handleItemsChange(event) {
        const value = event.detail?.value;
        this.itemsReceived = Array.isArray(value)
            ? [...value]
            : value
              ? [value]
              : [];
        this.errorMessage = undefined;
    }

    handleSerialChange(event) {
        this.serialNumber = event.target.value || '';
    }

    handleModelChange(event) {
        this.model = event.target.value || '';
    }

    handleQuantityChange(event) {
        const raw = event.target.value;
        this.quantityReceived = raw === '' || raw === null || raw === undefined ? undefined : raw;
    }

    handleNotesChange(event) {
        this.notes = event.target.value || '';
    }

    async handleFileSelected(event) {
        const files = Array.from(event.target.files || []);
        event.target.value = '';
        if (!files.length || this.isBusy) {
            return;
        }
        this.isBusy = true;
        this.errorMessage = undefined;
        try {
            for (const file of files) {
                const base64Data = await this.readFileAsDataUrl(file);
                const photo = await stageReceivingPhoto({
                    base64Data,
                    fileName: file.name
                });
                this.photos = [...this.photos, photo];
            }
        } catch (error) {
            this.errorMessage = this.normalizeError(error);
        } finally {
            this.isBusy = false;
        }
    }

    async handleRemovePhoto(event) {
        const contentDocumentId = event.currentTarget.dataset.documentId;
        if (!contentDocumentId || this.isBusy) {
            return;
        }
        this.isBusy = true;
        this.errorMessage = undefined;
        try {
            await deleteReceivingPhoto({ contentDocumentId });
            this.photos = this.photos.filter(
                (photo) => photo.contentDocumentId !== contentDocumentId
            );
        } catch (error) {
            this.errorMessage = this.normalizeError(error);
        } finally {
            this.isBusy = false;
        }
    }

    handleClose() {
        if (this.isBusy) {
            return;
        }
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleSubmit() {
        if (this.isSubmitDisabled) {
            if (!this.itemsReceived.length) {
                this.errorMessage = 'Item(s) Received is required.';
            } else if (!this.photos.length) {
                this.errorMessage = 'A picture of the shipping label is required.';
            }
            return;
        }
        this.isBusy = true;
        this.errorMessage = undefined;
        try {
            const quantityValue =
                this.quantityReceived === '' ||
                this.quantityReceived === null ||
                this.quantityReceived === undefined
                    ? null
                    : Number(this.quantityReceived);
            const caseId = await submitMissingReturnOrder({
                request: {
                    itemsReceived: [...this.itemsReceived],
                    serialNumber: this.serialNumber,
                    model: this.model,
                    quantityReceived: quantityValue,
                    notes: this.notes,
                    contentDocumentIds: this.photos.map((photo) => photo.contentDocumentId)
                }
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Missing Return Order submitted',
                    message: 'Case created for Ops Customer Care.',
                    variant: 'success'
                })
            );
            this.dispatchEvent(
                new CustomEvent('submitted', {
                    detail: { caseId }
                })
            );
        } catch (error) {
            this.errorMessage = this.normalizeError(error);
        } finally {
            this.isBusy = false;
        }
    }

    readFileAsDataUrl(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result);
            reader.onerror = () => reject(reader.error || new Error('Unable to read file.'));
            reader.readAsDataURL(file);
        });
    }

    normalizeError(error) {
        if (!error) {
            return 'Unexpected error.';
        }
        if (typeof error === 'string') {
            return error;
        }
        if (Array.isArray(error.body)) {
            return error.body.map((entry) => entry.message).join(', ');
        }
        if (error.body?.message) {
            return error.body.message;
        }
        if (error.message) {
            return error.message;
        }
        return 'Unexpected error.';
    }
}