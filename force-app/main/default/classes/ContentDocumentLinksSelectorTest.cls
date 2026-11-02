/**
 * @description Minimal tests for ContentDocumentLinksSelector Device Evaluation methods
 *              (GW-3913 / GW-3096).
 */
@IsTest
private class ContentDocumentLinksSelectorTest {

    @IsTest
    static void testDeviceEvaluationLinkMethodsNullGuards() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Test.startTest();
            Assert.isTrue(
                ContentDocumentLinksSelector.selectByLinkedEntityIdsLimited(null, 200).isEmpty()
            );
            Assert.isTrue(
                ContentDocumentLinksSelector.selectByLinkedEntityIdsLimited(new Set<Id>(), 200)
                    .isEmpty()
            );
            Assert.isTrue(
                ContentDocumentLinksSelector.selectByLinkedEntityIdsLimited(
                        new Set<Id>{ UserInfo.getUserId() },
                        0
                    )
                    .isEmpty()
            );
            Assert.isTrue(
                ContentDocumentLinksSelector.selectByDocumentsAndLinkedEntities(null, null).isEmpty()
            );
            Assert.areEqual(0, ContentDocumentLinksSelector.countByLinkedEntityIds(null));
            Assert.isTrue(
                ContentDocumentLinksSelector.selectLinkedEntityIdsByContentDocumentId(null).isEmpty()
            );
            Test.stopTest();
        }
    }

    @IsTest
    static void testSelectByLinkedEntityIdsLimitedHappyPath() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            adb_ContentVersion versionBuilder = new adb_ContentVersion()
                .title('CDL Selector Test')
                .pathOnClient('cdl-selector-test.jpg')
                .versionData(Blob.valueOf('cdl-selector'));
            versionBuilder.persist();
            ContentVersion version = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :versionBuilder.Id
                LIMIT 1
            ];

            Test.startTest();
            List<ContentDocumentLink> links =
                ContentDocumentLinksSelector.selectByLinkedEntityIdsLimited(
                    new Set<Id>{ UserInfo.getUserId() },
                    200
                );
            Integer linkCount = ContentDocumentLinksSelector.countByLinkedEntityIds(
                new Set<Id>{ UserInfo.getUserId() }
            );
            List<ContentDocumentLink> byDoc =
                ContentDocumentLinksSelector.selectLinkedEntityIdsByContentDocumentId(
                    version.ContentDocumentId
                );
            Test.stopTest();

            Assert.isTrue(linkCount >= 1, 'User should have at least the auto-created link');
            Assert.isFalse(byDoc.isEmpty(), 'Should return linked entities for the document');
            Boolean found = false;
            for (ContentDocumentLink link : links) {
                if (link.ContentDocumentId == version.ContentDocumentId) {
                    found = true;
                    break;
                }
            }
            Assert.isTrue(found, 'Limited query should include the staged document link');
        }
    }

    @IsTest
    static void testSelectByLinkedEntityIdForReceiving_returnsLinkedDocument() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            adb_ContentVersion versionBuilder = new adb_ContentVersion()
                .title('Receiving CDL Selector')
                .pathOnClient('receiving-cdl.txt')
                .versionData(Blob.valueOf('receiving-cdl'));
            versionBuilder.persist();
            ContentVersion version = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :versionBuilder.Id
                LIMIT 1
            ];

            Test.startTest();
            List<ContentDocumentLink> links =
                ContentDocumentLinksSelector.selectByLinkedEntityIdForReceiving(UserInfo.getUserId());
            List<ContentDocumentLink> emptyLinks =
                ContentDocumentLinksSelector.selectByLinkedEntityIdForReceiving(null);
            Test.stopTest();

            Assert.isTrue(emptyLinks.isEmpty(), 'Null entity should return no links');
            Boolean found = false;
            for (ContentDocumentLink link : links) {
                if (link.ContentDocumentId == version.ContentDocumentId) {
                    found = true;
                    break;
                }
            }
            Assert.isTrue(found, 'Receiving query should include the linked document');
        }
    }
}