import { LightningElement, api } from 'lwc';
import { FlowNavigationNextEvent } from 'lightning/flowSupport';

export default class HsReadOnlyField extends LightningElement {
    @api label;
    @api value;
    @api dateValue;
    @api dateTimeValue;
    @api editable = false;

    get isEditable() {
        return this.editable === true || this.editable === 'true';
    }

    get hasDateTime() {
        return !!this.dateTimeValue;
    }

    get hasDate() {
        return !this.dateTimeValue && !!this.dateValue;
    }

    get hasText() {
        return !this.dateTimeValue && !this.dateValue;
    }

    handleEdit() {
        this.dispatchEvent(new FlowNavigationNextEvent());
    }
}