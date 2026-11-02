/**
 * @description GW-5830 - Trigger handler for RepairCenterCdlTrigger.
 *              Thin orchestration only; delegates to RepairCenterContentDocumentLinksService.
 *              No SOQL or DML in this class.
 * @group WorkOrder
 */
public with sharing class RepairCenterCdlTriggerHandler extends TriggerHandler {
    /**
     * @description GW-5830 - After insert, runs Repair Center PO Required advancement
     *              when a file is linked to a Work Order.
     */
    public override void afterInsert() {
        if (!AutomationControl.isTriggerEnabled('RepairCenterCdlTrigger')) {
            return;
        }
        // GW-375: Repair Center PO advancement temporarily disabled until WorkOrdersSelector
        // selectForApproveRejectQuoteByIds is deployed and dependent classes recompile in CBM_Sandbox.
    }
}