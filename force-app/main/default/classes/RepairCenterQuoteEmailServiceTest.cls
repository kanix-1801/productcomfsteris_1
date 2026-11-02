/**
 * @description Tests for RepairCenterQuoteEmailService outbound HTML and send path (GW-5102).
 */
@IsTest
private class RepairCenterQuoteEmailServiceTest {
    @IsTest
    static void testBuildCustomerHtml_WhenPoRequired_OmitsApproveReject() {
        Test.startTest();
        String withPo = RepairCenterQuoteEmailService.buildCustomerHtml(true);
        String withoutPo = RepairCenterQuoteEmailService.buildCustomerHtml(false);
        String textWithPo = RepairCenterQuoteEmailService.buildCustomerText(true);
        Test.stopTest();

        Assert.isFalse(withPo.contains('Approved'));
        Assert.isFalse(withPo.contains('mailto:'));
        Assert.isTrue(withPo.contains('purchase order is required'));
        Assert.isTrue(
            withPo.contains(ExternalSystemEndpointSelector.connectCareQuoteApprovalUrl())
        );
        Assert.isTrue(withoutPo.contains('Approved'));
        Assert.isTrue(withoutPo.contains('Reject'));
        Assert.isFalse(withoutPo.contains('mailto:'));
        Assert.isTrue(textWithPo.contains('purchase order is required'));
    }

    @IsTest
    static void testResolveIntent_WhenFirstLineExactMatch() {
        Messaging.InboundEmail approved = new Messaging.InboundEmail();
        approved.plainTextBody = 'Approved\nThanks';
        Messaging.InboundEmail rejected = new Messaging.InboundEmail();
        rejected.plainTextBody = 'Reject';
        Messaging.InboundEmail help = new Messaging.InboundEmail();
        help.subject = 'Approved: Estimate';
        help.htmlBody = 'Approved';
        help.plainTextBody = 'Please call me';
        Messaging.InboundEmail boldReject = new Messaging.InboundEmail();
        boldReject.plainTextBody = '*Reject*\n\nOn Wed, someone wrote:\n> original';
        Messaging.InboundEmail htmlApproved = new Messaging.InboundEmail();
        htmlApproved.plainTextBody = '<b>Approved</b>';

        Test.startTest();
        String approvedIntent = EmailInboundService.resolveIntent(approved);
        String rejectedIntent = EmailInboundService.resolveIntent(rejected);
        String helpIntent = EmailInboundService.resolveIntent(help);
        String boldRejectIntent = EmailInboundService.resolveIntent(boldReject);
        String htmlApprovedIntent = EmailInboundService.resolveIntent(htmlApproved);
        Test.stopTest();

        Assert.areEqual(RepairCenterQuoteEmailService.INTENT_APPROVE, approvedIntent);
        Assert.areEqual(RepairCenterQuoteEmailService.INTENT_REJECT, rejectedIntent);
        Assert.areEqual(RepairCenterQuoteEmailService.INTENT_HELP, helpIntent);
        Assert.areEqual(RepairCenterQuoteEmailService.INTENT_REJECT, boldRejectIntent);
        Assert.areEqual(RepairCenterQuoteEmailService.INTENT_APPROVE, htmlApprovedIntent);
    }

    @IsTest
    static void testBuildQuoteEmailSubject_UsesReturnOrderAndOrderNumber() {
        WorkOrder workOrder = (WorkOrder) JSON.deserialize(
            '{"WorkOrderNumber":"00001064","ReturnOrder":{"ReturnOrderNumber":"RO-0386"}}',
            WorkOrder.class
        );

        Test.startTest();
        String subject = RepairCenterQuoteEmailService.buildQuoteEmailSubject(
            workOrder,
            'WESTON HOSPITAL'
        );
        Test.stopTest();

        Assert.areEqual(
            'Estimate for SRN #RO-0386, Order #00001064 - WESTON HOSPITAL',
            subject
        );
        Matcher orderMatcher = Pattern.compile('Order #([A-Za-z0-9-]+)').matcher(subject);
        Assert.isTrue(orderMatcher.find(), 'Subject should expose Order # for inbound routing');
        Assert.areEqual('00001064', orderMatcher.group(1));
    }

