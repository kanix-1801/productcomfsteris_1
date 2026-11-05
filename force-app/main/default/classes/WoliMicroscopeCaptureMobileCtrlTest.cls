/**
 * @author Sagar Anand
 * @date 2026-10-19
 * @group Field Service Mobile
 * @description GW-359 — Tests for WoliMicroscopeCaptureMobileCtrl: results shaped for the LWC, this
 *              component's checks, failures from the reused services, and a bulk (201 files) scenario.
 * @see WoliMicroscopeCaptureMobileCtrl
 */
@IsTest
private class WoliMicroscopeCaptureMobileCtrlTest {
    // 1x1 PNG
    private static final String PNG_BASE64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    private static final Integer BULK_FILE_COUNT = 201;
    /** @description ContentDocumentLinksService.getFilesForLinkedEntities returns at most this many files. */
    private static final Integer REUSED_SERVICE_FILE_CAP = 200;

    private class SelectorException extends Exception {
    }

    /**
     * @description ContentDocumentLinks selector that fails every query (reused-service failure path).
     */
    private class ThrowingLinksSelector implements ContentDocumentLinksService.IContentDocumentLinksSelector {
        public List<ContentDocumentLink> selectById(Set<Id> linkIds) {
            throw new SelectorException('selectById failed');
        }
        public List<ContentDocumentLink> selectByLinkedEntityIdsLimited(Set<Id> linkedEntityIds, Integer rowLimit) {
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
        public List<ContentDocumentLink> selectLinkedEntityIdsByContentDocumentId(Id contentDocumentId) {
            throw new SelectorException('selectLinkedEntityIdsByContentDocumentId failed');
        }
    }

