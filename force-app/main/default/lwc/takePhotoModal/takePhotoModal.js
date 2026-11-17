import { LightningElement, api } from 'lwc';
import stageReceivingPhoto from '@salesforce/apex/ReceivingController.stageReceivingPhoto';
import deleteReceivingPhoto from '@salesforce/apex/ReceivingController.deleteReceivingPhoto';
import renameReceivingPhoto from '@salesforce/apex/ReceivingController.renameReceivingPhoto';
import stageModFormPhoto from '@salesforce/apex/ReceivingController.stageModFormPhoto';
import deleteModFormPhoto from '@salesforce/apex/ReceivingController.deleteModFormPhoto';
import renameModFormPhoto from '@salesforce/apex/ReceivingController.renameModFormPhoto';

const DEFAULT_ACCEPT =
    '.png,.jpg,.jpeg,.gif,.bmp,.webp,.heic,.mp4,.mov,.avi,.wmv,.mkv,.webm,.m4v,.3gp,image/*,video/*';
const MODE_RECEIVING = 'receiving';
const MODE_MOD_FORM = 'modForm';

/**
 * Shared Upload or Capture modal (camera + file upload/drop) for Create RO and Receiving.
 * Staging mode:
 * - receiving: ReceivingController.stageReceivingPhoto (pre-create / Take a Picture)
 * - modForm: ReceivingController.stageModFormPhoto (attach to Return Order)
 */
export default class TakePhotoModal extends LightningElement {
    _isOpen = false;
    _photos = [];
    _editTitleById = {};

    @api title = 'Upload or Capture';
    @api subtitle =
        'Capture with the camera or upload files. Photos are attached when the order is saved.';
    @api emptyMessage = 'No photos yet.';
    @api accept = DEFAULT_ACCEPT;
    @api contextKey = '';
    /** receiving | modForm */
    @api mode = MODE_RECEIVING;
    /** Required when mode is modForm (Return Order Id). */
    @api recordId = '';
    @api enableTitleEdit = false;
    /**
     * auto: modal stages/deletes/renames via Apex.
     * parent: modal stages new files; delete/rename are emitted for the parent to persist.
     */
    @api persistenceMode = 'auto';

    cameraOptions = [];
    selectedCameraId = '';
    cameraError;
    isBusy = false;
    isDropActive = false;
    isCameraActive = false;
    isCameraStarting = false;
    isCapturing = false;
    renamingDocumentIds = new Set();
    mediaStream;
    videoEl;
    canvasEl;
    _thumbnailFailedById = {};

    @api
    get isOpen() {
        return this._isOpen;
    }
    set isOpen(value) {
        const next = value === true || value === 'true';
        const wasOpen = this._isOpen;
        this._isOpen = next;
        if (next && !wasOpen) {
            this._editTitleById = {};
            (this._photos || []).forEach((photo) => {
                if (photo?.contentDocumentId) {
                    this._editTitleById[photo.contentDocumentId] =
                        photo.editTitle || photo.title || photo.name || '';
                }
            });
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            window.setTimeout(() => {
                this.bindCameraElements();
                this.loadCameras();
            }, 0);
        }
        if (!next && wasOpen) {
            this.handleStopCamera();
            this.cameraError = undefined;
        }
    }

    @api
    get photos() {
        return this._photos;
    }
    set photos(value) {
        this._photos = Array.isArray(value) ? value : [];
        const nextTitles = { ...this._editTitleById };
        this._photos.forEach((photo) => {
            if (!photo?.contentDocumentId) {
                return;
            }
            if (nextTitles[photo.contentDocumentId] == null) {
                nextTitles[photo.contentDocumentId] =
                    photo.editTitle || photo.title || photo.name || '';
            }
        });
        this._editTitleById = nextTitles;
    }

    get resolvedTitle() {
        return this.title || 'Upload or Capture';
    }

