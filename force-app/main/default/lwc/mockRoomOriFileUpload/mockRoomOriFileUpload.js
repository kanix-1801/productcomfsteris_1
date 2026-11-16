import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';

export default class MockRoomOriFileUpload extends LightningElement {
    @api recordId;

    _uploadedDocumentIds = '';
    _fileNames = '';
    hideNativeLabelStyleApplied = false;

    @api
    get uploadedDocumentIds() {
        return this._uploadedDocumentIds;
    }
    set uploadedDocumentIds(value) {
        this._uploadedDocumentIds = value || '';
    }

    @api
    get fileNames() {
        return this._fileNames;
    }
    set fileNames(value) {
        this._fileNames = value || '';
    }

    /** lightning-file-upload renders its own label inside its shadow tree. This hides it so the custom label and help icon are shown. */
    renderedCallback() {
        const upload = this.template.querySelector('.native-upload');
        if (this.hideNativeLabelStyleApplied || !upload) {
            return;
        }
        const style = document.createElement('style');
        style.innerText = '.native-upload .slds-form-element__label{position:absolute!important;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0;}';
        upload.appendChild(style);
        this.hideNativeLabelStyleApplied = true;
    }

    get hasUploads() {
        return !!this._fileNames;
    }

    /** Appends the new files to any uploaded earlier, so returning to this screen keeps them. */
    handleUploadFinished(event) {
        const files = event.detail.files || [];
        this._uploadedDocumentIds = [this._uploadedDocumentIds, ...files.map((file) => file.documentId)].filter(Boolean).join(',');
        this._fileNames = [this._fileNames, ...files.map((file) => file.name)].filter(Boolean).join(', ');
        this.dispatchEvent(new FlowAttributeChangeEvent('uploadedDocumentIds', this._uploadedDocumentIds));
        this.dispatchEvent(new FlowAttributeChangeEvent('fileNames', this._fileNames));
    }
}