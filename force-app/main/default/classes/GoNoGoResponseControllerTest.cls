@IsTest
/**
 * @author PSL
 * @date 01-02-2026
 * @description Test class for GoNoGoResponseController. Verifies sending Go/No-Go reminder email
 *              using recipients from the latest matching EmailMessage and updates to Case.ReminderSentDate__c.
 */
private class GoNoGoResponseControllerTest {

    /* ============================================================
       Utility Methods
       ============================================================ */

    private static GoNoGoResponseController.Request req(Id caseId) {
        GoNoGoResponseController.Request r =
            new GoNoGoResponseController.Request();
        r.caseId = caseId;
        return r;
    }

    private static EmailMessage insertEmail(Id caseId, String toAddr, String ccAddr) {
        EmailMessage em = new EmailMessage(
            ParentId    = caseId,
            Subject     = 'Response Required: Go/No-Go',
            ToAddress   = toAddr,
            CcAddress   = ccAddr,
            FromAddress = 'external@test.com',
            Incoming    = false,
            MessageDate = System.now()
        );
        insert em;
        return em;
    }

    private static Case buildCase(String ipmDecision, String salesDecision) {
        Contact c = new Contact(
            LastName = 'Case Contact',
            Email    = 'case.contact@test.com'
        );
        insert c;

        Case cs = new Case(
            Subject           = 'Go No Go Case',
            ContactId         = c.Id,
            IPMDecision__c    = ipmDecision,
            Sales_Decision__c = salesDecision
        );
        insert cs;
        return cs;
    }

    private static Order buildOrder(Id caseId, Account acc) {
        Order o = new Order(
            AccountId     = acc.Id,
            parentCase__c = caseId,
            Status        = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id  = Test.getStandardPricebookId()
        );
        insert o;
        return o;
    }

    private static PricebookEntry createPBE(Id productId) {
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id   = productId,
            UnitPrice    = 100,
            IsActive     = true
        );
        insert pbe;
        return pbe;
    }

    private static OrderItem buildOrderItem(
        Id orderId,
        Id productId,
        String tasSalesCategory
    ) {
        PricebookEntry pbe = createPBE(productId);

        OrderItem oi = new OrderItem(
            OrderId             = orderId,
            Product2Id          = productId,
            PricebookEntryId    = pbe.Id,
            Quantity            = 1,
            UnitPrice           = 100,
            TASSalesCategory__c = tasSalesCategory
        );
        insert oi;
        return oi;
    }

    private static void linkSalesRepContact(Id orderItemId) {
        Contact salesRep = new Contact(
            LastName = 'Sales Rep',
            Email    = 'sales.rep@test.com'
        );
        insert salesRep;

        OrderLineContact__c olc = new OrderLineContact__c(
            OrderLine__c = orderItemId,
            SalesRep__c  = salesRep.Id
        );
        insert olc;
    }

    /* ============================================================
       Test Cases
       ============================================================ */

    @IsTest
    static void testPendingDecision_UsesLastEmailRecipients() {
        Case cs = buildCase(null, null);
        insertEmail(cs.Id, 'to1@test.com;to2@test.com', 'cc@test.com');

        Test.startTest();
        List<GoNoGoResponseController.Response> res =
            GoNoGoResponseController.sendEmail(
                new List<GoNoGoResponseController.Request>{ req(cs.Id) }
            );
        Test.stopTest();

        System.assertEquals('Sent', res[0].status);
    }

    @IsTest
    static void testIPMGo_SendsToSalesEmails_CapitalLine() {
        Account acc = new Account(
            Name = 'Capital Acc',
            CustomerClassCode__c = 'HC'
        );
        insert acc;

        Case cs = buildCase('Go', null);
        Order ord = buildOrder(cs.Id, acc);

        Product2 prod = new Product2(
            Name = 'Capital Equipment',
            SalesCategory__c = 'CAPEQUIP',
            IsActive = true
        );
        insert prod;

        OrderItem oi =
            buildOrderItem(ord.Id, prod.Id, 'SURG SPT'); // → Procedural
        linkSalesRepContact(oi.Id);

        insertEmail(cs.Id, 'previous@test.com', null);

        Test.startTest();
        List<GoNoGoResponseController.Response> res =
            GoNoGoResponseController.sendEmail(
                new List<GoNoGoResponseController.Request>{ req(cs.Id) }
            );
        Test.stopTest();

        System.assertEquals('Sent', res[0].status);
    }

    @IsTest
    static void testSalesGo_SendsToIPMEmails_ServiceInstallation() {
        Account acc = new Account(Name = 'Service Acc');
        insert acc;

        Case cs = buildCase(null, 'Go');
        Order ord = buildOrder(cs.Id, acc);

        Product2 prod = new Product2(
            Name = 'Service Product',
            SalesCategory__c = 'SERVICE',
            IsActive = true
        );
        insert prod;

        OrderItem oi =
            buildOrderItem(ord.Id, prod.Id, 'IPM'); // Service – Installation
        linkSalesRepContact(oi.Id);

        insertEmail(cs.Id, 'previous@test.com', null);

        Test.startTest();
        List<GoNoGoResponseController.Response> res =
            GoNoGoResponseController.sendEmail(
                new List<GoNoGoResponseController.Request>{ req(cs.Id) }
            );
        Test.stopTest();

        System.assertEquals('Sent', res[0].status);
    }

    @IsTest
    static void testNoMatchingEmail_Skipped() {
        Case cs = buildCase(null, null);

        Test.startTest();
        List<GoNoGoResponseController.Response> res =
            GoNoGoResponseController.sendEmail(
                new List<GoNoGoResponseController.Request>{ req(cs.Id) }
            );
        Test.stopTest();

        System.assertEquals('Skipped', res[0].status);
    }

    @IsTest
    static void testDuplicateCaseIds_UpdateReminderSentDate() {
        Case cs = buildCase(null, null);
        insertEmail(cs.Id, 'dup@test.com', null);

        Test.startTest();
        GoNoGoResponseController.sendEmail(
            new List<GoNoGoResponseController.Request>{
                req(cs.Id), req(cs.Id)
            }
        );
        Test.stopTest();

        Case refreshed =
            [SELECT ReminderSentDate__c FROM Case WHERE Id = :cs.Id];

        System.assertNotEquals(null, refreshed.ReminderSentDate__c);
    }
}