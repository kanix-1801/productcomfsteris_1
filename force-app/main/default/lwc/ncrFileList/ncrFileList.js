import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import getNcrFilesForReports from '@salesforce/apex/QualityInspectionController.getNcrFilesForReports';
import addNcrFile from '@salesforce/apex/QualityInspectionController.addNcrFile';
import renameNcrFile from '@salesforce/apex/QualityInspectionController.renameNcrFile';
import removeNcrFile from '@salesforce/apex/QualityInspectionController.removeNcrFile';

const FILE_ACCEPT = '.jpg,.jpeg,.png,.gif,.bmp,.webp,.mp4,.mov,.pdf,.doc,.docx,.xls,.xlsx';
const IMAGE_EXTENSIONS = new Set(['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp']);
const DOC_TYPE_BY_EXTENSION = {
    pdf: 'doctype:pdf',
    doc: 'doctype:word',
    docx: 'doctype:word',
    xls: 'doctype:excel',
    xlsx: 'doctype:excel',
    csv: 'doctype:csv',
    txt: 'doctype:txt',
    mp4: 'doctype:video',
    mov: 'doctype:video',
    png: 'doctype:image',
    jpg: 'doctype:image',
    jpeg: 'doctype:image',
    gif: 'doctype:image',
    webp: 'doctype:image',
    bmp: 'doctype:image'
};

/**
 * Files and camera capture for a Nonconformance Report header.
 */
export default class NcrFileList extends LightningElement {
    fileAccept = FILE_ACCEPT;
    files = [];
    isLoading = false;
    isUploading = false;
    isCapturing = false;
    isCameraOpen = false;
    isCameraStarting = false;
    isCameraActive = false;
    cameraError = '';
    cameraOptions = [];
    selectedCameraId;
    deletingDocumentIds = new Set();
    renamingDocumentIds = new Set();
    thumbnailFallbackIds = new Set();

    _reportIds = [];
    _captureReportId;
    mediaStream;
    videoEl;
    canvasEl;

    @api
    get reportIdsKey() {
        return this._reportIds.join(',');
    }

    set reportIdsKey(value) {
        const nextIds = String(value || '')
            .split(',')
            .map((reportId) => reportId.trim())
            .filter((reportId) => reportId);
        const nextKey = nextIds.join(',');
        const previousKey = this._reportIds.join(',');
        this._reportIds = nextIds;
        if (nextKey !== previousKey) {
            this.loadFiles();
        }
    }

    @api
    get recordId() {
        return this._captureReportId;
    }

    set recordId(value) {
        this._captureReportId = value || null;
    }

    disconnectedCallback() {
        this.stopCameraStream();
    }

    get isBusy() {
        return this.isLoading || this.isUploading || this.isCapturing;
    }

    get hasFiles() {
        return this.displayFiles.length > 0;
    }

    get isCaptureDisabled() {
        return !this.isCameraActive || this.isCapturing || this.isUploading;
    }

    get isStopCameraDisabled() {
        return !this.isCameraActive || this.isCameraStarting;
    }

    get displayFiles() {
        return (this.files || []).map((file) => {
            const extension = (file.fileExtension || file.fileType || '').toLowerCase();
            const contentDocumentId = file.contentDocumentId;
            const isImage = file.isImage === true || IMAGE_EXTENSIONS.has(extension);
            const previewUrl = file.imageDownloadUrl || file.thumbnailUrl || file.downloadUrl;
            const showThumbnail =
                isImage &&
                !!previewUrl &&
                !this.thumbnailFallbackIds.has(contentDocumentId);
            const editTitle = file.editTitle != null ? file.editTitle : file.title || '';
            const savedTitle = file.title || '';
            const isRenaming = this.renamingDocumentIds.has(contentDocumentId);
            const isTitleDirty = editTitle.trim() !== savedTitle.trim();
            return {
                ...file,
                fileExtension: extension || '—',
                showThumbnail,
                thumbnailUrl: previewUrl,
                docTypeIcon: DOC_TYPE_BY_EXTENSION[extension] || 'doctype:unknown',
                modifiedLabel: this.formatModified(file.lastModifiedDate),
                isDeleting: this.deletingDocumentIds.has(contentDocumentId),
                editTitle,
                isRenaming,
                isTitleDirty,
                isSaveTitleDisabled: !isTitleDirty || isRenaming,
                titleSaveVariant: isTitleDirty ? 'brand' : 'border-filled',
                titleSaveTitle: isTitleDirty ? 'Save title' : 'No title changes to save',
                titleSaveClass: isTitleDirty
                    ? 'photo-title-save photo-title-save_dirty'
                    : 'photo-title-save photo-title-save_clean',
                titleInputClass: isTitleDirty
                    ? 'photo-title-input photo-title-input_dirty'
                    : 'photo-title-input',
                rowKey: `${file.reportId || ''}:${contentDocumentId}`
            };
        });
    }

