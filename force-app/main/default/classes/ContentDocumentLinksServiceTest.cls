/**
 * @description Tests for ContentDocumentLinks Selector/Service including Device Evaluation helpers.
 */
@IsTest
private class ContentDocumentLinksServiceTest {
    private class SelectorException extends Exception {
    }

    private class ThrowingSelector
        implements ContentDocumentLinksService.IContentDocumentLinksSelector {
        public List<ContentDocumentLink> selectById(Set<Id> linkIds) {
            throw new SelectorException('selectById failed');
        }

        public List<ContentDocumentLink> selectByLinkedEntityIdsLimited(
            Set<Id> linkedEntityIds,
            Integer rowLimit
        ) {
            throw new SelectorException('selectByLinkedEntityIdsLimited failed');
        }

        public List<ContentDocumentLink> selectByDocumentsAndLinkedEntities(
            Set<Id> documentIds,
            Set<Id> linkedEntityIds
        ) {
            throw new SelectorException('selectByDocumentsAndLinkedEntities failed');
        }

        public Integer countByLinkedEntityIds(Set<Id> linkedEntityIds) {
            throw new SelectorException('countByLinkedEntityIds failed');
        }

        public List<ContentDocumentLink> selectLinkedEntityIdsByContentDocumentId(
            Id contentDocumentId
        ) {
            throw new SelectorException('selectLinkedEntityIdsByContentDocumentId failed');
        }
    }

    @TestSetup
    static void setupTestData() {
        adb_Account accountBuilder = new adb_Account();
        accountBuilder.persist();
    }

    @IsTest
    static void testContentDocumentLinkCrudAndDeviceEvaluationHelpers() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Account account = [SELECT Id FROM Account LIMIT 1];

