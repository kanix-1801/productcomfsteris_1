import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTemplateDownloadUrl from '@salesforce/apex/DistrictZoneAlignmentController.getTemplateDownloadUrl';
import getErrorFileDownloadUrl from '@salesforce/apex/DistrictZoneAlignmentController.getErrorFileDownloadUrl';
import processUpload from '@salesforce/apex/DistrictZoneAlignmentController.processUpload';
import cardTitle from '@salesforce/label/c.DZA_CardTitle';
import instructions from '@salesforce/label/c.DZA_Instructions';
import uploadLabel from '@salesforce/label/c.DZA_UploadLabel';
import selectedFile from '@salesforce/label/c.DZA_SelectedFile';
import startUpload from '@salesforce/label/c.DZA_StartUpload';
import downloadTemplate from '@salesforce/label/c.DZA_DownloadTemplate';
import downloadErrorFile from '@salesforce/label/c.DZA_DownloadErrorFile';
import processing from '@salesforce/label/c.DZA_Processing';
import fileUploadedTitle from '@salesforce/label/c.DZA_FileUploadedTitle';
import fileUploadedMessage from '@salesforce/label/c.DZA_FileUploadedMessage';
import uploadCompleteTitle from '@salesforce/label/c.DZA_UploadCompleteTitle';
import uploadFailedTitle from '@salesforce/label/c.DZA_UploadFailedTitle';
import downloadFailedTitle from '@salesforce/label/c.DZA_DownloadFailedTitle';
import emailSent from '@salesforce/label/c.DZA_EmailSent';
import emailNotSent from '@salesforce/label/c.DZA_EmailNotSent';
import moreErrors from '@salesforce/label/c.DZA_MoreErrors';
import unexpectedError from '@salesforce/label/c.DZA_UnexpectedError';

const VISIBLE_ERROR_LIMIT = 20;

/**
 * GW-2706: District Zone Alignment. Uploads the district to zone Excel file, starts processing and
 * downloads the template or the user's latest error file. Opened from the Field Service Backoffice Tool.
 */
export default class DistrictZoneAlignment extends NavigationMixin(LightningElement) {
    label = {
        cardTitle,
        instructions,
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
    result;

    get isStartDisabled() {
        return this.isBusy || !this.contentDocumentId;
    }

    get uploadedFileText() {
        return this.uploadedFileName ? format(selectedFile, this.uploadedFileName) : undefined;
    }

    get emailMessage() {
        return this.result && this.result.emailSent ? emailSent : emailNotSent;
    }

    get hasErrors() {
        return Boolean(this.result && this.result.errors && this.result.errors.length);
    }

    get hasHiddenErrors() {
        return this.hasErrors && this.result.errors.length > VISIBLE_ERROR_LIMIT;
    }

    get moreErrorsText() {
        return format(moreErrors, VISIBLE_ERROR_LIMIT);
    }

    get visibleErrors() {
        return this.result.errors.slice(0, VISIBLE_ERROR_LIMIT).map((message, index) => ({
            key: String(index),
            message
        }));
    }

    handleUploadFinished(event) {
        const uploadedFiles = event.detail.files || [];
        if (!uploadedFiles.length) {
            return;
        }
        this.contentDocumentId = uploadedFiles[0].documentId;
        this.uploadedFileName = uploadedFiles[0].name;
        this.result = undefined;
        this.showToast(fileUploadedTitle, format(fileUploadedMessage, this.uploadedFileName), 'success');
    }

    handleDownloadTemplate() {
        this.openFile(getTemplateDownloadUrl);
    }

    handleDownloadErrorFile() {
        this.openFile(getErrorFileDownloadUrl);
    }

    handleStartUpload() {
        this.isBusy = true;
        this.result = undefined;
        processUpload({ contentDocumentId: this.contentDocumentId })
            .then((result) => {
                this.result = result;
                this.showToast(uploadCompleteTitle, result.summary, result.skippedCount > 0 ? 'warning' : 'success');
            })
            .catch((error) => {
                this.showToast(uploadFailedTitle, reduceError(error), 'error');
            })
            .finally(() => {
                this.isBusy = false;
            });
    }

    openFile(getUrl) {
        this.isBusy = true;
        getUrl()
            .then((url) => {
                this[NavigationMixin.Navigate]({
                    type: 'standard__webPage',
                    attributes: { url }
                });
            })
            .catch((error) => {
                this.showToast(downloadFailedTitle, reduceError(error), 'error');
            })
            .finally(() => {
                this.isBusy = false;
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}

function format(text, value) {
    return text.replace('{0}', value);
}

function reduceError(error) {
    if (error && error.body && error.body.message) {
        return error.body.message;
    }
    return unexpectedError;
}