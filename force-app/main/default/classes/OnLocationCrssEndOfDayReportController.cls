/**
 * @author Uptima Development Team
 * @date 2026-10-28
 * @description GW-6257 - Rows for the CRSS On Location End of Day Report email.
 *              Reads the inspected Product Serviced lines on the CRSS site visit Work Order.
 *              Lines with an outcome other than Do Not Use(P0) fill the Inspected Asset table.
 *              Do Not Use(P0) lines fill the Do Not Use Assets table.
 *              without sharing so the email shows every line, whoever runs the send.
 * @group Service Appointment
 * @see OnLocationCrssEndOfDayReportTables
 */
public without sharing class OnLocationCrssEndOfDayReportController {
    /** @description Outcome of the Do Not Use Assets table. */
    public static final String OUTCOME_DO_NOT_USE_P0 = 'Do Not Use(P0)';

    /** @description CRSS site visit Work Order the email is about. Set by the component attribute. */
    public Id siteVisitWorkOrderId { get; set; }

    private List<ReportRow> inspectedRowList;
    private List<ReportRow> doNotUseRowList;

    /**
     * @description One asset row in a report table.
     */
    public class ReportRow {
        /** @description Asset name. */
        public String assetName { get; set; }
        /** @description Asset serial number. */
        public String serialNumber { get; set; }
        /** @description Asset manufacturer, from the Product. */
        public String make { get; set; }
        /** @description Asset model, from the Product. */
        public String model { get; set; }
        /** @description Inspection Outcome. */
        public String inspectionOutcome { get; set; }
        /** @description Reported Problem. */
        public String reportedProblem { get; set; }
    }

    /**
     * @description Inspected lines, except Do Not Use(P0).
     * @return Report rows
     */
    public List<ReportRow> getInspectedRows() {
        loadRows();
        return inspectedRowList;
    }

    /**
     * @description Do Not Use(P0) lines.
     * @return Report rows
     */
    public List<ReportRow> getDoNotUseRows() {
        loadRows();
        return doNotUseRowList;
    }

    /**
     * @description True when the Inspected Asset table has rows.
     * @return Whether to show the Inspected Asset table
     */
    public Boolean getHasInspectedRows() {
        return !getInspectedRows().isEmpty();
    }

    /**
     * @description True when the Do Not Use Assets table has rows.
     * @return Whether to show the Do Not Use Assets table
     */
    public Boolean getHasDoNotUseRows() {
        return !getDoNotUseRows().isEmpty();
    }

    /**
     * @description Loads both tables once per render.
     */
    private void loadRows() {
        if (inspectedRowList != null) {
            return;
        }
        inspectedRowList = new List<ReportRow>();
        doNotUseRowList = new List<ReportRow>();
        for (WorkOrderLineItem line : WorkOrderLineItemsSelector.selectCrssInspectedLines(siteVisitWorkOrderId)) {
            ReportRow row = new ReportRow();
            row.assetName = line.Asset?.Name;
            row.serialNumber = line.Asset?.SerialNumber;
            row.make = line.Asset?.ManufacturerCalculated__c;
            row.model = line.Asset?.ModelCalculated__c;
            row.inspectionOutcome = line.InspectionOutcome__c;
            row.reportedProblem = line.ReportedProblem__c;
            if (line.InspectionOutcome__c == OUTCOME_DO_NOT_USE_P0) {
                doNotUseRowList.add(row);
            } else {
                inspectedRowList.add(row);
            }
        }
    }
}