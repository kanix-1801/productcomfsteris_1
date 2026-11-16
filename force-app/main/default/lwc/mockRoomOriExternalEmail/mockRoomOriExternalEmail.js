import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';

export default class MockRoomOriExternalEmail extends LightningElement {
    @api value;
    @api required = false;

    handleChange(event) {
        const value = event.detail.value;
        this.dispatchEvent(new FlowAttributeChangeEvent('value', value));
        this.dispatchEvent(new CustomEvent('emailchange', { detail: { value } }));
    }

    /** Shows the message under the email field. A blank message clears it. Returns true when the field is valid. */
    @api
    setError(message) {
        const input = this.template.querySelector('lightning-input');
        input.setCustomValidity(message || '');
        return input.reportValidity();
    }
}