import { LightningElement, api } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import listAnnotatableImageFiles from '@salesforce/apex/WorkOrderLineItemCaptureService.listAnnotatableImageFiles';
import getImageFileForAnnotation from '@salesforce/apex/WorkOrderLineItemCaptureService.getImageFileForAnnotation';
import {
    BEYOND_REPAIR_CATEGORY,
    BEYOND_REPAIR_REASON_OPTIONS,
    buildCaptureFileName,
    canvasToCaptureDataUrl,
    IMAGE_CAPTURE_FORMAT_OPTIONS,
    IMAGE_CATEGORY_OPTIONS,
    JPEG_CAPTURE_QUALITY,
    uploadBase64ImageToWorkOrderLineItem
} from 'c/woliCaptureUpload';
import FABRIC_JS from '@salesforce/resourceUrl/FabricJs';

const DEFAULT_DEVICE_STORAGE_KEY = 'steris.woliMicroscope.defaultDeviceId';
const MAX_PREVIEW_WIDTH = 640;
const MAX_ANNOTATION_WIDTH = 960;

/**
 * GW-1505 — USB microscope capture and Fabric.js annotation on Work Order Line Item record pages (desktop).
 */
export default class WoliMicroscopeCapture extends LightningElement {
    @api recordId;

    stream;
    cameraOptions = [];
    selectedDeviceId;
    isCameraActive = false;
    isInitializing = false;
    isUploading = false;
    lastPreviewDataUrl;
    sessionCaptureCount = 0;
    errorMessage;
    browserSupported = true;

    isAnnotationOpen = false;
    isPendingCaptureAnnotation = false;
    isFabricLoading = false;
    isLoadingFileList = false;
    fabricScriptLoaded = false;
    annotatableFileOptions = [];
    annotatableFiles = [];
    pendingCaptureCategory = '';
    pendingCaptureBeyondRepairReason = '';
    pendingCaptureFormat = 'png';
    selectedContentDocumentId;
    annotationImageDataUrl;
    annotationSourceLabel = 'Last capture';
    annotationSourceFileName;
    annotationSourceCategory = '';
    annotationSourceBeyondRepairReason = '';
    lastCaptureCategory = '';
    lastCaptureBeyondRepairReason = '';
    lastCaptureContentDocumentId;
    annotationTool = 'pen';
    strokeColor = '#ff0000';
    strokeWidth = '3';

    fabricCanvas;
    _activeShape;
    _shapeOrigin;

    strokeWidthOptions = [
        { label: '2 px', value: '2' },
        { label: '3 px', value: '3' },
        { label: '5 px', value: '5' },
        { label: '8 px', value: '8' }
    ];

    toolOptions = [
        { label: 'Pen', value: 'pen' },
        { label: 'Select / Move', value: 'select' },
        { label: 'Circle', value: 'circle' },
        { label: 'Rectangle', value: 'rectangle' },
        { label: 'Arrow', value: 'arrow' },
        { label: 'Text', value: 'text' }
    ];

    connectedCallback() {
        this.browserSupported =
            typeof navigator !== 'undefined' &&
            navigator.mediaDevices &&
            typeof navigator.mediaDevices.getUserMedia === 'function';
        if (!this.browserSupported) {
            this.errorMessage =
                'This browser does not support camera capture. Use Chrome, Edge, Firefox, or Safari.';
            return;
        }
        this.initializeCameras();
        if (this.recordId) {
            this.refreshAnnotatableFileList();
        }
    }

    disconnectedCallback() {
        this.stopCamera();
        this.disposeFabricCanvas();
    }

    get hasRecordId() {
        return !!this.recordId;
    }

    get hasCameras() {
        return this.cameraOptions.length > 0;
    }

    get isStartCameraDisabled() {
        return !(this.hasCameras && this.selectedDeviceId && !this.isCameraActive && !this.isInitializing);
    }

    get isCaptureDisabled() {
        return !(this.isCameraActive && !this.isUploading && this.hasRecordId);
    }

