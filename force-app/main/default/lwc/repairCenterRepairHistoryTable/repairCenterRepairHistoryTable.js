import { LightningElement, api } from 'lwc';

/**
 * GW-4495 / GW-3400 - Presentational repair history table for evaluation Asset Information.
 */
export default class RepairCenterRepairHistoryTable extends LightningElement {
    @api rows = [];
    @api hasMore = false;

    showAll = false;

    /**
     * GW-4495 - All history rows returned for the Asset.
     */
    get allRows() {
        return this.rows || [];
    }

    /**
     * GW-4495 - True when the Asset has any prior Work Orders.
     */
    get hasAnyRows() {
        return this.allRows.length > 0;
    }

    /**
     * GW-4495 - Rows currently shown: last 12 months, or the full Asset history after View All.
     */
    get displayedRows() {
        const source = this.showAll
            ? this.allRows
            : this.allRows.filter((row) => row.isWithinLastTwelveMonths === true);
        const ordered = [...source].sort((left, right) => this.compareShipDateDesc(left, right));
        return ordered.map((row) => {
            const repairCodeLines = row.repairCodeLines || [];
            return {
                ...row,
                labNameDisplay: this.displayText(row.labName),
                reportedProblemDisplay: this.displayText(row.reportedProblem),
                evaluationNotesDisplay: this.displayText(row.evaluationNotes),
                internalNotesDisplay: this.displayText(row.internalNotes),
                repairCodeLines,
                hasRepairCodes: repairCodeLines.length > 0
            };
        });
    }

    /**
     * GW-4495 - True when the current view has table rows.
     */
    get hasVisibleRows() {
        return this.displayedRows.length > 0;
    }

    /**
     * GW-4495 - True when older-than-12-month Work Orders can be expanded.
     */
    get showViewAll() {
        return this.hasOlderRows && !this.showAll;
    }

    /**
     * GW-4495 - True when the expanded list can be collapsed.
     */
    get showCollapse() {
        return this.hasOlderRows && this.showAll;
    }

    /**
     * GW-4495 - True when at least one row is outside the default 12-month window.
     */
    get hasOlderRows() {
        return this.allRows.some((row) => row.isWithinLastTwelveMonths !== true);
    }

    /**
     * GW-4495 - Expands the table to all returned history rows for the Asset.
     */
    handleViewAll() {
        this.showAll = true;
    }

    /**
     * GW-4495 - Collapses the table to Actual Ship Date within the past 12 months.
     */
    handleShowLess() {
        this.showAll = false;
    }

    /**
     * GW-4495 - Newest Actual Ship Date first. Rows with no ship date stay at the bottom.
     */
    compareShipDateDesc(left, right) {
        const leftDate = left?.repairDate || '';
        const rightDate = right?.repairDate || '';
        if (leftDate === rightDate) {
            return 0;
        }
        if (!leftDate) {
            return 1;
        }
        if (!rightDate) {
            return -1;
        }
        return leftDate < rightDate ? 1 : -1;
    }

    displayText(value) {
        const text = value == null ? '' : String(value).trim();
        return text || '—';
    }
}