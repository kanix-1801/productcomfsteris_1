/**
 * @description Test class for ContentDocumentLinkTriggerHandler.
 *
 *              ContentDocumentLink trigger context coverage:
 *                - VALID:   before insert, after insert, before delete, after delete
 *                - INVALID: before update, after update (ContentDocumentLink is immutable after creation)
 *                           after undelete (ContentDocumentLink records cannot be undeleted)
 *
 *              ContentDocumentLink records are created by linking a ContentDocument to a Salesforce
 *              record via LinkedEntityId. Documents are created indirectly through ContentVersion.
 *              A ContentDocumentLink is permanently deleted when removed — it cannot be undeleted.
 */
@IsTest
private class ContentDocumentLinkTriggerHandlerTest {

    // ── Test Setup ────────────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        // Insert a ContentVersion to implicitly create a parent ContentDocument.
        // Do NOT insert a ContentDocumentLink in setup — insert tests need a clean slate.
        adb_ContentVersion cvBuilder = new adb_ContentVersion();
        ContentVersion cv = (ContentVersion) cvBuilder.record;
        insert cv;

        // Insert a target Account to use as the LinkedEntityId for ContentDocumentLink records.
        adb_Account acctBuilder = new adb_Account();
        acctBuilder.persist();
    }

    // ── Helper ────────────────────────────────────────────────────────────────

    private static User buildTestUser() {
        adb_User builder = new adb_User();
        builder.persist();
        return (User) builder.record;
    }

    // ── Before Insert / After Insert ──────────────────────────────────────────

    /**
     * @description Verifies that the before insert and after insert trigger contexts fire without
     *              error when a ContentDocumentLink is inserted.
     *
     *              NOTE: Update trigger contexts do NOT fire for ContentDocumentLink. Once inserted,
     *              a ContentDocumentLink is immutable — to change ShareType or Visibility you must
     *              delete the old link and insert a new one.
     */
    @IsTest
    static void shouldFireInsertContexts_WhenContentDocumentLinkIsInserted() {
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            // GIVEN: a ContentDocument and a target Account from test setup
            ContentVersion cv = [SELECT Id, ContentDocumentId FROM ContentVersion LIMIT 1];
            Account acct = [SELECT Id FROM Account LIMIT 1];

            ContentDocumentLink cdl = (ContentDocumentLink) new adb_ContentDocumentLink()
                .contentDocumentId(cv.ContentDocumentId)
                .linkedEntityId(acct.Id)
                .record;

            // WHEN: the ContentDocumentLink is inserted (fires before insert, after insert)
            Test.startTest();
            insert cdl;
            Test.stopTest();

            // THEN: the link was committed and is queryable
            Integer count = [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE ContentDocumentId = :cv.ContentDocumentId
                AND LinkedEntityId = :acct.Id
            ];
            System.Assert.isTrue(count > 0, 'ContentDocumentLink should have been created successfully.');
        }
    }

    // ── Before Delete / After Delete ──────────────────────────────────────────

    /**
     * @description Verifies that the before delete and after delete trigger contexts fire without
     *              error when a ContentDocumentLink is deleted.
     *
     *              NOTE: After undelete does NOT fire for ContentDocumentLink — the link cannot be
     *              undeleted once removed. Re-creating the link is the only option.
     */
    @IsTest
    static void shouldFireDeleteContexts_WhenContentDocumentLinkIsDeleted() {
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            // GIVEN: a ContentDocumentLink created between the document and the Account
            ContentVersion cv = [SELECT Id, ContentDocumentId FROM ContentVersion LIMIT 1];
            Account acct = [SELECT Id FROM Account LIMIT 1];

            ContentDocumentLink cdl = (ContentDocumentLink) new adb_ContentDocumentLink()
                .contentDocumentId(cv.ContentDocumentId)
                .linkedEntityId(acct.Id)
                .record;
            insert cdl;

            // Re-query to get the persisted Id (ContentDocumentLink Id may not auto-populate on the variable)
            ContentDocumentLink persisted = [
                SELECT Id
                FROM ContentDocumentLink
                WHERE ContentDocumentId = :cv.ContentDocumentId
                AND LinkedEntityId = :acct.Id
                LIMIT 1
            ];

            // WHEN: the ContentDocumentLink is deleted (fires before delete, after delete)
            Test.startTest();
            delete persisted;
            Test.stopTest();

            // THEN: the link no longer exists (ContentDocumentLink cannot be undeleted)
            Integer count = [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE ContentDocumentId = :cv.ContentDocumentId
                AND LinkedEntityId = :acct.Id
            ];
            System.Assert.areEqual(0, count, 'ContentDocumentLink should have been permanently deleted.');
        }
    }

    // ── Bulk Insert ───────────────────────────────────────────────────────────

    /**
     * @description Verifies that the handler processes bulk ContentDocumentLink insertions
     *              without hitting governor limits.
     */
    @IsTest
    static void shouldHandleBulkInsert_WhenManyLinksAreCreated() {
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            // GIVEN: 10 Accounts to link to the same ContentDocument
            ContentVersion cv = [SELECT Id, ContentDocumentId FROM ContentVersion LIMIT 1];
            List<Account> accounts = new List<Account>();

            // Build accounts for bulk linking
            for (Integer i = 0; i < 10; i++) {
                accounts.add((Account) new adb_Account().record);
            }
            insert accounts;

            List<ContentDocumentLink> links = new List<ContentDocumentLink>();
            // Build ContentDocumentLink records for each account
            for (Account acct : accounts) {
                links.add((ContentDocumentLink) new adb_ContentDocumentLink()
                    .contentDocumentId(cv.ContentDocumentId)
                    .linkedEntityId(acct.Id)
                    .record);
            }

            // WHEN: all links are inserted in bulk (fires before insert, after insert for each)
            Test.startTest();
            insert links;
            Test.stopTest();

            // THEN: all 10 links were created
            Integer count = [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE ContentDocumentId = :cv.ContentDocumentId
            ];
            System.Assert.areEqual(11, count, 'All 11 ContentDocumentLinks should have been created.');
        }
    }

    // ── Bypass ────────────────────────────────────────────────────────────────

    /**
     * @description Verifies that the TriggerHandler bypass mechanism suppresses handler logic
     *              for ContentDocumentLinkTrigger without causing errors.
     */
    @IsTest
    static void shouldBypassHandler_WhenTriggerIsBypassed() {
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            // GIVEN: a ContentDocument, an Account, and the trigger bypassed
            ContentVersion cv = [SELECT Id, ContentDocumentId FROM ContentVersion LIMIT 1];
            Account acct = [SELECT Id FROM Account LIMIT 1];
            TriggerHandler.bypass('ContentDocumentLinkTriggerHandler');

            ContentDocumentLink cdl = (ContentDocumentLink) new adb_ContentDocumentLink()
                .contentDocumentId(cv.ContentDocumentId)
                .linkedEntityId(acct.Id)
                .record;

            // WHEN: a link is inserted while the handler is bypassed
            Test.startTest();
            insert cdl;
            Test.stopTest();

            // THEN: the insert succeeded; clear the bypass for other tests
            TriggerHandler.clearBypass('ContentDocumentLinkTriggerHandler');
            Integer count = [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE ContentDocumentId = :cv.ContentDocumentId
                AND LinkedEntityId = :acct.Id
            ];
            System.Assert.isTrue(count > 0, 'Link should be created even when handler is bypassed.');
        }
    }
}