    get dropzoneClass() {
        return this.isDropActive
            ? 'take-photo-dropzone take-photo-dropzone_active'
            : 'take-photo-dropzone';
    }

    get resolvedSubtitle() {
        return (
            this.subtitle ||
            'Capture with the camera or upload files. Photos are attached when the order is saved.'
        );
    }

    get isModFormMode() {
        return this.mode === MODE_MOD_FORM;
    }

    get hasPhotos() {
        return (this._photos || []).length > 0;
    }

    get showTitleEdit() {
        return this.enableTitleEdit === true || this.enableTitleEdit === 'true';
    }

    get isParentPersistence() {
        return this.persistenceMode === 'parent';
    }

    get photoRows() {
        return (this._photos || []).map((photo) => {
            const contentDocumentId = photo.contentDocumentId;
            const title = photo.title || photo.name || contentDocumentId;
            const editTitle =
                this._editTitleById[contentDocumentId] != null
                    ? this._editTitleById[contentDocumentId]
                    : title;
            const fileExtension = photo.fileExtension || this.extensionFromName(title) || 'file';
            const thumbnailUrl = photo.thumbnailUrl || photo.imageDownloadUrl || '';
            const showThumbnail =
                Boolean(thumbnailUrl) && !this._thumbnailFailedById[contentDocumentId];
            const isRenaming = this.renamingDocumentIds.has(contentDocumentId);
            const trimmedEdit = String(editTitle || '').trim();
            const isSaveTitleDisabled =
                isRenaming || !trimmedEdit || trimmedEdit === String(title || '').trim();
            return {
                contentDocumentId,
                displayTitle: title,
                editTitle,
                fileExtension,
                thumbnailUrl,
                showThumbnail,
                isRenaming,
                isSaveTitleDisabled,
                titleSaveTitle: isSaveTitleDisabled ? 'No title changes' : 'Save title',
                titleSaveVariant: isSaveTitleDisabled ? 'border-filled' : 'brand',
                titleInputClass: 'slds-m-bottom_none'
            };
        });
    }

    get isStartCameraDisabled() {
        return this.isBusy || this.isCameraStarting || this.isCameraActive || !this.selectedCameraId;
    }

    get isCaptureDisabled() {
        return this.isBusy || !this.isCameraActive || this.isCapturing;
    }

    get isStopCameraDisabled() {
        return !this.isCameraActive && !this.isCameraStarting;
    }

    handleClose() {
        this.handleStopCamera();
        this.dispatchEvent(
            new CustomEvent('close', {
                detail: { contextKey: this.contextKey || '' }
            })
        );
    }

    handleChooseFiles() {
        if (this.isBusy) {
            return;
        }
        const input = this.template.querySelector('[data-id="take-photo-file-input"]');
        if (input) {
            input.click();
        }
    }

    handleDragOver(event) {
        event.preventDefault();
        if (this.isBusy) {
            return;
        }
        this.isDropActive = true;
    }

    handleDragLeave(event) {
        event.preventDefault();
        this.isDropActive = false;
    }

    async handleDrop(event) {
        event.preventDefault();
        this.isDropActive = false;
        if (this.isBusy) {
            return;
        }
        const files = Array.from(event.dataTransfer?.files || []);
        await this.uploadFiles(files);
    }

    async handleFileSelected(event) {
        const files = Array.from(event.target.files || []);
        event.target.value = '';
        await this.uploadFiles(files);
    }

    async uploadFiles(files) {
        if (!files.length || this.isBusy) {
            return;
        }
        this.isBusy = true;
        this.cameraError = undefined;
        try {
            for (const file of files) {
                const base64Data = await this.readFileAsDataUrl(file);
                const photo = await this.stagePhoto(base64Data, file.name);
                this.emitPhotoAdded(photo);
            }
        } catch (error) {
            this.cameraError = this.normalizeError(error);
        } finally {
            this.isBusy = false;
        }
    }

    handleCameraChange(event) {
        this.selectedCameraId = event.detail?.value || '';
    }

