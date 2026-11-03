/**
 * @description GW-5874 - Tests for the ContactPhoneMatcher Flow action, ContactsService.findContactsByPhones and
 *              ContactsSelector.searchByPhones. SOSL returns nothing in tests unless Test.setFixedSearchResults is
 *              used; the fixed results are then mapped back to each request by their phone fields.
 * @see ContactPhoneMatcher
 */
@isTest(SeeAllData=false)
private class ContactPhoneMatcherTest {
    private static final String SHARED_PHONE = '5551234567';
    private static final String SINGLE_PHONE = '5559876543';
    private static final String UNKNOWN_PHONE = '5550000000';
    private static final Integer BULK_REQUEST_COUNT = 200;

    @TestSetup
    static void setup() {
        adb_Account accountBuilder = new adb_Account().name('Contact Phone Matcher Account');
        new adb_Contact().lastName('Shared Phone One').phone('(555) 123-4567').account(accountBuilder);
        new adb_Contact().lastName('Shared Phone Two').phone('555.123.4567').account(accountBuilder);
        new adb_Contact().lastName('Single Mobile').email('single@test.example').account(accountBuilder);
        adb_DomainBuilder.save();

        Contact singleMobileContact = [SELECT Id FROM Contact WHERE LastName = 'Single Mobile'];
        singleMobileContact.MobilePhone = '+1 555 987 6543';
        update singleMobileContact;
    }

    private static List<ContactPhoneMatcher.Result> runMatcher(String phone) {
        ContactPhoneMatcher.Request request = new ContactPhoneMatcher.Request();
        request.phone = phone;
        return ContactPhoneMatcher.findContacts(new List<ContactPhoneMatcher.Request>{ request });
    }

    private static List<Id> getContactIdsByLastName(Set<String> lastNameSet) {
        return new List<Id>(new Map<Id, Contact>([SELECT Id FROM Contact WHERE LastName IN :lastNameSet]).keySet());
    }

    @IsTest
    static void singleMatchSetsContactId() {
        // GIVEN
        List<Id> expectedIdList = getContactIdsByLastName(new Set<String>{ 'Single Mobile' });
        Test.setFixedSearchResults(expectedIdList);

        // WHEN
        Test.startTest();
        List<ContactPhoneMatcher.Result> resultList = runMatcher(SINGLE_PHONE);
        Test.stopTest();

        // THEN
        Assert.areEqual(1, resultList.size(), 'One result per request');
        Assert.areEqual(1, resultList[0].matchCount, 'Exactly one Contact matches');
        Assert.areEqual(expectedIdList[0], resultList[0].contactId, 'Contact Id is set for a single match');
        Assert.areEqual(1, resultList[0].contacts.size(), 'Contacts list holds the match');
        Assert.areEqual(
            'Contact Phone Matcher Account',
            resultList[0].contacts[0].Account.Name,
            'Account Name is returned for the Data Table'
        );
        Assert.isNull(resultList[0].errorMessage, 'No error on success');
    }

    @IsTest
    static void multipleMatchesLeaveContactIdBlank() {
        // GIVEN
        Test.setFixedSearchResults(getContactIdsByLastName(new Set<String>{ 'Shared Phone One', 'Shared Phone Two' }));

        // WHEN
        Test.startTest();
        List<ContactPhoneMatcher.Result> resultList = runMatcher(SHARED_PHONE);
        Test.stopTest();

        // THEN
        Assert.areEqual(2, resultList[0].matchCount, 'Both Contacts match');
        Assert.isNull(resultList[0].contactId, 'Contact Id is only set for a single match');
        Assert.areEqual(2, resultList[0].contacts.size(), 'All matches are returned for the Data Table');
        Assert.isNull(resultList[0].errorMessage, 'No error on success');
    }

    @IsTest
    static void noMatchReturnsZero() {
        // GIVEN no fixed search results

        // WHEN
        Test.startTest();
        List<ContactPhoneMatcher.Result> resultList = runMatcher(UNKNOWN_PHONE);
        Test.stopTest();

        // THEN
        Assert.areEqual(0, resultList[0].matchCount, 'No Contact matches');
        Assert.isNull(resultList[0].contactId, 'No Contact Id without a match');
        Assert.isTrue(resultList[0].contacts.isEmpty(), 'Contacts list is empty');
        Assert.isNull(resultList[0].errorMessage, 'No match is not an error');
    }

    @IsTest
    static void searchResultNotMatchingThePhoneIsIgnored() {
        // GIVEN the search returns a Contact whose phone fields do not hold the requested number
        Test.setFixedSearchResults(getContactIdsByLastName(new Set<String>{ 'Single Mobile' }));

        // WHEN
        Test.startTest();
        List<ContactPhoneMatcher.Result> resultList = runMatcher(SHARED_PHONE);
        Test.stopTest();

        // THEN
        Assert.areEqual(0, resultList[0].matchCount, 'Only Contacts holding the number are matched');
        Assert.isNull(resultList[0].errorMessage, 'No error on success');
    }

