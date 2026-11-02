import { LightningElement } from 'lwc';
import { FlowNavigationNextEvent } from 'lightning/flowSupport';

export default class HsEventEditAction extends LightningElement {
    handleEdit() {
        this.dispatchEvent(new FlowNavigationNextEvent());
    }
}