    async loadCameras() {
        this.cameraOptions = [];
        this.selectedCameraId = '';
        this.cameraError = undefined;
        try {
            if (!navigator.mediaDevices?.enumerateDevices) {
                this.cameraError = 'Camera is not available in this browser.';
                return;
            }
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
            if (this.cameraOptions.length && !this.selectedCameraId) {
                this.selectedCameraId = this.cameraOptions[0].value;
            }
            if (!this.cameraOptions.length) {
                this.cameraError = 'No cameras were found on this device.';
            }
        } catch (error) {
            this.cameraError = this.normalizeError(
                error,
                'Unable to access cameras. Check browser permissions.'
            );
        }
    }

    bindCameraElements() {
        this.videoEl = this.template.querySelector('video.camera-preview');
        this.canvasEl = this.template.querySelector('canvas');
    }

    async handleStartCamera() {
        this.bindCameraElements();
        if (
            !navigator.mediaDevices ||
            typeof navigator.mediaDevices.getUserMedia !== 'function'
        ) {
            this.cameraError = 'Camera is not available in this browser.';
            return;
        }
        if (!this.selectedCameraId) {
            this.cameraError = 'Select a camera before starting.';
            return;
        }
        this.isCameraStarting = true;
        this.cameraError = undefined;
        try {
            this.handleStopCamera();
            const constraints = {
                video: { deviceId: { exact: this.selectedCameraId } },
                audio: false
            };
            this.mediaStream = await navigator.mediaDevices.getUserMedia(constraints);
            this.bindCameraElements();
            if (this.videoEl) {
                this.videoEl.srcObject = this.mediaStream;
                await this.videoEl.play();
            }
            this.isCameraActive = true;
        } catch (error) {
            this.cameraError = this.normalizeError(error, 'Failed to start the selected camera.');
            this.isCameraActive = false;
        } finally {
            this.isCameraStarting = false;
        }
    }

    handleStopCamera() {
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
        this.isCapturing = true;
        this.cameraError = undefined;
        try {
            this.bindCameraElements();
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
            const fileName = this.isModFormMode
                ? 'Mod Request.jpg'
                : `Capture-${Date.now()}.jpg`;
            const photo = await this.stagePhoto(dataUrl, fileName);
            this.emitPhotoAdded(photo);
        } catch (error) {
            this.cameraError = this.normalizeError(error);
        } finally {
            this.isCapturing = false;
        }
    }

    async stagePhoto(base64Data, fileName) {
        if (this.isModFormMode) {
            if (!this.recordId) {
                throw new Error('Return Order is required to save Mod Form photos.');
            }
            return stageModFormPhoto({
                returnOrderId: this.recordId,
                base64Data,
                fileName
            });
        }
        return stageReceivingPhoto({
            base64Data,
            fileName
        });
    }

    async handleRemovePhoto(event) {
        const contentDocumentId = event.currentTarget.dataset.documentId;
        if (!contentDocumentId || this.isBusy) {
            return;
        }
        this.isBusy = true;
        this.cameraError = undefined;
        try {
            if (!this.isParentPersistence) {
                if (this.isModFormMode) {
                    if (!this.recordId) {
                        throw new Error('Return Order is required to delete Mod Form photos.');
                    }
                    await deleteModFormPhoto({
                        returnOrderId: this.recordId,
                        contentDocumentId
                    });
                } else {
                    await deleteReceivingPhoto({ contentDocumentId });
                }
            }
            this.dispatchEvent(
                new CustomEvent('photoremoved', {
                    detail: {
                        contextKey: this.contextKey || '',
                        contentDocumentId
                    }
                })
            );
        } catch (error) {
            this.cameraError = this.normalizeError(error);
        } finally {
            this.isBusy = false;
        }
    }

