/**
 * @description GW-1505 / GW-1506 — Tests for {@link WorkOrderLineItemCaptureService}.
 * @author STERIS
 */
@IsTest
private class WorkOrderLineItemCaptureServiceTest {

    private static final String MIN_PNG_BASE64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

    @IsTest
    static void testSaveMicroscopeImageNullWorkOrderLineItemId() {
        Test.startTest();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult result =
            WorkOrderLineItemCaptureService.saveMicroscopeImage(null, MIN_PNG_BASE64, 'test.png', null, null);
        Test.stopTest();
        Assert.isFalse(result.success, 'Null WOLI Id should fail');
        Assert.isTrue(String.isNotBlank(result.message), 'Failure message should be returned');
    }

    @IsTest
    static void testGetImageFileForAnnotationRejectsNonImageFile() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();
        ContentVersion version = new ContentVersion();
        version.Title = 'Notes';
        version.PathOnClient = 'Notes.pdf';
        version.VersionData = Blob.valueOf('%PDF-1.4');
        insert version;

        version = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ];

        insert new ContentDocumentLink(
            ContentDocumentId = version.ContentDocumentId,
            LinkedEntityId = lineItem.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        Test.startTest();
        try {
            WorkOrderLineItemCaptureService.getImageFileForAnnotation(
                lineItem.Id,
                version.ContentDocumentId
            );
            Assert.fail('Expected AuraHandledException for non-image file');
        } catch (AuraHandledException expected) {
            Assert.isNotNull(expected, 'Expected AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSaveMicroscopeImageBlankImage() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();
        Test.startTest();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult result =
            WorkOrderLineItemCaptureService.saveMicroscopeImage(lineItem.Id, '', 'test.png', null, null);
        Test.stopTest();
        Assert.isFalse(result.success, 'Blank image should fail');
        Assert.isTrue(String.isNotBlank(result.message), 'Failure message should be returned');
    }

    @IsTest
    static void testSaveMicroscopeImageInvalidBase64() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();
        Test.startTest();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult result =
            WorkOrderLineItemCaptureService.saveMicroscopeImage(
                lineItem.Id,
                '%%%not-valid-base64%%%',
                'Invalid.png', null, null);
        Test.stopTest();
        Assert.isFalse(result.success, 'Invalid base64 should fail');
        Assert.isTrue(String.isNotBlank(result.message), 'Failure message should be returned');
    }

    @IsTest
    static void testSaveMicroscopeImageAttachesFile() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();
        String dataUrl = 'data:image/png;base64,' + MIN_PNG_BASE64;

        Test.startTest();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult result =
            WorkOrderLineItemCaptureService.saveMicroscopeImage(
                lineItem.Id,
                dataUrl,
                'Microscope_Test_Shot', null, null);
        Test.stopTest();

        Assert.isTrue(result.success, 'Expected successful attach');
        Assert.isNotNull(result.contentDocumentId, 'ContentDocumentId should be returned');
        Assert.isTrue(
            result.fileName.endsWith('.png') || result.fileName.endsWith('.jpg'),
            'File name should include an image extension'
        );

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :lineItem.Id
            AND ContentDocumentId = :result.contentDocumentId
        ];
        Assert.areEqual(1, links.size(), 'File should be linked to WOLI');
    }

    @IsTest
    static void testSaveMicroscopeImageBlankFileName() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();

        Test.startTest();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult result =
            WorkOrderLineItemCaptureService.saveMicroscopeImage(lineItem.Id, MIN_PNG_BASE64, '   ', null, null);
        Test.stopTest();

        Assert.isFalse(result.success, 'Blank file name should fail');
        Assert.isTrue(result.message.contains('File name'), 'Failure should mention file name');
    }

    @IsTest
    static void testSaveMicroscopeImageWorkOrderLineItemNotFound() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();
        Id deletedLineItemId = lineItem.Id;
        delete lineItem;

        Test.startTest();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult result =
            WorkOrderLineItemCaptureService.saveMicroscopeImage(
                deletedLineItemId,
                MIN_PNG_BASE64,
                'Missing_WOLI.png', null, null);
        Test.stopTest();

        Assert.isFalse(result.success, 'Deleted WOLI should fail');
        Assert.isTrue(result.message.contains('not found'), 'Failure should mention missing record');
    }

    @IsTest
    static void testLinkContentDocumentFromVersionRequiresIds() {
        Test.startTest();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult nullWoliResult =
            WorkOrderLineItemCaptureService.linkContentDocumentFromVersion(null, null);
        Test.stopTest();

        Assert.isFalse(nullWoliResult.success, 'Null WOLI Id should fail');
        Assert.isTrue(String.isNotBlank(nullWoliResult.message), 'Failure message should be returned');
    }

    @IsTest
    static void testLinkContentDocumentFromVersionMissingVersion() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();
        ContentVersion version = new ContentVersion();
        version.Title = 'Deleted_Version_Test';
        version.PathOnClient = 'Deleted_Version_Test.png';
        version.VersionData = EncodingUtil.base64Decode(MIN_PNG_BASE64);
        insert version;

        version = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ];
        Id versionId = version.Id;
        delete [SELECT Id FROM ContentDocument WHERE Id = :version.ContentDocumentId];

        Test.startTest();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult result =
            WorkOrderLineItemCaptureService.linkContentDocumentFromVersion(lineItem.Id, versionId);
        Test.stopTest();

        Assert.isFalse(result.success, 'Missing version should fail');
        Assert.isTrue(result.message.contains('not found'), 'Failure should mention missing version');
    }

    @IsTest
    static void testLinkContentDocumentFromVersion() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();
        ContentVersion version = new ContentVersion();
        version.Title = 'Rest_Upload_Test';
        version.PathOnClient = 'Rest_Upload_Test.png';
        version.VersionData = EncodingUtil.base64Decode(MIN_PNG_BASE64);
        insert version;

        version = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ];

        Test.startTest();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult result =
            WorkOrderLineItemCaptureService.linkContentDocumentFromVersion(lineItem.Id, version.Id);
        Test.stopTest();

        Assert.isTrue(result.success, 'REST link helper should succeed');
        Assert.areEqual(version.ContentDocumentId, result.contentDocumentId, 'Document Id should match');

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :lineItem.Id AND ContentDocumentId = :version.ContentDocumentId
        ];
        Assert.areEqual(1, links.size(), 'File should be linked to WOLI');
    }

    @IsTest
    static void testGetRestSessionId() {
        Test.startTest();
        String sessionId = WorkOrderLineItemCaptureService.getRestSessionId();
        Test.stopTest();
        Assert.isTrue(String.isNotBlank(sessionId), 'Session Id should be returned');
    }

    @IsTest
    static void testDiagnoseMicroscopeCaptureAccessWithoutWoli() {
        Test.startTest();
        String report = WorkOrderLineItemCaptureService.diagnoseMicroscopeCaptureAccess(null);
        Test.stopTest();
        Assert.isTrue(String.isNotBlank(report), 'Diagnostic report should be returned');
        Assert.isFalse(report.contains('WOLI record visible'), 'Null WOLI should skip visibility line');
    }

    @IsTest
    static void testUpdateMicroscopeImageCategoryRequiresContentDocumentId() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();

        Test.startTest();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult result =
            WorkOrderLineItemCaptureService.updateMicroscopeImageCategory(lineItem.Id, null, 'Fixable', null);
        Test.stopTest();

        Assert.isFalse(result.success, 'Null ContentDocument Id should fail');
        Assert.isTrue(result.message.contains('File selection'), 'Failure should mention file selection');
    }

    @IsTest
    static void testDiagnoseMicroscopeCaptureAccess() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();

        Test.startTest();
        String report = WorkOrderLineItemCaptureService.diagnoseMicroscopeCaptureAccess(lineItem.Id);
        Test.stopTest();

        Assert.isTrue(String.isNotBlank(report), 'Diagnostic report should be returned');
        Assert.isTrue(report.contains('ContentVersion create'), 'Report should list file permissions');
        Assert.isTrue(report.contains('WOLI record visible: true'), 'WOLI should be visible to test user');
    }

    @IsTest
    static void testListAnnotatableImageFilesNullId() {
        Test.startTest();
        List<WorkOrderLineItemCaptureService.AnnotatableFileSummary> results =
            WorkOrderLineItemCaptureService.listAnnotatableImageFiles(null);
        Test.stopTest();
        Assert.isTrue(results.isEmpty(), 'Null WOLI Id should return an empty list');
    }

    @IsTest
    static void testSaveMicroscopeImageWithCategory() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();

        Test.startTest();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult result =
            WorkOrderLineItemCaptureService.saveMicroscopeImage(
                lineItem.Id,
                MIN_PNG_BASE64,
                'Microscope_Category_Test.png',
                'Fixable',
                null
            );
        Test.stopTest();

        Assert.isTrue(result.success, 'Expected successful attach with category');

        List<ContentVersion> versions = [
            SELECT Category__c
            FROM ContentVersion
            WHERE ContentDocumentId = :result.contentDocumentId AND IsLatest = true
        ];
        Assert.areEqual(1, versions.size(), 'Latest version should exist');
        Assert.areEqual('Fixable', versions[0].Category__c, 'Category should be stored on ContentVersion');
    }

    @IsTest
    static void testUpdateMicroscopeImageCategoryAndReset() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult uploaded =
            WorkOrderLineItemCaptureService.saveMicroscopeImage(
                lineItem.Id,
                MIN_PNG_BASE64,
                'Microscope_Update_Category.png', null, null);
        Assert.isTrue(uploaded.success, 'Setup upload should succeed');

        Test.startTest();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult updateResult =
            WorkOrderLineItemCaptureService.updateMicroscopeImageCategory(
                lineItem.Id,
                uploaded.contentDocumentId,
                'Beyond Repair',
                'Pitting'
            );
        Test.stopTest();

        Assert.isTrue(updateResult.success, 'Category update should succeed');

        ContentVersion version = [
            SELECT Category__c, BeyondRepairReason__c
            FROM ContentVersion
            WHERE ContentDocumentId = :uploaded.contentDocumentId AND IsLatest = true
            LIMIT 1
        ];
        Assert.areEqual('Beyond Repair', version.Category__c, 'Category should be updated');
        Assert.areEqual('Pitting', version.BeyondRepairReason__c, 'Beyond Repair Reason should be updated');

        WorkOrderLineItemCaptureService.MicroscopeCaptureResult resetResult =
            WorkOrderLineItemCaptureService.updateMicroscopeImageCategory(
                lineItem.Id,
                uploaded.contentDocumentId, '', null);
        Assert.isTrue(resetResult.success, 'Category reset should succeed');

        version = [
            SELECT Category__c
            FROM ContentVersion
            WHERE ContentDocumentId = :uploaded.contentDocumentId AND IsLatest = true
            LIMIT 1
        ];
        Assert.isNull(version.Category__c, 'Category should be cleared');
    }

    @IsTest
    static void testSaveMicroscopeImageRejectsInvalidCategory() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();

        Test.startTest();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult result =
            WorkOrderLineItemCaptureService.saveMicroscopeImage(
                lineItem.Id,
                MIN_PNG_BASE64,
                'Microscope_Invalid_Save_Category.png',
                'Not A Real Category',
                null
            );
        Test.stopTest();

        Assert.isFalse(result.success, 'Invalid category on save should fail');
        Assert.isTrue(result.message.contains('Beyond Repair'), 'Failure should mention allowed values');
    }

    @IsTest
    static void testUpdateMicroscopeImageCategoryRequiresIds() {
        Test.startTest();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult nullWoliResult =
            WorkOrderLineItemCaptureService.updateMicroscopeImageCategory(null, null, 'Fixable', null);
        Test.stopTest();

        Assert.isFalse(nullWoliResult.success, 'Null WOLI Id should fail');
        Assert.isTrue(String.isNotBlank(nullWoliResult.message), 'Failure message should be returned');
    }

    @IsTest
    static void testUpdateMicroscopeImageCategoryRejectsUnlinkedDocument() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();
        WorkOrderLineItem otherLine = createWorkOrderLineItem();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult uploaded =
            WorkOrderLineItemCaptureService.saveMicroscopeImage(
                otherLine.Id,
                MIN_PNG_BASE64,
                'Other_Line_Category.png', null, null);

        Test.startTest();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult result =
            WorkOrderLineItemCaptureService.updateMicroscopeImageCategory(
                lineItem.Id,
                uploaded.contentDocumentId, 'Fixable', null);
        Test.stopTest();

        Assert.isFalse(result.success, 'Category update on unlinked file should fail');
        Assert.isTrue(String.isNotBlank(result.message), 'Failure message should be returned');
    }

    @IsTest
    static void testUpdateMicroscopeImageCategoryRejectsInvalidValue() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult uploaded =
            WorkOrderLineItemCaptureService.saveMicroscopeImage(
                lineItem.Id,
                MIN_PNG_BASE64,
                'Microscope_Invalid_Category.png', null, null);

        Test.startTest();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult result =
            WorkOrderLineItemCaptureService.updateMicroscopeImageCategory(
                lineItem.Id,
                uploaded.contentDocumentId, 'Not A Real Category', null);
        Test.stopTest();

        Assert.isFalse(result.success, 'Invalid category should fail');
        Assert.isTrue(result.message.contains('Beyond Repair'), 'Failure should mention allowed values');
    }

    @IsTest
    static void testListWorkOrderLineItemFilesIncludesNonImageFiles() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();
        WorkOrderLineItemCaptureService.saveMicroscopeImage(
            lineItem.Id,
            MIN_PNG_BASE64,
            'Microscope_List_Test.png',
            'Fixable',
            null
        );

        ContentVersion pdfVersion = new ContentVersion();
        pdfVersion.Title = 'Notes';
        pdfVersion.PathOnClient = 'Notes.pdf';
        pdfVersion.VersionData = Blob.valueOf('%PDF-1.4');
        insert pdfVersion;

        pdfVersion = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :pdfVersion.Id
            LIMIT 1
        ];

        insert new ContentDocumentLink(
            ContentDocumentId = pdfVersion.ContentDocumentId,
            LinkedEntityId = lineItem.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        Test.startTest();
        List<WorkOrderLineItemCaptureService.AnnotatableFileSummary> allFiles =
            WorkOrderLineItemCaptureService.listWorkOrderLineItemFiles(lineItem.Id);
        List<WorkOrderLineItemCaptureService.AnnotatableFileSummary> imageFiles =
            WorkOrderLineItemCaptureService.listAnnotatableImageFiles(lineItem.Id);
        Test.stopTest();

        Assert.isTrue(allFiles.size() >= 2, 'All-files list should include image and PDF');
        Assert.areEqual(1, imageFiles.size(), 'Image-only list should exclude PDF');

        Boolean imageHasThumbnail = false;
        for (WorkOrderLineItemCaptureService.AnnotatableFileSummary fileRow : allFiles) {
            if (fileRow.fileExtension == 'png' && String.isNotBlank(fileRow.thumbnailUrl)) {
                imageHasThumbnail = true;
                Assert.isTrue(
                    fileRow.thumbnailUrl.contains('rendition=THUMB120BY90'),
                    'Image rows should include a same-origin THUMB120BY90 rendition URL'
                );
            }
        }
        Assert.isTrue(imageHasThumbnail, 'PNG file row should include thumbnailUrl');
    }

    @IsTest
    static void testGetImageThumbnailDataUrl_returnsDataUrlForLinkedImage() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();
        WorkOrderLineItemCaptureService.saveMicroscopeImage(
            lineItem.Id,
            MIN_PNG_BASE64,
            'Microscope_Thumb_Test.png',
            'Fixable',
            null
        );

        List<WorkOrderLineItemCaptureService.AnnotatableFileSummary> files =
            WorkOrderLineItemCaptureService.listWorkOrderLineItemFiles(lineItem.Id);
        Assert.isFalse(files.isEmpty(), 'Expected at least one linked image file');

        Test.startTest();
        String dataUrl = WorkOrderLineItemCaptureService.getImageThumbnailDataUrl(
            lineItem.Id,
            files[0].contentDocumentId
        );
        Test.stopTest();

        Assert.isTrue(String.isNotBlank(dataUrl), 'Thumbnail URL should be returned');
        Assert.isTrue(
            dataUrl.contains('thumb=THUMB120BY90') || dataUrl.contains('rendition=THUMB120BY90'),
            'Thumbnail URL should reference THUMB120BY90'
        );
    }

    @IsTest
    static void testGetImageThumbnailDataUrls_returnsMapForLinkedImage() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();
        WorkOrderLineItemCaptureService.saveMicroscopeImage(
            lineItem.Id,
            MIN_PNG_BASE64,
            'Microscope_Thumb_Batch_Test.png',
            'Fixable',
            null
        );

        List<WorkOrderLineItemCaptureService.AnnotatableFileSummary> files =
            WorkOrderLineItemCaptureService.listWorkOrderLineItemFiles(lineItem.Id);
        Assert.isFalse(files.isEmpty(), 'Expected at least one linked image file');

        Test.startTest();
        Map<String, String> thumbnails = WorkOrderLineItemCaptureService.getImageThumbnailDataUrls(
            lineItem.Id,
            new List<Id>{ files[0].contentDocumentId }
        );
        Test.stopTest();

        Assert.isTrue(thumbnails.containsKey(String.valueOf(files[0].contentDocumentId)));
        String batchThumbnailUrl = thumbnails.get(String.valueOf(files[0].contentDocumentId));
        Assert.isTrue(
            batchThumbnailUrl.contains('thumb=THUMB120BY90')
                || batchThumbnailUrl.contains('rendition=THUMB120BY90'),
            'Batch thumbnail should reference THUMB120BY90'
        );
    }

    @IsTest
    static void testGetImageThumbnailDataUrl_returnsNullForMissingInputs() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();

        Test.startTest();
        Assert.isNull(
            WorkOrderLineItemCaptureService.getImageThumbnailDataUrl(null, null),
            'Null inputs should return null'
        );
        Assert.isNull(
            WorkOrderLineItemCaptureService.getImageThumbnailDataUrl(lineItem.Id, null),
            'Null ContentDocument Id should return null'
        );
        Assert.isNull(
            WorkOrderLineItemCaptureService.getImageThumbnailDataUrl(null, lineItem.Id),
            'Null WOLI Id should return null'
        );
        Test.stopTest();
    }

    @IsTest
    static void testListAndGetImageFileForAnnotation() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();
        WorkOrderLineItemCaptureService.saveMicroscopeImage(
            lineItem.Id,
            MIN_PNG_BASE64,
            'Microscope_List_Test.png',
            'Fixable',
            null
        );

        Test.startTest();
        List<WorkOrderLineItemCaptureService.AnnotatableFileSummary> summaries =
            WorkOrderLineItemCaptureService.listAnnotatableImageFiles(lineItem.Id);
        Assert.isFalse(summaries.isEmpty(), 'PNG on WOLI should be listable');
        Assert.areEqual('Fixable', summaries[0].category, 'List should include stored category');

        WorkOrderLineItemCaptureService.ImageFileForAnnotation payload =
            WorkOrderLineItemCaptureService.getImageFileForAnnotation(
                lineItem.Id,
                summaries[0].contentDocumentId
            );
        Test.stopTest();

        Assert.isNotNull(payload.base64DataUrl, 'Data URL should be returned');
        Assert.isTrue(
            payload.base64DataUrl.startsWith('data:image/'),
            'Payload should be an image data URL'
        );
        Assert.isNotNull(payload.fileName, 'File name should be returned');
        Assert.areEqual('Fixable', payload.category, 'Annotation payload should include source category');
    }

    @IsTest
    static void testGetImageFileForAnnotationRequiresIds() {
        Test.startTest();
        try {
            WorkOrderLineItemCaptureService.getImageFileForAnnotation(null, null);
            Assert.fail('Expected AuraHandledException when Ids are missing');
        } catch (AuraHandledException expected) {
            Assert.isNotNull(expected, 'Expected AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetImageFileForAnnotationRejectsUnlinkedDocument() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();
        WorkOrderLineItem otherLine = createWorkOrderLineItem();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult uploaded =
            WorkOrderLineItemCaptureService.saveMicroscopeImage(
                otherLine.Id,
                MIN_PNG_BASE64,
                'Other_Line.png', null, null);

        Test.startTest();
        try {
            WorkOrderLineItemCaptureService.getImageFileForAnnotation(
                lineItem.Id,
                uploaded.contentDocumentId
            );
            Assert.fail('Expected AuraHandledException for file on another WOLI');
        } catch (AuraHandledException expected) {
            Assert.isNotNull(expected, 'Expected AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSaveMicroscopeImageWithBeyondRepairReason() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();

        Test.startTest();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult result =
            WorkOrderLineItemCaptureService.saveMicroscopeImage(
                lineItem.Id,
                MIN_PNG_BASE64,
                'Microscope_Beyond_Repair.png',
                'Beyond Repair',
                'Pitting'
            );
        Test.stopTest();

        Assert.isTrue(result.success, 'Expected successful attach with Beyond Repair Reason');

        ContentVersion version = [
            SELECT Category__c, BeyondRepairReason__c
            FROM ContentVersion
            WHERE ContentDocumentId = :result.contentDocumentId AND IsLatest = true
            LIMIT 1
        ];
        Assert.areEqual('Beyond Repair', version.Category__c, 'Category should be stored');
        Assert.areEqual('Pitting', version.BeyondRepairReason__c, 'Beyond Repair Reason should be stored');
    }

    @IsTest
    static void testSaveMicroscopeImageRequiresBeyondRepairReason() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();

        Test.startTest();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult result =
            WorkOrderLineItemCaptureService.saveMicroscopeImage(
                lineItem.Id,
                MIN_PNG_BASE64,
                'Microscope_Missing_Reason.png',
                'Beyond Repair',
                null
            );
        Test.stopTest();

        Assert.isFalse(result.success, 'Beyond Repair without reason should fail');
        Assert.isTrue(
            result.message.contains('Beyond Repair Reason'),
            'Failure should mention Beyond Repair Reason'
        );
    }

    @IsTest
    static void testUpdateMicroscopeImageCategoryRejectsReasonWhenNotBeyondRepair() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult uploaded =
            WorkOrderLineItemCaptureService.saveMicroscopeImage(
                lineItem.Id,
                MIN_PNG_BASE64,
                'Microscope_Reason_On_Fixable.png',
                null,
                null
            );

        Test.startTest();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult result =
            WorkOrderLineItemCaptureService.updateMicroscopeImageCategory(
                lineItem.Id,
                uploaded.contentDocumentId,
                'Fixable',
                'Pitting'
            );
        Test.stopTest();

        Assert.isFalse(result.success, 'Reason on Fixable category should fail');
        Assert.isTrue(
            result.message.contains('Beyond Repair'),
            'Failure should mention Beyond Repair category requirement'
        );
    }

    @IsTest
    static void testDeleteMicroscopeImageFile() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult uploaded =
            WorkOrderLineItemCaptureService.saveMicroscopeImage(
                lineItem.Id,
                MIN_PNG_BASE64,
                'Microscope_Delete_Test.png',
                'Fixable',
                null
            );
        Assert.isTrue(uploaded.success, 'Setup upload should succeed');

        Test.startTest();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult deleteResult =
            WorkOrderLineItemCaptureService.deleteMicroscopeImageFile(
                lineItem.Id,
                uploaded.contentDocumentId
            );
        Test.stopTest();

        Assert.isTrue(deleteResult.success, 'Delete should succeed');

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :lineItem.Id
            AND ContentDocumentId = :uploaded.contentDocumentId
        ];
        Assert.isTrue(links.isEmpty(), 'File link should be removed from WOLI');
    }

    @IsTest
    static void testDeleteMicroscopeImageFileRejectsUnlinkedDocument() {
        WorkOrderLineItem lineItem = createWorkOrderLineItem();
        WorkOrderLineItem otherLine = createWorkOrderLineItem();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult uploaded =
            WorkOrderLineItemCaptureService.saveMicroscopeImage(
                otherLine.Id,
                MIN_PNG_BASE64,
                'Other_Line_Delete.png',
                null,
                null
            );

        Test.startTest();
        WorkOrderLineItemCaptureService.MicroscopeCaptureResult result =
            WorkOrderLineItemCaptureService.deleteMicroscopeImageFile(
                lineItem.Id,
                uploaded.contentDocumentId
            );
        Test.stopTest();

        Assert.isFalse(result.success, 'Delete on unlinked file should fail');
        Assert.isTrue(String.isNotBlank(result.message), 'Failure message should be returned');
    }

    @TestVisible
    private static WorkOrderLineItem createWorkOrderLineItem() {
        Account account = buildCaptureTestAccount('WOLI Capture Test Account');
        insert account;

        WorkOrder workOrder = new WorkOrder(AccountId = account.Id, Status = 'New');
        insert workOrder;

        WorkOrderLineItem lineItem = new WorkOrderLineItem(WorkOrderId = workOrder.Id, Status = 'New');
        insert lineItem;
        return lineItem;
    }

    private static Account buildCaptureTestAccount(String accountName) {
        Schema.RecordTypeInfo prospectRt =
            Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Prospect');
        Account account = new Account(Name = accountName);
        if (prospectRt != null) {
            account.RecordTypeId = prospectRt.getRecordTypeId();
            account.BillingStreet = '100 Microscope Test Ln';
            account.BillingCity = 'Mentor';
            account.BillingPostalCode = '44060';
            account.BillingCountryCode = 'US';
            account.ShippingStateCode = 'OH';
        } else if (Schema.sObjectType.Account.fields.getMap().containsKey('SystemID__c')) {
            String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
            account.put('SystemID__c', ('WOLICAP' + suffix).substring(0, Math.min(12, ('WOLICAP' + suffix).length())));
        }
        return account;
    }
}