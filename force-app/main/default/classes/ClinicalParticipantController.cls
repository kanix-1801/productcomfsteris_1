/**
 * @description GC-3542 - Aura entry point for the clinical participant popup and New button.
 */
public with sharing class ClinicalParticipantController {
    /**
     * @description GC-3542 - Returns the active User shown in the popup.
     * @param userId Salesforce User Id.
     * @return The active User, or null.
     */
    @AuraEnabled(cacheable=true)
    public static User getActiveSalesforceUser(Id userId) {
        return ClinicalParticipantService.getActiveSalesforceUser(userId);
    }

    /**
     * @description GC-3542 - Saves participants from the New button.
     * @param processReviewId Parent Process Review Id.
     * @param participantsJson Popup JSON.
     */
    @AuraEnabled
    public static void saveClinicalParticipantsForReview(Id processReviewId, String participantsJson) {
        try {
            ClinicalParticipantService.saveClinicalParticipantsForReview(processReviewId, participantsJson);
        } catch (ClinicalParticipantService.ClinicalParticipantException ex) {
            AuraHandledException error = new AuraHandledException(ex.getMessage());
            error.setMessage(ex.getMessage());
            throw error;
        }
    }
}