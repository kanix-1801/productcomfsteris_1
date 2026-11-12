/**
 * @author Sagar Anand
 * @date 2026-10-16
 * @description GW-359 — woliMicroscopeCaptureMobile. Field Service mobile screen action on Work Order
 * Line Item: live camera capture, Fabric.js markup, and save as a PNG file attached to the WOLI.
 * Works offline.
 *
 * Camera: the camera starts automatically. External cameras (e.g. a microscope) are preferred; a
 * selector is shown only when more than one external camera is connected, and switching restarts
 * the camera. With no external camera the device's rear camera is used.
 *
 * How offline save works (all through LDS, no Apex):
 *   1. createContentDocumentAndVersion stores the PNG as ContentDocument + ContentVersion
 *      drafts on the device and resolves immediately with draft Ids.
 *   2. createRecord creates a ContentDocumentLink draft (draft ContentDocument Id -> WOLI).
 *   When the device is online the Field Service app replays the queue in this order and
 *   swaps draft Ids for real Ids.
 *
 * Annotating an existing file uses Apex and is therefore online only.
 *
 * GW-6340 — Embedding (save-mode="emit"): another component hosts the camera and saves the
 * pictures itself. Capture fires "photocaptured" with a PNG data URL and the camera keeps running
 * for the next photo; nothing is saved here and the file list is not loaded. The host can call
 * openMarkup(dataUrl) to mark up a picture with the same tools; the result comes back in
 * "markupsaved", or "markupcancelled" when the user cancels. "Done" fires "close".
 *
 * GW-6340 — Zoom: pinch the live view with two fingers to zoom (up to MAX_ZOOM) and drag with one
 * finger to move around. Capture saves only the zoomed area. This is digital zoom (a crop of the
 * camera frame), so it works with any camera.
 *
 * Getters are kept to a single return statement so the offline static analyzer
 * (Komaci) can prime the component.
 *
 * Errors are logged with Nebula Logger (c/logger). Offline the log can't be saved to the
 * server, so logging is best-effort and never blocks the technician.
 */
import { LightningElement, api, wire, track } from "lwc";
import { loadScript } from "lightning/platformResourceLoader";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import {
  createContentDocumentAndVersion,
  createRecord
} from "lightning/uiRecordApi";
import { getObjectInfos } from "lightning/uiObjectInfoApi";
import { getLogger } from "c/logger";

import CONTENT_DOCUMENT from "@salesforce/schema/ContentDocument";
import CONTENT_VERSION from "@salesforce/schema/ContentVersion";
import CONTENT_DOCUMENT_LINK from "@salesforce/schema/ContentDocumentLink";
import CDL_CONTENT_DOCUMENT_ID_FIELD from "@salesforce/schema/ContentDocumentLink.ContentDocumentId";
import CDL_LINKED_ENTITY_ID_FIELD from "@salesforce/schema/ContentDocumentLink.LinkedEntityId";
import CDL_SHARE_TYPE_FIELD from "@salesforce/schema/ContentDocumentLink.ShareType";
import CDL_VISIBILITY_FIELD from "@salesforce/schema/ContentDocumentLink.Visibility";

import listAnnotatableImageFiles from "@salesforce/apex/WoliMicroscopeCaptureMobileCtrl.listAnnotatableImageFiles";
import getImageFileForAnnotation from "@salesforce/apex/WoliMicroscopeCaptureMobileCtrl.getImageFileForAnnotation";
import FABRIC_JS from "@salesforce/resourceUrl/FabricJs";

const MAX_PREVIEW_WIDTH = 640;
/** Largest width (px) of a photo handed to the host in emit mode; the host shrinks it further if needed. */
const MAX_EMIT_CAPTURE_WIDTH = 1600;
const SAVE_MODE_EMIT = "emit";
/*
 * Emit mode asks the camera for its best picture, up to this width. Without it many cameras run at
 * a low default (often 640x480). The height is left to the camera so a 4:3 microscope isn't cropped.
 */
const EMIT_MAX_VIDEO_WIDTH = 1920;
const EMIT_IDEAL_VIDEO_HEIGHT = 1440;
/** Largest width (px) a marked-up picture is handed to the host at in emit mode. */
const EMIT_MAX_ANNOTATION_WIDTH = 1600;
const MAX_ZOOM = 4;
/** Zoom below this snaps back to 1x, so a pinch that ends almost closed fully resets. */
const ZOOM_SNAP_TO_ONE = 1.05;
const ZOOM_BUTTON_STEP = 0.5;
/** Width / height of the live view until the camera reports its real size. */
const DEFAULT_VIDEO_ASPECT = 4 / 3;
/** Largest width (px) a marked-up image is saved at. */
const MAX_ANNOTATION_WIDTH = 960;
/** The markup editor may use at most this share of the screen height (matches the CSS max-height). */
const ANNOTATION_MAX_HEIGHT_RATIO = 0.55;
/** Emit mode sits inside the host's modal, which has its own margins, so the editor gets less height. */
const EMIT_ANNOTATION_MAX_HEIGHT_RATIO = 0.4;

/** Files are always stored as PNG (architect decision – no format choice). */
const PNG_MIME_TYPE = "image/png";
const MAX_FILE_BYTES = 10 * 1024 * 1024;
const MAX_PHOTOS_PER_SESSION = 20;
const SHARE_TYPE = "V"; // Viewer
const VISIBILITY = "AllUsers";

/**
 * Labels of cameras built into the phone, tablet or laptop (iOS, Android, Windows, macOS).
 * Any other camera, e.g. a USB microscope, is treated as external.
 */
const BUILT_IN_CAMERA_PATTERN =
  /facetime|built-?in|isight|integrated|front|back|rear|ultra ?wide|telephoto|truedepth|dual|triple/i;
/** Built-in cameras facing away from the user; preferred when no external camera is connected. */
const REAR_CAMERA_PATTERN = /back|rear|environment/i;
/**
 * Software ("virtual") cameras that stream a screen or app instead of a lens, e.g. OBS, Teams,
 * Camo. They are never used.
 */
const VIRTUAL_CAMERA_PATTERN =
  /virtual|obs|screen|snap camera|xsplit|manycam|camo|ndi|droidcam|iriun|epoccam|mmhmm|broadcast|teams|zoom/i;

/** Nebula Logger tags: SObjects touched by this component (singular object labels). */
const LOG_TAG_WOLI = "WorkOrderLineItem";
const LOG_TAG_CONTENT_VERSION = "ContentVersion";
const LOG_TAG_CONTENT_DOCUMENT_LINK = "ContentDocumentLink";

let keySeq = 0;

export default class WoliMicroscopeCaptureMobile extends LightningElement {
  /**
   * WOLI Id from the quick action. In quick actions it can be set after connectedCallback,
   * so the setter starts the (online-only) file list load once the Id is known.
   */
  @api
  get recordId() {
    return this._recordId;
  }
  set recordId(value) {
    this._recordId = value;
    if (this.isComponentConnected) {
      this.requestFileList();
    }
  }
  _recordId = null;

