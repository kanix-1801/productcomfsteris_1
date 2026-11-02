/**
 * @description Tests for GW-5102 inbound email handling and Repair Center quote replies.
 */
@IsTest
private class EmailInboundHandlerTest {
    private static final String OUTBOUND_MESSAGE_ID = '<gw5102-outbound@example.com>';

    @TestSetup
    static void setupTestData() {
        QuoteContext context = createQuoteContext('Evaluate & Quote', false);
        update new WorkOrder(Id = context.workOrder.Id, ActiveQuote__c = context.quote.Id);
        insertOutboundMessage(context.workOrder.Id, OUTBOUND_MESSAGE_ID);
    }

    @IsTest
    static void testHandleInboundEmail_WhenThreadMissing_SucceedsWithoutUpdates() {
        WorkOrder workOrder = queryWorkOrder();
        Messaging.InboundEmail email = newReply('Approved', '<missing-thread@example.com>');

        Test.startTest();
        Messaging.InboundEmailResult result =
            new EmailInboundHandler().handleInboundEmail(email, newEnvelope());
        Test.stopTest();

        Assert.isTrue(result.success);
        Quote quote = [SELECT Status FROM Quote WHERE Id = :workOrder.ActiveQuote__c];
        Assert.areNotEqual('Approved', quote.Status);
    }

    @IsTest
    static void testHandleInboundEmail_WhenMailtoSubjectHasOrderNumber_Approves() {
        WorkOrder workOrder = queryWorkOrder();
        Messaging.InboundEmail email = newMailtoReply(
            workOrder.WorkOrderNumber,
            'Approved',
            'Approved'
        );

        Test.startTest();
        Messaging.InboundEmailResult result =
            new EmailInboundHandler().handleInboundEmail(email, newEnvelope());
        Test.stopTest();

        Assert.isTrue(result.success);
        Quote quote = [SELECT Status FROM Quote WHERE Id = :workOrder.ActiveQuote__c];
        Assert.areEqual('Approved', quote.Status);
        WorkOrder updatedWorkOrder = [
            SELECT Status, SubStatus__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];
        Assert.areEqual('Evaluate & Quote', updatedWorkOrder.Status);
        Assert.isNull(updatedWorkOrder.SubStatus__c);
    }

    @IsTest
    static void testHandleInboundEmail_WhenMailtoSubjectHasOrderNumber_Rejects() {
        WorkOrder workOrder = queryWorkOrder();
        Messaging.InboundEmail email = newMailtoReply(
            workOrder.WorkOrderNumber,
            'Rejected',
            'Rejected'
        );

        Test.startTest();
        Messaging.InboundEmailResult result =
            new EmailInboundHandler().handleInboundEmail(email, newEnvelope());
        Test.stopTest();

        Assert.isTrue(result.success);
        Quote quote = [SELECT Status FROM Quote WHERE Id = :workOrder.ActiveQuote__c];
        Assert.areEqual('Rejected', quote.Status);
        WorkOrder updatedWorkOrder = [
            SELECT Status, SubStatus__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];
        Assert.areEqual('Evaluate & Quote', updatedWorkOrder.Status);
        Assert.isNull(updatedWorkOrder.SubStatus__c);
    }

    @IsTest
    static void testExtractWorkOrderNumberFromSubject_WhenOrderHashPresent() {
        String subject =
            'Approved: Re-Estimate for SRN #RO-0619, Order #00001616 - CLEVELAND CLINIC MERCY HOSPITAL';

        Test.startTest();
        String workOrderNumber = EmailInboundService.extractWorkOrderNumberFromSubject(subject);
        Test.stopTest();

        Assert.areEqual('00001616', workOrderNumber);
        Assert.isNull(EmailInboundService.extractWorkOrderNumberFromSubject('Re: Estimate'));
        Assert.isNull(EmailInboundService.extractWorkOrderNumberFromSubject(null));
    }