    handlePhotoTitleChange(event) {
        const contentDocumentId = event.currentTarget.dataset.docId;
        const value =
            event.detail && event.detail.value != null
                ? event.detail.value
                : event.target.value || '';
        if (!contentDocumentId) {
            return;
        }
        this._editTitleById = {
            ...this._editTitleById,
            [contentDocumentId]: value
        };
    }

    async handleSavePhotoTitle(event) {
        const contentDocumentId = event.currentTarget.dataset.docId;
        if (!contentDocumentId || this.isBusy) {
            return;
        }
        const newTitle = String(this._editTitleById[contentDocumentId] || '').trim();
        if (!newTitle) {
            this.cameraError = 'Photo title is required.';
            return;
        }
        const renaming = new Set(this.renamingDocumentIds);
        renaming.add(contentDocumentId);
        this.renamingDocumentIds = renaming;
        this.cameraError = undefined;
        try {
            if (this.isParentPersistence) {
                this.dispatchEvent(
                    new CustomEvent('phototitlesave', {
                        detail: {
                            contextKey: this.contextKey || '',
                            contentDocumentId,
                            newTitle
                        }
                    })
                );
                return;
            }
            const updated = this.isModFormMode
                ? await renameModFormPhoto({
                      returnOrderId: this.recordId,
                      contentDocumentId,
                      newTitle
                  })
                : await renameReceivingPhoto({ contentDocumentId, newTitle });
            this._editTitleById = {
                ...this._editTitleById,
                [contentDocumentId]: updated.title
            };
            this.dispatchEvent(
                new CustomEvent('photoupdated', {
                    detail: {
                        contextKey: this.contextKey || '',
                        photo: {
                            contentDocumentId: updated.contentDocumentId || contentDocumentId,
                            contentVersionId: updated.contentVersionId,
                            name: updated.title,
                            title: updated.title,
                            editTitle: updated.title,
                            fileExtension: updated.fileExtension,
                            imageDownloadUrl: updated.imageDownloadUrl,
                            thumbnailUrl: updated.thumbnailUrl
                        }
                    }
                })
            );
        } catch (error) {
            this.cameraError = this.normalizeError(error);
        } finally {
            const remaining = new Set(this.renamingDocumentIds);
            remaining.delete(contentDocumentId);
            this.renamingDocumentIds = remaining;
        }
    }

    handleThumbnailError(event) {
        const contentDocumentId = event.target?.dataset?.docId;
        if (!contentDocumentId) {
            return;
        }
        this._thumbnailFailedById = {
            ...this._thumbnailFailedById,
            [contentDocumentId]: true
        };
    }

    emitPhotoAdded(photo) {
        const normalized = {
            contentDocumentId: photo.contentDocumentId,
            contentVersionId: photo.contentVersionId,
            name: photo.title || photo.name,
            title: photo.title || photo.name,
            editTitle: photo.title || photo.name,
            fileExtension: photo.fileExtension,
            imageDownloadUrl: photo.imageDownloadUrl,
            thumbnailUrl: photo.thumbnailUrl
        };
        if (normalized.contentDocumentId) {
            this._editTitleById = {
                ...this._editTitleById,
                [normalized.contentDocumentId]: normalized.title
            };
        }
        this.dispatchEvent(
            new CustomEvent('photoadded', {
                detail: {
                    contextKey: this.contextKey || '',
                    photo: normalized
                }
            })
        );
    }

    extensionFromName(name) {
        const text = String(name || '');
        const index = text.lastIndexOf('.');
        if (index < 0 || index === text.length - 1) {
            return '';
        }
        return text.substring(index + 1).toLowerCase();
    }

    readFileAsDataUrl(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result);
            reader.onerror = () => reject(new Error('Unable to read the selected file.'));
            reader.readAsDataURL(file);
        });
    }

    normalizeError(error, fallback) {
        return (
            error?.body?.message ||
            error?.message ||
            fallback ||
            'Unable to complete the photo action.'
        );
    }

    disconnectedCallback() {
        this.handleStopCamera();
    }
}