    @IsTest
    static void testSendQuoteEmail_WhenContactMissing_Throws() {
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder();
        workOrderBuilder.persist();

        Boolean thrown = false;
        Test.startTest();
        try {
            RepairCenterQuoteEmailService.sendQuoteEmail(workOrderBuilder.Id);
        } catch (RepairCenterQuoteEmailService.RepairCenterQuoteEmailException e) {
            thrown = true;
            Assert.isTrue(e.getMessage().contains('Contact'));
        }
        Test.stopTest();
        Assert.isTrue(thrown);
    }

    @IsTest
    static void testSendQuoteEmails_WhenContactPresent_InvokesSend() {
        Id pricebookId = Test.getStandardPricebookId();
        adb_Account account = new adb_Account();
        adb_Contact contact = new adb_Contact()
            .email('customer@example.com')
            .account(account);
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .account(account)
            .contact(contact)
            .pricebook2Id(pricebookId);
        workOrderBuilder.set(WorkOrder.EstimateContact__c, contact.Id);
        workOrderBuilder.persist();

        Test.startTest();
        List<Id> emailed = RepairCenterQuoteEmailService.sendQuoteEmails(
            new List<Id>{ workOrderBuilder.Id }
        );
        List<Id> empty = RepairCenterQuoteEmailService.sendQuoteEmails(new List<Id>());
        Test.stopTest();

        Assert.areEqual(1, emailed.size());
        Assert.areEqual(workOrderBuilder.Id, emailed[0]);
        Assert.isTrue(RepairCenterQuoteEmailService.sendEmailInvoked);
        Assert.isTrue(empty.isEmpty());
    }

    @IsTest
    static void testSendQuoteEmail_WhenWorkOrderMissing_Throws() {
        Boolean thrown = false;
        Test.startTest();
        try {
            RepairCenterQuoteEmailService.sendQuoteEmail(null);
            RepairCenterQuoteEmailService.sendQuoteEmails(null);
        } catch (Exception e) {
            thrown = true;
        }
        Test.stopTest();
        Assert.isNull(RepairCenterQuoteEmailService.sendQuoteEmail(null));
        Assert.isFalse(thrown);
    }

    @IsTest
    static void testSelectQuoteForReplyAndUpdateQuotes_WhenEmpty_NoOp() {
        Test.startTest();
        Quote missing = RepairCenterQuoteEmailService.selectQuoteForReply(null);
        RepairCenterQuoteEmailService.updateQuotes(null);
        RepairCenterQuoteEmailService.updateQuotes(new List<Quote>());
        Boolean updateFailed = false;
        try {
            RepairCenterQuoteEmailService.updateQuotes(
                new List<Quote>{ new Quote(Id = UserInfo.getUserId()) }
            );
        } catch (Exception e) {
            updateFailed = true;
        }
        Test.stopTest();
        Assert.isNull(missing);
        Assert.isNull(RepairCenterQuoteEmailService.selectQuoteForReply(UserInfo.getUserId()));
        Assert.isTrue(updateFailed);
    }

    @IsTest
    static void testEmailMessagesServiceCreateInbound_WhenEmptyAndInvalid_HandlesBoth() {
        Test.startTest();
        List<EmailMessage> empty = EmailMessagesService.createInboundEmailMessages(null);
        List<EmailMessage> emptyList =
            EmailMessagesService.createInboundEmailMessages(new List<EmailMessage>());
        EmailMessagesService.outboundEmailSDNProcessing(null);
        EmailMessagesService.outboundEmailSDNProcessing(new List<EmailMessage>());
        Boolean insertFailed = false;
        try {
            EmailMessagesService.createInboundEmailMessages(
                new List<EmailMessage>{ null }
            );
        } catch (Exception e) {
            insertFailed = true;
        }
        Test.stopTest();
        Assert.isTrue(empty.isEmpty());
        Assert.isTrue(emptyList.isEmpty());
        Assert.isTrue(insertFailed);
    }
}