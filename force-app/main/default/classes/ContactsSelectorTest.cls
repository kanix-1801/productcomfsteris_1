/**
 * @description Test class for ContactsSelector.
 *              Covers Contact selection by Id, Account Id, and Email.
 *              Includes GC-2868 AC6 Contact retrieval functionality.
 */
@IsTest
private class ContactsSelectorTest {

    /**
     * @description Creates reusable test data.
     */
    @TestSetup
    static void setupTestData() {

        Account account1 = new Account(
            Name = 'Test Customer Account 1'
        );

        Account account2 = new Account(
            Name = 'Test Customer Account 2'
        );

        insert new List<Account>{
            account1,
            account2
        };

        List<Contact> contacts = new List<Contact>{
            new Contact(
                FirstName = 'John',
                LastName = 'Smith',
                Email = 'john.smith@testexample.com',
                Phone = '1234567890',
                Title = 'Manager',
                Department = 'Sales',
                AccountId = account1.Id
            ),
            new Contact(
                FirstName = 'Alice',
                LastName = 'Brown',
                Email = 'alice.brown@testexample.com',
                Phone = '1234567891',
                Title = 'Director',
                Department = 'Marketing',
                AccountId = account1.Id
            ),
            new Contact(
                FirstName = 'David',
                LastName = 'Wilson',
                Email = 'david.wilson@testexample.com',
                Phone = '1234567892',
                Title = 'Executive',
                Department = 'Operations',
                AccountId = account2.Id
            )
        };

        insert contacts;
    }

    /**
     * @description Tests selectById with valid Contact Ids.
     */
    @IsTest
    static void testSelectById() {

        List<Contact> contacts = [
            SELECT Id
            FROM Contact
            WHERE Email IN (
                'john.smith@testexample.com',
                'alice.brown@testexample.com'
            )
        ];

        Set<Id> contactIds = new Set<Id>();

        for (Contact con : contacts) {
            contactIds.add(con.Id);
        }

        Test.startTest();

        List<Contact> results =
            ContactsSelector.selectById(contactIds);

        Test.stopTest();

        System.Assert.areEqual(
            2,
            results.size(),
            'Two Contacts should be returned.'
        );

        for (Contact con : results) {
            System.Assert.isTrue(
                contactIds.contains(con.Id),
                'Returned Contact must match the requested Ids.'
            );

            System.Assert.isNotNull(
                con.Email,
                'Contact Email should be populated.'
            );
        }
    }

    /**
     * @description Tests selectById with null and empty sets.
     */
    @IsTest
    static void testSelectByIdNullAndEmpty() {

        Test.startTest();

        List<Contact> nullResults =
            ContactsSelector.selectById(null);

        List<Contact> emptyResults =
            ContactsSelector.selectById(new Set<Id>());

        Test.stopTest();

        System.Assert.areEqual(
            0,
            nullResults.size(),
            'Null input should return an empty list.'
        );

        System.Assert.areEqual(
            0,
            emptyResults.size(),
            'Empty input should return an empty list.'
        );
    }

    /**
     * @description GC-2868 AC6:
     *              Tests Contacts associated with Customer Accounts.
     */
    @IsTest
    static void testSelectByAccountIds() {

        List<Account> accounts = [
            SELECT Id, Name
            FROM Account
            WHERE Name LIKE 'Test Customer Account%'
        ];

        Set<Id> accountIds = new Set<Id>();

        for (Account acc : accounts) {
            accountIds.add(acc.Id);
        }

        Test.startTest();

        List<Contact> results =
            ContactsSelector.selectByAccountIds(accountIds);

        Test.stopTest();

        System.Assert.areEqual(
            3,
            results.size(),
            'Three Contacts should be returned.'
        );

        for (Contact con : results) {

            System.Assert.isTrue(
                accountIds.contains(con.AccountId),
                'Contact must belong to the requested Account.'
            );

            System.Assert.isNotNull(
                con.Account.Name,
                'Account Name should be retrieved.'
            );

            System.Assert.isNotNull(
                con.Owner.Name,
                'Contact Owner Name should be retrieved.'
            );
        }

        System.Assert.areEqual(
            'Brown',
            results[0].LastName,
            'Contacts should be sorted by Account and Last Name.'
        );

        System.Assert.areEqual(
            'Smith',
            results[1].LastName,
            'Contacts should be sorted by Account and Last Name.'
        );

        System.Assert.areEqual(
            'Wilson',
            results[2].LastName,
            'Contacts from the second Account should appear last.'
        );
    }

