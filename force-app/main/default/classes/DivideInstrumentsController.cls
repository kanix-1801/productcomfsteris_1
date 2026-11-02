/**
 * @description Thin Aura controller for Divide Instruments (GW-2891).
 *              Business logic lives on WorkOrdersService.
 */
public with sharing class DivideInstrumentsController {
    /**
     * @description GW-2891 - Service client used so tests can override WorkOrdersService.
     */
    @TestVisible
    private interface IDivideInstrumentsClient {
        /**
         * @description GW-2891 - Starts Divide Instruments for a Work Order Id.
         * @param workOrderId Scanned Work Order Id
         * @return Divide Instruments context
         */
        WorkOrdersService.DivideInstrumentsContext initializeDivideInstruments(Id workOrderId);
        /**
         * @description GW-2891 - Reconciles child Work Orders for the bin rows.
         * @param workOrderId Parent Work Order Id
         * @param quantityReceived Quantity Received from the UI
         * @param bins Bin rows
         * @return Divide Instruments context
         */
        WorkOrdersService.DivideInstrumentsContext completeDivideInstruments(
            Id workOrderId,
            Decimal quantityReceived,
            List<WorkOrdersService.DivideInstrumentsBin> bins
        );
    }

    /**
     * @description GW-2891 - Default client that delegates to WorkOrdersService.
     */
    private class DefaultClient implements IDivideInstrumentsClient {
        /**
         * @description GW-2891 - Delegates initialize to WorkOrdersService.
         * @param workOrderId Scanned Work Order Id
         * @return Divide Instruments context
         */
        public WorkOrdersService.DivideInstrumentsContext initializeDivideInstruments(Id workOrderId) {
            return WorkOrdersService.initializeDivideInstruments(workOrderId);
        }

        /**
         * @description GW-2891 - Delegates complete to WorkOrdersService.
         * @param workOrderId Parent Work Order Id
         * @param quantityReceived Quantity Received from the UI
         * @param bins Bin rows
         * @return Divide Instruments context
         */
        public WorkOrdersService.DivideInstrumentsContext completeDivideInstruments(
            Id workOrderId,
            Decimal quantityReceived,
            List<WorkOrdersService.DivideInstrumentsBin> bins
        ) {
            return WorkOrdersService.completeDivideInstruments(workOrderId, quantityReceived, bins);
        }
    }

    /**
     * @description GW-2891 - Optional test override for the service client.
     */
    @TestVisible
    private static IDivideInstrumentsClient clientOverride;

    /**
     * @description GW-2891 - Returns the injected test client, or the default service client.
     * @return Service client
     */
    private static IDivideInstrumentsClient client() {
        return clientOverride == null ? new DefaultClient() : clientOverride;
    }

    /**
     * @description GW-2891 - Label/value pair for Repair Category picklist options.
     */
    public class PicklistOption {
        @AuraEnabled
        public String label { get; set; }
        @AuraEnabled
        public String value { get; set; }
    }

    /**
     * @description GW-2891 - One bin row from the Divide Instruments LWC.
     */
    public class BinDraft {
        @AuraEnabled
        public Id childWorkOrderId { get; set; }
        @AuraEnabled
        public String repairCategory { get; set; }
        @AuraEnabled
        public Decimal quantity { get; set; }
        @AuraEnabled
        public Decimal turnTime { get; set; }
    }

    /**
     * @description GW-2891 - Workspace DTO returned to the Divide Instruments LWC.
     */
    public class Workspace {
        @AuraEnabled
        public Id workOrderId { get; set; }
        @AuraEnabled
        public String workOrderNumber { get; set; }
        @AuraEnabled
        public String estimateRequired { get; set; }
        @AuraEnabled
        public Boolean customerPoRequired { get; set; }
        @AuraEnabled
        public String customerPo { get; set; }
        @AuraEnabled
        public String repairWarranty { get; set; }
        @AuraEnabled
        public Boolean continuousImprovementOpportunity { get; set; }
        @AuraEnabled
        public Decimal quantityReceived { get; set; }
        @AuraEnabled
        public Id instrumentsRecordTypeId { get; set; }
        @AuraEnabled
        public String labelsWarning { get; set; }
        @AuraEnabled
        public List<BinDraft> existingBins { get; set; }
    }

    /**
     * @description GW-2891 - Starts Divide Instruments for the scanned Work Order Id or Number.
     * @param workOrderInput Work Order Salesforce Id or WorkOrderNumber
     * @return Workspace DTO
     */
    @AuraEnabled
    public static Workspace initializeDivide(String workOrderInput) {
        try {
            return mapWorkspace(
                client().initializeDivideInstruments(resolveWorkOrderId(workOrderInput))
            );
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            throw PlatformUtilities.buildAuraException(e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('DivideInstrumentsController.initializeDivide: Unexpected error.', e);
            Logger.saveLog();
            throw PlatformUtilities.buildAuraException('Unable to start Divide Instruments.');
        }
    }

    /**
     * @description GW-2891 - Reconciles child Work Orders for the bin rows.
     * @param workOrderId Parent Work Order Id
     * @param quantityReceived Quantity Received from the UI
     * @param bins Bin drafts
     * @return Workspace DTO
     */
    @AuraEnabled
    public static Workspace completeDivide(
        Id workOrderId,
        Decimal quantityReceived,
        List<BinDraft> bins
    ) {
        try {
            List<WorkOrdersService.DivideInstrumentsBin> serviceBins =
                new List<WorkOrdersService.DivideInstrumentsBin>();
            if (bins != null) {
                for (BinDraft draft : bins) {
                    WorkOrdersService.DivideInstrumentsBin bin =
                        new WorkOrdersService.DivideInstrumentsBin();
                    if (draft != null) {
                        bin.childWorkOrderId = draft.childWorkOrderId;
                        bin.repairCategory = draft.repairCategory;
                        bin.quantity = draft.quantity;
                        bin.turnTime = draft.turnTime;
                    }
                    serviceBins.add(bin);
                }
            }
            return mapWorkspace(
                client().completeDivideInstruments(workOrderId, quantityReceived, serviceBins)
            );
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            throw PlatformUtilities.buildAuraException(e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('DivideInstrumentsController.completeDivide: Unexpected error.', e);
            Logger.saveLog();
            throw PlatformUtilities.buildAuraException('Unable to complete Divide Instruments.');
        }
    }

    /**
     * @description GW-2891 - Resolves a scanned Work Order Id or Number to a Salesforce Id.
     * @param workOrderInput Work Order Salesforce Id or WorkOrderNumber
     * @return Work Order Id
     */
    private static Id resolveWorkOrderId(String workOrderInput) {
        if (String.isBlank(workOrderInput)) {
            throw PlatformUtilities.buildAuraException('Work Order is required.');
        }
        String trimmedInput = workOrderInput.trim();
        WorkOrder workOrder = WorkOrdersSelector.selectByIdOrNumber(trimmedInput);
        if (workOrder == null) {
            throw PlatformUtilities.buildAuraException('Work Order "' + trimmedInput + '" was not found.');
        }
        return workOrder.Id;
    }

    /**
     * @description GW-2891 - Maps service context to the LWC workspace DTO.
     * @param context Divide Instruments service context
     * @return Workspace DTO
     */
    private static Workspace mapWorkspace(WorkOrdersService.DivideInstrumentsContext context) {
        Workspace workspace = new Workspace();
        WorkOrder workOrder = context.workOrder;
        workspace.workOrderId = workOrder.Id;
        workspace.workOrderNumber = workOrder.WorkOrderNumber;
        workspace.estimateRequired = workOrder.EstimateRequired__c;
        workspace.customerPoRequired = workOrder.CustomerPORequired__c == true;
        workspace.customerPo = workOrder.CustomerPO__c;
        workspace.repairWarranty = workOrder.RepairWarranty__c;
        workspace.continuousImprovementOpportunity =
            workOrder.ContinuousImprovementOpportunity__c == true;
        workspace.quantityReceived = workOrder.QuantityReceived__c;
        workspace.instrumentsRecordTypeId = context.instrumentsRecordTypeId;
        workspace.labelsWarning = context.labelsWarning;
        workspace.existingBins = mapBinDrafts(context.existingBins);
        return workspace;
    }

    /**
     * @description GW-2891 - Maps service bins to LWC bin drafts.
     * @param bins Service bin rows
     * @return Bin drafts for the LWC
     */
    private static List<BinDraft> mapBinDrafts(List<WorkOrdersService.DivideInstrumentsBin> bins) {
        List<BinDraft> drafts = new List<BinDraft>();
        if (bins == null) {
            return drafts;
        }
        for (WorkOrdersService.DivideInstrumentsBin bin : bins) {
            if (bin == null) {
                continue;
            }
            BinDraft draft = new BinDraft();
            draft.childWorkOrderId = bin.childWorkOrderId;
            draft.repairCategory = bin.repairCategory;
            draft.quantity = bin.quantity;
            draft.turnTime = bin.turnTime;
            drafts.add(draft);
        }
        return drafts;
    }

}