    @IsTest
    static void testHandleInboundEmail_WhenApproved_UpdatesQuoteAndWorkOrder() {
        WorkOrder workOrder = queryWorkOrder();
        QuoteLineItem lineItem = queryLineItem(workOrder.ActiveQuote__c);

        Messaging.InboundEmail email = newReply('Approved', OUTBOUND_MESSAGE_ID);
        email.binaryAttachments = new List<Messaging.InboundEmail.BinaryAttachment>{
            newAttachment('po.pdf', Blob.valueOf('pdf-bytes'))
        };

        Test.startTest();
        Messaging.InboundEmailResult result =
            new EmailInboundHandler().handleInboundEmail(email, newEnvelope());
        Test.stopTest();

        Assert.isTrue(result.success);
        Quote quote = [
            SELECT Status
            FROM Quote
            WHERE Id = :workOrder.ActiveQuote__c
        ];
        Assert.areEqual('Approved', quote.Status);
        QuoteLineItem updatedLine = [
            SELECT Status__c
            FROM QuoteLineItem
            WHERE Id = :lineItem.Id
        ];
        Assert.areEqual('Approved', updatedLine.Status__c);
        WorkOrder updatedWorkOrder = [
            SELECT Status, SubStatus__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];
        Assert.areEqual('Evaluate & Quote', updatedWorkOrder.Status);
        Assert.isNull(updatedWorkOrder.SubStatus__c);
        List<EmailMessage> inboundMessages = [
            SELECT Status, Incoming
            FROM EmailMessage
            WHERE RelatedToId = :workOrder.Id
                AND Incoming = TRUE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        Assert.areEqual(1, inboundMessages.size());
        Assert.areEqual('1', inboundMessages[0].Status);
    }

    @IsTest
    static void testHandleInboundEmail_WhenIDoNotApprove_IsHelp() {
        WorkOrder workOrder = queryWorkOrder();
        Messaging.InboundEmail email = newReply('I do not approve', OUTBOUND_MESSAGE_ID);

        Test.startTest();
        new EmailInboundHandler().handleInboundEmail(email, newEnvelope());
        Test.stopTest();

        Quote quote = [SELECT Status FROM Quote WHERE Id = :workOrder.ActiveQuote__c];
        Assert.areNotEqual('Approved', quote.Status);
        WorkOrder updatedWorkOrder = [
            SELECT Status, SubStatus__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];
        Assert.areEqual('Evaluate & Quote', updatedWorkOrder.Status);
        Assert.areEqual('Customer Care', updatedWorkOrder.SubStatus__c);
    }

    @IsTest
    static void testHandleInboundEmail_WhenReject_UpdatesStatusesAndInspectionOverride() {
        WorkOrder workOrder = queryWorkOrder();
        QuoteLineItem lineItem = queryLineItem(workOrder.ActiveQuote__c);
        adb_Product2 inspectionProduct = new adb_Product2()
            .name('Inspection Fee')
            .productCode('INSP-001')
            .productType('Service Code');
        new adb_PricebookEntry().product(inspectionProduct).unitPrice(5).persist();
        Product2 inspection = [
            SELECT Id
            FROM Product2
            WHERE ProductCode = 'INSP-001'
            LIMIT 1
        ];

        RepairCenterQuoteEmailService.serviceCodeTypeByProductIdOverride = new Map<Id, String>();
        RepairCenterQuoteEmailService.inspectionServiceProductByQliProductIdOverride =
            new Map<Id, Id>{ resolveProductId(lineItem) => inspection.Id };

        Messaging.InboundEmail email = newReply('Rejected', OUTBOUND_MESSAGE_ID);

        Test.startTest();
        Messaging.InboundEmailResult result =
            new EmailInboundHandler().handleInboundEmail(email, newEnvelope());
        Test.stopTest();

        Assert.isTrue(result.success);
        Quote quote = [SELECT Status FROM Quote WHERE Id = :workOrder.ActiveQuote__c];
        Assert.areEqual('Rejected', quote.Status);
        QuoteLineItem updatedLine = [
            SELECT Status__c
            FROM QuoteLineItem
            WHERE Id = :lineItem.Id
        ];
        Assert.areEqual('Rejected', updatedLine.Status__c);
        WorkOrder updatedWorkOrder = [
            SELECT Status, SubStatus__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];
        Assert.areEqual('Evaluate & Quote', updatedWorkOrder.Status);
        Assert.isNull(updatedWorkOrder.SubStatus__c);
        List<WorkOrderLineItem> inspectionLines = [
            SELECT LineType__c, ProductCodeWoli__c, Status
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :workOrder.Id
                AND ProductCodeWoli__c = 'INSP-001'
        ];
        Assert.areEqual(1, inspectionLines.size());
        Assert.areEqual('Service Code', inspectionLines[0].LineType__c);
        Assert.areEqual('Approved', inspectionLines[0].Status);
    }

    @IsTest
    static void testHandleInboundEmail_WhenReject_AndInspectionServiceCodeBlank_SkipsFeeLine() {
        WorkOrder workOrder = queryWorkOrder();
        Messaging.InboundEmail email = newReply('Rejected', OUTBOUND_MESSAGE_ID);

        Test.startTest();
        Messaging.InboundEmailResult result =
            new EmailInboundHandler().handleInboundEmail(email, newEnvelope());
        Test.stopTest();

        Assert.isTrue(result.success);
        Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM WorkOrderLineItem
                WHERE WorkOrderId = :workOrder.Id
                    AND ProductCodeWoli__c = 'INSP-001'
            ]
        );
    }

    @IsTest
    static void testHandleInboundEmail_WhenHelp_SetsCustomerCareOnly() {
        WorkOrder workOrder = queryWorkOrder();
        Messaging.InboundEmail email = newReply('Please call me', OUTBOUND_MESSAGE_ID);

        Test.startTest();
        Messaging.InboundEmailResult result =
            new EmailInboundHandler().handleInboundEmail(email, newEnvelope());
        Test.stopTest();

        Assert.isTrue(result.success);
        WorkOrder updatedWorkOrder = [
            SELECT Status, SubStatus__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];
        Assert.areEqual('Evaluate & Quote', updatedWorkOrder.Status);
        Assert.areEqual('Customer Care', updatedWorkOrder.SubStatus__c);
    }

    @IsTest
    static void testHandleInboundEmail_WhenQuotedApprove_IsHelp() {
        WorkOrder workOrder = queryWorkOrder();
        Messaging.InboundEmail email = newReply('> Approved', OUTBOUND_MESSAGE_ID);

        Test.startTest();
        new EmailInboundHandler().handleInboundEmail(email, newEnvelope());
        Test.stopTest();

        Quote quote = [SELECT Status FROM Quote WHERE Id = :workOrder.ActiveQuote__c];
        Assert.areNotEqual('Approved', quote.Status);
        WorkOrder updatedWorkOrder = [
            SELECT SubStatus__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];
        Assert.areEqual('Customer Care', updatedWorkOrder.SubStatus__c);
    }

    @IsTest
    static void testHandleInboundEmail_WhenReferencesHeader_ResolvesWorkOrder() {
        WorkOrder workOrder = queryWorkOrder();
        Messaging.InboundEmail email = newEmail('Re: Estimate', 'Yes');
        Messaging.InboundEmail.Header referencesHeader = new Messaging.InboundEmail.Header();
        referencesHeader.name = 'References';
        referencesHeader.value = '<other@example.com> ' + OUTBOUND_MESSAGE_ID;
        email.headers = new List<Messaging.InboundEmail.Header>{ referencesHeader };

        Test.startTest();
        new EmailInboundHandler().handleInboundEmail(email, newEnvelope());
        Test.stopTest();

        Quote quote = [SELECT Status FROM Quote WHERE Id = :workOrder.ActiveQuote__c];
        Assert.areEqual('Approved', quote.Status);
    }

    @IsTest
    static void testHandleInboundEmail_WhenDisinfectionOverride_ApprovesThatLineOnReject() {
        WorkOrder workOrder = queryWorkOrder();
        QuoteLineItem lineItem = queryLineItem(workOrder.ActiveQuote__c);
        RepairCenterQuoteEmailService.serviceCodeTypeByProductIdOverride = new Map<Id, String>{
            resolveProductId(lineItem) => 'Disinfection'
        };

        Messaging.InboundEmail email = newReply('Reject', OUTBOUND_MESSAGE_ID);

        Test.startTest();
        new EmailInboundHandler().handleInboundEmail(email, newEnvelope());
        Test.stopTest();

        QuoteLineItem updatedLine = [
            SELECT Status__c
            FROM QuoteLineItem
            WHERE Id = :lineItem.Id
        ];
        Assert.areEqual('Approved', updatedLine.Status__c);
    }

    @IsTest
    static void testResolveIntent_WhenTokenInBothLists_RejectWins() {
        InboundEmailReplyConfigsSelector.configOverride = new InboundEmailReplyConfig__mdt(
            DeveloperName = 'RepairCenterQuote',
            ApproveKeywordList__c = 'Maybe, Yes',
            RejectKeywordList__c = 'Maybe, No'
        );
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.plainTextBody = 'Maybe';

        Test.startTest();
        String intent = EmailInboundService.resolveIntent(email);
        Test.stopTest();

        Assert.areEqual(RepairCenterQuoteEmailService.INTENT_REJECT, intent);
    }

    @IsTest
    static void testEmailInboundRoutesSelector_UsesOverride() {
        EmailInboundRoutesSelector.routeOverride = new EmailInboundRoute__mdt(
            DeveloperName = 'RepairCenterQuote',
            RecordKeyRegex__c = 'WO-([0-9]+)',
            SubjectContains__c = 'WO-',
            IsActive__c = true
        );

        Test.startTest();
        EmailInboundRoute__mdt route = EmailInboundRoutesSelector.selectRepairCenterQuote();
        String recordKey = EmailInboundService.extractWorkOrderNumberFromSubject(
            'Approve WO-5555 please'
        );
        Test.stopTest();

        Assert.areEqual('WO-([0-9]+)', route.RecordKeyRegex__c);
        Assert.areEqual('5555', recordKey);
    }

    @IsTest
    static void testInboundEmailReplyConfigsSelector_UsesOverride() {
        InboundEmailReplyConfigsSelector.configOverride = new InboundEmailReplyConfig__mdt(
            DeveloperName = 'RepairCenterQuote',
            ApproveKeywordList__c = 'OK',
            RejectKeywordList__c = 'Nope'
        );
        Test.startTest();
        InboundEmailReplyConfig__mdt config = InboundEmailReplyConfigsSelector.selectRepairCenterQuote();
        Test.stopTest();
        Assert.areEqual('OK', config.ApproveKeywordList__c);
    }

    private static WorkOrder queryWorkOrder() {
        return [
            SELECT Id, WorkOrderNumber, ActiveQuote__c, ParentWorkOrderId
            FROM WorkOrder
            WHERE ActiveQuote__c != NULL
            LIMIT 1
        ];
    }

    private static QuoteLineItem queryLineItem(Id quoteId) {
        return [
            SELECT Id, Product2Id, PricebookEntry.Product2Id, Status__c
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
            LIMIT 1
        ];
    }

    private static Id resolveProductId(QuoteLineItem lineItem) {
        return lineItem.Product2Id != null
            ? lineItem.Product2Id
            : lineItem.PricebookEntry.Product2Id;
    }

    private static void insertOutboundMessage(Id workOrderId, String messageId) {
        new adb_EmailMessage()
            .relatedTo(workOrderId)
            .messageIdentifier(messageId)
            .status('3')
            .setFromId(UserInfo.getUserId())
            .toAddress('customer@example.com')
            .subject('Estimate')
            .persist();
    }

    private static Messaging.InboundEmail newReply(String firstLine, String inReplyTo) {
        Messaging.InboundEmail email = newEmail('Re: Estimate', firstLine);
        email.inReplyTo = inReplyTo;
        return email;
    }

    private static Messaging.InboundEmail newMailtoReply(
        String workOrderNumber,
        String subjectAction,
        String firstLine
    ) {
        return newEmail(
            subjectAction +
                ': Re-Estimate for SRN #RO-0619, Order #' +
                workOrderNumber +
                ' - CLEVELAND CLINIC MERCY HOSPITAL',
            firstLine
        );
    }

    private static Messaging.InboundEmail newEmail(String subject, String body) {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.subject = subject;
        email.plainTextBody = body;
        email.fromAddress = 'customer@example.com';
        email.fromName = 'Customer';
        email.toAddresses = new List<String>{ 'quotes@example.com' };
        return email;
    }

    private static Messaging.InboundEnvelope newEnvelope() {
        Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
        envelope.fromAddress = 'customer@example.com';
        envelope.toAddress = 'quotes@example.com';
        return envelope;
    }

    private static Messaging.InboundEmail.BinaryAttachment newAttachment(String fileName, Blob body) {
        Messaging.InboundEmail.BinaryAttachment attachment =
            new Messaging.InboundEmail.BinaryAttachment();
        attachment.fileName = fileName;
        attachment.body = body;
        attachment.mimeTypeSubType = 'application/pdf';
        return attachment;
    }

    private class QuoteContext {
        WorkOrder workOrder;
        Quote quote;
    }

    private static QuoteContext createQuoteContext(String workOrderStatus, Boolean poRequired) {
        Id pricebookId = Test.getStandardPricebookId();
        adb_Account account = new adb_Account();
        adb_Contact contact = new adb_Contact()
            .email('customer@example.com')
            .account(account);
        contact.persist();
        adb_Product2 product = new adb_Product2()
            .name('Serviced Device')
            .productCode('SRV-001')
            .productType('Service Asset');
        new adb_PricebookEntry().product(product).unitPrice(25).persist();

        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .account(account)
            .contact(contact)
            .status(workOrderStatus)
            .pricebook2Id(pricebookId)
            .setRecordType('RepairCenterDevices');
        workOrderBuilder.set(WorkOrder.CustomerPORequired__c, poRequired);
        workOrderBuilder.set(WorkOrder.EstimateContact__c, contact.Id);
        workOrderBuilder.persist();

        Id serviceRtId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get('Service')
            .getRecordTypeId();
        Opportunity opportunity = new Opportunity(
            Name = 'GW-5102 Quote Opp',
            AccountId = account.Id,
            CloseDate = Date.today().addDays(30),
            StageName = 'Discovery',
            Pricebook2Id = pricebookId,
            RecordTypeId = serviceRtId
        );
        insert opportunity;

        Quote quote = new Quote(
            Name = 'Repair Estimate',
            OpportunityId = opportunity.Id,
            Pricebook2Id = pricebookId,
            Status = 'Waiting for Approval'
        );
        TriggerHandler.bypass('QuoteTriggerHandler');
        TriggerHandler.bypass('QuoteLineItemTriggerHandler');
        insert quote;

        PricebookEntry entry = [
            SELECT Id, Product2Id
            FROM PricebookEntry
            WHERE Product2Id = :product.Id
            LIMIT 1
        ];
        insert new QuoteLineItem(
            QuoteId = quote.Id,
            PricebookEntryId = entry.Id,
            Quantity = 1,
            UnitPrice = 25,
            LineType__c = 'Product Serviced',
            Status__c = 'Waiting for Approval'
        );
        TriggerHandler.clearBypass('QuoteTriggerHandler');
        TriggerHandler.clearBypass('QuoteLineItemTriggerHandler');

        QuoteContext context = new QuoteContext();
        context.workOrder = [
            SELECT Id, WorkOrderNumber, ActiveQuote__c
            FROM WorkOrder
            WHERE Id = :workOrderBuilder.Id
        ];
        context.quote = quote;
        return context;
    }
}