import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import getCalendar from '@salesforce/apex/MockRoomORICalendarController.getCalendar';

const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

export default class MockRoomOriCalendar extends LightningElement {
    @api excludeRequestId;

    _primaryDate;
    _backupDate;
    _businessJustification = '';
    _hasConflict = false;

    monthCursor = new Date(new Date().getFullYear(), new Date().getMonth(), 1);
    highlightToday = false;
    events = [];
    blocks = [];
    message = '';
    loadError = '';

    @api
    get primaryDate() {
        return this._primaryDate;
    }
    set primaryDate(value) {
        this._primaryDate = this.normalizeDate(value);
    }

    @api
    get backupDate() {
        return this._backupDate;
    }
    set backupDate(value) {
        this._backupDate = this.normalizeDate(value);
    }

    @api
    get businessJustification() {
        return this._businessJustification;
    }
    set businessJustification(value) {
        this._businessJustification = value || '';
    }

    @api
    get hasConflict() {
        return this._hasConflict;
    }
    set hasConflict(value) {
        this._hasConflict = value === true || value === 'true';
    }

    connectedCallback() {
        this.loadMonth();
    }

    get weekdayLabels() {
        return WEEKDAYS;
    }

    get monthLabel() {
        return this.monthCursor.toLocaleString('en-US', { month: 'long', year: 'numeric' });
    }

    get dayCells() {
        const first = new Date(this.monthCursor.getFullYear(), this.monthCursor.getMonth(), 1);
        const gridStart = new Date(first);
        gridStart.setDate(first.getDate() - first.getDay());
        const cells = [];
        for (let index = 0; index < 42; index += 1) {
            const date = new Date(gridStart);
            date.setDate(gridStart.getDate() + index);
            const iso = this.toIso(date);
            const inMonth = date.getMonth() === this.monthCursor.getMonth();
            const past = this.isBeforeToday(iso);
            const isToday = iso === this.todayIso();
            const classes = ['day'];
            if (!inMonth) {
                classes.push('outside');
            }
            if (past) {
                classes.push('past');
            }
            if (isToday) {
                classes.push('is-today');
            }
            if (isToday && this.highlightToday) {
                classes.push('today-focus');
            }
            if (iso === this._primaryDate || iso === this._backupDate) {
                classes.push('selected');
            }
            let selectionLabel = '';
            if (iso === this._primaryDate && iso === this._backupDate) {
                selectionLabel = 'Primary and backup';
            } else if (iso === this._primaryDate) {
                selectionLabel = 'Primary';
            } else if (iso === this._backupDate) {
                selectionLabel = 'Backup';
            }
            cells.push({
                iso,
                dayLabel: isToday
                    ? String(date.getDate())
                    : (date.getDate() === 1
                        ? date.toLocaleString('en-US', { month: 'short', day: 'numeric' })
                        : String(date.getDate())),
                numberClass: isToday ? 'number today-number' : (inMonth ? 'number' : 'number outside-number'),
                className: classes.join(' '),
                selectionLabel,
                isPast: past,
                tabIndex: past ? '-1' : '0',
                bars: this.barsFor(iso)
            });
        }
        return cells;
    }

    previousMonth() {
        this.monthCursor = new Date(this.monthCursor.getFullYear(), this.monthCursor.getMonth() - 1, 1);
        this.loadMonth();
    }

    nextMonth() {
        this.monthCursor = new Date(this.monthCursor.getFullYear(), this.monthCursor.getMonth() + 1, 1);
        this.loadMonth();
    }

    goToToday() {
        const today = new Date();
        this.highlightToday = false;
        this.monthCursor = new Date(today.getFullYear(), today.getMonth(), 1);
        this.loadMonth();
        Promise.resolve().then(() => {
            this.highlightToday = true;
        });
    }

    selectDay(event) {
        const iso = event.currentTarget.dataset.iso;
        if (this.isBeforeToday(iso)) {
            this.message = 'A past date cannot be requested. Choose today or a later date.';
            return;
        }
        const block = this.blockFor(iso);
        if (block) {
            this.message = 'This date is blocked. Choose another date. A blocked date cannot be requested.';
            return;
        }

        if (!this._primaryDate || (this._primaryDate && this._backupDate)) {
            this._primaryDate = iso;
            this._backupDate = null;
        } else if (iso === this._primaryDate) {
            this.message = 'Choose a different day for the backup date.';
            return;
        } else {
            this._backupDate = iso;
        }
        this.refreshConflict();
    }

    clearDates() {
        this._primaryDate = null;
        this._backupDate = null;
        this._hasConflict = false;
        this.message = '';
        this.publish();
    }

    justificationChanged(event) {
        this._businessJustification = event.target.value;
        this.publish();
    }

    @api
    validate() {
        if (!this._primaryDate || !this._backupDate) {
            return {
                isValid: false,
                errorMessage: 'Select a primary requested date and a backup requested date.'
            };
        }
        if (this.isBeforeToday(this._primaryDate) || this.isBeforeToday(this._backupDate)) {
            return {
                isValid: false,
                errorMessage: 'A past date cannot be requested. Choose today or a later date.'
            };
        }
        if (this.blockFor(this._primaryDate) || this.blockFor(this._backupDate)) {
            return {
                isValid: false,
                errorMessage: 'A blocked date cannot be requested. Choose a date Strategic Events has not closed.'
            };
        }
        if (this._hasConflict && !this._businessJustification) {
            return {
                isValid: false,
                errorMessage: 'Enter a business justification for the date that already has an event.'
            };
        }
        return { isValid: true };
    }

