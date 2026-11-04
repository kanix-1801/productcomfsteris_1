import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import LOCALE from '@salesforce/i18n/locale';
import getUnavailableDates from '@salesforce/apex/CscAvailabilityController.getUnavailableDates';
import getUnavailableDatesForVisit from '@salesforce/apex/CscAvailabilityController.getUnavailableDatesForVisit';

import CLEAR_HINT from '@salesforce/label/c.Calendar_Clear_Hint';
import ERROR_DATE_REQUIRED from '@salesforce/label/c.Calendar_Error_Date_Required';
import ERROR_DATES_MUST_DIFFER from '@salesforce/label/c.Calendar_Error_Dates_Must_Differ';
import PRIMARY_DATE_LABEL from '@salesforce/label/c.CSC_Primary_Requested_Date';
import BACKUP_DATE_LABEL from '@salesforce/label/c.CSC_Backup_Requested_Date';
import SELECT_AVAILABLE_DATE from '@salesforce/label/c.CSC_Select_Available_Date';

const TEXT = {
    available: 'Available',
    pending: 'Pending',
    unavailable: 'Unavailable',
    weekend: 'Weekend',
    pastDate: 'Past date',
    loading: 'Loading availability',
    previousMonth: 'Previous month',
    nextMonth: 'Next month',
    resetDates: 'Reset Dates'
};

