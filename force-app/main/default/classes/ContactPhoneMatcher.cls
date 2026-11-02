/**
 * @description Contact Management from SMS: Flow Apex Action that finds every Contact matching a phone number.
 *              Channel-agnostic, so voice, SMS or any other Genesys flow can reuse it. Uses SOSL IN PHONE FIELDS,
 *              so phone formatting on the Contact does not matter.
 *              Declared without sharing by design: if the Contact exists it is found, whatever the running user's access.
 *              Never throws; failures return matchCount = 0 and errorMessage.
 * @group Contact
 */
public without sharing class ContactPhoneMatcher {
    @TestVisible
    private static final String BLANK_PHONE_MESSAGE = 'Phone is required to search for a Contact.';

    @TestVisible
    private static Boolean forceException = false;

    /**
     * @description Flow request. Phone is the customer number, ideally 10 digits.
     */
    public class Request {
        @InvocableVariable(label='Phone' description='Customer phone number, ideally 10 digits' required=true)
        public String phone;
    }

    /**
     * @description Flow result. contactId is set only when exactly one Contact matches.
     */
    public class Result {
        @InvocableVariable(label='Match Count' description='Number of Contacts matching the phone number')
        public Integer matchCount = 0;

        @InvocableVariable(label='Contact Id' description='Matching Contact Id, set only when Match Count = 1')
        public Id contactId;

        @InvocableVariable(label='Contacts' description='All matching Contacts, for the Data Table')
        public List<Contact> contacts = new List<Contact>();

        @InvocableVariable(label='Error Message' description='Set when the search could not run')
        public String errorMessage;
    }

    /**
     * @description Finds the Contacts matching each request's phone number.
     * @param requests Flow requests
     * @return One result per request, in the same order
     */
    @InvocableMethod(
        label='Find Contacts by Phone'
        description='Returns every Contact whose phone fields match the number. Contact Id is set when exactly one matches.'
        category='Contact'
    )
    public static List<Result> findContacts(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null) {
            return results;
        }

        try {
            for (Request request : requests) {
                results.add(findContacts(request == null ? null : request.phone));
            }
        } finally {
            Logger.saveLog();
        }
        return results;
    }

    /**
     * @description Runs one SOSL search for a single phone number.
     * @param phone Raw phone number
     * @return Result for the phone number
     */
    private static Result findContacts(String phone) {
        Result result = new Result();
        String searchPhone = normalizePhone(phone);
        if (String.isBlank(searchPhone)) {
            result.errorMessage = BLANK_PHONE_MESSAGE;
            return result;
        }

        try {
            if (forceException) {
                throw new ContactPhoneMatcherException('Forced exception for test');
            }

            List<List<SObject>> searchResults = [
                FIND :searchPhone
                IN PHONE FIELDS
                RETURNING Contact(Id, Name, Phone, MobilePhone, Email, AccountId, Account.Name ORDER BY Name)
            ];
            result.contacts = (List<Contact>) searchResults[0];
            result.matchCount = result.contacts.size();
            if (result.matchCount == 1) {
                result.contactId = result.contacts[0].Id;
            }
        } catch (Exception e) {
            Logger.error(new LogMessage('ContactPhoneMatcher: Contact search failed for phone {0}', searchPhone), e);
            result = new Result();
            result.errorMessage = e.getMessage();
        }
        return result;
    }

    /**
     * @description Strips formatting and the +1 country code, so '+1 (555) 123-4567' searches as '5551234567'.
     * @param phone Raw phone number
     * @return Digits only, or null when there are none
     */
    @TestVisible
    private static String normalizePhone(String phone) {
        if (String.isBlank(phone)) {
            return null;
        }
        String digits = phone.replaceAll('[^0-9]', '');
        if (digits.length() == 11 && digits.startsWith('1')) {
            digits = digits.substring(1);
        }
        return String.isBlank(digits) ? null : digits;
    }

    private class ContactPhoneMatcherException extends Exception {
    }
}