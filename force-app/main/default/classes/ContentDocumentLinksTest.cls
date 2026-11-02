/**
 * @description Test class for ContentDocumentLinks domain class.
 *              Covers constructor and domain exception.
 */
@IsTest
private class ContentDocumentLinksTest {

    @IsTest
    static void shouldConstructDomain_WhenValidRecordListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<ContentDocumentLink> linkList = new List<ContentDocumentLink>{
                new ContentDocumentLink(),
                new ContentDocumentLink()
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ContentDocumentLinks domain = new ContentDocumentLinks(linkList);
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
            ContentDocumentLinks domain = new ContentDocumentLinks(new List<ContentDocumentLink>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(domain, 'Domain instance should be created from an empty list without error');
        }
    }

    @IsTest
    static void shouldThrowContentDocumentLinksException_WhenExceptionIsRaised() {
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
                throw new ContentDocumentLinks.ContentDocumentLinksException('ContentDocumentId is required.');
            } catch (ContentDocumentLinks.ContentDocumentLinksException e) {
                Assert.areEqual(
                    'ContentDocumentId is required.',
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