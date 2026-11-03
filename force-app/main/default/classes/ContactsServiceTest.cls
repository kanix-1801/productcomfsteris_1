/**
 * @description GW-5874 - Tests for ContactsService.findContactsByPhones.
 *              SOSL returns nothing in tests unless Test.setFixedSearchResults is used.
 * @see ContactsService
 */
@isTest(SeeAllData=false)
private class ContactsServiceTest {
    private static final String OFFICE_PHONE = '5551234567';
    private static final String MOBILE_PHONE = '5559876543';

    @TestSetup
    static void setup() {
        adb_Account accountBuilder = new adb_Account().name('Contacts Service Account');
        new adb_Contact().lastName('Office Phone').phone('(555) 123-4567').account(accountBuilder);
        new adb_Contact().lastName('Mobile Phone').email('mobile@test.example').account(accountBuilder);
        adb_DomainBuilder.save();

        Contact mobileContact = [SELECT Id FROM Contact WHERE LastName = 'Mobile Phone'];
        mobileContact.MobilePhone = '+1 555 987 6543';
        update mobileContact;
    }

    @IsTest
    static void mapsEachContactToItsPhone() {
        // GIVEN
        Map<Id, Contact> contactByIdMap = new Map<Id, Contact>([SELECT Id, LastName FROM Contact]);
        Test.setFixedSearchResults(new List<Id>(contactByIdMap.keySet()));

        // WHEN
        Test.startTest();
        Map<String, List<Contact>> contactsByPhoneMap = ContactsService.findContactsByPhones(
            new Set<String>{ OFFICE_PHONE, MOBILE_PHONE }
        );
        Test.stopTest();

        // THEN
        Assert.areEqual(2, contactsByPhoneMap.size(), 'Both numbers match');
        Assert.areEqual(1, contactsByPhoneMap.get(OFFICE_PHONE).size(), 'Office number matches one Contact');
        Assert.areEqual(
            'Office Phone',
            contactByIdMap.get(contactsByPhoneMap.get(OFFICE_PHONE)[0].Id).LastName,
            'Office number maps to the Contact holding it in Phone'
        );
        Assert.areEqual(
            'Mobile Phone',
            contactByIdMap.get(contactsByPhoneMap.get(MOBILE_PHONE)[0].Id).LastName,
            'Mobile number maps to the Contact holding it in MobilePhone'
        );
    }

    @IsTest
    static void emptyPhoneSetRunsNoSearch() {
        // WHEN
        Test.startTest();
        Map<String, List<Contact>> nullResultMap = ContactsService.findContactsByPhones(null);
        Map<String, List<Contact>> emptyResultMap = ContactsService.findContactsByPhones(new Set<String>());
        Integer soslQueryCount = Limits.getSoslQueries();
        Test.stopTest();

        // THEN
        Assert.isTrue(nullResultMap.isEmpty(), 'Null phone set returns no matches');
        Assert.isTrue(emptyResultMap.isEmpty(), 'Empty phone set returns no matches');
        Assert.areEqual(0, soslQueryCount, 'No search runs without phone numbers');
    }

    @IsTest
    static void forcedExceptionIsThrown() {
        // GIVEN
        ContactsService.forceException = true;

        // WHEN
        Exception caughtException;
        Test.startTest();
        try {
            ContactsService.findContactsByPhones(new Set<String>{ OFFICE_PHONE });
        } catch (ContactsService.ContactsServiceException e) {
            caughtException = e;
        }
        Test.stopTest();

        // THEN
        Assert.isNotNull(caughtException, 'Service surfaces the failure to the caller');
    }
}