  /**
   * "attach" (default): saves each photo on recordId (the WOLI quick action).
   * "emit": hands each photo to the host component, which saves it.
   */
  @api saveMode = "attach";

  isComponentConnected = false;

  logger = getLogger();

  /** Photos saved during this action session (resets when the action closes). */
  @track items = [];
  savedCount = 0;
  limitReached = false;

  stream;
  /** External cameras only; the selector is shown when there is more than one. */
  cameraOptions = [];
  selectedDeviceId = null;
  isCameraActive = false;
  isInitializing = false;
  /** Set when the camera should start as soon as the <video> element is rendered. */
  cameraStartPending = false;
  isUploading = false;
  lastPreviewDataUrl = null;
  errorMessage = null;
  /** Camera problems only; kept apart so restarting the camera doesn't hide other messages. */
  cameraError = null;

  isAnnotationOpen = false;
  isPendingCaptureAnnotation = false;
  isFabricLoading = false;
  fabricScriptLoaded = false;
  /** True when markup tools could not load for a capture; the photo can still be saved without markup. */
  fabricUnavailable = false;

  /** Existing-file annotation is online only (Apex). */
  isLoadingFileList = false;
  fileListAvailable = false;
  fileListRequested = false;
  /** Shown instead of the file list when it can't load: offline note, or the actual error when online. */
  fileListError = null;
  annotatableFileOptions = [];
  selectedContentDocumentId = null;

  /** Live view size ratio, so the view matches the camera frame and the zoomed area can be cropped exactly. */
  videoAspect = DEFAULT_VIDEO_ASPECT;
  /** Emit mode only: shows the size the camera actually delivers, to check the microscope on site. */
  cameraResolutionLabel = "";
  isZoomed = false;
  zoomLabel = "1x";
  /*
   * Zoom state is kept out of the template so a pinch doesn't re-render on every finger move.
   * _zoomX / _zoomY: top-left of the visible area as a fraction (0..1) of the camera frame.
   */
  _zoom = 1;
  _zoomX = 0;
  _zoomY = 0;
  _gesture = null;

  annotationImageDataUrl;
  annotationSourceLabel = "Capture";
  annotationSourceFileName;
  annotationTool = "pen";
  strokeColor = "#ff0000";
  strokeWidth = "3";

  fabricCanvas = null;
  /** Scales the on-screen (fit-to-screen) canvas back up to the saved image size. */
  annotationExportMultiplier = 1;
  _activeShape;
  _shapeOrigin;

  strokeWidthOptions = [
    { label: "2 px", value: "2" },
    { label: "3 px", value: "3" },
    { label: "5 px", value: "5" },
    { label: "8 px", value: "8" }
  ];

  toolOptions = [
    { label: "Pen", value: "pen" },
    { label: "Select / Move", value: "select" },
    { label: "Circle", value: "circle" },
    { label: "Rectangle", value: "rectangle" },
    { label: "Arrow", value: "arrow" },
    { label: "Text", value: "text" }
  ];

  /*
   * Priming: the offline engine needs metadata for every object written to, otherwise
   * draft creation fails offline. The result also gates the Capture button.
   */
  @wire(getObjectInfos, {
    objectApiNames: [CONTENT_DOCUMENT, CONTENT_VERSION, CONTENT_DOCUMENT_LINK]
  })
  objectInfos;

  connectedCallback() {
    this.isComponentConnected = true;
    // Load Fabric as soon as the action opens, so opening it once online is enough
    // for markup to be available later in the same app session.
    this.preloadFabric();
    this.initializeCameras();
    this.requestFileList();
  }

  renderedCallback() {
    // Auto-start the camera once its <video> element is on screen: it renders after recordId
    // arrives and again whenever the live view returns after a review or annotation.
    if (this.cameraStartPending && this.refs.videoElement) {
      this.cameraStartPending = false;
      this.startCamera();
    }
  }

  disconnectedCallback() {
    this.isComponentConnected = false;
    this.cameraStartPending = false;
    this.stopCamera();
    this.disposeFabricCanvas();
    this.items.forEach(
      (i) => i.thumbnailUrl && URL.revokeObjectURL(i.thumbnailUrl)
    );
  }

  /* ------------------------------ getters ------------------------------ */

  get isEmitMode() {
    return this.saveMode === SAVE_MODE_EMIT;
  }

  get capturePanelClass() {
    return this.isEmitMode
      ? "capture-panel capture-panel_embedded"
      : "capture-panel";
  }

  get panelHeader() {
    return this.isEmitMode
      ? "Microscope Picture"
      : "Microscopic Camera Picture Capture";
  }

  get metadataReady() {
    return !!(this.objectInfos && this.objectInfos.data);
  }

  get metadataError() {
    return !this.isEmitMode && this.objectInfos && this.objectInfos.error
      ? "File metadata is not available on this device yet. Open this action once while online so it can be prepared for offline use."
      : undefined;
  }

  /** In emit mode the host saves the photo, so no record or file metadata is needed here. */
  get hasCaptureContext() {
    return this.isEmitMode || this.hasRecordId;
  }

  get canSaveHere() {
    return this.isEmitMode || (this.hasRecordId && this.metadataReady);
  }

  get showExistingFiles() {
    return this.showLiveCapture && !this.isEmitMode;
  }

  get showDoneAction() {
    return this.isEmitMode && !this.isAnnotationOpen;
  }

  get summaryLabel() {
    return `${this.savedCount} of ${this.items.length} photo(s) saved to this device`;
  }

  get hasItems() {
    return this.items.length > 0;
  }

  get hasRecordId() {
    return !!this.recordId;
  }

  get showCameraSelector() {
    return this.cameraOptions.length > 1;
  }

  get showPreview() {
    return !!this.lastPreviewDataUrl;
  }

  get showLiveCapture() {
    return !this.showPreview;
  }

  get showReviewImage() {
    return !this.isAnnotationOpen;
  }

  get showSaveWithoutMarkup() {
    return this.fabricUnavailable && this.showPreview && !this.isAnnotationOpen;
  }

  /** The panel footer is only shown when it has buttons (markup editor, or save-without-markup). */
  /** In emit mode the markup buttons sit above the canvas, so the footer only holds Done. */
  get showFooterActions() {
    return this.isEmitMode
      ? this.showDoneAction
      : this.isAnnotationOpen || this.showSaveWithoutMarkup;
  }

  get annotationModalTitle() {
    return this.isEmitMode
      ? "Mark up picture"
      : this.isPendingCaptureAnnotation
        ? "Review capture"
        : `Annotate: ${this.annotationSourceLabel}`;
  }

  get annotationModalSubtitle() {
    return this.isEmitMode
      ? "Add markup, then tap Use markup. Cancel keeps the picture as it was."
      : this.isPendingCaptureAnnotation
        ? "Add markup if needed, then save. Cancel returns to the camera without saving."
        : "Markup is saved as a new file; the original file is unchanged.";
  }

