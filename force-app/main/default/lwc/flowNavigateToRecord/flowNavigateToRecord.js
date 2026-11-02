import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { FlowNavigationFinishEvent } from 'lightning/flowSupport';

export default class FlowNavigateToRecord extends NavigationMixin(LightningElement) {
    @api recordId;

    connectedCallback() {
        if (this.recordId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.recordId,
                    actionName: 'view'
                }
            });
        }

        this.dispatchEvent(new FlowNavigationFinishEvent());
    }
}