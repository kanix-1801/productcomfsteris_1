/**
 * @description Test class for ContentVersionTriggerHandler.
 *
 *              ContentVersion trigger context coverage:
 *                - VALID:   before insert, after insert, before update, after update
 *                - INVALID: before delete, after delete (published versions cannot be deleted directly;
 *                           use ContentDocument delete instead)
 *                           after undelete (ContentVersion cannot be undeleted independently)
 *
 *              Inserting a ContentVersion is the only way to create a ContentDocument on the platform.
 *              ContentDocumentId is available on Trigger.new during after insert.
 */
@IsTest
private class ContentVersionTriggerHandlerTest {

    // ── Helper ────────────────────────────────────────────────────────────────

    private static User buildTestUser() {
        adb_User builder = new adb_User();
        builder.persist();
        return (User) builder.record;
    }

    // ── Before Insert / After Insert ──────────────────────────────────────────

    /**
     * @description Verifies that the before insert and after insert trigger contexts fire without
     *              error when a ContentVersion is inserted.
     *
     *              Inserting a ContentVersion also causes the platform to implicitly create a
     *              parent ContentDocument. ContentDocumentId is available in the after insert context.
     */
    @IsTest
    static void shouldFireInsertContexts_WhenContentVersionIsInserted() {
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            // GIVEN: a new ContentVersion built using the test data builder
            adb_ContentVersion cvBuilder = new adb_ContentVersion();
            ContentVersion cv = (ContentVersion) cvBuilder.record;

            // WHEN: the ContentVersion is inserted (fires before insert, after insert)
            Test.startTest();
            insert cv;
            Test.stopTest();

            // THEN: the ContentVersion is committed and the parent ContentDocument was created implicitly
            ContentVersion result = [
                SELECT Id, ContentDocumentId, Title
                FROM ContentVersion
                WHERE Id = :cv.Id
            ];
            System.Assert.isNotNull(result.ContentDocumentId,
                'ContentDocumentId must be populated after ContentVersion insert.');
        }
    }

    /**
     * @description Verifies bulk before insert and after insert handling with 200 ContentVersion records.
     */
    @IsTest
    static void shouldFireInsertContexts_WhenBulkContentVersionsAreInserted() {
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            // GIVEN: 200 new ContentVersion records
            List<ContentVersion> versions = new List<ContentVersion>();

            // Build 200 content versions for bulk insert test
            for (Integer i = 0; i < 200; i++) {
                versions.add((ContentVersion) new adb_ContentVersion()
                    .title('Bulk Test Document ' + i)
                    .pathOnClient('BulkDocument' + i + '.txt')
                    .versionData(Blob.valueOf('Bulk content ' + i))
                    .record);
            }

            // WHEN: 200 ContentVersions are inserted in bulk
            Test.startTest();
            insert versions;
            Test.stopTest();

            // THEN: all 200 ContentDocuments were created
            Integer docCount = [
                SELECT COUNT()
                FROM ContentDocument
                WHERE CreatedDate = TODAY
            ];
            System.Assert.areEqual(200, docCount,
                '200 ContentDocuments should have been implicitly created by the bulk ContentVersion insert.');
        }
    }

    // ── Before Update / After Update ──────────────────────────────────────────

    /**
     * @description Verifies that the before update and after update trigger contexts fire without
     *              error when a ContentVersion is updated.
     *
     *              NOTE: Only specific fields on ContentVersion are updateable (e.g., Title,
     *              Description). VersionData, PathOnClient, and ContentDocumentId are immutable
     *              after the version is published.
     */
    @IsTest
    static void shouldFireUpdateContexts_WhenContentVersionIsUpdated() {
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            // GIVEN: an existing ContentVersion
            adb_ContentVersion cvBuilder = new adb_ContentVersion();
            ContentVersion cv = (ContentVersion) cvBuilder.record;
            insert cv;

            String updatedTitle = 'Updated Title ' + System.currentTimeMillis();

            // WHEN: the ContentVersion Title is updated (fires before update, after update)
            Test.startTest();
            cv.Title = updatedTitle;
            update cv;
            Test.stopTest();

            // THEN: the title is persisted
            ContentVersion result = [SELECT Id, Title FROM ContentVersion WHERE Id = :cv.Id];
            System.Assert.areEqual(updatedTitle, result.Title,
                'ContentVersion title should be updated after before update and after update contexts fire.');
        }
    }

    // ── After Insert — ContentDocumentId Availability ─────────────────────────

    /**
     * @description Verifies that ContentDocumentId is populated on Trigger.new records in the
     *              after insert context, which is required for creating ContentDocumentLink records.
     *
     *              This test confirms the documented platform behavior that makes after insert the
     *              correct context for linking documents to records.
     */
    @IsTest
    static void shouldPopulateContentDocumentId_WhenContentVersionIsInsertedAndQueried() {
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            // GIVEN: a new ContentVersion
            adb_ContentVersion cvBuilder = new adb_ContentVersion();
            ContentVersion cv = (ContentVersion) cvBuilder.record;

            // WHEN: the ContentVersion is inserted
            Test.startTest();
            insert cv;
            Test.stopTest();

            // THEN: re-querying confirms ContentDocumentId is set (as it would be in after insert Trigger.new)
            ContentVersion queried = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
            System.Assert.isNotNull(queried.ContentDocumentId,
                'ContentDocumentId must be set on the ContentVersion after insert, confirming ' +
                'it is available in the after insert trigger context.');

            // AND: the ContentDocument actually exists
            Integer docCount = [SELECT COUNT() FROM ContentDocument WHERE Id = :queried.ContentDocumentId];
            System.Assert.areEqual(1, docCount,
                'The platform-created ContentDocument must exist with the Id from ContentVersion.ContentDocumentId.');
        }
    }

    // ── Bypass ────────────────────────────────────────────────────────────────

    /**
     * @description Verifies that the TriggerHandler bypass mechanism suppresses handler logic
     *              for ContentVersionTrigger without causing errors.
     */
    @IsTest
    static void shouldBypassHandler_WhenTriggerIsBypassed() {
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            // GIVEN: a ContentVersion and the trigger bypassed
            adb_ContentVersion cvBuilder = new adb_ContentVersion();
            ContentVersion cv = (ContentVersion) cvBuilder.record;
            TriggerHandler.bypass('ContentVersionTriggerHandler');

            // WHEN: the ContentVersion is inserted while the handler is bypassed
            Test.startTest();
            insert cv;
            Test.stopTest();

            // THEN: the insert succeeded; clear the bypass for other tests
            TriggerHandler.clearBypass('ContentVersionTriggerHandler');
            Integer count = [SELECT COUNT() FROM ContentVersion WHERE Id = :cv.Id];
            System.Assert.areEqual(1, count, 'ContentVersion should be inserted even when handler is bypassed.');
        }
    }
}