  get annotationSaveButtonLabel() {
    return this.isEmitMode
      ? "Use markup"
      : this.isPendingCaptureAnnotation
        ? "Save image"
        : "Save annotated copy";
  }

  get isAnnotationSaveDisabled() {
    return this.isUploading || !this.fabricCanvas;
  }

  get hasAnnotatableFiles() {
    return this.annotatableFileOptions.length > 0;
  }

  get showNoFilesMessage() {
    return !this.hasAnnotatableFiles;
  }

  get isAnnotateFileDisabled() {
    return (
      !this.selectedContentDocumentId ||
      this.isUploading ||
      this.isFabricLoading ||
      this.isLoadingFileList ||
      this.limitReached
    );
  }

  get isCaptureDisabled() {
    return !(
      this.isCameraActive &&
      !this.isUploading &&
      this.canSaveHere &&
      !this.limitReached
    );
  }

  get statusLabel() {
    return this.isUploading
      ? "Saving photo…"
      : this.isFabricLoading
        ? "Opening markup tools…"
        : this.showPreview
          ? "Review the photo, add markup if needed, then save."
          : this.isCameraActive
            ? "Camera ready. Pinch to zoom, then tap Capture."
            : this.isInitializing
              ? "Starting camera…"
              : "Waiting for a camera.";
  }

  get zoomViewportClass() {
    return this.isZoomed ? "zoom-viewport zoom-viewport_zoomed" : "zoom-viewport";
  }

  get showCameraResolution() {
    return this.isEmitMode && this.isCameraActive && !!this.cameraResolutionLabel;
  }

  get isZoomOutDisabled() {
    return !this.isZoomed;
  }

  get isZoomInDisabled() {
    return this.zoomLabel === `${MAX_ZOOM}x`;
  }

  get zoomViewportStyle() {
    return `--video-aspect: ${this.videoAspect}`;
  }

  get numericStrokeWidth() {
    return Number(this.strokeWidth) || 3;
  }

  /* ------------------------------ camera ------------------------------- */

  /** Asks for camera permission (needed for camera labels), picks a camera and starts it. */
  async initializeCameras() {
    this.isInitializing = true;
    this.cameraError = undefined;

    const mediaDevicesExists =
      typeof navigator !== "undefined" &&
      navigator.mediaDevices &&
      typeof navigator.mediaDevices.getUserMedia === "function";

    if (!mediaDevicesExists) {
      this.cameraOptions = [];
      this.selectedDeviceId = undefined;
      this.isInitializing = false;
      return;
    }

    try {
      const permissionStream = await navigator.mediaDevices.getUserMedia({
        video: true,
        audio: false
      });
      permissionStream.getTracks().forEach((mediaTrack) => mediaTrack.stop());
      const devices = await navigator.mediaDevices.enumerateDevices();
      const choice = chooseCamera(
        devices.filter((device) => device.kind === "videoinput")
      );
      this.cameraOptions = choice.externalOptions;
      this.selectedDeviceId = choice.deviceId;
      if (!this.selectedDeviceId) {
        this.cameraError = "No camera was found on this device.";
      }
    } catch (error) {
      this.cameraOptions = [];
      this.selectedDeviceId = undefined;
      this.cameraError = "Camera access was denied or no camera was found.";
      this.log("info", "Camera access denied or no camera found", error, [
        LOG_TAG_WOLI
      ]);
    } finally {
      this.isInitializing = false;
    }

    if (this.selectedDeviceId) {
      await this.startCamera();
    }
  }

  /** Switching between external cameras restarts the preview on the chosen camera. */
  async handleCameraChange(event) {
    this.selectedDeviceId = event.detail.value;
    this.resetZoom();
    await this.startCamera();
  }

  /**
   * Starts (or restarts) the preview on the selected camera. When the <video> element isn't
   * rendered yet, the start is deferred to renderedCallback.
   */
  async startCamera() {
    if (!this.selectedDeviceId || !this.isComponentConnected) {
      return;
    }
    const video = this.refs.videoElement;
    if (!video) {
      this.cameraStartPending = true;
      return;
    }

    this.isInitializing = true;
    this.cameraError = undefined;
    try {
      this.stopCamera();
      this.stream = await this.openVideoStream(this.selectedDeviceId);
      video.srcObject = this.stream;
      await video.play();
      if (this.isEmitMode) {
        await this.raiseVideoResolution();
      }
      this.updateVideoSize();
      // The <video> is re-created after markup or review; keep the zoom the user had
      this.applyZoomTransform();
      this.isCameraActive = true;
    } catch (error) {
      this.cameraError = "The camera could not be started.";
      this.log("warn", "Selected camera could not be started", error, [
        LOG_TAG_WOLI
      ]);
      this.stopCamera();
    } finally {
      this.isInitializing = false;
    }
  }

