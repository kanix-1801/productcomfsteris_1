import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import listWorkOrderLineItemFiles from '@salesforce/apex/WorkOrderLineItemCaptureService.listWorkOrderLineItemFiles';
import updateMicroscopeImageCategory from '@salesforce/apex/WorkOrderLineItemCaptureService.updateMicroscopeImageCategory';
import deleteMicroscopeImageFile from '@salesforce/apex/WorkOrderLineItemCaptureService.deleteMicroscopeImageFile';
import {
    BEYOND_REPAIR_CATEGORY,
    BEYOND_REPAIR_REASON_OPTIONS,
    IMAGE_CATEGORY_OPTIONS
} from 'c/woliCaptureUpload';

const IMAGE_EXTENSIONS = new Set(['png', 'jpg', 'jpeg', 'gif', 'webp']);
const THUMBNAIL_PROXY_PATH = '/services/apexrest/woli/v1/file-thumbnail/';

const DOC_TYPE_BY_EXTENSION = {
    pdf: 'doctype:pdf',
    doc: 'doctype:word',
    docx: 'doctype:word',
    xls: 'doctype:excel',
    xlsx: 'doctype:excel',
    ppt: 'doctype:ppt',
    pptx: 'doctype:ppt',
    txt: 'doctype:txt',
    zip: 'doctype:zip',
    csv: 'doctype:csv'
};

/**
 * GW-1505 — Files-style list with preview, thumbnails, editable Category, and delete.
 */
export default class WoliFileList extends NavigationMixin(LightningElement) {
    @api recordId;

    fileRows = [];
    isLoading = false;
    updatingCategoryDocumentId;
    deletingDocumentId;
    errorMessage;

    connectedCallback() {
        if (this.recordId) {
            this.refreshFileList();
        }
    }

    get hasFileRows() {
        return this.fileRows.length > 0;
    }

    get fileCountLabel() {
        const count = this.fileRows.length;
        return count === 1 ? '1 item' : `${count} items`;
    }

    get displayFileRows() {
        return this.fileRows.map((row) => ({
            ...row,
            isUpdatingCategory: this.updatingCategoryDocumentId === row.contentDocumentId,
            isDeleting: this.deletingDocumentId === row.contentDocumentId,
            showBeyondRepairReason: row.category === BEYOND_REPAIR_CATEGORY
        }));
    }

    get categoryOptions() {
        return IMAGE_CATEGORY_OPTIONS;
    }

    get beyondRepairReasonOptions() {
        return BEYOND_REPAIR_REASON_OPTIONS;
    }

