/**
 * @author PWC Developer
 * @date 2026/11/20
 *
 * @group Survey Management
 *
 * @description
 * GC-3506. Screen controller for NPS survey distribution. Distribution rules live in NpsSurveyDistributionService.
 */
public with sharing class NpsSurveyDistributionController {

    @AuraEnabled
    public static NpsSurveyDistributionService.WorkspaceContext getWorkspaceContext(Id approvedSurveyId) {
        return NpsSurveyDistributionService.getWorkspaceContext(approvedSurveyId);
    }

    @AuraEnabled
    public static NpsSurveyDistributionService.DistributionResult uploadRecipients(
        Id approvedSurveyId,
        String csvBody,
        Integer expirationDays,
        Integer reminderCount,
        Integer reminderIntervalDays
    ) {
        try {
            return NpsSurveyDistributionService.uploadRecipients(
                approvedSurveyId, csvBody, expirationDays, reminderCount, reminderIntervalDays
            );
        } catch (Exception exceptionValue) {
            throw handled(exceptionValue);
        }
    }

    @AuraEnabled
    public static NpsSurveyDistributionService.DistributionResult startUploadFromFile(
        Id approvedSurveyId,
        Id contentDocumentId,
        Integer expirationDays,
        Integer reminderCount,
        Integer reminderIntervalDays
    ) {
        try {
            return NpsSurveyDistributionService.startUploadFromFile(
                approvedSurveyId, contentDocumentId, expirationDays, reminderCount, reminderIntervalDays
            );
        } catch (Exception exceptionValue) {
            throw handled(exceptionValue);
        }
    }

    @AuraEnabled
    public static NpsSurveyDistributionService.DistributionResult sendDistribution(Id distributionId) {
        try {
            return NpsSurveyDistributionService.sendDistribution(distributionId);
        } catch (Exception exceptionValue) {
            throw handled(exceptionValue);
        }
    }

    @AuraEnabled
    public static NpsSurveyDistributionService.DistributionResult generateAnonymousLink(Id approvedSurveyId) {
        try {
            return NpsSurveyDistributionService.generateAnonymousLink(approvedSurveyId);
        } catch (Exception exceptionValue) {
            throw handled(exceptionValue);
        }
    }

    @AuraEnabled
    public static NpsSurveyDistributionService.DistributionResult refreshSurveyAvailability(Id approvedSurveyId) {
        try {
            return NpsSurveyDistributionService.refreshSurveyAvailability(approvedSurveyId);
        } catch (Exception exceptionValue) {
            throw handled(exceptionValue);
        }
    }

    @AuraEnabled
    public static NpsSurveyDistributionService.TrackingPage getTracking(Id distributionId) {
        try {
            return NpsSurveyDistributionService.getTracking(distributionId);
        } catch (Exception exceptionValue) {
            throw handled(exceptionValue);
        }
    }

    @AuraEnabled
    public static List<NpsSurveyDistributionService.SearchRow> searchRecipients(String searchText) {
        try {
            return NpsSurveyDistributionService.searchRecipients(searchText);
        } catch (Exception exceptionValue) {
            throw handled(exceptionValue);
        }
    }

    @AuraEnabled
    public static void setSurveyOptOut(Id contactId) {
        try {
            NpsSurveyDistributionService.setSurveyOptOut(contactId);
        } catch (Exception exceptionValue) {
            throw handled(exceptionValue);
        }
    }

    @AuraEnabled
    public static void updateFailedRecipient(Id recipientId, String firstName, String lastName, String email, String customerNumber) {
        try {
            NpsSurveyDistributionService.updateFailedRecipient(recipientId, firstName, lastName, email, customerNumber);
        } catch (Exception exceptionValue) {
            throw handled(exceptionValue);
        }
    }

    private static AuraHandledException handled(Exception exceptionValue) {
        AuraHandledException handledException = new AuraHandledException(exceptionValue.getMessage());
        handledException.setMessage(exceptionValue.getMessage());
        return handledException;
    }
}