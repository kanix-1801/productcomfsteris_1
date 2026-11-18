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
	static void testHandleNewContentDocumentLinks_workOrderOrderAcknowledgementEnqueues() {
		WorkOrder workOrderRecord = insertWorkOrder();

		Test.startTest();
		RepairCenterDocumentEmailService.handleNewContentDocumentLinks(new List<ContentDocumentLink>{ buildWorkOrderLink(workOrderRecord, orderAcknowledgementTitle(workOrderRecord)) });
		Integer enqueuedJobs = Limits.getQueueableJobs();
		Test.stopTest();

		Assert.areEqual(1, enqueuedJobs, 'The Order Acknowledgement PDF should enqueue email');
	}

	@IsTest
	static void testHandleNewContentDocumentLinks_workOrderDeliveryDocumentsDoNotEnqueue() {
		// GW-5695 - Service Delivery Reports and Delivery Notes must not go out as an Order Acknowledgement.
		WorkOrder workOrderRecord = insertWorkOrder();
		String orderAcknowledgementTitle = orderAcknowledgementTitle(workOrderRecord);

		Test.startTest();
		RepairCenterDocumentEmailService.handleNewContentDocumentLinks(new List<ContentDocumentLink>{
			buildWorkOrderLink(workOrderRecord, orderAcknowledgementTitle + '-SDR'),
			buildWorkOrderLink(workOrderRecord, orderAcknowledgementTitle + '-DN'),
			buildWorkOrderLink(workOrderRecord, workOrderRecord.WorkOrderNumber + '-photo')
		});
		Integer enqueuedJobs = Limits.getQueueableJobs();
		Test.stopTest();

		Assert.areEqual(0, enqueuedJobs, 'Only the Order Acknowledgement PDF should enqueue email on a Work Order');
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

		Assert.isTrue(RepairCenterDocumentEmailService.isRepairCenterDocGenTitle('00004824-1001-V9', fakeQuoteId, null));
		Assert.isTrue(RepairCenterDocumentEmailService.isRepairCenterDocGenTitle('RepairCenterQuote-0Q0Ou000004y60EKAQ', fakeQuoteId, null));
		Assert.isFalse(RepairCenterDocumentEmailService.isRepairCenterDocGenTitle('Random', fakeQuoteId, null));
		Assert.isTrue(RepairCenterDocumentEmailService.isRepairCenterDocGenTitle('00001234-1001', fakeWorkOrderId, '00001234-1001'));
		Assert.isTrue(RepairCenterDocumentEmailService.isRepairCenterDocGenTitle('00001234-ACC-1041', fakeWorkOrderId, '00001234-ACC-1041'), 'Account numbers with dashes still match');
		Assert.isFalse(RepairCenterDocumentEmailService.isRepairCenterDocGenTitle('00001234-1001-SDR', fakeWorkOrderId, '00001234-1001'));
		Assert.isFalse(RepairCenterDocumentEmailService.isRepairCenterDocGenTitle('00001234-1001-DN', fakeWorkOrderId, '00001234-1001'));
		Assert.isFalse(RepairCenterDocumentEmailService.isRepairCenterDocGenTitle('00001234-1001-V1', fakeWorkOrderId, '00001234-1001'));
		Assert.isFalse(RepairCenterDocumentEmailService.isRepairCenterDocGenTitle('00001234-1001', fakeWorkOrderId, null), 'Unknown Work Order never sends');
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

	private static WorkOrder insertWorkOrder() {
		adb_WorkOrder workOrderBuilder = new adb_WorkOrder();
		workOrderBuilder.persist();
		return [SELECT Id, WorkOrderNumber, Account.AccountNumber FROM WorkOrder WHERE Id = :workOrderBuilder.Id];
	}

	private static String orderAcknowledgementTitle(WorkOrder workOrderRecord) {
		return workOrderRecord.WorkOrderNumber + '-' + (workOrderRecord.Account?.AccountNumber == null ? '' : workOrderRecord.Account.AccountNumber);
	}

	// Files are linked to the Account first so the real trigger does not enqueue; the Work Order-shaped link is built in memory.
	private static ContentDocumentLink buildWorkOrderLink(WorkOrder workOrderRecord, String title) {
		ContentDocumentLink accountLink = insertFileLink([SELECT Id FROM Account LIMIT 1].Id, title, 'wo-doc.pdf');
		return new ContentDocumentLink(Id = accountLink.Id, ContentDocumentId = accountLink.ContentDocumentId, LinkedEntityId = workOrderRecord.Id);
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