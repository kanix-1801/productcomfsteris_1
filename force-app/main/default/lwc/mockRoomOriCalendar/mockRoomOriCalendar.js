import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import getCalendar from '@salesforce/apex/MockRoomORICalendarController.getCalendar';

const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const FLOW_OUTPUTS = ['primaryDate', 'backupDate', 'hasConflict', 'businessJustification', 'eventDuration'];
const PAST_DATE_MESSAGE = 'A past date cannot be requested. Choose today or a later date.';
const invalid = (errorMessage) => ({ isValid: false, errorMessage });
const toDuration = (value) => {
    const parsed = Number(value);
    return Number.isFinite(parsed) && parsed >= 1 ? Math.floor(parsed) : 1;
};

export default class MockRoomOriCalendar extends LightningElement {
    @api excludeRequestId;

    _primaryDate;
    _backupDate;
    _businessJustification = '';
    _hasConflict = false;
    _eventDuration = 1;

    weekdayLabels = WEEKDAYS;
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
    get eventDuration() {
        return this._eventDuration;
    }
    set eventDuration(value) {
        this._eventDuration = toDuration(value);
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

    get monthLabel() {
        return this.monthCursor.toLocaleString('en-US', { month: 'long', year: 'numeric' });
    }

    /** Primary span uses the event duration. The backup date stays one day until it is confirmed. */
    get selectedDates() {
        return [...this.spanDates(this._primaryDate, this._eventDuration), ...this.spanDates(this._backupDate, 1)];
    }

    get dayCells() {
        const gridStart = new Date(this.monthCursor);
        gridStart.setDate(1 - gridStart.getDay());
        const todayIso = this.toIso(new Date());
        const selected = this.selectedDates;
        const cells = [];
        for (let index = 0; index < 42; index += 1) {
            const date = new Date(gridStart);
            date.setDate(gridStart.getDate() + index);
            const iso = this.toIso(date);
            const inMonth = date.getMonth() === this.monthCursor.getMonth();
            const past = iso < todayIso;
            const isToday = iso === todayIso;
            let selectionLabel = '';
            if (iso === this._primaryDate) {
                selectionLabel = iso === this._backupDate ? 'Primary and backup' : 'Primary';
            } else if (iso === this._backupDate) {
                selectionLabel = 'Backup';
            }
            cells.push({
                iso,
                dayLabel: isToday || date.getDate() !== 1
                    ? String(date.getDate())
                    : date.toLocaleString('en-US', { month: 'short', day: 'numeric' }),
                numberClass: isToday ? 'number today-number' : (inMonth ? 'number' : 'number outside-number'),
                className: [
                    'day',
                    !inMonth && 'outside',
                    past && 'past',
                    isToday && 'is-today',
                    isToday && this.highlightToday && 'today-focus',
                    selected.includes(iso) && 'selected'
                ].filter(Boolean).join(' '),
                selectionLabel,
                isPast: past,
                tabIndex: past ? '-1' : '0',
                bars: this.barsFor(iso)
            });
        }
        return cells;
    }

    changeMonth(event) {
        const offset = Number(event.currentTarget.dataset.offset);
        this.monthCursor = new Date(this.monthCursor.getFullYear(), this.monthCursor.getMonth() + offset, 1);
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
            this.message = PAST_DATE_MESSAGE;
            return;
        }
        if (this.blockFor(iso)) {
            this.message = 'This date is blocked. Choose another date. A blocked date cannot be requested.';
            return;
        }
        if (!this._primaryDate || this._backupDate) {
            this._primaryDate = iso;
            this._backupDate = null;
        } else {
            this._backupDate = iso === this._primaryDate ? null : iso;
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

    durationChanged(event) {
        this._eventDuration = toDuration(event.target.value);
        this.refreshConflict();
    }

    @api
    validate() {
        const dates = this.selectedDates;
        if (!this._primaryDate) {
            return invalid('Select a primary requested date. The backup requested date is optional.');
        }
        if (dates.some((iso) => this.isBeforeToday(iso))) {
            return invalid(PAST_DATE_MESSAGE);
        }
        if (dates.some((iso) => this.blockFor(iso))) {
            return invalid('A blocked date cannot be requested. Choose a date Strategic Events has not closed.');
        }
        if (this._hasConflict && !this._businessJustification) {
            return invalid('Enter a business justification for the date that already has an event.');
        }
        return { isValid: true };
    }

    loadMonth() {
        const gridStart = new Date(this.monthCursor);
        gridStart.setDate(1 - gridStart.getDay());
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
                this.loadError = error?.body?.message || 'The calendar could not be loaded.';
            });
    }

