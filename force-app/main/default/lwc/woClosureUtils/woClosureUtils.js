/**
 * @description GW-6407: Helpers shared by the Work Order closure (woClosureES) tab components:
 *              formatting, dates, Salesforce Ids, error messages, record pickers and toasts.
 * @author Sagar Anand
 */
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export const RESOURCE_PICKER_FILTER = { criteria: [{ fieldPath: 'IsActive', operator: 'eq', value: true }] };
export const RESOURCE_PICKER_DISPLAY_INFO = { primaryField: 'Name' };
export const RESOURCE_PICKER_MATCHING_INFO = { primaryField: { fieldPath: 'Name' } };

/**
 * @description True when two Salesforce Ids refer to the same record (15- or 18-char).
 * @param {string|null} left First Id
 * @param {string|null} right Second Id
 * @return {Boolean}
 */
export function isSameSalesforceId(left, right) {
    if (!left || !right) return false;
    const a = String(left);
    const b = String(right);
    return a === b || a.substring(0, 15) === b.substring(0, 15);
}

/**
 * @description True for boolean true or the string "true".
 * @param {*} value Value to test
 * @return {Boolean}
 */
export function isTruthyFlag(value) {
    return value === true || value === 'true';
}

/**
 * @description Local calendar date (YYYY-MM-DD).
 * @return {string}
 */
export function todayDateString() {
    const now = new Date();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    return `${now.getFullYear()}-${month}-${day}`;
}

/**
 * @description Hours between two ISO datetimes, or null when either is missing or the end is not after the start.
 * @param {string} startDate ISO datetime
 * @param {string} endDate ISO datetime
 * @return {number|null}
 */
export function computeDurationHours(startDate, endDate) {
    if (!startDate || !endDate) return null;
    const start = new Date(startDate).getTime();
    const end = new Date(endDate).getTime();
    if (Number.isNaN(start) || Number.isNaN(end) || end <= start) return null;
    return (end - start) / (1000 * 60 * 60);
}

/**
 * @description Adds hours to an ISO datetime string.
 * @param {string} startDate ISO datetime
 * @param {number} hours Duration hours
 * @return {string}
 */
export function addHoursToDatetime(startDate, hours) {
    const startMs = new Date(startDate).getTime();
    if (Number.isNaN(startMs)) {
        return startDate;
    }
    return new Date(startMs + (hours * 60 * 60 * 1000)).toISOString();
}

/**
 * @description Milliseconds of an ISO datetime, or null.
 * @param {string} iso ISO datetime
 * @return {number|null}
 */
export function toMs(iso) {
    if (!iso) return null;
    const t = new Date(iso).getTime();
    return Number.isNaN(t) ? null : t;
}

/**
 * @description Formats a number with two decimals ("0.00" when not a number).
 * @param {*} n Amount
 * @return {string}
 */
export function fmtMoney(n) {
    const num = Number(n);
    if (!Number.isFinite(num)) return '0.00';
    return num.toFixed(2);
}

/**
 * @description Formats money only when populated.
 * @param {*} n Amount
 * @return {string}
 */
export function fmtOptionalMoney(n) {
    return n === null || n === undefined || n === '' ? '' : fmtMoney(n);
}

/**
 * @description Formats hours as "1.50 hrs".
 * @param {*} hours Duration hours
 * @return {string}
 */
export function fmtDurationLabel(hours) {
    if (hours == null || hours === '') return '';
    const n = Number(hours);
    if (Number.isNaN(n)) return '';
    return `${n.toFixed(2)} hrs`;
}

/**
 * @description Short local date and time of an ISO datetime.
 * @param {string} iso ISO datetime
 * @return {string}
 */
