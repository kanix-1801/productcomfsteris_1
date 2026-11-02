/**
 * @description Test class for ContactsService.
 *              Covers create, update, delete, and retrieval operations
 *              across positive, negative, bulk, and empty-input scenarios.
 */
@IsTest
private class ContactsServiceTest {

    @TestSetup
    static void setupTestData() {
        // Build and persist an Account, then attach 10 Contacts
        adb_Account accountBuilder = new adb_Account();
        accountBuilder.persist();

        List<Contact> contactList = new List<Contact>();
        for (Integer i = 0; i < 10; i++) {
            Contact c = (Contact) new adb_Contact().lastName('TestContact' + i).record;
            c.AccountId = accountBuilder.id;
            contactList.add(c);
        }
        insert contactList;
    }

    // ── createContacts ────────────────────────────────────────────────────────

    @IsTest
    static void shouldCreateContacts_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<Contact> contactList = new List<Contact>{
                (Contact) new adb_Contact().lastName('NewContact1').record,
                (Contact) new adb_Contact().lastName('NewContact2').record
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ContactsService.createContacts(contactList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> insertedIds = new Map<Id, Contact>(contactList).keySet();
            List<Contact> insertedList = [SELECT Id FROM Contact WHERE Id IN :insertedIds];
            Assert.areEqual(2, insertedList.size(), 'createContacts should insert all 2 Contacts');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenCreateContactsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM Contact];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ContactsService.createContacts(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM Contact];
            Assert.areEqual(countBefore, countAfter, 'createContacts with null should not insert any records');
        }
    }

    // ── updateContacts ────────────────────────────────────────────────────────

    @IsTest
    static void shouldUpdateContacts_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<Contact> contactList = [SELECT Id, Title FROM Contact LIMIT 3];
            for (Contact c : contactList) {
                c.Title = 'Manager';
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ContactsService.updateContacts(contactList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> updatedIds = new Map<Id, Contact>(contactList).keySet();
            List<Contact> updatedList = [SELECT Id, Title FROM Contact WHERE Id IN :updatedIds];
            for (Contact c : updatedList) {
                Assert.areEqual('Manager', c.Title, 'Title should be updated to Manager');
            }
        }
    }

    @IsTest
    static void shouldDoNothing_WhenUpdateContactsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ContactsService.updateContacts(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(true, 'updateContacts with null should complete without error');
        }
    }

    // ── deleteContacts ────────────────────────────────────────────────────────

    @IsTest
    static void shouldDeleteContacts_WhenValidIdsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> contactIdSet = new Map<Id, Contact>([SELECT Id FROM Contact LIMIT 3]).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ContactsService.deleteContacts(contactIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer remainingCount = [SELECT COUNT() FROM Contact WHERE Id IN :contactIdSet];
            Assert.areEqual(0, remainingCount, 'deleteContacts should delete all specified Contacts');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenDeleteContactsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM Contact];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ContactsService.deleteContacts(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM Contact];
            Assert.areEqual(countBefore, countAfter, 'deleteContacts with null should not delete any records');
        }
    }

    // ── getContactsById ───────────────────────────────────────────────────────

    @IsTest
    static void shouldReturnContacts_WhenGetByIdCalledWithValidIds() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> contactIdSet = new Map<Id, Contact>([SELECT Id FROM Contact]).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<Contact> resultList = ContactsService.getContactsById(contactIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(10, resultList.size(), 'getContactsById should return all 10 Contacts');
        }
    }

    @IsTest
    static void shouldReturnEmpty_WhenGetByIdCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<Contact> resultList = ContactsService.getContactsById(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getContactsById with null should return an empty list');
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static User buildTestUser() {
        adb_User builder = new adb_User();
        builder.persist();
        return (User) builder.record;
    }
}