    async loadFiles() {
        if (!this._reportIds.length) {
            this.files = [];
            return false;
        }
        const showSpinner = this.files.length === 0;
        if (showSpinner) {
            this.isLoading = true;
        }
        try {
            const rows = await getNcrFilesForReports({ reportIds: this._reportIds });
            this.files = rows || [];
            return true;
        } catch (error) {
            this.showToast('Unable to load photos', this.reduceError(error), 'error');
            return false;
        } finally {
            this.isLoading = false;
        }
    }

    reportIdForFile(contentDocumentId) {
        const current = (this.files || []).find(
            (file) => file.contentDocumentId === contentDocumentId
        );
        return current?.reportId || this._captureReportId;
    }

    /**
     * Opens the file picker. Called from the Nonconformance Report header.
     */
    @api
    chooseFiles() {
        if (this.isBusy || !this._captureReportId) {
            return;
        }
        const input = this.template.querySelector('[data-id="ncr-file-input"]');
        if (input) {
            input.click();
        }
    }

    /**
     * Opens the camera dialog. Called from the Nonconformance Report header.
     * File refresh (isLoading) must not block this; the photo button should open immediately.
     */
    @api
    openCamera() {
        if (this.isUploading || this.isCapturing || !this._captureReportId) {
            return;
        }
        this.handleOpenCamera();
    }

    async handleFilesSelected(event) {
        const selected = Array.from(event.target.files || []);
        event.target.value = '';
        if (!selected.length || !this._captureReportId) {
            return;
        }
        this.isUploading = true;
        try {
            let uploaded = 0;
            for (const file of selected) {
                const base64Data = await this.readFileAsDataUrl(file);
                // One file per call keeps the photo payload inside a single transaction.
                // eslint-disable-next-line no-await-in-loop
                await addNcrFile({
                    reportId: this._captureReportId,
                    base64Data,
                    fileName: file.name
                });
                uploaded += 1;
            }
            const refreshed = await this.loadFiles();
            if (refreshed) {
                this.showToast(
                    'Files added',
                    uploaded === 1
                        ? '1 file added to this Nonconformance Report.'
                        : `${uploaded} files added to this Nonconformance Report.`,
                    'success'
                );
            }
        } catch (error) {
            await this.loadFiles();
            this.showToast('Unable to add the file', this.reduceError(error), 'error');
        } finally {
            this.isUploading = false;
        }
    }

    handleTitleChange(event) {
        const contentDocumentId = event.currentTarget.dataset.docId;
        const value =
            event.detail && event.detail.value != null
                ? event.detail.value
                : event.target.value || '';
        if (!contentDocumentId) {
            return;
        }
        this.files = (this.files || []).map((file) =>
            file.contentDocumentId === contentDocumentId ? { ...file, editTitle: value } : file
        );
    }

