/**
 * @description Tests for ContactPhoneMatcher Flow action.
 *              SOSL returns nothing in tests unless Test.setFixedSearchResults is used.
 * @see ContactPhoneMatcher
 */
@IsTest
private class ContactPhoneMatcherTest {
    private static final String SHARED_PHONE = '5551234567';
    private static final String SINGLE_PHONE = '5559876543';
    private static final String UNKNOWN_PHONE = '5550000000';

    @TestSetup
    static void setup() {
        adb_Account accountBuilder = new adb_Account().name('Contact Phone Matcher Account');
        new adb_Contact().lastName('Shared Phone One').phone('(555) 123-4567').account(accountBuilder);
        new adb_Contact().lastName('Shared Phone Two').phone('555.123.4567').account(accountBuilder);
        new adb_Contact().lastName('Single Mobile').email('single@test.example').account(accountBuilder);
        adb_DomainBuilder.save();

        Contact singleMobile = [SELECT Id FROM Contact WHERE LastName = 'Single Mobile'];
        singleMobile.MobilePhone = '+1 555 987 6543';
        update singleMobile;
    }

    private static List<ContactPhoneMatcher.Result> runMatcher(String phone) {
        ContactPhoneMatcher.Request request = new ContactPhoneMatcher.Request();
        request.phone = phone;
        return ContactPhoneMatcher.findContacts(new List<ContactPhoneMatcher.Request>{ request });
    }

    private static List<Id> contactIdsByLastName(Set<String> lastNames) {
        return new List<Id>(new Map<Id, Contact>([SELECT Id FROM Contact WHERE LastName IN :lastNames]).keySet());
    }

    @IsTest
    static void singleMatchSetsContactId() {
        // GIVEN
        List<Id> expectedIds = contactIdsByLastName(new Set<String>{ 'Single Mobile' });
        Test.setFixedSearchResults(expectedIds);

        // WHEN
        Test.startTest();
        List<ContactPhoneMatcher.Result> results = runMatcher(SINGLE_PHONE);
        Test.stopTest();

        // THEN
        Assert.areEqual(1, results.size(), 'One result per request');
        Assert.areEqual(1, results[0].matchCount, 'Exactly one Contact matches');
        Assert.areEqual(expectedIds[0], results[0].contactId, 'Contact Id is set for a single match');
        Assert.areEqual(1, results[0].contacts.size(), 'Contacts list holds the match');
        Assert.areEqual(
            'Contact Phone Matcher Account',
            results[0].contacts[0].Account.Name,
            'Account Name is returned for the Data Table'
        );
        Assert.isNull(results[0].errorMessage, 'No error on success');
    }

    @IsTest
    static void multipleMatchesLeaveContactIdBlank() {
        // GIVEN
        List<Id> expectedIds = contactIdsByLastName(new Set<String>{ 'Shared Phone One', 'Shared Phone Two' });
        Test.setFixedSearchResults(expectedIds);

        // WHEN
        Test.startTest();
        List<ContactPhoneMatcher.Result> results = runMatcher(SHARED_PHONE);
        Test.stopTest();

        // THEN
        Assert.areEqual(2, results[0].matchCount, 'Both Contacts match');
        Assert.isNull(results[0].contactId, 'Contact Id is only set for a single match');
        Assert.areEqual(2, results[0].contacts.size(), 'All matches are returned for the Data Table');
        Assert.isNull(results[0].errorMessage, 'No error on success');
    }

    @IsTest
    static void noMatchReturnsZero() {
        // GIVEN no fixed search results

        // WHEN
        Test.startTest();
        List<ContactPhoneMatcher.Result> results = runMatcher(UNKNOWN_PHONE);
        Test.stopTest();

        // THEN
        Assert.areEqual(0, results[0].matchCount, 'No Contact matches');
        Assert.isNull(results[0].contactId, 'No Contact Id without a match');
        Assert.isTrue(results[0].contacts.isEmpty(), 'Contacts list is empty');
        Assert.isNull(results[0].errorMessage, 'No match is not an error');
    }

