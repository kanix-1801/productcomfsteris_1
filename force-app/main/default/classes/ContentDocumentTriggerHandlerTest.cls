/**
 * @description Test class for ContentDocumentTriggerHandler.
 *
 *              ContentDocument trigger context coverage:
 *                - VALID:   before update, before delete, after update, after delete, after undelete
 *                - INVALID: before insert, after insert (ContentDocument has no insert trigger context)
 *
 *              ContentDocument records cannot be inserted directly. All tests create documents
 *              implicitly by inserting a ContentVersion, then operate on the resulting ContentDocument.
 */
@IsTest
private class ContentDocumentTriggerHandlerTest {

    // ── Test Setup ────────────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        // Insert a ContentVersion, which implicitly creates a ContentDocument.
        adb_ContentVersion cvBuilder = new adb_ContentVersion();
        ContentVersion cv = (ContentVersion) cvBuilder.record;
        insert cv;
    }

    // ── Helper ────────────────────────────────────────────────────────────────

    private static User buildTestUser() {
        User runningUser = [
            SELECT Id, ProfileId, TimeZoneSidKey, LocaleSidKey, EmailEncodingKey, LanguageLocaleKey
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];
        User testUser = new User(
            Alias             = 'cdtst',
            Email             = 'cd.triggertest@example.com.invalid',
            EmailEncodingKey  = runningUser.EmailEncodingKey,
            LastName          = 'ContentDocTriggerTest',
            LanguageLocaleKey = runningUser.LanguageLocaleKey,
            LocaleSidKey      = runningUser.LocaleSidKey,
            ProfileId         = runningUser.ProfileId,
            TimeZoneSidKey    = runningUser.TimeZoneSidKey,
            UserName          = 'cd.triggertest.' + System.currentTimeMillis() + '@example.com.invalid'
        );
        insert testUser;
        return testUser;
    }

    // ── Before Update / After Update ──────────────────────────────────────────

    /**
     * @description Verifies that the before update and after update trigger contexts fire without
     *              error when a ContentDocument is updated.
     */
    @IsTest
    static void shouldFireUpdateContexts_WhenContentDocumentIsUpdated() {
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            // GIVEN: a ContentDocument created from the test setup ContentVersion
            ContentDocument doc = [SELECT Id, Title FROM ContentDocument LIMIT 1];
            String updatedTitle = 'Updated Title ' + System.currentTimeMillis();

            // WHEN: the ContentDocument is updated (fires before update, after update)
            Test.startTest();
            doc.Title = updatedTitle;
            update doc;
            Test.stopTest();

            // THEN: the update committed without error and the title reflects the change
            ContentDocument result = [SELECT Id, Title FROM ContentDocument WHERE Id = :doc.Id];
            System.Assert.areEqual(updatedTitle, result.Title, 'ContentDocument title should be updated.');
        }
    }

    // ── Before Delete / After Delete ──────────────────────────────────────────

    /**
     * @description Verifies that the before delete and after delete trigger contexts fire without
     *              error when a ContentDocument is deleted.
     *
     *              NOTE: Deleting a ContentDocument also cascades to all its ContentVersions
     *              and ContentDocumentLinks. This is intentional platform behavior.
     */
    @IsTest
    static void shouldFireDeleteContexts_WhenContentDocumentIsDeleted() {
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            // GIVEN: a ContentDocument created from the test setup ContentVersion
            ContentDocument doc = [SELECT Id FROM ContentDocument LIMIT 1];

            // WHEN: the ContentDocument is deleted (fires before delete, after delete)
            Test.startTest();
            delete doc;
            Test.stopTest();

            // THEN: the ContentDocument is in the Recycle Bin (deleted but not permanently removed)
            Integer count = [SELECT COUNT() FROM ContentDocument WHERE Id = :doc.Id ALL ROWS];
            System.Assert.areEqual(1, count, 'Deleted ContentDocument should exist in the Recycle Bin.');
        }
    }

    // ── After Undelete ────────────────────────────────────────────────────────

    /**
     * @description Verifies that the after undelete trigger context fires without error when
     *              a ContentDocument is restored from the Recycle Bin.
     */
    @IsTest
    static void shouldFireAfterUndeleteContext_WhenContentDocumentIsRestored() {
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            // GIVEN: a ContentDocument that has been deleted (is in the Recycle Bin)
            ContentDocument doc = [SELECT Id FROM ContentDocument LIMIT 1];
            delete doc;

            // WHEN: the ContentDocument is undeleted (fires after undelete)
            Test.startTest();
            undelete doc;
            Test.stopTest();

            // THEN: the ContentDocument is active again
            Integer count = [SELECT COUNT() FROM ContentDocument WHERE Id = :doc.Id];
            System.Assert.areEqual(1, count, 'Undeleted ContentDocument should be active again.');
        }
    }

    // ── Bypass ────────────────────────────────────────────────────────────────

    /**
     * @description Verifies that the TriggerHandler bypass mechanism suppresses all handler logic
     *              for ContentDocumentTrigger without causing errors.
     */
    @IsTest
    static void shouldBypassHandler_WhenTriggerIsBypassed() {
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            // GIVEN: a ContentDocument and the trigger bypassed
            ContentDocument doc = [SELECT Id, Title FROM ContentDocument LIMIT 1];
            TriggerHandler.bypass('ContentDocumentTriggerHandler');

            // WHEN: an update is performed while bypassed
            Test.startTest();
            doc.Title = 'Bypassed Update';
            update doc;
            Test.stopTest();

            // THEN: the update succeeded; the bypass is cleared for other tests
            TriggerHandler.clearBypass('ContentDocumentTriggerHandler');
            ContentDocument result = [SELECT Id, Title FROM ContentDocument WHERE Id = :doc.Id];
            System.Assert.areEqual('Bypassed Update', result.Title, 'Update should succeed even when handler is bypassed.');
        }
    }
}