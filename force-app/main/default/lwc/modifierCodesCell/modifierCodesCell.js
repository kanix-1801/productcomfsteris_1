import { LightningElement, api } from 'lwc';

/**
 * GW-3458 - Modifier column: add, edit, or remove the single modifier on a line.
 */
export default class ModifierCodesCell extends LightningElement {
    @api row;

    get showValue() {
        return this.row?.hasModifier === true;
    }

    get showAdd() {
        return this.row?.canAdd === true && !this.showValue;
    }

    get showEdit() {
        return this.row?.canEdit === true;
    }

    handleAdd() {
        this.dispatchEvent(new CustomEvent('add', { detail: this.row }));
    }

    handleEdit() {
        this.dispatchEvent(new CustomEvent('edit', { detail: this.row }));
    }

    handleRemove() {
        this.dispatchEvent(new CustomEvent('remove', { detail: this.row }));
    }
}