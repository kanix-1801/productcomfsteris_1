import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import getPhotos from '@salesforce/apex/EvaluationPhotosController.getPhotos';
import capturePhoto from '@salesforce/apex/EvaluationPhotosController.capturePhoto';
import renamePhoto from '@salesforce/apex/EvaluationPhotosController.renamePhoto';
import deletePhoto from '@salesforce/apex/EvaluationPhotosController.deletePhoto';

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

export default class EvaluationPhotos extends LightningElement {
    fileAccept = FILE_ACCEPT;
    @track photos = [];
    @track cameraOptions = [];
    @track deletingDocumentIds = new Set();
    @track thumbnailFallbackIds = new Set();

    isLoading = false;
    errorMessage = '';
    cameraError = '';
    isPhotoModalOpen = false;
    isCameraStarting = false;
    isCameraActive = false;
    isCapturing = false;
    isUploadingFiles = false;
    selectedCameraId = '';
    mediaStream;
    videoEl;
    canvasEl;
    _workOrderId;

    @api
    get workOrderId() {
        return this._workOrderId;
    }

    set workOrderId(value) {
        const next = value || null;
        const changed = next !== this._workOrderId;
        this._workOrderId = next;
        if (changed && next) {
            this.loadPhotos();
        }
        if (!next) {
            this.photos = [];
        }
    }

    get isBusy() {
        return this.isLoading || this.isUploadingFiles || this.isCapturing;
    }

    get hasPhotos() {
        return (this.photos || []).length > 0;
    }

    get isPhotoModalBusy() {
        return this.isUploadingFiles || this.isCapturing;
    }

    get isCameraBusy() {
        return this.isCameraStarting || this.isCameraActive || !this.selectedCameraId;
    }

    get isCaptureDisabled() {
        return !this.isCameraActive || this.isCapturing;
    }

    get isStopCameraDisabled() {
        return !this.isCameraActive;
    }

    get displayPhotos() {
        return (this.photos || []).map((file) => this.decoratePhoto(file));
    }

