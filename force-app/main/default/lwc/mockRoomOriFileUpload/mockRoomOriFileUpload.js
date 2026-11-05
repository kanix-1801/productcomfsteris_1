import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';

export default class MockRoomOriFileUpload extends LightningElement {
    @api recordId;

    _uploadedDocumentIds = '';
    _fileNames = '';

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

    hideNativeLabelStyleApplied = false;

    renderedCallback() {
        if (this.hideNativeLabelStyleApplied) {
            return;
        }
        const upload = this.template.querySelector('.native-upload');
        if (!upload) {
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

    handleUploadFinished(event) {
        const files = event.detail.files || [];
        const existingIds = this._uploadedDocumentIds ? this._uploadedDocumentIds.split(',') : [];
        const existingNames = this._fileNames ? this._fileNames.split(', ') : [];
        this._uploadedDocumentIds = [...existingIds, ...files.map((file) => file.documentId)].join(',');
        this._fileNames = [...existingNames, ...files.map((file) => file.name)].join(', ');
        this.dispatchEvent(new FlowAttributeChangeEvent('uploadedDocumentIds', this._uploadedDocumentIds));
        this.dispatchEvent(new FlowAttributeChangeEvent('fileNames', this._fileNames));
    }

    @api
    validate() {
        return { isValid: true };
    }
}