export function fmtDateTime(iso) {
    if (!iso) return '';
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return '';
    return d.toLocaleString(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
}

/**
 * @description "start → end" date range label.
 * @param {string} startDate ISO datetime
 * @param {string} endDate ISO datetime
 * @return {string}
 */
export function fmtDateRange(startDate, endDate) {
    const s = fmtDateTime(startDate);
    const e = fmtDateTime(endDate);
    if (s && e) return `${s} → ${e}`;
    if (s) return s;
    if (e) return `→ ${e}`;
    return '';
}

/**
 * @description Reads a record Id from a lookup / record-picker event (desktop and mobile).
 * @param {Event} event Change event
 * @return {string|null}
 */
export function lookupRecordId(event) {
    return event?.detail?.recordId
        ?? event?.detail?.value
        ?? event?.currentTarget?.value
        ?? event?.target?.value
        ?? null;
}

/**
 * @description Sorts line models by start date, then line number.
 * @param {Array<Object>} lines Line models
 * @return {Array<Object>}
 */
export function sortByStartDate(lines) {
    return lines.sort((a, b) => {
        const aMs = a.startDateMs ?? Number.POSITIVE_INFINITY;
        const bMs = b.startDateMs ?? Number.POSITIVE_INFINITY;
        if (aMs !== bMs) return aMs - bMs;
        return (a.lineNumber || '').localeCompare(b.lineNumber || '');
    });
}

/**
 * @description Keeps the line models whose visible text contains the search term.
 * @param {Array<Object>} lines Line models
 * @param {string} searchTerm Search text
 * @return {Array<Object>}
 */
export function filterLinesBySearch(lines, searchTerm) {
    const term = (searchTerm ?? '').trim().toLowerCase();
    if (!term) return lines;
    return lines.filter(line => [
        line.title, line.metaLine, line.lineNumber, line.description,
        line.expenseType, line.partsSource, line.returnable, line.usagesException,
        line.assignedResourceName, line.productName, line.repairCodeProductCode,
        line.returnableLabel, line.editReturnableLabel,
        line.assetSerialNumber, line.startDate, line.endDate, line.totalPrice,
        line.lineType, line.rate, line.travelType
    ].filter(v => v != null && v !== '').join(' ').toLowerCase().includes(term));
}

/**
 * @description Message of an Apex error, or null.
 * @param {Object} error Apex error
 * @return {string|null}
 */
export function apexErrorMessage(error) {
    if (!error) return null;
    if (typeof error.body?.message === 'string' && error.body.message) return error.body.message;
    if (Array.isArray(error.body) && error.body[0]?.message) return error.body[0].message;
    if (typeof error.message === 'string' && error.message) return error.message;
    return null;
}

/**
 * @description Message of a Lightning Data Service error, or null.
 * @param {Object} err LDS error
 * @return {string|null}
 */
function ldsErrorMessage(err) {
    if (!err) return null;
    let body = err.body;
    if (typeof body === 'string') {
        try { body = JSON.parse(body); } catch (e) { return body; }
    }
    if (body?.message) return body.message;
    const pageErrors = body?.pageErrors;
    if (Array.isArray(pageErrors) && pageErrors.length) {
        return pageErrors.map(e => e.message).filter(Boolean).join(' ');
    }
    const fieldErrors = body?.fieldErrors;
    if (fieldErrors && typeof fieldErrors === 'object') {
        const msgs = Object.values(fieldErrors).flat().map(e => e?.message).filter(Boolean);
        if (msgs.length) return msgs.join(' ');
    }
    return err.message ?? null;
}

/**
 * @description Error serialized to text, or null.
 * @param {Object} err Error
 * @return {string|null}
 */
function serializeError(err) {
    if (!err) return null;
    try {
        const payload = err.body ?? err;
        const text = typeof payload === 'string' ? payload : JSON.stringify(payload);
        return text && text !== '{}' ? text : null;
    } catch (e) {
        return err.message ?? null;
    }
}

/**
 * @description Readable message of a save or load error.
 * @param {Object} err Error
 * @return {string}
 */
export function errorMessage(err) {
    return ldsErrorMessage(err) || serializeError(err) || 'Save failed.';
}

/**
 * @description Validates staged line edits.
 * @param {Object} pendingEdits Staged edits keyed by line Id
 * @param {Function} validateEdit Returns an error message for an edit, or null
 * @return {Object} Error messages keyed by line Id (empty when all edits are valid)
 */
export function validateEdits(pendingEdits, validateEdit) {
    const errors = {};
    for (const [id, edit] of Object.entries(pendingEdits)) {
        const error = validateEdit(edit);
        if (error) {
            errors[id] = error;
        }
    }
    return errors;
}

/**
 * @description Copy of a map without one key.
 * @param {Object} map Map keyed by line Id
 * @param {string} key Key to remove
 * @return {Object}
 */
export function withoutKey(map, key) {
    const next = { ...map };
    delete next[key];
    return next;
}

/**
 * @description Opens the cards of edited lines that have an error, so the error is visible after Save All.
 * @param {Object} editStateMap Card state keyed by line Id
 * @param {Object} pendingEdits Staged edits keyed by line Id
 * @param {Object} editErrors Error messages keyed by line Id
 * @return {Object} Card state with those cards open
 */
export function openCardsWithErrors(editStateMap, pendingEdits, editErrors) {
    const next = { ...editStateMap };
    Object.keys(pendingEdits)
        .filter(id => editErrors[id])
        .forEach(id => {
            next[id] = { ...next[id], isEditing: true };
        });
    return next;
}

/**
 * @description Saves staged line edits one by one, so each failure is reported on its own line.
 * @param {Object} pendingEdits Staged edits keyed by line Id
 * @param {Function} saveEdit Saves one edit (id, edit) and returns a Promise
 * @return {Promise<Object>} okIds, failedEdits (still staged) and errors keyed by line Id
 */
export async function saveEditsInOrder(pendingEdits, saveEdit) {
    const okIds = [];
    const failedEdits = {};
    const errors = {};
    for (const [id, edit] of Object.entries(pendingEdits)) {
        try {
            // eslint-disable-next-line no-await-in-loop
            await saveEdit(id, edit);
            okIds.push(id);
        } catch (err) {
            failedEdits[id] = edit;
            errors[id] = errorMessage(err);
        }
    }
    return { okIds, failedEdits, errors };
}

/**
 * @description Shows a toast from a component.
 * @param {LightningElement} component Component dispatching the toast
 * @param {string} title Title
 * @param {string} message Message
 * @param {string} variant success, warning, error or info
 */
export function showToast(component, title, message, variant) {
    component.dispatchEvent(new ShowToastEvent({ title, message, variant }));
}