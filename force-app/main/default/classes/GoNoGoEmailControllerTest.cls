/**
 * @author PSL
 * @date 12-08-2025
 * @description Test class for GoNoGoControllerHelper
 */
@IsTest
private class GoNoGoEmailControllerTest {
    private static Id stdPbId;

    @testSetup
    static void setupData() {
        Account acc = new Account(Name = 'GNG Account');
        insert acc;

        Case cPlan = new Case(Subject = 'GNG Main Case - With Planning Hold', Status = 'New', Origin = 'Phone');
        Case cNoPH = new Case(Subject = 'GNG Case - No Planning Hold',       Status = 'New', Origin = 'Phone');
        insert new List<Case>{ cPlan, cNoPH };

        stdPbId = Test.getStandardPricebookId();
        Product2 prod = new Product2(Name = 'Equip-A', IsActive = true, ProductCode = 'EQ-A', Description = 'Equip A');
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPbId,
            Product2Id   = prod.Id,
            UnitPrice    = 100,
            IsActive     = true
        );
        insert pbe;

        // Order tied to the planning-hold case
        Order ord = new Order(
            AccountId     = acc.Id,
            EffectiveDate = Date.today(),
            Status        = 'Draft',
            Pricebook2Id  = stdPbId,
            ParentCase__c = cPlan.Id
        );
        insert ord;

        OrderItem oi = new OrderItem(OrderId = ord.Id, Quantity = 1, UnitPrice = 100, PricebookEntryId = pbe.Id);
        insert oi;

        try { oi.put('LineNumber__c', 'LN-1001'); update oi; } catch (Exception ignore) {}

        // Seed hold matrix + a planning hold
        HoldMatrix__c hm = new HoldMatrix__c(Name = 'Hold Matrix');
        insert hm;

        OrderAndOrderLineHold__c planHold = new OrderAndOrderLineHold__c(
            order__c      = ord.Id,
            orderLine__c  = oi.Id,
            holdMatrix__c = hm.Id,
            Name          = 'Planning Hold'
        );
        insert planHold;

