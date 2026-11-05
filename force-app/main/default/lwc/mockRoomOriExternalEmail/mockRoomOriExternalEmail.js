import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';

export default class MockRoomOriExternalEmail extends LightningElement {
    @api value;
    @api required = false;

    handleChange(event) {
        this.value = event.detail.value;
        this.dispatchEvent(new FlowAttributeChangeEvent('value', this.value));
        this.dispatchEvent(new CustomEvent('emailchange', { detail: { value: this.value } }));
    }

    @api
    setError(message) {
        const input = this.template.querySelector('lightning-input');
        if (!input) {
            return false;
        }
        input.setCustomValidity(message || '');
        return input.reportValidity();
    }
}