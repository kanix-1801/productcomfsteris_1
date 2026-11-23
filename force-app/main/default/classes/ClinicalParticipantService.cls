/**
 * @description GC-3542 - Builds and saves clinical participants from the popup JSON.
 * The create flow calls the invocable method. The LWC calls ClinicalParticipantController.
 */
public with sharing class ClinicalParticipantService {
    public class ParticipantInput {
        @InvocableVariable(label='Process Review Id' required=true)
        public Id processReviewId;

        @InvocableVariable(label='Participants JSON')
        public String participantsJson;
    }

    public class ClinicalParticipantException extends Exception {
    }

    private class ParticipantDraft {
        public String userId;
        public String name;
        public String email;
    }

    /**
     * @description GC-3542 - Active User for the popup.
     * @param userId Salesforce User Id.
     * @return The active User, or null.
     */
    public static User getActiveSalesforceUser(Id userId) {
        return ClinicalParticipantSelector.selectActiveUser(userId);
    }

    /**
     * @description GC-3542 - Saves one review's participants. The controller wraps errors for the LWC.
     * @param processReviewId Parent Process Review Id.
     * @param participantsJson Popup JSON.
     */
    public static void saveClinicalParticipantsForReview(Id processReviewId, String participantsJson) {
        ParticipantInput inputRow = new ParticipantInput();
        inputRow.processReviewId = processReviewId;
        inputRow.participantsJson = participantsJson;
        saveClinicalParticipants(new List<ParticipantInput>{ inputRow });
    }

    @InvocableMethod(
        label='Save Clinical Participants'
        description='GC-3542 - Creates clinical participant rows from the create-flow popup.'
        category='Key Account Process Review'
    )
    public static void saveClinicalParticipants(List<ParticipantInput> inputs) {
        if (inputs == null || inputs.isEmpty()) {
            return;
        }

        List<ClinicalParticipant__c> rows = new List<ClinicalParticipant__c>();
        for (ParticipantInput inputRow : inputs) {
            if (inputRow == null || inputRow.processReviewId == null || String.isBlank(inputRow.participantsJson)) {
                continue;
            }
            rows.addAll(clinicalParticipantsFromJson(inputRow.processReviewId, inputRow.participantsJson));
        }
        if (rows.isEmpty()) {
            return;
        }

        try {
            insert rows;
        } catch (DmlException ex) {
            Logger.error('ClinicalParticipantService.saveClinicalParticipants', ex);
            Logger.saveLog();
            String message = ex.getNumDml() > 0 ? ex.getDmlMessage(0) : ex.getMessage();
            throw new ClinicalParticipantException(message);
        }
    }

    private static List<ClinicalParticipant__c> clinicalParticipantsFromJson(Id processReviewId, String participantsJson) {
        List<ParticipantDraft> drafts;
        try {
            drafts = (List<ParticipantDraft>) JSON.deserialize(participantsJson, List<ParticipantDraft>.class);
        } catch (Exception ex) {
            Logger.error('ClinicalParticipantService.clinicalParticipantsFromJson', ex);
            Logger.saveLog();
            throw new ClinicalParticipantException('Clinical participants could not be read. Add them again.');
        }

        List<ClinicalParticipant__c> rows = new List<ClinicalParticipant__c>();
        Set<String> emails = new Set<String>();
        Map<Id, User> usersById = salesforceUsersForDrafts(drafts);
        for (ParticipantDraft draft : drafts) {
            if (draft == null) {
                continue;
            }
            Id salesforceUserId = salesforceUserIdFromText(draft.userId);
            User salesforceUser = salesforceUserId == null ? null : usersById.get(salesforceUserId);
            String email = salesforceUser != null && String.isNotBlank(salesforceUser.Email)
                ? salesforceUser.Email.trim()
                : (draft.email == null ? '' : draft.email.trim());
            if (String.isBlank(email)) {
                continue;
            }
            String emailKey = email.toLowerCase();
            if (!emails.add(emailKey)) {
                throw new ClinicalParticipantException('This email is already on this Process Review.');
            }
            String participantName = salesforceUser != null && String.isNotBlank(salesforceUser.Name)
                ? salesforceUser.Name.trim()
                : (String.isBlank(draft.name) ? email : draft.name.trim());
            if (participantName.length() > 80) {
                participantName = participantName.substring(0, 80);
            }
            rows.add(
                new ClinicalParticipant__c(
                    Name = participantName,
                    Email__c = email,
                    User__c = salesforceUserId,
                    NotSalesforceUser__c = salesforceUserId == null,
                    KeyAccountProcessReview__c = processReviewId
                )
            );
        }
        return rows;
    }

    private static Map<Id, User> salesforceUsersForDrafts(List<ParticipantDraft> drafts) {
        Set<Id> userIds = new Set<Id>();
        for (ParticipantDraft draft : drafts) {
            if (draft == null) {
                continue;
            }
            Id userId = salesforceUserIdFromText(draft.userId);
            if (userId != null) {
                userIds.add(userId);
            }
        }
        return ClinicalParticipantSelector.selectUsersByIds(userIds);
    }

    private static Id salesforceUserIdFromText(String userId) {
        if (String.isBlank(userId)) {
            return null;
        }
        try {
            return Id.valueOf(userId);
        } catch (Exception ex) {
            return null;
        }
    }
}