    get isStopCameraDisabled() {
        return !this.isCameraActive;
    }

    get showPreview() {
        return !!this.lastPreviewDataUrl;
    }

    get showLiveCapture() {
        return !this.showPreview;
    }

    get showBeyondRepairReason() {
        return this.pendingCaptureCategory === BEYOND_REPAIR_CATEGORY;
    }

    get beyondRepairReasonOptions() {
        return BEYOND_REPAIR_REASON_OPTIONS;
    }

    get isAnnotateFileDisabled() {
        return (
            !this.selectedContentDocumentId ||
            this.isUploading ||
            this.isFabricLoading ||
            this.isLoadingFileList
        );
    }

    get hasAnnotatableFiles() {
        return this.annotatableFileOptions.length > 0;
    }

    get imageCategoryOptions() {
        return IMAGE_CATEGORY_OPTIONS;
    }

    get imageFormatOptions() {
        return IMAGE_CAPTURE_FORMAT_OPTIONS;
    }

    get annotationModalTitle() {
        if (this.isPendingCaptureAnnotation) {
            return 'Review capture';
        }
        return `Annotate: ${this.annotationSourceLabel}`;
    }

    get annotationModalSubtitle() {
        if (this.isPendingCaptureAnnotation) {
            return 'Add markup if needed, then save. Cancel returns to the camera without saving.';
        }
        return 'Markup is saved as a new file; the original file is unchanged.';
    }

    get annotationSaveButtonLabel() {
        return this.isPendingCaptureAnnotation ? 'Save image' : 'Save annotated copy';
    }

    get isAnnotationSaveDisabled() {
        return this.isUploading || !this.fabricCanvas;
    }

    get statusLabel() {
        if (this.isUploading) {
            return 'Attaching image…';
        }
        if (this.showPreview) {
            if (this.isFabricLoading) {
                return 'Opening annotation editor…';
            }
            if (this.isAnnotationOpen) {
                return 'Review capture — annotate if needed, then save.';
            }
            return 'Review capture';
        }
        if (this.isCameraActive) {
            return 'Camera active — capture multiple images without restarting.';
        }
        if (this.isInitializing) {
            return 'Loading cameras…';
        }
        return 'Select a camera and start a capture session.';
    }

    async initializeCameras() {
        this.isInitializing = true;
        this.errorMessage = undefined;
        try {
            await this.loadCameraDevices();
        } catch (error) {
            this.errorMessage = this.resolveErrorMessage(error, 'Unable to access cameras.');
        } finally {
            this.isInitializing = false;
        }
    }

    async loadCameraDevices() {
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

        const savedDeviceId = window.localStorage.getItem(DEFAULT_DEVICE_STORAGE_KEY);
        const savedStillPresent = videoInputs.some((device) => device.deviceId === savedDeviceId);
        if (savedStillPresent) {
            this.selectedDeviceId = savedDeviceId;
        } else if (videoInputs.length > 0) {
            const externalDevice =
                videoInputs.find((device) => device.label && !/facetime|built-?in|isight/i.test(device.label)) ||
                videoInputs[videoInputs.length - 1];
            this.selectedDeviceId = externalDevice.deviceId;
        }
    }

    handleCameraChange(event) {
        this.selectedDeviceId = event.detail.value;
        window.localStorage.setItem(DEFAULT_DEVICE_STORAGE_KEY, this.selectedDeviceId);
        if (this.isCameraActive) {
            this.stopCamera();
            this.startCamera();
        }
    }

    handleSetDefaultCamera() {
        if (this.selectedDeviceId) {
            window.localStorage.setItem(DEFAULT_DEVICE_STORAGE_KEY, this.selectedDeviceId);
            this.dispatchToast('Default camera saved', 'This device will be selected next time.', 'success');
        }
    }

    async handleStartCamera() {
        await this.startCamera();
    }

    handleStopCamera() {
        this.stopCamera();
    }

