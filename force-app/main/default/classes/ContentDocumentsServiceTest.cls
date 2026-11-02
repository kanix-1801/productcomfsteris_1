/**
 * @description Tests for ContentDocuments Selector/Service including Device Evaluation helpers.
 */
@IsTest
private class ContentDocumentsServiceTest {
    private class SelectorException extends Exception {
    }

    private class ThrowingSelector
        implements ContentDocumentsService.IContentDocumentsSelector {
        public List<ContentDocument> selectById(Set<Id> contentDocumentIds) {
            throw new SelectorException('selectById failed');
        }

        public List<ContentDocument> selectOwnedByCreatedBy(
            Id contentDocumentId,
            Id createdById
        ) {
            throw new SelectorException('selectOwnedByCreatedBy failed');
        }
    }

    @IsTest
    static void testContentDocumentCrudAndOwnedLookup() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            adb_ContentVersion versionBuilder = new adb_ContentVersion()
                .title('CD Service Test')
                .pathOnClient('cd-service-test.jpg')
                .versionData(Blob.valueOf('cd-service'));
            versionBuilder.persist();
            ContentVersion version = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :versionBuilder.Id
                LIMIT 1
            ];

            Test.startTest();
            List<ContentDocument> byId = ContentDocumentsSelector.selectById(
                new Set<Id>{ version.ContentDocumentId }
            );
            List<ContentDocument> byLinked = ContentDocumentsSelector.selectByLinkedEntityId(
                new Set<Id>{ UserInfo.getUserId() }
            );
            Assert.isTrue(ContentDocumentsSelector.selectByLinkedEntityId(null).isEmpty());
            List<ContentDocument> viaService = ContentDocumentsService.getContentDocumentsById(
                new Set<Id>{ version.ContentDocumentId }
            );
            ContentDocumentsService.updateContentDocuments(
                new List<ContentDocument>{
                    new ContentDocument(Id = version.ContentDocumentId, Description = 'Updated desc')
                }
            );
            ContentDocument owned = ContentDocumentsService.getOwnedDocumentForDeviceEvaluation(
                version.ContentDocumentId,
                UserInfo.getUserId()
            );

            Assert.isTrue(ContentDocumentsSelector.selectById(null).isEmpty());
            Assert.isTrue(ContentDocumentsService.getContentDocumentsById(null).isEmpty());
            ContentDocumentsService.updateContentDocuments(null);
            ContentDocumentsService.deleteContentDocuments(null);
            Assert.isNull(
                ContentDocumentsService.getOwnedDocumentForDeviceEvaluation(null, null)
            );

            ContentDocumentsService.deleteContentDocuments(new Set<Id>{ version.ContentDocumentId });
            Test.stopTest();

            Assert.areEqual(1, byId.size());
            Assert.isFalse(byLinked.isEmpty(), 'User auto-link should resolve ContentDocuments');
            Assert.areEqual(1, viaService.size());
            Assert.isNotNull(owned);
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM ContentDocument WHERE Id = :version.ContentDocumentId],
                'Document should be deleted'
            );
        }
    }

    @IsTest
    static void testDeleteStagedPhotoForDeviceEvaluationValidation() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Boolean threw = false;
            try {
                ContentDocumentsService.deleteStagedPhotoForDeviceEvaluation(null);
            } catch (ContentDocumentsService.ContentDocumentsServiceException e) {
                threw = true;
                Assert.isTrue(e.getMessage().contains('File is required'));
            }
            Assert.isTrue(threw, 'delete requires contentDocumentId');

            threw = false;
            try {
                ContentDocumentsService.deleteStagedPhotoForDeviceEvaluation(UserInfo.getUserId());
            } catch (ContentDocumentsService.ContentDocumentsServiceException e) {
                threw = true;
                Assert.isTrue(
                    e.getMessage().contains('not found') ||
                    e.getMessage().contains('already been removed')
                );
            }
            Assert.isTrue(threw, 'missing owned document should fail');
        }
    }

    @IsTest
    static void testGetContentDocumentsById_selectorThrows() {
        assertSelectorFailure('get');
    }

    @IsTest
    static void testDeleteContentDocuments_selectorThrows() {
        assertSelectorFailure('delete');
    }

    @IsTest
    static void testGetOwnedDocumentForDeviceEvaluation_selectorThrows() {
        assertSelectorFailure('owned');
    }

    private static void assertSelectorFailure(String operation) {
        Id documentId = (Id)(ContentDocument.SObjectType.getDescribe().getKeyPrefix() +
            '000000000001');
        ContentDocumentsService.selectorOverride = new ThrowingSelector();
        try {
            Boolean threw = false;
            try {
                if (operation == 'get') {
                    ContentDocumentsService.getContentDocumentsById(
                        new Set<Id>{ documentId }
                    );
                } else if (operation == 'delete') {
                    ContentDocumentsService.deleteContentDocuments(
                        new Set<Id>{ documentId }
                    );
                } else {
                    ContentDocumentsService.getOwnedDocumentForDeviceEvaluation(
                        documentId,
                        UserInfo.getUserId()
                    );
                }
            } catch (ContentDocumentsService.ContentDocumentsServiceException e) {
                threw = true;
                Assert.isNotNull(e.getCause(), 'Wrapped exception should retain its cause');
            }
            Assert.isTrue(threw, operation + ' should wrap selector failures');
        } finally {
            ContentDocumentsService.selectorOverride = null;
        }
    }

    @IsTest
    static void testUpdateContentDocuments_deletedIdWrapsDmlFailure() {
        ContentVersion version = new ContentVersion(
            Title = 'Deleted document update',
            PathOnClient = 'deleted-document.txt',
            VersionData = Blob.valueOf('content')
        );
        insert version;
        version = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ];
        delete new ContentDocument(Id = version.ContentDocumentId);

        Boolean threw = false;
        try {
            ContentDocumentsService.updateContentDocuments(
                new List<ContentDocument>{
                    new ContentDocument(
                        Id = version.ContentDocumentId,
                        Description = 'Should fail'
                    )
                }
            );
        } catch (ContentDocumentsService.ContentDocumentsServiceException e) {
            threw = true;
            Assert.isInstanceOfType(e.getCause(), DmlException.class);
        }
        Assert.isTrue(threw, 'Updating a deleted document should wrap DML failure');
    }
}