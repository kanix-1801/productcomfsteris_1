/**
 * @description Minimal tests for ContentVersionsService Device Evaluation methods
 *              (GW-3913 / GW-3096).
 */
@IsTest
private class ContentVersionsServiceTest {
    private class SelectorException extends Exception {
    }

    private class ThrowingSelector
        implements ContentVersionsService.IContentVersionsSelector {
        public List<ContentVersion> selectById(Set<Id> contentVersionIds) {
            throw new SelectorException('selectById failed');
        }

        public List<ContentVersion> selectLatestForDeviceEvaluationRename(
            Id contentDocumentId
        ) {
            throw new SelectorException('selectLatestForDeviceEvaluationRename failed');
        }

        public List<ContentVersion> selectForDeviceEvaluationFileRowById(
            Id contentVersionId
        ) {
            throw new SelectorException('selectForDeviceEvaluationFileRowById failed');
        }

        public List<ContentVersion> selectLatestForDeviceEvaluationByDocumentIds(
            Set<Id> contentDocumentIds
        ) {
            throw new SelectorException('selectLatestForDeviceEvaluationByDocumentIds failed');
        }

        public List<ContentVersion> selectLatestByContentDocumentIdsAndTitle(
            Set<Id> contentDocumentIds,
            String titleContains
        ) {
            throw new SelectorException('selectLatestByContentDocumentIdsAndTitle failed');
        }

        public List<ContentVersion> selectVersionDataById(Id contentVersionId) {
            throw new SelectorException('selectVersionDataById failed');
        }
    }

    @IsTest
    static void testDeviceEvaluationContentVersionMethods() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            adb_ContentVersion versionBuilder = new adb_ContentVersion()
                .title('CV Service Test')
                .pathOnClient('cv-service-test.jpg')
                .versionData(Blob.valueOf('cv-service'));
            versionBuilder.persist();
            ContentVersion version = [
                SELECT Id, ContentDocumentId, Title
                FROM ContentVersion
                WHERE Id = :versionBuilder.Id
                LIMIT 1
            ];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<ContentVersion> created = ContentVersionsService.createContentVersions(
                new List<ContentVersion>{
                    new ContentVersion(
                        Title = 'CV Service Created',
                        PathOnClient = 'cv-created.jpg',
                        VersionData = Blob.valueOf('created'),
                        IsMajorVersion = true
                    )
                }
            );
            List<ContentVersion> byIds = ContentVersionsService.getContentVersionsById(
                new Set<Id>{ version.Id }
            );
            Assert.isTrue(ContentVersionsService.createContentVersions(null).isEmpty());
            Assert.isTrue(ContentVersionsService.getContentVersionsById(null).isEmpty());
            Assert.isFalse(created.isEmpty(), 'createContentVersions should return inserted rows');
            Assert.areEqual(1, byIds.size(), 'getContentVersionsById should return the version');