    /**
     * @description Tests selectByAccountIds with null and empty sets.
     */
    @IsTest
    static void testSelectByAccountIdsNullAndEmpty() {

        Test.startTest();

        List<Contact> nullResults =
            ContactsSelector.selectByAccountIds(null);

        List<Contact> emptyResults =
            ContactsSelector.selectByAccountIds(new Set<Id>());

        Test.stopTest();

        System.Assert.areEqual(
            0,
            nullResults.size(),
            'Null Account Id set should return no Contacts.'
        );

        System.Assert.areEqual(
            0,
            emptyResults.size(),
            'Empty Account Id set should return no Contacts.'
        );
    }

    /**
     * @description Tests selectByAccountId.
     */
    @IsTest
    static void testSelectByAccountId() {

        Account accountRecord = [
            SELECT Id
            FROM Account
            WHERE Name = 'Test Customer Account 1'
            LIMIT 1
        ];

        Test.startTest();

        List<Contact> results =
            ContactsSelector.selectByAccountId(
                new Set<Id>{ accountRecord.Id }
            );

        Test.stopTest();

        System.Assert.areEqual(
            2,
            results.size(),
            'Two Contacts should belong to Account 1.'
        );

        System.Assert.areEqual(
            'Brown',
            results[0].LastName,
            'Contacts should be ordered by LastName.'
        );

        System.Assert.areEqual(
            'Smith',
            results[1].LastName,
            'Contacts should be ordered by LastName.'
        );

        for (Contact con : results) {
            System.Assert.areEqual(
                accountRecord.Id,
                con.AccountId,
                'Returned Contact must belong to Account 1.'
            );
        }
    }

    /**
     * @description Tests selectByAccountId with null and empty sets.
     */
    @IsTest
    static void testSelectByAccountIdNullAndEmpty() {

        Test.startTest();

        List<Contact> nullResults =
            ContactsSelector.selectByAccountId(null);

        List<Contact> emptyResults =
            ContactsSelector.selectByAccountId(new Set<Id>());

        Test.stopTest();

        System.Assert.areEqual(
            0,
            nullResults.size(),
            'Null input should return no Contacts.'
        );

        System.Assert.areEqual(
            0,
            emptyResults.size(),
            'Empty input should return no Contacts.'
        );
    }

    /**
     * @description Tests selectByEmail with matching Email addresses.
     */
    @IsTest
    static void testSelectByEmail() {

        Set<String> emails = new Set<String>{
            'john.smith@testexample.com',
            'david.wilson@testexample.com'
        };

        Test.startTest();

        List<Contact> results =
            ContactsSelector.selectByEmail(emails);

        Test.stopTest();

        System.Assert.areEqual(
            2,
            results.size(),
            'Two Contacts should match the supplied Emails.'
        );

        for (Contact con : results) {
            System.Assert.isTrue(
                emails.contains(con.Email),
                'Returned Contact Email must match the input.'
            );
        }
    }

    /**
     * @description Tests selectByEmail with null and empty sets.
     */
    @IsTest
    static void testSelectByEmailNullAndEmpty() {

        Test.startTest();

        List<Contact> nullResults =
            ContactsSelector.selectByEmail(null);

        List<Contact> emptyResults =
            ContactsSelector.selectByEmail(new Set<String>());

        Test.stopTest();

        System.Assert.areEqual(
            0,
            nullResults.size(),
            'Null Email set should return an empty list.'
        );

        System.Assert.areEqual(
            0,
            emptyResults.size(),
            'Empty Email set should return an empty list.'
        );
    }

    /**
     * @description Tests selectByEmail when no Contacts match.
     */
    @IsTest
    static void testSelectByEmailNoMatch() {

        Test.startTest();

        List<Contact> results =
            ContactsSelector.selectByEmail(
                new Set<String>{
                    'notfound@testexample.com'
                }
            );

        Test.stopTest();

        System.Assert.areEqual(
            0,
            results.size(),
            'No Contacts should be returned for an unmatched Email.'
        );
    }

    /**
     * @description Tests selectById when Contact Id does not exist.
     */
    @IsTest
    static void testSelectByIdNoMatch() {

        Account accountRecord = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];

        Test.startTest();

        List<Contact> results =
            ContactsSelector.selectById(
                new Set<Id>{ accountRecord.Id }
            );

        Test.stopTest();

        System.Assert.areEqual(
            0,
            results.size(),
            'No Contacts should match an Account Id.'
        );
    }
}