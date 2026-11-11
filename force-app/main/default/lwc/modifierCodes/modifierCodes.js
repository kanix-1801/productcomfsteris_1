import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getWorkspace from '@salesforce/apex/ModifierCodesController.getWorkspace';
import getPricingModifierOptions from '@salesforce/apex/ModifierCodesController.getPricingModifierOptions';
import getPriorWorkOrders from '@salesforce/apex/ModifierCodesController.getPriorWorkOrders';
import getReasonCodeOptions from '@salesforce/apex/ModifierCodesController.getReasonCodeOptions';
import saveModifier from '@salesforce/apex/ModifierCodesController.saveModifier';
import removeModifier from '@salesforce/apex/ModifierCodesController.removeModifier';

const KIND_ITEM = 'item';
const KIND_SERVICE = 'service';

/**
 * GW-3458 - Modifier Codes tables shared by Device Evaluation and Instrument Evaluation.
 */
export default class ModifierCodes extends LightningElement {
    @api workOrderId;
    @api variant = 'device';

    workspace;
    isLoading = true;
    isActing = false;
    errorMessage = '';

    isModalOpen = false;
    optionsLoading = false;
    modalTitle = 'Add Modifier';
    targetLineId;
    targetAssetId;
    targetKind = KIND_ITEM;
    isEdit = false;
    pricingModifierId = '';
    reasonCodeId = '';
    orderReferenceId = '';
    modifierOptions = [];
    reasonCodeOptions = [];
    workOrderOptions = [];

    connectedCallback() {
        this.loadWorkspace();
    }

    get isDevice() {
        return this.variant !== 'instrument';
    }

    get showOrderReference() {
        return this.workspace?.showOrderReference !== false && this.isDevice;
    }

    get itemRows() {
        return this.workspace?.items || [];
    }

    get serviceRows() {
        return this.workspace?.services || [];
    }

    get groups() {
        return this.workspace?.groups || [];
    }

    get hasItems() {
        return this.itemRows.length > 0;
    }

    get hasServices() {
        return this.serviceRows.length > 0;
    }

    get hasGroups() {
        return this.groups.length > 0;
    }

    get isSaveDisabled() {
        return this.isActing || this.optionsLoading || !this.pricingModifierId;
    }

    get modalIntro() {
        return this.targetKind === KIND_SERVICE
            ? 'Choose the pricing modifier for this service.'
            : 'Choose the pricing modifier for this item.';
    }

    async loadWorkspace() {
        if (!this.workOrderId) {
            this.workspace = null;
            this.isLoading = false;
            this.errorMessage = 'Work Order is required.';
            return;
        }
        this.isLoading = true;
        this.errorMessage = '';
        try {
            this.workspace = await getWorkspace({
                workOrderId: this.workOrderId,
                variant: this.variant
            });
        } catch (error) {
            this.workspace = null;
            this.errorMessage = this.messageFrom(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleAdd(event) {
        this.openModal(this.rowFromEvent(event), false);
    }

    handleEdit(event) {
        this.openModal(this.rowFromEvent(event), true);
    }

    rowFromEvent(event) {
        if (event.detail && event.detail.id) {
            return {
                lineId: event.detail.id,
                assetId: event.detail.assetId,
                kind: event.detail.kind,
                pricingModifierId: event.detail.pricingModifierId,
                reasonCodeId: event.detail.modifierReasonCode,
                orderReferenceId: event.detail.orderReferenceId
            };
        }
        const dataset = event.currentTarget?.dataset || {};
        return {
            lineId: dataset.lineId,
            assetId: dataset.assetId,
            kind: dataset.kind,
            pricingModifierId: dataset.pricingModifierId,
            reasonCodeId: dataset.reasonCodeId,
            orderReferenceId: dataset.orderReferenceId
        };
    }

    async openModal(source, isEdit) {
        this.targetLineId = source.lineId;
        this.targetAssetId = source.assetId || null;
        this.targetKind = source.kind || KIND_ITEM;
        this.isEdit = isEdit;
        this.modalTitle = isEdit ? 'Edit Modifier' : 'Add Modifier';
        this.pricingModifierId = isEdit ? source.pricingModifierId || '' : '';
        this.reasonCodeId = isEdit ? source.reasonCodeId || '' : '';
        this.orderReferenceId = isEdit ? source.orderReferenceId || '' : '';
        this.modifierOptions = [];
        this.reasonCodeOptions = [];
        this.workOrderOptions = [];
        this.isModalOpen = true;
        this.optionsLoading = true;
        try {
            const modifierRequest = getPricingModifierOptions({ appliesTo: this.targetKind });
            const workOrderRequest = this.showOrderReference && this.targetAssetId
                ? getPriorWorkOrders({ assetId: this.targetAssetId })
                : Promise.resolve([]);
            const [modifiers, workOrders, reasons] = await Promise.all([
                modifierRequest,
                workOrderRequest,
                getReasonCodeOptions()
            ]);
            this.modifierOptions = modifiers || [];
            this.workOrderOptions = workOrders || [];
            this.reasonCodeOptions = reasons || [];
        } catch (error) {
            this.isModalOpen = false;
            this.toastError(this.messageFrom(error));
        } finally {
            this.optionsLoading = false;
        }
    }

    handlePricingModifierChange(event) {
        this.pricingModifierId = event.detail.value;
    }

    handleReasonChange(event) {
        this.reasonCodeId = event.detail.value;
    }

    handleOrderReferenceChange(event) {
        this.orderReferenceId = event.detail.value;
    }

    handleCancel() {
        if (this.isActing) {
            return;
        }
        this.isModalOpen = false;
    }

    async handleSave() {
        if (this.isSaveDisabled) {
            return;
        }
        if (!this.targetLineId) {
            this.toastError('Work Order Line is required.');
            return;
        }
        this.isActing = true;
        try {
            await saveModifier({
                workOrderLineItemId: this.targetLineId,
                pricingModifierId: this.pricingModifierId,
                modifierReasonCode: this.reasonCodeId || null,
                orderReferenceId: this.showOrderReference ? this.orderReferenceId || null : null,
                applyOrderReference: this.showOrderReference
            });
            this.isModalOpen = false;
            await this.loadWorkspace();
        } catch (error) {
            this.toastError(this.messageFrom(error));
        } finally {
            this.isActing = false;
        }
    }

    async handleRemove(event) {
        const lineId = this.rowFromEvent(event).lineId;
        if (!lineId || this.isActing) {
            return;
        }
        this.isActing = true;
        try {
            await removeModifier({ workOrderLineItemId: lineId });
            await this.loadWorkspace();
        } catch (error) {
            this.toastError(this.messageFrom(error));
        } finally {
            this.isActing = false;
        }
    }

    toastError(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Modifier codes',
                message,
                variant: 'error'
            })
        );
    }

    messageFrom(error) {
        return error?.body?.message || error?.message || 'Unable to update the modifier.';
    }
}