    @IsTest
    static void blankPhoneReturnsError() {
        // WHEN
        Test.startTest();
        List<ContactPhoneMatcher.Result> blankResultList = runMatcher('   ');
        List<ContactPhoneMatcher.Result> nonDigitResultList = runMatcher('+-()');
        Test.stopTest();

        // THEN
        Assert.areEqual(0, blankResultList[0].matchCount, 'Blank phone matches nothing');
        Assert.areEqual(
            ContactPhoneMatcher.BLANK_PHONE_MESSAGE,
            blankResultList[0].errorMessage,
            'Blank phone is reported'
        );
        Assert.areEqual(
            ContactPhoneMatcher.BLANK_PHONE_MESSAGE,
            nonDigitResultList[0].errorMessage,
            'Phone with no digits is treated as blank'
        );
    }

    @IsTest
    static void exceptionReturnsErrorWithoutThrowing() {
        // GIVEN
        Test.setFixedSearchResults(getContactIdsByLastName(new Set<String>{ 'Single Mobile' }));
        ContactsService.forceException = true;
        ContactPhoneMatcher.Request request = new ContactPhoneMatcher.Request();
        request.phone = SINGLE_PHONE;
        request.recordId = getContactIdsByLastName(new Set<String>{ 'Single Mobile' })[0];

        // WHEN
        Test.startTest();
        List<ContactPhoneMatcher.Result> resultList = ContactPhoneMatcher.findContacts(
            new List<ContactPhoneMatcher.Request>{ request }
        );
        Test.stopTest();

        // THEN
        Assert.areEqual(0, resultList[0].matchCount, 'Match count is 0 on failure');
        Assert.isNull(resultList[0].contactId, 'No Contact Id on failure');
        Assert.isTrue(resultList[0].contacts.isEmpty(), 'No Contacts on failure');
        Assert.isNotNull(resultList[0].errorMessage, 'Error message is returned');
    }

    @IsTest
    static void searchRunsForRestrictedUser() {
        // GIVEN a Standard User who does not own the Contact or its Account
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User restrictedUser = (User) new adb_User().alias('cpmuser').profileId(standardProfile.Id).persist();
        List<Id> expectedIdList = getContactIdsByLastName(new Set<String>{ 'Single Mobile' });

        // WHEN
        List<ContactPhoneMatcher.Result> resultList;
        Test.startTest();
        System.runAs(restrictedUser) {
            Test.setFixedSearchResults(expectedIdList);
            resultList = runMatcher(SINGLE_PHONE);
        }
        Test.stopTest();

        // THEN
        Assert.areEqual(1, resultList.size(), 'One result per request');
        Assert.isNull(resultList[0].errorMessage, 'Search runs without error for a restricted user');
    }

    @IsTest
    static void processesEachRequestInOrder() {
        // GIVEN
        ContactPhoneMatcher.Request blankRequest = new ContactPhoneMatcher.Request();
        ContactPhoneMatcher.Request phoneRequest = new ContactPhoneMatcher.Request();
        phoneRequest.phone = UNKNOWN_PHONE;

        // WHEN
        Test.startTest();
        List<ContactPhoneMatcher.Result> resultList = ContactPhoneMatcher.findContacts(
            new List<ContactPhoneMatcher.Request>{ blankRequest, null, phoneRequest }
        );
        List<ContactPhoneMatcher.Result> nullResultList = ContactPhoneMatcher.findContacts(
            (List<ContactPhoneMatcher.Request>) null
        );
        Test.stopTest();

        // THEN
        Assert.areEqual(3, resultList.size(), 'One result per request');
        Assert.areEqual(ContactPhoneMatcher.BLANK_PHONE_MESSAGE, resultList[0].errorMessage, 'Blank request reported');
        Assert.areEqual(ContactPhoneMatcher.BLANK_PHONE_MESSAGE, resultList[1].errorMessage, 'Null request reported');
        Assert.isNull(resultList[2].errorMessage, 'Valid request runs');
        Assert.isTrue(nullResultList.isEmpty(), 'Null request list returns no results');
    }

    @IsTest
    static void bulkRequestsUseOneSearch() {
        // GIVEN a full trigger batch alternating between the shared and the single phone number
        Test.setFixedSearchResults(
            getContactIdsByLastName(new Set<String>{ 'Shared Phone One', 'Shared Phone Two', 'Single Mobile' })
        );
        List<ContactPhoneMatcher.Request> requestList = new List<ContactPhoneMatcher.Request>();
        for (Integer i = 0; i < BULK_REQUEST_COUNT; i++) {
            ContactPhoneMatcher.Request request = new ContactPhoneMatcher.Request();
            request.phone = Math.mod(i, 2) == 0 ? SHARED_PHONE : '+1 ' + SINGLE_PHONE;
            requestList.add(request);
        }

        // WHEN
        Test.startTest();
        List<ContactPhoneMatcher.Result> resultList = ContactPhoneMatcher.findContacts(requestList);
        Integer soslQueryCount = Limits.getSoslQueries();
        Test.stopTest();

        // THEN
        Assert.areEqual(1, soslQueryCount, 'One SOSL search serves the whole batch');
        Assert.areEqual(BULK_REQUEST_COUNT, resultList.size(), 'One result per request');
        for (Integer i = 0; i < BULK_REQUEST_COUNT; i++) {
            Integer expectedMatchCount = Math.mod(i, 2) == 0 ? 2 : 1;
            Assert.areEqual(expectedMatchCount, resultList[i].matchCount, 'Result ' + i + ' maps to its own phone');
        }
    }
}