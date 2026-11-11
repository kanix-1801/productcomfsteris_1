/**
 * @description GW-3377 - Repair Center Execute Pricing and Repair requote gate.
 *              Invokes Pricing_SubFlow_ExecutePricing after WOLI DML and compares
 *              Repair Code TotalPrice sums against the IMS Pre-Approval Limit.
 */
public with sharing class WorkOrderRepairPricingService {
    public static final String REQUOTE_BLOCKED_MESSAGE =
        'The cost of repair has increased and a new quote needs to be approved before work ' +
        'can be continued. Please return to Eval for requote.';

    private static final String FLOW_API_NAME = 'Pricing_SubFlow_ExecutePricing';
    private static final String CONTEXT_DEFINITION_NAME = 'STERIS_RepairCenterContext';
    private static final String CONTEXT_MAPPING_TITLE = 'STERIS_RepairCenterMapping';
    private static final String PRICING_PROCEDURE_NAME = 'STERIS_RepairCenterPricingProcedure';
    private static final String WORKSTREAM_REPAIR_CENTER = 'RepairCenter';
    private static final String STATUS_REPAIR = 'Repair';
    private static final String ESTIMATE_REQUIRED_VALUE = 'Estimate Required';
    private static final String ESTIMATE_ORDER_ACKNOWLEDGEMENT = 'Order Acknowledgement';

    /** When false in tests, the Execute Pricing flow is not started. */
    @TestVisible
    static Boolean executePricingInTests = false;

    /** Optional test override for Repair Code net total. */
    @TestVisible
    static Decimal testNetTotalOverride;

    /** Sequential test totals: original snapshot first, then post-pricing. */
    @TestVisible
    static List<Decimal> testNetTotalQueue;

    /** Last totals stamped onto evaluation context for the LWC header. */
    public static PricingTotals lastTotals;

    /**
     * Yellow warning for a Repair save that exceeds the active quote and Pre-Approval Limit.
     * Next still throws REQUOTE_BLOCKED_MESSAGE.
     */
    public static String lastRequoteWarning;

    /** Test ceiling for the parent Active Quote total. Null reads the quote. */
    @TestVisible
    static Decimal testQuoteNetTotalOverride;

    /**
     * @description Totals returned to evaluation workspaces after pricing.
     */
    public class PricingTotals {
        public Id workOrderId;
        public Decimal originalNetTotal;
        public Decimal newNetTotal;
    }

    /**
     * @description Repair + Estimate Required or Customer PO Required.
     * @param workOrder Work Order
     * @return True when the Repair requote gate applies
     */
    public static Boolean requiresRequoteGate(WorkOrder workOrder) {
        if (workOrder == null || workOrder.Status != STATUS_REPAIR) {
            return false;
        }
        return ESTIMATE_REQUIRED_VALUE.equals(workOrder.EstimateRequired__c) ||
            workOrder.CustomerPORequired__c == true;
    }

    /**
     * @description Whether Complete must run Execute Pricing before Status changes.
     *              Ready for Repair, Estimate Required, Order Acknowledgement, or a
     *              missing Customer PO.
     * @param workOrder Work Order being completed
     * @return True when pricing runs before the status update
     */
    public static Boolean shouldPriceBeforeStatusChange(WorkOrder workOrder) {
        if (workOrder == null) {
            return false;
        }
        Boolean estimateRequired = ESTIMATE_REQUIRED_VALUE.equals(workOrder.EstimateRequired__c);
        Boolean orderAcknowledgement = ESTIMATE_ORDER_ACKNOWLEDGEMENT.equals(
            workOrder.EstimateRequired__c
        );
        Boolean poRequired = workOrder.CustomerPORequired__c == true;
        Boolean poMissing = poRequired && String.isBlank(workOrder.CustomerPO__c);
        Boolean readyForRepair = !estimateRequired && !poRequired;
        return readyForRepair || estimateRequired || orderAcknowledgement || poMissing;
    }

    /**
     * @description Sum of Repair Code TotalPrice for the top-level order.
     * @param workOrder Work Order being saved
     * @return Sum, or 0 when none
     */
    public static Decimal sumRepairCodeNetTotal(WorkOrder workOrder) {
        if (testNetTotalQueue != null && !testNetTotalQueue.isEmpty()) {
            return testNetTotalQueue.remove(0);
        }
        if (testNetTotalOverride != null) {
            return testNetTotalOverride;
        }
        if (workOrder == null || workOrder.Id == null) {
            return 0;
        }
        Id repairCodeRtId = WorkOrderLineItemsService.getRepairCodeRecordTypeId();
        if (repairCodeRtId == null) {
            return 0;
        }
        Id topLevelId = workOrder.ParentWorkOrderId != null
            ? workOrder.ParentWorkOrderId
            : workOrder.Id;
        return WorkOrderLineItemsSelector.sumRepairCodeTotalPrice(workOrder.Id, topLevelId, repairCodeRtId);
    }

    /**
     * @description Runs Execute Pricing, measures new total, and enforces the requote gate.
     * @param workOrder Work Order after line DML
     * @param requoteGate True when Repair requote rules apply
     * @param originalTotal Snapshot taken before line DML
     * @return Original and new totals
     */
    public static PricingTotals priceAfterLineChanges(
        WorkOrder workOrder,
        Boolean requoteGate,
        Decimal originalTotal
    ) {
        return priceAfterLineChanges(workOrder, requoteGate, originalTotal, true);
    }

    /**
     * @description Runs Execute Pricing and applies the Repair requote gate.
     * @param workOrder Work Order after line DML
     * @param requoteGate True when Repair requote rules apply
     * @param originalTotal Snapshot taken before line DML
     * @param blockWhenExceeded True on Next. False shows a warning and keeps the save.
     * @return Original and new totals
     */
    public static PricingTotals priceAfterLineChanges(
        WorkOrder workOrder,
        Boolean requoteGate,
        Decimal originalTotal,
        Boolean blockWhenExceeded
    ) {
        lastRequoteWarning = null;
        executeRepairCenterPricing(workOrder);
        PricingTotals totals = new PricingTotals();
        totals.workOrderId = workOrder == null ? null : workOrder.Id;
        totals.originalNetTotal = originalTotal == null ? 0 : originalTotal;
        totals.newNetTotal = sumRepairCodeNetTotal(workOrder);
        if (requoteGate == true && repairCostExceedsApproval(workOrder, totals.newNetTotal)) {
            if (blockWhenExceeded == true) {
                throw new WorkOrdersService.WorkOrdersServiceException(REQUOTE_BLOCKED_MESSAGE);
            }
            lastRequoteWarning = REQUOTE_BLOCKED_MESSAGE;
        }
        lastTotals = totals;
        return totals;
    }

    /**
     * @description Blocks Next when the sibling net total exceeds the active quote
     *              and the Pre-Approval Limit.
     * @param workOrder Work Order
     * @param originalTotal Unused. Kept so existing callers stay source-compatible.
     * @param newTotal Sibling Service Code net total after pricing
     */
    public static void assertRequoteAllowed(
        WorkOrder workOrder,
        Decimal originalTotal,
        Decimal newTotal
    ) {
        if (originalTotal == null && newTotal == null) {
            return;
        }
        if (repairCostExceedsApproval(workOrder, newTotal)) {
            throw new WorkOrdersService.WorkOrdersServiceException(REQUOTE_BLOCKED_MESSAGE);
        }
    }

    /**
     * @description True when the sibling sum is above the active quote and is not
     *              covered by a non-zero Pre-Approval Limit.
     * @param workOrder Work Order
     * @param siblingSum Sum of child Work Order net totals
     * @return True when the repair cost is not approved
     */
    @TestVisible
    private static Boolean repairCostExceedsApproval(WorkOrder workOrder, Decimal siblingSum) {
        Decimal sumValue = siblingSum == null ? 0 : siblingSum;
        if (sumValue <= resolveActiveQuoteNetTotal(workOrder)) {
            return false;
        }
        Decimal preApprovalLimit = CustomerPreferencesService.getPreApprovalLimit(
            workOrder == null ? null : workOrder.AccountId,
            resolveProductLine(workOrder)
        );
        return preApprovalLimit == null || preApprovalLimit == 0 || sumValue > preApprovalLimit;
    }

    /**
     * @description Parent Active Quote total. Quote.NetTotalPrice__c is not in QA yet,
     *              so this uses GrandTotal, which is the quote total available there.
     * @param workOrder Child or standalone Work Order
     * @return Quote total, or 0 when there is no active quote
     */
    private static Decimal resolveActiveQuoteNetTotal(WorkOrder workOrder) {
        if (testQuoteNetTotalOverride != null) {
            return testQuoteNetTotalOverride;
        }
        if (workOrder == null || workOrder.Id == null) {
            return 0;
        }
        try {
            List<WorkOrder> rows = WorkOrdersSelector.selectActiveQuoteGrandTotalById(workOrder.Id);
            if (rows.isEmpty()) {
                return 0;
            }
            WorkOrder row = rows[0];
            Decimal quoteTotal = row.ParentWorkOrderId == null
                ? row.ActiveQuote__r.GrandTotal
                : row.ParentWorkOrder.ActiveQuote__r.GrandTotal;
            return quoteTotal == null ? 0 : quoteTotal;
        } catch (Exception e) {
            return 0;
        }
    }

    /**
     * @description Invokes Pricing SubFlow - Execute Pricing for a Repair Center Work Order.
     * @param workOrder Work Order whose WOLIs were just saved
     */
    public static void executeRepairCenterPricing(WorkOrder workOrder) {
        if (workOrder == null || workOrder.Id == null) {
            return;
        }

        List<WorkOrder> billingRows = [
            SELECT Id, AccountId, ShipToAddressAccount__c, BillToAddressAccount__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
            LIMIT 1
        ];
        if (billingRows.isEmpty()) {
            return;
        }
        WorkOrder billingWorkOrder = billingRows[0];
        Id shipToAccountId = billingWorkOrder.ShipToAddressAccount__c != null
            ? billingWorkOrder.ShipToAddressAccount__c
            : billingWorkOrder.AccountId;
        Id billToAccountId = billingWorkOrder.BillToAddressAccount__c != null
            ? billingWorkOrder.BillToAddressAccount__c
            : billingWorkOrder.AccountId;

        Id contextDefinitionId = queryFirstId(
            'SELECT Id FROM ContextDefinition WHERE DeveloperName = \'' +
                String.escapeSingleQuotes(CONTEXT_DEFINITION_NAME) +
                '\' LIMIT 1'
        );
        Id contextVersionId = contextDefinitionId == null
            ? null
            : queryFirstId(
                'SELECT Id FROM ContextDefinitionVersion WHERE ContextDefinitionId = \'' +
                    String.valueOf(contextDefinitionId) +
                    '\' AND IsActive = true LIMIT 1'
            );
        Id contextMappingId = contextVersionId == null
            ? null
            : queryFirstId(
                'SELECT Id FROM ContextMapping WHERE Title = \'' +
                    String.escapeSingleQuotes(CONTEXT_MAPPING_TITLE) +
                    '\' AND ContextDefinitionVersionId = \'' +
                    String.valueOf(contextVersionId) +
                    '\' LIMIT 1'
            );

        Map<String, Object> inputs = new Map<String, Object>{
            'varRecordId' => String.valueOf(workOrder.Id),
            'varAccountId' => shipToAccountId == null ? null : String.valueOf(shipToAccountId),
            'varBillToAccountId' => billToAccountId == null ? null : String.valueOf(billToAccountId),
            'varContextDefinitionId' => contextDefinitionId == null
                ? null
                : String.valueOf(contextDefinitionId),
            'varContextMappingId' => contextMappingId == null
                ? null
                : String.valueOf(contextMappingId),
            'varPricingProcedureId' => PRICING_PROCEDURE_NAME,
            'varWorkstream' => WORKSTREAM_REPAIR_CENTER
        };
        if (Test.isRunningTest() && executePricingInTests != true) {
            return;
        }
        Flow.Interview interview = Flow.Interview.createInterview(FLOW_API_NAME, inputs);
        interview.start();
        Object successValue = interview.getVariableValue('varIsSuccess');
        if (successValue == false) {
            Object errorMessage = interview.getVariableValue('varErrorMessage');
            String detail = errorMessage == null ? 'Oracle pricing failed.' : String.valueOf(errorMessage);
            throw new WorkOrdersService.WorkOrdersServiceException(detail);
        }
    }

    private static String resolveProductLine(WorkOrder workOrder) {
        if (workOrder == null) {
            return null;
        }
        if (workOrder.Asset != null && workOrder.Asset.Product2 != null) {
            return workOrder.Asset.Product2.ProductLine__c;
        }
        return workOrder.ProductLine_f__c;
    }

    private static Id queryFirstId(String soql) {
        try {
            List<SObject> rows = Database.query(soql);
            return rows.isEmpty() ? null : rows[0].Id;
        } catch (Exception e) {
            return null;
        }
    }
}