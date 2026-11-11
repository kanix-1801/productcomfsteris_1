import { LightningElement, api } from 'lwc';

export default class ReturnToRecord extends LightningElement {
    @api recordId;

    @api invoke() {
        if (!this.recordId) {
            return;
        }
        const url = '/lightning/r/' + this.recordId + '/view';
        const target = window.top || window;
        target.location.assign(url);
    }
}