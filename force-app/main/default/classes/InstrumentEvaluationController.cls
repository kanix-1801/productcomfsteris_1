/**
 * @description Thin Aura controller for Instrument Evaluation (GW-3400).
 *              Business logic lives on WorkOrdersService.
 */
public with sharing class InstrumentEvaluationController {
    /**
     * @description GW-3400 - Service client used so tests can override WorkOrdersService.
     */
    @TestVisible
    private interface IInstrumentEvaluationClient {
        /**
         * @description GW-3400 - Initializes Instrument Evaluation for a scanned Work Order.
         * @param workOrderInput Work Order Salesforce Id or WorkOrderNumber
         * @return Instrument Evaluation context
         */
        WorkOrdersService.InstrumentEvaluationContext initializeInstrumentEvaluation(
            String workOrderInput
        );
        /**
         * @description GW-3400 - Persists header and notes fields for Instrument Evaluation.
         * @param workOrderId Parent Work Order Id
         * @param subStatus Sub Status value
         * @param unableToTakePhoto Unable To Take Photo checkbox
         * @param turnTime Turn Time
         * @param quantityReceived Quantity Received (required)
         * @param evaluationNotes Customer-facing evaluation notes
         * @param internalEvaluationNotes Internal evaluation notes
         * @param internalSpecialistEvaluationNotes Internal specialist notes
         * @return Instrument Evaluation context
         */
        WorkOrdersService.InstrumentEvaluationContext saveInstrumentEvaluationWorkOrderFields(
            Id workOrderId,
            String subStatus,
            Boolean unableToTakePhoto,
            Decimal turnTime,
            Decimal quantityReceived,
            String evaluationNotes,
            String internalEvaluationNotes,
            String internalSpecialistEvaluationNotes
        );
        /**
         * @description GW-3400 - Loads Eval Category cards for Item Selection.
         * @param workOrderId Parent Work Order Id
         * @return Eval Category cards
         */
        List<WorkOrdersService.InstrumentEvalCategoryCard> getInstrumentEvaluationEvalCategories(
            Id workOrderId
        );
        /**
         * @description GW-3400 - Loads products for a selected Eval Category.
         * @param workOrderId Parent Work Order Id
         * @param evalCategory Selected Eval Category
         * @return Product cards
         */
        List<WorkOrdersService.InstrumentProductCard> getInstrumentEvaluationProducts(
            Id workOrderId,
            String evalCategory
        );
        /**
         * @description GW-3400 - Loads category and service repair-code cards.
         * @param workOrderId Parent Work Order Id
         * @param productId Instrument Product2 Id, or null to use the Asset Product
         * @return Repair-code cards
         */
        ProductRelatedMaterialsService.InstrumentEvaluationCodeCards
            getInstrumentEvaluationRepairCodes(Id workOrderId, Id productId);
        /**
         * @description GW-3400 - Persists a Product Serviced item and repair-code children.
         * @param workOrderId Parent Work Order Id
         * @param productId Selected instrument Product2 Id
         * @param quantity Product Serviced quantity
         * @param repairCodeProductIds Selected repair-code Product Ids
         * @return Created Product Serviced Id
         */
        Id persistInstrumentEvaluationItem(
            Id workOrderId,
            Id productId,
            Decimal quantity,
            List<Id> repairCodeProductIds
        );
        /**
         * @description GW-3400 - Saves draft Instrument Evaluation items without completion status.
         * @param workOrderId Parent Work Order Id
         * @param draftItems Draft entries from the LWC
         * @return Created Product Serviced Ids
         */
        List<Id> saveInstrumentEvaluationDraft(
            Id workOrderId,
            List<WorkOrdersService.InstrumentEvaluationDraftItem> draftItems
        );
        /**
         * @description GW-3400 - Saves draft Instrument Evaluation items without completion status.
         * @param workOrderId Parent Work Order Id
         * @param draftItems Draft entries from the LWC
         * @param reconcileRemovedLines When true, deletes lines omitted from draftItems
         * @return Created Product Serviced Ids
         */
        List<Id> saveInstrumentEvaluationDraft(
            Id workOrderId,
            List<WorkOrdersService.InstrumentEvaluationDraftItem> draftItems,
            Boolean reconcileRemovedLines
        );
        /**
         * @description GW-3400 - Persists draft Instrument Evaluation items and links photos.
         * @param workOrderId Parent Work Order Id
         * @param draftItems Draft entries from the LWC
         * @return Created Product Serviced Ids
         */
        List<Id> completeInstrumentEvaluationDraft(
            Id workOrderId,
            List<WorkOrdersService.InstrumentEvaluationDraftItem> draftItems
        );
        /**
         * @description GW-3400 - Loads persisted Product Serviced items.
         * @param workOrderId Parent Work Order Id
         * @return Evaluation items
         */
        List<WorkOrdersService.InstrumentEvaluationItem> getInstrumentEvaluationItems(
            Id workOrderId
        );
        /**
         * @description GW-3400 - Returns the Work Order to evaluation (GW-3095 mapping).
         * @param workOrderId Parent Work Order Id
         */
        void returnWorkOrderToEvaluation(Id workOrderId);
    }

    /**
     * @description GW-3400 - Default client that delegates to WorkOrdersService.
     */
    private class DefaultClient implements IInstrumentEvaluationClient {
        /**
         * @description GW-3400 - Delegates initialize to WorkOrdersService.
         * @param workOrderInput Work Order Salesforce Id or WorkOrderNumber
         * @return Instrument Evaluation context
         */
        public WorkOrdersService.InstrumentEvaluationContext initializeInstrumentEvaluation(
            String workOrderInput
        ) {
            return WorkOrdersService.initializeInstrumentEvaluation(workOrderInput);
        }

        /**
         * @description GW-3400 - Delegates save to WorkOrdersService.
         * @param workOrderId Parent Work Order Id
         * @param subStatus Sub Status value
         * @param unableToTakePhoto Unable To Take Photo checkbox
         * @param turnTime Turn Time
         * @param quantityReceived Quantity Received (required)
         * @param evaluationNotes Customer-facing evaluation notes
         * @param internalEvaluationNotes Internal evaluation notes
         * @param internalSpecialistEvaluationNotes Internal specialist notes
         * @return Instrument Evaluation context
         */
        public WorkOrdersService.InstrumentEvaluationContext saveInstrumentEvaluationWorkOrderFields(
            Id workOrderId,
            String subStatus,
            Boolean unableToTakePhoto,
            Decimal turnTime,
            Decimal quantityReceived,
            String evaluationNotes,
            String internalEvaluationNotes,
            String internalSpecialistEvaluationNotes
        ) {
            return WorkOrdersService.saveInstrumentEvaluationWorkOrderFields(
                workOrderId,
                subStatus,
                unableToTakePhoto,
                turnTime,
                quantityReceived,
                evaluationNotes,
                internalEvaluationNotes,
                internalSpecialistEvaluationNotes
            );
        }

        /**
         * @description GW-3400 - Delegates Eval Category load to WorkOrdersService.
         * @param workOrderId Parent Work Order Id
         * @return Eval Category cards
         */
        public List<WorkOrdersService.InstrumentEvalCategoryCard> getInstrumentEvaluationEvalCategories(
            Id workOrderId
        ) {
            return WorkOrdersService.getInstrumentEvaluationEvalCategories(workOrderId);
        }

        /**
         * @description GW-3400 - Delegates product load to WorkOrdersService.
         * @param workOrderId Parent Work Order Id
         * @param evalCategory Selected Eval Category
         * @return Product cards
         */
        public List<WorkOrdersService.InstrumentProductCard> getInstrumentEvaluationProducts(
            Id workOrderId,
            String evalCategory
        ) {
            return WorkOrdersService.getInstrumentEvaluationProducts(workOrderId, evalCategory);
        }

        /**
         * @description GW-3400 - Delegates repair-code load to WorkOrdersService.
         * @param workOrderId Parent Work Order Id
         * @param productId Instrument Product2 Id, or null to use the Asset Product
         * @return Repair-code cards
         */
        public ProductRelatedMaterialsService.InstrumentEvaluationCodeCards
            getInstrumentEvaluationRepairCodes(Id workOrderId, Id productId) {
            return WorkOrdersService.getInstrumentEvaluationRepairCodes(workOrderId, productId);
        }

        /**
         * @description GW-3400 - Delegates item persist to WorkOrdersService.
         * @param workOrderId Parent Work Order Id
         * @param productId Selected instrument Product2 Id
         * @param quantity Product Serviced quantity
         * @param repairCodeProductIds Selected repair-code Product Ids
         * @return Created Product Serviced Id
         */
        public Id persistInstrumentEvaluationItem(
            Id workOrderId,
            Id productId,
            Decimal quantity,
            List<Id> repairCodeProductIds
        ) {
            return WorkOrdersService.persistInstrumentEvaluationItem(
                workOrderId,
                productId,
                quantity,
                repairCodeProductIds
            );
        }

        /**
         * @description GW-3400 - Delegates draft save to WorkOrdersService.
         * @param workOrderId Parent Work Order Id
         * @param draftItems Draft entries from the LWC
         * @return Created Product Serviced Ids
         */
        public List<Id> saveInstrumentEvaluationDraft(
            Id workOrderId,
            List<WorkOrdersService.InstrumentEvaluationDraftItem> draftItems
        ) {
            return WorkOrdersService.saveInstrumentEvaluationDraft(workOrderId, draftItems);
        }

        public List<Id> saveInstrumentEvaluationDraft(
            Id workOrderId,
            List<WorkOrdersService.InstrumentEvaluationDraftItem> draftItems,
            Boolean reconcileRemovedLines
        ) {
            return WorkOrdersService.saveInstrumentEvaluationDraft(
                workOrderId,
                draftItems,
                reconcileRemovedLines
            );
        }

        /**
         * @description GW-3400 - Delegates draft complete to WorkOrdersService.
         * @param workOrderId Parent Work Order Id
         * @param draftItems Draft entries from the LWC
         * @return Created Product Serviced Ids
         */
        public List<Id> completeInstrumentEvaluationDraft(
            Id workOrderId,
            List<WorkOrdersService.InstrumentEvaluationDraftItem> draftItems
        ) {
            return WorkOrdersService.completeInstrumentEvaluationDraft(workOrderId, draftItems);
        }

        /**
         * @description GW-3400 - Delegates item load to WorkOrdersService.
         * @param workOrderId Parent Work Order Id
         * @return Evaluation items
         */
        public List<WorkOrdersService.InstrumentEvaluationItem> getInstrumentEvaluationItems(
            Id workOrderId
        ) {
            return WorkOrdersService.getInstrumentEvaluationItems(workOrderId);
        }

        /**
         * @description GW-3400 - Delegates Return to Eval to WorkOrdersService (GW-3095).
         * @param workOrderId Parent Work Order Id
         */
        public void returnWorkOrderToEvaluation(Id workOrderId) {
            WorkOrdersService.returnWorkOrderToEvaluation(workOrderId);
        }
    }

    /**
     * @description GW-3400 - Optional test override for the service client.
     */
    @TestVisible
    private static IInstrumentEvaluationClient clientOverride;

    /**
     * @description GW-3400 - Returns the injected test client, or the default service client.
     * @return Service client
     */
    private static IInstrumentEvaluationClient client() {
        return clientOverride == null ? new DefaultClient() : clientOverride;
    }

    /**
     * @description GW-3400 - Customer preference row for the shared preferences table.
     */
    public class PreferenceRow {
        @AuraEnabled
        public Id preferenceId { get; set; }
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public String preferenceType { get; set; }
        @AuraEnabled
        public String productLine { get; set; }
        @AuraEnabled
        public Date startDate { get; set; }
        @AuraEnabled
        public Date endDate { get; set; }
    }

    /**
     * @description GW-3400 - Prior repair history row for the Asset Information tab.
     */
    public class RepairCodeLine {
        @AuraEnabled
        public String key { get; set; }
        @AuraEnabled
        public String label { get; set; }
    }

    public class RepairHistoryRow {
        @AuraEnabled
        public Id workOrderId { get; set; }
        @AuraEnabled
        public String workOrderNumber { get; set; }
        @AuraEnabled
        public Date actualShipDate { get; set; }
        @AuraEnabled
        public String evaluatorName { get; set; }
        @AuraEnabled
        public String recordUrl { get; set; }
        @AuraEnabled
        public String labName { get; set; }
        @AuraEnabled
        public String reportedProblem { get; set; }
        @AuraEnabled
        public Datetime repairDate { get; set; }
        @AuraEnabled
        public String evaluationNotes { get; set; }
        @AuraEnabled
        public String internalNotes { get; set; }
        @AuraEnabled
        public Boolean isWithinLastTwelveMonths { get; set; }
        @AuraEnabled
        public List<RepairCodeLine> repairCodeLines { get; set; }
    }

    /**
     * @description GW-3400 - Workspace DTO returned to the Instrument Evaluation LWC.
     */
    public class Workspace {
        @AuraEnabled
        public Id workOrderId { get; set; }
        @AuraEnabled
        public String workOrderNumber { get; set; }
        @AuraEnabled
        public String status { get; set; }
        @AuraEnabled
        public String subStatus { get; set; }
        @AuraEnabled
        public Boolean photosRequired { get; set; }
        @AuraEnabled
        public Boolean unableToTakePhoto { get; set; }
        @AuraEnabled
        public Decimal turnTime { get; set; }
        @AuraEnabled
        public String estimateRequired { get; set; }
        @AuraEnabled
        public String repairWarranty { get; set; }
        @AuraEnabled
        public Boolean continuousImprovementOpportunity { get; set; }
        @AuraEnabled
        public Boolean customerPoRequired { get; set; }
        @AuraEnabled
        public String customerPo { get; set; }
        /** GW-5696 - Customer requires ship complete. */
        @AuraEnabled
        public Boolean shipComplete { get; set; }
        @AuraEnabled
        public String evaluationNotes { get; set; }
        @AuraEnabled
        public String internalEvaluationNotes { get; set; }
        @AuraEnabled
        public String internalSpecialistEvaluationNotes { get; set; }
        /** GW-5453 - Read-only Quality Technician notes on Evaluation Notes tab. */
        @AuraEnabled
        public String qcInspectionNotes { get; set; }
        /** GW-5883 - Contamination locations shown when Sub Status is Contaminated. */
        @AuraEnabled
        public WorkOrdersService.ContaminationInformation contamination { get; set; }
        @AuraEnabled
        public Id assetId { get; set; }
        @AuraEnabled
        public String assetName { get; set; }
        @AuraEnabled
        public String serialNumber { get; set; }
        @AuraEnabled
        public Id productId { get; set; }
        @AuraEnabled
        public String productCode { get; set; }
        @AuraEnabled
        public String productName { get; set; }
        @AuraEnabled
        public String manufacturer { get; set; }
        @AuraEnabled
        public String model { get; set; }
        @AuraEnabled
        public String productLine { get; set; }
        @AuraEnabled
        public String assetIdentityLine { get; set; }
        @AuraEnabled
        public Boolean hasAsset { get; set; }
        @AuraEnabled
        public Boolean showItemSelection { get; set; }
        @AuraEnabled
        public Boolean canAddItems { get; set; }
        /** GW-3377 - Current Repair Cost (test header, Repair only). */
        @AuraEnabled
        public Decimal originalNetTotalPrice { get; set; }
        /** GW-3377 - Updated Repair Cost after pricing (test header, Repair only). */
        @AuraEnabled
        public Decimal newNetTotalPrice { get; set; }
        @AuraEnabled
        public String repairCategory { get; set; }
        @AuraEnabled
        public Decimal quantityReceived { get; set; }
        @AuraEnabled
        public Id returnOrderId { get; set; }
        @AuraEnabled
        public String subject { get; set; }
        @AuraEnabled
        public String description { get; set; }
        @AuraEnabled
        public List<PlatformUtilities.PicklistOption> subStatusOptions { get; set; }
        @AuraEnabled
        public List<PreferenceRow> customerPreferences { get; set; }
        @AuraEnabled
        public List<RepairHistoryRow> repairHistory { get; set; }
        @AuraEnabled
        public Boolean repairHistoryHasMore { get; set; }
    }

    /**
     * @description GW-3400 - Eval Category card DTO for the Item Selection wizard.
     */
    public class EvalCategoryCard {
        @AuraEnabled
        public String evalCategory { get; set; }
        @AuraEnabled
        public String evalRank { get; set; }
    }

    /**
     * @description GW-3400 - Product card DTO for the Item Selection wizard.
     */
    public class ProductCard {
        @AuraEnabled
        public Id productId { get; set; }
        @AuraEnabled
        public String productCode { get; set; }
        @AuraEnabled
        public String productName { get; set; }
        @AuraEnabled
        public String evalCategory { get; set; }
    }

    /**
     * @description GW-3400 - Repair-code card DTO for Instrument Evaluation.
     */
    public class RepairCodeCard {
        @AuraEnabled
        public Id productId { get; set; }
        @AuraEnabled
        public Id workOrderLineItemId { get; set; }
        @AuraEnabled
        public String status { get; set; }
        @AuraEnabled
        public String productCode { get; set; }
        @AuraEnabled
        public String productName { get; set; }
        @AuraEnabled
        public String codeType { get; set; }
        @AuraEnabled
        public Boolean selected { get; set; }
    }

    /**
     * @description GW-3400 - Repair signature row for Work Performed.
     */
    public class RepairSignatureRow {
        @AuraEnabled
        public Id id { get; set; }
        @AuraEnabled
        public Id workOrderLineItemId { get; set; }
        @AuraEnabled
        public Id productId { get; set; }
        @AuraEnabled
        public Id userId { get; set; }
        @AuraEnabled
        public String userName { get; set; }
    }

    /**
     * @description GW-3400 - Category and service repair-code lists.
     */
    public class RepairCodeWorkspace {
        @AuraEnabled
        public List<RepairCodeCard> categoryCodes { get; set; }
        @AuraEnabled
        public List<RepairCodeCard> serviceCodes { get; set; }
    }

    /**
     * @description GW-3377 - Draft save result including Repair Cost totals for the header.
     */
    public class DraftSaveResult {
        @AuraEnabled
        public List<Id> productServicedIds { get; set; }
        @AuraEnabled
        public Decimal originalNetTotalPrice { get; set; }
        @AuraEnabled
        public Decimal newNetTotalPrice { get; set; }
        /** GW-3377 - Yellow warning when a Repair save exceeds the approved cost. */
        @AuraEnabled
        public String requoteWarning { get; set; }
    }

    /**
     * @description GW-3400 - Draft item payload from the Instrument Evaluation LWC.
     */
    public class DraftItemInput {
        @AuraEnabled
        public Id productServicedId { get; set; }
        @AuraEnabled
        public Id productId { get; set; }
        @AuraEnabled
        public Decimal quantity { get; set; }
        @AuraEnabled
        public List<Id> returnOrderLineItemIds { get; set; }
        @AuraEnabled
        public List<Id> repairCodeProductIds { get; set; }
        @AuraEnabled
        public List<Id> contentDocumentIds { get; set; }
        @AuraEnabled
        public Boolean vendorProcessingRequired { get; set; }
        @AuraEnabled
        public Id vendorAccountId { get; set; }
        @AuraEnabled
        public String instructionsToVendor { get; set; }
        @AuraEnabled
        public String sterisPurchaseOrderToVendor { get; set; }
        @AuraEnabled
        public String vendorNotes { get; set; }
        @AuraEnabled
        public String vendorReferenceNumber { get; set; }
        @AuraEnabled
        public Decimal vendorCost { get; set; }
        @AuraEnabled
        public Date shippedToVendorDate { get; set; }
        @AuraEnabled
        public String trackingNumber { get; set; }
    }

    /**
     * @description GW-3400 - Persisted Product Serviced item DTO.
     */
    public class EvaluationItem {
        @AuraEnabled
        public Id productServicedId { get; set; }
        @AuraEnabled
        public String status { get; set; }
        @AuraEnabled
        public Id productId { get; set; }
        @AuraEnabled
        public String productCode { get; set; }
        @AuraEnabled
        public String productName { get; set; }
        @AuraEnabled
        public Decimal quantity { get; set; }
        @AuraEnabled
        public String returnOrderLineItems { get; set; }
        @AuraEnabled
        public Boolean vendorProcessingRequired { get; set; }
        @AuraEnabled
        public Id vendorAccountId { get; set; }
        @AuraEnabled
        public String instructionsToVendor { get; set; }
        @AuraEnabled
        public String sterisPurchaseOrderToVendor { get; set; }
        @AuraEnabled
        public String vendorNotes { get; set; }
        @AuraEnabled
        public String vendorReferenceNumber { get; set; }
        @AuraEnabled
        public Decimal vendorCost { get; set; }
        @AuraEnabled
        public Date shippedToVendorDate { get; set; }
        @AuraEnabled
        public String trackingNumber { get; set; }
        @AuraEnabled
        public Boolean vendorWorkOrderLocked { get; set; }
        @AuraEnabled
        public Id vendorWorkOrderId { get; set; }
        @AuraEnabled
        public List<RepairCodeCard> repairCodes { get; set; }
        @AuraEnabled
        public List<EvaluationPhoto> photos { get; set; }
    }

    /**
     * @description GW-5324 - One selectable Return Order Line Item.
     */
    public class ReturnOrderLineOption {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String lineItemNumber { get; set; }
        @AuraEnabled public String serialNumber { get; set; }
        @AuraEnabled public Id productId { get; set; }
        @AuraEnabled public String productName { get; set; }
        @AuraEnabled public String itemDescription { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public Boolean selected { get; set; }
    }

    /**
     * @description GW-5324 - Data displayed by the RO Line assignment modal.
     */
    public class ReturnOrderLineAssignment {
        @AuraEnabled public String returnOrderNumber { get; set; }
        @AuraEnabled public List<ReturnOrderLineOption> options { get; set; }
    }

    /**
     * @description GW-3400 - Photo already linked to a Product Serviced WOLI.
     */
    public class EvaluationPhoto {
        @AuraEnabled
        public Id contentDocumentId { get; set; }
        @AuraEnabled
        public String title { get; set; }
        @AuraEnabled
        public String thumbnailUrl { get; set; }
        @AuraEnabled
        public String imageDownloadUrl { get; set; }
        @AuraEnabled
        public String fileExtension { get; set; }
        @AuraEnabled
        public Boolean isImage { get; set; }
    }

    /**
     * @description GW-4616 - Billing address for a Vendor Account (Vendor popup / tab).
     * @param accountId Vendor Account Id
     * @return Address DTO
     */
    @AuraEnabled(cacheable=true)
    public static WorkOrdersService.VendorAddressResult getVendorAddress(Id accountId) {
        try {
            return WorkOrdersService.getVendorAddress(accountId);
        } catch (Exception e) {
            Logger.error('InstrumentEvaluationController.getVendorAddress failed', e);
            Logger.saveLog();
            throw buildAuraException('Unable to load vendor address.');
        }
    }

    /**
     * @description GW-3400 - Initializes Instrument Evaluation for a scanned Work Order.
     * @param workOrderInput Work Order Salesforce Id or WorkOrderNumber
     * @return Workspace DTO
     */
    @AuraEnabled
    public static Workspace initializeEvaluation(String workOrderInput) {
        try {
            if (String.isBlank(workOrderInput)) {
                throw buildAuraException('Work Order is required.');
            }
            return mapWorkspace(client().initializeInstrumentEvaluation(workOrderInput.trim()));
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            throw buildAuraException(e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('InstrumentEvaluationController.initializeEvaluation: Unexpected error.', e);
            Logger.saveLog();
            throw buildAuraException('Unable to start Instrument Evaluation.');
        }
    }

    /**
     * @description GW-3400 - Persists editable Instrument Evaluation header and notes fields.
     * @param workOrderId Parent Work Order Id
     * @param subStatus Sub Status value
     * @param unableToTakePhoto Unable To Take Photo checkbox
     * @param turnTime Turn Time
     * @param quantityReceived Quantity Received (required)
     * @param evaluationNotes Customer-facing evaluation notes
     * @param internalEvaluationNotes Internal evaluation notes
     * @param internalSpecialistEvaluationNotes Internal specialist notes
     * @param contaminationJson GW-5687 contamination locations JSON. Required when Sub Status is Contaminated.
     * @return Workspace DTO
     */
    @AuraEnabled
    public static Workspace saveWorkOrderFields(
        Id workOrderId,
        String subStatus,
        Boolean unableToTakePhoto,
        Decimal turnTime,
        Decimal quantityReceived,
        String evaluationNotes,
        String internalEvaluationNotes,
        String internalSpecialistEvaluationNotes,
        String contaminationJson
    ) {
        Savepoint savePoint = Database.setSavepoint();
        try {
            if (workOrderId == null) {
                throw buildAuraException('Work Order is required.');
            }
            WorkOrdersService.applyContaminationInformation(
                workOrderId,
                subStatus,
                WorkOrdersService.parseContaminationInformation(contaminationJson)
            );
            return mapWorkspace(
                client().saveInstrumentEvaluationWorkOrderFields(
                    workOrderId,
                    subStatus,
                    unableToTakePhoto,
                    turnTime,
                    quantityReceived,
                    evaluationNotes,
                    internalEvaluationNotes,
                    internalSpecialistEvaluationNotes
                )
            );
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            Database.rollback(savePoint);
            throw buildAuraException(e.getMessage());
        } catch (AuraHandledException e) {
            Database.rollback(savePoint);
            throw e;
        } catch (Exception e) {
            Database.rollback(savePoint);
            Logger.error('InstrumentEvaluationController.saveWorkOrderFields: Unexpected error.', e);
            Logger.saveLog();
            throw buildAuraException('Unable to save Instrument Evaluation.');
        }
    }

    /**
     * @description GW-3400 - Loads Eval Category cards for the Item Selection wizard.
     * @param workOrderId Parent Work Order Id
     * @return Eval Category cards
     */
    @AuraEnabled
    public static List<EvalCategoryCard> getEvalCategories(Id workOrderId) {
        try {
            if (workOrderId == null) {
                throw buildAuraException('Work Order is required.');
            }
            return mapEvalCategoryCards(client().getInstrumentEvaluationEvalCategories(workOrderId));
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            throw buildAuraException(e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('InstrumentEvaluationController.getEvalCategories: Unexpected error.', e);
            Logger.saveLog();
            throw buildAuraException('Unable to load evaluation categories.');
        }
    }

    /**
     * @description GW-3400 - Loads products for a selected Eval Category.
     * @param workOrderId Parent Work Order Id
     * @param evalCategory Selected Eval Category
     * @return Product cards
     */
    @AuraEnabled
    public static List<ProductCard> getProductsForEvalCategory(Id workOrderId, String evalCategory) {
        try {
            if (workOrderId == null) {
                throw buildAuraException('Work Order is required.');
            }
            if (String.isBlank(evalCategory)) {
                throw buildAuraException('Eval Category is required.');
            }
            return mapProductCards(
                client().getInstrumentEvaluationProducts(workOrderId, evalCategory)
            );
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            throw buildAuraException(e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Logger.error(
                'InstrumentEvaluationController.getProductsForEvalCategory: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw buildAuraException('Unable to load evaluation products.');
        }
    }

    /**
     * @description GW-3400 - Loads category and service repair-code cards for a product or Asset.
     * @param workOrderId Parent Work Order Id
     * @param productId Instrument Product2 Id; null uses the Asset Product
     * @return Repair-code workspace
     */
    @AuraEnabled
    public static RepairCodeWorkspace getRepairCodesForProduct(Id workOrderId, Id productId) {
        try {
            if (workOrderId == null) {
                throw buildAuraException('Work Order is required.');
            }
            return mapRepairCodeWorkspace(
                client().getInstrumentEvaluationRepairCodes(workOrderId, productId)
            );
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            throw buildAuraException(e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Logger.error(
                'InstrumentEvaluationController.getRepairCodesForProduct: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw buildAuraException('Unable to load repair codes.');
        }
    }

    /**
     * @description GW-3400 - Saves draft Instrument Evaluation items and links staged photos
     *              without applying Complete Status / Sub Status. Used by Quick Save / Save & Close.
     *              When productServicedId is set, syncs quantity and adds missing repair codes.
     * @param workOrderId Parent Work Order Id
     * @param draftItems Draft entries (item + codes + staged photo document Ids)
     * @return Created or updated Product Serviced Ids and Repair Cost totals
     */
    @AuraEnabled
    public static DraftSaveResult saveDraftItems(
        Id workOrderId,
        List<DraftItemInput> draftItems,
        Boolean reconcileRemovedLines
    ) {
        try {
            if (workOrderId == null) {
                throw buildAuraException('Work Order is required.');
            }
            return toDraftSaveResult(
                client().saveInstrumentEvaluationDraft(
                    workOrderId,
                    mapDraftItemInputs(draftItems),
                    reconcileRemovedLines == true
                )
            );
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            throw buildAuraException(e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('InstrumentEvaluationController.saveDraftItems: Unexpected error.', e);
            Logger.saveLog();
            throw buildAuraException('Unable to save Instrument Evaluation items.');
        }
    }

    /**
     * @description GW-3400 - Persists draft Instrument Evaluation items and links staged photos
     *              to Product Serviced WOLIs, then applies Complete Status / Sub Status.
     * @param workOrderId Parent Work Order Id
     * @param draftItems Draft entries (item + codes + staged photo document Ids)
     * @return Created Product Serviced Ids
     */
    @AuraEnabled
    public static List<Id> completeDraftItems(Id workOrderId, List<DraftItemInput> draftItems) {
        try {
            if (workOrderId == null) {
                throw buildAuraException('Work Order is required.');
            }
            return client().completeInstrumentEvaluationDraft(
                workOrderId,
                mapDraftItemInputs(draftItems)
            );
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            throw buildAuraException(e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('InstrumentEvaluationController.completeDraftItems: Unexpected error.', e);
            Logger.saveLog();
            throw buildAuraException('Unable to complete Instrument Evaluation items.');
        }
    }

    /**
     * @description GW-3377 - Execute Pricing after draft DML has committed, then optionally Complete.
     */
    @AuraEnabled
    public static DraftSaveResult finalizeInstrumentEvaluationAfterPricing(
        Id workOrderId,
        Decimal originalNetTotal,
        Boolean applyCompletion
    ) {
        try {
            if (workOrderId == null) {
                throw buildAuraException('Work Order is required.');
            }
            WorkOrdersService.finalizeInstrumentEvaluationAfterPricing(
                workOrderId,
                originalNetTotal,
                applyCompletion == true
            );
            return toDraftSaveResult(new List<Id>());
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            throw buildAuraException(e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Logger.error(
                'InstrumentEvaluationController.finalizeInstrumentEvaluationAfterPricing failed',
                e
            );
            Logger.saveLog();
            throw buildAuraException('Unable to price Instrument Evaluation.');
        }
    }

    /**
     * @description GW-3377 - Copies Execute Pricing totals onto the draft save DTO.
     * @param productServicedIds Persisted Product Serviced Ids
     * @return Draft save result for the LWC
     */
    private static DraftSaveResult toDraftSaveResult(List<Id> productServicedIds) {
        DraftSaveResult result = new DraftSaveResult();
        result.productServicedIds =
            productServicedIds == null ? new List<Id>() : productServicedIds;
        WorkOrderRepairPricingService.PricingTotals totals =
            WorkOrderRepairPricingService.lastTotals;
        if (totals != null) {
            result.originalNetTotalPrice = totals.originalNetTotal;
            result.newNetTotalPrice = totals.newNetTotal;
        }
        result.requoteWarning = WorkOrderRepairPricingService.lastRequoteWarning;
        WorkOrderRepairPricingService.lastRequoteWarning = null;
        return result;
    }

    /**
     * @description Maps LWC draft payloads to WorkOrdersService draft items.
     * @param draftItems Aura draft inputs
     * @return Service draft items
     */
    private static List<WorkOrdersService.InstrumentEvaluationDraftItem> mapDraftItemInputs(
        List<DraftItemInput> draftItems
    ) {
        List<WorkOrdersService.InstrumentEvaluationDraftItem> serviceItems =
            new List<WorkOrdersService.InstrumentEvaluationDraftItem>();
        if (draftItems == null) {
            return serviceItems;
        }
        for (DraftItemInput draftItem : draftItems) {
            if (draftItem == null) {
                continue;
            }
            WorkOrdersService.InstrumentEvaluationDraftItem serviceItem =
                new WorkOrdersService.InstrumentEvaluationDraftItem();
            serviceItem.productServicedId = draftItem.productServicedId;
            serviceItem.productId = draftItem.productId;
            serviceItem.quantity = draftItem.quantity;
            serviceItem.returnOrderLineItemIds = draftItem.returnOrderLineItemIds;
            serviceItem.repairCodeProductIds = draftItem.repairCodeProductIds;
            serviceItem.contentDocumentIds = draftItem.contentDocumentIds;
            serviceItem.vendorProcessingRequired = draftItem.vendorProcessingRequired;
            serviceItem.vendorAccountId = draftItem.vendorAccountId;
            serviceItem.instructionsToVendor = draftItem.instructionsToVendor;
            serviceItem.sterisPurchaseOrderToVendor = draftItem.sterisPurchaseOrderToVendor;
            serviceItem.vendorNotes = draftItem.vendorNotes;
            serviceItem.vendorReferenceNumber = draftItem.vendorReferenceNumber;
            serviceItem.vendorCost = draftItem.vendorCost;
            serviceItem.shippedToVendorDate = draftItem.shippedToVendorDate;
            serviceItem.trackingNumber = draftItem.trackingNumber;
            serviceItems.add(serviceItem);
        }
        return serviceItems;
    }

    /**
     * @description GW-3400 - Persists a Product Serviced item and selected repair codes.
     * @param workOrderId Parent Work Order Id
     * @param productId Selected instrument Product2 Id
     * @param quantity Product Serviced quantity
     * @param repairCodeProductIds Selected repair-code Product Ids
     * @return Created Product Serviced Id
     */
    @AuraEnabled
    public static Id saveProductServicedItem(
        Id workOrderId,
        Id productId,
        Decimal quantity,
        List<Id> repairCodeProductIds
    ) {
        try {
            if (workOrderId == null) {
                throw buildAuraException('Work Order is required.');
            }
            if (productId == null) {
                throw buildAuraException('Product is required.');
            }
            return client().persistInstrumentEvaluationItem(
                workOrderId,
                productId,
                quantity,
                repairCodeProductIds
            );
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            throw buildAuraException(e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Logger.error(
                'InstrumentEvaluationController.saveProductServicedItem: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw buildAuraException('Unable to save the evaluation item.');
        }
    }

    /**
     * @description GW-3400 - Loads persisted Product Serviced items for the Work Order.
     * @param workOrderId Parent Work Order Id
     * @return Evaluation items
     */
    @AuraEnabled
    public static List<EvaluationItem> getEvaluationItems(Id workOrderId) {
        try {
            if (workOrderId == null) {
                throw buildAuraException('Work Order is required.');
            }
            return mapEvaluationItems(client().getInstrumentEvaluationItems(workOrderId));
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            throw buildAuraException(e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('InstrumentEvaluationController.getEvaluationItems: Unexpected error.', e);
            Logger.saveLog();
            throw buildAuraException('Unable to load evaluation items.');
        }
    }

    /**
     * @description GW-5324 - Loads RO Lines and auto/saved selections for one summary item.
     * @param workOrderId Instrument Work Order Id
     * @param productServicedId Product Serviced WorkOrderLineItem Id
     * @return Return Order Line assignment modal data
     */
    @AuraEnabled
    public static ReturnOrderLineAssignment getReturnOrderLineAssignment(
        Id workOrderId,
        Id productServicedId
    ) {
        try {
            if (workOrderId == null || productServicedId == null) {
                throw buildAuraException('Work Order and Product Serviced item are required.');
            }
            return mapReturnOrderLineAssignment(
                WorkOrdersService.getInstrumentReturnOrderLineAssignment(
                    workOrderId,
                    productServicedId
                )
            );
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            throw buildAuraException(e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Logger.error(
                'InstrumentEvaluationController.getReturnOrderLineAssignment: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw buildAuraException('Unable to load Return Order Line Items.');
        }
    }

    /**
     * @description GW-3400 - Removes a photo linked to a Product Serviced evaluation item.
     * @param workOrderId Parent Work Order Id
     * @param productServicedId Product Serviced WOLI Id
     * @param contentDocumentId ContentDocument Id
     */
    @AuraEnabled
    public static void removeEvaluationPhoto(
        Id workOrderId,
        Id productServicedId,
        Id contentDocumentId
    ) {
        try {
            if (workOrderId == null || productServicedId == null || contentDocumentId == null) {
                throw buildAuraException('Work Order, item, and photo are required.');
            }
            WorkOrderLineItem line = WorkOrderLineItemsService.getLineItemByIdAndWorkOrderId(
                productServicedId,
                workOrderId
            );
            if (line == null) {
                throw buildAuraException(
                    'The evaluation item was not found on this Work Order.'
                );
            }
            ContentDocumentLinksService.removeDocumentFromLinkedEntity(
                productServicedId,
                contentDocumentId
            );
        } catch (ContentDocumentLinksService.ContentDocumentLinksServiceException e) {
            throw buildAuraException(e.getMessage());
        } catch (ContentDocumentsService.ContentDocumentsServiceException e) {
            throw buildAuraException(e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Logger.error(
                'InstrumentEvaluationController.removeEvaluationPhoto: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw buildAuraException('Unable to remove the photo.');
        }
    }

    /**
     * @description GW-3400 - Loads Work Performed signatures for the Work Order.
     * @param workOrderId Work Order Id
     * @return Signature rows
     */
    @AuraEnabled
    public static List<RepairSignatureRow> getRepairSignatures(Id workOrderId) {
        try {
            if (workOrderId == null) {
                throw buildAuraException('Work Order is required.');
            }
            return mapRepairSignatures(
                RepairCenterTeamMembersService.getWorkOrderLineSignatures(workOrderId)
            );
        } catch (RepairCenterTeamMembersService.RepairCenterTeamMembersServiceException e) {
            throw buildAuraException(e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('InstrumentEvaluationController.getRepairSignatures: Unexpected error.', e);
            Logger.saveLog();
            throw buildAuraException('Unable to load repair signatures.');
        }
    }

    /**
     * @description GW-3400 - Signs a Repair Code WOLI as the current user.
     * @param workOrderId Work Order Id
     * @param workOrderLineItemId Repair Code WOLI Id
     * @return Updated signature rows
     */
    @AuraEnabled
    public static List<RepairSignatureRow> addRepairSignature(
        Id workOrderId,
        Id workOrderLineItemId
    ) {
        try {
            return mapRepairSignatures(
                RepairCenterTeamMembersService.addSignatureForLineItem(
                    workOrderId,
                    workOrderLineItemId
                )
            );
        } catch (RepairCenterTeamMembersService.RepairCenterTeamMembersServiceException e) {
            throw buildAuraException(e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('InstrumentEvaluationController.addRepairSignature: Unexpected error.', e);
            Logger.saveLog();
            throw buildAuraException('Unable to sign the repair code.');
        }
    }

    /**
     * @description GW-3400 - Signs all supplied Repair Code WOLIs as the current user.
     * @param workOrderId Work Order Id
     * @param workOrderLineItemIds Repair Code WOLI Ids
     * @return Updated signature rows
     */
    @AuraEnabled
    public static List<RepairSignatureRow> signAllRepairCodes(
        Id workOrderId,
        List<Id> workOrderLineItemIds
    ) {
        try {
            return mapRepairSignatures(
                RepairCenterTeamMembersService.signAllForLineItems(
                    workOrderId,
                    workOrderLineItemIds
                )
            );
        } catch (RepairCenterTeamMembersService.RepairCenterTeamMembersServiceException e) {
            throw buildAuraException(e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('InstrumentEvaluationController.signAllRepairCodes: Unexpected error.', e);
            Logger.saveLog();
            throw buildAuraException('Unable to sign repair codes.');
        }
    }

    /**
     * @description GW-3400 - Removes a Work Performed signature.
     * @param workOrderId Work Order Id
     * @param signatureId Team Member Id
     * @return Updated signature rows
     */
    @AuraEnabled
    public static List<RepairSignatureRow> removeRepairSignature(
        Id workOrderId,
        Id signatureId
    ) {
        try {
            return mapRepairSignatures(
                RepairCenterTeamMembersService.removeSignature(workOrderId, signatureId)
            );
        } catch (RepairCenterTeamMembersService.RepairCenterTeamMembersServiceException e) {
            throw buildAuraException(e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Logger.error(
                'InstrumentEvaluationController.removeRepairSignature: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw buildAuraException('Unable to remove the signature.');
        }
    }

    /**
     * @description GW-3400 - Returns Instruments Work Orders to Status = Evaluate & Quote
     *              with blank Sub Status. LWC saves pending changes before calling this.
     * @param workOrderId Parent Work Order Id
     */
    @AuraEnabled
    public static void returnToEvaluation(Id workOrderId) {
        try {
            if (workOrderId == null) {
                throw buildAuraException('Work Order is required.');
            }
            client().returnWorkOrderToEvaluation(workOrderId);
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            throw buildAuraException(e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('InstrumentEvaluationController.returnToEvaluation: Unexpected error.', e);
            Logger.saveLog();
            throw buildAuraException('Unable to return Work Order to evaluation.');
        }
    }

    /**
     * @description GW-3400 - Maps service context to the LWC workspace DTO.
     * @param context Instrument Evaluation service context
     * @return Workspace DTO
     */
    private static Workspace mapWorkspace(WorkOrdersService.InstrumentEvaluationContext context) {
        Workspace workspace = new Workspace();
        if (context == null || context.workOrder == null) {
            return workspace;
        }
        WorkOrder workOrder = context.workOrder;
        workspace.workOrderId = workOrder.Id;
        workspace.workOrderNumber = workOrder.WorkOrderNumber;
        workspace.status = workOrder.Status;
        workspace.subStatus = workOrder.SubStatus__c;
        workspace.photosRequired = context.photosRequired == true;
        workspace.unableToTakePhoto = workOrder.UnableToTakePhoto__c == true;
        workspace.turnTime = workOrder.TurnTime__c;
        workspace.estimateRequired = workOrder.EstimateRequired__c;
        workspace.repairWarranty = workOrder.RepairWarranty__c;
        workspace.continuousImprovementOpportunity =
            workOrder.ContinuousImprovementOpportunity__c == true;
        workspace.customerPoRequired = workOrder.CustomerPORequired__c == true;
        workspace.customerPo = workOrder.CustomerPO__c;
        workspace.shipComplete = workOrder.ShipComplete__c == true;
        workspace.evaluationNotes = workOrder.EvaluationNotes__c;
        workspace.internalEvaluationNotes = workOrder.InternalEvaluationNotes__c;
        workspace.internalSpecialistEvaluationNotes = workOrder.InternalSpecialistEvaluationNotes__c;
        workspace.qcInspectionNotes = workOrder.QCInspectionNotes__c;
        workspace.contamination = WorkOrdersService.toContaminationInformation(workOrder);
        workspace.assetId = workOrder.AssetId;
        workspace.assetName = workOrder.Asset != null ? workOrder.Asset.Name : null;
        workspace.serialNumber = context.serialNumber;
        workspace.productId = workOrder.Asset != null ? workOrder.Asset.Product2Id : null;
        workspace.productCode =
            workOrder.Asset != null && workOrder.Asset.Product2 != null
                ? workOrder.Asset.Product2.ProductCode
                : null;
        workspace.productName =
            workOrder.Asset != null && workOrder.Asset.Product2 != null
                ? workOrder.Asset.Product2.Name
                : null;
        workspace.manufacturer = context.manufacturer;
        workspace.model = context.model;
        workspace.productLine = context.productLine;
        workspace.assetIdentityLine = context.assetIdentityLine;
        workspace.hasAsset = context.hasAsset == true;
        workspace.showItemSelection = context.showItemSelection == true;
        workspace.canAddItems = context.canAddItems == true;
        workspace.originalNetTotalPrice = context.originalNetTotalPrice;
        workspace.newNetTotalPrice = context.newNetTotalPrice;
        workspace.repairCategory = workOrder.RepairCategory__c;
        workspace.quantityReceived = workOrder.QuantityReceived__c;
        workspace.returnOrderId =
            workOrder.ReturnOrder__c != null ? workOrder.ReturnOrder__c : workOrder.ReturnOrderId;
        workspace.subject = workOrder.Subject;
        workspace.description = workOrder.Description;
        workspace.subStatusOptions = getSubStatusOptions(workOrder.Status, workOrder.SubStatus__c);
        workspace.customerPreferences = mapPreferenceRows(context.customerPreferences);
        workspace.repairHistory = mapRepairHistoryRows(context.repairHistory);
        workspace.repairHistoryHasMore = context.repairHistoryHasMore == true;
        return workspace;
    }

    /**
     * @description GW-3400 - Maps preference records to LWC table rows.
     * @param preferences Active IMS customer preferences
     * @return Preference rows
     */
    private static List<PreferenceRow> mapPreferenceRows(List<CustomerPreference__c> preferences) {
        List<PreferenceRow> rows = new List<PreferenceRow>();
        if (preferences == null || preferences.isEmpty()) {
            return rows;
        }
        for (CustomerPreference__c preference : preferences) {
            PreferenceRow row = new PreferenceRow();
            row.preferenceId = preference.Id;
            row.name = preference.Name;
            row.preferenceType = preference.PreferenceType__c;
            row.productLine = preference.ProductLine__c;
            row.startDate = preference.StartDate__c;
            row.endDate = preference.EndDate__c;
            rows.add(row);
        }
        return rows;
    }

    /**
     * @description GW-3400 - Maps repair history Work Orders to LWC table rows.
     * @param history Prior shipped Work Orders for the same Account and Asset
     * @return Repair history rows
     */
    private static List<RepairHistoryRow> mapRepairHistoryRows(List<WorkOrder> history) {
        List<RepairHistoryRow> rows = new List<RepairHistoryRow>();
        if (history == null || history.isEmpty()) {
            return rows;
        }
        Datetime cutoff = Datetime.now().addMonths(-12);
        for (WorkOrder historyWorkOrder : history) {
            RepairHistoryRow row = new RepairHistoryRow();
            row.workOrderId = historyWorkOrder.Id;
            row.workOrderNumber = historyWorkOrder.WorkOrderNumber;
            row.actualShipDate = historyWorkOrder.ActualShipDate__c;
            row.evaluatorName =
                historyWorkOrder.Evaluator__r != null ? historyWorkOrder.Evaluator__r.Name : null;
            row.recordUrl = '/' + historyWorkOrder.Id;
            row.labName =
                historyWorkOrder.RepairCenter__r != null
                    ? historyWorkOrder.RepairCenter__r.Name
                    : null;
            row.reportedProblem = historyWorkOrder.Description;
            row.repairDate = historyWorkOrder.CompletedTimestamp__c;
            row.evaluationNotes = historyWorkOrder.EvaluationNotes__c;
            row.internalNotes = historyWorkOrder.InternalEvaluationNotes__c;
            row.isWithinLastTwelveMonths =
                historyWorkOrder.CompletedTimestamp__c != null &&
                historyWorkOrder.CompletedTimestamp__c >= cutoff;
            row.repairCodeLines = mapRepairCodeLines(historyWorkOrder);
            rows.add(row);
        }
        return rows;
    }

    private static List<RepairCodeLine> mapRepairCodeLines(WorkOrder historyWorkOrder) {
        List<RepairCodeLine> codes = new List<RepairCodeLine>();
        if (historyWorkOrder == null || historyWorkOrder.WorkOrderLineItems == null) {
            return codes;
        }
        Integer index = 0;
        for (WorkOrderLineItem lineItem : historyWorkOrder.WorkOrderLineItems) {
            String productCode =
                lineItem.Product2 != null ? lineItem.Product2.ProductCode : null;
            String productName = lineItem.Product2 != null ? lineItem.Product2.Name : null;
            String label;
            if (String.isNotBlank(productCode) && String.isNotBlank(productName)) {
                label = productCode + ': ' + productName;
            } else if (String.isNotBlank(productName)) {
                label = productName;
            } else {
                label = productCode;
            }
            if (String.isBlank(label)) {
                continue;
            }
            RepairCodeLine code = new RepairCodeLine();
            code.key = String.valueOf(historyWorkOrder.Id) + '-' + String.valueOf(index);
            code.label = label;
            codes.add(code);
            index++;
        }
        return codes;
    }

    /**
     * @description GW-3400 - Maps Eval Category domain cards to Aura DTOs.
     * @param cards Service Eval Category cards
     * @return Aura Eval Category cards
     */
    private static List<EvalCategoryCard> mapEvalCategoryCards(
        List<WorkOrdersService.InstrumentEvalCategoryCard> cards
    ) {
        List<EvalCategoryCard> mapped = new List<EvalCategoryCard>();
        if (cards == null) {
            return mapped;
        }
        for (WorkOrdersService.InstrumentEvalCategoryCard card : cards) {
            EvalCategoryCard dto = new EvalCategoryCard();
            dto.evalCategory = card.evalCategory;
            dto.evalRank = card.evalRank;
            mapped.add(dto);
        }
        return mapped;
    }

    /**
     * @description GW-3400 - Maps product domain cards to Aura DTOs.
     * @param cards Service product cards
     * @return Aura product cards
     */
    private static List<ProductCard> mapProductCards(
        List<WorkOrdersService.InstrumentProductCard> cards
    ) {
        List<ProductCard> mapped = new List<ProductCard>();
        if (cards == null) {
            return mapped;
        }
        for (WorkOrdersService.InstrumentProductCard card : cards) {
            ProductCard dto = new ProductCard();
            dto.productId = card.productId;
            dto.productCode = card.productCode;
            dto.productName = card.productName;
            dto.evalCategory = card.evalCategory;
            mapped.add(dto);
        }
        return mapped;
    }

    /**
     * @description GW-3400 - Maps repair-code cards to the Aura workspace DTO.
     * @param cards Service code cards
     * @return Aura repair-code workspace
     */
    private static RepairCodeWorkspace mapRepairCodeWorkspace(
        ProductRelatedMaterialsService.InstrumentEvaluationCodeCards cards
    ) {
        RepairCodeWorkspace workspace = new RepairCodeWorkspace();
        workspace.categoryCodes = new List<RepairCodeCard>();
        workspace.serviceCodes = new List<RepairCodeCard>();
        if (cards == null) {
            return workspace;
        }
        workspace.categoryCodes = mapRepairCodeCards(cards.categoryCodes);
        workspace.serviceCodes = mapRepairCodeCards(cards.serviceCodes);
        return workspace;
    }

    /**
     * @description GW-3400 - Maps persisted evaluation items to Aura DTOs.
     * @param items Service evaluation items
     * @return Aura evaluation items
     */
    private static List<EvaluationItem> mapEvaluationItems(
        List<WorkOrdersService.InstrumentEvaluationItem> items
    ) {
        List<EvaluationItem> mapped = new List<EvaluationItem>();
        if (items == null) {
            return mapped;
        }
        for (WorkOrdersService.InstrumentEvaluationItem item : items) {
            EvaluationItem dto = new EvaluationItem();
            dto.productServicedId = item.productServicedId;
            dto.status = item.status;
            dto.productId = item.productId;
            dto.productCode = item.productCode;
            dto.productName = item.productName;
            dto.quantity = item.quantity;
            dto.returnOrderLineItems = item.returnOrderLineItems;
            dto.vendorProcessingRequired = item.vendorProcessingRequired == true;
            dto.vendorAccountId = item.vendorAccountId;
            dto.instructionsToVendor = item.instructionsToVendor;
            dto.sterisPurchaseOrderToVendor = item.sterisPurchaseOrderToVendor;
            dto.vendorNotes = item.vendorNotes;
            dto.vendorReferenceNumber = item.vendorReferenceNumber;
            dto.vendorCost = item.vendorCost;
            dto.shippedToVendorDate = item.shippedToVendorDate;
            dto.trackingNumber = item.trackingNumber;
            dto.vendorWorkOrderLocked = item.vendorWorkOrderLocked == true;
            dto.vendorWorkOrderId = item.vendorWorkOrderId;
            dto.repairCodes = mapRepairCodeCards(item.repairCodes);
            dto.photos = mapEvaluationPhotos(item.photos);
            mapped.add(dto);
        }
        return mapped;
    }

    @TestVisible
    private static ReturnOrderLineAssignment mapReturnOrderLineAssignment(
        WorkOrdersService.InstrumentReturnOrderLineAssignment source
    ) {
        ReturnOrderLineAssignment assignment = new ReturnOrderLineAssignment();
        assignment.options = new List<ReturnOrderLineOption>();
        if (source == null) {
            return assignment;
        }
        assignment.returnOrderNumber = source.returnOrderNumber;
        List<WorkOrdersService.InstrumentReturnOrderLineOption> sourceOptions =
            source.options == null
                ? new List<WorkOrdersService.InstrumentReturnOrderLineOption>()
                : source.options;
        for (WorkOrdersService.InstrumentReturnOrderLineOption sourceOption : sourceOptions) {
            ReturnOrderLineOption option = new ReturnOrderLineOption();
            option.id = sourceOption.id;
            option.lineItemNumber = sourceOption.lineItemNumber;
            option.serialNumber = sourceOption.serialNumber;
            option.productId = sourceOption.productId;
            option.productName = sourceOption.productName;
            option.itemDescription = sourceOption.itemDescription;
            option.model = sourceOption.model;
            option.quantity = sourceOption.quantity;
            option.selected = sourceOption.selected == true;
            assignment.options.add(option);
        }
        return assignment;
    }

    /**
     * @description GW-3400 - Maps linked file rows to Aura photo DTOs.
     * @param files Service file rows
     * @return Aura photo DTOs
     */
    private static List<EvaluationPhoto> mapEvaluationPhotos(
        List<ContentDocumentLinksService.DeviceEvaluationFileData> files
    ) {
        List<EvaluationPhoto> mapped = new List<EvaluationPhoto>();
        if (files == null) {
            return mapped;
        }
        for (ContentDocumentLinksService.DeviceEvaluationFileData file : files) {
            if (file == null || file.contentDocumentId == null) {
                continue;
            }
            EvaluationPhoto photo = new EvaluationPhoto();
            photo.contentDocumentId = file.contentDocumentId;
            photo.title = file.title;
            photo.fileExtension = file.fileExtension;
            photo.isImage = file.isImage == true;
            photo.imageDownloadUrl = file.imageDownloadUrl;
            // Prefer version download for IE summary — THUMB renditions are often not ready yet.
            photo.thumbnailUrl = String.isNotBlank(file.imageDownloadUrl)
                ? file.imageDownloadUrl
                : file.thumbnailUrl;
            mapped.add(photo);
        }
        return mapped;
    }

    /**
     * @description GW-3400 - Maps domain repair-code cards to Aura DTOs.
     * @param cards Service repair-code cards
     * @return Aura repair-code cards
     */
    private static List<RepairCodeCard> mapRepairCodeCards(
        List<ProductRelatedMaterialsService.RepairCodeCardData> cards
    ) {
        List<RepairCodeCard> mapped = new List<RepairCodeCard>();
        if (cards == null) {
            return mapped;
        }
        for (ProductRelatedMaterialsService.RepairCodeCardData card : cards) {
            RepairCodeCard dto = new RepairCodeCard();
            dto.productId = card.productId;
            dto.workOrderLineItemId = card.workOrderLineItemId;
            dto.status = card.status;
            dto.productCode = card.productCode;
            dto.productName = card.productName;
            dto.codeType = card.codeType;
            dto.selected = card.selected == true;
            mapped.add(dto);
        }
        return mapped;
    }

    /**
     * @description GW-3400 - Maps Team Member signatures to Aura DTOs.
     * @param signatures Team Member rows
     * @return Signature DTOs
     */
    private static List<RepairSignatureRow> mapRepairSignatures(
        List<RepairCenterTeamMember__c> signatures
    ) {
        List<RepairSignatureRow> rows = new List<RepairSignatureRow>();
        if (signatures == null) {
            return rows;
        }
        for (RepairCenterTeamMember__c signature : signatures) {
            RepairSignatureRow row = new RepairSignatureRow();
            row.id = signature.Id;
            row.workOrderLineItemId = signature.WorkOrderLineItem__c;
            row.productId = signature.WorkOrderLineItem__r != null
                ? signature.WorkOrderLineItem__r.Product2Id
                : null;
            row.userId = signature.Person__c;
            row.userName = signature.Person__r != null &&
                String.isNotBlank(signature.Person__r.Name)
                ? signature.Person__r.Name
                : signature.Name;
            rows.add(row);
        }
        return rows;
    }

    /**
     * @description Sub Status values available on Repair Center - Instruments record type
     *              (UI API picklist-values for RepairCenterInstruments). Excludes Device-only
     *              repair-stage values such as Angulation, Assembly, Video, etc.
     */
    private static final Set<String> INSTRUMENTS_RECORD_TYPE_SUB_STATUSES = new Set<String>{
        'Contaminated',
        'Customer Care',
        'Mod Hold',
        'Need Additional Information',
        'Other',
        'Ship to Vendor',
        'Ready for Eval',
        'Ready for QC',
        'Receive from Vendor',
        'Received from Vendor',
        'Redirect',
        'Rejected',
        'Resolved',
        'STERIS',
        'Shipped to Vendor',
        'Verification',
        'Waiting for Approval',
        'Warranty Inspection',
        'PO Required'
    };

    /**
     * @description GW-3400 - Returns active Sub Status values valid for the Work Order Status
     *              and Instruments record type. When Status is Evaluate & Quote, Waiting for
     *              Approval, Rejected, and PO Required are omitted unless they are the current Sub Status.
     * @param controllingStatus Work Order Status
     * @param currentSubStatus Current Sub Status on the Work Order
     * @return Sub Status picklist options
     */
    @TestVisible
    private static List<PlatformUtilities.PicklistOption> getSubStatusOptions(
        String controllingStatus,
        String currentSubStatus
    ) {
        List<PlatformUtilities.PicklistOption> options =
            new List<PlatformUtilities.PicklistOption>();
        Integer controllerIndex = getPicklistValueIndex(
            WorkOrder.Status.getDescribe().getPicklistValues(),
            controllingStatus
        );
        Boolean restrictEvaluateQuoteSubStatus =
            controllingStatus == 'Evaluate & Quote';
        Boolean currentIncluded = false;
        for (Schema.PicklistEntry entry : WorkOrder.SubStatus__c.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            if (controllerIndex >= 0 && !isPicklistEntryValidFor(entry, controllerIndex)) {
                continue;
            }
            String value = entry.getValue();
            if (
                !INSTRUMENTS_RECORD_TYPE_SUB_STATUSES.contains(value) &&
                value != currentSubStatus
            ) {
                continue;
            }
            if (
                restrictEvaluateQuoteSubStatus &&
                (value == 'Waiting for Approval' ||
                    value == 'Rejected' ||
                    value == 'PO Required') &&
                value != currentSubStatus
            ) {
                continue;
            }
            PlatformUtilities.PicklistOption option = new PlatformUtilities.PicklistOption();
            option.label = entry.getLabel();
            option.value = value;
            options.add(option);
            if (value == currentSubStatus) {
                currentIncluded = true;
            }
        }
        if (String.isNotBlank(currentSubStatus) && !currentIncluded) {
            PlatformUtilities.PicklistOption currentOption =
                new PlatformUtilities.PicklistOption();
            currentOption.label = currentSubStatus;
            currentOption.value = currentSubStatus;
            options.add(currentOption);
        }
        return options;
    }

    /**
     * @description GW-3400 - Finds the controlling picklist index for a value.
     * @param entries Picklist entries
     * @param value Value to match
     * @return Index, or -1 when not found
     */
    private static Integer getPicklistValueIndex(
        List<Schema.PicklistEntry> entries,
        String value
    ) {
        if (String.isBlank(value) || entries == null) {
            return -1;
        }
        for (Integer i = 0; i < entries.size(); i++) {
            if (entries[i].getValue() == value) {
                return i;
            }
        }
        return -1;
    }

    /**
     * @description GW-3400 - Uses PicklistEntry.validFor to decide dependent-picklist validity.
     * @param entry Dependent picklist entry
     * @param controllerIndex Controlling-value index
     * @return True when the dependent value is valid for the controller
     */
    private static Boolean isPicklistEntryValidFor(
        Schema.PicklistEntry entry,
        Integer controllerIndex
    ) {
        if (entry == null || controllerIndex == null || controllerIndex < 0) {
            return false;
        }
        Map<String, Object> entryMap =
            (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(entry));
        String validFor = (String) entryMap.get('validFor');
        if (String.isBlank(validFor)) {
            return true;
        }
        String base64Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
        Integer charIndex = controllerIndex / 6;
        if (charIndex >= validFor.length()) {
            return false;
        }
        Integer bitShift = 5 - Math.mod(controllerIndex, 6);
        Integer bitValue = base64Chars.indexOf(validFor.substring(charIndex, charIndex + 1));
        return bitValue >= 0 && (bitValue & (1 << bitShift)) != 0;
    }

    /**
     * @description GW-3400 - Builds an AuraHandledException with a user-visible message.
     * @param message Exception message
     * @return AuraHandledException
     */
    private static AuraHandledException buildAuraException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}