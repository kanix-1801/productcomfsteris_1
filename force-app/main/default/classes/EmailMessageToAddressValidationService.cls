public class EmailMessageToAddressValidationService {

    private static final String CBM_CASE_RECORD_TYPE = 'CBMCase';

    public static void validateToAddress(List<EmailMessage> newEmails) {

        // Step 1: Collect Parent Case Ids only
        Set<Id> caseIds = new Set<Id>();
        for (EmailMessage em : newEmails) {
            if (em.ParentId != null
                && em.ParentId.getSObjectType() == Case.SObjectType
                && String.isNotBlank(em.ToAddress)) {
                caseIds.add(em.ParentId);
            }
        }

        if (caseIds.isEmpty()) return;

        // Step 2: Query only CBMCase record type cases
        Map<Id, Case> cbmCaseMap = new Map<Id, Case>([
            SELECT Id, Email_Reviewed__c
            FROM Case
            WHERE Id IN :caseIds
            AND RecordType.DeveloperName = :CBM_CASE_RECORD_TYPE
        ]);

        if (cbmCaseMap.isEmpty()) return;

        // Step 3: Parse all To addresses from relevant EmailMessages
        Set<String> allToAddresses = new Set<String>();
        for (EmailMessage em : newEmails) {
            if (!cbmCaseMap.containsKey(em.ParentId)) continue;
            if (String.isBlank(em.ToAddress)) continue;

            for (String addr : em.ToAddress.split(',')) {
                String cleaned = addr.trim().toLowerCase();
                if (String.isNotBlank(cleaned)) {
                    allToAddresses.add(cleaned);
                }
            }
        }

        if (allToAddresses.isEmpty()) return;

        // Step 4: Find active Salesforce Users matching those addresses
        Set<String> internalUserEmails = new Set<String>();
        for (User u : [
            SELECT Email
            FROM User
            WHERE IsActive = true
            AND Email IN :allToAddresses
        ]) {
            internalUserEmails.add(u.Email.toLowerCase());
        }

        if (internalUserEmails.isEmpty()) return;

        // Step 5: Add error if Email_Reviewed__c is NOT checked
        for (EmailMessage em : newEmails) {

            // Only process CBMCase parents
            if (!cbmCaseMap.containsKey(em.ParentId)) continue;

            Case parentCase = cbmCaseMap.get(em.ParentId);

            // Bypass validation if Email Reviewed checkbox is checked
            if (parentCase.Email_Reviewed__c == true) continue;

            if (String.isBlank(em.ToAddress)) continue;

            for (String addr : em.ToAddress.split(',')) {
                String cleaned = addr.trim().toLowerCase();
                if (internalUserEmails.contains(cleaned)) {
                    em.addError(
                        'Please review your To list. One or more recipients is an internal Salesforce user. '
                        + 'If this is intentional, check the "Email Reviewed" checkbox on the Case and try again.'
                    );
                    break;
                }
            }
        }
    }
}