  async openVideoStream(deviceId) {
    const attempts = [];
    if (this.isEmitMode) {
      attempts.push({
        deviceId: { exact: deviceId },
        width: { ideal: EMIT_MAX_VIDEO_WIDTH },
        height: { ideal: EMIT_IDEAL_VIDEO_HEIGHT }
      });
    }
    attempts.push({ deviceId: { exact: deviceId } });
    // Some devices reject an exact deviceId; fall back to it as a preference
    attempts.push({ deviceId: { ideal: deviceId } });

    let lastError;
    for (const video of attempts) {
      try {
        // eslint-disable-next-line no-await-in-loop
        return await navigator.mediaDevices.getUserMedia({
          video,
          audio: false
        });
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError;
  }

  /**
   * Emit mode: once the camera runs, switches it to the largest size it reports (capped at
   * EMIT_MAX_VIDEO_WIDTH). Cameras that can't report or change their size keep the size they started at.
   */
  async raiseVideoResolution() {
    const track = this.stream && this.stream.getVideoTracks()[0];
    if (
      !track ||
      typeof track.getCapabilities !== "function" ||
      typeof track.applyConstraints !== "function"
    ) {
      return;
    }
    try {
      const capabilities = track.getCapabilities() || {};
      const target = computeTargetResolution(
        capabilities.width && capabilities.width.max,
        capabilities.height && capabilities.height.max,
        EMIT_MAX_VIDEO_WIDTH
      );
      if (target) {
        await track.applyConstraints({
          width: { ideal: target.width },
          height: { ideal: target.height }
        });
      }
    } catch (error) {
      this.log("info", "Camera resolution could not be raised", error, [
        LOG_TAG_WOLI
      ]);
    }
  }

  /** The camera size can change after it starts (raiseVideoResolution), so the live view follows it. */
  handleVideoResize() {
    this.updateVideoSize();
  }

  updateVideoSize() {
    const video = this.refs && this.refs.videoElement;
    if (!video || !video.videoWidth || !video.videoHeight) {
      return;
    }
    this.videoAspect = video.videoWidth / video.videoHeight;
    this.cameraResolutionLabel = `Camera: ${video.videoWidth} × ${video.videoHeight}`;
  }

  stopCamera() {
    if (this.stream) {
      this.stream.getTracks().forEach((mediaTrack) => mediaTrack.stop());
      this.stream = undefined;
    }
    const video = this.refs && this.refs.videoElement;
    if (video) {
      video.srcObject = null;
    }
    this.isCameraActive = false;
  }

  /** Grabs the visible (zoomed) area of the current camera frame as a PNG data URL. */
  grabFrameFromVideo(maxWidth = MAX_PREVIEW_WIDTH) {
    const video = this.refs.videoElement;
    const canvas = this.refs.canvasElement;
    if (!video || !canvas || !video.videoWidth || !video.videoHeight) {
      return null;
    }

    const crop = computeZoomCrop(
      video.videoWidth,
      video.videoHeight,
      this._zoom,
      this._zoomX,
      this._zoomY
    );
    const scale = Math.min(1, maxWidth / crop.width);
    canvas.width = Math.max(1, Math.round(crop.width * scale));
    canvas.height = Math.max(1, Math.round(crop.height * scale));
    const context = canvas.getContext("2d");
    context.drawImage(
      video,
      crop.x,
      crop.y,
      crop.width,
      crop.height,
      0,
      0,
      canvas.width,
      canvas.height
    );
    return canvas.toDataURL(PNG_MIME_TYPE);
  }

  /* -------------------------------- zoom ------------------------------- */

  /**
   * Two fingers start a pinch; one finger starts a drag when zoomed in. Positions are kept as
   * fractions of the live view so they don't depend on the screen size.
   */
  handleZoomTouchStart(event) {
    if (event.touches && event.touches.length >= 2) {
      // Without this iOS can claim the two-finger gesture before touchmove reaches the component
      event.preventDefault();
    }
    this.startZoomGesture(event.touches);
  }

  /** iOS (WebKit) only: stops the app's own pinch handling so the pinch zooms the camera. */
  handleZoomGesture(event) {
    event.preventDefault();
  }

  handleZoomIn() {
    this.zoomAroundCenter(this._zoom + ZOOM_BUTTON_STEP);
  }

  handleZoomOut() {
    this.zoomAroundCenter(this._zoom - ZOOM_BUTTON_STEP);
  }

  /** Zoom buttons keep the middle of the current view in the middle. */
  zoomAroundCenter(targetZoom) {
    const zoom = clampNumber(targetZoom, 1, MAX_ZOOM);
    const centerX = this._zoomX + 0.5 / this._zoom;
    const centerY = this._zoomY + 0.5 / this._zoom;
    this.setZoom(zoom, centerX - 0.5 / zoom, centerY - 0.5 / zoom);
  }

  handleZoomTouchMove(event) {
    const gesture = this._gesture;
    if (!gesture) {
      return;
    }
    // Stop the popup from scrolling or the page from zooming while the camera is pinched or dragged
    event.preventDefault();
    const touches = event.touches;
    if (gesture.type === "pinch" && touches.length >= 2) {
      const distance = touchDistance(touches[0], touches[1]);
      const midpoint = this.toViewportFraction(
        touchMidpoint(touches[0], touches[1]),
        gesture.rect
      );
      const zoom = clampNumber(
        (gesture.startZoom * distance) / gesture.startDistance,
        1,
        MAX_ZOOM
      );
      // Keep the spot under the fingers in place while zooming
      this.setZoom(
        zoom,
        gesture.anchorX - midpoint.x / zoom,
        gesture.anchorY - midpoint.y / zoom
      );
    } else if (gesture.type === "pan" && touches.length === 1) {
      const point = this.toViewportFraction(
        { x: touches[0].clientX, y: touches[0].clientY },
        gesture.rect
      );
      this.setZoom(
        this._zoom,
        gesture.startZoomX - (point.x - gesture.startX) / this._zoom,
        gesture.startZoomY - (point.y - gesture.startY) / this._zoom
      );
    }
  }

  /** Lifting one finger of a pinch carries on as a drag with the other finger. */
  handleZoomTouchEnd(event) {
    if (this._zoom < ZOOM_SNAP_TO_ONE) {
      this.resetZoom();
    }
    this.startZoomGesture(event.touches);
  }

  handleResetZoom() {
    this.resetZoom();
  }

  startZoomGesture(touches) {
    const viewport = this.refs.zoomViewport;
    if (!viewport || !touches || touches.length === 0) {
      this._gesture = null;
      return;
    }
    const rect = viewport.getBoundingClientRect();
    if (!rect.width || !rect.height) {
      this._gesture = null;
      return;
    }
    if (touches.length >= 2) {
      const midpoint = this.toViewportFraction(
        touchMidpoint(touches[0], touches[1]),
        rect
      );
      this._gesture = {
        type: "pinch",
        rect,
        startZoom: this._zoom,
        startDistance: Math.max(1, touchDistance(touches[0], touches[1])),
        anchorX: this._zoomX + midpoint.x / this._zoom,
        anchorY: this._zoomY + midpoint.y / this._zoom
      };
    } else if (this._zoom > 1) {
      const point = this.toViewportFraction(
        { x: touches[0].clientX, y: touches[0].clientY },
        rect
      );
      this._gesture = {
        type: "pan",
        rect,
        startX: point.x,
        startY: point.y,
        startZoomX: this._zoomX,
        startZoomY: this._zoomY
      };
    } else {
      // One finger at 1x is left to the browser, so the popup can still be scrolled
      this._gesture = null;
    }
  }

  toViewportFraction(point, rect) {
    return {
      x: (point.x - rect.left) / rect.width,
      y: (point.y - rect.top) / rect.height
    };
  }

  /** Sets the zoom and the top-left of the visible area, kept inside the camera frame. */
  setZoom(zoom, zoomX, zoomY) {
    const visible = 1 / zoom;
    this._zoom = zoom;
    this._zoomX = clampNumber(zoomX, 0, 1 - visible);
    this._zoomY = clampNumber(zoomY, 0, 1 - visible);
    this.applyZoomTransform();
    const label = `${Math.round(zoom * 10) / 10}x`;
    if (label !== this.zoomLabel) {
      this.zoomLabel = label;
    }
    const zoomed = zoom > 1;
    if (zoomed !== this.isZoomed) {
      this.isZoomed = zoomed;
    }
  }

  resetZoom() {
    this._gesture = null;
    this.setZoom(1, 0, 0);
  }

  /** Moves and scales the <video> directly; the template is not re-rendered on each finger move. */
  applyZoomTransform() {
    const video = this.refs && this.refs.videoElement;
    if (!video) {
      return;
    }
    video.style.transform =
      this._zoom > 1
        ? `scale(${this._zoom}) translate(${-this._zoomX * 100}%, ${-this._zoomY * 100}%)`
        : "";
  }

  /* ------------------------------ capture ------------------------------ */

  async handleCaptureForReview() {
    if (this.isCaptureDisabled) {
      return;
    }
    const dataUrl = this.grabFrameFromVideo(
      this.isEmitMode ? MAX_EMIT_CAPTURE_WIDTH : MAX_PREVIEW_WIDTH
    );
    if (!dataUrl) {
      this.errorMessage = "Could not read an image from the camera preview.";
      return;
    }
    if (this.isEmitMode) {
      this.errorMessage = undefined;
      this.dispatchEvent(
        new CustomEvent("photocaptured", { detail: { dataUrl } })
      );
      return;
    }
    this.lastPreviewDataUrl = dataUrl;
    this.stopCamera();
    await this.openAnnotator(dataUrl, "Review capture", null, true);
  }

  /** Fallback when markup tools could not load: save the raw capture. */
  async handleSaveWithoutMarkup() {
    if (!this.lastPreviewDataUrl || this.isUploading) {
      return;
    }
    const queued = await this.savePhoto(this.lastPreviewDataUrl, false);
    if (queued) {
      this.fabricUnavailable = false;
      this.errorMessage = undefined;
      this.resumeLiveCapture();
    }
  }

  handleDiscardCapture() {
    this.fabricUnavailable = false;
    this.errorMessage = undefined;
    this.resumeLiveCapture();
  }

  /** Returns to the live view; the camera restarts once the <video> element is rendered again. */
  resumeLiveCapture() {
    this.lastPreviewDataUrl = undefined;
    this.isPendingCaptureAnnotation = false;
    this.cameraStartPending = true;
  }

  /* ------------------------------ save flow ---------------------------- */

  /**
   * Adds the photo to the session list and saves it. Returns true once the photo is
   * in the list (saved, or failed with a Retry option), so the caller can move on
   * without the user saving the same image twice.
   */
  async savePhoto(dataUrl, isAnnotated) {
    if (!this.recordId) {
      this.dispatchToast(
        "Save failed",
        "Work Order Line Item Id is missing.",
        "error"
      );
      return false;
    }
    let item;
    try {
      item = this.addItem(dataUrl, isAnnotated);
    } catch (error) {
      this.dispatchToast("Save failed", reduceError(error), "error");
      this.log(
        "error",
        "Captured image could not be prepared for saving",
        error,
        [LOG_TAG_CONTENT_VERSION]
      );
      return false;
    }

    this.isUploading = true;
    try {
      await this.saveItem(item.key);
    } finally {
      this.isUploading = false;
    }
    return true;
  }

  addItem(dataUrl, isAnnotated) {
    const title = isAnnotated
      ? this.buildAnnotatedFileName()
      : this.buildFileName();
    const file = dataUrlToFile(dataUrl, `${title}.png`);

    keySeq += 1;
    const item = {
      key: `p${Date.now()}_${keySeq}`,
      title,
      thumbnailUrl: URL.createObjectURL(file),
      sizeLabel: formatBytes(file.size),
      status: "processing",
      statusLabel: "Preparing…",
      isError: false,
      error: undefined,
      sourceFile: file,
      contentDocumentId: undefined,
      isLinked: false
    };
    this.setItems([item, ...this.items]);
    return item;
  }

  /**
   * Runs the two LDS steps. Each step records its result on the item, so a retry
   * resumes where the last attempt stopped instead of creating a duplicate file.
   */
  async saveItem(key) {
    this.patchItem(key, {
      status: "processing",
      statusLabel: "Preparing…",
      isError: false,
      error: undefined
    });
    try {
      // 1. ContentDocument + ContentVersion (drafts when offline)
      let item = this.getItem(key);
      if (!item.contentDocumentId) {
        if (item.sourceFile.size > MAX_FILE_BYTES) {
          throw new Error(
            `Photo is ${formatBytes(item.sourceFile.size)}; the limit is ${formatBytes(MAX_FILE_BYTES)}.`
          );
        }
        this.patchItem(key, { statusLabel: "Saving photo…" });
        const created = await createContentDocumentAndVersion({
          title: item.title,
          fileData: item.sourceFile
        });
        this.patchItem(key, { contentDocumentId: created.contentDocument.id });
      }

      // 2. Attach to the WOLI (draft references the draft ContentDocument Id offline)
      item = this.getItem(key);
      if (!item.isLinked) {
        this.patchItem(key, { statusLabel: "Attaching to line item…" });
        await createRecord({
          apiName: CONTENT_DOCUMENT_LINK.objectApiName,
          fields: {
            [CDL_CONTENT_DOCUMENT_ID_FIELD.fieldApiName]:
              item.contentDocumentId,
            [CDL_LINKED_ENTITY_ID_FIELD.fieldApiName]: this.recordId,
            [CDL_SHARE_TYPE_FIELD.fieldApiName]: SHARE_TYPE,
            [CDL_VISIBILITY_FIELD.fieldApiName]: VISIBILITY
          }
        });
        this.patchItem(key, { isLinked: true });
      }

      this.patchItem(key, {
        status: "saved",
        statusLabel: "Saved – syncs automatically when online",
        sourceFile: undefined // release the file from memory
      });
      this.dispatchToast(
        "Photo saved",
        "It syncs to the line item automatically when online.",
        "success"
      );
      this.refreshAnnotatableFileList();
    } catch (error) {
      const message = reduceError(error);
      const failedItem = this.getItem(key);
      this.patchItem(key, {
        status: "error",
        statusLabel: "Not saved",
        isError: true,
        error: message
      });
      this.dispatchToast("Photo not saved", message, "error");
      this.log(
        "error",
        `Photo "${failedItem.title}" could not be saved`,
        error,
        [LOG_TAG_CONTENT_VERSION, LOG_TAG_CONTENT_DOCUMENT_LINK]
      );
    }
  }

  async handleRetry(event) {
    const item = this.getItem(event.currentTarget.dataset.key);
    if (!item || !item.sourceFile || this.isUploading) {
      return;
    }
    this.isUploading = true;
    try {
      await this.saveItem(item.key);
    } finally {
      this.isUploading = false;
    }
  }

  buildFileName() {
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
    return `Microscope_mobile_${timestamp}`;
  }

  buildAnnotatedFileName() {
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
    if (this.annotationSourceFileName) {
      const baseName = this.annotationSourceFileName
        .replace(/\.[^.]+$/, "")
        .replace(/[^a-zA-Z0-9._-]/g, "_");
      return `Microscope_mobile_annotated_${baseName}_${timestamp}`;
    }
    return `Microscope_mobile_annotated_${timestamp}`;
  }

  getItem(key) {
    return this.items.find((i) => i.key === key);
  }

  patchItem(key, patch) {
    this.setItems(
      this.items.map((i) => (i.key === key ? { ...i, ...patch } : i))
    );
  }

  setItems(items) {
    this.items = items;
    this.savedCount = items.filter((i) => i.status === "saved").length;
    this.limitReached = items.length >= MAX_PHOTOS_PER_SESSION;
  }

  /* -------------------- existing files (online only) ------------------- */

  /** Loads the file list once, as soon as the component is connected and recordId is known. */
  requestFileList() {
    if (this.recordId && !this.fileListRequested && !this.isEmitMode) {
      this.fileListRequested = true;
      this.refreshAnnotatableFileList();
    }
  }

  async handleRefreshFileList() {
    await this.refreshAnnotatableFileList();
  }

  handleExistingFileChange(event) {
    this.selectedContentDocumentId = event.detail.value;
  }

  async refreshAnnotatableFileList() {
    if (!this.recordId) {
      this.annotatableFileOptions = [];
      this.selectedContentDocumentId = undefined;
      return;
    }
    this.isLoadingFileList = true;
    this.fileListError = undefined;
    try {
      const files =
        (await listAnnotatableImageFiles({
          workOrderLineItemId: this.recordId
        })) || [];
      this.annotatableFileOptions = files.map((file) => ({
        label: file.title,
        value: file.contentDocumentId
      }));
      const selectionStillValid = this.annotatableFileOptions.some(
        (option) => option.value === this.selectedContentDocumentId
      );
      if (!selectionStillValid) {
        this.selectedContentDocumentId = this.hasAnnotatableFiles
          ? this.annotatableFileOptions[0].value
          : undefined;
      }
      this.fileListAvailable = true;
    } catch (error) {
      this.fileListAvailable = false;
      const isOffline =
        typeof navigator !== "undefined" && navigator.onLine === false;
      this.fileListError = isOffline
        ? "Annotating existing files is available when you are online."
        : `Could not load files on this line item: ${reduceError(error)}`;
      // Expected while offline (INFO); a failure while online is a system error
      this.log(
        isOffline ? "info" : "error",
        "Image file list could not be loaded",
        error,
        [LOG_TAG_CONTENT_DOCUMENT_LINK]
      );
    } finally {
      this.isLoadingFileList = false;
    }
  }

  async handleAnnotateSelectedFile() {
    if (!this.recordId || !this.selectedContentDocumentId) {
      return;
    }
    // The annotator replaces the live-capture view in the panel, so release the camera
    this.stopCamera();
    this.isFabricLoading = true;
    this.errorMessage = undefined;
    try {
      const payload = await getImageFileForAnnotation({
        workOrderLineItemId: this.recordId,
        contentDocumentId: this.selectedContentDocumentId
      });
      const label = (payload && payload.fileName) || "Selected file";
      await this.openAnnotator(payload.base64DataUrl, label, payload.fileName);
    } catch (error) {
      this.errorMessage =
        "Could not load the selected file. Annotating existing files needs a connection.";
      this.dispatchToast("Annotate failed", this.errorMessage, "error");
      this.log(
        "error",
        `Image file ${this.selectedContentDocumentId} could not be loaded for annotation`,
        error,
        [LOG_TAG_CONTENT_VERSION]
      );
      this.cameraStartPending = true;
    } finally {
      this.isFabricLoading = false;
    }
  }

  /* ------------------------------ annotator ---------------------------- */

  async preloadFabric() {
    try {
      await this.ensureFabricLoaded();
    } catch (error) {
      // Retried when the annotator opens; capture falls back to saving without markup
      this.log(
        "warn",
        "Fabric.js markup library could not be preloaded",
        error,
        [LOG_TAG_WOLI]
      );
    }
  }

  async ensureFabricLoaded() {
    if (this.fabricScriptLoaded && window.fabric) {
      return;
    }
    await loadScript(this, FABRIC_JS);
    if (!window.fabric) {
      throw new Error("Fabric.js did not load.");
    }
    this.fabricScriptLoaded = true;
  }

  async openAnnotator(
    imageDataUrl,
    sourceLabel,
    sourceFileName,
    isPendingCapture = false
  ) {
    if (!imageDataUrl) {
      return;
    }
    this.isPendingCaptureAnnotation = isPendingCapture;
    this.annotationImageDataUrl = imageDataUrl;
    this.annotationSourceLabel = sourceLabel || "Image";
    this.annotationSourceFileName = sourceFileName;
    this.fabricUnavailable = false;
    this.isFabricLoading = true;
    this.errorMessage = undefined;
    try {
      await this.ensureFabricLoaded();
      this.isAnnotationOpen = true;
      // Wait for the annotation host to render before Fabric attaches to it
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      await new Promise((resolve) => requestAnimationFrame(resolve));
      await this.initFabricCanvas();
    } catch (error) {
      this.disposeFabricCanvas();
      this.isAnnotationOpen = false;
      if (isPendingCapture) {
        // Never lose a capture because markup tools are unavailable (e.g. offline after app restart)
        this.fabricUnavailable = true;
        this.errorMessage =
          "Markup tools are not available right now. You can still save the photo without markup.";
        this.log(
          "warn",
          "Annotation editor unavailable; offering save without markup",
          error,
          [LOG_TAG_WOLI]
        );
      } else {
        this.errorMessage = "Could not open the annotation editor.";
        this.log("error", "Annotation editor could not be opened", error, [
          LOG_TAG_CONTENT_VERSION
        ]);
        this.cameraStartPending = true;
      }
    } finally {
      this.isFabricLoading = false;
    }
  }

  /** Closes the annotator and returns to the live camera. */
  handleCloseAnnotator() {
    this.disposeFabricCanvas();
    this.isAnnotationOpen = false;
    this.resumeLiveCapture();
  }

  /** Cancel is disabled while saving; the guard also covers a tap that lands before it re-renders. */
  handleCancelAnnotation() {
    if (this.isUploading) {
      return;
    }
    this.handleCloseAnnotator();
    if (this.isEmitMode) {
      this.dispatchEvent(new CustomEvent("markupcancelled"));
    }
  }

  /**
   * Emit mode: opens the markup editor on a picture the host already holds. The camera pauses
   * while the editor is open and restarts when it closes.
   * @param {string} dataUrl Picture to mark up
   * @returns {Promise<boolean>} False when the markup tools could not open
   */
  @api
  async openMarkup(dataUrl) {
    if (!dataUrl || this.isAnnotationOpen) {
      return false;
    }
    this.stopCamera();
    await this.openAnnotator(dataUrl, "Picture", null);
    return this.isAnnotationOpen;
  }

  /** Emit mode: the host closes the camera. */
  handleDone() {
    this.dispatchEvent(new CustomEvent("close"));
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
    // Markup is flattened into the PNG, so annotations are stored on the picture itself.
    // The editor is shrunk to fit the screen; the multiplier saves it back at full size.
    const dataUrl = this.fabricCanvas.toDataURL({
      format: "png",
      multiplier: this.annotationExportMultiplier
    });
    if (this.isEmitMode) {
      this.handleCloseAnnotator();
      this.dispatchEvent(
        new CustomEvent("markupsaved", { detail: { dataUrl } })
      );
      return;
    }
    const isExistingFileAnnotation = !!this.annotationSourceFileName;
    const queued = await this.savePhoto(dataUrl, isExistingFileAnnotation);
    if (queued) {
      this.handleCloseAnnotator();
    }
  }

  async initFabricCanvas() {
    this.disposeFabricCanvas();
    const host = this.template.querySelector('[data-id="annotationHost"]');
    if (!host) {
      throw new Error("Annotation surface is not available.");
    }

    // Fabric.js needs a raw <canvas>; it lives in an lwc:dom="manual" container
    host.replaceChildren();
    const canvasElement = document.createElement("canvas");
    canvasElement.setAttribute("aria-label", "Annotation canvas");
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
            reject(new Error("Could not load the image for annotation."));
            return;
          }
          // Fit the whole image on screen (phones are ~360-430px wide); save at full size
          const layout = computeAnnotationLayout(
            image.width,
            image.height,
            this.getAnnotationAreaWidth(),
            Math.round(
              window.innerHeight *
                (this.isEmitMode
                  ? EMIT_ANNOTATION_MAX_HEIGHT_RATIO
                  : ANNOTATION_MAX_HEIGHT_RATIO)
            ),
            this.isEmitMode ? EMIT_MAX_ANNOTATION_WIDTH : MAX_ANNOTATION_WIDTH
          );
          this.annotationExportMultiplier = layout.exportMultiplier;
          this.fabricCanvas.setWidth(layout.displayWidth);
          this.fabricCanvas.setHeight(layout.displayHeight);
          image.set({
            scaleX: layout.displayScale,
            scaleY: layout.displayScale,
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
        { crossOrigin: "anonymous" }
      );
    });
  }

