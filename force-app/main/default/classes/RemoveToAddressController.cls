public with sharing class RemoveToAddressController {

    @AuraEnabled(cacheable=true)
    public static List<String> getSalesforceUserEmails(List<String> emails) {
        if (emails == null || emails.isEmpty()) {
            return new List<String>();
        }

        // Normalize to lowercase for case-insensitive comparison
        List<String> normalizedEmails = new List<String>();
        for (String email : emails) {
            normalizedEmails.add(email.toLowerCase().trim());
        }

        List<User> users = [
            SELECT Email
            FROM User
            WHERE Email IN :normalizedEmails
            AND IsActive = TRUE
        ];

        List<String> sfUserEmails = new List<String>();
        for (User u : users) {
            sfUserEmails.add(u.Email.toLowerCase().trim());
        }

        return sfUserEmails;
    }
}