    refreshConflict() {
        const conflicts = this.selectedDates.flatMap((iso) =>
            this.eventsFor(iso).filter((row) => !this.isRequestBeingEdited(row.requestId))
        );
        this._hasConflict = conflicts.length > 0;
        if (this._hasConflict) {
            const names = new Set(conflicts.map((row) => `${row.requestName} (${row.requestType}, ${row.status})`));
            this.message = `This date already has an event: ${[...names].join(', ')}. You can still request it. Enter a business justification. Strategic Events will decide whether it can be supported.`;
        } else if (this._primaryDate && this._backupDate) {
            this.message = 'Primary and backup dates are free of other Mock Room and ORI events.';
        } else if (this._primaryDate) {
            this.message = 'Primary date selected. A backup date is optional.';
        } else {
            this.message = 'Select the primary requested date. A backup date is optional.';
        }
        this.publish();
    }

    publish() {
        FLOW_OUTPUTS.forEach((name) => this.dispatchEvent(new FlowAttributeChangeEvent(name, this[`_${name}`])));
    }

    openRequest(event) {
        event.preventDefault();
        const requestId = event.currentTarget.dataset.requestId;
        if (requestId) {
            event.stopPropagation();
            window.open(`/${requestId}`, '_blank');
        }
    }

    barsFor(iso) {
        const bars = [];
        const block = this.blockFor(iso);
        if (block) {
            const reason = block.reason || 'Blocked';
            bars.push({
                key: `block-${iso}`,
                text: reason,
                title: reason,
                href: '#',
                requestId: null,
                className: this.barClass(this.normalizeDate(block.startDate), this.normalizeDate(block.endDate), iso)
            });
        }
        this.eventsFor(iso).slice(0, 2).forEach((row, index) => {
            const typeLabel = row.requestType === 'ORI Demonstration' ? 'ORI' : 'Mock Room';
            const text = `${row.requestName} - ${row.accountName || 'Customer'} - ${typeLabel}`;
            bars.push({
                key: `${iso}-event-${index}`,
                text,
                title: `${text} (${row.status}, ${row.dateRole})`,
                href: `/${row.requestId}`,
                requestId: row.requestId,
                className: row.status === 'Approved' ? 'bar confirmed span-single' : 'bar pending span-single'
            });
        });
        return bars;
    }

    /** Rounds the block bar on the first and last day of a multi-day block. */
    barClass(start, end, iso) {
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
        return `bar blocked ${span}`;
    }

    spanDates(startIso, dayCount) {
        return startIso ? Array.from({ length: dayCount }, (unused, offset) => this.shiftIso(startIso, offset)) : [];
    }

    shiftIso(iso, days) {
        const [year, month, day] = iso.split('-').map(Number);
        return this.toIso(new Date(year, month - 1, day + days));
    }

    isRequestBeingEdited(requestId) {
        return !!this.excludeRequestId && !!requestId
            && String(requestId).substring(0, 15) === String(this.excludeRequestId).substring(0, 15);
    }

    eventsFor(iso) {
        return this.events.filter((row) => this.normalizeDate(row.eventDate) === iso);
    }

    blockFor(iso) {
        return this.blocks.find((block) => {
            const start = this.normalizeDate(block.startDate);
            const end = this.normalizeDate(block.endDate);
            return start && end && iso >= start && iso <= end;
        });
    }

    isBeforeToday(iso) {
        return !!iso && iso < this.toIso(new Date());
    }

    normalizeDate(value) {
        return value ? String(value).substring(0, 10) : null;
    }

    toIso(date) {
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        return `${date.getFullYear()}-${month}-${day}`;
    }
}