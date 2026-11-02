import saveMicroscopeImage from '@salesforce/apex/WorkOrderLineItemCaptureService.saveMicroscopeImage';

/**
 * GW-1505 / GW-1506 — Shared WOLI image upload (single Apex saveMicroscopeImage request).
 */

/** @type {Array<{label: string, value: string}>} */
export const IMAGE_CAPTURE_FORMAT_OPTIONS = [
    { label: 'PNG (lossless)', value: 'png' },
    { label: 'JPEG (smaller file)', value: 'jpeg' }
];

export const BEYOND_REPAIR_CATEGORY = 'Beyond Repair';

/** @type {Array<{label: string, value: string}>} */
export const IMAGE_CATEGORY_OPTIONS = [
    { label: '— None —', value: '' },
    { label: 'Beyond Repair', value: BEYOND_REPAIR_CATEGORY },
    { label: 'Fixable', value: 'Fixable' }
];

/** @type {Array<{label: string, value: string}>} */
export const BEYOND_REPAIR_REASON_OPTIONS = [
    { label: '— Select reason —', value: '' },
    { label: 'Pitting', value: 'Pitting' },
    { label: 'Shortening', value: 'Shortening' },
    { label: 'Unsafe for Continued Use', value: 'Unsafe for Continued Use' },
    { label: 'Cracked in a Critical Area', value: 'Cracked in a Critical Area' },
    { label: 'Cracked Box Lock', value: 'Cracked Box Lock' },
    { label: 'Exceeded Useful Life', value: 'Exceeded Useful Life' }
];

export const JPEG_CAPTURE_QUALITY = 0.85;

/** Max longest edge when re-encoding JPEG on mobile before upload. */
export const MOBILE_JPEG_MAX_DIMENSION = 1280;

/**
 * @description File extension including dot for a capture format choice.
 * @param {string} format `png` or `jpeg`.
 * @return {string} `.png` or `.jpg`.
 */
export function resolveCaptureFileExtension(format) {
    return format === 'jpeg' ? '.jpg' : '.png';
}

/**
 * @description Encodes a canvas as PNG or JPEG.
 * @param {HTMLCanvasElement} canvas Source canvas.
 * @param {string} format `png` or `jpeg`.
 * @param {number} [quality] JPEG quality when format is jpeg.
 * @return {string} Data URL.
 */
export function canvasToCaptureDataUrl(canvas, format, quality = JPEG_CAPTURE_QUALITY) {
    if (format === 'jpeg') {
        return canvas.toDataURL('image/jpeg', quality);
    }
    return canvas.toDataURL('image/png');
}

/**
 * @description Builds an upload file name with the correct extension.
 * @param {string} baseName Name without extension.
 * @param {string} format `png` or `jpeg`.
 * @return {string} File name with extension.
 */
export function buildCaptureFileName(baseName, format) {
    return `${baseName}${resolveCaptureFileExtension(format)}`;
}

/**
 * @description Re-encodes a data URL to the chosen format (optional resize for mobile JPEG).
 * @param {string} dataUrl Source image data URL.
 * @param {string} format `png` or `jpeg`.
 * @param {object} [options] Encoding options.
 * @param {number} [options.maxDimension] Longest edge cap when set.
 * @param {number} [options.quality] JPEG quality.
 * @return {Promise<string>} Encoded data URL.
 */
export function reencodeCaptureDataUrl(dataUrl, format, options = {}) {
    const { maxDimension, quality = JPEG_CAPTURE_QUALITY } = options;

    if (format === 'png' && !maxDimension) {
        return Promise.resolve(dataUrl);
    }

    return new Promise((resolve, reject) => {
        const image = new Image();
        image.onload = () => {
            let scale = 1;
            if (maxDimension) {
                scale = Math.min(
                    1,
                    maxDimension / (image.width || maxDimension),
                    maxDimension / (image.height || maxDimension)
                );
            }
            const width = Math.max(1, Math.round((image.width || maxDimension) * scale));
            const height = Math.max(1, Math.round((image.height || maxDimension) * scale));
            const canvas = document.createElement('canvas');
            canvas.width = width;
            canvas.height = height;
            const context = canvas.getContext('2d');
            context.drawImage(image, 0, 0, width, height);
            resolve(canvasToCaptureDataUrl(canvas, format, quality));
        };
        image.onerror = () => reject(new Error('Could not decode the image.'));
        image.src = dataUrl;
    });
}

/**
 * @description Strips a data-URL prefix when present.
 * @param {string} dataUrl Raw or data-URL payload.
 * @return {string} Base64 body only.
 */
export function stripDataUrlPrefix(dataUrl) {
    if (!dataUrl) {
        return '';
    }
    const trimmed = dataUrl.trim();
    const commaIndex = trimmed.indexOf(',');
    return commaIndex > -1 ? trimmed.substring(commaIndex + 1) : trimmed;
}

/**
 * @description Human-readable size summary for attach error messages.
 * @param {string} base64Payload Base64 or data-URL image body.
 * @return {string} Size description for UI.
 */
export function describeImagePayloadSize(base64Payload) {
    const rawBase64 = stripDataUrlPrefix(base64Payload);
    if (!rawBase64) {
        return 'Image size: unknown (no data).';
    }
    const base64Chars = rawBase64.length;
    const approxBytes = Math.max(1, Math.round((base64Chars * 3) / 4));
    const kilobytes = (approxBytes / 1024).toFixed(1);
    return (
        `Image size: ~${kilobytes} KB (${approxBytes.toLocaleString()} bytes, ` +
        `${base64Chars.toLocaleString()} base64 characters).`
    );
}

/**
 * @description Appends image size details to an error message.
 * @param {string} message Primary error text.
 * @param {string} base64Payload Base64 or data-URL image body.
 * @return {string} Combined message.
 */
