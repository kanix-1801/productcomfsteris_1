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
        opportunityBuilder.persist();
        Quote quoteRecord = new Quote(
            Name = 'GW4378 Quote',
            OpportunityId = opportunityBuilder.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            WorkOrder__c = parent.Id
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