    async handleCaptureForReview() {
        if (this.isCaptureDisabled) {
            return;
        }
        if (this.showBeyondRepairReason && !this.pendingCaptureBeyondRepairReason) {
            this.dispatchToast(
                'Validation',
                'Beyond Repair Reason is required when Category is Beyond Repair.',
                'error'
            );
            return;
        }
        const dataUrl = this.grabFrameFromVideo();
        if (!dataUrl) {
            this.errorMessage = 'Could not read an image from the camera preview.';
            return;
        }
        this.lastPreviewDataUrl = dataUrl;
        this.stopCamera();
        await this.openAnnotator(
            dataUrl,
            'Review capture',
            null,
            this.pendingCaptureCategory || '',
            this.pendingCaptureBeyondRepairReason || '',
            true
        );
    }

    async handleAnnotateSelectedFile() {
        if (!this.recordId || !this.selectedContentDocumentId) {
            return;
        }
        this.isFabricLoading = true;
        this.errorMessage = undefined;
        try {
            const payload = await getImageFileForAnnotation({
                workOrderLineItemId: this.recordId,
                contentDocumentId: this.selectedContentDocumentId
            });
            const label = payload?.fileName || 'Selected file';
            await this.openAnnotator(
                payload.base64DataUrl,
                label,
                payload.fileName,
                payload.category || '',
                payload.beyondRepairReason || ''
            );
        } catch (error) {
            this.errorMessage = this.resolveErrorMessage(error, 'Could not load the selected file.');
            this.dispatchToast('Annotate failed', this.errorMessage, 'error');
        } finally {
            this.isFabricLoading = false;
        }
    }

    handleExistingFileChange(event) {
        this.selectedContentDocumentId = event.detail.value;
    }

    async refreshAnnotatableFileList() {
        if (!this.recordId) {
            this.annotatableFileOptions = [];
            this.annotatableFiles = [];
            this.selectedContentDocumentId = undefined;
            return;
        }
        this.isLoadingFileList = true;
        try {
            const files = await listAnnotatableImageFiles({
                workOrderLineItemId: this.recordId
            });
            this.annotatableFiles = files || [];
            this.annotatableFileOptions = this.annotatableFiles.map((file) => ({
                label: file.title,
                value: file.contentDocumentId
            }));
            const selectionStillValid = this.annotatableFileOptions.some(
                (option) => option.value === this.selectedContentDocumentId
            );
            if (!selectionStillValid) {
                this.selectedContentDocumentId =
                    this.annotatableFileOptions.length > 0
                        ? this.annotatableFileOptions[0].value
                        : undefined;
            }
        } catch (error) {
            this.errorMessage = this.resolveErrorMessage(error, 'Could not load image files on this line item.');
        } finally {
            this.isLoadingFileList = false;
        }
    }

    handlePendingCaptureCategoryChange(event) {
        this.pendingCaptureCategory = event.detail.value || '';
        if (this.pendingCaptureCategory !== BEYOND_REPAIR_CATEGORY) {
            this.pendingCaptureBeyondRepairReason = '';
        }
    }

    handlePendingCaptureBeyondRepairReasonChange(event) {
        this.pendingCaptureBeyondRepairReason = event.detail.value || '';
    }

    handlePendingCaptureFormatChange(event) {
        this.pendingCaptureFormat = event.detail.value === 'jpeg' ? 'jpeg' : 'png';
    }

    resolveUploadCategory(isAnnotated) {
        if (isAnnotated) {
            return this.annotationSourceCategory || undefined;
        }
        return this.pendingCaptureCategory || undefined;
    }

    resolveUploadBeyondRepairReason(isAnnotated) {
        if (isAnnotated) {
            return this.annotationSourceBeyondRepairReason || undefined;
        }
        return this.pendingCaptureBeyondRepairReason || undefined;
    }

    clearReviewCapture() {
        this.lastPreviewDataUrl = undefined;
        this.isPendingCaptureAnnotation = false;
    }

