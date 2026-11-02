/**
 * @description Tests for RepairCenterQuoteEmailSendAction (GW-5102).
 */
@IsTest
private class RepairCenterQuoteEmailSendActionTest {
    private static final String SENDER_ADDRESS = 'gwftest_no-reply@steris.com';
    private static final Id TEMPLATE_ID = fakeId(EmailTemplate.SObjectType);
    private static final Id ORG_WIDE_EMAIL_ADDRESS_ID = fakeId(OrgWideEmailAddress.SObjectType);

    @IsTest
    static void testSend_WhenValid_SetsReplyToTemplateAndFrom() {
        QuoteEmailFixture fixture = createFixture();
        ContentVersion version = insertPdf();
        RepairCenterQuoteEmailSendAction.orgWideEmailAddressIdOverride =
            ORG_WIDE_EMAIL_ADDRESS_ID;

        RepairCenterQuoteEmailSendAction.Request request = newRequest(
            fixture.contact.Id,
            fixture.workOrder.Id
        );
        request.recipientAddresses = new List<String>{
            'extra@example.com',
            fixture.contact.Email,
            ' ',
            'extra@example.com'
        };
        request.attachmentIds = new List<String>{ version.Id, 'not-an-id', null };

        Test.startTest();
        RepairCenterQuoteEmailSendAction.send(
            new List<RepairCenterQuoteEmailSendAction.Request>{ request }
        );
        Test.stopTest();

        Assert.areEqual(1, RepairCenterQuoteEmailSendAction.lastMessages.size());
        Messaging.SingleEmailMessage mail = RepairCenterQuoteEmailSendAction.lastMessages[0];
        Assert.areEqual(
            ExternalSystemEndpointSelector.repairCenterQuoteInboundEmail(),
            mail.getReplyTo()
        );
        Assert.areEqual(ORG_WIDE_EMAIL_ADDRESS_ID, mail.getOrgWideEmailAddressId());
        Assert.areEqual(TEMPLATE_ID, mail.getTemplateId());
        Assert.areEqual(fixture.contact.Id, mail.getTargetObjectId());
        Assert.areEqual(fixture.workOrder.Id, mail.getWhatId());
        Assert.areEqual(
            new List<String>{ fixture.contact.Email, 'extra@example.com' },
            mail.getToAddresses()
        );
        Assert.areEqual(new List<String>{ version.Id }, mail.getEntityAttachments());
    }

    @IsTest
    static void testSend_WhenEmptyOrNull_DoesNotSend() {
        Test.startTest();
        RepairCenterQuoteEmailSendAction.send(null);
        RepairCenterQuoteEmailSendAction.send(
            new List<RepairCenterQuoteEmailSendAction.Request>()
        );
        Test.stopTest();

        Assert.isNull(RepairCenterQuoteEmailSendAction.lastMessages);
    }

    @IsTest
    static void testSend_WhenRecipientMissing_Throws() {
        RepairCenterQuoteEmailSendAction.orgWideEmailAddressIdOverride =
            ORG_WIDE_EMAIL_ADDRESS_ID;
        RepairCenterQuoteEmailSendAction.Request request =
            new RepairCenterQuoteEmailSendAction.Request();
        request.relatedRecordId = fakeId(WorkOrder.SObjectType);
        request.emailTemplateId = TEMPLATE_ID;

        Boolean thrown = false;
        Test.startTest();
        try {
            RepairCenterQuoteEmailSendAction.send(
                new List<RepairCenterQuoteEmailSendAction.Request>{ request }
            );
        } catch (RepairCenterQuoteEmailSendAction.RepairCenterQuoteEmailSendException e) {
            thrown = true;
            Assert.isTrue(e.getMessage().contains('recipient'));
        }
        Test.stopTest();

        Assert.isTrue(thrown);
    }

    @IsTest
    static void testSend_WhenContactHasNoEmail_Throws() {
        QuoteEmailFixture fixture = createFixture();
        update new Contact(Id = fixture.contact.Id, Email = null);
        RepairCenterQuoteEmailSendAction.orgWideEmailAddressIdOverride =
            ORG_WIDE_EMAIL_ADDRESS_ID;

        Boolean thrown = false;
        Test.startTest();
        try {
            RepairCenterQuoteEmailSendAction.send(
                new List<RepairCenterQuoteEmailSendAction.Request>{
                    newRequest(fixture.contact.Id, fixture.workOrder.Id)
                }
            );
        } catch (RepairCenterQuoteEmailSendAction.RepairCenterQuoteEmailSendException e) {
            thrown = true;
            Assert.isTrue(e.getMessage().contains('email address'));
        }
        Test.stopTest();

        Assert.isTrue(thrown);
    }

    @IsTest
    static void testSend_WhenOrgWideAddressMissing_Throws() {
        QuoteEmailFixture fixture = createFixture();
        RepairCenterQuoteEmailSendAction.Request request = newRequest(
            fixture.contact.Id,
            fixture.workOrder.Id
        );
        request.senderAddress = 'missing-owea@steris.com';

        Boolean thrown = false;
        Test.startTest();
        try {
            RepairCenterQuoteEmailSendAction.send(
                new List<RepairCenterQuoteEmailSendAction.Request>{ request }
            );
        } catch (RepairCenterQuoteEmailSendAction.RepairCenterQuoteEmailSendException e) {
            thrown = true;
            Assert.isTrue(e.getMessage().contains('org-wide email address'));
        }
        Test.stopTest();

        Assert.isTrue(thrown);
    }

    private static RepairCenterQuoteEmailSendAction.Request newRequest(
        Id contactId,
        Id workOrderId
    ) {
        RepairCenterQuoteEmailSendAction.Request request =
            new RepairCenterQuoteEmailSendAction.Request();
        request.recipientId = contactId;
        request.relatedRecordId = workOrderId;
        request.emailTemplateId = TEMPLATE_ID;
        request.senderAddress = SENDER_ADDRESS;
        request.logEmailOnSend = true;
        return request;
    }

    private static QuoteEmailFixture createFixture() {
        Id pricebookId = Test.getStandardPricebookId();
        adb_Account account = new adb_Account();
        adb_Contact contact = new adb_Contact()
            .email('customer@example.com')
            .account(account);
        adb_WorkOrder workOrder = new adb_WorkOrder()
            .account(account)
            .contact(contact)
            .pricebook2Id(pricebookId);
        workOrder.persist();

        QuoteEmailFixture fixture = new QuoteEmailFixture();
        fixture.contact = (Contact) contact.record;
        fixture.workOrder = (WorkOrder) workOrder.record;
        return fixture;
    }

    private static Id fakeId(Schema.SObjectType sobjectType) {
        return (Id) (sobjectType.getDescribe().getKeyPrefix() + '000000000001');
    }

    private static ContentVersion insertPdf() {
        ContentVersion version = new ContentVersion(
            Title = 'Quote',
            PathOnClient = 'Quote.pdf',
            VersionData = Blob.valueOf('quote-pdf'),
            IsMajorVersion = true
        );
        insert version;
        return [
            SELECT Id
            FROM ContentVersion
            WHERE Id = :version.Id
        ];
    }

    private class QuoteEmailFixture {
        public Contact contact;
        public WorkOrder workOrder;
    }
}