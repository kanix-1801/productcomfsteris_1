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
    static void testSelectByIdAndLinkedEntityAndDocument_happyPath() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            adb_ContentVersion versionBuilder = new adb_ContentVersion()
                .title('CDL Base Selector')
                .pathOnClient('cdl-base-selector.txt')
                .versionData(Blob.valueOf('cdl-base'));
            versionBuilder.persist();
            ContentVersion version = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :versionBuilder.Id
                LIMIT 1
            ];
            ContentDocumentLink existing = [
                SELECT Id, ContentDocumentId, LinkedEntityId
                FROM ContentDocumentLink
                WHERE ContentDocumentId = :version.ContentDocumentId
                LIMIT 1
            ];

            Test.startTest();
            List<ContentDocumentLink> byId = ContentDocumentLinksSelector.selectById(
                new Set<Id>{ existing.Id }
            );
            List<ContentDocumentLink> byEntity =
                ContentDocumentLinksSelector.selectByLinkedEntityId(
                    new Set<Id>{ existing.LinkedEntityId }
                );
            List<ContentDocumentLink> byDoc =
                ContentDocumentLinksSelector.selectByContentDocumentId(
                    new Set<Id>{ version.ContentDocumentId }
                );
            List<ContentDocumentLink> byBoth =
                ContentDocumentLinksSelector.selectByDocumentsAndLinkedEntities(
                    new Set<Id>{ version.ContentDocumentId },
                    new Set<Id>{ existing.LinkedEntityId }
                );
            List<ContentDocumentLink> emptyById = ContentDocumentLinksSelector.selectById(null);
            List<ContentDocumentLink> emptyByEntity =
                ContentDocumentLinksSelector.selectByLinkedEntityId(null);
            List<ContentDocumentLink> emptyByDoc =
                ContentDocumentLinksSelector.selectByContentDocumentId(null);
            Test.stopTest();

            Assert.areEqual(1, byId.size());
            Assert.isFalse(byEntity.isEmpty());
            Assert.isFalse(byDoc.isEmpty());
            Assert.isFalse(byBoth.isEmpty());
            Assert.isTrue(emptyById.isEmpty());
            Assert.isTrue(emptyByEntity.isEmpty());
            Assert.isTrue(emptyByDoc.isEmpty());
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

    @IsTest
    static void testSelectWithVersionDescriptionByLinkedEntityId_happyPathAndNullGuard() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            adb_ContentVersion versionBuilder = new adb_ContentVersion()
                .title('CDL Version Description')
                .pathOnClient('cdl-version-description.txt')
                .versionData(Blob.valueOf('cdl-version-description'));
            versionBuilder.persist();

            Test.startTest();
            List<ContentDocumentLink> links =
                ContentDocumentLinksSelector.selectWithVersionDescriptionByLinkedEntityId(
                    UserInfo.getUserId()
                );
            List<ContentDocumentLink> emptyLinks =
                ContentDocumentLinksSelector.selectWithVersionDescriptionByLinkedEntityId(null);
            Test.stopTest();

            Assert.isTrue(emptyLinks.isEmpty(), 'Null entity should return no links');
            Assert.isFalse(
                links.isEmpty(),
                'Version description query should return linked documents'
            );
        }
    }
}