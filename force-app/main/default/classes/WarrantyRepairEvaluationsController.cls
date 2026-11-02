/**
 * @description Thin Aura controller for the shared Warranty Repair Evaluation panel (GW-3891 / GW-3400).
 *              DTOs and @AuraEnabled entry points only. Business logic lives on
 *              WarrantyRepairEvaluationsService (and WorkOrders / WOLI services for form context).
 */
public with sharing class WarrantyRepairEvaluationsController {
    /**
     * @description Service client so tests can override WarrantyRepairEvaluationsService.
     */
    @TestVisible
    private interface IWarrantyRepairEvaluationsClient {
        List<WarrantyRepairEvaluation__c> getEvaluationsByWorkOrderId(
            Id workOrderId,
            Id workOrderLineItemId
        );
        WarrantyRepairEvaluation__c buildEvaluationForForm(
            Id workOrderId,
            Id recordId,
            Id workOrderLineItemId
        );
        List<WarrantyRepairEvaluation__c> saveEvaluation(WarrantyRepairEvaluation__c evaluation);
        WorkOrder getWorkOrderForForm(Id workOrderId);
        WorkOrderLineItem getLineItemForForm(Id workOrderLineItemId);
    }

    private class DefaultClient implements IWarrantyRepairEvaluationsClient {
        public List<WarrantyRepairEvaluation__c> getEvaluationsByWorkOrderId(
            Id workOrderId,
            Id workOrderLineItemId
        ) {
            return WarrantyRepairEvaluationsService.getEvaluationsByWorkOrderId(
                workOrderId,
                workOrderLineItemId
            );
        }

        public WarrantyRepairEvaluation__c buildEvaluationForForm(
            Id workOrderId,
            Id recordId,
            Id workOrderLineItemId
        ) {
            return WarrantyRepairEvaluationsService.buildEvaluationForForm(
                workOrderId,
                recordId,
                workOrderLineItemId
            );
        }

        public List<WarrantyRepairEvaluation__c> saveEvaluation(
            WarrantyRepairEvaluation__c evaluation
        ) {
            return WarrantyRepairEvaluationsService.saveEvaluation(evaluation);
        }

        public WorkOrder getWorkOrderForForm(Id workOrderId) {
            return WorkOrdersService.getWorkOrderForWarrantyRepairEvaluation(workOrderId);
        }

        public WorkOrderLineItem getLineItemForForm(Id workOrderLineItemId) {
            return WorkOrderLineItemsService.getLineItemForWarrantyRepairEvaluation(
                workOrderLineItemId
            );
        }
    }

    @TestVisible
    private static IWarrantyRepairEvaluationsClient clientOverride;

    private static IWarrantyRepairEvaluationsClient client() {
        return clientOverride == null ? new DefaultClient() : clientOverride;
    }


    public class WarrantyRepairEvaluationRow {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String disposition;
        @AuraEnabled
        public String technicianName;
        @AuraEnabled
        public Date evaluationDate;
        @AuraEnabled
        public Id workOrderLineItemId;
    }

    public class WarrantyRepairEvaluationForm {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public Id workOrderId;
        @AuraEnabled
        public Id workOrderLineItemId;
        @AuraEnabled
        public String workOrderNumber;
        @AuraEnabled
        public Id parentWorkOrderId;
        @AuraEnabled
        public String parentWorkOrderNumber;
        @AuraEnabled
        public Id relatedReturnOrderId;
        @AuraEnabled
        public String relatedReturnOrderNumber;
        @AuraEnabled
        public String customerNumber;
        @AuraEnabled
        public Date dateReceived;
        @AuraEnabled
        public Decimal itemCount;
        @AuraEnabled
        public String reasonForReturn;
        @AuraEnabled
        public String signsOfDamageWearFailure;
        @AuraEnabled
        public String originalReturnOrder;
        @AuraEnabled
        public Id previousRepairQcTechnicianId;
        @AuraEnabled
        public Date previousRepairDate;
        @AuraEnabled
        public String deviceType;
        @AuraEnabled
        public String manufacturerOfTheDeviceInstrument;
        @AuraEnabled
        public String modelNumberOfTheDeviceInstrument;
        @AuraEnabled
        public String serialNumberOfTheDeviceInstrument;
        @AuraEnabled
        public String disposition;
        @AuraEnabled
        public String confirmedCustomerReportedIssue;
        @AuraEnabled
        public String issueRelatedToPreviousRepair;
        @AuraEnabled
        public String previousWorkPerformed;
        @AuraEnabled
        public String workPerformedAndRecommendation;
        @AuraEnabled
        public Id technicianPerformingWorkId;
        @AuraEnabled
        public Date technicianSignOffDate;
        @AuraEnabled
        public Id teamLeaderId;
        @AuraEnabled
        public Date teamLeaderSignOffDate;
        @AuraEnabled
        public String autoclaved;
        @AuraEnabled
        public String correctiveActionTaken;
        @AuraEnabled
        public String correctiveActionAdditionalDetails;
        @AuraEnabled
        public String contributingFactor;
        @AuraEnabled
        public String componentNcrCreated;
        @AuraEnabled
        public String ncrNumber;
        @AuraEnabled
        public String partNumber;
        @AuraEnabled
        public String lotNumber;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Boolean serialNumberRequired;
        @AuraEnabled
        public Boolean useInstrumentTypeLabel;
        @AuraEnabled
        public Integer maxEvaluationCount;
        @AuraEnabled
        public List<PlatformUtilities.PicklistOption> signsOfDamageOptions;
        @AuraEnabled
        public List<PlatformUtilities.PicklistOption> dispositionOptions;
        @AuraEnabled
        public List<PlatformUtilities.PicklistOption> yesNoOptions;
        @AuraEnabled
        public List<PlatformUtilities.PicklistOption> autoclavedOptions;
        @AuraEnabled
        public List<PlatformUtilities.PicklistOption> contributingFactorOptions;
    }

    /**
     * @description GW-3891 - Related-list rows for Warranty Repair Evaluation.
     * @param workOrderId Parent Work Order Id
     * @param workOrderLineItemId Optional Product Serviced WOLI filter (GW-3400)
     * @return Aura row DTOs
     */
    @AuraEnabled
    public static List<WarrantyRepairEvaluationRow> getWarrantyRepairEvaluations(
        Id workOrderId,
        Id workOrderLineItemId
    ) {
        try {
            return mapWarrantyRepairEvaluationRows(
                client().getEvaluationsByWorkOrderId(workOrderId, workOrderLineItemId)
            );
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            logError('WarrantyRepairEvaluationsController.getWarrantyRepairEvaluations failed', e);
            throw PlatformUtilities.buildAuraException(resolveWarrantyRepairExceptionMessage(e));
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-3891 - New/edit form defaults for Warranty Repair Evaluation.
     * @param workOrderId Parent Work Order Id
     * @param recordId Existing WRE Id when editing; null for New
     * @param workOrderLineItemId Optional Product Serviced WOLI to stamp/seed (GW-3400)
     * @return Aura form DTO
     */
    @AuraEnabled
    public static WarrantyRepairEvaluationForm getWarrantyRepairEvaluationForm(
        Id workOrderId,
        Id recordId,
        Id workOrderLineItemId
    ) {
        try {
            WorkOrder workOrder = client().getWorkOrderForForm(workOrderId);
            if (workOrder == null) {
                throw PlatformUtilities.buildAuraException('Work Order was not found.');
            }
            WarrantyRepairEvaluation__c evaluation = client().buildEvaluationForForm(
                workOrderId,
                recordId,
                workOrderLineItemId
            );
            return mapWarrantyRepairEvaluationForm(workOrder, evaluation);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            logError('WarrantyRepairEvaluationsController.getWarrantyRepairEvaluationForm failed', e);
            throw PlatformUtilities.buildAuraException(resolveWarrantyRepairExceptionMessage(e));
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-3891 - Creates or updates a Warranty Repair Evaluation from the LWC form.
     * @param workOrderId Parent Work Order Id (fallback when form omits it)
     * @param formJson Serialized WarrantyRepairEvaluationForm JSON
     * @return Updated related-list rows
     */
    @AuraEnabled
    public static List<WarrantyRepairEvaluationRow> saveWarrantyRepairEvaluation(
        Id workOrderId,
        String formJson
    ) {
        try {
            if (String.isBlank(formJson)) {
                throw PlatformUtilities.buildAuraException('Warranty Repair Evaluation form data is required.');
            }
            WarrantyRepairEvaluationForm form = (WarrantyRepairEvaluationForm) JSON.deserialize(
                formJson,
                WarrantyRepairEvaluationForm.class
            );
            Id resolvedWorkOrderId = form != null && form.workOrderId != null
                ? form.workOrderId
                : workOrderId;
            if (form == null || resolvedWorkOrderId == null) {
                throw PlatformUtilities.buildAuraException('Work Order is required.');
            }
            List<WarrantyRepairEvaluation__c> savedRows = client().saveEvaluation(
                mapWarrantyRepairEvaluationFormToSObject(form, resolvedWorkOrderId)
            );
            return mapWarrantyRepairEvaluationRows(savedRows);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            logError('WarrantyRepairEvaluationsController.saveWarrantyRepairEvaluation failed', e);
            throw PlatformUtilities.buildAuraException(resolveWarrantyRepairExceptionMessage(e));
        } finally {
            Logger.saveLog();
        }
    }



    private static String resolveWarrantyRepairExceptionMessage(Exception e) {
        if (e instanceof WarrantyRepairEvaluationsService.WarrantyRepairEvaluationsServiceException) {
            return e.getMessage();
        }
        if (e instanceof WorkOrdersService.WorkOrdersServiceException) {
            return e.getMessage();
        }
        if (e instanceof WorkOrderLineItemsService.WorkOrderLineItemsServiceException) {
            return e.getMessage();
        }
        return PlatformUtilities.resolveExceptionMessage(e);
    }

    private static void logError(String context, Exception e) {
        if (e == null) {
            Logger.error(context);
            return;
        }
        Logger.error(context, e);
    }

    private static List<WarrantyRepairEvaluationRow> mapWarrantyRepairEvaluationRows(
        List<WarrantyRepairEvaluation__c> evaluations
    ) {
        List<WarrantyRepairEvaluationRow> rows = new List<WarrantyRepairEvaluationRow>();
        if (evaluations == null || evaluations.isEmpty()) {
            return rows;
        }
        for (WarrantyRepairEvaluation__c evaluation : evaluations) {
            WarrantyRepairEvaluationRow row = new WarrantyRepairEvaluationRow();
            row.id = evaluation.Id;
            row.name = evaluation.Name;
            row.disposition = evaluation.Disposition__c;
            row.technicianName =
                evaluation.TechnicianPerformingWork__r != null
                    ? evaluation.TechnicianPerformingWork__r.Name
                    : null;
            row.evaluationDate = evaluation.Date__c;
            row.workOrderLineItemId = evaluation.WorkOrderLineItem__c;
            rows.add(row);
        }
        return rows;
    }

    private static WarrantyRepairEvaluationForm mapWarrantyRepairEvaluationForm(
        WorkOrder workOrder,
        WarrantyRepairEvaluation__c evaluation
    ) {
        WarrantyRepairEvaluationForm form = new WarrantyRepairEvaluationForm();
        if (evaluation == null) {
            return form;
        }
        form.id = evaluation.Id;
        form.name = evaluation.Name;
        form.workOrderId = evaluation.WorkOrder__c != null ? evaluation.WorkOrder__c : workOrder.Id;
        form.workOrderLineItemId = evaluation.WorkOrderLineItem__c;
        form.workOrderNumber = workOrder != null ? workOrder.WorkOrderNumber : null;
        form.parentWorkOrderId = evaluation.ParentWorkOrder__c;
        form.parentWorkOrderNumber =
            evaluation.ParentWorkOrder__r != null
                ? evaluation.ParentWorkOrder__r.WorkOrderNumber
                : workOrder != null && workOrder.ParentWorkOrder != null
                  ? workOrder.ParentWorkOrder.WorkOrderNumber
                  : null;
        form.relatedReturnOrderId = evaluation.RelatedReturnOrder__c;
        form.relatedReturnOrderNumber =
            evaluation.RelatedReturnOrder__r != null
                ? evaluation.RelatedReturnOrder__r.ReturnOrderNumber
                : workOrder != null && workOrder.ReturnOrder__r != null
                  ? workOrder.ReturnOrder__r.ReturnOrderNumber
                  : null;
        form.customerNumber = evaluation.CustomerNumber__c;
        form.dateReceived = evaluation.DateReceived__c;
        form.itemCount = evaluation.ItemCount__c;
        form.reasonForReturn = evaluation.ReasonForReturn__c;
        form.signsOfDamageWearFailure = evaluation.SignsOfDamageWearFailure__c;
        form.originalReturnOrder = evaluation.OriginalReturnOrder__c;
        form.previousRepairQcTechnicianId = evaluation.PreviousRepairQCTechnician__c;
        form.previousRepairDate = evaluation.PreviousRepairDate__c;
        form.deviceType = evaluation.DeviceType__c;
        form.manufacturerOfTheDeviceInstrument = evaluation.ManufacturerOfTheDeviceInstrument__c;
        form.modelNumberOfTheDeviceInstrument = evaluation.ModelNumberOfTheDeviceInstrument__c;
        form.serialNumberOfTheDeviceInstrument = evaluation.SerialNumberOfTheDeviceInstrument__c;
        form.disposition = evaluation.Disposition__c;
        form.confirmedCustomerReportedIssue = evaluation.ConfirmedCustomerReportedIssue__c;
        form.issueRelatedToPreviousRepair = evaluation.IssueRelatedToPreviousRepair__c;
        form.previousWorkPerformed = evaluation.PreviousWorkPerformed__c;
        form.workPerformedAndRecommendation = evaluation.WorkPerformedAndRecommendation__c;
        form.technicianPerformingWorkId = evaluation.TechnicianPerformingWork__c;
        form.technicianSignOffDate = evaluation.Date__c;
        form.teamLeaderId = evaluation.TeamLeader__c;
        form.teamLeaderSignOffDate = evaluation.TeamLeaderSignOff__c;
        form.autoclaved = evaluation.Autoclaved__c;
        form.correctiveActionTaken = evaluation.CorrectiveActionTaken__c;
        form.correctiveActionAdditionalDetails = evaluation.CorrectiveActionAdditionalDetails__c;
        form.contributingFactor = evaluation.ContributingFactor__c;
        form.componentNcrCreated = evaluation.ComponentNCRCreated__c;
        form.ncrNumber = evaluation.NCRNumber__c;
        form.partNumber = evaluation.PartNumber__c;
        form.lotNumber = evaluation.LotNumber__c;
        form.signsOfDamageOptions = PlatformUtilities.getActivePicklistOptions(
            WarrantyRepairEvaluation__c.SignsOfDamageWearFailure__c
        );
        form.dispositionOptions = PlatformUtilities.getActivePicklistOptions(WarrantyRepairEvaluation__c.Disposition__c);
        form.yesNoOptions = PlatformUtilities.buildYesNoOptions();
        form.autoclavedOptions = PlatformUtilities.getActivePicklistOptions(WarrantyRepairEvaluation__c.Autoclaved__c);
        form.contributingFactorOptions = PlatformUtilities.getActivePicklistOptions(
            WarrantyRepairEvaluation__c.ContributingFactor__c
        );
        Boolean hasAsset = workOrder != null && workOrder.AssetId != null;
        Boolean instrumentItemContext =
            form.workOrderLineItemId != null && workOrder != null && !hasAsset;
        form.serialNumberRequired = hasAsset;
        form.useInstrumentTypeLabel = instrumentItemContext;
        if (instrumentItemContext && form.workOrderLineItemId != null) {
            WorkOrderLineItem lineItem = client().getLineItemForForm(form.workOrderLineItemId);
            Decimal lineQuantity = lineItem != null ? lineItem.Quantity : null;
            form.maxEvaluationCount =
                lineQuantity != null ? Integer.valueOf(lineQuantity.intValue()) : 1;
        } else {
            form.maxEvaluationCount = 1;
        }
        return form;
    }

    private static WarrantyRepairEvaluation__c mapWarrantyRepairEvaluationFormToSObject(
        WarrantyRepairEvaluationForm form,
        Id workOrderId
    ) {
        WarrantyRepairEvaluation__c evaluation = new WarrantyRepairEvaluation__c();
        evaluation.Id = form.id;
        if (form.id == null) {
            evaluation.WorkOrder__c = workOrderId;
        }
        evaluation.WorkOrderLineItem__c = form.workOrderLineItemId;
        evaluation.ParentWorkOrder__c = form.parentWorkOrderId;
        evaluation.RelatedReturnOrder__c = form.relatedReturnOrderId;
        evaluation.CustomerNumber__c = form.customerNumber;
        evaluation.DateReceived__c = form.dateReceived;
        evaluation.ItemCount__c = form.itemCount;
        evaluation.ReasonForReturn__c = form.reasonForReturn;
        evaluation.SignsOfDamageWearFailure__c = form.signsOfDamageWearFailure;
        evaluation.OriginalReturnOrder__c = form.originalReturnOrder;
        evaluation.PreviousRepairQCTechnician__c = form.previousRepairQcTechnicianId;
        evaluation.PreviousRepairDate__c = form.previousRepairDate;
        evaluation.DeviceType__c = form.deviceType;
        evaluation.ManufacturerOfTheDeviceInstrument__c = form.manufacturerOfTheDeviceInstrument;
        evaluation.ModelNumberOfTheDeviceInstrument__c = form.modelNumberOfTheDeviceInstrument;
        evaluation.SerialNumberOfTheDeviceInstrument__c = form.serialNumberOfTheDeviceInstrument;
        evaluation.Disposition__c = form.disposition;
        evaluation.ConfirmedCustomerReportedIssue__c = form.confirmedCustomerReportedIssue;
        evaluation.IssueRelatedToPreviousRepair__c = form.issueRelatedToPreviousRepair;
        evaluation.PreviousWorkPerformed__c = form.previousWorkPerformed;
        evaluation.WorkPerformedAndRecommendation__c = form.workPerformedAndRecommendation;
        evaluation.TechnicianPerformingWork__c = form.technicianPerformingWorkId;
        evaluation.Date__c = form.technicianSignOffDate;
        evaluation.TeamLeader__c = form.teamLeaderId;
        evaluation.TeamLeaderSignOff__c = form.teamLeaderSignOffDate;
        evaluation.Autoclaved__c = form.autoclaved;
        evaluation.CorrectiveActionTaken__c = form.correctiveActionTaken;
        evaluation.CorrectiveActionAdditionalDetails__c = form.correctiveActionAdditionalDetails;
        evaluation.ContributingFactor__c = form.contributingFactor;
        evaluation.ComponentNCRCreated__c = form.componentNcrCreated;
        evaluation.NCRNumber__c = form.ncrNumber;
        evaluation.PartNumber__c = form.partNumber;
        evaluation.LotNumber__c = form.lotNumber;
        return evaluation;
    }


}