    async handleSaveTitle(event) {
        const contentDocumentId = event.currentTarget.dataset.docId;
        const reportId = this.reportIdForFile(contentDocumentId);
        if (!contentDocumentId || !reportId) {
            return;
        }
        const current = (this.files || []).find(
            (file) => file.contentDocumentId === contentDocumentId
        );
        const newTitle = (current?.editTitle || '').trim();
        if (!newTitle) {
            this.showToast('File title is required', 'Enter a title before saving.', 'error');
            return;
        }
        this.renamingDocumentIds = new Set(this.renamingDocumentIds).add(contentDocumentId);
        try {
            const updated = await renameNcrFile({
                reportId,
                contentDocumentId,
                newTitle
            });
            this.files = (this.files || []).map((file) =>
                file.contentDocumentId === contentDocumentId
                    ? { ...file, ...updated, editTitle: updated.title }
                    : file
            );
            this.showToast('Title updated', `File renamed to "${updated.title}".`, 'success');
        } catch (error) {
            this.showToast('Unable to rename the file', this.reduceError(error), 'error');
        } finally {
            const remaining = new Set(this.renamingDocumentIds);
            remaining.delete(contentDocumentId);
            this.renamingDocumentIds = remaining;
        }
    }

    async handleDeleteFile(event) {
        const contentDocumentId = event.currentTarget.dataset.docId;
        const title = event.currentTarget.dataset.title || 'this file';
        const reportId = this.reportIdForFile(contentDocumentId);
        if (!contentDocumentId || !reportId) {
            return;
        }
        const confirmed = await LightningConfirm.open({
            message: `Remove "${title}" from this Nonconformance Report?`,
            label: 'Remove file',
            theme: 'warning'
        });
        if (!confirmed) {
            return;
        }
        this.deletingDocumentIds = new Set(this.deletingDocumentIds).add(contentDocumentId);
        try {
            await removeNcrFile({
                reportId,
                contentDocumentId
            });
            this.files = (this.files || []).filter(
                (file) => file.contentDocumentId !== contentDocumentId
            );
        } catch (error) {
            this.showToast('Unable to remove the file', this.reduceError(error), 'error');
        } finally {
            const remaining = new Set(this.deletingDocumentIds);
            remaining.delete(contentDocumentId);
            this.deletingDocumentIds = remaining;
        }
    }

    handleThumbnailError(event) {
        const contentDocumentId = event.currentTarget.dataset.docId;
        if (!contentDocumentId) {
            return;
        }
        this.thumbnailFallbackIds = new Set(this.thumbnailFallbackIds).add(contentDocumentId);
    }

    async handleOpenCamera() {
        this.cameraError = '';
        this.isCameraOpen = true;
        await this.loadCameras();
    }

    handleCloseCamera() {
        this.stopCameraStream();
        this.isCameraOpen = false;
        this.cameraError = '';
    }

    async loadCameras() {
        this.cameraError = '';
        if (
            !navigator.mediaDevices ||
            typeof navigator.mediaDevices.getUserMedia !== 'function'
        ) {
            this.cameraOptions = [];
            this.cameraError =
                'This browser does not support camera capture. Use Chrome, Edge, Firefox, or Safari.';
            return;
        }
        try {
            const permissionStream = await navigator.mediaDevices.getUserMedia({
                video: true,
                audio: false
            });
            permissionStream.getTracks().forEach((track) => track.stop());
            const devices = await navigator.mediaDevices.enumerateDevices();
            const videoInputs = devices.filter((device) => device.kind === 'videoinput');
            this.cameraOptions = videoInputs.map((device, index) => ({
                label: device.label || `Camera ${index + 1}`,
                value: device.deviceId
            }));
            if (this.cameraOptions.length > 0 && !this.selectedCameraId) {
                this.selectedCameraId = this.cameraOptions[0].value;
            }
            if (this.cameraOptions.length === 0) {
                this.cameraError = 'No cameras were found on this device.';
            }
        } catch (error) {
            this.cameraOptions = [];
            this.cameraError = this.reduceError(
                error,
                'Unable to access cameras. Check browser permissions.'
            );
        }
    }

    handleCameraChange(event) {
        this.selectedCameraId = event.detail.value;
    }

