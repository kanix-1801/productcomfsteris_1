import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import { RefreshEvent } from 'lightning/refresh';
import GenerateQuote from 'c/generateQuote';

export default class CopyQuoteAction extends LightningElement {
    @api recordId;

    quoteComponent = GenerateQuote;

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