    /**
     * @description ContentVersions selector that fails every query (reused-service failure path). Also declares
     *              the title / version-data methods expected back in ContentVersionsService, so it keeps compiling
     *              when they are restored to the interface.
     */
    private class ThrowingVersionsSelector implements ContentVersionsService.IContentVersionsSelector {
        public List<ContentVersion> selectById(Set<Id> contentVersionIds) {
            throw new SelectorException('selectById failed');
        }
        public List<ContentVersion> selectLatestForDeviceEvaluationRename(Id contentDocumentId) {
            throw new SelectorException('selectLatestForDeviceEvaluationRename failed');
        }
        public List<ContentVersion> selectForDeviceEvaluationFileRowById(Id contentVersionId) {
            throw new SelectorException('selectForDeviceEvaluationFileRowById failed');
        }
        public List<ContentVersion> selectLatestForDeviceEvaluationByDocumentIds(Set<Id> contentDocumentIds) {
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

    @TestSetup
    static void setupData() {
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder();
        workOrderBuilder.persist();

        WorkOrderLineItem lineItem = (WorkOrderLineItem) new adb_WorkOrderLineItem()
            .description('WOLI Photo Capture Test Line Item')
            .record;
        lineItem.WorkOrderId = workOrderBuilder.id;
        // Test data is set up in system mode; the code under test runs in user mode
        Database.insert(lineItem, AccessLevel.SYSTEM_MODE);
    }

    /**
     * @description Only images the annotator can open are returned (not PDF, not BMP).
     */
    @IsTest
    static void testListAnnotatableImageFilesReturnsOnlyAnnotatableImages() {
        /********************************************
         * SETUP
         ********************************************/
        User contextUser = new User(Id = UserInfo.getUserId());
        Id lineItemId = getLineItemId();

        /********************************************
         * GIVEN
         ********************************************/
        Database.insert(
            new List<ContentVersion>{
                buildVersion('Before.png', Blob.valueOf('png'), lineItemId),
                buildVersion('Notes.pdf', Blob.valueOf('%PDF-1.4'), lineItemId),
                buildVersion('Scan.bmp', Blob.valueOf('bmp'), lineItemId)
            },
            AccessLevel.SYSTEM_MODE
        );
        Assert.areEqual(3, countLinks(lineItemId), 'Three files should be linked before the call');

        /********************************************
         * WHEN
         ********************************************/
        List<WoliMicroscopeCaptureMobileCtrl.ImageFile> files;
        Test.startTest();
        System.runAs(contextUser) {
            files = WoliMicroscopeCaptureMobileCtrl.listAnnotatableImageFiles(lineItemId);
        }
        Test.stopTest();

        /********************************************
         * THEN
         ********************************************/
        Assert.areEqual(1, files.size(), 'Only the PNG should be annotatable');
        Assert.areEqual('Before.png', files[0].title, 'The PNG title should be returned');
        Assert.isNotNull(files[0].contentDocumentId, 'The ContentDocument Id should be returned');
    }

    /**
     * @description Bulk: with 201 image files, the reused service's 200-file cap applies.
     */
    @IsTest
    static void testListAnnotatableImageFilesBulk() {
        /********************************************
         * SETUP
         ********************************************/
        User contextUser = new User(Id = UserInfo.getUserId());
        Id lineItemId = getLineItemId();

        /********************************************
         * GIVEN
         ********************************************/
        List<ContentVersion> versionList = new List<ContentVersion>();
        for (Integer i = 0; i < BULK_FILE_COUNT; i++) {
            versionList.add(buildVersion('Photo_' + i + '.png', Blob.valueOf('png' + i), lineItemId));
        }
        Database.insert(versionList, AccessLevel.SYSTEM_MODE);
        Assert.areEqual(BULK_FILE_COUNT, countLinks(lineItemId), 'All files should be linked before the call');

        /********************************************
         * WHEN
         ********************************************/
        List<WoliMicroscopeCaptureMobileCtrl.ImageFile> files;
        Test.startTest();
        System.runAs(contextUser) {
            files = WoliMicroscopeCaptureMobileCtrl.listAnnotatableImageFiles(lineItemId);
        }
        Test.stopTest();

        /********************************************
         * THEN
         ********************************************/
        Assert.areEqual(REUSED_SERVICE_FILE_CAP, files.size(), 'The 200 most recently linked files should be returned');
    }

    /**
     * @description A null line item Id returns an empty list.
     */
    @IsTest
    static void testListAnnotatableImageFilesNullId() {
        /********************************************
         * SETUP
         ********************************************/
        User contextUser = new User(Id = UserInfo.getUserId());

        /********************************************
         * GIVEN
         ********************************************/
        Id lineItemId = null;

        /********************************************
         * WHEN
         ********************************************/
        List<WoliMicroscopeCaptureMobileCtrl.ImageFile> files;
        Test.startTest();
        System.runAs(contextUser) {
            files = WoliMicroscopeCaptureMobileCtrl.listAnnotatableImageFiles(lineItemId);
        }
        Test.stopTest();

        /********************************************
         * THEN
         ********************************************/
        Assert.isNotNull(files, 'A list should always be returned');
        Assert.isTrue(files.isEmpty(), 'No files should be returned for a null Id');
    }

    /**
     * @description A failure in the reused service is returned to the LWC as a readable message.
     */
    @IsTest
    static void testListAnnotatableImageFilesServiceFailure() {
        /********************************************
         * SETUP
         ********************************************/
        User contextUser = new User(Id = UserInfo.getUserId());
        Id lineItemId = getLineItemId();

        /********************************************
         * GIVEN
         ********************************************/
        ContentDocumentLinksService.selectorOverride = new ThrowingLinksSelector();

        /********************************************
         * WHEN
         ********************************************/
        String message;
        Test.startTest();
        System.runAs(contextUser) {
            try {
                WoliMicroscopeCaptureMobileCtrl.listAnnotatableImageFiles(lineItemId);
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
        }
        Test.stopTest();

        /********************************************
         * THEN
         ********************************************/
        Assert.areEqual(WoliMicroscopeCaptureMobileCtrl.ERROR_LIST_FILES, message, 'A readable error should be thrown');
    }

    /**
     * @description Files are sorted newest first; files without a date go last.
     */
    @IsTest
    static void testImageFilesSortNewestFirst() {
        /********************************************
         * SETUP
         ********************************************/
        User contextUser = new User(Id = UserInfo.getUserId());

        /********************************************
         * GIVEN
         ********************************************/
        List<WoliMicroscopeCaptureMobileCtrl.ImageFile> files = new List<WoliMicroscopeCaptureMobileCtrl.ImageFile>{
            buildImageFile('Undated', null),
            buildImageFile('Old', Datetime.newInstance(2026, 1, 1)),
            buildImageFile('New', Datetime.newInstance(2026, 6, 1)),
            buildImageFile('AlsoUndated', null)
        };

        /********************************************
         * WHEN
         ********************************************/
        Test.startTest();
        System.runAs(contextUser) {
            files.sort();
        }
        Test.stopTest();

        /********************************************
         * THEN
         ********************************************/
        Assert.areEqual('New', files[0].title, 'The newest file should be first');
        Assert.areEqual('Old', files[1].title, 'The older file should be second');
        Assert.isNull(files[3].lastModifiedDate, 'Undated files should be last');
    }

    /**
     * @description An image on the line item is returned as a PNG data URL.
     */
    @IsTest
    static void testGetImageFileForAnnotationReturnsDataUrl() {
        /********************************************
         * SETUP
         ********************************************/
        User contextUser = new User(Id = UserInfo.getUserId());
        Id lineItemId = getLineItemId();

        /********************************************
         * GIVEN
         ********************************************/
        Id contentDocumentId = insertAndGetDocumentId(
            buildVersion('Before.png', EncodingUtil.base64Decode(PNG_BASE64), lineItemId)
        );
        Assert.areEqual(1, countLinks(lineItemId), 'The image should be linked before the call');

        /********************************************
         * WHEN
         ********************************************/
        WoliMicroscopeCaptureMobileCtrl.AnnotationImage image;
        Test.startTest();
        System.runAs(contextUser) {
            image = WoliMicroscopeCaptureMobileCtrl.getImageFileForAnnotation(lineItemId, contentDocumentId);
        }
        Test.stopTest();

        /********************************************
         * THEN
         ********************************************/
        Assert.areEqual(contentDocumentId, image.contentDocumentId, 'The requested file should be returned');
        Assert.areEqual('Before.png', image.fileName, 'The file name should be returned');
        Assert.areEqual(
            'data:image/png;base64,' + PNG_BASE64,
            image.base64DataUrl,
            'The image should be returned as a PNG data URL'
        );
    }

    /**
     * @description This component's checks are returned with user-facing messages.
     */
    @IsTest
    static void testGetImageFileForAnnotationValidationMessages() {
        /********************************************
         * SETUP
         ********************************************/
        User contextUser = new User(Id = UserInfo.getUserId());
        Id lineItemId = getLineItemId();

        /********************************************
         * GIVEN
         ********************************************/
        Id pdfDocumentId = insertAndGetDocumentId(
            buildVersion('Notes.pdf', Blob.valueOf('%PDF-1.4'), lineItemId)
        );
        Id largeDocumentId = insertAndGetDocumentId(
            buildVersion('Large.png', Blob.valueOf('x'.repeat(900001)), lineItemId)
        );
        Id unlinkedDocumentId = insertAndGetDocumentId(buildVersion('Other.png', Blob.valueOf('png'), null));
        Assert.areEqual(2, countLinks(lineItemId), 'Only the PDF and the large image should be linked');

        /********************************************
         * WHEN
         ********************************************/
        Map<String, String> messageByCase = new Map<String, String>();
        Test.startTest();
        System.runAs(contextUser) {
            messageByCase.put('ids', getAnnotationError(lineItemId, null));
            messageByCase.put('notLinked', getAnnotationError(lineItemId, unlinkedDocumentId));
            messageByCase.put('notImage', getAnnotationError(lineItemId, pdfDocumentId));
            messageByCase.put('tooLarge', getAnnotationError(lineItemId, largeDocumentId));
        }
        Test.stopTest();

        /********************************************
         * THEN
         ********************************************/
        Assert.areEqual(WoliMicroscopeCaptureMobileCtrl.ERROR_IDS_REQUIRED, messageByCase.get('ids'), 'Ids');
        Assert.areEqual(WoliMicroscopeCaptureMobileCtrl.ERROR_NOT_LINKED, messageByCase.get('notLinked'), 'Link');
        Assert.areEqual(WoliMicroscopeCaptureMobileCtrl.ERROR_NOT_IMAGE, messageByCase.get('notImage'), 'Type');
        Assert.areEqual(WoliMicroscopeCaptureMobileCtrl.ERROR_TOO_LARGE, messageByCase.get('tooLarge'), 'Size');
    }

    /**
     * @description Failures in the reused services return the generic message.
     */
    @IsTest
    static void testGetImageFileForAnnotationServiceFailures() {
        /********************************************
         * SETUP
         ********************************************/
        User contextUser = new User(Id = UserInfo.getUserId());
        Id lineItemId = getLineItemId();

        /********************************************
         * GIVEN
         ********************************************/
        Id contentDocumentId = insertAndGetDocumentId(
            buildVersion('Before.png', Blob.valueOf('png'), lineItemId)
        );

        /********************************************
         * WHEN
         ********************************************/
        String versionServiceMessage;
        String linkServiceMessage;
        Test.startTest();
        System.runAs(contextUser) {
            ContentVersionsService.selectorOverride = new ThrowingVersionsSelector();
            versionServiceMessage = getAnnotationError(lineItemId, contentDocumentId);
            ContentDocumentLinksService.selectorOverride = new ThrowingLinksSelector();
            linkServiceMessage = getAnnotationError(lineItemId, contentDocumentId);
        }
        Test.stopTest();

        /********************************************
         * THEN
         ********************************************/
        Assert.areEqual(
            WoliMicroscopeCaptureMobileCtrl.ERROR_LOAD_FILE,
            versionServiceMessage,
            'A ContentVersions failure should return the generic message'
        );
        Assert.areEqual(
            WoliMicroscopeCaptureMobileCtrl.ERROR_LOAD_FILE,
            linkServiceMessage,
            'A ContentDocumentLinks failure should return the generic message'
        );
    }

    /**
     * @description MIME type mapping and the AuraHandledException helper.
     */
    @IsTest
    static void testHelpers() {
        /********************************************
         * SETUP
         ********************************************/
        User contextUser = new User(Id = UserInfo.getUserId());

        /********************************************
         * WHEN
         ********************************************/
        AuraHandledException auraException;
        Test.startTest();
        System.runAs(contextUser) {
            auraException = WoliMicroscopeCaptureMobileCtrl.toAuraHandledException(
                WoliMicroscopeCaptureMobileCtrl.ERROR_LIST_FILES
            );
        }
        Test.stopTest();

        /********************************************
         * THEN
         ********************************************/
        Assert.areEqual(
            WoliMicroscopeCaptureMobileCtrl.ERROR_LIST_FILES,
            auraException.getMessage(),
            'The message should be readable from Apex'
        );
        Assert.areEqual('image/jpeg', WoliMicroscopeCaptureMobileCtrl.resolveMimeType('JPG', 'JPG'), 'JPG');
        Assert.areEqual('image/webp', WoliMicroscopeCaptureMobileCtrl.resolveMimeType(null, 'webp'), 'WebP');
        Assert.areEqual('image/bmp', WoliMicroscopeCaptureMobileCtrl.resolveMimeType('image/bmp', 'bmp'), 'FileType');
        Assert.areEqual('image/png', WoliMicroscopeCaptureMobileCtrl.resolveMimeType(null, null), 'PNG default');
    }

    private static String getAnnotationError(Id lineItemId, Id contentDocumentId) {
        try {
            WoliMicroscopeCaptureMobileCtrl.getImageFileForAnnotation(lineItemId, contentDocumentId);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    private static Id getLineItemId() {
        return [SELECT Id FROM WorkOrderLineItem LIMIT 1].Id;
    }

    private static Integer countLinks(Id lineItemId) {
        return [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :lineItemId];
    }

    private static Id insertAndGetDocumentId(ContentVersion version) {
        Database.insert(version, AccessLevel.SYSTEM_MODE);
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id].ContentDocumentId;
    }

    private static WoliMicroscopeCaptureMobileCtrl.ImageFile buildImageFile(
        String title,
        Datetime lastModifiedDate
    ) {
        WoliMicroscopeCaptureMobileCtrl.ImageFile imageFile = new WoliMicroscopeCaptureMobileCtrl.ImageFile();
        imageFile.title = title;
        imageFile.lastModifiedDate = lastModifiedDate;
        return imageFile;
    }

    /**
     * @description Builds a ContentVersion; when lineItemId is set it is linked on insert
     *              (FirstPublishLocationId creates the ContentDocumentLink).
     */
    private static ContentVersion buildVersion(String fileName, Blob body, Id lineItemId) {
        ContentVersion version = (ContentVersion) new adb_ContentVersion()
            .title(fileName)
            .pathOnClient(fileName)
            .versionData(body)
            .record;
        if (lineItemId != null) {
            version.FirstPublishLocationId = lineItemId;
        }
        return version;
    }
}