/**
 * @description GC-3542 - Saves clinical participants collected by the create-flow popup
 * and returns a Salesforce user's name and email for that popup.
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

    @AuraEnabled(cacheable=true)
    public static User getSalesforceUser(Id userId) {
        if (userId == null) {
            return null;
        }
        List<User> users = [
            SELECT Name, Email
            FROM User
            WHERE Id = :userId AND IsActive = TRUE
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0];
    }

    @AuraEnabled
    public static void saveForReview(Id processReviewId, String participantsJson) {
        ParticipantInput inputRow = new ParticipantInput();
        inputRow.processReviewId = processReviewId;
        inputRow.participantsJson = participantsJson;
        try {
            saveParticipants(new List<ParticipantInput>{ inputRow });
        } catch (ClinicalParticipantException ex) {
            AuraHandledException error = new AuraHandledException(ex.getMessage());
            error.setMessage(ex.getMessage());
            throw error;
        }
    }

    @InvocableMethod(
        label='Save Clinical Participants'
        description='GC-3542 - Creates clinical participant rows from the create-flow popup.'
        category='Key Account Process Review'
    )
    public static void saveParticipants(List<ParticipantInput> inputs) {
        if (inputs == null || inputs.isEmpty()) {
            return;
        }

        List<ClinicalParticipant__c> rows = new List<ClinicalParticipant__c>();
        for (ParticipantInput inputRow : inputs) {
            if (inputRow == null || inputRow.processReviewId == null || String.isBlank(inputRow.participantsJson)) {
                continue;
            }
            rows.addAll(buildRows(inputRow.processReviewId, inputRow.participantsJson));
        }
        if (rows.isEmpty()) {
            return;
        }

        try {
            insert rows;
        } catch (DmlException ex) {
            String message = ex.getNumDml() > 0 ? ex.getDmlMessage(0) : ex.getMessage();
            ClinicalParticipantException error = new ClinicalParticipantException(message);
            error.setMessage(message);
            throw error;
        }
    }

    private static List<ClinicalParticipant__c> buildRows(Id processReviewId, String participantsJson) {
        List<ParticipantDraft> drafts;
        try {
            drafts = (List<ParticipantDraft>) JSON.deserialize(participantsJson, List<ParticipantDraft>.class);
        } catch (Exception ex) {
            ClinicalParticipantException error = new ClinicalParticipantException(
                'Clinical participants could not be read. Add them again.'
            );
            error.setMessage('Clinical participants could not be read. Add them again.');
            throw error;
        }

        List<ClinicalParticipant__c> rows = new List<ClinicalParticipant__c>();
        Set<String> emails = new Set<String>();
        Map<Id, User> usersById = usersFor(drafts);
        for (ParticipantDraft draft : drafts) {
            if (draft == null) {
                continue;
            }
            Id salesforceUserId = toUserId(draft.userId);
            User salesforceUser = salesforceUserId == null ? null : usersById.get(salesforceUserId);
            String email = salesforceUser != null && String.isNotBlank(salesforceUser.Email)
                ? salesforceUser.Email.trim()
                : (draft.email == null ? '' : draft.email.trim());
            if (String.isBlank(email)) {
                continue;
            }
            String emailKey = email.toLowerCase();
            if (!emails.add(emailKey)) {
                ClinicalParticipantException error = new ClinicalParticipantException(
                    'Each email can be added only once on a Process Review.'
                );
                error.setMessage('Each email can be added only once on a Process Review.');
                throw error;
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

    private static Map<Id, User> usersFor(List<ParticipantDraft> drafts) {
        Set<Id> userIds = new Set<Id>();
        for (ParticipantDraft draft : drafts) {
            if (draft == null) {
                continue;
            }
            Id userId = toUserId(draft.userId);
            if (userId != null) {
                userIds.add(userId);
            }
        }
        if (userIds.isEmpty()) {
            return new Map<Id, User>();
        }
        return new Map<Id, User>([
            SELECT Name, Email
            FROM User
            WHERE Id IN :userIds
        ]);
    }

    private static Id toUserId(String userId) {
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