    loadMonth() {
        const gridStart = new Date(this.monthCursor.getFullYear(), this.monthCursor.getMonth(), 1);
        gridStart.setDate(gridStart.getDate() - gridStart.getDay());
        const gridEnd = new Date(gridStart);
        gridEnd.setDate(gridStart.getDate() + 41);
        this.loadError = '';
        getCalendar({
            rangeStart: this.toIso(gridStart),
            rangeEnd: this.toIso(gridEnd),
            excludeRequestId: this.excludeRequestId || null
        })
            .then((data) => {
                this.events = data.events || [];
                this.blocks = data.blocks || [];
                this.refreshConflict();
            })
            .catch((error) => {
                this.events = [];
                this.blocks = [];
                this.loadError = this.readError(error);
            });
    }

    refreshConflict() {
        const primaryEvents = this.conflictingEvents(this._primaryDate);
        const backupEvents = this.conflictingEvents(this._backupDate);
        this._hasConflict = primaryEvents.length > 0 || backupEvents.length > 0;
        const names = [...primaryEvents, ...backupEvents].map(
            (row) => `${row.requestName} (${row.requestType}, ${row.status})`
        );
        if (this._hasConflict) {
            this.message = `This date already has an event: ${[...new Set(names)].join(', ')}. You can still request it. Enter a business justification. Strategic Events will decide whether it can be supported.`;
        } else if (this._primaryDate && this._backupDate) {
            this.message = 'Both dates are free of other Mock Room and ORI events.';
        } else if (this._primaryDate) {
            this.message = 'Primary date selected. Choose the backup date.';
        } else {
            this.message = 'Select the primary requested date, then the backup requested date.';
        }
        this.publish();
    }

    publish() {
        this.dispatchEvent(new FlowAttributeChangeEvent('primaryDate', this._primaryDate));
        this.dispatchEvent(new FlowAttributeChangeEvent('backupDate', this._backupDate));
        this.dispatchEvent(new FlowAttributeChangeEvent('hasConflict', this._hasConflict));
        this.dispatchEvent(new FlowAttributeChangeEvent('businessJustification', this._businessJustification));
    }

    barsFor(iso) {
        const bars = [];
        const block = this.blockFor(iso);
        if (block) {
            const start = this.normalizeDate(block.startDate);
            const end = this.normalizeDate(block.endDate);
            bars.push({
                key: `block-${iso}`,
                text: '\u00a0',
                title: 'Blocked',
                className: this.barClass('blocked', start, end, iso)
            });
        }
        this.eventsFor(iso).slice(0, 2).forEach((row, index) => {
            const confirmed = row.status === 'Approved';
            const typeLabel = row.requestType === 'ORI Demonstration' ? 'ORI' : 'Mock Room';
            const text = `${typeLabel} - ${row.requestName}`;
            bars.push({
                key: `${iso}-event-${index}`,
                text: confirmed ? '\u00a0' : text,
                title: confirmed ? 'Confirmed' : `${text} (${row.status}, ${row.dateRole})`,
                className: confirmed ? 'bar confirmed span-single' : 'bar pending span-single'
            });
        });
        return bars;
    }

    barClass(tone, start, end, iso) {
        const continuesBefore = start && this.shiftIso(iso, -1) >= start;
        const continuesAfter = end && this.shiftIso(iso, 1) <= end;
        let span = 'span-single';
        if (continuesBefore && continuesAfter) {
            span = 'span-middle';
        } else if (continuesBefore) {
            span = 'span-end';
        } else if (continuesAfter) {
            span = 'span-start';
        }
        return `bar ${tone} ${span}`;
    }

    shiftIso(iso, days) {
        const [year, month, day] = iso.split('-').map(Number);
        const date = new Date(year, month - 1, day);
        date.setDate(date.getDate() + days);
        return this.toIso(date);
    }

    conflictingEvents(iso) {
        return this.eventsFor(iso).filter((row) => !this.isRequestBeingEdited(row.requestId));
    }

    isRequestBeingEdited(requestId) {
        if (!this.excludeRequestId || !requestId) {
            return false;
        }
        return String(requestId).substring(0, 15) === String(this.excludeRequestId).substring(0, 15);
    }

    eventsFor(iso) {
        if (!iso) {
            return [];
        }
        return this.events.filter((row) => this.normalizeDate(row.eventDate) === iso);
    }

    blockFor(iso) {
        if (!iso) {
            return null;
        }
        return this.blocks.find((block) => {
            const start = this.normalizeDate(block.startDate);
            const end = this.normalizeDate(block.endDate);
            return start && end && iso >= start && iso <= end;
        });
    }

    todayIso() {
        return this.toIso(new Date());
    }

    isBeforeToday(iso) {
        return !!iso && iso < this.todayIso();
    }

    normalizeDate(value) {
        if (!value) {
            return null;
        }
        const text = String(value);
        return text.length >= 10 ? text.substring(0, 10) : text;
    }

    toIso(date) {
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        return `${date.getFullYear()}-${month}-${day}`;
    }

    readError(error) {
        return error?.body?.message || 'The calendar could not be loaded.';
    }
}