  /** Inner width (px) of the box the markup canvas sits in; 0 when it isn't laid out yet. */
  getAnnotationAreaWidth() {
    const wrapper = this.template.querySelector(".annotation-canvas-wrapper");
    return wrapper ? wrapper.clientWidth : 0;
  }

  applyAnnotationTool() {
    if (!this.fabricCanvas || !window.fabric) {
      return;
    }
    const fabric = window.fabric;
    const isPen = this.annotationTool === "pen";
    this.fabricCanvas.isDrawingMode = isPen;
    if (isPen) {
      this.fabricCanvas.freeDrawingBrush = new fabric.PencilBrush(
        this.fabricCanvas
      );
      this.fabricCanvas.freeDrawingBrush.color = this.strokeColor;
      this.fabricCanvas.freeDrawingBrush.width = this.numericStrokeWidth;
    }
  }

  bindShapeDrawingHandlers() {
    if (!this.fabricCanvas) {
      return;
    }
    this.fabricCanvas.off("mouse:down");
    this.fabricCanvas.off("mouse:move");
    this.fabricCanvas.off("mouse:up");
    this.fabricCanvas.on("mouse:down", (event) =>
      this.onFabricMouseDown(event)
    );
    this.fabricCanvas.on("mouse:move", (event) =>
      this.onFabricMouseMove(event)
    );
    this.fabricCanvas.on("mouse:up", () => this.onFabricMouseUp());
  }

