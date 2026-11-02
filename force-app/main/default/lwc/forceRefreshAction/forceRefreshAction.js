import { LightningElement, api } from 'lwc'; // Ensure 'api' is imported here
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

export default class ForceRefreshAction extends LightningElement {
    @api recordId; // This MUST match the name in your XML exactly

    @api
    async invoke() {
        if (this.recordId) {
            try {
                await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            } catch (error) {
                console.error('Refresh failed', error);
            }
        }
    }
}