            adb_ContentVersion versionBuilder = new adb_ContentVersion()
                .title('CDL Service Test')
                .pathOnClient('cdl-service-test.jpg')
                .versionData(Blob.valueOf('cdl-service'));
            versionBuilder.persist();
            ContentVersion version = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :versionBuilder.Id
                LIMIT 1
            ];

            ContentDocumentLink accountLink = new ContentDocumentLink(
                ContentDocumentId = version.ContentDocumentId,
                LinkedEntityId = account.Id,
                ShareType = 'V',
                Visibility = 'AllUsers'
            );

            Test.startTest();
            ContentDocumentLinksService.createContentDocumentLinks(
                new List<ContentDocumentLink>{ accountLink }
            );

            List<ContentDocumentLink> byId = ContentDocumentLinksSelector.selectById(
                new Set<Id>{ accountLink.Id }
            );
            List<ContentDocumentLink> byEntity = ContentDocumentLinksSelector.selectByLinkedEntityId(
                new Set<Id>{ account.Id }
            );
            List<ContentDocumentLink> byDoc = ContentDocumentLinksSelector.selectByContentDocumentId(
                new Set<Id>{ version.ContentDocumentId }
            );
            List<ContentDocumentLink> viaService = ContentDocumentLinksService.getContentDocumentLinksById(
                new Set<Id>{ accountLink.Id }
            );
            List<ContentDocumentLink> limited =
                ContentDocumentLinksService.getLinksByLinkedEntityIdsLimited(
                    new Set<Id>{ account.Id },
                    200
                );
            List<ContentDocumentLink> byDocsAndEntities =
                ContentDocumentLinksService.getLinksByDocumentsAndLinkedEntities(
                    new Set<Id>{ version.ContentDocumentId },
                    new Set<Id>{ account.Id }
                );
            Integer countLinks = ContentDocumentLinksService.countLinksByLinkedEntityIds(
                new Set<Id>{ account.Id }
            );
            List<ContentDocumentLink> linkedEntities =
                ContentDocumentLinksService.getLinkedEntityIdsByContentDocumentId(
                    version.ContentDocumentId
                );

            Assert.isTrue(ContentDocumentLinksSelector.selectById(null).isEmpty());
            Assert.isTrue(ContentDocumentLinksSelector.selectByLinkedEntityId(null).isEmpty());
            Assert.isTrue(ContentDocumentLinksSelector.selectByContentDocumentId(null).isEmpty());
            Assert.isTrue(ContentDocumentLinksService.getContentDocumentLinksById(null).isEmpty());
            ContentDocumentLinksService.createContentDocumentLinks(null);
            ContentDocumentLinksService.deleteContentDocumentLinks(null);

            ContentDocumentLinksService.deleteContentDocumentLinks(new Set<Id>{ accountLink.Id });
            Test.stopTest();

            Assert.areEqual(1, byId.size());
            Assert.isFalse(byEntity.isEmpty());
            Assert.isFalse(byDoc.isEmpty());
            Assert.areEqual(1, viaService.size());
            Assert.isFalse(limited.isEmpty());
            Assert.isFalse(byDocsAndEntities.isEmpty());
            Assert.isTrue(countLinks >= 1);
            Assert.isFalse(linkedEntities.isEmpty());
        }
    }

    @IsTest
    static void testDeviceEvaluationAttachAndFileHelpers() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Test.startTest();
            Assert.isFalse(
                ContentDocumentLinksService.repairCodeWolisHaveFilesForDeviceEvaluation(null)
            );
            Assert.isTrue(
                ContentDocumentLinksService.getRepairCodeWoliFilesForDeviceEvaluation(null).isEmpty()
            );
            ContentDocumentLinksService.attachStagedPhotosToWolisForDeviceEvaluation(
                null,
                null,
                null
            );

            ContentVersion version = new ContentVersion(
                Title = 'CDL DE File',
                PathOnClient = 'cdl-de-file.jpg',
                VersionData = Blob.valueOf('cdl-de'),
                FirstPublishLocationId = UserInfo.getUserId()
            );
            insert version;
            version = [
                SELECT
                    Id,
                    ContentDocumentId,
                    Title,
                    FileExtension,
                    FileType,
                    PathOnClient,
                    LastModifiedDate
                FROM ContentVersion
                WHERE Id = :version.Id
                LIMIT 1
            ];
            ContentDocumentLinksService.DeviceEvaluationFileData fileData =
                ContentDocumentLinksService.toFileData(version);
            Test.stopTest();

            Assert.areEqual(version.ContentDocumentId, fileData.contentDocumentId);
            Assert.areEqual(version.Id, fileData.contentVersionId);
            Assert.isTrue(fileData.isImage, 'jpg should be treated as image');
            Assert.isTrue(
                String.isNotBlank(fileData.downloadUrl),
                'downloadUrl should be populated'
            );
        }
    }

    @IsTest
    static void testAttachStagedPhotos_idempotentAndNonImageToFileData() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Schema.RecordTypeInfo repairCodeRt = Schema.SObjectType.WorkOrderLineItem
                .getRecordTypeInfosByDeveloperName()
                .get('RepairCode');
            if (repairCodeRt == null) {
                Assert.isTrue(true, 'RepairCode RT unavailable');
                return;
            }

            adb_Account accountBuilder = new adb_Account();
            accountBuilder.persist();
            Id pricebookId = Test.getStandardPricebookId();
            Product2 product = new Product2(
                Name = 'CDL Attach Product',
                ProductCode = 'CDL-ATTACH-001',
                IsActive = true
            );
            insert product;
            insert new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id = product.Id,
                UnitPrice = 1,
                IsActive = true
            );
            PricebookEntry pbe = [
                SELECT Id
                FROM PricebookEntry
                WHERE Product2Id = :product.Id AND Pricebook2Id = :pricebookId
                LIMIT 1
            ];
            WorkOrder workOrder = new WorkOrder(
                AccountId = accountBuilder.id,
                Subject = 'CDL Attach WO',
                Status = 'Evaluate',
                Pricebook2Id = pricebookId
            );
            insert workOrder;
            WorkOrderLineItem woli = new WorkOrderLineItem(
                WorkOrderId = workOrder.Id,
                RecordTypeId = repairCodeRt.getRecordTypeId(),
                Product__c = product.Id,
                PricebookEntryId = pbe.Id,
                Quantity = 1
            );
            insert woli;

            ContentVersion version = new ContentVersion(
                Title = 'CDL Attach Doc',
                PathOnClient = 'cdl-attach.jpg',
                VersionData = Blob.valueOf('cdl-attach'),
                FirstPublishLocationId = UserInfo.getUserId()
            );
            insert version;
            version = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :version.Id
            ];

            ContentDocumentLinksService.StagedPhotoAssignment assignment =
                new ContentDocumentLinksService.StagedPhotoAssignment();
            assignment.contentDocumentId = version.ContentDocumentId;
            assignment.productId = product.Id;
            List<ContentDocumentLinksService.StagedPhotoAssignment> staged =
                new List<ContentDocumentLinksService.StagedPhotoAssignment>{
                    null,
                    assignment,
                    assignment
                };

            Test.startTest();
            ContentDocumentLinksService.attachStagedPhotosToWolisForDeviceEvaluation(
                workOrder.Id,
                staged,
                new Set<Id>{ product.Id }
            );
            // Second call should skip existing link (idempotent).
            ContentDocumentLinksService.attachStagedPhotosToWolisForDeviceEvaluation(
                workOrder.Id,
                new List<ContentDocumentLinksService.StagedPhotoAssignment>{ assignment },
                new Set<Id>{ product.Id }
            );
            List<ContentDocumentLinksService.DeviceEvaluationFileData> repairCodeFiles =
                ContentDocumentLinksService.getRepairCodeWoliFilesForDeviceEvaluation(
                    workOrder.Id
                );

            ContentVersion pdfVersion = new ContentVersion(
                Title = 'CDL PDF',
                PathOnClient = 'notes.pdf',
                VersionData = Blob.valueOf('%PDF-1.4'),
                FirstPublishLocationId = UserInfo.getUserId()
            );
            insert pdfVersion;
            pdfVersion = [
                SELECT
                    Id,
                    ContentDocumentId,
                    Title,
                    FileExtension,
                    FileType,
                    PathOnClient,
                    LastModifiedDate
                FROM ContentVersion
                WHERE Id = :pdfVersion.Id
            ];
            ContentDocumentLinksService.DeviceEvaluationFileData pdfData =
                ContentDocumentLinksService.toFileData(pdfVersion);
            ContentDocumentLinksService.DeviceEvaluationFileData nullData =
                ContentDocumentLinksService.toFileData(null);
            Test.stopTest();

            Integer linkCount = [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :woli.Id
                    AND ContentDocumentId = :version.ContentDocumentId
            ];
            Assert.areEqual(1, linkCount, 'Idempotent attach should create one link');
            Assert.areEqual(1, repairCodeFiles.size(), 'Repair Code WOLI file should be returned');
            Assert.areEqual(product.Id, repairCodeFiles[0].productId);
            Assert.areEqual(false, pdfData.isImage, 'pdf should not be treated as image');
            Assert.isTrue(String.isBlank(pdfData.thumbnailUrl), 'Non-image has no thumbnail');
            Assert.isNull(nullData.contentDocumentId, 'Null version yields empty file data');
        }
    }

    @IsTest
    static void testGetContentDocumentLinksById_selectorThrows() {
        assertSelectorFailure('byId');
    }

    @IsTest
    static void testGetLinksByLinkedEntityIdsLimited_selectorThrows() {
        assertSelectorFailure('limited');
    }

    @IsTest
    static void testGetLinksByDocumentsAndLinkedEntities_selectorThrows() {
        assertSelectorFailure('documentsAndEntities');
    }

    @IsTest
    static void testCountLinksByLinkedEntityIds_selectorThrows() {
        assertSelectorFailure('count');
    }

    @IsTest
    static void testGetLinkedEntityIdsByContentDocumentId_selectorThrows() {
        assertSelectorFailure('linkedEntities');
    }

    private static void assertSelectorFailure(String operation) {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Id documentId = (Id)(ContentDocument.SObjectType.getDescribe().getKeyPrefix() +
            '000000000001');
        Id linkId = (Id)(ContentDocumentLink.SObjectType.getDescribe().getKeyPrefix() +
            '000000000001');
        ContentDocumentLinksService.selectorOverride = new ThrowingSelector();
        try {
            Boolean threw = false;
            try {
                if (operation == 'byId') {
                    ContentDocumentLinksService.getContentDocumentLinksById(
                        new Set<Id>{ linkId }
                    );
                } else if (operation == 'limited') {
                    ContentDocumentLinksService.getLinksByLinkedEntityIdsLimited(
                        new Set<Id>{ account.Id },
                        1
                    );
                } else if (operation == 'documentsAndEntities') {
                    ContentDocumentLinksService.getLinksByDocumentsAndLinkedEntities(
                        new Set<Id>{ documentId },
                        new Set<Id>{ account.Id }
                    );
                } else if (operation == 'count') {
                    ContentDocumentLinksService.countLinksByLinkedEntityIds(
                        new Set<Id>{ account.Id }
                    );
                } else {
                    ContentDocumentLinksService.getLinkedEntityIdsByContentDocumentId(
                        documentId
                    );
                }
            } catch (ContentDocumentLinksService.ContentDocumentLinksServiceException e) {
                threw = true;
                Assert.isNotNull(e.getCause(), 'Wrapped exception should retain its cause');
            }
            Assert.isTrue(threw, operation + ' should wrap selector failures');
        } finally {
            ContentDocumentLinksService.selectorOverride = null;
        }
    }

    @IsTest
    static void testGetFilesForLinkedEntities_returnsLinkedImageRows() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Account account = [SELECT Id FROM Account LIMIT 1];

            adb_ContentVersion versionBuilder = new adb_ContentVersion()
                .title('CDL Linked Files')
                .pathOnClient('cdl-linked-files.jpg')
                .versionData(Blob.valueOf('cdl-linked'));
            versionBuilder.persist();
            ContentVersion version = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :versionBuilder.Id
                LIMIT 1
            ];

            ContentDocumentLinksService.attachDocumentsToLinkedEntity(
                account.Id,
                new List<Id>{ version.ContentDocumentId }
            );
            // Second attach should be idempotent (no duplicate link).
            ContentDocumentLinksService.attachDocumentsToLinkedEntity(
                account.Id,
                new List<Id>{ version.ContentDocumentId, null }
            );

            Test.startTest();
            List<ContentDocumentLinksService.DeviceEvaluationFileData> empty =
                ContentDocumentLinksService.getFilesForLinkedEntities(null);
            List<ContentDocumentLinksService.DeviceEvaluationFileData> rows =
                ContentDocumentLinksService.getFilesForLinkedEntities(
                    new Set<Id>{ account.Id }
                );
            Test.stopTest();

            Assert.isTrue(empty.isEmpty(), 'Null entity set should return empty');
            Assert.areEqual(1, rows.size(), 'One linked image should be returned');
            Assert.areEqual(version.ContentDocumentId, rows[0].contentDocumentId);
            Assert.areEqual(account.Id, rows[0].linkedEntityId);
            Assert.isTrue(rows[0].isImage, 'jpg should be treated as image');
            Assert.isTrue(
                String.isNotBlank(rows[0].thumbnailUrl),
                'Image should have thumbnail URL'
            );

            Integer linkCount = [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE
                    LinkedEntityId = :account.Id
                    AND ContentDocumentId = :version.ContentDocumentId
            ];
            Assert.areEqual(1, linkCount, 'Attach should create a single link');
        }
    }

    @IsTest
    static void testToFileData_usesFileTypeWhenExtensionMissing() {
        Id contentDocumentId = (Id) (
            ContentDocument.SObjectType.getDescribe().getKeyPrefix() + '000000000001'
        );
        Id contentVersionId = (Id) (
            ContentVersion.SObjectType.getDescribe().getKeyPrefix() + '000000000001'
        );

        // FileType / LastModifiedDate are not writeable on ContentVersion; hydrate via JSON.
        ContentVersion version = (ContentVersion) JSON.deserialize(
            JSON.serialize(
                new Map<String, Object>{
                    'Id' => contentVersionId,
                    'ContentDocumentId' => contentDocumentId,
                    'Title' => 'camera-capture',
                    'PathOnClient' => 'camera-capture',
                    'FileType' => 'JPG'
                }
            ),
            ContentVersion.class
        );

        Test.startTest();
        ContentDocumentLinksService.DeviceEvaluationFileData fileData =
            ContentDocumentLinksService.toFileData(version);
        Test.stopTest();

        Assert.isTrue(fileData.isImage, 'FileType JPG should be treated as image');
        Assert.areEqual('jpg', fileData.fileExtension);
        Assert.isTrue(
            String.isNotBlank(fileData.thumbnailUrl),
            'Image without PathOnClient extension should still get thumbnail URL'
        );
        Assert.isTrue(
            fileData.thumbnailUrl.contains(String.valueOf(contentVersionId)),
            'Thumbnail URL should reference ContentVersion Id'
        );
    }

    @IsTest
    static void testRemoveDocumentFromLinkedEntity_WhenLinked_DeletesLinkAndDocument() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Account account = [SELECT Id FROM Account LIMIT 1];

            adb_ContentVersion versionBuilder = new adb_ContentVersion()
                .title('CDL Remove Test')
                .pathOnClient('cdl-remove-test.jpg')
                .versionData(Blob.valueOf('cdl-remove'));
            versionBuilder.persist();
            ContentVersion version = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :versionBuilder.Id
                LIMIT 1
            ];
            Id contentDocumentId = version.ContentDocumentId;

            ContentDocumentLinksService.attachDocumentsToLinkedEntity(
                account.Id,
                new List<Id>{ contentDocumentId }
            );

            Test.startTest();
            ContentDocumentLinksService.removeDocumentFromLinkedEntity(
                account.Id,
                contentDocumentId
            );
            Test.stopTest();

            List<ContentDocumentLink> remainingLinks = [
                SELECT Id
                FROM ContentDocumentLink
                WHERE
                    ContentDocumentId = :contentDocumentId
                    AND LinkedEntityId = :account.Id
            ];
            Assert.areEqual(0, remainingLinks.size(), 'Link should be removed');

            List<ContentDocument> remainingDocs = [
                SELECT Id
                FROM ContentDocument
                WHERE Id = :contentDocumentId
            ];
            Assert.areEqual(0, remainingDocs.size(), 'Orphaned document should be deleted');
        }
    }

    @IsTest
    static void testRemoveDocumentFromLinkedEntity_WhenNotLinked_Throws() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Account account = [SELECT Id FROM Account LIMIT 1];

            adb_ContentVersion versionBuilder = new adb_ContentVersion()
                .title('CDL Not Linked')
                .pathOnClient('cdl-not-linked.jpg')
                .versionData(Blob.valueOf('cdl-not-linked'));
            versionBuilder.persist();
            ContentVersion version = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :versionBuilder.Id
                LIMIT 1
            ];

            Boolean threw = false;
            try {
                ContentDocumentLinksService.removeDocumentFromLinkedEntity(
                    account.Id,
                    version.ContentDocumentId
                );
            } catch (ContentDocumentLinksService.ContentDocumentLinksServiceException e) {
                threw = true;
                Assert.isTrue(
                    e.getMessage().contains('not attached'),
                    'Expected not-attached message: ' + e.getMessage()
                );
            }
            Assert.isTrue(threw, 'Removing an unlinked document should throw');
        }
    }

    @IsTest
    static void testRemoveDocumentFromLinkedEntity_requiresIds() {
        Boolean threw = false;
        try {
            ContentDocumentLinksService.removeDocumentFromLinkedEntity(null, null);
        } catch (ContentDocumentLinksService.ContentDocumentLinksServiceException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('required'),
                'Expected required-ids message: ' + e.getMessage()
            );
        }
        Assert.isTrue(threw, 'Null ids should throw');
    }
}