            ContentVersion fileRow = ContentVersionsService.getForDeviceEvaluationFileRow(version.Id);
            ContentVersion forRename =
                ContentVersionsService.getLatestForDeviceEvaluationRename(version.ContentDocumentId);
            List<ContentVersion> latestList =
                ContentVersionsService.getLatestForDeviceEvaluationByDocumentIds(
                    new Set<Id>{ version.ContentDocumentId }
                );
            ContentVersionsService.updateContentVersions(
                new List<ContentVersion>{
                    new ContentVersion(Id = version.Id, Title = 'CV Service Renamed')
                }
            );
            ContentVersion nullFileRow = ContentVersionsService.getForDeviceEvaluationFileRow(null);
            ContentVersion nullRename =
                ContentVersionsService.getLatestForDeviceEvaluationRename(null);
            List<ContentVersion> emptyLatest =
                ContentVersionsService.getLatestForDeviceEvaluationByDocumentIds(null);
            ContentVersionsService.updateContentVersions(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(fileRow, 'File row lookup should return the version');
            Assert.areEqual(version.Id, fileRow.Id);
            Assert.isNotNull(forRename, 'Rename lookup should return latest version');
            Assert.areEqual(UserInfo.getUserId(), forRename.ContentDocument.CreatedById);
            Assert.areEqual(1, latestList.size(), 'Latest-by-document should return one version');
            Assert.isNull(nullFileRow, 'Null contentVersionId should return null');
            Assert.isNull(nullRename, 'Null contentDocumentId should return null');
            Assert.isTrue(emptyLatest.isEmpty(), 'Null document Ids should return empty list');

            ContentVersion refreshed = [
                SELECT Title
                FROM ContentVersion
                WHERE Id = :version.Id
                LIMIT 1
            ];
            Assert.areEqual('CV Service Renamed', refreshed.Title, 'Title should be updated');

            ContentDocument owned = ContentDocumentsService.getOwnedDocumentForDeviceEvaluation(
                version.ContentDocumentId,
                UserInfo.getUserId()
            );
            Assert.isNotNull(owned, 'Owned document lookup should succeed for creator');
            Assert.isNull(
                ContentDocumentsService.getOwnedDocumentForDeviceEvaluation(null, null),
                'Null inputs should return null'
            );
        }
    }

    @IsTest
    static void testStageAndRenamePhotoForDeviceEvaluationValidation() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Boolean threw = false;
            try {
                ContentVersionsService.stagePhotoForDeviceEvaluation(null, 'abc', 'x.jpg');
            } catch (ContentVersionsService.ContentVersionsServiceException e) {
                threw = true;
                Assert.isTrue(e.getMessage().contains('Repair code product'));
            }
            Assert.isTrue(threw, 'stage requires productId');

            threw = false;
            try {
                ContentVersionsService.stagePhotoForDeviceEvaluation(
                    UserInfo.getUserId(),
                    ' ',
                    'x.jpg'
                );
            } catch (ContentVersionsService.ContentVersionsServiceException e) {
                threw = true;
                Assert.isTrue(e.getMessage().contains('File data'));
            }
            Assert.isTrue(threw, 'stage requires file data');

            threw = false;
            try {
                ContentVersionsService.renamePhotoForDeviceEvaluation(null, 'Title');
            } catch (ContentVersionsService.ContentVersionsServiceException e) {
                threw = true;
                Assert.isTrue(e.getMessage().contains('File is required'));
            }
            Assert.isTrue(threw, 'rename requires contentDocumentId');
        }
    }

    @IsTest
    static void testStageAndRenamePhotoForDeviceEvaluation() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Product2 describedProduct = new Product2(
                Name = 'GW-3913 Stage Name',
                ProductCode = 'GW3913-STG',
                Description = 'Staged device photo',
                IsActive = true
            );
            Product2 namedProduct = new Product2(
                Name = 'GW-3913 Name Only',
                ProductCode = 'GW3913-NAME',
                IsActive = true
            );
            insert new List<Product2>{ describedProduct, namedProduct };

            String dataUrl =
                'data:image/jpeg;base64,' +
                EncodingUtil.base64Encode(Blob.valueOf('device-eval-photo'));

            Test.startTest();
            ContentVersionsService.StagedPhotoResult described =
                ContentVersionsService.stagePhotoForDeviceEvaluation(
                    describedProduct.Id,
                    dataUrl,
                    'DeviceEval'
                );
            ContentVersionsService.StagedPhotoResult named =
                ContentVersionsService.stagePhotoForDeviceEvaluation(
                    namedProduct.Id,
                    EncodingUtil.base64Encode(Blob.valueOf('second-photo')),
                    null
                );
            ContentVersion renamed = ContentVersionsService.renamePhotoForDeviceEvaluation(
                described.version.ContentDocumentId,
                'Renamed Photo.jpg'
            );
            Test.stopTest();

            Assert.areEqual('DeviceEval', described.version.Title);
            Assert.areEqual(describedProduct.Id, described.productId);
            Assert.areEqual('GW3913-STG', described.productCode);
            Assert.areEqual('Staged device photo', described.productName);
            Assert.isTrue(
                named.version.Title.startsWith('DeviceEval-'),
                'Blank file name should use the default title'
            );
            Assert.areEqual('GW-3913 Name Only', named.productName);
            Assert.areEqual('Renamed Photo', renamed.Title);

            Boolean threw = false;
            try {
                ContentVersionsService.renamePhotoForDeviceEvaluation(
                    described.version.ContentDocumentId,
                    ' '
                );
            } catch (ContentVersionsService.ContentVersionsServiceException e) {
                threw = true;
                Assert.isTrue(e.getMessage().contains('Photo title is required'));
            }
            Assert.isTrue(threw, 'rename requires a title');

            threw = false;
            try {
                ContentVersionsService.renamePhotoForDeviceEvaluation(
                    described.version.ContentDocumentId,
                    '.'
                );
            } catch (ContentVersionsService.ContentVersionsServiceException e) {
                threw = true;
                Assert.isTrue(e.getMessage().contains('Photo title is required'));
            }
            Assert.isTrue(threw, 'rename strips a title that is only an extension');

            Id missingDocumentId = (Id) (
                ContentDocument.SObjectType.getDescribe().getKeyPrefix() + '000000000001'
            );
            threw = false;
            try {
                ContentVersionsService.renamePhotoForDeviceEvaluation(missingDocumentId, 'Missing');
            } catch (ContentVersionsService.ContentVersionsServiceException e) {
                threw = true;
                Assert.isTrue(e.getMessage().contains('cannot be renamed'));
            }
            Assert.isTrue(threw, 'rename rejects a missing file');
        }
    }

    @IsTest
    static void testGetContentVersionsById_selectorThrows() {
        assertSelectorFailure('byId');
    }

    @IsTest
    static void testGetLatestForDeviceEvaluationRename_selectorThrows() {
        assertSelectorFailure('rename');
    }

    @IsTest
    static void testGetForDeviceEvaluationFileRow_selectorThrows() {
        assertSelectorFailure('fileRow');
    }

    @IsTest
    static void testGetLatestForDeviceEvaluationByDocumentIds_selectorThrows() {
        assertSelectorFailure('latest');
    }

    @IsTest
    static void testGetLatestByContentDocumentIdsAndTitle_selectorThrows() {
        assertSelectorFailure('title');
    }

    @IsTest
    static void testGetVersionDataById_selectorThrows() {
        assertSelectorFailure('versionData');
    }

    @IsTest
    static void testLatestByTitleAndVersionData() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            adb_ContentVersion olderBuilder = new adb_ContentVersion()
                .title('RO Form Older')
                .pathOnClient('ro-form-older.pdf')
                .versionData(Blob.valueOf('older-bytes'));
            olderBuilder.persist();
            adb_ContentVersion newerBuilder = new adb_ContentVersion()
                .title('RO Form Newer')
                .pathOnClient('ro-form-newer.pdf')
                .versionData(Blob.valueOf('ro-form-bytes'));
            newerBuilder.persist();
            Test.setCreatedDate(olderBuilder.Id, Datetime.now().addDays(-2));
            Test.setCreatedDate(newerBuilder.Id, Datetime.now());

            Map<Id, ContentVersion> versionsById = new Map<Id, ContentVersion>([
                SELECT Id, ContentDocumentId, Title
                FROM ContentVersion
                WHERE Id IN :new Set<Id>{ olderBuilder.Id, newerBuilder.Id }
            ]);
            ContentVersion olderVersion = versionsById.get(olderBuilder.Id);
            ContentVersion newerVersion = versionsById.get(newerBuilder.Id);
            Set<Id> documentIds = new Set<Id>{
                olderVersion.ContentDocumentId,
                newerVersion.ContentDocumentId
            };

            Test.startTest();
            List<ContentVersion> serviceMatch =
                ContentVersionsService.getLatestByContentDocumentIdsAndTitle(
                    documentIds,
                    '  RO Form  '
                );
            List<ContentVersion> serviceMiss =
                ContentVersionsService.getLatestByContentDocumentIdsAndTitle(
                    documentIds,
                    'Shipping Label'
                );
            List<ContentVersion> serviceEmptyIds =
                ContentVersionsService.getLatestByContentDocumentIdsAndTitle(
                    new Set<Id>(),
                    'RO Form'
                );
            List<ContentVersion> serviceNullIds =
                ContentVersionsService.getLatestByContentDocumentIdsAndTitle(null, 'RO Form');
            List<ContentVersion> serviceBlankTitle =
                ContentVersionsService.getLatestByContentDocumentIdsAndTitle(
                    documentIds,
                    ' '
                );
            List<ContentVersion> serviceData =
                ContentVersionsService.getVersionDataById(newerVersion.Id);
            List<ContentVersion> serviceNullData =
                ContentVersionsService.getVersionDataById(null);
            Test.stopTest();

            Assert.areEqual(1, serviceMatch.size(), 'Title search should return one row');
            Assert.areEqual(
                newerVersion.Id,
                serviceMatch[0].Id,
                'Title search should return the newest match'
            );
            Assert.areEqual('RO Form Newer', serviceMatch[0].Title);
            Assert.isTrue(serviceMiss.isEmpty(), 'Unrelated title should return no rows');
            Assert.isTrue(serviceEmptyIds.isEmpty(), 'Empty document Ids should return an empty list');
            Assert.isTrue(serviceNullIds.isEmpty(), 'Null document Ids should return an empty list');
            Assert.isTrue(serviceBlankTitle.isEmpty(), 'Blank title should return an empty list');
            Assert.areEqual(1, serviceData.size(), 'Service version data should return the file');
            Assert.areEqual(
                EncodingUtil.base64Encode(Blob.valueOf('ro-form-bytes')),
                EncodingUtil.base64Encode(serviceData[0].VersionData),
                'Service version data should match the saved file'
            );
            Assert.isTrue(serviceNullData.isEmpty(), 'Null version Id should return an empty list');
        }
    }

    private static void assertSelectorFailure(String operation) {
        Id versionId = (Id)(ContentVersion.SObjectType.getDescribe().getKeyPrefix() +
            '000000000001');
        Id documentId = (Id)(ContentDocument.SObjectType.getDescribe().getKeyPrefix() +
            '000000000001');
        ContentVersionsService.selectorOverride = new ThrowingSelector();
        try {
            Boolean threw = false;
            try {
                if (operation == 'byId') {
                    ContentVersionsService.getContentVersionsById(
                        new Set<Id>{ versionId }
                    );
                } else if (operation == 'rename') {
                    ContentVersionsService.getLatestForDeviceEvaluationRename(documentId);
                } else if (operation == 'fileRow') {
                    ContentVersionsService.getForDeviceEvaluationFileRow(versionId);
                } else if (operation == 'title') {
                    ContentVersionsService.getLatestByContentDocumentIdsAndTitle(
                        new Set<Id>{ documentId },
                        'RO Form'
                    );
                } else if (operation == 'versionData') {
                    ContentVersionsService.getVersionDataById(versionId);
                } else {
                    ContentVersionsService.getLatestForDeviceEvaluationByDocumentIds(
                        new Set<Id>{ documentId }
                    );
                }
            } catch (ContentVersionsService.ContentVersionsServiceException e) {
                threw = true;
                Assert.isNotNull(e.getCause(), 'Wrapped exception should retain its cause');
            }
            Assert.isTrue(threw, operation + ' should wrap selector failures');
        } finally {
            ContentVersionsService.selectorOverride = null;
        }
    }

    @IsTest
    static void testCreateContentVersions_invalidRecordWrapsDmlFailure() {
        Boolean threw = false;
        try {
            ContentVersionsService.createContentVersions(
                new List<ContentVersion>{ new ContentVersion() }
            );
        } catch (ContentVersionsService.ContentVersionsServiceException e) {
            threw = true;
            Assert.isInstanceOfType(e.getCause(), DmlException.class);
        }
        Assert.isTrue(threw, 'Invalid ContentVersion should wrap DML failure');
    }

    @IsTest
    static void testUpdateContentVersions_deletedIdWrapsDmlFailure() {
        ContentVersion version = new ContentVersion(
            Title = 'Deleted version update',
            PathOnClient = 'deleted-version.txt',
            VersionData = Blob.valueOf('content')
        );
        insert version;
        version = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ];
        delete new ContentDocument(Id = version.ContentDocumentId);

        Boolean threw = false;
        try {
            ContentVersionsService.updateContentVersions(
                new List<ContentVersion>{
                    new ContentVersion(Id = version.Id, Title = 'Should fail')
                }
            );
        } catch (ContentVersionsService.ContentVersionsServiceException e) {
            threw = true;
            Assert.isInstanceOfType(e.getCause(), DmlException.class);
        }
        Assert.isTrue(threw, 'Updating a deleted ContentVersion should wrap DML failure');
    }

    /**
     * @description GW-4189 - Service delegates latest PDF lookup used by document email.
     */
    @IsTest
    static void testSelectLatestPdfsByContentDocumentIds() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            ContentVersion pdfVersion = new ContentVersion(
                Title = 'GW4189 Service Pdf',
                PathOnClient = 'gw4189-service.pdf',
                VersionData = Blob.valueOf('service-pdf'),
                IsMajorVersion = true
            );
            insert pdfVersion;
            pdfVersion = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :pdfVersion.Id
            ];

            Test.startTest();
            Assert.isTrue(
                ContentVersionsService.selectLatestPdfsByContentDocumentIds(null).isEmpty(),
                'Null ids should return empty'
            );
            List<ContentVersion> pdfs = ContentVersionsService.selectLatestPdfsByContentDocumentIds(
                new Set<Id>{ pdfVersion.ContentDocumentId }
            );
            Test.stopTest();

            Assert.areEqual(1, pdfs.size(), 'Latest PDF should return');
            Assert.areEqual(pdfVersion.ContentDocumentId, pdfs[0].ContentDocumentId);
            Assert.areEqual('GW4189 Service Pdf', pdfs[0].Title);
        }
    }
}