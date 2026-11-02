/**
 * @description Apex controller for the Device Evaluation LWC (GW-3913 / GW-3096).
 *              Thin Aura layer: DTOs, @AuraEnabled entry points, exception wrapping, and
 *              mapping from dominant-object service domain types. Business logic lives on
 *              WorkOrdersService, WorkOrderLineItemsService, ProductRelatedMaterialsService,
 *              and Content* services.
 *              Uses Nebula Logger for ERROR/WARN entries with saveLog in finally
 *              (same approach as Case routing logging + OraclePricingService persistence).
 */
public with sharing class DeviceEvaluationController {
    private static final String WO_STATUS_REPAIR = 'Repair';
    private static final String WO_SUB_STATUS_CONTAMINATED = 'Contaminated';
    private static final String WO_SUB_STATUS_SHIP_TO_VENDOR = 'Ship to Vendor';

    @TestVisible
    private interface IDeviceEvaluationWorkOrdersClient {
        WorkOrdersService.DeviceEvaluationContext initializeDeviceEvaluation(
            String workOrderNumber
        );
        WorkOrdersService.DeviceEvaluationContext saveDeviceEvaluationWorkOrderFields(
            Id workOrderId,
            String subStatus,
            Boolean unableToTakePhoto,
            Decimal turnTime,
            String usageCount,
            String evaluationNotes,
            String internalEvaluationNotes,
            String internalSpecialistEvaluationNotes
        );
        WorkOrdersService.DeviceEvaluationContext persistDeviceEvaluationDraft(
            Id workOrderId,
            String subStatus,
            Boolean unableToTakePhoto,
            Decimal turnTime,
            String usageCount,
            String evaluationNotes,
            String internalEvaluationNotes,
            String internalSpecialistEvaluationNotes,
            List<Id> selectedProductIds,
            List<ContentDocumentLinksService.StagedPhotoAssignment> stagedPhotos,
            Boolean completeEvaluation
        );
    }

    private class DefaultDeviceEvaluationWorkOrdersClient
        implements IDeviceEvaluationWorkOrdersClient {
        public WorkOrdersService.DeviceEvaluationContext initializeDeviceEvaluation(
            String workOrderNumber
        ) {
            return WorkOrdersService.initializeDeviceEvaluation(workOrderNumber);
        }

        public WorkOrdersService.DeviceEvaluationContext saveDeviceEvaluationWorkOrderFields(
            Id workOrderId,
            String subStatus,
            Boolean unableToTakePhoto,
            Decimal turnTime,
            String usageCount,
            String evaluationNotes,
            String internalEvaluationNotes,
            String internalSpecialistEvaluationNotes
        ) {
            return WorkOrdersService.saveDeviceEvaluationWorkOrderFields(
                workOrderId,
                subStatus,
                unableToTakePhoto,
                turnTime,
                usageCount,
                evaluationNotes,
                internalEvaluationNotes,
                internalSpecialistEvaluationNotes
            );
        }

        public WorkOrdersService.DeviceEvaluationContext persistDeviceEvaluationDraft(
            Id workOrderId,
            String subStatus,
            Boolean unableToTakePhoto,
            Decimal turnTime,
            String usageCount,
            String evaluationNotes,
            String internalEvaluationNotes,
            String internalSpecialistEvaluationNotes,
            List<Id> selectedProductIds,
            List<ContentDocumentLinksService.StagedPhotoAssignment> stagedPhotos,
            Boolean completeEvaluation
        ) {
            return WorkOrdersService.persistDeviceEvaluationDraft(
                workOrderId,
                subStatus,
                unableToTakePhoto,
                turnTime,
                usageCount,
                evaluationNotes,
                internalEvaluationNotes,
                internalSpecialistEvaluationNotes,
                selectedProductIds,
                stagedPhotos,
                completeEvaluation
            );
        }
    }

    @TestVisible
    private static IDeviceEvaluationWorkOrdersClient facadeOverride;

    private static IDeviceEvaluationWorkOrdersClient workOrdersClient() {
        return facadeOverride == null
            ? new DefaultDeviceEvaluationWorkOrdersClient()
            : facadeOverride;
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    public class RepairCodeCard {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productCode;
        @AuraEnabled public String productName;
        @AuraEnabled public String codeType;
        @AuraEnabled public String evalCategory;
        @AuraEnabled public String evalRank;
        /** Product Condition__c - used by Mark All Ok (Observation Codes). */
        @AuraEnabled public String condition;
        /** BOM Component Sequence - used to sort cards within a tab. */
        @AuraEnabled public Decimal componentSequence;
        @AuraEnabled public Boolean selected;
    }

    public class EvalCategoryTab {
        @AuraEnabled public String categoryName;
        @AuraEnabled public String tabValue;
        /**
         * Minimum Eval Rank across Observation/Service cards in this category.
         * Used only to order dynamic eval-category tabs.
         */
        @AuraEnabled public String minEvalRank;
        @AuraEnabled public List<RepairCodeCard> observationCodes;
        @AuraEnabled public List<RepairCodeCard> serviceCodes;
    }

    public class RepairCodeLine {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
    }

    public class RepairHistoryRow {
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public Date actualShipDate;
        @AuraEnabled public String evaluatorName;
        @AuraEnabled public String recordUrl;
        @AuraEnabled public String labName;
        @AuraEnabled public String reportedProblem;
        @AuraEnabled public Datetime repairDate;
        @AuraEnabled public String evaluationNotes;
        @AuraEnabled public String internalNotes;
        @AuraEnabled public Boolean isWithinLastTwelveMonths;
        @AuraEnabled public List<RepairCodeLine> repairCodeLines;
    }

    public class PreferenceRow {
        @AuraEnabled public Id preferenceId;
        @AuraEnabled public String name;
        @AuraEnabled public String preferenceType;
        @AuraEnabled public String productLine;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
    }

    public class WorkOrderFileRow {
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public String title;
        @AuraEnabled public String fileExtension;
        @AuraEnabled public String fileType;
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public String downloadUrl;
        @AuraEnabled public String thumbnailUrl;
        @AuraEnabled public String imageDownloadUrl;
        @AuraEnabled public Boolean isImage;
        /** Repair-code Product Id when staged/attached at WOLI level. */
        @AuraEnabled public Id productId;
        @AuraEnabled public String productCode;
        /** Repair-code description (Product Description, else Name). */
        @AuraEnabled public String productName;
    }

    /**
     * @description Client → Complete mapping of a staged ContentDocument to a repair-code Product.
     */
    public class StagedPhotoAssignment {
        @AuraEnabled public Id contentDocumentId { get; set; }
        @AuraEnabled public Id productId { get; set; }
    }

    public class CameraCaptureResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public WorkOrderFileRow file;
        @AuraEnabled public List<WorkOrderFileRow> files;
    }


    /**
     * @description Repair Center Team Member signature on a Repair Code WOLI.
     */
    public class RepairSignatureRow {
        @AuraEnabled public Id id;
        @AuraEnabled public Id workOrderLineItemId;
        @AuraEnabled public Id productId;
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
    }


    public class EvaluationWorkspace {
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public String deviceIdentityLine;
        @AuraEnabled public String status;
        @AuraEnabled public String subStatus;
        @AuraEnabled public Boolean photosRequired;
        @AuraEnabled public Boolean unableToTakePhoto;
        @AuraEnabled public Decimal turnTime;
        @AuraEnabled public String usageCount;
        @AuraEnabled public Date usageCountDate;
        @AuraEnabled public String estimateRequired;
        @AuraEnabled public String repairWarranty;
        @AuraEnabled public Boolean continuousImprovementOpportunity;
        @AuraEnabled public Boolean customerPORequired;
        @AuraEnabled public String customerPO;
        /** GW-5696 - Customer requires ship complete. */
        @AuraEnabled public Boolean shipComplete;
        /** Work Order Description shown on the WO Details tab. */
        @AuraEnabled public String description;
        @AuraEnabled public String evaluationNotes;
        @AuraEnabled public String internalEvaluationNotes;
        @AuraEnabled public String internalSpecialistEvaluationNotes;
        /** GW-5453 - Read-only Quality Technician notes on Evaluation Notes tab. */
        @AuraEnabled public String qcInspectionNotes;
        /** GW-5883 - Contamination locations shown when Sub Status is Contaminated. */
        @AuraEnabled public WorkOrdersService.ContaminationInformation contamination;
        @AuraEnabled public Id assetId;
        @AuraEnabled public String assetName;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String manufacturer;
        @AuraEnabled public String model;
        @AuraEnabled public String productLine;
        /** Work Order Product Line formula (ProductLine_f__c) - used for Usage Count visibility. */
        @AuraEnabled public String workOrderProductLine;
        @AuraEnabled public List<PicklistOption> subStatusOptions;
        @AuraEnabled public List<RepairHistoryRow> repairHistory;
        @AuraEnabled public Boolean repairHistoryHasMore;
        @AuraEnabled public List<PreferenceRow> customerPreferences;
        @AuraEnabled public List<RepairCodeCard> categoryCodes;
        @AuraEnabled public List<EvalCategoryTab> evalCategoryTabs;
        @AuraEnabled public List<Id> selectedProductIds;
        @AuraEnabled public List<WorkOrderFileRow> attachedFiles;
        @AuraEnabled public Integer selectableCardCount;
        @AuraEnabled public Integer categoryCodeCount;
        @AuraEnabled public Integer observationCodeCount;
        @AuraEnabled public Integer serviceCodeCount;
        @AuraEnabled public List<WarrantyRepairEvaluationsController.WarrantyRepairEvaluationRow> warrantyRepairEvaluations;
        @AuraEnabled public List<RepairSignatureRow> repairSignatures;
        @AuraEnabled public Id vendorAccountId;
        @AuraEnabled public Id vendorWorkOrderId;
        @AuraEnabled public String instructionsToVendor;
        @AuraEnabled public String sterisPurchaseOrderToVendor;
        @AuraEnabled public String vendorNotes;
        @AuraEnabled public String vendorReferenceNumber;
        @AuraEnabled public Decimal vendorCost;
        @AuraEnabled public Date shippedToVendorDate;
        @AuraEnabled public String trackingNumber;
        @AuraEnabled public String vendorAddress;
    }

    /**
     * @description Resolves a Work Order by Id or number, initializes eval fields, returns workspace.
     */
    @AuraEnabled
    public static EvaluationWorkspace initializeEvaluation(String workOrderNumber) {
        try {
            if (String.isBlank(workOrderNumber)) {
                throw PlatformUtilities.buildAuraException('Work Order Id / Number is required.');
            }
            return mapContextToWorkspace(
                workOrdersClient().initializeDeviceEvaluation(workOrderNumber.trim())
            );
        } catch (AuraHandledException e) {
            Logger.warn(
                new LogMessage(
                    'DeviceEvaluationController.initializeEvaluation validation: {0}',
                    e.getMessage()
                )
            );
            throw e;
        } catch (DmlException e) {
            logError('DeviceEvaluationController.initializeEvaluation DML', e);
            throw PlatformUtilities.buildAuraException(
                'Unable to initialize the Work Order for evaluation: ' + e.getDmlMessage(0)
            );
        } catch (Exception e) {
            Exception unwrapped = unwrapDmlCause(e);
            if (unwrapped instanceof DmlException) {
                logError('DeviceEvaluationController.initializeEvaluation DML', unwrapped);
                throw PlatformUtilities.buildAuraException(
                    'Unable to initialize the Work Order for evaluation: ' +
                    ((DmlException) unwrapped).getDmlMessage(0)
                );
            }
            if (isBusinessServiceException(e)) {
                Logger.warn(
                    new LogMessage(
                        'DeviceEvaluationController.initializeEvaluation validation: {0}',
                        e.getMessage()
                    )
                );
                throw PlatformUtilities.buildAuraException(e.getMessage());
            }
            logError('DeviceEvaluationController.initializeEvaluation failed', e);
            throw PlatformUtilities.buildAuraException(
                'Unable to initialize Device Evaluation: ' + PlatformUtilities.resolveExceptionMessage(e)
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Persists editable Device Evaluation header / notes fields on the Work Order.
     */
    @AuraEnabled
    public static EvaluationWorkspace saveWorkOrderFields(
        Id workOrderId,
        String subStatus,
        Boolean unableToTakePhoto,
        Decimal turnTime,
        String usageCount,
        String evaluationNotes,
        String internalEvaluationNotes,
        String internalSpecialistEvaluationNotes,
        String contaminationJson
    ) {
        Savepoint savePoint = Database.setSavepoint();
        try {
            if (workOrderId == null) {
                throw PlatformUtilities.buildAuraException('Work Order is required.');
            }
            WorkOrdersService.applyContaminationInformation(
                workOrderId,
                subStatus,
                WorkOrdersService.parseContaminationInformation(contaminationJson)
            );
            return mapContextToWorkspace(
                workOrdersClient().saveDeviceEvaluationWorkOrderFields(
                    workOrderId,
                    subStatus,
                    unableToTakePhoto,
                    turnTime,
                    usageCount,
                    evaluationNotes,
                    internalEvaluationNotes,
                    internalSpecialistEvaluationNotes
                )
            );
        } catch (AuraHandledException e) {
            Database.rollback(savePoint);
            Logger.warn(
                new LogMessage(
                    'DeviceEvaluationController.saveWorkOrderFields validation: {0}',
                    e.getMessage()
                )
            );
            throw e;
        } catch (DmlException e) {
            Database.rollback(savePoint);
            logError('DeviceEvaluationController.saveWorkOrderFields DML', e);
            throw PlatformUtilities.buildAuraException('Unable to save Work Order changes: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            Database.rollback(savePoint);
            Exception unwrapped = unwrapDmlCause(e);
            if (unwrapped instanceof DmlException) {
                logError('DeviceEvaluationController.saveWorkOrderFields DML', unwrapped);
                throw PlatformUtilities.buildAuraException(
                    'Unable to save Work Order changes: ' +
                    ((DmlException) unwrapped).getDmlMessage(0)
                );
            }
            if (isBusinessServiceException(e)) {
                Logger.warn(
                    new LogMessage(
                        'DeviceEvaluationController.saveWorkOrderFields validation: {0}',
                        e.getMessage()
                    )
                );
                throw PlatformUtilities.buildAuraException(e.getMessage());
            }
            logError('DeviceEvaluationController.saveWorkOrderFields failed', e);
            throw PlatformUtilities.buildAuraException(
                'Unable to save Work Order changes: ' + PlatformUtilities.resolveExceptionMessage(e)
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Saves evaluation progress without completing (GW-3913 §xii).
     *              Commits notes, Photos Required, Repair Code WOLI reconcile, staged photo
     *              links, then Sub Status (after WOLIs so dependent flows see the lines).
     */
    @AuraEnabled
    public static EvaluationWorkspace saveEvaluation(
        Id workOrderId,
        String subStatus,
        Boolean unableToTakePhoto,
        Decimal turnTime,
        String usageCount,
        String evaluationNotes,
        String internalEvaluationNotes,
        String internalSpecialistEvaluationNotes,
        List<Id> selectedProductIds,
        List<StagedPhotoAssignment> stagedPhotos,
        String vendorDetailsJson,
        String contaminationJson
    ) {
        Savepoint savePoint = Database.setSavepoint();
        try {
            WorkOrdersService.applyContaminationInformation(
                workOrderId,
                subStatus,
                WorkOrdersService.parseContaminationInformation(contaminationJson)
            );
            WorkOrdersService.DeviceEvaluationContext context =
                workOrdersClient().persistDeviceEvaluationDraft(
                    workOrderId,
                    subStatus,
                    unableToTakePhoto,
                    turnTime,
                    usageCount,
                    evaluationNotes,
                    internalEvaluationNotes,
                    internalSpecialistEvaluationNotes,
                    selectedProductIds,
                    mapStagedPhotoAssignments(stagedPhotos),
                    false
                );
            applyVendorDetailsIfProvided(workOrderId, subStatus, vendorDetailsJson);
            WorkOrder refreshed = WorkOrdersService.getWorkOrderForDeviceEvaluationById(workOrderId);
            if (refreshed != null) {
                context.workOrder = refreshed;
            }
            return mapContextToWorkspace(context);
        } catch (AuraHandledException e) {
            Database.rollback(savePoint);
            Logger.warn(
                new LogMessage(
                    'DeviceEvaluationController.saveEvaluation validation: {0}',
                    e.getMessage()
                )
            );
            throw e;
        } catch (DmlException e) {
            Database.rollback(savePoint);
            logError('DeviceEvaluationController.saveEvaluation DML', e);
            throw PlatformUtilities.buildAuraException('Unable to save Device Evaluation: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            Database.rollback(savePoint);
            Exception unwrapped = unwrapDmlCause(e);
            if (unwrapped instanceof DmlException) {
                logError('DeviceEvaluationController.saveEvaluation DML', unwrapped);
                throw PlatformUtilities.buildAuraException(
                    'Unable to save Device Evaluation: ' +
                    ((DmlException) unwrapped).getDmlMessage(0)
                );
            }
            if (isBusinessServiceException(e)) {
                Logger.warn(
                    new LogMessage(
                        'DeviceEvaluationController.saveEvaluation validation: {0}',
                        e.getMessage()
                    )
                );
                throw PlatformUtilities.buildAuraException(e.getMessage());
            }
            logError('DeviceEvaluationController.saveEvaluation failed', e);
            throw PlatformUtilities.buildAuraException(
                'Unable to save Device Evaluation: ' + PlatformUtilities.resolveExceptionMessage(e)
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Completes Device Evaluation: photo check, header save, WOLI reconcile,
     *              attach staged photos to Repair Code WOLIs, then completion Status/Sub Status.
     *              Status/Sub Status are committed after WOLIs so quote-generation flows see lines.
     */
    @AuraEnabled
    public static void completeEvaluation(
        Id workOrderId,
        String subStatus,
        Boolean unableToTakePhoto,
        Decimal turnTime,
        String usageCount,
        String evaluationNotes,
        String internalEvaluationNotes,
        String internalSpecialistEvaluationNotes,
        List<Id> selectedProductIds,
        List<StagedPhotoAssignment> stagedPhotos,
        String vendorDetailsJson,
        String contaminationJson
    ) {
        Savepoint savePoint = Database.setSavepoint();
        try {
            WorkOrdersService.applyContaminationInformation(
                workOrderId,
                subStatus,
                WorkOrdersService.parseContaminationInformation(contaminationJson)
            );
            workOrdersClient().persistDeviceEvaluationDraft(
                workOrderId,
                subStatus,
                unableToTakePhoto,
                turnTime,
                usageCount,
                evaluationNotes,
                internalEvaluationNotes,
                internalSpecialistEvaluationNotes,
                selectedProductIds,
                mapStagedPhotoAssignments(stagedPhotos),
                true
            );
            applyVendorDetailsIfProvided(workOrderId, subStatus, vendorDetailsJson);
        } catch (AuraHandledException e) {
            Database.rollback(savePoint);
            Logger.warn(
                new LogMessage(
                    'DeviceEvaluationController.completeEvaluation validation: {0}',
                    e.getMessage()
                )
            );
            throw e;
        } catch (DmlException e) {
            Database.rollback(savePoint);
            logError('DeviceEvaluationController.completeEvaluation DML', e);
            throw PlatformUtilities.buildAuraException('Unable to complete Device Evaluation: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            Database.rollback(savePoint);
            Exception unwrapped = unwrapDmlCause(e);
            if (unwrapped instanceof DmlException) {
                logError('DeviceEvaluationController.completeEvaluation DML', unwrapped);
                throw PlatformUtilities.buildAuraException(
                    'Unable to complete Device Evaluation: ' +
                    ((DmlException) unwrapped).getDmlMessage(0)
                );
            }
            if (isBusinessServiceException(e)) {
                Logger.warn(
                    new LogMessage(
                        'DeviceEvaluationController.completeEvaluation validation: {0}',
                        e.getMessage()
                    )
                );
                throw PlatformUtilities.buildAuraException(e.getMessage());
            }
            logError('DeviceEvaluationController.completeEvaluation failed', e);
            throw PlatformUtilities.buildAuraException(
                'Unable to complete Device Evaluation: ' + PlatformUtilities.resolveExceptionMessage(e)
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Saves pending Device Evaluation changes, then returns the Work Order
     *              to Status = Evaluate and Sub Status = Re-Quote Required.
     */
    @AuraEnabled
    public static void returnToEvaluation(
        Id workOrderId,
        String subStatus,
        Boolean unableToTakePhoto,
        Decimal turnTime,
        String usageCount,
        String evaluationNotes,
        String internalEvaluationNotes,
        String internalSpecialistEvaluationNotes,
        List<Id> selectedProductIds,
        List<StagedPhotoAssignment> stagedPhotos
    ) {
        Savepoint savePoint = Database.setSavepoint();
        try {
            workOrdersClient().persistDeviceEvaluationDraft(
                workOrderId,
                subStatus,
                unableToTakePhoto,
                turnTime,
                usageCount,
                evaluationNotes,
                internalEvaluationNotes,
                internalSpecialistEvaluationNotes,
                selectedProductIds,
                mapStagedPhotoAssignments(stagedPhotos),
                false
            );
            WorkOrdersService.returnWorkOrderToEvaluation(workOrderId);
        } catch (AuraHandledException e) {
            Database.rollback(savePoint);
            Logger.warn(
                new LogMessage(
                    'DeviceEvaluationController.returnToEvaluation validation: {0}',
                    e.getMessage()
                )
            );
            throw e;
        } catch (DmlException e) {
            Database.rollback(savePoint);
            logError('DeviceEvaluationController.returnToEvaluation DML', e);
            throw PlatformUtilities.buildAuraException(
                'Unable to return the Work Order to Evaluate: ' + e.getDmlMessage(0)
            );
        } catch (Exception e) {
            Database.rollback(savePoint);
            Exception unwrapped = unwrapDmlCause(e);
            if (unwrapped instanceof DmlException) {
                logError('DeviceEvaluationController.returnToEvaluation DML', unwrapped);
                throw PlatformUtilities.buildAuraException(
                    'Unable to return the Work Order to Evaluate: ' +
                    ((DmlException) unwrapped).getDmlMessage(0)
                );
            }
            if (isBusinessServiceException(e)) {
                Logger.warn(
                    new LogMessage(
                        'DeviceEvaluationController.returnToEvaluation validation: {0}',
                        e.getMessage()
                    )
                );
                throw PlatformUtilities.buildAuraException(e.getMessage());
            }
            logError('DeviceEvaluationController.returnToEvaluation failed', e);
            throw PlatformUtilities.buildAuraException(
                'Unable to return the Work Order to Evaluate: ' + PlatformUtilities.resolveExceptionMessage(e)
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Persists a draft, then adds the current user's signature to a Repair Code.
     */
    @AuraEnabled
    public static List<RepairSignatureRow> addRepairSignature(
        Id workOrderId,
        String subStatus,
        Boolean unableToTakePhoto,
        Decimal turnTime,
        String usageCount,
        String evaluationNotes,
        String internalEvaluationNotes,
        String internalSpecialistEvaluationNotes,
        List<Id> selectedProductIds,
        List<StagedPhotoAssignment> stagedPhotos,
        String vendorDetailsJson,
        Id productId
    ) {
        Savepoint savePoint = Database.setSavepoint();
        try {
            persistEvaluationDraftForSignatures(
                workOrderId,
                subStatus,
                unableToTakePhoto,
                turnTime,
                usageCount,
                evaluationNotes,
                internalEvaluationNotes,
                internalSpecialistEvaluationNotes,
                selectedProductIds,
                stagedPhotos
            );
            if (WO_SUB_STATUS_SHIP_TO_VENDOR.equals(subStatus)) {
                applyVendorDetailsIfProvided(workOrderId, subStatus, vendorDetailsJson);
            }
            return mapRepairSignatures(
                RepairCenterTeamMembersService.addSignature(workOrderId, productId)
            );
        } catch (AuraHandledException e) {
            Database.rollback(savePoint);
            throw e;
        } catch (DmlException e) {
            Database.rollback(savePoint);
            logError('DeviceEvaluationController.addRepairSignature DML', e);
            throw PlatformUtilities.buildAuraException('Unable to sign the repair code: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            Database.rollback(savePoint);
            Exception unwrapped = unwrapDmlCause(e);
            if (unwrapped instanceof DmlException) {
                logError('DeviceEvaluationController.addRepairSignature DML', unwrapped);
                throw PlatformUtilities.buildAuraException(
                    'Unable to sign the repair code: ' +
                    ((DmlException) unwrapped).getDmlMessage(0)
                );
            }
            if (isBusinessServiceException(e)) {
                Logger.warn(
                    new LogMessage(
                        'DeviceEvaluationController.addRepairSignature validation: {0}',
                        e.getMessage()
                    )
                );
                throw PlatformUtilities.buildAuraException(e.getMessage());
            }
            logError('DeviceEvaluationController.addRepairSignature failed', e);
            throw PlatformUtilities.buildAuraException(
                'Unable to sign the repair code: ' + PlatformUtilities.resolveExceptionMessage(e)
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Persists a draft, then signs every supplied Repair Code the current user has not signed.
     */
    @AuraEnabled
    public static List<RepairSignatureRow> signAllRepairCodes(
        Id workOrderId,
        String subStatus,
        Boolean unableToTakePhoto,
        Decimal turnTime,
        String usageCount,
        String evaluationNotes,
        String internalEvaluationNotes,
        String internalSpecialistEvaluationNotes,
        List<Id> selectedProductIds,
        List<StagedPhotoAssignment> stagedPhotos,
        String vendorDetailsJson,
        List<Id> productIds
    ) {
        Savepoint savePoint = Database.setSavepoint();
        try {
            persistEvaluationDraftForSignatures(
                workOrderId,
                subStatus,
                unableToTakePhoto,
                turnTime,
                usageCount,
                evaluationNotes,
                internalEvaluationNotes,
                internalSpecialistEvaluationNotes,
                selectedProductIds,
                stagedPhotos
            );
            if (WO_SUB_STATUS_SHIP_TO_VENDOR.equals(subStatus)) {
                applyVendorDetailsIfProvided(workOrderId, subStatus, vendorDetailsJson);
            }
            return mapRepairSignatures(
                RepairCenterTeamMembersService.signAll(workOrderId, productIds)
            );
        } catch (AuraHandledException e) {
            Database.rollback(savePoint);
            throw e;
        } catch (DmlException e) {
            Database.rollback(savePoint);
            logError('DeviceEvaluationController.signAllRepairCodes DML', e);
            throw PlatformUtilities.buildAuraException('Unable to sign repair codes: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            Database.rollback(savePoint);
            Exception unwrapped = unwrapDmlCause(e);
            if (unwrapped instanceof DmlException) {
                logError('DeviceEvaluationController.signAllRepairCodes DML', unwrapped);
                throw PlatformUtilities.buildAuraException(
                    'Unable to sign repair codes: ' +
                    ((DmlException) unwrapped).getDmlMessage(0)
                );
            }
            if (isBusinessServiceException(e)) {
                Logger.warn(
                    new LogMessage(
                        'DeviceEvaluationController.signAllRepairCodes validation: {0}',
                        e.getMessage()
                    )
                );
                throw PlatformUtilities.buildAuraException(e.getMessage());
            }
            logError('DeviceEvaluationController.signAllRepairCodes failed', e);
            throw PlatformUtilities.buildAuraException(
                'Unable to sign repair codes: ' + PlatformUtilities.resolveExceptionMessage(e)
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Deletes a Repair Center Team Member signature for the Work Order.
     */
    @AuraEnabled
    public static List<RepairSignatureRow> removeRepairSignature(Id workOrderId, Id signatureId) {
        Savepoint savePoint = Database.setSavepoint();
        try {
            return mapRepairSignatures(
                RepairCenterTeamMembersService.removeSignature(workOrderId, signatureId)
            );
        } catch (AuraHandledException e) {
            Database.rollback(savePoint);
            throw e;
        } catch (DmlException e) {
            Database.rollback(savePoint);
            logError('DeviceEvaluationController.removeRepairSignature DML', e);
            throw PlatformUtilities.buildAuraException('Unable to remove the signature: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            Database.rollback(savePoint);
            Exception unwrapped = unwrapDmlCause(e);
            if (unwrapped instanceof DmlException) {
                logError('DeviceEvaluationController.removeRepairSignature DML', unwrapped);
                throw PlatformUtilities.buildAuraException(
                    'Unable to remove the signature: ' +
                    ((DmlException) unwrapped).getDmlMessage(0)
                );
            }
            if (isBusinessServiceException(e)) {
                Logger.warn(
                    new LogMessage(
                        'DeviceEvaluationController.removeRepairSignature validation: {0}',
                        e.getMessage()
                    )
                );
                throw PlatformUtilities.buildAuraException(e.getMessage());
            }
            logError('DeviceEvaluationController.removeRepairSignature failed', e);
            throw PlatformUtilities.buildAuraException(
                'Unable to remove the signature: ' + PlatformUtilities.resolveExceptionMessage(e)
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Stages a photo/file for a repair-code Product without linking yet.
     *              Linked to the Repair Code WOLI on Quick Save, Save & Close, or Complete.
     */
    @AuraEnabled
    public static CameraCaptureResult stageEvaluationPhoto(
        Id productId,
        String base64Data,
        String fileName
    ) {
        try {
            ContentVersionsService.StagedPhotoResult staged =
                ContentVersionsService.stagePhotoForDeviceEvaluation(
                    productId,
                    base64Data,
                    fileName
                );
            WorkOrderFileRow row = mapFileData(
                ContentDocumentLinksService.toFileData(staged.version)
            );
            row.productId = staged.productId;
            row.productCode = staged.productCode;
            row.productName = staged.productName;

            CameraCaptureResult result = new CameraCaptureResult();
            result.success = true;
            result.message =
                'Photo staged for this repair code. It is saved on Quick Save, Save & Close, or Complete.';
            result.contentDocumentId = staged.version.ContentDocumentId;
            result.file = row;
            return result;
        } catch (AuraHandledException e) {
            Logger.warn(
                new LogMessage(
                    'DeviceEvaluationController.stageEvaluationPhoto validation: {0}',
                    e.getMessage()
                )
            );
            throw e;
        } catch (DmlException e) {
            logError('DeviceEvaluationController.stageEvaluationPhoto DML', e);
            throw PlatformUtilities.buildAuraException('Unable to stage photo: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            Exception unwrapped = unwrapDmlCause(e);
            if (unwrapped instanceof DmlException) {
                logError('DeviceEvaluationController.stageEvaluationPhoto DML', unwrapped);
                throw PlatformUtilities.buildAuraException(
                    'Unable to stage photo: ' + ((DmlException) unwrapped).getDmlMessage(0)
                );
            }
            if (isBusinessServiceException(e)) {
                Logger.warn(
                    new LogMessage(
                        'DeviceEvaluationController.stageEvaluationPhoto validation: {0}',
                        e.getMessage()
                    )
                );
                throw PlatformUtilities.buildAuraException(e.getMessage());
            }
            logError('DeviceEvaluationController.stageEvaluationPhoto failed', e);
            throw PlatformUtilities.buildAuraException('Unable to stage photo: ' + PlatformUtilities.resolveExceptionMessage(e));
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Renames a staged/linked evaluation photo Title for a ContentDocument
     *              created by the current user.
     */
    @AuraEnabled
    public static WorkOrderFileRow renameStagedEvaluationPhoto(
        Id contentDocumentId,
        String newTitle
    ) {
        try {
            ContentVersion refreshed = ContentVersionsService.renamePhotoForDeviceEvaluation(
                contentDocumentId,
                newTitle
            );
            return mapFileData(ContentDocumentLinksService.toFileData(refreshed));
        } catch (AuraHandledException e) {
            Logger.warn(
                new LogMessage(
                    'DeviceEvaluationController.renameStagedEvaluationPhoto validation: {0}',
                    e.getMessage()
                )
            );
            throw e;
        } catch (DmlException e) {
            logError('DeviceEvaluationController.renameStagedEvaluationPhoto DML', e);
            throw PlatformUtilities.buildAuraException('Unable to rename photo: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            Exception unwrapped = unwrapDmlCause(e);
            if (unwrapped instanceof DmlException) {
                logError('DeviceEvaluationController.renameStagedEvaluationPhoto DML', unwrapped);
                throw PlatformUtilities.buildAuraException(
                    'Unable to rename photo: ' + ((DmlException) unwrapped).getDmlMessage(0)
                );
            }
            if (isBusinessServiceException(e)) {
                Logger.warn(
                    new LogMessage(
                        'DeviceEvaluationController.renameStagedEvaluationPhoto validation: {0}',
                        e.getMessage()
                    )
                );
                throw PlatformUtilities.buildAuraException(e.getMessage());
            }
            logError('DeviceEvaluationController.renameStagedEvaluationPhoto failed', e);
            throw PlatformUtilities.buildAuraException('Unable to rename photo: ' + PlatformUtilities.resolveExceptionMessage(e));
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Deletes a staged ContentDocument owned by the current user (not yet linked).
     */
    @AuraEnabled
    public static void deleteStagedEvaluationPhoto(Id contentDocumentId) {
        try {
            ContentDocumentsService.deleteStagedPhotoForDeviceEvaluation(contentDocumentId);
        } catch (AuraHandledException e) {
            Logger.warn(
                new LogMessage(
                    'DeviceEvaluationController.deleteStagedEvaluationPhoto validation: {0}',
                    e.getMessage()
                )
            );
            throw e;
        } catch (DmlException e) {
            logError('DeviceEvaluationController.deleteStagedEvaluationPhoto DML', e);
            throw PlatformUtilities.buildAuraException('Unable to delete staged photo: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            Exception unwrapped = unwrapDmlCause(e);
            if (unwrapped instanceof DmlException) {
                logError('DeviceEvaluationController.deleteStagedEvaluationPhoto DML', unwrapped);
                throw PlatformUtilities.buildAuraException(
                    'Unable to delete staged photo: ' +
                    ((DmlException) unwrapped).getDmlMessage(0)
                );
            }
            if (isBusinessServiceException(e)) {
                Logger.warn(
                    new LogMessage(
                        'DeviceEvaluationController.deleteStagedEvaluationPhoto validation: {0}',
                        e.getMessage()
                    )
                );
                throw PlatformUtilities.buildAuraException(e.getMessage());
            }
            logError('DeviceEvaluationController.deleteStagedEvaluationPhoto failed', e);
            throw PlatformUtilities.buildAuraException(
                'Unable to delete staged photo: ' + PlatformUtilities.resolveExceptionMessage(e)
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-3913 - Removes a photo already linked to a Repair Code WOLI (parity with IE).
     * @param workOrderId Parent Work Order Id
     * @param productId Repair-code Product Id for the line
     * @param contentDocumentId ContentDocument Id
     */
    @AuraEnabled
    public static void removeEvaluationPhoto(
        Id workOrderId,
        Id productId,
        Id contentDocumentId
    ) {
        try {
            if (workOrderId == null || productId == null || contentDocumentId == null) {
                throw PlatformUtilities.buildAuraException('Work Order, repair code, and photo are required.');
            }

            Id repairCodeRtId = WorkOrderLineItemsService.getRepairCodeRecordTypeId();
            if (repairCodeRtId == null) {
                throw PlatformUtilities.buildAuraException('Repair Code record type is not configured.');
            }

            List<WorkOrderLineItem> repairCodeLines =
                WorkOrderLineItemsService.getRepairCodeByWorkOrderAndProducts(
                    workOrderId,
                    repairCodeRtId,
                    new Set<Id>{ productId }
                );
            if (repairCodeLines.isEmpty()) {
                throw PlatformUtilities.buildAuraException(
                    'The repair code was not found on this Work Order.'
                );
            }

            ContentDocumentLinksService.removeDocumentFromLinkedEntity(
                repairCodeLines[0].Id,
                contentDocumentId
            );
        } catch (ContentDocumentLinksService.ContentDocumentLinksServiceException e) {
            throw PlatformUtilities.buildAuraException(e.getMessage());
        } catch (ContentDocumentsService.ContentDocumentsServiceException e) {
            throw PlatformUtilities.buildAuraException(e.getMessage());
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            throw PlatformUtilities.buildAuraException(e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            logError('DeviceEvaluationController.removeEvaluationPhoto failed', e);
            throw PlatformUtilities.buildAuraException('Unable to remove the photo.');
        } finally {
            Logger.saveLog();
        }
    }


    /**
     * @description GW-3891 - Delegates to WarrantyRepairEvaluationsController (shared WRE panel API).
     * @param workOrderId Parent Work Order Id
     * @param workOrderLineItemId Optional Product Serviced WOLI filter (GW-3400)
     * @return Aura row DTOs
     */
    @AuraEnabled
    public static List<WarrantyRepairEvaluationsController.WarrantyRepairEvaluationRow> getWarrantyRepairEvaluations(
        Id workOrderId,
        Id workOrderLineItemId
    ) {
        return WarrantyRepairEvaluationsController.getWarrantyRepairEvaluations(
            workOrderId,
            workOrderLineItemId
        );
    }

    /**
     * @description GW-3891 - Delegates to WarrantyRepairEvaluationsController (shared WRE panel API).
     * @param workOrderId Parent Work Order Id
     * @param recordId Existing WRE Id when editing; null for New
     * @param workOrderLineItemId Optional Product Serviced WOLI to stamp/seed (GW-3400)
     * @return Aura form DTO
     */
    @AuraEnabled
    public static WarrantyRepairEvaluationsController.WarrantyRepairEvaluationForm getWarrantyRepairEvaluationForm(
        Id workOrderId,
        Id recordId,
        Id workOrderLineItemId
    ) {
        return WarrantyRepairEvaluationsController.getWarrantyRepairEvaluationForm(
            workOrderId,
            recordId,
            workOrderLineItemId
        );
    }

    /**
     * @description GW-3891 - Delegates to WarrantyRepairEvaluationsController (shared WRE panel API).
     * @param workOrderId Parent Work Order Id
     * @param formJson Serialized form JSON
     * @return Updated related-list rows
     */
    @AuraEnabled
    public static List<WarrantyRepairEvaluationsController.WarrantyRepairEvaluationRow> saveWarrantyRepairEvaluation(
        Id workOrderId,
        String formJson
    ) {
        return WarrantyRepairEvaluationsController.saveWarrantyRepairEvaluation(workOrderId, formJson);
    }




    private static Exception unwrapDmlCause(Exception e) {
        if (e == null) {
            return null;
        }
        if (e instanceof DmlException) {
            return e;
        }
        if (e.getCause() instanceof DmlException) {
            return e.getCause();
        }
        return e;
    }

    private static Boolean isBusinessServiceException(Exception e) {
        return e instanceof WorkOrdersService.WorkOrdersServiceException ||
            e instanceof WorkOrderLineItemsService.WorkOrderLineItemsServiceException ||
            e instanceof ProductRelatedMaterialsService.ProductRelatedMaterialsServiceException ||
            e instanceof ContentDocumentLinksService.ContentDocumentLinksServiceException ||
            e instanceof ContentVersionsService.ContentVersionsServiceException ||
            e instanceof ContentDocumentsService.ContentDocumentsServiceException ||
            e instanceof CustomerPreferencesService.CustomerPreferencesServiceException ||
            e instanceof ProductsService.ProductsServiceException ||
            e instanceof PricebookEntriesService.PricebookEntriesServiceException ||
            e instanceof WarrantyRepairEvaluationsService.WarrantyRepairEvaluationsServiceException ||
            e instanceof RepairCenterTeamMembersService.RepairCenterTeamMembersServiceException;
    }

    private static void applyVendorDetailsIfProvided(
        Id workOrderId,
        String newSubStatus,
        String vendorDetailsJson
    ) {
        if (workOrderId == null) {
            return;
        }
        WorkOrdersService.VendorHeaderDetails details = null;
        if (String.isNotBlank(vendorDetailsJson)) {
            details = (WorkOrdersService.VendorHeaderDetails) JSON.deserialize(
                vendorDetailsJson,
                WorkOrdersService.VendorHeaderDetails.class
            );
        }
        // Create whenever Sub Status is Ship to Vendor and the Vendor WO is still blank.
        // Sync whenever vendor details are posted.
        if (details == null && !WO_SUB_STATUS_SHIP_TO_VENDOR.equals(newSubStatus)) {
            return;
        }
        try {
            WorkOrdersService.handleDeviceEvaluationOutsideVendor(
                workOrderId,
                newSubStatus,
                details
            );
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            throw PlatformUtilities.buildAuraException(e.getMessage());
        }
    }

    private static void logError(String context, Exception e) {
        if (e == null) {
            Logger.error(context);
            return;
        }
        Logger.error(context, e);
    }

    private static List<ContentDocumentLinksService.StagedPhotoAssignment> mapStagedPhotoAssignments(
        List<StagedPhotoAssignment> stagedPhotos
    ) {
        List<ContentDocumentLinksService.StagedPhotoAssignment> mapped =
            new List<ContentDocumentLinksService.StagedPhotoAssignment>();
        if (stagedPhotos == null || stagedPhotos.isEmpty()) {
            return mapped;
        }
        for (StagedPhotoAssignment assignment : stagedPhotos) {
            if (assignment == null) {
                continue;
            }
            ContentDocumentLinksService.StagedPhotoAssignment domainAssignment =
                new ContentDocumentLinksService.StagedPhotoAssignment();
            domainAssignment.contentDocumentId = assignment.contentDocumentId;
            domainAssignment.productId = assignment.productId;
            mapped.add(domainAssignment);
        }
        return mapped;
    }

    private static EvaluationWorkspace mapContextToWorkspace(
        WorkOrdersService.DeviceEvaluationContext context
    ) {
        EvaluationWorkspace workspace = new EvaluationWorkspace();
        if (context == null || context.workOrder == null) {
            return workspace;
        }
        WorkOrder workOrder = context.workOrder;
        workspace.workOrderId = workOrder.Id;
        workspace.workOrderNumber = workOrder.WorkOrderNumber;
        workspace.status = workOrder.Status;
        workspace.subStatus = workOrder.SubStatus__c;
        workspace.photosRequired = context.photosRequired;
        workspace.unableToTakePhoto = workOrder.UnableToTakePhoto__c == true;
        workspace.turnTime = workOrder.TurnTime__c;
        workspace.usageCount = workOrder.UsageCount__c;
        workspace.usageCountDate = workOrder.UsageCountDate__c;
        workspace.estimateRequired = workOrder.EstimateRequired__c;
        workspace.repairWarranty = workOrder.RepairWarranty__c;
        workspace.continuousImprovementOpportunity =
            workOrder.ContinuousImprovementOpportunity__c == true;
        workspace.customerPORequired = workOrder.CustomerPORequired__c == true;
        workspace.customerPO = workOrder.CustomerPO__c;
        workspace.shipComplete = workOrder.ShipComplete__c == true;
        workspace.description = workOrder.Description;
        workspace.evaluationNotes = workOrder.EvaluationNotes__c;
        workspace.internalEvaluationNotes = workOrder.InternalEvaluationNotes__c;
        workspace.internalSpecialistEvaluationNotes = workOrder.InternalSpecialistEvaluationNotes__c;
        workspace.qcInspectionNotes = workOrder.QCInspectionNotes__c;
        workspace.contamination = WorkOrdersService.toContaminationInformation(workOrder);
        workspace.assetId = workOrder.AssetId;
        workspace.assetName = workOrder.Asset != null ? workOrder.Asset.Name : null;
        workspace.serialNumber = context.serialNumber;
        workspace.productId = workOrder.Asset != null ? workOrder.Asset.Product2Id : null;
        workspace.productName =
            workOrder.Asset != null && workOrder.Asset.Product2 != null
                ? workOrder.Asset.Product2.Name
                : null;
        workspace.manufacturer = context.manufacturer;
        workspace.model = context.model;
        workspace.productLine = context.productLine;
        workspace.workOrderProductLine = workOrder.ProductLine_f__c;
        workspace.deviceIdentityLine = context.deviceIdentityLine;
        workspace.subStatusOptions = getSubStatusOptions(
            workOrder.Status,
            workOrder.ProductLine_f__c,
            workOrder.SubStatus__c
        );
        workspace.customerPreferences = mapPreferenceRows(context.customerPreferences);
        workspace.repairHistory = mapRepairHistoryRows(context.repairHistory);
        workspace.repairHistoryHasMore = context.repairHistoryHasMore == true;
        workspace.categoryCodes = mapRepairCodeCards(context.categoryCodes);
        workspace.evalCategoryTabs = mapEvalCategoryTabs(context.evalCategoryTabs);
        workspace.selectedProductIds = context.selectedProductIds == null
            ? new List<Id>()
            : new List<Id>(context.selectedProductIds);
        workspace.attachedFiles = mapFileDataRows(context.attachedFiles);
        workspace.selectableCardCount = context.selectableCardCount;
        workspace.categoryCodeCount = context.categoryCodeCount;
        workspace.observationCodeCount = context.observationCodeCount;
        workspace.serviceCodeCount = context.serviceCodeCount;
        workspace.warrantyRepairEvaluations =
            WarrantyRepairEvaluationsController.getWarrantyRepairEvaluations(workOrder.Id, null);
        workspace.vendorAccountId = workOrder.Vendor__c;
        workspace.vendorWorkOrderId = workOrder.VendorWorkOrder__c;
        workspace.instructionsToVendor = workOrder.InstructionsToVendor__c;
        workspace.sterisPurchaseOrderToVendor = workOrder.STERISPurchaseOrdertoVendor__c;
        workspace.vendorNotes = workOrder.VendorNotes__c;
        workspace.vendorReferenceNumber = workOrder.VendorReferenceNumber__c;
        workspace.vendorCost = workOrder.VendorCost__c;
        workspace.shippedToVendorDate = workOrder.ShippedToVendorDate__c;
        workspace.trackingNumber = workOrder.TrackingNumber__c;
        applyVendorWorkOrderHeaderToWorkspace(workspace, workOrder);
        if (workspace.vendorAccountId != null && String.isBlank(workspace.vendorAddress)) {
            workspace.vendorAddress = WorkOrdersService.getVendorAddress(
                    workspace.vendorAccountId
                )
                .formattedAddress;
        }
        workspace.repairSignatures = mapRepairSignatures(
            RepairCenterTeamMembersService.getWorkOrderLineSignatures(workOrder.Id)
        );
        return workspace;
    }

    /**
     * @description Prefers Vendor WO header fields when linked (matches Instrument Evaluation).
     *              Tracking Number is written to the Vendor WO by shipment flows, not the eval WO.
     */
    private static void applyVendorWorkOrderHeaderToWorkspace(
        EvaluationWorkspace workspace,
        WorkOrder workOrder
    ) {
        if (workspace == null || workOrder == null || workOrder.VendorWorkOrder__c == null) {
            return;
        }
        WorkOrdersService.VendorHeaderDetails vendorHeader =
            WorkOrdersService.getVendorWorkOrderHeaderDetails(workOrder.VendorWorkOrder__c);
        if (vendorHeader == null) {
            return;
        }
        if (vendorHeader.vendorAccountId != null) {
            workspace.vendorAccountId = vendorHeader.vendorAccountId;
        }
        workspace.instructionsToVendor = vendorHeader.instructionsToVendor;
        workspace.sterisPurchaseOrderToVendor = vendorHeader.sterisPurchaseOrderToVendor;
        workspace.vendorNotes = vendorHeader.vendorNotes;
        workspace.vendorReferenceNumber = vendorHeader.vendorReferenceNumber;
        workspace.vendorCost = vendorHeader.vendorCost;
        workspace.shippedToVendorDate = vendorHeader.shippedToVendorDate;
        workspace.trackingNumber = vendorHeader.trackingNumber;
        if (workspace.vendorAccountId != null) {
            workspace.vendorAddress = WorkOrdersService.getVendorAddress(
                    workspace.vendorAccountId
                )
                .formattedAddress;
        }
    }

    private static void persistEvaluationDraftForSignatures(
        Id workOrderId,
        String subStatus,
        Boolean unableToTakePhoto,
        Decimal turnTime,
        String usageCount,
        String evaluationNotes,
        String internalEvaluationNotes,
        String internalSpecialistEvaluationNotes,
        List<Id> selectedProductIds,
        List<StagedPhotoAssignment> stagedPhotos
    ) {
        workOrdersClient().persistDeviceEvaluationDraft(
            workOrderId,
            subStatus,
            unableToTakePhoto,
            turnTime,
            usageCount,
            evaluationNotes,
            internalEvaluationNotes,
            internalSpecialistEvaluationNotes,
            selectedProductIds,
            mapStagedPhotoAssignments(stagedPhotos),
            false
        );
    }

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
                ? signature.WorkOrderLineItem__r.Product__c
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

    private static List<RepairCodeCard> mapRepairCodeCards(
        List<ProductRelatedMaterialsService.RepairCodeCardData> cards
    ) {
        List<RepairCodeCard> mapped = new List<RepairCodeCard>();
        if (cards == null || cards.isEmpty()) {
            return mapped;
        }
        for (ProductRelatedMaterialsService.RepairCodeCardData card : cards) {
            if (card == null) {
                continue;
            }
            RepairCodeCard row = new RepairCodeCard();
            row.productId = card.productId;
            row.productCode = card.productCode;
            row.productName = card.productName;
            row.codeType = card.codeType;
            row.evalCategory = card.evalCategory;
            row.evalRank = card.evalRank;
            row.condition = card.condition;
            row.componentSequence = card.componentSequence;
            row.selected = card.selected == true;
            mapped.add(row);
        }
        return mapped;
    }

    private static List<EvalCategoryTab> mapEvalCategoryTabs(
        List<ProductRelatedMaterialsService.EvalCategoryTabData> tabs
    ) {
        List<EvalCategoryTab> mapped = new List<EvalCategoryTab>();
        if (tabs == null || tabs.isEmpty()) {
            return mapped;
        }
        for (ProductRelatedMaterialsService.EvalCategoryTabData tab : tabs) {
            if (tab == null) {
                continue;
            }
            EvalCategoryTab row = new EvalCategoryTab();
            row.categoryName = tab.categoryName;
            row.tabValue = tab.tabValue;
            row.minEvalRank = tab.minEvalRank;
            row.observationCodes = mapRepairCodeCards(tab.observationCodes);
            row.serviceCodes = mapRepairCodeCards(tab.serviceCodes);
            mapped.add(row);
        }
        return mapped;
    }

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
                lineItem.Product__r != null ? lineItem.Product__r.ProductCode : null;
            String productName = lineItem.Product__r != null ? lineItem.Product__r.Name : null;
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

    private static List<WorkOrderFileRow> mapFileDataRows(
        List<ContentDocumentLinksService.DeviceEvaluationFileData> files
    ) {
        List<WorkOrderFileRow> rows = new List<WorkOrderFileRow>();
        if (files == null || files.isEmpty()) {
            return rows;
        }
        for (ContentDocumentLinksService.DeviceEvaluationFileData fileData : files) {
            rows.add(mapFileData(fileData));
        }
        return rows;
    }

    private static WorkOrderFileRow mapFileData(
        ContentDocumentLinksService.DeviceEvaluationFileData fileData
    ) {
        WorkOrderFileRow row = new WorkOrderFileRow();
        if (fileData == null) {
            return row;
        }
        row.contentDocumentId = fileData.contentDocumentId;
        row.contentVersionId = fileData.contentVersionId;
        row.title = fileData.title;
        row.fileExtension = fileData.fileExtension;
        row.fileType = fileData.fileType;
        row.lastModifiedDate = fileData.lastModifiedDate;
        row.downloadUrl = fileData.downloadUrl;
        row.thumbnailUrl = fileData.thumbnailUrl;
        row.imageDownloadUrl = fileData.imageDownloadUrl;
        row.isImage = fileData.isImage;
        row.productId = fileData.productId;
        row.productCode = fileData.productCode;
        row.productName = fileData.productName;
        return row;
    }

    /**
     * @description Returns active Sub Status values valid for the Work Order Status
     *              controlling picklist (SubStatus__c is restricted + dependent).
     *              When Status = Repair, options are further limited by Product Line.
     */
    @TestVisible
    private static List<PicklistOption> getSubStatusOptions(
        String controllingStatus,
        String productLine,
        String currentSubStatus
    ) {
        List<PicklistOption> options = new List<PicklistOption>();
        Integer controllerIndex = getPicklistValueIndex(
            WorkOrder.Status.getDescribe().getPicklistValues(),
            controllingStatus
        );
        for (Schema.PicklistEntry entry : WorkOrder.SubStatus__c.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            if (controllerIndex >= 0 && !isPicklistEntryValidFor(entry, controllerIndex)) {
                continue;
            }
            PicklistOption option = new PicklistOption();
            option.label = entry.getLabel();
            option.value = entry.getValue();
            options.add(option);
        }
        if (!WO_STATUS_REPAIR.equals(controllingStatus)) {
            return options;
        }
        return filterRepairSubStatusOptions(options, productLine, currentSubStatus);
    }

    @TestVisible
    private static List<PicklistOption> filterRepairSubStatusOptions(
        List<PicklistOption> statusOptions,
        String productLine,
        String currentSubStatus
    ) {
        Set<String> allowed = repairSubStatusValuesForProductLine(productLine);
        List<PicklistOption> filtered = new List<PicklistOption>();
        Boolean currentIncluded = false;
        for (PicklistOption option : statusOptions) {
            if (option == null || String.isBlank(option.value)) {
                continue;
            }
            if (allowed.contains(option.value)) {
                filtered.add(option);
                if (option.value == currentSubStatus) {
                    currentIncluded = true;
                }
            }
        }
        if (String.isNotBlank(currentSubStatus) && !currentIncluded) {
            PicklistOption currentOption = new PicklistOption();
            currentOption.label = currentSubStatus;
            currentOption.value = currentSubStatus;
            filtered.add(currentOption);
        }
        return filtered;
    }

    @TestVisible
    private static Set<String> repairSubStatusValuesForProductLine(String productLine) {
        // GW-5687 - Contaminated is valid for Repair across product lines (picklist dependency).
        Set<String> allowed = new Set<String>{ WO_SUB_STATUS_CONTAMINATED };
        if (String.isBlank(productLine)) {
            return allowed;
        }
        Set<String> byLine = repairSubStatusByProductLine().get(normalizeRepairProductLine(productLine));
        if (byLine != null) {
            allowed.addAll(byLine);
        }
        return allowed;
    }

    private static String normalizeRepairProductLine(String productLine) {
        String key = productLine.trim().toUpperCase();
        if (key == 'RIGID SCOPE') {
            return 'RIGID';
        }
        return key;
    }

    private static Map<String, Set<String>> repairSubStatusByProductLine() {
        return new Map<String, Set<String>>{
            'FLEXIBLE SCOPE' => new Set<String>{
                'Angulation',
                'Assembly',
                'Attachment',
                'Bending Rubber',
                'Channel Replacement',
                'Disassembly',
                'Distal',
                'Drying Hold',
                'Electrical',
                'Eyepiece',
                'Light Guide Tube Replacement',
                'Loading',
                'Insertion Tube',
                'Other',
                WO_SUB_STATUS_SHIP_TO_VENDOR,
                'Prep',
                'Pre QC',
                'Part Hold - NI (Not Inventory)',
                'Part Hold - I (Inventory)',
                'Part Hold - IM (Internal Manufacturing)',
                'Rack',
                'Repair',
                'Specialty',
                'Phaco',
                'Bronchoscope',
                'Gastroscope'
            },
            'POWER' => new Set<String>{
                'Electric',
                'Attachment',
                'Sub-assembly',
                'Small Bone',
                'Large Bone',
                'Ophthalmic',
                'Diamond Knives',
                'GRE',
                'Pre QC'
            },
            'VIDEO' => new Set<String>{ 'Video', 'Pre QC' },
            'RIGID' => new Set<String>{ 'Refiber', 'Optics', 'Pre QC' },
            'ENDOCAM' => new Set<String>{ 'Endocam', 'Pre QC' }
        };
    }

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
     * @description Uses PicklistEntry.validFor bitset (via JSON serialize) to decide
     *              whether a dependent value is allowed for the controlling index.
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
}