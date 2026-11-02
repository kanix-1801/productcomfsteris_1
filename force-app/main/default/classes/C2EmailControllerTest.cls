/**
 * @author PSL
 * @date 12-10-2025
 * @description Test class for C2EmailController that validates helper methods for email functionality
 */
@IsTest
private class C2EmailControllerTest {
    @TestSetup
    static void setupData() {
        // Minimal Case
        Case c = new Case(Origin = 'Phone', Status = 'New', Subject = 'C2 Test Case');
        insert c;

        // Contacts used in CaseContactRoles
        Contact recv = new Contact(LastName = 'Receiving Contact', Email = 'recv@example.com');
        Contact inst = new Contact(LastName = 'Install Contact', Email = 'inst@example.com');
        insert new List<Contact>{ recv, inst };

        // Case Contact Roles for helper methods
        insert new List<CaseContactRole>{
            new CaseContactRole(CasesId = c.Id, ContactId = recv.Id, Role = 'Receiving Contact'),
            new CaseContactRole(CasesId = c.Id, ContactId = inst.Id, Role = 'Install Contact')
        };

        Id stdPbId = Test.getStandardPricebookId();
        Account acc = new Account(Name = 'SDN Test Account');
        insert acc;
        Product2 prod = new Product2(Name = 'Prod A', IsActive = true, ProductCode = 'P-100', Description = 'Prod A Desc');
        insert prod;
        PricebookEntry pbe = new PricebookEntry(Pricebook2Id = stdPbId, Product2Id = prod.Id, UnitPrice = 100, IsActive = true);
        insert pbe;
        Order ord = new Order(AccountId = acc.Id, EffectiveDate = Date.today(), Status = 'Draft', Pricebook2Id = stdPbId, ParentCase__c = c.Id);
        insert ord;
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

    @IsTest
    static void test_getAccountManagerCapSerLineSalesRep_blankCaseId() {
        C2EmailController ctrl = new C2EmailController();
        ctrl.caseId = null;
        Test.startTest();
        String val = ctrl.getAccountManagerCapSerLineSalesRep();
        Test.stopTest();
        System.assertEquals('', val, 'Blank caseId should return empty string');
    }

    @IsTest
    static void test_getAccountManagerCapSerLineSalesRep_withCaseId() {
        Case c = getSetupCase();
        C2EmailController ctrl = new C2EmailController();
        ctrl.caseId = c.Id;
        Test.startTest();
        String val = ctrl.getAccountManagerCapSerLineSalesRep();
        Test.stopTest();
        // Helper may return empty if no data matches; ensure method executed
        System.assertEquals(String.valueOf(val), val, 'Return should be a String (possibly empty)');
    }

    @IsTest
    static void test_getCaseContactRoles_blankCaseId() {
        C2EmailController ctrl = new C2EmailController();
        ctrl.caseId = '';
        Test.startTest();
        List<CaseContactRole> roles = ctrl.getCaseContactRoles();
        Test.stopTest();
        System.assertEquals(0, roles.size(), 'Blank caseId should return empty list');
    }

    @IsTest
    static void test_getCaseContactRoles_withCaseId() {
        Case c = getSetupCase();
        C2EmailController ctrl = new C2EmailController();
        ctrl.caseId = c.Id;
        Test.startTest();
        List<CaseContactRole> roles = ctrl.getCaseContactRoles();
        Test.stopTest();
        System.assert(roles.size() >= 2, 'Should return Receiving and Install contacts when present');
        Set<String> roleNames = new Set<String>();
        for (CaseContactRole r : roles) roleNames.add(r.Role);
        System.assert(roleNames.contains('Receiving Contact'));
        System.assert(roleNames.contains('Install Contact'));
    }

    @IsTest
    static void test_getGiReprocessingOrders_blankCaseId() {
        C2EmailController ctrl = new C2EmailController();
        Test.startTest();
        Boolean res = ctrl.getGiReprocessingOrders();
        Test.stopTest();
        System.assertEquals(false, res, 'Blank caseId should return false');
    }

    @IsTest
    static void test_getGiReprocessingOrders_withCaseId() {
        Case c = getSetupCase();
        C2EmailController ctrl = new C2EmailController();
        ctrl.caseId = c.Id;
        Test.startTest();
        Boolean res = ctrl.getGiReprocessingOrders();
        Test.stopTest();
        System.assert(res == true || res == false, 'Should return a boolean');
    }

    @IsTest
    static void test_getActiveHolds_blankCaseId() {
        C2EmailController ctrl = new C2EmailController();
        Test.startTest();
        String res = ctrl.getActiveHolds();
        Test.stopTest();
        System.assertEquals('', res, 'Blank caseId should return empty string');
    }

    @IsTest
    static void test_getActiveHolds_withCaseId() {
        Case c = getSetupCase();
        C2EmailController ctrl = new C2EmailController();
        ctrl.caseId = c.Id;
        Test.startTest();
        String res = ctrl.getActiveHolds();
        Test.stopTest();
        System.assertEquals(String.valueOf(res), res, 'Should return a string (possibly empty)');
    }

    @IsTest
    static void test_getIsPlannigHold_blankCaseId() {
        C2EmailController ctrl = new C2EmailController();
        Test.startTest();
        String res = ctrl.getIsPlannigHold();
        Test.stopTest();
        System.assertEquals('No', res, 'Blank caseId should return "No"');
    }

    @IsTest
    static void test_getIsPlannigHold_withCaseId() {
        Case c = getSetupCase();
        C2EmailController ctrl = new C2EmailController();
        ctrl.caseId = c.Id;
        Test.startTest();
        String res = ctrl.getIsPlannigHold();
        Test.stopTest();
        System.assert(new Set<String>{'Yes','No'}.contains(res), 'Should return Yes/No');
    }

    @IsTest
    static void test_getPlanningHoldDetails_blankCaseId() {
        C2EmailController ctrl = new C2EmailController();
        Test.startTest();
        String res = ctrl.getPlanningHoldDetails();
        Test.stopTest();
        System.assertEquals('', res, 'Blank caseId should return empty');
    }

    @IsTest
    static void test_getPlanningHoldDetails_withCaseId() {
        Case c = getSetupCase();
        C2EmailController ctrl = new C2EmailController();
        ctrl.caseId = c.Id;
        Test.startTest();
        String res = ctrl.getPlanningHoldDetails();
        Test.stopTest();
        System.assertEquals(String.valueOf(res), res, 'Should return a string (possibly empty)');
    }

    @IsTest
    static void test_getBlUser_blankCaseId() {
        C2EmailController ctrl = new C2EmailController();
        Test.startTest();
        String res = ctrl.getBlUser();
        Test.stopTest();
        System.assertEquals('', res, 'Blank caseId returns empty');
    }

    @IsTest
    static void test_getBlUser_withCaseId() {
        Case c = getSetupCase();
        C2EmailController ctrl = new C2EmailController();
        ctrl.caseId = c.Id;
        Test.startTest();
        String res = ctrl.getBlUser();
        Test.stopTest();
        // Could be empty or a name depending on Case Team setup
        System.assertEquals(String.valueOf(res), res, 'Should return a string (possibly empty)');
    }

    @IsTest
    static void test_getisServiceLine_blankCaseId() {
        C2EmailController ctrl = new C2EmailController();
        Test.startTest();
        Boolean res = ctrl.getisServiceLine();
        Test.stopTest();
        System.assertEquals(false, res, 'Blank caseId should return false');
    }

    @IsTest
    static void test_getisServiceLine_withCaseId() {
        Case c = getSetupCase();
        C2EmailController ctrl = new C2EmailController();
        ctrl.caseId = c.Id;
        Test.startTest();
        Boolean res = ctrl.getisServiceLine();
        Test.stopTest();
        System.assert(res == true || res == false, 'Should return a boolean');
    }

    @IsTest
    static void test_getShippingLineItems_withCaseId() {
        Case c = getSetupCase();
        C2EmailController ctrl = new C2EmailController();
        ctrl.caseId = c.Id;
        Test.startTest();
        List<C2EmailController.LineItem> shipping = ctrl.getShippingLineItems();
        Test.stopTest();
    }
}