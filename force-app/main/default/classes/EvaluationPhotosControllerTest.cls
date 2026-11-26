/**
 * @description GW-4378 - Optional evaluation photos on the child Work Order and related Quotes.
 */
@IsTest
private class EvaluationPhotosControllerTest {
    @IsTest
    static void capturePhoto_storesOnChildWorkOrderWithDateTitle() {
        /********************************************
         * GIVEN
         ********************************************/
        WorkOrder child = insertChildWorkOrder();
        String payload = EncodingUtil.base64Encode(Blob.valueOf('gw4378-photo'));

        /********************************************
         * WHEN
         ********************************************/
        Test.startTest();
        EvaluationPhotosController.EvaluationPhotoRow saved = EvaluationPhotosController.capturePhoto(
            child.Id,
            payload,
            'repair.jpg'
        );
        List<EvaluationPhotosController.EvaluationPhotoRow> listed =
            EvaluationPhotosController.getPhotos(child.Id);
        Test.stopTest();

        /********************************************
         * THEN
         ********************************************/
        String expectedDate = Datetime.now().format('yyyy-MM-dd');
        System.assertEquals(expectedDate + ' TBD', saved.title, 'Photo title should be [date] TBD.');
        System.assertEquals(true, saved.isOptional, 'New photos are stored on the Work Order.');
        System.assertEquals(child.Id, saved.linkedEntityId);
        System.assertEquals(1, listed.size(), 'The Photos tab lists the saved Work Order photo.');
        System.assertEquals(saved.contentDocumentId, listed[0].contentDocumentId);

        System.assertEquals(
            1,
            ContentDocumentLinksService.getLinksByDocumentsAndLinkedEntities(
                new Set<Id>{ saved.contentDocumentId },
                new Set<Id>{ child.Id }
            ).size(),
            'The photo is linked to the child Work Order.'
        );
    }

    @IsTest
    static void renameAndDelete_updatesTheWorkOrderPhoto() {
        WorkOrder child = insertChildWorkOrder();
        EvaluationPhotosController.EvaluationPhotoRow saved = EvaluationPhotosController.capturePhoto(
            child.Id,
            EncodingUtil.base64Encode(Blob.valueOf('gw4378-rename')),
            null
        );

        Test.startTest();
        EvaluationPhotosController.EvaluationPhotoRow renamed = EvaluationPhotosController.renamePhoto(
            saved.contentDocumentId,
            'Crack on housing'
        );
        EvaluationPhotosController.deletePhoto(child.Id, child.Id, saved.contentDocumentId);
        Test.stopTest();

        System.assertEquals('Crack on housing', renamed.title);
        System.assertEquals(
            0,
            EvaluationPhotosController.getPhotos(child.Id).size(),
            'Deleting the photo removes it from the Work Order list.'
        );
    }

    @IsTest
    static void attachOptionalPhotosToQuotes_copiesChildWorkOrderPhotos() {
        adb_Account accountBuilder = new adb_Account().name('GW4378 Quote Account');
        WorkOrder parent = new WorkOrder(Subject = 'GW4378 Parent', Status = 'New', Priority = 'Medium');
        accountBuilder.persist();
        parent.AccountId = accountBuilder.Id;
        insert parent;
        WorkOrder child = new WorkOrder(
            Subject = 'GW4378 Child Quote',
            Status = 'New',
            Priority = 'Medium',
            AccountId = accountBuilder.Id,
            ParentWorkOrderId = parent.Id
        );
        insert child;

        EvaluationPhotosController.EvaluationPhotoRow saved = EvaluationPhotosController.capturePhoto(
            child.Id,
            EncodingUtil.base64Encode(Blob.valueOf('gw4378-quote')),
            null
        );

        adb_Opportunity opportunityBuilder = new adb_Opportunity()
            .name('GW4378 Quote Opp')
            .account(accountBuilder);
        useDiscoveryStage(opportunityBuilder);
        opportunityBuilder.persist();
        Quote quoteRecord = new Quote(
            Name = 'GW4378 Quote',
            OpportunityId = opportunityBuilder.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            WorkOrder__c = parent.Id,
            QuoteType__c = 'Trial Quote'
        );
        TriggerHandler.bypass('QuoteTriggerHandler');
        insert quoteRecord;
        TriggerHandler.clearBypass('QuoteTriggerHandler');

        Test.startTest();
        EvaluationPhotosService.attachOptionalPhotosToQuotes(new List<Quote>{ quoteRecord });
        Test.stopTest();

        System.assertEquals(
            1,
            ContentDocumentLinksService.getLinksByDocumentsAndLinkedEntities(
                new Set<Id>{ saved.contentDocumentId },
                new Set<Id>{ quoteRecord.Id }
            ).size(),
            'Optional Work Order photos are included on the related Quote.'
        );
    }