/** Converts a Date to YYYY-MM-DD. */
function toIso(date) {
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day}`;
}

/** Flow may pass a Date or a datetime string. The grid compares YYYY-MM-DD. */
function normalizeDate(value) {
    if (!value) {
        return null;
    }
    if (value instanceof Date) {
        return toIso(value);
    }
    const text = String(value);
    return text.length >= 10 ? text.substring(0, 10) : text;
}

/** Fills {0}, {1} placeholders in a label. */
function format(template, ...args) {
    return args.reduce((text, value, index) => text.replace(`{${index}}`, value), template);
}

/**
 * GC-3302 CSC visit calendar. Loads occupancy for a visit location
 * and returns Primary and Backup dates to Flow.
 */
export default class CscVisitCalendar extends LightningElement {
    weeks = [];
    isLoading = false;

    label = {
        available: TEXT.available,
        pending: TEXT.pending,
        unavailable: TEXT.unavailable,
        loading: TEXT.loading,
        previousMonth: TEXT.previousMonth,
        nextMonth: TEXT.nextMonth,
        resetDates: TEXT.resetDates,
        clearHint: CLEAR_HINT,
        primaryDate: PRIMARY_DATE_LABEL,
        backupDate: BACKUP_DATE_LABEL,
        confirmedDate: 'Confirmed Date'
    };

    today = toIso(new Date());
    viewDate = new Date();
    dateStatus = new Map();

    _requestType;
    _visitLocation;
    _primaryDate;
    _backupDate;
    _selectionMode = 'Visit';
    _excludeVisitId;
    _datesToBlock = [];
    _datesToUnblock = [];

    /** Request Type from Flow. ORC, IMS, and OSV each reload their own calendar. */
    @api
    get requestType() {
        return this._requestType;
    }
    set requestType(value) {
        const changed = this._requestType !== value;
        this._requestType = value;
        if (changed && this.isConnected) {
            this.loadMonth();
        }
    }

    /** Visit Location from Flow. Reloads the CSC calendar when it changes. */
    @api
    get visitLocation() {
        return this._visitLocation;
    }
    set visitLocation(value) {
        const changed = this._visitLocation !== value;
        this._visitLocation = value;
        if (changed && this.isConnected) {
            this.loadMonth();
        }
    }

    /** Primary date selected on the calendar. */
    @api
    get primaryDate() {
        return this._primaryDate;
    }
    set primaryDate(value) {
        this._primaryDate = normalizeDate(value);
        this.buildWeeks();
    }

    /** Backup date selected on the calendar. */
    @api
    get backupDate() {
        return this._backupDate;
    }
    set backupDate(value) {
        this._backupDate = normalizeDate(value);
        this.buildWeeks();
    }

    /** Visit keeps primary and backup. Block lets an admin select many days. */
    @api
    get selectionMode() {
        return this._selectionMode;
    }
    set selectionMode(value) {
        if (value === 'Block') {
            this._selectionMode = 'Block';
        } else if (value === 'Change') {
            this._selectionMode = 'Change';
        } else {
            this._selectionMode = 'Visit';
        }
        this.buildWeeks();
    }

    /** Visit being rescheduled. Its own dates stay selectable. */
    @api
    get excludeVisitId() {
        return this._excludeVisitId;
    }
    set excludeVisitId(value) {
        const changed = this._excludeVisitId !== value;
        this._excludeVisitId = value;
        if (changed && this.isConnected) {
            this.loadMonth();
        }
    }

    /** Dates the admin added, separated by semicolons, for the flow. */
    @api
    get datesToBlock() {
        return this._datesToBlock.join(';');
    }

    /** Blocked dates the admin cleared, separated by semicolons, for the flow. */
    @api
    get datesToUnblock() {
        return this._datesToUnblock.join(';');
    }

    get isBlockMode() {
        return this._selectionMode === 'Block';
    }

    get isChangeMode() {
        return this._selectionMode === 'Change';
    }

    get showVisitDates() {
        return !this.isBlockMode && !this.isChangeMode;
    }

    get blockSummary() {
        const blocking = this._datesToBlock.length
            ? `Block: ${this._datesToBlock.join(', ')}`
            : '';
        const unblocking = this._datesToUnblock.length
            ? `Remove: ${this._datesToUnblock.join(', ')}`
            : '';
        return [blocking, unblocking].filter(Boolean).join(' · ') || 'Click each day to block. Click a blocked day to remove it.';
    }

    /** Loads occupancy when the component is added to the screen. */
    connectedCallback() {
        this.loadMonth();
    }

    /** Sunday-first weekday headers in the user locale. */
    get weekdays() {
        const shortFmt = new Intl.DateTimeFormat(LOCALE, { weekday: 'short' });
        const longFmt = new Intl.DateTimeFormat(LOCALE, { weekday: 'long' });
        // 4 Jan 2026 is a Sunday, so the columns stay Sunday-first.
        return Array.from({ length: 7 }, (unused, index) => {
            const date = new Date(2026, 0, 4 + index);
            return { short: shortFmt.format(date), full: longFmt.format(date) };
        });
    }

    /** Visible month and year, for example September 2026. */
    get monthLabel() {
        return new Intl.DateTimeFormat(LOCALE, { month: 'long', year: 'numeric' }).format(this.viewDate);
    }

    /**
     * Flow Next/Finish check. Both dates are required and must differ.
     * @returns {{isValid: Boolean, errorMessage?: String}}
     */
    @api
    validate() {
        if (this.isBlockMode) {
            if (!this._datesToBlock.length && !this._datesToUnblock.length) {
                return { isValid: false, errorMessage: 'Select at least one date to block or remove.' };
            }
            return { isValid: true };
        }
        if (this.isChangeMode) {
            if (!this._primaryDate) {
                return { isValid: false, errorMessage: SELECT_AVAILABLE_DATE };
            }
            return { isValid: true };
        }
        if (!this._primaryDate) {
            return { isValid: false, errorMessage: format(ERROR_DATE_REQUIRED, this.label.primaryDate) };
        }
        if (!this._backupDate) {
            return { isValid: false, errorMessage: format(ERROR_DATE_REQUIRED, this.label.backupDate) };
        }
        if (this._primaryDate === this._backupDate) {
            return {
                isValid: false,
                errorMessage: format(ERROR_DATES_MUST_DIFFER, this.label.backupDate, this.label.primaryDate)
            };
        }
        return { isValid: true };
    }

    /** Shows the previous month. */
    handlePrevious() {
        this.viewDate = new Date(this.viewDate.getFullYear(), this.viewDate.getMonth() - 1, 1);
        this.loadMonth();
    }

    /** Shows the next month. */
    handleNext() {
        this.viewDate = new Date(this.viewDate.getFullYear(), this.viewDate.getMonth() + 1, 1);
        this.loadMonth();
    }

    /** Loads Pending and Confirmed dates for the visible month. */
    async loadMonth() {
        const year = this.viewDate.getFullYear();
        const month = this.viewDate.getMonth();
        const status = new Map();

        if (this.shouldLoadOccupancy) {
            this.isLoading = true;
            try {
                const range = {
                    requestType: this._requestType,
                    visitLocation: this._visitLocation,
                    startDate: toIso(new Date(year, month, 1)),
                    endDate: toIso(new Date(year, month + 1, 0))
                };
                const rows = this._excludeVisitId
                    ? await getUnavailableDatesForVisit({
                        ...range,
                        excludeVisitId: this._excludeVisitId
                    })
                    : await getUnavailableDates(range);
                (rows || []).forEach((row) => {
                    status.set(row.dateValue, row.reason);
                });
            } catch (error) {
                // Calendar still renders; occupancy just will not grey out.
            }
            this.isLoading = false;
        }

        this.dateStatus = status;
        this.buildWeeks();
    }

    /** ORC, IMS, and OSV load without a location. CSC and block mode need a location. */
    get shouldLoadOccupancy() {
        if (this._requestType === 'ORC' || this._requestType === 'IMS' || this._requestType === 'OSV') {
            return true;
        }
        return Boolean(this._visitLocation);
    }

    /** True when the date cannot be selected. Block mode can still toggle a blocked day. */
    isUnavailable(iso) {
        const dayOfWeek = new Date(`${iso}T00:00:00`).getDay();
        if (dayOfWeek === 0 || dayOfWeek === 6 || iso < this.today) {
            return true;
        }
        if (!this.isBlockMode) {
            return this.dateStatus.has(iso);
        }
        const reason = this.dateStatus.get(iso);
        return reason === TEXT.pending || reason === 'Confirmed';
    }

    /** Tooltip text for a blocked date. */
    unavailableReason(iso) {
        const dayOfWeek = new Date(`${iso}T00:00:00`).getDay();
        if (dayOfWeek === 0 || dayOfWeek === 6) {
            return TEXT.weekend;
        }
        if (iso < this.today) {
            return TEXT.pastDate;
        }
        return this.dateStatus.get(iso) === TEXT.pending ? TEXT.pending : TEXT.unavailable;
    }

    /** Builds the month grid and applies selected / blocked styles. */
    buildWeeks() {
        const year = this.viewDate.getFullYear();
        const month = this.viewDate.getMonth();
        const daysInMonth = new Date(year, month + 1, 0).getDate();
        const cells = [];

        for (let i = 0; i < new Date(year, month, 1).getDay(); i += 1) {
            cells.push({ key: `pad-${i}`, iso: '', label: '', cellClass: 'slds-day_adjacent-month' });
        }

        for (let day = 1; day <= daysInMonth; day += 1) {
            const iso = toIso(new Date(year, month, day));
            const classes = [];
            let title = TEXT.available;

            if (this.isUnavailable(iso)) {
                classes.push('slds-disabled-text');
                title = this.unavailableReason(iso);
                if (this.dateStatus.get(iso) === TEXT.pending) {
                    classes.push('slds-theme_warning');
                }
            }
            if (this.isBlockMode && this.dateStatus.get(iso) === 'Blocked') {
                classes.push('slds-theme_shade');
                title = 'Blocked';
            }
            if (iso === this.today) {
                classes.push('slds-is-today');
            }
            if (this.isBlockMode && this._datesToBlock.includes(iso)) {
                classes.push('slds-is-selected');
                title = 'Date to block';
            } else if (this.isBlockMode && this._datesToUnblock.includes(iso)) {
                classes.push('slds-is-selected');
                title = 'Date to remove';
            } else if (this.isChangeMode && iso === this._primaryDate) {
                classes.push('slds-is-selected');
                title = this.label.confirmedDate;
            } else if (iso === this._primaryDate || iso === this._backupDate) {
                classes.push('slds-is-selected');
                title = iso === this._primaryDate ? this.label.primaryDate : this.label.backupDate;
            }

            cells.push({
                key: iso,
                iso,
                label: day,
                title,
                selected: classes.includes('slds-is-selected') ? 'true' : 'false',
                cellClass: classes.join(' ')
            });
        }

        const weeks = [];
        for (let i = 0; i < cells.length; i += 7) {
            weeks.push({ key: `week-${i}`, days: cells.slice(i, i + 7) });
        }
        this.weeks = weeks;
    }

    /** True when Reset Dates has nothing to clear. */
    get resetDisabled() {
        if (this.isBlockMode) {
            return this._datesToBlock.length === 0 && this._datesToUnblock.length === 0;
        }
        if (this.isChangeMode) {
            return !this._primaryDate;
        }
        return !this._primaryDate && !this._backupDate;
    }

    /** Clears the selected visit dates, or the pending block changes. */
    handleReset() {
        if (this.isBlockMode) {
            this._datesToBlock = [];
            this._datesToUnblock = [];
        } else if (this.isChangeMode) {
            this._primaryDate = null;
        } else {
            this._primaryDate = null;
            this._backupDate = null;
        }
        this.publish();
    }

    /** First click = Primary, second click = Backup. Block mode toggles many days. */
    handleDayClick(event) {
        const iso = event.currentTarget.dataset.iso;
        if (!iso || this.isUnavailable(iso)) {
            return;
        }
        if (this.isBlockMode) {
            this.toggleBlockedDate(iso);
            return;
        }
        if (this.isChangeMode) {
            this._primaryDate = iso === this._primaryDate ? null : iso;
            this._backupDate = null;
            this.publish();
            return;
        }
        if (iso === this._primaryDate) {
            this._primaryDate = null;
        } else if (iso === this._backupDate) {
            this._backupDate = null;
        } else if (!this._primaryDate) {
            this._primaryDate = iso;
        } else {
            this._backupDate = iso;
        }
        this.publish();
    }

    /** Adds or removes one day from the admin block lists. */
    toggleBlockedDate(iso) {
        if (this.dateStatus.get(iso) === 'Blocked') {
            this._datesToUnblock = this.toggleValue(this._datesToUnblock, iso);
        } else {
            this._datesToBlock = this.toggleValue(this._datesToBlock, iso);
        }
        this.publish();
    }

    /** Returns a new list with the value added or removed. */
    toggleValue(values, iso) {
        return values.includes(iso) ? values.filter((value) => value !== iso) : [...values, iso];
    }

    /** Sends the selected dates back to Flow. */
    publish() {
        this.buildWeeks();
        if (this.isBlockMode) {
            this.dispatchEvent(new FlowAttributeChangeEvent('datesToBlock', this.datesToBlock));
            this.dispatchEvent(new FlowAttributeChangeEvent('datesToUnblock', this.datesToUnblock));
            return;
        }
        this.dispatchEvent(new FlowAttributeChangeEvent('primaryDate', this._primaryDate));
        this.dispatchEvent(new FlowAttributeChangeEvent('backupDate', this._backupDate));
    }
}