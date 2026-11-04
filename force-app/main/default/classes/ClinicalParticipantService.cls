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
            WITH USER_MODE
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0];
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
        for (ParticipantDraft draft : drafts) {
            if (draft == null || String.isBlank(draft.email)) {
                continue;
            }
            String email = draft.email.trim();
            String emailKey = email.toLowerCase();
            if (!emails.add(emailKey)) {
                ClinicalParticipantException error = new ClinicalParticipantException(
                    'Each email can be added only once on a Process Review.'
                );
                error.setMessage('Each email can be added only once on a Process Review.');
                throw error;
            }
            String participantName = String.isBlank(draft.name) ? email : draft.name.trim();
            if (participantName.length() > 80) {
                participantName = participantName.substring(0, 80);
            }
            rows.add(
                new ClinicalParticipant__c(
                    Name = participantName,
                    Email__c = email,
                    User__c = toUserId(draft.userId),
                    KeyAccountProcessReview__c = processReviewId
                )
            );
        }
        return rows;
    }

    public static void blockDuplicateEmailOnReview(List<ClinicalParticipant__c> rows) {
        if (rows == null || rows.isEmpty()) {
            return;
        }
        Set<Id> reviewIds = new Set<Id>();
        for (ClinicalParticipant__c row : rows) {
            if (row.KeyAccountProcessReview__c != null) {
                reviewIds.add(row.KeyAccountProcessReview__c);
            }
        }
        Map<String, Id> existingByEmail = new Map<String, Id>();
        if (!reviewIds.isEmpty()) {
            for (ClinicalParticipant__c existing : [
                SELECT Id, Email__c, KeyAccountProcessReview__c
                FROM ClinicalParticipant__c
                WHERE KeyAccountProcessReview__c IN :reviewIds
            ]) {
                if (String.isNotBlank(existing.Email__c)) {
                    existingByEmail.put(emailKey(existing.KeyAccountProcessReview__c, existing.Email__c), existing.Id);
                }
            }
        }
        Set<String> batchEmails = new Set<String>();
        for (ClinicalParticipant__c row : rows) {
            if (row.KeyAccountProcessReview__c == null || String.isBlank(row.Email__c)) {
                continue;
            }
            String rowKey = emailKey(row.KeyAccountProcessReview__c, row.Email__c);
            Id existingId = existingByEmail.get(rowKey);
            if ((existingId != null && existingId != row.Id) || !batchEmails.add(rowKey)) {
                row.addError('Each email can be added only once on a Process Review.');
            }
        }
    }

    private static String emailKey(Id processReviewId, String email) {
        return String.valueOf(processReviewId) + '|' + email.trim().toLowerCase();
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