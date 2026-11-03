/**
 * @description GW-5874 - Service class for Contact business operations.
 *              Contact Management from SMS: matches customer phone numbers to Contacts.
 * @group Contact
 */
public with sharing class ContactsService {
    /** Contact phone fields searched by SOSL IN PHONE FIELDS, used to map each match back to its number. */
    private static final List<Schema.SObjectField> PHONE_FIELD_LIST = new List<Schema.SObjectField>{
        Contact.Phone,
        Contact.MobilePhone,
        Contact.HomePhone,
        Contact.OtherPhone,
        Contact.AssistantPhone,
        Contact.Fax
    };

    @TestVisible
    private static Boolean forceException = false;

    /**
     * @description Finds the Contacts matching each phone number with a single SOSL search, so the call is safe
     *              for a full trigger batch. Fields the running user cannot read are stripped from the results.
     * @param phoneSet Normalized phone numbers (see PlatformUtilities.normalizePhone)
     * @return Matching Contacts by normalized phone; a number with no match has no key
     */
    public static Map<String, List<Contact>> findContactsByPhones(Set<String> phoneSet) {
        Map<String, List<Contact>> contactsByPhoneMap = new Map<String, List<Contact>>();
        if (phoneSet == null || phoneSet.isEmpty()) {
            return contactsByPhoneMap;
        }
        if (forceException) {
            throw new ContactsServiceException('Forced exception for test');
        }

        List<Contact> contactList = ContactsSelector.searchByPhones(phoneSet);
        List<Contact> readableContactList = (List<Contact>) Security.stripInaccessible(
                AccessType.READABLE,
                contactList
            )
            .getRecords();

        for (Integer i = 0; i < contactList.size(); i++) {
            for (String phone : getNormalizedPhoneSet(contactList[i])) {
                if (!phoneSet.contains(phone)) {
                    continue;
                }
                if (!contactsByPhoneMap.containsKey(phone)) {
                    contactsByPhoneMap.put(phone, new List<Contact>());
                }
                contactsByPhoneMap.get(phone).add(readableContactList[i]);
            }
        }
        return contactsByPhoneMap;
    }

    /**
     * @description Normalized values of every phone field on the Contact. Read from the unstripped record so the
     *              match does not depend on the running user's field access.
     * @param contactRecord Contact returned by the search
     * @return Distinct normalized phone numbers
     */
    private static Set<String> getNormalizedPhoneSet(Contact contactRecord) {
        Set<String> phoneSet = new Set<String>();
        for (Schema.SObjectField phoneField : PHONE_FIELD_LIST) {
            String phone = PlatformUtilities.normalizePhone((String) contactRecord.get(phoneField));
            if (phone != null) {
                phoneSet.add(phone);
            }
        }
        return phoneSet;
    }

    /**
     * @description Business exception for Contact operations.
     */
    public class ContactsServiceException extends Exception {
    }
}