export function appendImageSizeToMessage(message, base64Payload) {
    const sizeDescription = describeImagePayloadSize(base64Payload);
    if (!message) {
        return sizeDescription;
    }
    return `${message} ${sizeDescription}`;
}

/**
 * @description Extracts a user-facing message from an LWC Apex wire/imperative error.
 * @param {object} error Error from Apex call.
 * @return {string} Message text.
 */
export function extractApexErrorMessage(error) {
    if (!error) {
        return '';
    }

    const parts = [];
    const body = error.body;

    if (typeof body === 'string' && body) {
        parts.push(body);
    } else if (body && typeof body === 'object') {
        if (body.exceptionMessage) {
            parts.push(body.exceptionMessage);
        }
        if (body.pageErrors?.length) {
            body.pageErrors.forEach((pageError) => {
                if (pageError?.message) {
                    parts.push(pageError.message);
                }
            });
        }
        if (body.fieldErrors) {
            Object.keys(body.fieldErrors).forEach((fieldName) => {
                const fieldMessages = body.fieldErrors[fieldName];
                if (Array.isArray(fieldMessages)) {
                    fieldMessages.forEach((fieldError) => {
                        if (fieldError?.message) {
                            parts.push(`${fieldName}: ${fieldError.message}`);
                        }
                    });
                }
            });
        }
        if (body.output?.errors?.length) {
            body.output.errors.forEach((outputError) => {
                if (outputError?.message) {
                    parts.push(outputError.message);
                }
            });
        }
        if (Array.isArray(body) && body[0]?.message) {
            parts.push(body[0].message);
        }
        if (typeof body.message === 'string' && body.message) {
            const isGenericHandlerMessage =
                body.message === 'An error occurred while executing an Apex handler script.' ||
                body.message.includes('executing an Apex handler');
            if (!isGenericHandlerMessage) {
                parts.push(body.message);
            }
        }
    }

    if (error.statusText) {
        parts.push(error.statusText);
    }
    if (error.message && !isGenericScriptThrownMessage(error.message)) {
        parts.push(error.message);
    }

    const uniqueParts = [...new Set(parts.map((part) => part.trim()).filter(Boolean))];
    if (uniqueParts.length > 0) {
        return uniqueParts.join(' ');
    }

    if (error.message) {
        return error.message;
    }
    return 'Unknown Apex error';
}

/**
 * @description Full Apex error payload for debug screens (type, stack, JSON body).
 * @param {object} error Error from Apex call.
 * @return {string} Multi-line detail text.
 */
export function formatApexErrorDetail(error) {
    if (!error) {
        return '';
    }

    const lines = [];
    const body = error.body;

    if (error.status) {
        lines.push(`httpStatus=${error.status}`);
    }
    if (error.statusText) {
        lines.push(`statusText=${error.statusText}`);
    }
    if (typeof body === 'string') {
        lines.push(body);
    } else if (body && typeof body === 'object') {
        if (body.exceptionType) {
            lines.push(`exceptionType=${body.exceptionType}`);
        }
        if (body.exceptionMessage) {
            lines.push(`exceptionMessage=${body.exceptionMessage}`);
        }
        if (body.stackTrace) {
            lines.push('stackTrace:');
            lines.push(body.stackTrace);
        }
        if (body.pageErrors?.length) {
            body.pageErrors.forEach((pageError, index) => {
                lines.push(
                    `pageError[${index}]=${pageError?.statusCode || ''} ${pageError?.message || ''}`.trim()
                );
            });
        }
        try {
            const serializedBody = JSON.stringify(body, null, 2);
            if (serializedBody && serializedBody !== '{}') {
                lines.push('body:');
                lines.push(
                    serializedBody.length > 3500
                        ? `${serializedBody.substring(0, 3500)}…`
                        : serializedBody
                );
            }
        } catch (stringifyError) {
            lines.push('body=[unserializable]');
        }
    }

    if (lines.length === 0 && error.message) {
        lines.push(error.message);
    }

    return lines.join('\n').substring(0, 4000);
}

/**
 * @param {string} message Error message from the platform.
 * @return {boolean} True when the LWC only exposes a generic script failure label.
 */
function isGenericScriptThrownMessage(message) {
    return message === 'script-thrown exception' || message === 'Script-thrown exception';
}

/**
 * @description Uploads image bytes to a WOLI in one Apex call (saveMicroscopeImage).
 * @param {object} options Upload options.
 * @param {string} options.workOrderLineItemId Parent WOLI Id.
 * @param {string} options.base64Payload Base64 or data-URL image body.
 * @param {string} options.fileName Target file name.
 * @param {string} [options.category] Optional ContentVersion.Category__c value.
 * @param {string} [options.beyondRepairReason] Optional ContentVersion.BeyondRepairReason__c value.
 * @return {Promise<object>} MicroscopeCaptureResult from Apex.
 */
export async function uploadBase64ImageToWorkOrderLineItem({
    workOrderLineItemId,
    base64Payload,
    fileName,
    category,
    beyondRepairReason
}) {
    const rawBase64 = stripDataUrlPrefix(base64Payload);
    if (!rawBase64) {
        throw new Error(appendImageSizeToMessage('No image data to upload.', base64Payload));
    }

    const apexParams = {
        workOrderLineItemId,
        base64Image: rawBase64,
        fileName
    };
    if (category) {
        apexParams.category = category;
    }
    if (beyondRepairReason) {
        apexParams.beyondRepairReason = beyondRepairReason;
    }

    const result = await saveMicroscopeImage(apexParams);

    if (result?.success === true) {
        return result;
    }

    throw new Error(
        appendImageSizeToMessage(
            result?.message || 'Could not attach image to this Work Order Line Item.',
            base64Payload
        )
    );
}