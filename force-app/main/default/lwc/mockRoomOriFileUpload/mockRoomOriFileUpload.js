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