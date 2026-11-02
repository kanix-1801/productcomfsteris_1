/**
 * @author Uptima Development Team
 * @date 2026-10-26
 * @description GW-6191 - Rows for the On Location End of Day Report email.
 *              Reads instrument lines on the completed (not closed) child Work Orders of the site visit.
 *              Lines sent to the National Repair Center fill the first table. Beyond repair lines
 *              (a Reported Problem without Send to Repair Center) fill the second table.
 *              without sharing so the email shows every child line, whoever owns the child Work Order.
 * @group Service Appointment
 * @see OnLocationEndOfDayReportTables
 */
public without sharing class OnLocationEndOfDayReportController {
    /** @description Site visit Work Order the email is about. Set by the component attribute. */
    public Id siteVisitWorkOrderId { get; set; }

    private List<ReportRow> repairCenterRowList;
    private List<ReportRow> beyondRepairRowList;

    /**
     * @description One instrument row in a report table.
     */
    public class ReportRow {
        /** @description Tray (Asset) name. */
        public String trayName { get; set; }
        /** @description Instrument (Product) name. */
        public String instrument { get; set; }
        /** @description Make entered on the beyond repair fields. */
        public String manufacturer { get; set; }
        /** @description Model entered on the beyond repair fields. */
        public String catalogNumber { get; set; }
        /** @description Line quantity. */
        public Decimal quantity { get; set; }
        /** @description Reported Problem. */
        public String reason { get; set; }
        /** @description Yes or No for Replaced with I-Xchange. */
        public String replacedWithIXchange { get; set; }
    }

    /**
     * @description Lines sent to the National Repair Center.
     * @return Report rows
     */
    public List<ReportRow> getRepairCenterRows() {
        loadRows();
        return repairCenterRowList;
    }

    /**
     * @description Beyond repair lines not sent to the National Repair Center.
     * @return Report rows
     */
    public List<ReportRow> getBeyondRepairRows() {
        loadRows();
        return beyondRepairRowList;
    }

    /**
     * @description True when the first table has rows.
     * @return Whether to show the National Repair Center table
     */
    public Boolean getHasRepairCenterRows() {
        return !getRepairCenterRows().isEmpty();
    }

    /**
     * @description True when the second table has rows.
     * @return Whether to show the Beyond Repair table
     */
    public Boolean getHasBeyondRepairRows() {
        return !getBeyondRepairRows().isEmpty();
    }

    /**
     * @description Loads both tables once per render.
     */
    private void loadRows() {
        if (repairCenterRowList != null) {
            return;
        }
        repairCenterRowList = new List<ReportRow>();
        beyondRepairRowList = new List<ReportRow>();
        if (siteVisitWorkOrderId == null) {
            return;
        }
        Set<Id> childIds = new Map<Id, WorkOrder>(
            WorkOrdersSelector.selectCompletedChildWorkOrders(new Set<Id>{ siteVisitWorkOrderId }, null)
        ).keySet();
        for (WorkOrderLineItem line : WorkOrderLineItemsSelector.selectActiveInstrumentLines(childIds)) {
            if (line.SendToRepairCenter__c) {
                repairCenterRowList.add(toRow(line));
            } else if (String.isNotBlank(line.ReportedProblem__c)) {
                beyondRepairRowList.add(toRow(line));
            }
        }
    }

    /**
     * @description Maps an instrument line to a report row.
     * @param line Instrument line
     * @return Report row
     */
    private static ReportRow toRow(WorkOrderLineItem line) {
        ReportRow row = new ReportRow();
        row.trayName = String.isNotBlank(line.Asset?.Name) ? line.Asset.Name : line.WorkOrder?.Asset?.Name;
        row.instrument = line.Product2?.Name;
        row.manufacturer = line.SerialNumber__c;
        row.catalogNumber = line.Model__c;
        row.quantity = line.Quantity;
        row.reason = line.ReportedProblem__c;
        row.replacedWithIXchange = line.ReplacedWithIXchange__c ? 'Yes' : 'No';
        return row;
    }
}