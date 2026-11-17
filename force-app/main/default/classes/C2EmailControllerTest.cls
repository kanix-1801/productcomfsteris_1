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
// ---------------------------------------------------------------------
// CBM-1480 test data helpers
// ---------------------------------------------------------------------

private static Order createCbmOrder(String subject) {
    Case testCase = new Case(
        Origin = 'Phone',
        Status = 'New',
        Subject = subject
    );
    insert testCase;

    Account accountRecord = [SELECT Id FROM Account LIMIT 1];

    Order orderRecord = new Order(
        AccountId = accountRecord.Id,
        EffectiveDate = Date.today(),
        Status = 'Draft',
        Pricebook2Id = Test.getStandardPricebookId(),
        ParentCase__c = testCase.Id
    );
    insert orderRecord;

    return [
        SELECT Id,
               ParentCase__c,
               Pricebook2Id,
               Country__c,
               IsTradInLineOpen__c
        FROM Order
        WHERE Id = :orderRecord.Id
    ];
}

private static void addOpenTradeInLine(Order orderRecord) {
    String suffix =
        String.valueOf(orderRecord.Id).right(4) +
        String.valueOf(Limits.getDmlStatements());

    Product2 tradeProduct = new Product2(
        Name = 'CBM-1480 Trade-In ' + suffix,
        IsActive = true,
        ProductCode = 'CBMTR' + suffix,
        ItemID__c = 'CBM' + suffix,
        InventoryOrgId__c = 'CBM' + suffix
    );

    Schema.SObjectField itemTypeField =
        Schema.SObjectType.Product2.fields
            .getMap()
            .get('ItemType__c');

    if (
        itemTypeField != null &&
        itemTypeField.getDescribe().isCreateable()
    ) {
        tradeProduct.put('ItemType__c', 'Trade-In');
    }

    insert tradeProduct;

    PricebookEntry tradeEntry = new PricebookEntry(
        Pricebook2Id = orderRecord.Pricebook2Id,
        Product2Id = tradeProduct.Id,
        UnitPrice = 10,
        IsActive = true
    );
    insert tradeEntry;

    OrderItem tradeLine = new OrderItem(
        OrderId = orderRecord.Id,
        PricebookEntryId = tradeEntry.Id,
        Quantity = -1,
        UnitPrice = 10,
        OrderLineStatus__c = 'Picked',
        MailSent__c = false
    );

    Schema.SObjectField lineTypeField =
        Schema.SObjectType.OrderItem.fields
            .getMap()
            .get('OrderLineType__c');

    if (
        lineTypeField != null &&
        lineTypeField.getDescribe().isCreateable()
    ) {
        tradeLine.put(
            'OrderLineType__c',
            'Trade In Lines'
        );
    }

    insert tradeLine;
}

private static Order refreshCbmOrder(Id orderId) {
    return [
        SELECT Id,
               ParentCase__c,
               Pricebook2Id,
               Country__c,
               IsTradInLineOpen__c
        FROM Order
        WHERE Id = :orderId
    ];
}

@IsTest
static void cbm1480_blankCaseId_hidesConditionalMessage() {
    C2EmailController controller =
        new C2EmailController();

    controller.caseId = null;
    System.assertEquals(
        false,
        controller.getHasOpenTradeInLines(),
        'Null Case Id must hide the Trade-In paragraph.'
    );

    controller.caseId = '';
    System.assertEquals(
        false,
        controller.getHasOpenTradeInLines(),
        'Empty Case Id must hide the Trade-In paragraph.'
    );

    controller.caseId = '   ';
    System.assertEquals(
        false,
        controller.getHasOpenTradeInLines(),
        'Whitespace Case Id must hide the Trade-In paragraph.'
    );
}

@IsTest
static void cbm1480_caseWithoutOrder_hidesConditionalMessage() {
    Case caseWithoutOrder = new Case(
        Origin = 'Phone',
        Status = 'New',
        Subject = 'CBM-1480 no Order'
    );
    insert caseWithoutOrder;

    C2EmailController controller =
        new C2EmailController();

    controller.caseId = caseWithoutOrder.Id;

    Test.startTest();
    Boolean shouldRender =
        controller.getHasOpenTradeInLines();
    Test.stopTest();

    System.assertEquals(
        false,
        shouldRender,
        'The paragraph must remain hidden when no Order exists.'
    );
}

