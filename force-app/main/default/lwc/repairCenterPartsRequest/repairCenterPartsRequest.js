import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getBomParts from '@salesforce/apex/RepairCenterPartsRequestController.getBomParts';
import findScannedPart from '@salesforce/apex/RepairCenterPartsRequestController.findScannedPart';
import getProductRequests from '@salesforce/apex/RepairCenterPartsRequestController.getProductRequests';
import createPartsRequest from '@salesforce/apex/RepairCenterPartsRequestController.createPartsRequest';

const MODE_BOM = 'bom';
const NO_LINES_MESSAGE = 'Add at least one part before saving.';
const QUANTITY_MESSAGE = 'Enter a quantity greater than zero for each part.';

/**
 * GW-5981 - Product Requests tab body for Device (BOM) and Instrument (scan) evaluation.
 */
export default class RepairCenterPartsRequest extends LightningElement {
    @api workOrderId;
    @api mode = MODE_BOM;

    requests = [];
    draftParts = [];
    scanValue = '';
    scanError = '';
    modalError = '';
    isModalOpen = false;
    isListLoading = false;
    isModalLoading = false;
    isSaving = false;
    loadError = '';

    get isBomMode() {
        return this.mode === MODE_BOM;
    }

    get hasRequests() {
        return this.requests.length > 0;
    }

    get isBusy() {
        return this.isListLoading || this.isModalLoading || this.isSaving;
    }

    connectedCallback() {
        this.loadRequests();
    }

    async loadRequests() {
        if (!this.workOrderId) {
            this.requests = [];
            return;
        }
        this.isListLoading = true;
        this.loadError = '';
        try {
            this.requests = (await getProductRequests({ workOrderId: this.workOrderId })) || [];
        } catch (error) {
            this.loadError = this.errorMessage(error, 'Unable to load product requests.');
            this.requests = [];
        } finally {
            this.isListLoading = false;
        }
    }

    async openModal() {
        this.isModalOpen = true;
        this.modalError = '';
        this.scanError = '';
        this.scanValue = '';
        this.draftParts = [];
        if (this.isBomMode) {
            await this.loadBom();
        } else {
            this.focusScanField();
        }
    }

    closeModal() {
        if (this.isSaving) {
            return;
        }
        this.isModalOpen = false;
        this.draftParts = [];
        this.scanValue = '';
        this.scanError = '';
        this.modalError = '';
    }

    async loadBom() {
        this.isModalLoading = true;
        this.modalError = '';
        try {
            const parts = (await getBomParts({ workOrderId: this.workOrderId })) || [];
            this.draftParts = parts.map((part) => this.toDraft(part, false));
        } catch (error) {
            this.modalError = this.errorMessage(error, 'Unable to load the bill of material.');
        } finally {
            this.isModalLoading = false;
        }
    }

    handleScanInput(event) {
        this.scanValue = event.target.value;
        this.scanError = '';
    }

    async handleScanKeyDown(event) {
        if (event.key !== 'Enter') {
            return;
        }
        event.preventDefault();
        const entered = (event.target.value || this.scanValue || '').trim();
        this.scanValue = '';
        await this.submitScan(entered);
    }

    async submitScan(entered) {
        this.focusScanField();
        if (!entered) {
            return;
        }
        this.isModalLoading = true;
        this.scanError = '';
        try {
            const part = await findScannedPart({ scanValue: entered });
            if (this.draftParts.some((row) => row.productId === part.productId)) {
                this.scanError = 'This part is already on the request.';
                return;
            }
            this.draftParts = [...this.draftParts, this.toDraft(part, true)];
        } catch (error) {
            this.scanError = this.errorMessage(
                error,
                `No Product could be identified for the provided Part Number: ${entered}.`
            );
        } finally {
            this.isModalLoading = false;
            this.focusScanField();
        }
    }

    handleChecked(event) {
        const productId = event.target.dataset.id;
        const selected = event.target.checked;
        this.modalError = '';
        this.draftParts = this.draftParts.map((part) => {
            if (part.productId !== productId) {
                return part;
            }
            return {
                ...part,
                selected,
                quantity: selected ? part.quantity : ''
            };
        });
    }

    handleQuantityChange(event) {
        const productId = event.target.dataset.id;
        const quantity = event.target.value;
        this.draftParts = this.draftParts.map((part) =>
            part.productId === productId ? { ...part, quantity } : part
        );
    }

    handleRemove(event) {
        const productId = event.currentTarget.dataset.id;
        this.draftParts = this.draftParts.filter((part) => part.productId !== productId);
    }

    async handleSave() {
        const selected = this.draftParts.filter((part) => part.selected);
        if (selected.length === 0) {
            this.modalError = NO_LINES_MESSAGE;
            return;
        }
        const inputs = [...this.template.querySelectorAll('lightning-input.quantity-input')];
        const lines = [];
        let quantitiesValid = inputs.length === selected.length;
        inputs.forEach((input) => {
            const quantity = Number(input.value);
            if (!input.reportValidity() || !Number.isFinite(quantity) || quantity <= 0) {
                input.setCustomValidity(QUANTITY_MESSAGE);
                input.reportValidity();
                quantitiesValid = false;
                return;
            }
            input.setCustomValidity('');
            lines.push({
                productId: input.dataset.id,
                quantity
            });
        });
        if (!quantitiesValid) {
            this.modalError = QUANTITY_MESSAGE;
            return;
        }

        this.isSaving = true;
        this.modalError = '';
        try {
            const result = await createPartsRequest({
                workOrderId: this.workOrderId,
                lines
            });
            this.isSaving = false;
            this.closeModal();
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Parts request created',
                    message: result?.productRequestNumber
                        ? `Product Request ${result.productRequestNumber} was submitted.`
                        : 'The parts request was submitted.',
                    variant: 'success'
                })
            );
            await this.loadRequests();
        } catch (error) {
            this.modalError = this.errorMessage(error, 'Unable to save the parts request.');
            this.isSaving = false;
        }
    }

    handleModalKeyDown(event) {
        if (event.key === 'Escape') {
            this.closeModal();
        }
    }

    toDraft(part, selected) {
        return {
            productId: part.productId,
            label: part.label,
            selected,
            quantity: ''
        };
    }

    focusScanField() {
        window.setTimeout(() => {
            this.template.querySelector('lightning-input.scan-input')?.focus();
        }, 0);
    }

    errorMessage(error, fallback) {
        return error?.body?.message || error?.message || fallback;
    }
}