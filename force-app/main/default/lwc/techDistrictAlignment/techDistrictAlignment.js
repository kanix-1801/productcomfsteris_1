import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTemplateDownloadUrl from '@salesforce/apex/DistrictZoneAlignmentController.getTemplateDownloadUrl';
import getErrorFileDownloadUrl from '@salesforce/apex/DistrictZoneAlignmentController.getErrorFileDownloadUrl';
import processUpload from '@salesforce/apex/DistrictZoneAlignmentController.processUpload';
import cardTitle from '@salesforce/label/c.TDA_CardTitle';
import instructionsProcess from '@salesforce/label/c.TDA_InstructionsProcess';
import instructionsColumns from '@salesforce/label/c.TDA_InstructionsColumns';
import uploadLabel from '@salesforce/label/c.TDA_UploadLabel';
import selectedFile from '@salesforce/label/c.TDA_SelectedFile';
import startUpload from '@salesforce/label/c.TDA_StartUpload';
import downloadTemplate from '@salesforce/label/c.TDA_DownloadTemplate';
import downloadErrorFile from '@salesforce/label/c.TDA_DownloadErrorFile';
import processing from '@salesforce/label/c.TDA_Processing';
import fileUploadedTitle from '@salesforce/label/c.TDA_FileUploadedTitle';
import fileUploadedMessage from '@salesforce/label/c.TDA_FileUploadedMessage';
import downloadTemplateFailed from '@salesforce/label/c.TDA_DownloadTemplateFailed';
import downloadErrorFileFailed from '@salesforce/label/c.TDA_DownloadErrorFileFailed';
import noFileSelectedTitle from '@salesforce/label/c.TDA_NoFileSelectedTitle';
import fileRequired from '@salesforce/label/c.TDA_FileRequired';
import uploadComplete from '@salesforce/label/c.TDA_UploadComplete';
import uploadFailed from '@salesforce/label/c.TDA_UploadFailed';
import emailSent from '@salesforce/label/c.TDA_EmailSent';
import emailNotSent from '@salesforce/label/c.TDA_EmailNotSent';
import moreErrors from '@salesforce/label/c.TDA_MoreErrors';
import unexpectedError from '@salesforce/label/c.TDA_UnexpectedError';

const VISIBLE_ERROR_LIMIT = 20;

/**
 * GW-2707: Tech District Alignment. Uploads the Excel file, starts processing and downloads the template or the
 * user's latest error file. Opened from the Field Service Backoffice Tool.
 */
export default class TechDistrictAlignment extends NavigationMixin(LightningElement) {
    label = {
        cardTitle,
        instructionsProcess,
        instructionsColumns,
        uploadLabel,
        startUpload,
        downloadTemplate,
        downloadErrorFile,
        processing
    };
    acceptedFormats = ['.xlsx'];
    contentDocumentId;
    uploadedFileName;
    isBusy = false;
    resultSummary;
    emailMessage;
    errors = [];

    get isStartDisabled() {
        return this.isBusy || !this.contentDocumentId;
    }

    get selectedFileText() {
        return format(selectedFile, this.uploadedFileName);
    }

    get moreErrorsText() {
        return format(moreErrors, VISIBLE_ERROR_LIMIT);
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
                title: fileUploadedTitle,
                message: format(fileUploadedMessage, uploadedFile.name),
                variant: 'success'
            })
        );
    }

    handleDownloadTemplate() {
        this.openFile(getTemplateDownloadUrl, downloadTemplateFailed);
    }

    handleDownloadErrorFile() {
        this.openFile(getErrorFileDownloadUrl, downloadErrorFileFailed);
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
                    title: noFileSelectedTitle,
                    message: fileRequired,
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
                this.resultSummary = result.summary;
                this.emailMessage = result.emailSent ? emailSent : emailNotSent;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: uploadComplete,
                        message: this.resultSummary,
                        variant: result.skippedCount > 0 ? 'warning' : 'success'
                    })
                );
            })
            .catch((error) => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: uploadFailed,
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
        return unexpectedError;
    }
}

function format(text, value) {
    return text.replace('{0}', value);
}