    @IsTest
    static void getPhotos_rejectsAMissingWorkOrder() {
        Boolean unknownThrew = false;
        Test.startTest();
        try {
            EvaluationPhotosController.getPhotos(null);
            System.assert(false, 'A missing Work Order should fail.');
        } catch (AuraHandledException expectedError) {
            System.assert(
                expectedError.getMessage().contains('Work Order is required.'),
                expectedError.getMessage()
            );
        }
        try {
            EvaluationPhotosController.getPhotos(fakeId(WorkOrder.SObjectType));
            System.assert(false, 'An unknown Work Order should fail.');
        } catch (AuraHandledException expectedError) {
            unknownThrew = true;
            System.assert(
                expectedError.getMessage().contains('Work Order was not found.'),
                expectedError.getMessage()
            );
        }
        Test.stopTest();
        System.assertEquals(true, unknownThrew, 'An unknown Work Order should fail.');
    }

    @IsTest
    static void capturePhoto_rejectsAnInvalidPayload() {
        WorkOrder child = insertChildWorkOrder();
        Boolean blankThrew = false;
        Boolean invalidThrew = false;

        Test.startTest();
        try {
            EvaluationPhotosController.capturePhoto(child.Id, '   ', 'repair.jpg');
            System.assert(false, 'A blank photo payload should fail.');
        } catch (AuraHandledException expectedError) {
            blankThrew = true;
            System.assert(
                expectedError.getMessage().contains('File data is required.'),
                expectedError.getMessage()
            );
        }
        try {
            EvaluationPhotosController.capturePhoto(child.Id, '!!!', 'repair.jpg');
            System.assert(false, 'An invalid photo payload should fail.');
        } catch (AuraHandledException expectedError) {
            invalidThrew = true;
            System.assert(
                String.isNotBlank(expectedError.getMessage()),
                'Invalid photo data should surface an error.'
            );
        }
        Test.stopTest();

        System.assertEquals(true, blankThrew, 'A blank photo payload should fail.');
        System.assertEquals(true, invalidThrew, 'An invalid photo payload should fail.');
    }

    @IsTest
    static void renamePhoto_rejectsAMissingFileAndBlankTitle() {
        WorkOrder child = insertChildWorkOrder();
        EvaluationPhotosController.EvaluationPhotoRow saved = EvaluationPhotosController.capturePhoto(
            child.Id,
            EncodingUtil.base64Encode(Blob.valueOf('gw4378-rename-error')),
            null
        );
        Boolean missingFileThrew = false;
        Boolean blankTitleThrew = false;

        Test.startTest();
        try {
            EvaluationPhotosController.renamePhoto(null, 'Housing crack');
            System.assert(false, 'A missing photo should fail.');
        } catch (AuraHandledException expectedError) {
            missingFileThrew = true;
            System.assert(
                expectedError.getMessage().contains('File is required.'),
                expectedError.getMessage()
            );
        }
        try {
            EvaluationPhotosController.renamePhoto(saved.contentDocumentId, '   ');
            System.assert(false, 'A blank title should fail.');
        } catch (AuraHandledException expectedError) {
            blankTitleThrew = true;
            System.assert(
                expectedError.getMessage().contains('Photo title is required.'),
                expectedError.getMessage()
            );
        }
        Test.stopTest();

        System.assertEquals(true, missingFileThrew, 'A missing photo should fail.');
        System.assertEquals(true, blankTitleThrew, 'A blank title should fail.');
    }

    @IsTest
    static void deletePhoto_rejectsAPhotoThatIsNotOnTheWorkOrder() {
        WorkOrder child = insertChildWorkOrder();
        Boolean missingPhotoThrew = false;
        Boolean otherRecordThrew = false;

        Test.startTest();
        try {
            EvaluationPhotosController.deletePhoto(child.Id, child.Id, null);
            System.assert(false, 'A missing photo should fail.');
        } catch (AuraHandledException expectedError) {
            missingPhotoThrew = true;
            System.assert(
                expectedError.getMessage().contains('Photo is required.'),
                expectedError.getMessage()
            );
        }
        try {
            EvaluationPhotosController.deletePhoto(
                child.Id,
                fakeId(WorkOrder.SObjectType),
                fakeId(ContentDocument.SObjectType)
            );
            System.assert(false, 'A photo on another record should fail.');
        } catch (AuraHandledException expectedError) {
            otherRecordThrew = true;
            System.assert(
                expectedError.getMessage().contains('not attached to this Work Order'),
                expectedError.getMessage()
            );
        }
        Test.stopTest();

        System.assertEquals(true, missingPhotoThrew, 'A missing photo should fail.');
        System.assertEquals(true, otherRecordThrew, 'A photo on another record should fail.');
    }

