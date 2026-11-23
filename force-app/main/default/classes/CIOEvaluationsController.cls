/**
 * @description Aura API for the CIO Evaluation questionnaire on Device and Instrument Evaluation. GW-4749
 */
public with sharing class CIOEvaluationsController {
    /**
     * @description Related-list row shown after the questionnaire is saved.
     */
    public class EvaluationRow {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String confirmedCustomerReportedIssue;
        @AuraEnabled
        public String identifiableRootCause;
        @AuraEnabled
        public String issueRelatedToPreviousRepair;
        @AuraEnabled
        public String signsOfDamageWearFailure;
        @AuraEnabled
        public String determineExtentOfUsage;
        @AuraEnabled
        public String correctiveActionTaken;
        @AuraEnabled
        public String technicianName;
        @AuraEnabled
        public Date evaluationDate;
    }

    /**
     * @description Defaults for a new questionnaire popup.
     */
    public class FormContext {
        @AuraEnabled
        public Id recordTypeId;
        @AuraEnabled
        public Id parentWorkOrderId;
        @AuraEnabled
        public Id technicianId;
        @AuraEnabled
        public Date evaluationDate;
    }

    /**
     * @description CIO Evaluations for the current Work Order.
     * @param workOrderId Work Order Id
     * @return Related-list rows
     */
    @AuraEnabled
    public static List<EvaluationRow> getEvaluations(Id workOrderId) {
        try {
            return mapRows(CIOEvaluationsService.getByWorkOrderId(workOrderId));
        } catch (CIOEvaluationsService.CIOEvaluationsServiceException e) {
            throw PlatformUtilities.buildAuraException(e.getMessage());
        } catch (Exception e) {
            Logger.error('CIOEvaluationsController.getEvaluations failed.', e);
            Logger.saveLog();
            throw PlatformUtilities.buildAuraException('Unable to load CIO Evaluations.');
        }
    }

    /**
     * @description Defaults for creating a CIO Evaluation from the current Work Order.
     * @param workOrderId Work Order Id
     * @return Form defaults
     */
    @AuraEnabled
    public static FormContext getFormContext(Id workOrderId) {
        try {
            CIOEvaluationsService.FormContext source = CIOEvaluationsService.getFormContext(
                workOrderId
            );
            FormContext context = new FormContext();
            context.recordTypeId = source.recordTypeId;
            context.parentWorkOrderId = source.parentWorkOrderId;
            context.technicianId = source.technicianId;
            context.evaluationDate = source.evaluationDate;
            return context;
        } catch (CIOEvaluationsService.CIOEvaluationsServiceException e) {
            throw PlatformUtilities.buildAuraException(e.getMessage());
        } catch (Exception e) {
            Logger.error('CIOEvaluationsController.getFormContext failed.', e);
            Logger.saveLog();
            throw PlatformUtilities.buildAuraException('Unable to open the CIO Questionnaire.');
        }
    }

    private static List<EvaluationRow> mapRows(List<CIOEvaluation__c> evaluations) {
        List<EvaluationRow> rows = new List<EvaluationRow>();
        if (evaluations == null) {
            return rows;
        }
        for (CIOEvaluation__c evaluation : evaluations) {
            EvaluationRow row = new EvaluationRow();
            row.id = evaluation.Id;
            row.name = evaluation.Name;
            row.confirmedCustomerReportedIssue = evaluation.ConfirmedCustomerReportedIssue__c;
            row.identifiableRootCause = evaluation.IdentifiableRootCause__c;
            row.issueRelatedToPreviousRepair = evaluation.IssueRelatedToPreviousRepair__c;
            row.signsOfDamageWearFailure = evaluation.SignsOfDamageWearFailure__c;
            row.determineExtentOfUsage = evaluation.DetermineExtentOfUsage__c;
            row.correctiveActionTaken = evaluation.CorrectiveActionTaken__c;
            row.technicianName = evaluation.Technician__r == null
                ? null
                : evaluation.Technician__r.Name;
            row.evaluationDate = evaluation.Date__c;
            rows.add(row);
        }
        return rows;
    }
}