    async resumeLiveCaptureAfterReview() {
        this.clearReviewCapture();
        if (!this.selectedDeviceId) {
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        await new Promise((resolve) => requestAnimationFrame(resolve));
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        await new Promise((resolve) => requestAnimationFrame(resolve));
        await this.startCamera();
    }

    async openAnnotator(
        imageDataUrl,
        sourceLabel,
        sourceFileName,
        sourceCategory = '',
        sourceBeyondRepairReason = '',
        isPendingCapture = false
    ) {
        if (!imageDataUrl) {
            return;
        }
        this.isPendingCaptureAnnotation = isPendingCapture;
        this.annotationImageDataUrl = imageDataUrl;
        this.annotationSourceLabel = sourceLabel || 'Image';
        this.annotationSourceFileName = sourceFileName;
        this.annotationSourceCategory = sourceCategory || '';
        this.annotationSourceBeyondRepairReason = sourceBeyondRepairReason || '';
        this.isFabricLoading = true;
        this.errorMessage = undefined;
        try {
            await this.ensureFabricLoaded();
            this.isAnnotationOpen = true;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            await new Promise((resolve) => requestAnimationFrame(resolve));
            await this.initFabricCanvas();
        } catch (error) {
            this.errorMessage = this.resolveErrorMessage(error, 'Could not open the annotation editor.');
            this.isAnnotationOpen = false;
            if (isPendingCapture) {
                await this.resumeLiveCaptureAfterReview();
            }
        } finally {
            this.isFabricLoading = false;
        }
    }

    async handleCloseAnnotator() {
        const wasPendingCapture = this.isPendingCaptureAnnotation;
        this.disposeFabricCanvas();
        this.isAnnotationOpen = false;
        this.isPendingCaptureAnnotation = false;
        this.annotationSourceCategory = '';
        this.annotationSourceBeyondRepairReason = '';
        if (wasPendingCapture) {
            await this.resumeLiveCaptureAfterReview();
        }
    }

    handleToolChange(event) {
        this.annotationTool = event.detail.value;
        this.applyAnnotationTool();
    }

    handleColorChange(event) {
        this.strokeColor = event.detail.value;
        this.applyAnnotationTool();
    }

    handleWidthChange(event) {
        this.strokeWidth = event.detail.value;
        this.applyAnnotationTool();
    }

    get numericStrokeWidth() {
        return Number(this.strokeWidth) || 3;
    }

    handleUndoAnnotation() {
        if (!this.fabricCanvas) {
            return;
        }
        const objects = this.fabricCanvas.getObjects();
        if (objects.length > 0) {
            this.fabricCanvas.remove(objects[objects.length - 1]);
            this.fabricCanvas.requestRenderAll();
        }
    }

    handleClearAnnotations() {
        if (!this.fabricCanvas) {
            return;
        }
        const objects = this.fabricCanvas.getObjects();
        objects.forEach((object) => this.fabricCanvas.remove(object));
        this.fabricCanvas.requestRenderAll();
    }

    async handleSaveAnnotated() {
        if (!this.fabricCanvas || this.isUploading) {
            return;
        }
        const dataUrl = this.fabricCanvas.toDataURL({
            format: this.pendingCaptureFormat === 'jpeg' ? 'jpeg' : 'png',
            quality: this.pendingCaptureFormat === 'jpeg' ? JPEG_CAPTURE_QUALITY : 1,
            multiplier: 1
        });
        const isExistingFileAnnotation = !!this.annotationSourceFileName;
        const uploaded = await this.uploadCapture(dataUrl, isExistingFileAnnotation);
        if (uploaded) {
            await this.handleCloseAnnotator();
        }
    }

    async ensureFabricLoaded() {
        if (this.fabricScriptLoaded && window.fabric) {
            return;
        }
        await loadScript(this, FABRIC_JS);
        if (!window.fabric) {
            throw new Error('Fabric.js did not load.');
        }
        this.fabricScriptLoaded = true;
    }

    async initFabricCanvas() {
        this.disposeFabricCanvas();
        const host = this.template.querySelector('[data-id="annotationHost"]');
        if (!host) {
            throw new Error('Annotation surface is not available.');
        }

        host.innerHTML = '';
        const canvasElement = document.createElement('canvas');
        canvasElement.setAttribute('aria-label', 'Annotation canvas');
        host.appendChild(canvasElement);

        const fabric = window.fabric;
        this.fabricCanvas = new fabric.Canvas(canvasElement, {
            selection: true,
            preserveObjectStacking: true
        });

        await new Promise((resolve, reject) => {
            fabric.Image.fromURL(
                this.annotationImageDataUrl,
                (image) => {
                    if (!this.fabricCanvas || !image) {
                        reject(new Error('Could not load the capture for annotation.'));
                        return;
                    }
                    const scale = Math.min(1, MAX_ANNOTATION_WIDTH / (image.width || MAX_ANNOTATION_WIDTH));
                    const width = Math.max(1, Math.round((image.width || MAX_ANNOTATION_WIDTH) * scale));
                    const height = Math.max(1, Math.round((image.height || MAX_ANNOTATION_WIDTH) * scale));
                    this.fabricCanvas.setWidth(width);
                    this.fabricCanvas.setHeight(height);
                    image.set({
                        scaleX: scale,
                        scaleY: scale,
                        selectable: false,
                        evented: false
                    });
                    this.fabricCanvas.setBackgroundImage(
                        image,
                        this.fabricCanvas.requestRenderAll.bind(this.fabricCanvas)
                    );
                    this.bindShapeDrawingHandlers();
                    this.applyAnnotationTool();
                    resolve();
                },
                { crossOrigin: 'anonymous' }
            );
        });
    }

    applyAnnotationTool() {
        if (!this.fabricCanvas || !window.fabric) {
            return;
        }
        const fabric = window.fabric;
        const isPen = this.annotationTool === 'pen';
        this.fabricCanvas.isDrawingMode = isPen;
        if (isPen) {
            this.fabricCanvas.freeDrawingBrush = new fabric.PencilBrush(this.fabricCanvas);
            this.fabricCanvas.freeDrawingBrush.color = this.strokeColor;
            this.fabricCanvas.freeDrawingBrush.width = this.numericStrokeWidth;
        }
    }

    bindShapeDrawingHandlers() {
        if (!this.fabricCanvas) {
            return;
        }
        this.fabricCanvas.off('mouse:down');
        this.fabricCanvas.off('mouse:move');
        this.fabricCanvas.off('mouse:up');

        this.fabricCanvas.on('mouse:down', (event) => this.onFabricMouseDown(event));
        this.fabricCanvas.on('mouse:move', (event) => this.onFabricMouseMove(event));
        this.fabricCanvas.on('mouse:up', () => this.onFabricMouseUp());
    }

    onFabricMouseDown(event) {
        if (!this.fabricCanvas || !window.fabric) {
            return;
        }
        if (this.annotationTool === 'pen' || this.annotationTool === 'select') {
            return;
        }

        if (event.target) {
            return;
        }

        const pointer = this.fabricCanvas.getPointer(event.e);
        const fabric = window.fabric;

        if (this.annotationTool === 'text') {
            const label = new fabric.IText('', {
                left: pointer.x,
                top: pointer.y,
                fill: this.strokeColor,
                fontSize: 18,
                fontFamily: 'Arial',
                editable: true
            });
            this.fabricCanvas.add(label);
            this.fabricCanvas.setActiveObject(label);
            label.enterEditing();
            this.fabricCanvas.requestRenderAll();
            return;
        }

        this._shapeOrigin = { x: pointer.x, y: pointer.y };
        const stroke = this.strokeColor;
        const strokeWidth = this.numericStrokeWidth;

        if (this.annotationTool === 'circle') {
            this._activeShape = new fabric.Circle({
                left: pointer.x,
                top: pointer.y,
                radius: 1,
                fill: 'transparent',
                stroke,
                strokeWidth,
                originX: 'center',
                originY: 'center'
            });
        } else if (this.annotationTool === 'rectangle') {
            this._activeShape = new fabric.Rect({
                left: pointer.x,
                top: pointer.y,
                width: 1,
                height: 1,
                fill: 'transparent',
                stroke,
                strokeWidth
            });
        } else if (this.annotationTool === 'arrow') {
            this._activeShape = new fabric.Line([pointer.x, pointer.y, pointer.x, pointer.y], {
                stroke,
                strokeWidth
            });
        }

        if (this._activeShape) {
            this.fabricCanvas.add(this._activeShape);
        }
    }

    onFabricMouseMove(event) {
        if (!this._activeShape || !this._shapeOrigin || !this.fabricCanvas) {
            return;
        }
        const pointer = this.fabricCanvas.getPointer(event.e);
        const origin = this._shapeOrigin;

        if (this.annotationTool === 'circle') {
            const radius = Math.sqrt(
                Math.pow(pointer.x - origin.x, 2) + Math.pow(pointer.y - origin.y, 2)
            );
            this._activeShape.set({ radius: Math.max(radius, 1) });
        } else if (this.annotationTool === 'rectangle') {
            const left = Math.min(origin.x, pointer.x);
            const top = Math.min(origin.y, pointer.y);
            this._activeShape.set({
                left,
                top,
                width: Math.max(Math.abs(pointer.x - origin.x), 1),
                height: Math.max(Math.abs(pointer.y - origin.y), 1)
            });
        } else if (this.annotationTool === 'arrow') {
            this._activeShape.set({ x2: pointer.x, y2: pointer.y });
        }
        this.fabricCanvas.requestRenderAll();
    }

    onFabricMouseUp() {
        if (this.annotationTool === 'arrow' && this._activeShape && this._shapeOrigin && window.fabric) {
            const line = this._activeShape;
            const x1 = line.x1;
            const y1 = line.y1;
            const x2 = line.x2;
            const y2 = line.y2;
            const angle = (Math.atan2(y2 - y1, x2 - x1) * 180) / Math.PI;
            const head = new window.fabric.Triangle({
                left: x2,
                top: y2,
                originX: 'center',
                originY: 'center',
                width: 14,
                height: 18,
                fill: this.strokeColor,
                angle: angle + 90,
                selectable: false,
                evented: false
            });
            const group = new window.fabric.Group([line, head], {
                selectable: true
            });
            this.fabricCanvas.remove(line);
            this.fabricCanvas.add(group);
            this.fabricCanvas.setActiveObject(group);
            this.fabricCanvas.requestRenderAll();
        }
        this._activeShape = null;
        this._shapeOrigin = null;
    }

    disposeFabricCanvas() {
        if (this.fabricCanvas) {
            this.fabricCanvas.off('mouse:down');
            this.fabricCanvas.off('mouse:move');
            this.fabricCanvas.off('mouse:up');
            this.fabricCanvas.dispose();
            this.fabricCanvas = null;
        }
        const host = this.template.querySelector('[data-id="annotationHost"]');
        if (host) {
            host.innerHTML = '';
        }
        this._activeShape = null;
        this._shapeOrigin = null;
    }

    async startCamera() {
        if (!this.selectedDeviceId) {
            this.errorMessage = 'Select a camera before starting.';
            return;
        }
        const video = this.refs.videoElement;
        if (!video) {
            return;
        }
        this.errorMessage = undefined;
        try {
            this.stopCamera();
            this.stream = await this.openVideoStream(this.selectedDeviceId);
            video.srcObject = this.stream;
            await video.play();
            this.isCameraActive = true;
        } catch (error) {
            this.errorMessage = this.resolveErrorMessage(error, 'Failed to start the selected camera.');
            this.stopCamera();
        }
    }

    async openVideoStream(deviceId) {
        const exactConstraints = {
            video: { deviceId: { exact: deviceId } },
            audio: false
        };
        try {
            return await navigator.mediaDevices.getUserMedia(exactConstraints);
        } catch (exactError) {
            return navigator.mediaDevices.getUserMedia({
                video: { deviceId: { ideal: deviceId } },
                audio: false
            });
        }
    }

    stopCamera() {
        if (this.stream) {
            this.stream.getTracks().forEach((track) => track.stop());
            this.stream = undefined;
        }
        const video = this.refs.videoElement;
        if (video) {
            video.srcObject = null;
        }
        this.isCameraActive = false;
    }

    grabFrameFromVideo() {
        const video = this.refs.videoElement;
        const canvas = this.refs.canvasElement;
        if (!video || !canvas || !video.videoWidth || !video.videoHeight) {
            return null;
        }

        const scale = Math.min(1, MAX_PREVIEW_WIDTH / video.videoWidth);
        canvas.width = Math.round(video.videoWidth * scale);
        canvas.height = Math.round(video.videoHeight * scale);
        const context = canvas.getContext('2d');
        context.drawImage(video, 0, 0, canvas.width, canvas.height);
        return canvasToCaptureDataUrl(canvas, this.pendingCaptureFormat, JPEG_CAPTURE_QUALITY);
    }

    async uploadCapture(dataUrl, isAnnotated) {
        this.isUploading = true;
        this.errorMessage = undefined;
        const baseName = isAnnotated ? this.buildAnnotatedFileName() : this.buildFileName();
        const uploadFileName = buildCaptureFileName(baseName, this.pendingCaptureFormat);
        try {
            const result = await uploadBase64ImageToWorkOrderLineItem({
                workOrderLineItemId: this.recordId,
                base64Payload: dataUrl,
                fileName: uploadFileName,
                category: this.resolveUploadCategory(isAnnotated),
                beyondRepairReason: this.resolveUploadBeyondRepairReason(isAnnotated)
            });
            if (!result || result.success !== true) {
                const failureMessage = result?.message || 'Could not attach image to this line item.';
                this.errorMessage = failureMessage;
                this.dispatchToast('Attach failed', failureMessage, 'error');
                return false;
            }
            this.sessionCaptureCount += 1;
            if (!isAnnotated) {
                this.lastCaptureContentDocumentId = result.contentDocumentId;
                this.lastCaptureCategory = this.pendingCaptureCategory || '';
                this.lastCaptureBeyondRepairReason = this.pendingCaptureBeyondRepairReason || '';
            }
            this.dispatchToast(
                isAnnotated ? 'Annotated image attached' : 'Image attached',
                result.fileName || uploadFileName,
                'success'
            );
            await this.refreshAnnotatableFileList();
            return true;
        } catch (error) {
            this.errorMessage = this.resolveErrorMessage(error, 'Failed to attach image to this line item.');
            this.dispatchToast('Attach failed', this.errorMessage, 'error');
            return false;
        } finally {
            this.isUploading = false;
        }
    }

    buildFileName() {
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        return `Microscope_${timestamp}`;
    }

    buildAnnotatedFileName() {
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        if (this.annotationSourceFileName) {
            const baseName = this.annotationSourceFileName
                .replace(/\.[^.]+$/, '')
                .replace(/[^a-zA-Z0-9._-]/g, '_');
            return `Microscope_annotated_${baseName}_${timestamp}`;
        }
        return `Microscope_annotated_${timestamp}`;
    }

    resolveErrorMessage(error, fallback) {
        if (!error) {
            return fallback;
        }
        if (typeof error.body === 'string' && error.body) {
            return error.body;
        }
        if (error.body) {
            if (Array.isArray(error.body) && error.body[0]?.message) {
                return error.body[0].message;
            }
            if (error.body.message) {
                return error.body.message;
            }
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