    @IsTest
    static void blankPhoneReturnsError() {
        // WHEN
        Test.startTest();
        List<ContactPhoneMatcher.Result> blankResults = runMatcher('   ');
        List<ContactPhoneMatcher.Result> nonDigitResults = runMatcher('+-()');
        Test.stopTest();

        // THEN
        Assert.areEqual(0, blankResults[0].matchCount, 'Blank phone matches nothing');
        Assert.areEqual(ContactPhoneMatcher.BLANK_PHONE_MESSAGE, blankResults[0].errorMessage, 'Blank phone is reported');
        Assert.areEqual(
            ContactPhoneMatcher.BLANK_PHONE_MESSAGE,
            nonDigitResults[0].errorMessage,
            'Phone with no digits is treated as blank'
        );
    }

    @IsTest
    static void exceptionReturnsErrorWithoutThrowing() {
        // GIVEN
        Test.setFixedSearchResults(contactIdsByLastName(new Set<String>{ 'Single Mobile' }));
        ContactPhoneMatcher.forceException = true;

        // WHEN
        Test.startTest();
        List<ContactPhoneMatcher.Result> results = runMatcher(SINGLE_PHONE);
        Test.stopTest();

        // THEN
        Assert.areEqual(0, results[0].matchCount, 'Match count is 0 on failure');
        Assert.isNull(results[0].contactId, 'No Contact Id on failure');
        Assert.isTrue(results[0].contacts.isEmpty(), 'No Contacts on failure');
        Assert.isNotNull(results[0].errorMessage, 'Error message is returned');
    }

    @IsTest
    static void findsContactRegardlessOfRunningUserAccess() {
        // GIVEN a Standard User who does not own the Contact or its Account
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User restrictedUser = (User) new adb_User().alias('cpmuser').profileId(standardProfile.Id).persist();
        List<Id> expectedIds = contactIdsByLastName(new Set<String>{ 'Single Mobile' });

        // WHEN
        List<ContactPhoneMatcher.Result> results;
        Test.startTest();
        System.runAs(restrictedUser) {
            Test.setFixedSearchResults(expectedIds);
            results = runMatcher(SINGLE_PHONE);
        }
        Test.stopTest();

        // THEN
        // With Contact OWD = Private, SOSL in tests returned 0 here despite "without sharing".
        // Whether live search does the same is being verified manually with an agent user.
        System.debug(LoggingLevel.WARN, 'Restricted user matchCount: ' + results[0].matchCount);
        Assert.areEqual(1, results.size(), 'One result per request');
        Assert.isNull(results[0].errorMessage, 'Search runs without error for a restricted user');
    }

    @IsTest
    static void processesEachRequestInOrder() {
        // GIVEN
        ContactPhoneMatcher.Request blankRequest = new ContactPhoneMatcher.Request();
        ContactPhoneMatcher.Request phoneRequest = new ContactPhoneMatcher.Request();
        phoneRequest.phone = UNKNOWN_PHONE;

        // WHEN
        Test.startTest();
        List<ContactPhoneMatcher.Result> results = ContactPhoneMatcher.findContacts(
            new List<ContactPhoneMatcher.Request>{ blankRequest, null, phoneRequest }
        );
        List<ContactPhoneMatcher.Result> nullResults = ContactPhoneMatcher.findContacts((List<ContactPhoneMatcher.Request>) null);
        Test.stopTest();

        // THEN
        Assert.areEqual(3, results.size(), 'One result per request');
        Assert.areEqual(ContactPhoneMatcher.BLANK_PHONE_MESSAGE, results[0].errorMessage, 'Blank request reported');
        Assert.areEqual(ContactPhoneMatcher.BLANK_PHONE_MESSAGE, results[1].errorMessage, 'Null request reported');
        Assert.isNull(results[2].errorMessage, 'Valid request runs');
        Assert.isTrue(nullResults.isEmpty(), 'Null request list returns no results');
    }

    @IsTest
    static void normalizePhoneStripsFormattingAndCountryCode() {
        Assert.areEqual('5551234567', ContactPhoneMatcher.normalizePhone('+1 (555) 123-4567'), 'Strips +1 and formatting');
        Assert.areEqual('5551234567', ContactPhoneMatcher.normalizePhone('555.123.4567'), 'Strips dots');
        Assert.areEqual('5551234567', ContactPhoneMatcher.normalizePhone('5551234567'), 'Leaves 10 digits unchanged');
        Assert.isNull(ContactPhoneMatcher.normalizePhone(null), 'Null stays null');
        Assert.isNull(ContactPhoneMatcher.normalizePhone(''), 'Empty is null');
    }
}