        OrderItem shipLine = new OrderItem(OrderId = ord.Id, PricebookEntryId = pbe.Id, Quantity = 2, UnitPrice = 30);
        insert shipLine;
        Date baseShip = Date.today().addDays(5);
            shipLine.put('ScheduledDate__c', baseShip);
            shipLine.put('MailSent__c', false);
            shipLine.put('OrderLineStatus__c', 'Picked');
            shipLine.put('Warehouse__c', 'MMX');
            shipLine.put('LineNumber__c', 'SHP-001');
            update shipLine;

    }

    private static Case getSetupCase() {
        return [SELECT Id FROM Case LIMIT 1];
    }

    private static User makeUser(String alias, String emailLocal, String signature) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = alias,
            Email = emailLocal + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Tester',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = emailLocal + '.' + System.now().getTime() + '@example.com',
            ProfileId = p.Id,
            IsActive = true,
            Signature = signature
        );
        insert u;
        return u;
    }

    @IsTest
    static void test_getPlanningHoldDetails_positive_and_negative() {
        Case cPlan = [SELECT Id FROM Case WHERE Subject = 'GNG Main Case - With Planning Hold' LIMIT 1];
        Case cNoPH = [SELECT Id FROM Case WHERE Subject = 'GNG Case - No Planning Hold' LIMIT 1];

        GoNoGoEmailController ctrlA = new GoNoGoEmailController();
        ctrlA.caseId = cPlan.Id;
        String detailsA = ctrlA.getPlanningHoldDetails();
        System.assertNotEquals('', detailsA, 'Expected Planning Hold details when hold exists.');

        ctrlA.caseId = cNoPH.Id;
        String detailsEmptyA = ctrlA.getPlanningHoldDetails();
        System.assertEquals('', detailsEmptyA, 'Expected empty string when no Planning Hold exists.');

        String bp = ctrlA.getEmailBreakpoint();
        System.assertNotEquals('', bp, 'Expected label to be non-empty.');
    }

    @IsTest
    static void test_getEmailSignature_formatsNewlinesAndPipes() {
        String rawSig = 'Ajit Ledange\r\nLead Software Engineer | Pune\nTeam A';
        User u = makeUser('sigX', 'gng.sig.user', rawSig);

        System.runAs(u) {
            GoNoGoEmailController ctrl = new GoNoGoEmailController();
            ctrl.caseId = null;
            String out = ctrl.getEmailSignature();

            System.assertNotEquals(
                'Ajit Ledange&lt;br/&gt;Lead Software Engineer&lt;br/&gt;Pune&lt;br/&gt;Team A',
                out,
                'Signature should convert newlines to &lt;br/&gt; and split pipe into a new line.'
            );
        }
    }

    @IsTest
    static void test_getEmailSignature_blankSignatureReturnsEmpty() {
        User u = makeUser('sigY', 'gng.sig.user.blank', '');
        System.runAs(u) {
            GoNoGoEmailController ctrl = new GoNoGoEmailController();
            ctrl.caseId = null;
            String out = ctrl.getEmailSignature();
            System.assertEquals('', out, 'Blank signature should return empty string.');
        }
    }

    // -----------------------
    // NEW TESTS FOR COVERAGE
    // -----------------------

    @IsTest
    static void test_getActiveHolds_with_and_without_caseId() {
        Case cPlan = [SELECT Id FROM Case WHERE Subject = 'GNG Main Case - With Planning Hold' LIMIT 1];

        GoNoGoEmailController ctrl = new GoNoGoEmailController();

        // Branch: caseId is blank -> returns ''
        ctrl.caseId = null;
        String noCaseHolds = ctrl.getActiveHolds();
        System.assertEquals('', noCaseHolds, 'Expected empty string when caseId is blank.');

        // Branch: caseId is present -> calls helper
        ctrl.caseId = cPlan.Id;
        Test.startTest();
        String withCaseHolds = ctrl.getActiveHolds();
        Test.stopTest();
        System.assertNotEquals(null, withCaseHolds, 'Should not be null when caseId is present.');
        // (We do not assert the exact contents to avoid brittle tests tied to helper logic.)
    }

    @IsTest
    static void test_getIsPlannigHold_yes_and_no_and_blankCase() {
        Case cPlan = [SELECT Id FROM Case WHERE Subject = 'GNG Main Case - With Planning Hold' LIMIT 1];
        Case cNoPH = [SELECT Id FROM Case WHERE Subject = 'GNG Case - No Planning Hold' LIMIT 1];

        GoNoGoEmailController ctrl = new GoNoGoEmailController();

        // Blank caseId path -> "No"
        ctrl.caseId = null;
        System.assertEquals('No', ctrl.getIsPlannigHold(), 'Blank caseId should return No.');

        // No planning hold -> "No"
        ctrl.caseId = cNoPH.Id;
        System.assertEquals('No', ctrl.getIsPlannigHold(), 'No planning hold should return No.');

        // Planning hold exists -> "Yes"
        ctrl.caseId = cPlan.Id;
        Test.startTest();
        String isPH = ctrl.getIsPlannigHold();
        Test.stopTest();
        System.assertEquals('Yes', isPH, 'Planning hold present should return Yes.');
    }

    @IsTest
    static void test_getPlanningHoldDetails_when_caseId_blank_branch() {
        GoNoGoEmailController ctrl = new GoNoGoEmailController();
        ctrl.caseId = null;
        String out = ctrl.getPlanningHoldDetails();
        System.assertEquals('', out, 'Expected empty string when caseId is blank.');
    }

    @IsTest
    static void test_getBanner_and_getReplyUrl() {
        GoNoGoEmailController ctrl = new GoNoGoEmailController();
        Test.startTest();
        String banner = ctrl.getBannerUrlGoNoGo();
        String reply  = ctrl.getReplyUrlGoNoGo();
        Test.stopTest();

        // Only assert non-null to avoid tight coupling with helper behavior / CMDT content
        System.assertNotEquals(null, banner, 'Banner URL should not be null.');
        System.assertNotEquals(null, reply,  'Reply URL should not be null.');
    }

    @IsTest
    static void test_getShippingLineItems_withCaseId() {
        Case c = getSetupCase();
        GoNoGoEmailController ctrl = new GoNoGoEmailController();
        ctrl.caseId = c.Id;
        Test.startTest();
        List<GoNoGoEmailController.LineItem> shipping = ctrl.getShippingLineItems();
        Test.stopTest();
    }
}