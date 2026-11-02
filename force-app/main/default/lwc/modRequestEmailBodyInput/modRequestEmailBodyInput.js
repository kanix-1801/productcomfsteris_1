import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';

export default class ModRequestEmailBodyInput extends LightningElement {
    @api bodyValue;
    @api fieldLabel = 'Body';

    handleChange(event) {
        this.bodyValue = event.target.value;
        this.dispatchEvent(new FlowAttributeChangeEvent('bodyValue', this.bodyValue));
    }
}