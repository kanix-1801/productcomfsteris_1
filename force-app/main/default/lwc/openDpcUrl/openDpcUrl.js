import { LightningElement, api } from 'lwc';

export default class OpenDpcUrl extends LightningElement {
    @api url;

    connectedCallback() {
        this.openCatalog();
    }

    openCatalog() {
        if (!this.url) {
            return;
        }
        window.open(this.url, '_blank', 'noopener,noreferrer');
    }
}