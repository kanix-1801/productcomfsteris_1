import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTemplateDownloadUrl from '@salesforce/apex/TechAccountAlignmentController.getTemplateDownloadUrl';
import processUpload from '@salesforce/apex/TechAccountAlignmentController.processUpload';

const VISIBLE_ERROR_LIMIT = 20;

export default class TechAccountAlignment extends NavigationMixin(LightningElement) {
    acceptedFormats = ['.csv', '.xlsx'];
    contentDocumentId;
    uploadedFileName;
    isBusy = false;
    resultSummary;
    errors = [];

    get isStartDisabled() {
        return this.isBusy || !this.contentDocumentId;
    }

    get hasErrors() {
        return this.errors && this.errors.length > 0;
    }

    get visibleErrors() {
        return (this.errors || []).slice(0, VISIBLE_ERROR_LIMIT).map((message, index) => ({
            key: String(index),
            message
        }));
    }

    handleUploadFinished(event) {
        const uploadedFiles = event.detail.files || [];
        if (uploadedFiles.length === 0) {
            return;
        }
        const uploadedFile = uploadedFiles[0];
        this.contentDocumentId = uploadedFile.documentId;
        this.uploadedFileName = uploadedFile.name;
        this.resultSummary = undefined;
        this.errors = [];
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'File uploaded',
                message: uploadedFile.name + ' is ready. Click Start Upload to process.',
                variant: 'success'
            })
        );
    }

    handleDownloadTemplate() {
        this.isBusy = true;
        getTemplateDownloadUrl()
            .then((url) => {
                this[NavigationMixin.Navigate]({
                    type: 'standard__webPage',
                    attributes: {
                        url
                    }
                });
            })
            .catch((error) => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Template download failed',
                        message: this.reduceError(error),
                        variant: 'error'
                    })
                );
            })
            .finally(() => {
                this.isBusy = false;
            });
    }

    handleStartUpload() {
        if (!this.contentDocumentId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'No file selected',
                    message: 'Upload a file before clicking Start Upload.',
                    variant: 'warning'
                })
            );
            return;
        }

        this.isBusy = true;
        this.resultSummary = undefined;
        this.errors = [];
        processUpload({ contentDocumentId: this.contentDocumentId })
            .then((result) => {
                this.errors = result.errors || [];
                this.resultSummary =
                    'Processed ' +
                    result.processedCount +
                    ' row(s). Created ' +
                    result.createdCount +
                    ', skipped ' +
                    result.skippedCount +
                    '.';
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Upload complete',
                        message: this.resultSummary,
                        variant: result.createdCount > 0 ? 'success' : 'info'
                    })
                );
            })
            .catch((error) => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Upload failed',
                        message: this.reduceError(error),
                        variant: 'error'
                    })
                );
            })
            .finally(() => {
                this.isBusy = false;
            });
    }

    reduceError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        if (error && error.message) {
            return error.message;
        }
        return 'Unexpected error.';
    }
}