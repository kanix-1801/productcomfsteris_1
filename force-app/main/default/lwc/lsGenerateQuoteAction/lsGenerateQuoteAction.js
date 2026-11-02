import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import { RefreshEvent } from 'lightning/refresh';
import LsGenerateQuote from 'c/lsGenerateQuote';

export default class LsGenerateQuoteAction extends LightningElement {
    @api recordId;

    quoteComponent = LsGenerateQuote;

    handleCloseQuickAction(event) {
        const shouldRefresh = event.detail?.refresh !== false;

        if (shouldRefresh && this.recordId) {
            getRecordNotifyChange([{ recordId: this.recordId }]);
            this.dispatchEvent(new RefreshEvent());
        }

        window.setTimeout(() => {
            this.dispatchEvent(new CloseActionScreenEvent());
        }, 0);
    }
}