    async loadPhotos() {
        if (!this._workOrderId) {
            this.photos = [];
            return;
        }
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const rows = await getPhotos({ workOrderId: this._workOrderId });
            this.photos = (rows || []).map((row) => ({
                ...row,
                editTitle: row.title || ''
            }));
        } catch (error) {
            this.errorMessage = this.resolveErrorMessage(error, 'Unable to load photos.');
        } finally {
            this.isLoading = false;
        }
    }

    decoratePhoto(file) {
        const extension = (file.fileExtension || '').toLowerCase();
        const contentDocumentId = file.contentDocumentId;
        const isImage =
            file.isImage === true ||
            IMAGE_EXTENSIONS.has(extension) ||
            IMAGE_EXTENSIONS.has((file.fileType || '').toLowerCase());
        const previewUrl = this.thumbnailFallbackIds.has(contentDocumentId)
            ? file.imageDownloadUrl || file.downloadUrl
            : file.thumbnailUrl || file.imageDownloadUrl || file.downloadUrl;
        const editTitle = file.editTitle != null ? file.editTitle : file.title || '';
        const savedTitle = file.title || '';
        const isRenaming = this.deletingDocumentIds.has(`rename:${contentDocumentId}`);
        const isTitleDirty = editTitle.trim() !== savedTitle.trim();
        return {
            ...file,
            rowKey: `${contentDocumentId}-${file.linkedEntityId || ''}`,
            fileExtension: extension || (file.fileType || '').toLowerCase() || '—',
            showThumbnail: isImage && !!previewUrl && !this.thumbnailFallbackIds.has(`gone:${contentDocumentId}`),
            thumbnailUrl: previewUrl,
            docTypeIcon: DOC_TYPE_BY_EXTENSION[extension] || 'doctype:attachment',
            modifiedDisplay: this.formatModified(file.lastModifiedDate),
            isDeleting: this.deletingDocumentIds.has(contentDocumentId),
            isRenaming,
            editTitle,
            isTitleDirty,
            isSaveTitleDisabled: !isTitleDirty || isRenaming,
            titleSaveVariant: isTitleDirty ? 'brand' : 'border-filled',
            titleSaveTitle: isTitleDirty ? 'Save title' : 'No title changes to save',
            titleInputClass: isTitleDirty
                ? 'photo-title-input photo-title-input_dirty'
                : 'photo-title-input'
        };
    }

    formatModified(value) {
        if (!value) {
            return '';
        }
        const parsed = new Date(value);
        if (Number.isNaN(parsed.getTime())) {
            return value;
        }
        return parsed.toLocaleString();
    }

    handleThumbnailError(event) {
        const contentDocumentId = event.currentTarget?.dataset?.docId;
        if (!contentDocumentId) {
            return;
        }
        const next = new Set(this.thumbnailFallbackIds);
        if (next.has(contentDocumentId)) {
            next.add(`gone:${contentDocumentId}`);
        } else {
            next.add(contentDocumentId);
        }
        this.thumbnailFallbackIds = next;
    }

    handleTitleChange(event) {
        const contentDocumentId = event.currentTarget.dataset.docId;
        const value = event.detail?.value != null ? event.detail.value : event.target.value || '';
        this.photos = (this.photos || []).map((file) =>
            file.contentDocumentId === contentDocumentId ? { ...file, editTitle: value } : file
        );
    }

    async handleSaveTitle(event) {
        const contentDocumentId = event.currentTarget.dataset.docId;
        const photo = (this.photos || []).find((file) => file.contentDocumentId === contentDocumentId);
        const newTitle = (photo?.editTitle || '').trim();
        if (!contentDocumentId || !newTitle) {
            this.errorMessage = 'Photo title is required.';
            return;
        }
        this.markBusy(`rename:${contentDocumentId}`, true);
        this.errorMessage = '';
        try {
            const updated = await renamePhoto({ contentDocumentId, newTitle });
            this.photos = (this.photos || []).map((file) => {
                if (file.contentDocumentId !== contentDocumentId) {
                    return file;
                }
                return {
                    ...file,
                    title: updated.title,
                    editTitle: updated.title,
                    lastModifiedDate: updated.lastModifiedDate
                };
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Title updated',
                    message: `Photo renamed to "${updated.title}".`,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.errorMessage = this.resolveErrorMessage(error, 'Unable to rename photo.');
        } finally {
            this.markBusy(`rename:${contentDocumentId}`, false);
        }
    }

    async handleDelete(event) {
        const contentDocumentId = event.currentTarget.dataset.docId;
        const linkedEntityId = event.currentTarget.dataset.linkedId;
        const title = event.currentTarget.dataset.title || 'this photo';
        if (!contentDocumentId || !linkedEntityId || !this._workOrderId) {
            return;
        }
        const confirmed = await LightningConfirm.open({
            message: `Delete "${title}"? This removes the photo from the Work Order.`,
            label: 'Delete photo',
            theme: 'warning'
        });
        if (!confirmed) {
            return;
        }
        this.markBusy(contentDocumentId, true);
        this.errorMessage = '';
        try {
            await deletePhoto({
                workOrderId: this._workOrderId,
                linkedEntityId,
                contentDocumentId
            });
            this.photos = (this.photos || []).filter(
                (file) =>
                    file.contentDocumentId !== contentDocumentId ||
                    file.linkedEntityId !== linkedEntityId
            );
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Photo deleted',
                    message: 'The photo was removed.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.errorMessage = this.resolveErrorMessage(error, 'Unable to delete photo.');
        } finally {
            this.markBusy(contentDocumentId, false);
        }
    }

    markBusy(key, isBusy) {
        const next = new Set(this.deletingDocumentIds);
        if (isBusy) {
            next.add(key);
        } else {
            next.delete(key);
        }
        this.deletingDocumentIds = next;
    }

    disconnectedCallback() {
        if (this.isPhotoModalOpen) {
            this.notifyModal(false);
        }
        this.stopCameraStream();
    }

    async handleTakePhotoClick() {
        if (!this._workOrderId) {
            this.errorMessage = 'Open a Work Order before taking a photo.';
            return;
        }
        this.isPhotoModalOpen = true;
        this.cameraError = '';
        this.notifyModal(true);
        await this.loadCameras();
    }

    handleClosePhotoModal() {
        this.stopCameraStream();
        this.isPhotoModalOpen = false;
        this.cameraError = '';
        this.notifyModal(false);
    }

    /**
     * GW-4378 - Asks the evaluation workspace to drop the header behind this dialog.
     * @param {Boolean} open true while the take-photo dialog is open
     */
    notifyModal(open) {
        this.dispatchEvent(
            new CustomEvent('modalchange', {
                bubbles: true,
                composed: true,
                detail: { open }
            })
        );
    }

    handleChooseFilesClick() {
        const input = this.template.querySelector('[data-id="photo-file-input"]');
        if (input) {
            input.click();
        }
    }

    async handleFileSelected(event) {
        const files = Array.from(event.target.files || []);
        event.target.value = '';
        if (!files.length) {
            return;
        }
        this.isUploadingFiles = true;
        this.cameraError = '';
        try {
            let uploaded = 0;
            for (const file of files) {
                const base64Data = await this.readFileAsDataUrl(file);
                const saved = await capturePhoto({
                    workOrderId: this._workOrderId,
                    base64Data,
                    fileName: file.name
                });
                this.upsertPhoto(saved);
                uploaded += 1;
            }
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Photo saved',
                    message:
                        uploaded === 1
                            ? '1 photo saved on this Work Order.'
                            : `${uploaded} photos saved on this Work Order.`,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.cameraError = this.resolveErrorMessage(error, 'Unable to upload photos.');
        } finally {
            this.isUploadingFiles = false;
        }
    }

    async loadCameras() {
        this.cameraError = '';
        if (!navigator.mediaDevices || typeof navigator.mediaDevices.getUserMedia !== 'function') {
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
            this.cameraError = this.resolveErrorMessage(
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
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => this.bindVideoElement(), 0);
        } catch (error) {
            this.isCameraActive = false;
            this.cameraError = this.resolveErrorMessage(error, 'Failed to start the selected camera.');
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
                    // Autoplay can fail briefly; capture still works once a frame is available.
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
        if (!this.isCameraActive || this.isCapturing) {
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
            const saved = await capturePhoto({
                workOrderId: this._workOrderId,
                base64Data: this.canvasEl.toDataURL('image/jpeg', 0.92),
                fileName: 'photo.jpg'
            });
            this.upsertPhoto(saved);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Photo saved',
                    message: 'Photo saved on this Work Order.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.cameraError = this.resolveErrorMessage(error, 'Unable to capture photo.');
        } finally {
            this.isCapturing = false;
        }
    }

    upsertPhoto(saved) {
        if (!saved?.contentDocumentId) {
            return;
        }
        const next = [...(this.photos || [])];
        const index = next.findIndex(
            (file) =>
                file.contentDocumentId === saved.contentDocumentId &&
                file.linkedEntityId === saved.linkedEntityId
        );
        const row = { ...saved, editTitle: saved.title || '' };
        if (index >= 0) {
            next[index] = row;
        } else {
            next.unshift(row);
        }
        this.photos = next;
    }

    readFileAsDataUrl(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result);
            reader.onerror = () => reject(new Error('Unable to read the selected file.'));
            reader.readAsDataURL(file);
        });
    }

    resolveErrorMessage(error, fallbackMessage) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body) && error.body.length > 0 && error.body[0].message) {
            return error.body[0].message;
        }
        if (error?.message) {
            return error.message;
        }
        return fallbackMessage;
    }
}