    async refreshFileList() {
        if (!this.recordId) {
            this.fileRows = [];
            return;
        }
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const files = await listWorkOrderLineItemFiles({
                workOrderLineItemId: this.recordId
            });
            this.fileRows = (files || []).map((file) => this.buildFileRow(file));
        } catch (error) {
            this.errorMessage = this.resolveErrorMessage(error, 'Could not load files on this line item.');
        } finally {
            this.isLoading = false;
        }
    }

    buildFileRow(file) {
        const extension = (file.fileExtension || '').toLowerCase();
        const thumbnailUrl = this.resolveThumbnailUrl(file);
        return {
            contentDocumentId: file.contentDocumentId,
            contentVersionId: file.contentVersionId,
            title: file.title,
            fileExtension: extension,
            category: file.category || '',
            beyondRepairReason: file.beyondRepairReason || '',
            createdDate: file.createdDate,
            ownerName: file.ownerName || '',
            sizeLabel: this.formatFileSize(file.contentSize),
            typeLabel: extension ? extension.toUpperCase() : 'FILE',
            rowKey: file.contentDocumentId,
            thumbnailUrl,
            apexThumbnailUrl: file.thumbnailUrl || null,
            imageDownloadUrl: file.imageDownloadUrl || null,
            showThumbnail: !!thumbnailUrl,
            docTypeIcon: this.resolveDocTypeIcon(extension)
        };
    }

    resolveThumbnailUrl(file) {
        const extension = (file.fileExtension || '').toLowerCase();
        if (!IMAGE_EXTENSIONS.has(extension) || !file.contentVersionId) {
            return null;
        }
        return THUMBNAIL_PROXY_PATH + file.contentVersionId;
    }

    handleThumbnailError(event) {
        const contentDocumentId = event.currentTarget.dataset.docId;
        if (!contentDocumentId) {
            return;
        }
        this.fileRows = this.fileRows.map((row) => {
            if (row.contentDocumentId !== contentDocumentId) {
                return row;
            }
            if (
                row.thumbnailUrl &&
                row.thumbnailUrl.startsWith(THUMBNAIL_PROXY_PATH) &&
                row.apexThumbnailUrl
            ) {
                return { ...row, thumbnailUrl: row.apexThumbnailUrl };
            }
            if (row.thumbnailUrl === row.apexThumbnailUrl && row.imageDownloadUrl) {
                return { ...row, thumbnailUrl: row.imageDownloadUrl };
            }
            return { ...row, showThumbnail: false };
        });
    }

    resolveDocTypeIcon(extension) {
        const normalizedExtension = (extension || '').toLowerCase();
        if (['png', 'jpg', 'jpeg', 'gif', 'webp'].includes(normalizedExtension)) {
            return 'doctype:image';
        }
        return DOC_TYPE_BY_EXTENSION[normalizedExtension] || 'doctype:attachment';
    }

    formatFileSize(bytes) {
        const size = Number(bytes);
        if (!size || size < 1) {
            return '—';
        }
        if (size < 1024) {
            return `${size} B`;
        }
        if (size < 1024 * 1024) {
            return `${(size / 1024).toFixed(1)} KB`;
        }
        return `${(size / (1024 * 1024)).toFixed(1)} MB`;
    }

    async handleRefresh() {
        await this.refreshFileList();
    }

    handleOpenFilePreview(event) {
        const contentDocumentId = event.currentTarget.dataset.docId;
        if (!contentDocumentId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'filePreview'
            },
            state: {
                selectedRecordId: contentDocumentId
            }
        });
    }

    handleCategoryChange(event) {
        const contentDocumentId = event.currentTarget.dataset.docId;
        const category = event.detail.value || '';
        if (!this.recordId || !contentDocumentId) {
            return;
        }
        const currentRow = this.fileRows.find((row) => row.contentDocumentId === contentDocumentId);
        const beyondRepairReason =
            category === BEYOND_REPAIR_CATEGORY ? currentRow?.beyondRepairReason || '' : '';
        this.persistFileMetadata(contentDocumentId, category, beyondRepairReason);
    }

    handleBeyondRepairReasonChange(event) {
        const contentDocumentId = event.currentTarget.dataset.docId;
        const beyondRepairReason = event.detail.value || '';
        if (!this.recordId || !contentDocumentId) {
            return;
        }
        const currentRow = this.fileRows.find((row) => row.contentDocumentId === contentDocumentId);
        this.persistFileMetadata(
            contentDocumentId,
            currentRow?.category || BEYOND_REPAIR_CATEGORY,
            beyondRepairReason
        );
    }

    async handleDeleteFile(event) {
        const contentDocumentId = event.currentTarget.dataset.docId;
        if (!this.recordId || !contentDocumentId) {
            return;
        }
        const currentRow = this.fileRows.find((row) => row.contentDocumentId === contentDocumentId);
        const fileLabel = currentRow?.title || 'this file';
        // eslint-disable-next-line no-alert
        const confirmed = window.confirm(`Delete ${fileLabel} from this Work Order Line Item?`);
        if (!confirmed) {
            return;
        }

        this.deletingDocumentId = contentDocumentId;
        this.errorMessage = undefined;
        try {
            const result = await deleteMicroscopeImageFile({
                workOrderLineItemId: this.recordId,
                contentDocumentId
            });
            if (!result || result.success !== true) {
                const failureMessage = result?.message || 'Could not delete the selected file.';
                this.errorMessage = failureMessage;
                this.dispatchToast('Delete failed', failureMessage, 'error');
                return;
            }
            this.dispatchToast('File deleted', fileLabel, 'success');
            await this.refreshFileList();
        } catch (error) {
            this.errorMessage = this.resolveErrorMessage(error, 'Could not delete the selected file.');
            this.dispatchToast('Delete failed', this.errorMessage, 'error');
        } finally {
            this.deletingDocumentId = undefined;
        }
    }

    async persistFileMetadata(contentDocumentId, category, beyondRepairReason) {
        this.updatingCategoryDocumentId = contentDocumentId;
        this.errorMessage = undefined;
        try {
            const result = await updateMicroscopeImageCategory({
                workOrderLineItemId: this.recordId,
                contentDocumentId,
                category,
                beyondRepairReason
            });
            if (!result || result.success !== true) {
                const failureMessage = result?.message || 'Could not update the file metadata.';
                this.errorMessage = failureMessage;
                this.dispatchToast('Update failed', failureMessage, 'error');
                return;
            }
            await this.refreshFileList();
        } catch (error) {
            this.errorMessage = this.resolveErrorMessage(error, 'Could not update the file metadata.');
            this.dispatchToast('Update failed', this.errorMessage, 'error');
        } finally {
            this.updatingCategoryDocumentId = undefined;
        }
    }

    resolveErrorMessage(error, fallback) {
        if (!error) {
            return fallback;
        }
        if (typeof error.body === 'string' && error.body) {
            return error.body;
        }
        if (error.body?.message) {
            return error.body.message;
        }
        if (error.message) {
            return error.message;
        }
        return fallback;
    }

    dispatchToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}