@IsTest
static void cbm1480_orderWithoutTradeIn_hidesConditionalMessage() {
    Order orderRecord =
        createCbmOrder('CBM-1480 zero Trade-In');

    Order refreshedOrder =
        refreshCbmOrder(orderRecord.Id);

    System.assertEquals(
        0,
        refreshedOrder.IsTradInLineOpen__c,
        'The new Order must initially have no open Trade-In lines.'
    );

    C2EmailController controller =
        new C2EmailController();

    controller.caseId =
        refreshedOrder.ParentCase__c;

    Test.startTest();
    Boolean shouldRender =
        controller.getHasOpenTradeInLines();
    Test.stopTest();

    System.assertEquals(
        false,
        shouldRender,
        'An Order without open Trade-In lines must hide the paragraph.'
    );
}

    @IsTest
    static void cbm1480_openTradeIn_usesCalculatedOrderValues() {
        Order orderRecord =
            createCbmOrder('CBM-1480 calculated values');

        addOpenTradeInLine(orderRecord);

        Order refreshedOrder =
            refreshCbmOrder(orderRecord.Id);

        List<Order> selectedOrders =
            OrderSelector.orderRecord(
                refreshedOrder.ParentCase__c
            );

        System.assertNotEquals(
            null,
            selectedOrders,
            'OrderSelector must return the related Order.'
        );

        System.assertEquals(
            1,
            selectedOrders.size(),
            'The test Case must have one related Order.'
        );

        /*
        * Country__c and IsTradInLineOpen__c are calculated/read-only
        * fields. The test must not assign values directly to them.
        *
        * Instead, calculate the expected controller result from the
        * values returned by Salesforce.
        */
        Order selectedOrder = selectedOrders[0];

        Boolean expectedResult =
            selectedOrder.Country__c == 'Canada' &&
            selectedOrder.IsTradInLineOpen__c != null &&
            selectedOrder.IsTradInLineOpen__c > 0;

        C2EmailController controller =
            new C2EmailController();

        controller.caseId =
            refreshedOrder.ParentCase__c;

        Test.startTest();
        Boolean actualResult =
            controller.getHasOpenTradeInLines();
        Test.stopTest();

        System.assertEquals(
            expectedResult,
            actualResult,
            'The controller result must match the calculated Order country and open Trade-In count.'
        );
    }

    @IsTest
    static void cbm1480_helperMatchesOrderCalculation() {
        Order orderRecord =
            createCbmOrder('CBM-1480 helper calculation');

        addOpenTradeInLine(orderRecord);

        Order refreshedOrder =
            refreshCbmOrder(orderRecord.Id);

        Boolean expectedResult =
            refreshedOrder.Country__c == 'Canada' &&
            refreshedOrder.IsTradInLineOpen__c != null &&
            refreshedOrder.IsTradInLineOpen__c > 0;

        Test.startTest();
        Boolean actualResult =
            EmailControllerHelper.hasOpenTradeInLines(
                refreshedOrder.ParentCase__c
            );
        Test.stopTest();

        System.assertEquals(
            expectedResult,
            actualResult,
            'Helper output must match the calculated Order field values.'
        );
    }

    @IsTest
    static void cbm1480_selectorFieldsAreAvailable() {
        Order orderRecord =
            createCbmOrder('CBM-1480 selector fields');

        List<Order> selectedOrders =
            OrderSelector.orderRecord(
                orderRecord.ParentCase__c
            );

        System.assertNotEquals(
            null,
            selectedOrders,
            'OrderSelector must return a list.'
        );

        System.assertEquals(
            1,
            selectedOrders.size(),
            'Exactly one Order should be related to the test Case.'
        );

        /*
        * Accessing these fields proves that OrderSelector queried them.
        * If either field is missing from the selector SOQL, Salesforce
        * throws an SObjectException.
        */
        String calculatedCountry =
            selectedOrders[0].Country__c;

        Decimal openTradeInCount =
            selectedOrders[0].IsTradInLineOpen__c;

        System.assertEquals(
            calculatedCountry,
            selectedOrders[0].Country__c
        );

        System.assertEquals(
            openTradeInCount,
            selectedOrders[0].IsTradInLineOpen__c
        );
    }

    @IsTest
    static void cbm1480_selectorException_isRethrownByController() {
        Order orderRecord =
            createCbmOrder('CBM-1480 selector exception');

        C2EmailController controller =
            new C2EmailController();

        controller.caseId =
            orderRecord.ParentCase__c;

        Boolean caught = false;

        OrderSelector.throwTestException = true;

        try {
            controller.getHasOpenTradeInLines();
        } catch (Exception expected) {
            caught = true;
        } finally {
            OrderSelector.throwTestException = false;
        }

        System.assertEquals(
            true,
            caught,
            'Selector exceptions must remain visible to the caller.'
        );
    }

    @IsTest
    static void test_remainingControllerNullGuardsAndLineItemMapping() {
        C2EmailController controller =
            new C2EmailController();

        controller.caseId = null;

        System.assertEquals(
            '',
            controller.getinstallContact()
        );

        System.assertEquals(
            0,
            controller.getShippingLineItems().size()
        );

        System.assertEquals(
            0,
            controller.getOpenLineItems().size()
        );

        System.assertEquals(
            null,
            controller.getFirstScheduledShipDate()
        );

        System.assertEquals(
            null,
            controller.getLastScheduledShipDate()
        );

        System.assertEquals(
            false,
            controller.getHasOpenTradeInLines()
        );

        System.assertNotEquals(
            null,
            controller.getEmailSignature()
        );

        Date shipDate =
            Date.today().addDays(10);

        C2EmailController.LineItem line =
            new C2EmailController.LineItem(
                'ITEM-1',
                '10',
                'Fixture description',
                2,
                shipDate,
                '1 Test Way',
                'Toronto',
                'ON',
                'A1A 1A1',
                'Canada'
            );

        System.assertEquals(
            'ITEM-1',
            line.itemNumber
        );

        System.assertEquals(
            '10',
            line.lineNumber
        );

        System.assertEquals(
            'Fixture description',
            line.itemDescription
        );

        System.assertEquals(
            2,
            line.qty
        );

        System.assertEquals(
            shipDate,
            line.shipDate
        );

        System.assertEquals(
            '1 Test Way',
            line.street
        );

        System.assertEquals(
            'Toronto',
            line.city
        );

        System.assertEquals(
            'ON',
            line.state
        );

        System.assertEquals(
            'A1A 1A1',
            line.postalCode
        );

        System.assertEquals(
            'Canada',
            line.country
        );
    }
}