    async handleStartCamera() {
        this.cameraError = '';
        if (!this.selectedCameraId) {
            this.cameraError = 'Select a camera before starting.';
            return;
        }
        this.isCameraStarting = true;
        try {
            this.stopCameraStream();
            this.mediaStream = await this.openCameraStream(this.selectedCameraId);
            this.isCameraActive = true;
            // The video element is manual DOM and is ready on the next tick.
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => this.bindVideoElement(), 0);
        } catch (error) {
            this.isCameraActive = false;
            this.cameraError = this.reduceError(error, 'Failed to start the selected camera.');
        } finally {
            this.isCameraStarting = false;
        }
    }

    async openCameraStream(deviceId) {
        try {
            return await navigator.mediaDevices.getUserMedia({
                audio: false,
                video: {
                    deviceId: { exact: deviceId },
                    width: { ideal: 1280 },
                    height: { ideal: 720 }
                }
            });
        } catch (error) {
            return navigator.mediaDevices.getUserMedia({
                audio: false,
                video: true
            });
        }
    }

    bindVideoElement() {
        this.videoEl = this.template.querySelector('video');
        this.canvasEl = this.template.querySelector('canvas');
        if (this.videoEl && this.mediaStream) {
            this.videoEl.srcObject = this.mediaStream;
            const playPromise = this.videoEl.play();
            if (playPromise && typeof playPromise.catch === 'function') {
                playPromise.catch(() => {
                    // Autoplay can fail briefly; capture still works when a frame is available.
                });
            }
        }
    }

    handleStopCamera() {
        this.stopCameraStream();
    }

    stopCameraStream() {
        if (this.mediaStream) {
            this.mediaStream.getTracks().forEach((track) => track.stop());
            this.mediaStream = undefined;
        }
        if (this.videoEl) {
            this.videoEl.srcObject = null;
        }
        this.isCameraActive = false;
        this.isCameraStarting = false;
    }

    async handleCapturePhoto() {
        if (!this.isCameraActive || this.isCapturing || !this._captureReportId) {
            return;
        }
        this.cameraError = '';
        this.isCapturing = true;
        try {
            if (!this.videoEl) {
                this.bindVideoElement();
            }
            if (!this.videoEl || !this.canvasEl) {
                throw new Error('Camera preview is not ready.');
            }
            const width = this.videoEl.videoWidth || 1280;
            const height = this.videoEl.videoHeight || 720;
            this.canvasEl.width = width;
            this.canvasEl.height = height;
            const context = this.canvasEl.getContext('2d');
            context.drawImage(this.videoEl, 0, 0, width, height);
            const dataUrl = this.canvasEl.toDataURL('image/jpeg', 0.92);
            const fileName = `NCR-${this.todayIsoDate()}-${Date.now()}.jpg`;
            await addNcrFile({
                reportId: this._captureReportId,
                base64Data: dataUrl,
                fileName
            });
            const refreshed = await this.loadFiles();
            if (refreshed) {
                this.showToast(
                    'Photo added',
                    'Photo added to this Nonconformance Report.',
                    'success'
                );
            }
        } catch (error) {
            this.cameraError = this.reduceError(error, 'Unable to capture photo.');
        } finally {
            this.isCapturing = false;
        }
    }

    readFileAsDataUrl(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result);
            reader.onerror = () => reject(new Error('Unable to read the selected file.'));
            reader.readAsDataURL(file);
        });
    }

    formatModified(value) {
        if (!value) {
            return '';
        }
        const parsed = new Date(value);
        if (Number.isNaN(parsed.getTime())) {
            return value;
        }
        return new Intl.DateTimeFormat(undefined, {
            year: 'numeric',
            month: 'short',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit'
        }).format(parsed);
    }

    todayIsoDate() {
        const today = new Date();
        const month = String(today.getMonth() + 1).padStart(2, '0');
        const day = String(today.getDate()).padStart(2, '0');
        return `${today.getFullYear()}-${month}-${day}`;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    reduceError(error, fallbackMessage) {
        return (
            error?.body?.message ||
            error?.body?.pageErrors?.[0]?.message ||
            error?.message ||
            fallbackMessage ||
            'An unexpected error occurred.'
        );
    }
}