  onFabricMouseDown(event) {
    if (!this.fabricCanvas || !window.fabric) {
      return;
    }
    if (
      this.annotationTool === "pen" ||
      this.annotationTool === "select" ||
      event.target
    ) {
      return;
    }

    const pointer = this.fabricCanvas.getPointer(event.e);
    const fabric = window.fabric;

    if (this.annotationTool === "text") {
      const label = new fabric.IText("", {
        left: pointer.x,
        top: pointer.y,
        fill: this.strokeColor,
        fontSize: 18,
        fontFamily: "Arial",
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

    if (this.annotationTool === "circle") {
      this._activeShape = new fabric.Circle({
        left: pointer.x,
        top: pointer.y,
        radius: 1,
        fill: "transparent",
        stroke,
        strokeWidth,
        originX: "center",
        originY: "center"
      });
    } else if (this.annotationTool === "rectangle") {
      this._activeShape = new fabric.Rect({
        left: pointer.x,
        top: pointer.y,
        width: 1,
        height: 1,
        fill: "transparent",
        stroke,
        strokeWidth
      });
    } else if (this.annotationTool === "arrow") {
      this._activeShape = new fabric.Line(
        [pointer.x, pointer.y, pointer.x, pointer.y],
        { stroke, strokeWidth }
      );
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

    if (this.annotationTool === "circle") {
      const radius = Math.sqrt(
        Math.pow(pointer.x - origin.x, 2) + Math.pow(pointer.y - origin.y, 2)
      );
      this._activeShape.set({ radius: Math.max(radius, 1) });
    } else if (this.annotationTool === "rectangle") {
      const left = Math.min(origin.x, pointer.x);
      const top = Math.min(origin.y, pointer.y);
      this._activeShape.set({
        left,
        top,
        width: Math.max(Math.abs(pointer.x - origin.x), 1),
        height: Math.max(Math.abs(pointer.y - origin.y), 1)
      });
    } else if (this.annotationTool === "arrow") {
      this._activeShape.set({ x2: pointer.x, y2: pointer.y });
    }
    this.fabricCanvas.requestRenderAll();
  }

  onFabricMouseUp() {
    if (
      this.annotationTool === "arrow" &&
      this._activeShape &&
      this._shapeOrigin &&
      window.fabric
    ) {
      const line = this._activeShape;
      const angle =
        (Math.atan2(line.y2 - line.y1, line.x2 - line.x1) * 180) / Math.PI;
      const head = new window.fabric.Triangle({
        left: line.x2,
        top: line.y2,
        originX: "center",
        originY: "center",
        width: 14,
        height: 18,
        fill: this.strokeColor,
        angle: angle + 90,
        selectable: false,
        evented: false
      });
      const group = new window.fabric.Group([line, head], { selectable: true });
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
      this.fabricCanvas.off("mouse:down");
      this.fabricCanvas.off("mouse:move");
      this.fabricCanvas.off("mouse:up");
      this.fabricCanvas.dispose();
      this.fabricCanvas = null;
    }
    const host = this.template.querySelector('[data-id="annotationHost"]');
    if (host) {
      host.replaceChildren();
    }
    this._activeShape = null;
    this._shapeOrigin = null;
  }

  dispatchToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  /**
   * Writes a Nebula Logger entry linked to the WOLI and saves it.
   * @param {string} level Nebula level: 'error' | 'warn' | 'info'
   * @param {string} message What happened, in plain words
   * @param {*} error Original error; its message is appended
   * @param {string[]} tags SObjects involved (singular object labels)
   */
  log(level, message, error, tags = []) {
    const entry = this.logger[level](
      error ? `${message}: ${reduceError(error)}` : message
    );
    if (this.recordId) {
      entry.setRecordId(this.recordId);
    }
    tags.forEach((tag) => entry.addTag(tag));
    this.logger.saveLog();
  }
}

/* ------------------------------ module helpers ------------------------------ */

/**
 * Picks the camera to start. Virtual (screen-streaming) cameras are never used. External cameras
 * (e.g. a USB microscope) are preferred: the first one is used, and every external camera becomes a
 * selector option. With no external camera the rear built-in camera is used (else the first
 * built-in camera) and no selector is shown.
 * @param {MediaDeviceInfo[]} videoInputs Video input devices from enumerateDevices()
 * @returns {{externalOptions: {label: string, value: string}[], deviceId: (string|undefined)}}
 */
export function chooseCamera(videoInputs) {
  const cameras = (videoInputs || []).filter(
    (camera) => !camera.label || !VIRTUAL_CAMERA_PATTERN.test(camera.label)
  );
  const externalCameras = cameras.filter(
    (camera) => camera.label && !BUILT_IN_CAMERA_PATTERN.test(camera.label)
  );
  const externalOptions = externalCameras.map((camera, index) => ({
    label: camera.label || `Camera ${index + 1}`,
    value: camera.deviceId
  }));
  if (externalCameras.length > 0) {
    return { externalOptions, deviceId: externalCameras[0].deviceId };
  }
  const rearCamera = cameras.find(
    (camera) => camera.label && REAR_CAMERA_PATTERN.test(camera.label)
  );
  const fallbackCamera = rearCamera || cameras[0];
  return {
    externalOptions,
    deviceId: fallbackCamera ? fallbackCamera.deviceId : undefined
  };
}

/**
 * Sizes the markup canvas so the whole image fits on screen, and works out the export multiplier
 * that saves it back at full resolution (capped at maxWidth).
 * @param {number} imageWidth Natural image width (px)
 * @param {number} imageHeight Natural image height (px)
 * @param {number} areaWidth Available width on screen (px); 0 or less means unknown
 * @param {number} areaHeight Available height on screen (px); 0 or less means unknown
 * @param {number} maxWidth Largest saved width (px); defaults to MAX_ANNOTATION_WIDTH
 * @returns {{displayScale: number, displayWidth: number, displayHeight: number, exportMultiplier: number}}
 */
export function computeAnnotationLayout(
  imageWidth,
  imageHeight,
  areaWidth,
  areaHeight,
  maxWidth = MAX_ANNOTATION_WIDTH
) {
  const naturalWidth = imageWidth || maxWidth;
  const naturalHeight = imageHeight || maxWidth;
  // Never save larger than the original, nor wider than maxWidth
  const exportScale = Math.min(1, maxWidth / naturalWidth);
  const widthFit = areaWidth > 0 ? areaWidth / naturalWidth : exportScale;
  const heightFit = areaHeight > 0 ? areaHeight / naturalHeight : exportScale;
  const displayScale = Math.min(exportScale, widthFit, heightFit);
  return {
    displayScale,
    displayWidth: Math.max(1, Math.round(naturalWidth * displayScale)),
    displayHeight: Math.max(1, Math.round(naturalHeight * displayScale)),
    exportMultiplier: exportScale / displayScale
  };
}

/**
 * Area of the camera frame shown when zoomed in.
 * @param {number} frameWidth Camera frame width (px)
 * @param {number} frameHeight Camera frame height (px)
 * @param {number} zoom 1 shows the whole frame
 * @param {number} zoomX Left edge of the visible area as a fraction of the frame width
 * @param {number} zoomY Top edge of the visible area as a fraction of the frame height
 * @returns {{x: number, y: number, width: number, height: number}} Source rectangle in frame pixels
 */
export function computeZoomCrop(frameWidth, frameHeight, zoom, zoomX, zoomY) {
  const safeZoom = Math.max(1, zoom || 1);
  const width = frameWidth / safeZoom;
  const height = frameHeight / safeZoom;
  return {
    x: clampNumber((zoomX || 0) * frameWidth, 0, frameWidth - width),
    y: clampNumber((zoomY || 0) * frameHeight, 0, frameHeight - height),
    width,
    height
  };
}

/**
 * Largest camera size to ask for, keeping the camera's own shape.
 * @param {number} maxWidth Largest width the camera reports (px)
 * @param {number} maxHeight Largest height the camera reports (px)
 * @param {number} widthCap Never ask for more than this width (px)
 * @returns {{width: number, height: number}|null} Null when the camera doesn't report its size
 */
export function computeTargetResolution(maxWidth, maxHeight, widthCap) {
  if (!(maxWidth > 0) || !(maxHeight > 0)) {
    return null;
  }
  const scale = Math.min(1, widthCap / maxWidth);
  return {
    width: Math.round(maxWidth * scale),
    height: Math.round(maxHeight * scale)
  };
}

export function clampNumber(value, min, max) {
  return Math.min(Math.max(value, min), Math.max(min, max));
}

function touchDistance(first, second) {
  return Math.hypot(
    second.clientX - first.clientX,
    second.clientY - first.clientY
  );
}

function touchMidpoint(first, second) {
  return {
    x: (first.clientX + second.clientX) / 2,
    y: (first.clientY + second.clientY) / 2
  };
}

/** Returns the base64 body of a data URL ("data:image/png;base64,<body>"), or the input if it has no prefix. */
export function stripDataUrlPrefix(dataUrl) {
  if (!dataUrl) {
    return "";
  }
  const trimmed = dataUrl.trim();
  const commaIndex = trimmed.indexOf(",");
  return commaIndex > -1 ? trimmed.substring(commaIndex + 1) : trimmed;
}

/** Human-readable byte size, e.g. 1.4 MB */
export function formatBytes(bytes) {
  if (!Number.isFinite(bytes) || bytes < 0) {
    return "";
  }
  if (bytes < 1024) {
    return `${bytes} B`;
  }
  const units = ["KB", "MB", "GB"];
  let value = bytes / 1024;
  let i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return `${value.toFixed(1)} ${units[i]}`;
}

/** Converts a PNG data URL (canvas / Fabric output) to a File for createContentDocumentAndVersion. */
export function dataUrlToFile(dataUrl, fileName) {
  const binary = atob(stripDataUrlPrefix(dataUrl));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return new File([bytes], fileName, {
    type: PNG_MIME_TYPE,
    lastModified: Date.now()
  });
}

/** Normalise LDS / Apex / JS errors to a readable string */
export function reduceError(error) {
  if (!error) {
    return "Unknown error";
  }
  if (typeof error === "string") {
    return error;
  }
  if (error.body) {
    if (Array.isArray(error.body)) {
      return error.body.map((b) => b.message).join(", ");
    }
    if (error.body.message) {
      return error.body.message;
    }
    const out = error.body.output;
    if (out && out.errors && out.errors.length) {
      return out.errors.map((x) => x.message).join(", ");
    }
  }
  return error.message || JSON.stringify(error);
}