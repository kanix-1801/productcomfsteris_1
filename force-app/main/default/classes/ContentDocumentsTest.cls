/**
 * @description Test class for ContentDocuments domain class.
 *              Covers constructor and domain exception.
 *              Note: ContentDocument cannot be inserted directly — it is created
 *              implicitly by inserting a ContentVersion.
 */
@IsTest
private class ContentDocumentsTest {

    @IsTest
    static void shouldConstructDomain_WhenValidRecordListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN — create ContentVersion to get a real ContentDocument
             ********************************************/
            ContentVersion cv = (ContentVersion) new adb_ContentVersion().title('Test Doc').record;
            insert cv;
            ContentVersion insertedCv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
            List<ContentDocument> docList = [SELECT Id FROM ContentDocument WHERE Id = :insertedCv.ContentDocumentId];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ContentDocuments domain = new ContentDocuments(docList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(domain, 'Domain instance should be created from a valid record list');
        }
    }

    @IsTest
    static void shouldConstructDomain_WhenEmptyListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ContentDocuments domain = new ContentDocuments(new List<ContentDocument>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(domain, 'Domain instance should be created from an empty list without error');
        }
    }

    @IsTest
    static void shouldThrowContentDocumentsException_WhenExceptionIsRaised() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN / THEN
             ********************************************/
            Test.startTest();
            try {
                throw new ContentDocuments.ContentDocumentsException('Title is required.');
            } catch (ContentDocuments.ContentDocumentsException e) {
                Assert.areEqual(
                    'Title is required.',
                    e.getMessage(),
                    'Exception message should match the value provided at construction'
                );
            }
            Test.stopTest();
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static User buildTestUser() {
        adb_User builder = new adb_User();
        builder.persist();
        return (User) builder.record;
    }
}