    @IsTest
    static void insertQuote_attachesOptionalChildWorkOrderPhotos() {
        /********************************************
         * GIVEN
         ********************************************/
        allowQuoteTrigger();
        adb_Account accountBuilder = new adb_Account().name('GW4378 Insert Quote Account');
        WorkOrder parent = new WorkOrder(
            Subject = 'GW4378 Insert Parent',
            Status = 'New',
            Priority = 'Medium'
        );
        accountBuilder.persist();
        parent.AccountId = accountBuilder.Id;
        insert parent;
        WorkOrder child = new WorkOrder(
            Subject = 'GW4378 Insert Child',
            Status = 'New',
            Priority = 'Medium',
            AccountId = accountBuilder.Id,
            ParentWorkOrderId = parent.Id
        );
        insert child;
        EvaluationPhotosController.EvaluationPhotoRow saved = EvaluationPhotosController.capturePhoto(
            child.Id,
            EncodingUtil.base64Encode(Blob.valueOf('gw4378-insert-quote')),
            null
        );
        adb_Opportunity opportunityBuilder = new adb_Opportunity()
            .name('GW4378 Insert Quote Opp')
            .account(accountBuilder);
        useDiscoveryStage(opportunityBuilder);
        opportunityBuilder.persist();
        Quote quoteRecord = new Quote(
            Name = 'GW4378 Insert Quote',
            OpportunityId = opportunityBuilder.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            WorkOrder__c = parent.Id,
            QuoteType__c = 'Trial Quote'
        );

        /********************************************
         * WHEN
         ********************************************/
        Test.startTest();
        TriggerHandler.bypass('QuoteTriggerHandler');
        try {
            insert quoteRecord;
        } finally {
            TriggerHandler.clearBypass('QuoteTriggerHandler');
        }
        Test.stopTest();

        /********************************************
         * THEN
         ********************************************/
        System.assertEquals(
            1,
            ContentDocumentLinksService.getLinksByDocumentsAndLinkedEntities(
                new Set<Id>{ saved.contentDocumentId },
                new Set<Id>{ quoteRecord.Id }
            ).size(),
            'Creating a Quote attaches optional photos from the child Work Order.'
        );
    }

    @IsTest
    static void attachOptionalPhotosToQuotes_skipsQuotesThatCannotReceivePhotos() {
        Quote quoteWithoutWorkOrder = new Quote(Name = 'GW4378 Missing Work Order');
        Quote unsavedQuote = new Quote(WorkOrder__c = fakeId(WorkOrder.SObjectType));
        Quote quoteWithoutPhotos = new Quote(
            Id = fakeId(Quote.SObjectType),
            WorkOrder__c = fakeId(WorkOrder.SObjectType)
        );

        Test.startTest();
        EvaluationPhotosService.attachOptionalPhotosToQuotes(null);
        EvaluationPhotosService.attachOptionalPhotosToQuotes(new List<Quote>());
        EvaluationPhotosService.attachOptionalPhotosToQuotes(
            new List<Quote>{ null, quoteWithoutWorkOrder, unsavedQuote }
        );
        EvaluationPhotosService.attachOptionalPhotosToQuotes(new List<Quote>{ quoteWithoutPhotos });
        Test.stopTest();

        System.assertEquals(
            null,
            quoteWithoutWorkOrder.WorkOrder__c,
            'A quote without a Work Order is skipped.'
        );
        System.assertEquals(null, unsavedQuote.Id, 'A quote that has not been saved is skipped.');
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :quoteWithoutPhotos.Id
            ],
            'A Work Order with no optional photo does not add a Quote file.'
        );
    }

    private static void useDiscoveryStage(adb_Opportunity opportunityBuilder) {
        // Open, the first active stage, does not allow Pipeline. New Service opportunities
        // must be Discovery, which accepts the forecast value the builder already set.
        // Won is valid only for Closed Won.
        opportunityBuilder.record.put(Opportunity.StageName, 'Discovery');
        opportunityBuilder.record.put(Opportunity.Amount, 100);
        opportunityBuilder.record.put(Opportunity.CloseDate, Date.today().addDays(30));
        opportunityBuilder.record.put(Opportunity.BypassValidations__c, true);
    }

    private static void allowQuoteTrigger() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<Automation_Setting_Trigger__c> existing = [
                SELECT Id
                FROM Automation_Setting_Trigger__c
                WHERE SetupOwnerId = :UserInfo.getUserId()
                LIMIT 1
            ];
            Automation_Setting_Trigger__c settings = existing.isEmpty()
                ? new Automation_Setting_Trigger__c(SetupOwnerId = UserInfo.getUserId())
                : existing[0];
            settings.QuoteTriggerByPass__c = false;
            settings.disableAll__c = false;
            upsert settings;
        }
    }

    private static Id fakeId(Schema.SObjectType objectType) {
        return (Id) (objectType.getDescribe().getKeyPrefix() + '0'.repeat(12));
    }

    private static WorkOrder insertChildWorkOrder() {
        adb_Account accountBuilder = new adb_Account().name('GW4378 Photos Account');
        accountBuilder.persist();
        WorkOrder child = new WorkOrder(
            Subject = 'GW4378 Child',
            Status = 'New',
            Priority = 'Medium',
            AccountId = accountBuilder.Id
        );
        insert child;
        return child;
    }
}