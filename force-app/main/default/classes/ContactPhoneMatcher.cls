/**
 * @description GW-5874 - Contact Management from SMS: Flow Apex Action that finds every Contact matching a phone
 *              number. Channel-agnostic, so voice, SMS or any other Genesys flow can reuse it.
 *              Thin entry point: translates Flow requests and results; matching is done by ContactsService.
 *              Never throws; failures return matchCount = 0 and errorMessage.
 * @group Contact
 */
public with sharing class ContactPhoneMatcher {
    @TestVisible
    private static final String BLANK_PHONE_MESSAGE = 'Phone is required to search for a Contact.';

    /**
     * @description Flow request. Phone is the customer number, ideally 10 digits.
     */
    public class Request {
        @InvocableVariable(label='Phone' description='Customer phone number, ideally 10 digits' required=true)
        public String phone;

        @InvocableVariable(label='Record Id' description='Record the search is for (e.g. the SMS), used in logs')
        public Id recordId;
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
     * @description Finds the Contacts matching each request's phone number, using one search for all requests.
     * @param requestList Flow requests
     * @return One result per request, in the same order
     */
    @InvocableMethod(
        label='Find Contacts by Phone'
        description='Returns every Contact whose phone fields match the number. Contact Id is set on a single match.'
        category='Contact'
    )
    public static List<Result> findContacts(List<Request> requestList) {
        List<Result> resultList = new List<Result>();
        if (requestList == null) {
            return resultList;
        }

        List<String> phoneList = new List<String>();
        Set<String> phoneSet = new Set<String>();
        for (Request request : requestList) {
            String phone = PlatformUtilities.normalizePhone(request == null ? null : request.phone);
            phoneList.add(phone);
            if (phone != null) {
                phoneSet.add(phone);
            }
        }

        try {
            Map<String, List<Contact>> contactsByPhoneMap = ContactsService.findContactsByPhones(phoneSet);
            for (String phone : phoneList) {
                resultList.add(buildResult(phone, contactsByPhoneMap.get(phone)));
            }
        } catch (Exception e) {
            resultList = buildErrorResults(requestList, phoneList, e);
        } finally {
            Logger.saveLog();
        }
        return resultList;
    }

    /**
     * @description Builds the result for one phone number.
     * @param phone Normalized phone number, or null when the request had none
     * @param contactList Contacts matching the phone number, or null when none match
     * @return Result for the request
     */
    private static Result buildResult(String phone, List<Contact> contactList) {
        Result result = new Result();
        if (phone == null) {
            result.errorMessage = BLANK_PHONE_MESSAGE;
            return result;
        }
        if (contactList != null) {
            result.contacts = contactList;
            result.matchCount = contactList.size();
        }
        if (result.matchCount == 1) {
            result.contactId = result.contacts[0].Id;
        }
        return result;
    }

    /**
     * @description Logs the failed search against each affected record and returns an error result per request.
     * @param requestList Flow requests
     * @param phoneList Normalized phone number per request
     * @param searchException Exception raised by the search
     * @return One error result per request, in the same order
     */
    private static List<Result> buildErrorResults(
        List<Request> requestList,
        List<String> phoneList,
        Exception searchException
    ) {
        List<Result> resultList = new List<Result>();
        for (Integer i = 0; i < requestList.size(); i++) {
            Result result = new Result();
            result.errorMessage = phoneList[i] == null ? BLANK_PHONE_MESSAGE : searchException.getMessage();
            resultList.add(result);

            Id recordId = requestList[i] == null ? null : requestList[i].recordId;
            Logger.error('ContactPhoneMatcher.findContacts: Contact search by phone failed', searchException)
                .setRecord(recordId);
        }
        return resultList;
    }
}