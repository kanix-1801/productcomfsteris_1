import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTemplateDownloadUrl from '@salesforce/apex/DistrictZoneAlignmentController.getTemplateDownloadUrl';
import getErrorFileDownloadUrl from '@salesforce/apex/DistrictZoneAlignmentController.getErrorFileDownloadUrl';
import processUpload from '@salesforce/apex/DistrictZoneAlignmentController.processUpload';

const VISIBLE_ERROR_LIMIT = 20;

export default class DistrictZoneAlignment extends NavigationMixin(LightningElement) {
    acceptedFormats = ['.csv', '.xlsx'];
    visibleErrorLimit = VISIBLE_ERROR_LIMIT;
    contentDocumentId;
    uploadedFileName;
    isBusy = false;
    resultSummary;
    emailMessage;
    errors = [];

    get isStartDisabled() {
        return this.isBusy || !this.contentDocumentId;
    }

    get hasErrors() {
        return this.errors && this.errors.length > 0;
    }

    get hasHiddenErrors() {
        return this.errors && this.errors.length > VISIBLE_ERROR_LIMIT;
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
        this.emailMessage = undefined;
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
        this.openFile(getTemplateDownloadUrl, 'Template download failed');
    }

    handleDownloadErrorFile() {
        this.openFile(getErrorFileDownloadUrl, 'Error file download failed');
    }

    openFile(getUrl, failureTitle) {
        this.isBusy = true;
        getUrl()
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
                        title: failureTitle,
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
        this.emailMessage = undefined;
        this.errors = [];
        processUpload({ contentDocumentId: this.contentDocumentId })
            .then((result) => {
                this.errors = result.errors || [];
                this.resultSummary =
                    'Processed ' +
                    result.processedCount +
                    ' row(s). Created ' +
                    result.createdCount +
                    ', updated ' +
                    result.updatedCount +
                    ', unchanged ' +
                    result.unchangedCount +
                    ', skipped ' +
                    result.skippedCount +
                    '.';
                this.emailMessage = result.emailSent
                    ? 'The error file has been emailed to you. Use Download Error File to get it again.'
                    : 'The error file could not be emailed. Use Download Error File to get it.';
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Upload complete',
                        message: this.resultSummary,
                        variant: result.skippedCount > 0 ? 'warning' : 'success'
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