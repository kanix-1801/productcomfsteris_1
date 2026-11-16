import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';

/**
 * #GC-3598 Required create-form field.
 * The error appears after Create and clears when the user leaves a field that now has a value.
 */
export default class DealerFlowField extends LightningElement {
    @api label;
    @api fieldType = 'text';
    @api helpText;
    @api choices;
    @api value;

    _required = false;
    _showErrors = false;
    _errorsShown = false;

    @api
    get required() {
        return this._required;
    }
    set required(value) {
        this._required = value === true || value === 'true';
    }

    @api
    get showErrors() {
        return this._showErrors;
    }
    set showErrors(value) {
        this._showErrors = value === true || value === 'true';
    }

    get isTextLike() {
        return this.fieldType === 'text' || this.fieldType === 'date';
    }

    get isTextarea() {
        return this.fieldType === 'textarea';
    }

    get isPicklist() {
        return this.fieldType === 'picklist';
    }

    get inputType() {
        return this.fieldType === 'date' ? 'date' : 'text';
    }

    get picklistOptions() {
        return (this.choices || '')
            .split(';')
            .map((entry) => entry.trim())
            .filter((entry) => entry)
            .map((entry) => ({ label: entry, value: entry }));
    }

    renderedCallback() {
        if (this._showErrors && !this._errorsShown) {
            this._errorsShown = true;
            this.report();
        }
    }

    handleChange(event) {
        this.value = event.detail.value;
        this.dispatchEvent(new FlowAttributeChangeEvent('value', this.value));
        if (this._showErrors) {
            this.report();
        }
    }

    handleBlur() {
        if (this._showErrors) {
            this.report();
        }
    }

    @api
    validate() {
        return { isValid: true };
    }

    report() {
        const input = this.template.querySelector('[data-input]');
        if (input) {
            input.reportValidity();
        }
    }
}