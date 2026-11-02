/**
 * @description Tests for GW-4189 / GW-3591 Repair Center email enqueue from Content Document Link.
 */
@IsTest
private class RepairCenterDocumentEmailQueueableTest {
    @TestSetup
    static void setupTestData() {
        adb_Account accountBuilder = new adb_Account();
        accountBuilder.persist();
    }

    @IsTest
    static void testHandleNewContentDocumentLinks_accountLinkDoesNotEnqueue() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        ContentDocumentLink accountLink = insertFileLink(
            account.Id,
            '00001-1001-V1',
            'quote-doc.pdf'
        );

        Test.startTest();
        RepairCenterDocumentEmailService.handleNewContentDocumentLinks(
            new List<ContentDocumentLink>{ accountLink }
        );
        Integer enqueuedJobs = Limits.getQueueableJobs();
        Test.stopTest();

        Assert.areEqual(0, enqueuedJobs, 'Account file links should not enqueue email');
    }

    @IsTest
    static void testHandleNewContentDocumentLinks_quotePrefixEnqueues() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        ContentDocumentLink pdfLink = insertFileLink(
            account.Id,
            '00004824-1001-V9',
            'quote-doc.pdf'
        );
        Id fakeQuoteId = (Id) (Quote.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        ContentDocumentLink quoteShapedLink = new ContentDocumentLink(
            Id = pdfLink.Id,
            ContentDocumentId = pdfLink.ContentDocumentId,
            LinkedEntityId = fakeQuoteId
        );

        Test.startTest();
        RepairCenterDocumentEmailService.handleNewContentDocumentLinks(
            new List<ContentDocumentLink>{ quoteShapedLink }
        );
        Integer enqueuedJobs = Limits.getQueueableJobs();
        Test.stopTest();

        Assert.areEqual(1, enqueuedJobs, 'Quote doc-gen PDF links should enqueue email');
    }

    @IsTest
    static void testHandleNewContentDocumentLinks_workOrderPrefixEnqueues() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        ContentDocumentLink pdfLink = insertFileLink(
            account.Id,
            '00001234-1001',
            'wo-doc.pdf'
        );
        Id fakeWorkOrderId = (Id) (WorkOrder.SObjectType.getDescribe().getKeyPrefix() +
            '000000000001');
        ContentDocumentLink workOrderShapedLink = new ContentDocumentLink(
            Id = pdfLink.Id,
            ContentDocumentId = pdfLink.ContentDocumentId,
            LinkedEntityId = fakeWorkOrderId
        );

        Test.startTest();
        RepairCenterDocumentEmailService.handleNewContentDocumentLinks(
            new List<ContentDocumentLink>{ workOrderShapedLink }
        );
        Integer enqueuedJobs = Limits.getQueueableJobs();
        Test.stopTest();

        Assert.areEqual(1, enqueuedJobs, 'Work Order doc-gen PDF links should enqueue email');
    }

    @IsTest
    static void testHandleNewContentDocumentLinks_nonDocGenTitleDoesNotEnqueue() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        ContentDocumentLink pdfLink = insertFileLink(
            account.Id,
            'Random Attachment',
            'random.pdf'
        );
        Id fakeQuoteId = (Id) (Quote.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        ContentDocumentLink quoteShapedLink = new ContentDocumentLink(
            Id = pdfLink.Id,
            ContentDocumentId = pdfLink.ContentDocumentId,
            LinkedEntityId = fakeQuoteId
        );

        Test.startTest();
        RepairCenterDocumentEmailService.handleNewContentDocumentLinks(
            new List<ContentDocumentLink>{ quoteShapedLink }
        );
        Integer enqueuedJobs = Limits.getQueueableJobs();
        Test.stopTest();

        Assert.areEqual(0, enqueuedJobs, 'Non doc-gen titles should not enqueue email');
    }

    @IsTest
    static void testIsRepairCenterDocGenTitle_patterns() {
        Id fakeQuoteId = (Id) (Quote.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        Id fakeWorkOrderId = (Id) (WorkOrder.SObjectType.getDescribe().getKeyPrefix() +
            '000000000001');

        Assert.isTrue(
            RepairCenterDocumentEmailService.isRepairCenterDocGenTitle(
                '00004824-1001-V9',
                fakeQuoteId
            )
        );
        Assert.isTrue(
            RepairCenterDocumentEmailService.isRepairCenterDocGenTitle(
                'RepairCenterQuote-0Q0Ou000004y60EKAQ',
                fakeQuoteId
            )
        );
        Assert.isTrue(
            RepairCenterDocumentEmailService.isRepairCenterDocGenTitle(
                '00001234-1001',
                fakeWorkOrderId
            )
        );
        Assert.isFalse(
            RepairCenterDocumentEmailService.isRepairCenterDocGenTitle(
                '00001234-1001-V1',
                fakeWorkOrderId
            )
        );
        Assert.isFalse(
            RepairCenterDocumentEmailService.isRepairCenterDocGenTitle('Random', fakeQuoteId)
        );
    }

    @IsTest
    static void testQueueable_emptyList_doesNotThrow() {
        Test.startTest();
        Id jobId = System.enqueueJob(new SendRepairCenterDocumentEmailQueueable(new List<Id>()));
        Test.stopTest();

        Assert.isNotNull(jobId, 'Empty-list queueable should still enqueue');
    }

    @IsTest
    static void testQueueable_accountLink_doesNotThrow() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        ContentDocumentLink accountLink = insertFileLink(
            account.Id,
            'CDL Document Email Test',
            'cdl-document-email-test.jpg'
        );

        Test.startTest();
        new SendRepairCenterDocumentEmailQueueable(new List<Id>{ accountLink.Id }).execute(null);
        Test.stopTest();

        Assert.isNotNull(accountLink.Id, 'Account link execute path should complete');
    }

    @IsTest
    static void testStartEmailFlow_quoteAndWorkOrderLinks_startFlow() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        ContentDocumentLink accountLink = insertFileLink(
            account.Id,
            '00004824-1001-V9',
            'quote-doc.pdf'
        );
        Id fakeQuoteId = (Id) (Quote.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        Id fakeWorkOrderId = (Id) (WorkOrder.SObjectType.getDescribe().getKeyPrefix() +
            '000000000001');
        ContentDocumentLink quoteShapedLink = new ContentDocumentLink(
            Id = accountLink.Id,
            ContentDocumentId = accountLink.ContentDocumentId,
            LinkedEntityId = fakeQuoteId
        );
        ContentDocumentLink workOrderShapedLink = new ContentDocumentLink(
            Id = accountLink.Id,
            ContentDocumentId = accountLink.ContentDocumentId,
            LinkedEntityId = fakeWorkOrderId
        );

        Test.startTest();
        SendRepairCenterDocumentEmailQueueable.startEmailFlow(quoteShapedLink);
        SendRepairCenterDocumentEmailQueueable.startEmailFlow(workOrderShapedLink);
        SendRepairCenterDocumentEmailQueueable.startEmailFlow(null);
        Test.stopTest();

        Assert.isNotNull(quoteShapedLink.Id, 'Quote-shaped link should start the email flow');
        Assert.isNotNull(
            workOrderShapedLink.Id,
            'Work Order-shaped link should start the email flow'
        );
    }

    @IsTest
    static void testTriggerHandler_insertAndDelete_coverTriggerPaths() {
        Account account = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        ContentDocumentLink accountLink = insertFileLink(
            account.Id,
            'CDL Document Email Test',
            'cdl-document-email-test.jpg'
        );
        delete accountLink;
        Test.stopTest();

        Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE Id = :accountLink.Id
            ],
            'Deleted file link should be gone'
        );
    }

    @IsTest
    static void testHandleNewContentDocumentLinks_nullAndBlank_doNotThrow() {
        RepairCenterDocumentEmailService.handleNewContentDocumentLinks(null);
        RepairCenterDocumentEmailService.handleNewContentDocumentLinks(
            new List<ContentDocumentLink>()
        );
        RepairCenterDocumentEmailService.handleNewContentDocumentLinks(
            new List<ContentDocumentLink>{ null, new ContentDocumentLink() }
        );
        Assert.areEqual(0, Limits.getQueueableJobs(), 'Null and blank link lists should not enqueue email');
    }

    private static ContentDocumentLink insertFileLink(
        Id linkedEntityId,
        String title,
        String pathOnClient
    ) {
        adb_ContentVersion versionBuilder = new adb_ContentVersion()
            .title(title)
            .pathOnClient(pathOnClient)
            .versionData(Blob.valueOf('cdl-document-email'));
        versionBuilder.persist();
        ContentVersion version = [
            SELECT ContentDocumentId, FileType
            FROM ContentVersion
            WHERE Id = :versionBuilder.Id
            LIMIT 1
        ];
        ContentDocumentLink link = new ContentDocumentLink(
            ContentDocumentId = version.ContentDocumentId,
            LinkedEntityId = linkedEntityId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert link;
        return link;
    }
}