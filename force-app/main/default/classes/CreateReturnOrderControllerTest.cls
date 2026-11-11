/**
 * @description Test class for CreateReturnOrderController.
 */
@isTest
private class CreateReturnOrderControllerTest {

    private static String groupKeyFor(String returnOrderType, String innerKey) {
        return returnOrderType + '::' + innerKey;
    }

    private static String getDisinfectedYesValueForTest() {
        for (Schema.PicklistEntry entry : ReturnOrderLineItem.Disinfected__c.getDescribe()
            .getPicklistValues()) {
            if (entry.isActive() && entry.getValue().toLowerCase().startsWith('yes')) {
                return entry.getValue();
            }
        }
        return 'Yes, Item is Disinfected';
    }

    private static String getDisinfectedNoValueForTest() {
        for (Schema.PicklistEntry entry : ReturnOrderLineItem.Disinfected__c.getDescribe()
            .getPicklistValues()) {
            if (entry.isActive() && entry.getValue().toLowerCase().startsWith('no')) {
                return entry.getValue();
            }
        }
        return 'No, Item is not Disinfected';
    }

    private static Account insertRoutingShipTo(
        Id parentAccountId,
        String name,
        String sourceSystemId,
        String stateCode
    ) {
        Account shipTo = new Account(
            Name = name,
            ParentId = parentAccountId,
            SourceSystemID__c = sourceSystemId,
            Type = 'Address',
            ShiptoAddressStatus__c = 'Primary'
        );
        if (String.isNotBlank(stateCode)) {
            shipTo.BillingCountryCode = 'US';
            shipTo.BillingStateCode = stateCode;
        }
        insert shipTo;
        return shipTo;
    }

    private static String getEstimateRequiredFieldApiName() {
        if (
            Schema.SObjectType.ReturnOrderLineItem.fields.getMap()
                .containsKey('estimaterequired__c')
        ) {
            return 'EstimateRequired__c';
        }
        return 'EstReq__c';
    }

    private static Object readEstimateRequiredValue(Id returnOrderId) {
        return readReturnOrderLineItemField(
            returnOrderId,
            getEstimateRequiredFieldApiName()
        );
    }

    private static String readReturnOrderType(Id returnOrderId) {
        try {
            ReturnOrder returnOrder = Database.query(
                'SELECT ReturnOrderType__c FROM ReturnOrder WHERE Id = :returnOrderId LIMIT 1'
            );
            return (String) returnOrder.get('ReturnOrderType__c');
        } catch (Exception e) {
            return null;
        }
    }

    private static void assertReturnOrderType(Id returnOrderId, String expectedType) {
        String actualType = readReturnOrderType(returnOrderId);
        if (actualType == null) {
            return;
        }
        System.assertEquals(expectedType, actualType);
    }

    private static Object readReturnOrderLineItemField(
        Id returnOrderId,
        String fieldApiName
    ) {
        if (
            !Schema.SObjectType.ReturnOrderLineItem.fields.getMap()
                .containsKey(fieldApiName.toLowerCase())
        ) {
            return null;
        }

        List<SObject> lineItems = Database.query(
            'SELECT ' +
            fieldApiName +
            ' FROM ReturnOrderLineItem WHERE ReturnOrderId = :returnOrderId LIMIT 1'
        );
        return lineItems.isEmpty() ? null : lineItems[0].get(fieldApiName);
    }

    private static void assertInstrumentAdditionalServiceFields(
        Id returnOrderId,
        Boolean expectedModRequest,
        String expectedInsulationPowderCoating,
        String expectedColorDipping,
        String expectedSerialNumber
    ) {
        if (
            !Schema.SObjectType.ReturnOrderLineItem.fields.getMap()
                .containsKey('insulationpowdercoating__c')
        ) {
            return;
        }

        System.assertEquals(
            expectedModRequest,
            readReturnOrderLineItemField(returnOrderId, 'ModRequest__c')
        );
        System.assertEquals(
            expectedInsulationPowderCoating,
            readReturnOrderLineItemField(returnOrderId, 'InsulationPowderCoating__c')
        );
        System.assertEquals(
            expectedColorDipping,
            readReturnOrderLineItemField(returnOrderId, 'ColorDipping__c')
        );
        System.assertEquals(
            expectedSerialNumber,
            readReturnOrderLineItemField(returnOrderId, 'SerialNumber__c')
        );
    }

    private static void assertInstrumentLegPositionersField(
        Id returnOrderId,
        String expectedLegPositionersStirrup,
        String expectedSerialNumber
    ) {
        if (
            !Schema.SObjectType.ReturnOrderLineItem.fields.getMap()
                .containsKey('legpositionersstirrup__c')
        ) {
            return;
        }

        System.assertEquals(
            expectedLegPositionersStirrup,
            readReturnOrderLineItemField(returnOrderId, 'LegPositionersStirrup__c')
        );
        System.assertEquals(
            expectedSerialNumber,
            readReturnOrderLineItemField(returnOrderId, 'SerialNumber__c')
        );
    }

    private static void assertInstrumentNoSerialAdditionalServiceFields(
        Id returnOrderId,
        Boolean expectedAdditionalServiceRepair,
        String expectedLaserMarking,
        String expectedColorDipping,
        String expectedNumberOfRings
    ) {
        if (
            !Schema.SObjectType.ReturnOrderLineItem.fields.getMap()
                .containsKey('additionalservicerepair__c')
        ) {
            return;
        }

        System.assertEquals(
            expectedAdditionalServiceRepair,
            readReturnOrderLineItemField(returnOrderId, 'AdditionalServiceRepair__c')
        );
        System.assertEquals(
            expectedLaserMarking,
            readReturnOrderLineItemField(returnOrderId, 'LaserMarking__c')
        );
        System.assertEquals(
            expectedColorDipping,
            readReturnOrderLineItemField(returnOrderId, 'ColorDipping__c')
        );
        System.assertEquals(
            expectedNumberOfRings,
            readReturnOrderLineItemField(returnOrderId, 'NumberOfRings__c')
        );
    }

    @TestSetup
    static void setupTestData() {
        Account testAccount = new Account(
            Name = 'Return Order Test Account',
            SystemID__c = 'LEG-1001',
            SourceSystemID__c = 'TEST-ORACLE-001',
            OrgIDs__c = '82'
        );
        insert testAccount;

        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            AccountId = testAccount.Id
        );
        insert testContact;

        Case testCase = new Case(
            Subject = 'Return Order Test Case',
            AccountId = testAccount.Id,
            Status = 'New'
        );
        insert testCase;

        Schema.Location repairCenter = new Schema.Location(
            Name = 'Test Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        Department__c testDepartment = new Department__c(
            Name = 'Surgery'
        );
        insert testDepartment;

        insert new AccountDepartment__c(
            Account__c = testAccount.Id,
            Department__c = testDepartment.Id
        );

        Product2 testProduct = new Product2(
            Name = 'Test Service Asset Product',
            ProductType__c = 'Service Asset',
            ProductLine__c = 'Surgical',
            IsActive = true
        );
        insert testProduct;

        insert new Product2(
            Name = 'Default Product',
            ProductType__c = 'Service Asset',
            ProductLine__c = 'INSTRUMENT',
            IsActive = true,
            Description = 'Default return order product'
        );

        Asset testAsset = new Asset(
            Name = 'Test Asset',
            AccountId = testAccount.Id,
            SerialNumber = 'SN-001',
            Product2Id = testProduct.Id,
            Department__c = testDepartment.Id
        );
        insert testAsset;
    }

    @isTest
    static void testGetDefaultProduct_returnsDefaultProductByName() {
        Test.startTest();
        Product2 defaultProduct = CreateReturnOrderController.getDefaultProduct();
        Test.stopTest();

        System.assertNotEquals(null, defaultProduct);
        System.assertEquals('Default Product', defaultProduct.Name);
    }

    @isTest
    static void testGetInitialContextFromAccount() {
        Account account = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        CreateReturnOrderController.InitContext ctx =
            CreateReturnOrderController.getInitialContext(account.Id, 'Account', null);
        Test.stopTest();

        System.assertEquals(account.Id, ctx.accountId);
        System.assertEquals('LEG-1001', ctx.legacyCustomerId);
        System.assertEquals('82', ctx.defaultOperatingUnit);
        System.assertNotEquals(null, ctx.operatingUnitOptions);
        System.assertNotEquals(null, ctx.defaultProductId);
    }

    @isTest
    static void testGetInitialContextFromCase() {
        Case testCase = [SELECT Id, AccountId FROM Case LIMIT 1];

        Test.startTest();
        CreateReturnOrderController.InitContext ctx =
            CreateReturnOrderController.getInitialContext(testCase.Id, 'Case', null);
        Test.stopTest();

        System.assertEquals(testCase.AccountId, ctx.accountId);
        System.assertEquals(testCase.Id, ctx.caseId);
        System.assertEquals(true, ctx.lockCase);
        System.assertEquals(true, ctx.lockAccount);
        System.assertNotEquals(null, ctx.accountName);
    }

    @isTest
    static void testGetInitialContextFromAssets() {
        Asset asset = [SELECT Id FROM Asset LIMIT 1];
        List<String> assetIds = new List<String>{ asset.Id };

        Test.startTest();
        CreateReturnOrderController.InitContext ctx =
            CreateReturnOrderController.getInitialContext(null, 'Asset', assetIds);
        Test.stopTest();

        System.assertEquals(1, ctx.assetIds.size());
        System.assertEquals(asset.Id, ctx.assetIds[0]);

        Account account = [SELECT Id FROM Account LIMIT 1];
        System.assertEquals(account.Id, ctx.accountId);
    }

    @isTest
    static void testGetInitialContextUsesFirstSelectedAssetAccount() {
        Account firstAccount = new Account(
            Name = 'First Selected Account',
            SystemID__c = 'LEG-FIRST',
            SourceSystemID__c = 'TEST-ORACLE-002'
        );
        Account secondAccount = new Account(
            Name = 'Second Selected Account',
            SystemID__c = 'LEG-SECOND',
            SourceSystemID__c = 'TEST-ORACLE-003'
        );
        insert new List<Account>{ firstAccount, secondAccount };

        Asset firstAsset = new Asset(
            Name = 'First Selected Asset',
            AccountId = firstAccount.Id,
            SerialNumber = 'SN-FIRST'
        );
        Asset secondAsset = new Asset(
            Name = 'Second Selected Asset',
            AccountId = secondAccount.Id,
            SerialNumber = 'SN-SECOND'
        );
        insert new List<Asset>{ firstAsset, secondAsset };

        List<String> assetIds = new List<String>{
            String.valueOf(firstAsset.Id),
            String.valueOf(secondAsset.Id)
        };

        Test.startTest();
        CreateReturnOrderController.InitContext ctx =
            CreateReturnOrderController.getInitialContext(null, null, assetIds);
        Test.stopTest();

        System.assertEquals(firstAccount.Id, ctx.accountId);
        System.assertEquals(2, ctx.assetIds.size());
        System.assertEquals(firstAsset.Id, ctx.assetIds[0]);
        System.assertEquals(secondAsset.Id, ctx.assetIds[1]);
    }

    @isTest
    static void testGetInitialContextInfersObjectFromRecordId() {
        Account account = [SELECT Id, Name FROM Account LIMIT 1];

        Test.startTest();
        CreateReturnOrderController.InitContext ctx =
            CreateReturnOrderController.getInitialContext(account.Id, null, null);
        Test.stopTest();

        System.assertEquals(account.Id, ctx.accountId);
        System.assertEquals(account.Name, ctx.accountName);
    }

    @isTest
    static void testGetInitialContextFromSingleAssetRecord() {
        Asset asset = [SELECT Id, AccountId FROM Asset LIMIT 1];

        Test.startTest();
        CreateReturnOrderController.InitContext ctx =
            CreateReturnOrderController.getInitialContext(asset.Id, 'Asset', null);
        Test.stopTest();

        System.assertEquals(asset.AccountId, ctx.accountId);
        System.assertEquals(1, ctx.assetIds.size());
    }

    @isTest
    static void testGetContactsAndCasesAndLocations() {
        Account account = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<Contact> contacts = CreateReturnOrderController.getContactsForAccount(account.Id);
        List<Case> cases = CreateReturnOrderController.getOpenCasesForAccount(account.Id);
        List<CreateReturnOrderController.LocationOption> locations =
            CreateReturnOrderController.getRepairCenterLocations();
        List<User> users = CreateReturnOrderController.getActiveInternalUsers();
        Test.stopTest();

        System.assert(!contacts.isEmpty());
        System.assert(!cases.isEmpty());
        System.assert(!locations.isEmpty());
        System.assert(!users.isEmpty());
    }

    @isTest
    static void testCheckOpenReturnOrdersForAsset_findsOpenOrder() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];

        ReturnOrder openReturnOrder = new ReturnOrder(
            AccountId = account.Id,
            Status = 'Created'
        );
        openReturnOrder.put('OperatingUnit__c', '82');
        insert openReturnOrder;

        insert new ReturnOrderLineItem(
            ReturnOrderId = openReturnOrder.Id,
            AssetId = asset.Id,
            Product2Id = asset.Product2Id,
            QuantityReturned = 1
        );

        openReturnOrder = [
            SELECT ReturnOrderNumber
            FROM ReturnOrder
            WHERE Id = :openReturnOrder.Id
            LIMIT 1
        ];

        Test.startTest();
        CreateReturnOrderController.AssetReturnOrderCheckResult result =
            CreateReturnOrderController.checkOpenReturnOrdersForAsset(asset.Id);
        Test.stopTest();

        System.assertEquals(true, result.hasOpenReturnOrders);
        System.assertEquals(1, result.returnOrders.size());
        System.assertEquals(openReturnOrder.Id, result.returnOrders[0].returnOrderId);
        System.assertEquals(
            openReturnOrder.ReturnOrderNumber,
            result.returnOrders[0].returnOrderNumber
        );
        System.assertEquals('Created', result.returnOrders[0].status);
    }

    @isTest
    static void testCheckOpenReturnOrdersForAsset_ignoresClosedOrders() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];

        ReturnOrder closedReturnOrder = new ReturnOrder(
            AccountId = account.Id,
            Status = 'Closed'
        );
        closedReturnOrder.put('OperatingUnit__c', '82');
        insert closedReturnOrder;

        insert new ReturnOrderLineItem(
            ReturnOrderId = closedReturnOrder.Id,
            AssetId = asset.Id,
            Product2Id = asset.Product2Id,
            QuantityReturned = 1
        );

        Test.startTest();
        CreateReturnOrderController.AssetReturnOrderCheckResult result =
            CreateReturnOrderController.checkOpenReturnOrdersForAsset(asset.Id);
        Test.stopTest();

        System.assertEquals(false, result.hasOpenReturnOrders);
        System.assertEquals(0, result.returnOrders.size());
    }

    @isTest
    static void testCheckOpenReturnOrdersForAsset_nullAsset() {
        Test.startTest();
        CreateReturnOrderController.AssetReturnOrderCheckResult result =
            CreateReturnOrderController.checkOpenReturnOrdersForAsset(null);
        Test.stopTest();

        System.assertEquals(false, result.hasOpenReturnOrders);
        System.assertEquals(0, result.returnOrders.size());
    }

    @isTest
    static void testGetContactsForAccount_includesAccountContactRelations() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Account otherAccount = new Account(
            Name = 'ACR Test Account',
            SystemID__c = 'LEG-ACR-001',
            SourceSystemID__c = 'TEST-ORACLE-ACR'
        );
        insert otherAccount;

        Contact relatedContact = new Contact(
            FirstName = 'Related',
            LastName = 'ViaACR',
            AccountId = otherAccount.Id
        );
        insert relatedContact;

        insert new AccountContactRelation(
            AccountId = account.Id,
            ContactId = relatedContact.Id
        );

        Test.startTest();
        List<Contact> contacts = CreateReturnOrderController.getContactsForAccount(account.Id);
        Test.stopTest();

        Set<Id> contactIds = new Set<Id>();
        for (Contact contact : contacts) {
            contactIds.add(contact.Id);
        }

        System.assert(
            contactIds.contains(relatedContact.Id),
            'Contacts linked through Account Contact Relationship should be returned.'
        );
    }

    @isTest
    static void testCreateReturnOrder() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        Schema.Location repairCenter = [SELECT Id FROM Location LIMIT 1];
        Asset asset = [SELECT Id, Product2Id, Department__c FROM Asset LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82',
            'creationSource' => 'Salesforce',
            'salesRepId' => UserInfo.getUserId(),
            'caseId' => testCase.Id,
            'repairCenterId' => repairCenter.Id
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'assetId' => asset.Id,
                'product2Id' => asset.Product2Id,
                'model' => 'Test Model',
                'departmentId' => testDepartment.Id,
                'disinfected' => getDisinfectedYesValueForTest(),
                'contactId' => contact.Id,
                'estimateRequired' => 'Pre-Approved',
                'productLine' => 'Surgical',
                'customerPo' => 'PO-123',
                'isLoanerAsset' => true,
                'loanerRequested' => false,
                'reportedProblem' => 'Unit not powering on',
                'customerReference' => 'REF-456',
                'status' => 'Created',
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        CreateReturnOrderController.CreateResult result = CreateReturnOrderController.createReturnOrder(
            JSON.serialize(header),
            JSON.serialize(lines)
        );
        Test.stopTest();

        System.assertNotEquals(null, result.returnOrderId);

        ReturnOrder created = [
            SELECT
                Id,
                AccountId,
                Status,
                OperatingUnit__c,
                LegacyCustomerID__c,
                DestinationLocationId,
                CaseId
            FROM ReturnOrder
            WHERE Id = :result.returnOrderId
            LIMIT 1
        ];
        System.assertEquals(account.Id, created.AccountId);
        System.assertEquals('Created', created.Status);
        System.assertEquals('82', created.OperatingUnit__c);
        System.assertEquals(repairCenter.Id, created.DestinationLocationId);
        System.assertEquals('LEG-1001', created.LegacyCustomerID__c);

        Id returnOrderId = created.Id;
        List<ReturnOrderLineItem> lineItems = Database.query(
            'SELECT Id, AssetId, Department__c, QuantityReturned, Status__c, Disinfected__c, ' +
            'Contact__c, CustomerPO__c, IsLoanerAsset__c, LoanerRequested__c, ReportedProblem__c, ' +
            'CustomerReference__c, ProductLine__c, LineType__c, ' +
            getEstimateRequiredFieldApiName() +
            ' FROM ReturnOrderLineItem WHERE ReturnOrderId = :returnOrderId'
        );
        System.assertEquals(1, lineItems.size());
        System.assertEquals('Pre-Approved', readEstimateRequiredValue(returnOrderId));
        System.assertEquals('Surgical', lineItems[0].ProductLine__c);
        System.assertEquals('Serialized', lineItems[0].LineType__c);
        System.assertEquals(asset.Id, lineItems[0].AssetId);
        System.assertEquals(testDepartment.Id, lineItems[0].Department__c);
        System.assertEquals('Created', lineItems[0].Status__c);
        System.assertEquals(1, lineItems[0].QuantityReturned);
        System.assertEquals(getDisinfectedYesValueForTest(), lineItems[0].Disinfected__c);
        System.assertEquals(contact.Id, lineItems[0].Contact__c);
        System.assertEquals('PO-123', lineItems[0].CustomerPO__c);
        System.assertEquals(true, lineItems[0].IsLoanerAsset__c);
        System.assertEquals(false, lineItems[0].LoanerRequested__c);
        System.assertEquals('Unit not powering on', lineItems[0].ReportedProblem__c);
        System.assertEquals('REF-456', lineItems[0].CustomerReference__c);
    }

    @isTest
    static void testGetInitialContextFromWorkOrder() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Asset headerAsset = [SELECT Id, Product2Id, Department__c FROM Asset LIMIT 1];
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            ContactId = contact.Id,
            AssetId = headerAsset.Id,
            Status = 'New'
        );
        insert workOrder;

        Asset lineAsset = new Asset(
            Name = 'WO Line Asset',
            AccountId = account.Id,
            SerialNumber = 'SN-WO-002',
            Product2Id = headerAsset.Product2Id,
            Department__c = headerAsset.Department__c
        );
        insert lineAsset;

        insert new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            AssetId = lineAsset.Id
        );

        Test.startTest();
        CreateReturnOrderController.InitContext ctx =
            CreateReturnOrderController.getInitialContext(workOrder.Id, 'WorkOrder', null);
        Test.stopTest();

        System.assertEquals(account.Id, ctx.accountId);
        System.assertEquals(true, ctx.lockAccount);
        System.assertEquals(contact.Id, ctx.contactId);
        System.assertNotEquals(null, ctx.contactName);
        System.assertEquals(workOrder.Id, ctx.workOrderId);
        System.assertEquals(true, ctx.lockWorkOrder);
        System.assertNotEquals(null, ctx.workOrderLabel);
        System.assertEquals(false, ctx.lockCase);
        System.assertEquals(2, ctx.assetIds.size());
        System.assertEquals(String.valueOf(headerAsset.Id), ctx.assetIds[0]);
        System.assertEquals(String.valueOf(lineAsset.Id), ctx.assetIds[1]);
    }

    /**
     * @description GW-6017 - A CRSS work order returns only lines marked Send to Repair Center,
     *              and the mark is cleared once the asset is placed on a return order.
     */
    @isTest
    static void testCrssWorkOrderReturnsMarkedLinesOnly() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Asset headerAsset = [SELECT Id, Product2Id, Department__c FROM Asset LIMIT 1];
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            AssetId = headerAsset.Id,
            Status = 'New',
            RecordTypeId = Schema.SObjectType.WorkOrder
                .getRecordTypeInfosByDeveloperName()
                .get('CRSSFieldRepair')
                .getRecordTypeId()
        );
        insert workOrder;

        Asset markedAsset = new Asset(
            Name = 'CRSS Marked Asset',
            AccountId = account.Id,
            SerialNumber = 'SN-CRSS-001',
            Product2Id = headerAsset.Product2Id,
            Department__c = headerAsset.Department__c
        );
        Asset unmarkedAsset = new Asset(
            Name = 'CRSS Unmarked Asset',
            AccountId = account.Id,
            SerialNumber = 'SN-CRSS-002',
            Product2Id = headerAsset.Product2Id,
            Department__c = headerAsset.Department__c
        );
        insert new List<Asset>{ markedAsset, unmarkedAsset };

        Id productServicedRecordTypeId = Schema.SObjectType.WorkOrderLineItem
            .getRecordTypeInfosByDeveloperName()
            .get('ProductServiced')
            .getRecordTypeId();
        WorkOrderLineItem markedLine = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            RecordTypeId = productServicedRecordTypeId,
            AssetId = markedAsset.Id,
            LineType__c = 'Product Serviced',
            SendToRepairCenter__c = true,
            Department__c = headerAsset.Department__c,
            ReportedProblem__c = 'Broken hinge'
        );
        WorkOrderLineItem unmarkedLine = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            RecordTypeId = productServicedRecordTypeId,
            AssetId = unmarkedAsset.Id,
            LineType__c = 'Product Serviced'
        );
        insert new List<WorkOrderLineItem>{ markedLine, unmarkedLine };

        Test.startTest();
        CreateReturnOrderController.InitContext ctx =
            CreateReturnOrderController.getInitialContext(workOrder.Id, 'WorkOrder', null);
        CreateReturnOrderController.clearCrssSendToRepairCenterByAsset(
            JSON.serialize(new Map<String, Object>{ 'workOrderId' => workOrder.Id }),
            new List<Object>{ new Map<String, Object>{ 'assetId' => String.valueOf(markedAsset.Id) } }
        );
        Test.stopTest();

        System.assertEquals(1, ctx.assetIds.size(), 'Only the marked line asset should be returned.');
        System.assertEquals(String.valueOf(markedAsset.Id), ctx.assetIds[0]);
        CreateReturnOrderController.AssetLineDefaults defaults = ctx.lineDefaultsByAssetId.get(ctx.assetIds[0]);
        System.assertEquals(headerAsset.Department__c, defaults.departmentId, 'Department should come from the line.');
        System.assertEquals('Broken hinge', defaults.reportedProblem, 'Reported problem should come from the line.');
        System.assertEquals(
            false,
            [SELECT SendToRepairCenter__c FROM WorkOrderLineItem WHERE Id = :markedLine.Id].SendToRepairCenter__c,
            'Send to Repair Center should be cleared after the return order is created.'
        );
    }

    @isTest
    static void testCreateReturnOrder_fromWorkOrderHeader() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            ContactId = contact.Id,
            Status = 'New'
        );
        insert workOrder;

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82',
            'workOrderId' => workOrder.Id
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'serialized' => true,
                'serialNumber' => 'SN-001',
                'assetId' => asset.Id,
                'product2Id' => asset.Product2Id,
                'model' => 'Test Model',
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'estimateRequired' => 'Pre-Approved',
                'disinfected' => getDisinfectedYesValueForTest(),
                'reportedProblem' => 'Issue noted',
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        CreateReturnOrderController.CreateResult result = CreateReturnOrderController.createReturnOrder(
            JSON.serialize(header),
            JSON.serialize(lines)
        );
        Test.stopTest();

        ReturnOrder created = [
            SELECT WorkOrder__c, AccountId
            FROM ReturnOrder
            WHERE Id = :result.returnOrderId
            LIMIT 1
        ];
        System.assertEquals(workOrder.Id, created.WorkOrder__c);
        System.assertEquals(account.Id, created.AccountId);

        ReturnOrderLineItem lineItem = [
            SELECT Contact__c, SerialNumber__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :result.returnOrderId
            LIMIT 1
        ];
        System.assertEquals(contact.Id, lineItem.Contact__c);
        System.assertEquals('SN-001', lineItem.SerialNumber__c);
    }

    @isTest
    static void testCreateReturnOrder_serialNumberWithoutAsset() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'serialized' => true,
                'serialNumber' => 'manual-sn-999',
                'product2Id' => product.Id,
                'model' => 'Manual Model abc',
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'estimateRequired' => 'Pre-Approved',
                'disinfected' => getDisinfectedYesValueForTest(),
                'reportedProblem' => 'Manual serial entry',
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        CreateReturnOrderController.CreateResult result = CreateReturnOrderController.createReturnOrder(
            JSON.serialize(header),
            JSON.serialize(lines)
        );
        Test.stopTest();

        ReturnOrderLineItem lineItem = [
            SELECT AssetId, Model__c, SerialNumber__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :result.returnOrderId
            LIMIT 1
        ];
        System.assertEquals(null, lineItem.AssetId);
        System.assertEquals('MANUAL-SN-999', lineItem.SerialNumber__c);
        System.Assert.areEqual('MANUAL MODEL ABC', lineItem.Model__c);
    }

    @isTest
    static void testCreateReturnOrder_linksLineItemAttachments() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Schema.Location repairCenter = [SELECT Id FROM Location LIMIT 1];

        ContentVersion contentVersion = new ContentVersion(
            Title = 'Line Attachment',
            PathOnClient = 'line-photo.png',
            VersionData = Blob.valueOf('test-image-bytes'),
            IsMajorVersion = true
        );
        insert contentVersion;
        contentVersion = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersion.Id
            LIMIT 1
        ];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82',
            'repairCenterId' => repairCenter.Id
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'serialized' => true,
                'serialNumber' => 'SN-ATTACH',
                'assetId' => asset.Id,
                'product2Id' => asset.Product2Id,
                'model' => 'Attachment Model',
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'estimateRequired' => 'Pre-Approved',
                'disinfected' => getDisinfectedYesValueForTest(),
                'reportedProblem' => 'Visible damage',
                'quantityReturned' => 1,
                'contentDocumentIds' => new List<String>{
                    String.valueOf(contentVersion.ContentDocumentId)
                }
            }
        };

        Test.startTest();
        CreateReturnOrderController.CreateResult result = CreateReturnOrderController.createReturnOrder(
            JSON.serialize(header),
            JSON.serialize(lines)
        );
        Test.stopTest();

        ReturnOrderLineItem lineItem = [
            SELECT Id
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :result.returnOrderId
            LIMIT 1
        ];

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :lineItem.Id
        ];
        System.assertEquals(1, links.size());
        System.assertEquals(contentVersion.ContentDocumentId, links[0].ContentDocumentId);
    }

    @isTest
    static void testGetInitialContextFromCaseWithoutSubject() {
        Case testCase = [SELECT Id, CaseNumber FROM Case LIMIT 1];
        testCase.Subject = '';
        update testCase;

        Test.startTest();
        CreateReturnOrderController.InitContext ctx =
            CreateReturnOrderController.getInitialContext(testCase.Id, 'Case', null);
        Test.stopTest();

        System.assertEquals(testCase.CaseNumber, ctx.caseLabel);
    }

    @isTest
    static void testGetInitialContextFromInvalidRecordIdOnly() {
        Test.startTest();
        CreateReturnOrderController.InitContext ctx =
            CreateReturnOrderController.getInitialContext('not-a-valid-id', null, null);
        Test.stopTest();

        System.assertEquals(null, ctx.accountId);
        System.assertEquals(0, ctx.assetIds.size());
    }

    @isTest
    static void testGetInitialContextFromAssetIdsWithoutObjectName() {
        Asset asset = [SELECT Id FROM Asset LIMIT 1];

        Test.startTest();
        CreateReturnOrderController.InitContext ctx = CreateReturnOrderController.getInitialContext(
            null,
            null,
            new List<String>{ 'not-a-valid-id', asset.Id }
        );
        Test.stopTest();

        System.assertEquals(1, ctx.assetIds.size());
        System.assertEquals(asset.Id, ctx.assetIds[0]);
    }

    @isTest
    static void testGetInitialContextSkipsInvalidAssetIds() {
        Asset asset = [SELECT Id FROM Asset LIMIT 1];

        Test.startTest();
        CreateReturnOrderController.InitContext ctx = CreateReturnOrderController.getInitialContext(
            null,
            'Asset',
            new List<String>{ '', 'bad-id', asset.Id }
        );
        Test.stopTest();

        System.assertEquals(1, ctx.assetIds.size());
    }

    @isTest
    static void testGetInitialContextHandlesQueryFailure() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Boolean thrown = false;

        Test.startTest();
        try {
            CreateReturnOrderController.getInitialContext(account.Id, 'Case', null);
        } catch (Exception e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'Expected failure when Case record does not exist for Account Id.');
    }

    @isTest
    static void testGetAccountDetails_null_returnsNull() {
        Test.startTest();
        Account result = CreateReturnOrderController.getAccountDetails(null);
        Test.stopTest();

        System.assertEquals(null, result);
    }

    @isTest
    static void testGetContactsCasesAssets_nullAccount_returnsEmpty() {
        Test.startTest();
        List<Contact> contacts = CreateReturnOrderController.getContactsForAccount(null);
        List<Case> cases = CreateReturnOrderController.getOpenCasesForAccount(null);
        List<CreateReturnOrderController.AssetLineData> assets =
            CreateReturnOrderController.getAssetsForAccount(null);
        List<CreateReturnOrderController.AssetLineData> assetsByIds =
            CreateReturnOrderController.getAssetsByIds(null);
        Test.stopTest();

        System.assertEquals(0, contacts.size());
        System.assertEquals(0, cases.size());
        System.assertEquals(0, assets.size());
        System.assertEquals(0, assetsByIds.size());
    }

    @isTest
    static void testGetAssetsByIds_preservesInputOrder() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Product2 testProduct = [SELECT Id FROM Product2 LIMIT 1];

        Asset firstAsset = new Asset(
            Name = 'First Ordered Asset',
            AccountId = account.Id,
            SerialNumber = 'ORDER-001',
            Product2Id = testProduct.Id,
            Department__c = testDepartment.Id
        );
        Asset secondAsset = new Asset(
            Name = 'Second Ordered Asset',
            AccountId = account.Id,
            SerialNumber = 'ORDER-002',
            Product2Id = testProduct.Id,
            Department__c = testDepartment.Id
        );
        insert new List<Asset>{ firstAsset, secondAsset };

        Test.startTest();
        List<CreateReturnOrderController.AssetLineData> selectedAssets =
            CreateReturnOrderController.getAssetsByIds(
                new List<String>{ secondAsset.Id, firstAsset.Id }
            );
        Test.stopTest();

        System.assertEquals(2, selectedAssets.size());
        System.assertEquals(secondAsset.Id, selectedAssets[0].id);
        System.assertEquals(firstAsset.Id, selectedAssets[1].id);
    }

    @isTest
    static void testGetAssetsForAccountAndByIds() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Asset asset = [SELECT Id FROM Asset LIMIT 1];

        Test.startTest();
        List<CreateReturnOrderController.AssetLineData> accountAssets =
            CreateReturnOrderController.getAssetsForAccount(account.Id);
        List<CreateReturnOrderController.AssetLineData> selectedAssets =
            CreateReturnOrderController.getAssetsByIds(new List<String>{ asset.Id });
        List<CreateReturnOrderController.AssetLineData> emptySelection =
            CreateReturnOrderController.getAssetsByIds(new List<String>{ 'invalid-id' });
        Test.stopTest();

        System.assertEquals(1, accountAssets.size());
        System.assertEquals(asset.Id, accountAssets[0].id);
        System.assertEquals(1, selectedAssets.size());
        System.assertEquals(asset.Id, selectedAssets[0].id);
        System.assertEquals(0, emptySelection.size());

        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        System.assertEquals(testDepartment.Id, selectedAssets[0].departmentId);
    }

    @isTest
    static void testFindAssetsBySerial_blankSerial_returnsEmpty() {
        Test.startTest();
        List<CreateReturnOrderController.ScanSerialAssetResult> results =
            CreateReturnOrderController.findAssetsBySerial(null);
        Test.stopTest();

        System.assertEquals(0, results.size());
    }

    @isTest
    static void testFindAssetsBySerial_returnsMatchingAssets() {
        Asset asset = [SELECT Id, SerialNumber, AccountId FROM Asset LIMIT 1];
        Account account = [SELECT Id, Name FROM Account WHERE Id = :asset.AccountId LIMIT 1];

        Test.startTest();
        List<CreateReturnOrderController.ScanSerialAssetResult> results =
            CreateReturnOrderController.findAssetsBySerial(asset.SerialNumber);
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(asset.Id, results[0].id);
        System.assertEquals(account.Id, results[0].accountId);
        System.assertEquals(account.Name, results[0].accountName);
    }

    @isTest
    static void testValidateAccountForReturnOrder_readyWhenOperatingUnitPresent() {
        Account account = [SELECT Id, Name FROM Account LIMIT 1];

        Test.startTest();
        CreateReturnOrderController.AccountReadinessResult result =
            CreateReturnOrderController.validateAccountForReturnOrder(account.Id);
        Test.stopTest();

        System.assertEquals(true, result.isReady);
        System.assertEquals(0, result.missingFields.size());
        System.assertEquals(account.Id, result.accountId);
        System.assertEquals('82', result.operatingUnit);
    }

    @isTest
    static void testValidateAccountForReturnOrder_missingOperatingUnit() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        account.OrgIDs__c = null;
        update account;

        Test.startTest();
        CreateReturnOrderController.AccountReadinessResult result =
            CreateReturnOrderController.validateAccountForReturnOrder(account.Id);
        Test.stopTest();

        System.assertEquals(false, result.isReady);
        System.assertEquals(1, result.missingFields.size());
        System.assertEquals('Operating Unit', result.missingFields[0]);
    }

    @isTest
    static void testValidateAccountForReturnOrder_nullAccount() {
        Test.startTest();
        CreateReturnOrderController.AccountReadinessResult result =
            CreateReturnOrderController.validateAccountForReturnOrder(null);
        Test.stopTest();

        System.assertEquals(false, result.isReady);
        System.assertEquals(1, result.missingFields.size());
        System.assertEquals('Account', result.missingFields[0]);
    }

    @isTest
    static void testGetDepartmentsForAccount_returnsAccountDepartments() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Department__c testDepartment = [SELECT Id, Name FROM Department__c LIMIT 1];

        Test.startTest();
        List<CreateReturnOrderController.PicklistOption> departments =
            CreateReturnOrderController.getDepartmentsForAccount(account.Id, null);
        Test.stopTest();

        System.assertEquals(1, departments.size());
        System.assertEquals(testDepartment.Id, departments[0].value);
        System.assertEquals(testDepartment.Name, departments[0].label);
    }

    @isTest
    static void testGetDepartmentsForAccount_includesAdditionalDepartment() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Department__c accountDepartment = [SELECT Id, Name FROM Department__c LIMIT 1];
        Department__c otherDepartment = new Department__c(Name = 'Non-Account Department');
        insert otherDepartment;

        Test.startTest();
        List<CreateReturnOrderController.PicklistOption> departments =
            CreateReturnOrderController.getDepartmentsForAccount(
                account.Id,
                new List<String>{ otherDepartment.Id }
            );
        Test.stopTest();

        System.assertEquals(2, departments.size());

        Set<Id> departmentIds = new Set<Id>();
        for (CreateReturnOrderController.PicklistOption option : departments) {
            departmentIds.add(option.value);
        }
        System.assert(departmentIds.contains(accountDepartment.Id));
        System.assert(departmentIds.contains(otherDepartment.Id));
    }

    @isTest
    static void testGetDepartmentsForAccount_nullAccount() {
        Test.startTest();
        List<CreateReturnOrderController.PicklistOption> departments =
            CreateReturnOrderController.getDepartmentsForAccount(null, null);
        Test.stopTest();

        System.assertEquals(0, departments.size());
    }

    @isTest
    static void testCreateReturnOrder_headerOnlyNoLines() {
        Account account = [SELECT Id FROM Account LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82',
            'creationSource' => 'Salesforce'
        };

        Test.startTest();
        CreateReturnOrderController.CreateResult result = CreateReturnOrderController.createReturnOrder(
            JSON.serialize(header),
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, result.returnOrderId);
        System.assertEquals(
            0,
            [SELECT COUNT() FROM ReturnOrderLineItem WHERE ReturnOrderId = :result.returnOrderId]
        );
    }

    @isTest
    static void testCreateReturnOrder_lineDefaults() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        contact.Email = 'line.defaults@example.com';
        update contact;
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'assetId' => asset.Id,
                'product2Id' => asset.Product2Id,
                'model' => 'Default Model',
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'estimateContactId' => String.valueOf(contact.Id),
                'estimateRequired' => 'Estimate Required',
                'disinfected' => getDisinfectedNoValueForTest(),
                'reportedProblem' => 'Needs repair',
                'loanerRequested' => true
            }
        };

        Test.startTest();
        CreateReturnOrderController.CreateResult result = CreateReturnOrderController.createReturnOrder(
            JSON.serialize(header),
            JSON.serialize(lines)
        );
        Test.stopTest();

        Id returnOrderId = result.returnOrderId;
        ReturnOrderLineItem lineItem = Database.query(
            'SELECT Disinfected__c, LoanerRequested__c, IsLoanerAsset__c, Status__c, QuantityReturned, ' +
            getEstimateRequiredFieldApiName() +
            ' FROM ReturnOrderLineItem WHERE ReturnOrderId = :returnOrderId LIMIT 1'
        );
        System.assertEquals('Estimate Required', readEstimateRequiredValue(returnOrderId));
        System.assertEquals(getDisinfectedNoValueForTest(), lineItem.Disinfected__c);
        System.assertEquals(true, lineItem.LoanerRequested__c);
        System.assertEquals(false, lineItem.IsLoanerAsset__c);
        System.assertEquals('Created', lineItem.Status__c);
        System.assertEquals(1, lineItem.QuantityReturned);
    }

    @isTest
    static void testCreateReturnOrder_quantityReturned() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'assetId' => asset.Id,
                'product2Id' => asset.Product2Id,
                'model' => 'Qty Model',
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'estimateRequired' => 'Pre-Approved',
                'disinfected' => getDisinfectedYesValueForTest(),
                'serialNumber' => 'SN-QTY',
                'reportedProblem' => 'Broken display',
                'quantityReturned' => 3
            }
        };

        Test.startTest();
        CreateReturnOrderController.CreateResult result = CreateReturnOrderController.createReturnOrder(
            JSON.serialize(header),
            JSON.serialize(lines)
        );
        Test.stopTest();

        ReturnOrderLineItem lineItem = [
            SELECT QuantityReturned
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :result.returnOrderId
            LIMIT 1
        ];
        System.assertEquals(1, lineItem.QuantityReturned);
    }

    @isTest
    static void testCreateReturnOrder_missingModel_throws() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'serialized' => true,
                'product2Id' => asset.Product2Id,
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'estimateRequired' => 'Pre-Approved',
                'reportedProblem' => 'Issue noted',
                'quantityReturned' => 1
            }
        };

        Boolean thrown = false;

        Test.startTest();
        try {
            CreateReturnOrderController.createReturnOrder(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        } catch (Exception e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'Expected validation error when Model is missing.');
    }

    @isTest
    static void testCreateReturnOrder_missingReportedProblem_throws() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'serialized' => true,
                'product2Id' => asset.Product2Id,
                'model' => 'Test Model',
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'estimateRequired' => 'Pre-Approved',
                'quantityReturned' => 1
            }
        };

        Boolean thrown = false;

        Test.startTest();
        try {
            CreateReturnOrderController.createReturnOrder(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        } catch (Exception e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(
            true,
            thrown,
            'Expected validation error when Reported Problem is missing.'
        );
    }

    @isTest
    static void testCreateReturnOrder_missingAccount_throws() {
        Map<String, Object> header = new Map<String, Object>{
            'operatingUnit' => '82'
        };

        Boolean thrown = false;

        Test.startTest();
        try {
            CreateReturnOrderController.createReturnOrder(JSON.serialize(header), '[]');
        } catch (Exception e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'Expected validation error when Account is missing.');
    }

    @isTest
    static void testCreateReturnOrder_missingOperatingUnit_throws() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        account.OrgIDs__c = null;
        update account;
        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id
        };

        Boolean thrown = false;

        Test.startTest();
        try {
            CreateReturnOrderController.createReturnOrder(JSON.serialize(header), '[]');
        } catch (Exception e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'Expected validation error when Operating Unit is missing.');
    }

    @isTest
    static void testCreateReturnOrder_mapsOperatingUnitFromAccount() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Schema.Location repairCenter = [SELECT Id FROM Location LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'creationSource' => 'Salesforce',
            'salesRepId' => UserInfo.getUserId(),
            'repairCenterId' => repairCenter.Id
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'assetId' => asset.Id,
                'product2Id' => asset.Product2Id,
                'model' => 'Test Model',
                'departmentId' => testDepartment.Id,
                'disinfected' => getDisinfectedYesValueForTest(),
                'contactId' => contact.Id,
                'estimateRequired' => 'Pre-Approved',
                'productLine' => 'Surgical',
                'reportedProblem' => 'Unit not powering on',
                'status' => 'Created',
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        CreateReturnOrderController.CreateResult result = CreateReturnOrderController.createReturnOrder(
            JSON.serialize(header),
            JSON.serialize(lines)
        );
        Test.stopTest();

        ReturnOrder created = [
            SELECT OperatingUnit__c
            FROM ReturnOrder
            WHERE Id = :result.returnOrderId
            LIMIT 1
        ];
        System.assertEquals('82', created.OperatingUnit__c);
    }

    @isTest
    static void testGetAccountDetails_returnsOperatingUnit() {
        Account account = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Account result = CreateReturnOrderController.getAccountDetails(account.Id);
        Test.stopTest();

        System.assertEquals('82', result.OrgIDs__c);
    }

    @isTest
    static void testCreateAccountContact_success() {
        Account account = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        CreateReturnOrderController.CreateContactResult result =
            CreateReturnOrderController.createAccountContact(
                account.Id,
                'Jane',
                'Doe',
                'jane.doe@example.com',
                '555-0100',
                'Clinical Engineer',
                false
            );
        Test.stopTest();

        System.assertNotEquals(null, result.contactId);
        System.assertEquals('Jane Doe', result.contactName);

        Contact created = [
            SELECT AccountId, FirstName, LastName, Email, Phone, Title
            FROM Contact
            WHERE Id = :result.contactId
            LIMIT 1
        ];
        System.assertEquals('Jane', created.FirstName);
        System.assertEquals('Doe', created.LastName);
        System.assertEquals('jane.doe@example.com', created.Email);
        System.assertEquals('555-0100', created.Phone);
        System.assertEquals('Clinical Engineer', created.Title);

        System.assertEquals(account.Id, created.AccountId);

        List<Contact> eligibleContacts = CreateReturnOrderController.getContactsForAccount(
            account.Id
        );
        Set<Id> eligibleIds = new Set<Id>();
        for (Contact eligibleContact : eligibleContacts) {
            eligibleIds.add(eligibleContact.Id);
        }
        System.assert(
            eligibleIds.contains(result.contactId),
            'Created contact should appear in eligible contact list.'
        );
    }

    @isTest
    static void testCreateAccountContact_requiredFields() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Boolean thrown = false;

        Test.startTest();
        try {
            CreateReturnOrderController.createAccountContact(
                account.Id,
                '',
                'Doe',
                null,
                null,
                null,
                false
            );
        } catch (Exception e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'Expected validation error when First Name is missing.');
    }

    @isTest
    static void testCreateAccountContact_missingAccount() {
        Boolean thrown = false;

        Test.startTest();
        try {
            CreateReturnOrderController.createAccountContact(
                null,
                'Jane',
                'Doe',
                null,
                null,
                null,
                false
            );
        } catch (Exception e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'Expected validation error when Account is missing.');
    }

    @isTest
    static void testCreateReturnOrder_missingEstReq_throws() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'serialized' => true,
                'product2Id' => asset.Product2Id,
                'model' => 'Test Model',
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'reportedProblem' => 'Issue noted',
                'quantityReturned' => 1
            }
        };

        Boolean thrown = false;

        Test.startTest();
        try {
            CreateReturnOrderController.createReturnOrder(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        } catch (Exception e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'Expected validation error when Est. Required is missing.');
    }

    @isTest
    static void testCreateReturnOrder_instruments_missingEstReq_throws() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineType' => 'instruments',
                'serialized' => false,
                'product2Id' => asset.Product2Id,
                'productLine' => 'INSTRUMENT',
                'itemDescription' => 'Forceps',
                'disinfected' => getDisinfectedYesValueForTest(),
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'reportedProblem' => 'Worn component',
                'quantityReturned' => 1
            }
        };

        Boolean thrown = false;

        Test.startTest();
        try {
            CreateReturnOrderController.createReturnOrder(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        } catch (Exception e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(
            true,
            thrown,
            'Expected validation error when Est. Required is missing on instrument lines.'
        );
    }

    @isTest
    static void testGetInitialContext_includesEstReqPicklist() {
        Account account = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        CreateReturnOrderController.InitContext ctx =
            CreateReturnOrderController.getInitialContext(account.Id, 'Account', null);
        Test.stopTest();

        System.assertNotEquals(null, ctx.estimateRequiredOptions);
        System.assert(
            ctx.estimateRequiredOptions.size() > 0,
            'Estimate Required picklist options should be loaded.'
        );
    }

    @isTest
    static void testCreateAccountContact_duplicateName() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Integer contactCountBefore = [
            SELECT COUNT()
            FROM Contact
            WHERE AccountId = :account.Id
        ];

        Boolean thrown = false;

        Test.startTest();
        try {
            CreateReturnOrderController.createAccountContact(
                account.Id,
                'test',
                'contact',
                null,
                null,
                null,
                false
            );
        } catch (Exception e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'Expected duplicate contact validation error.');
        System.assertEquals(
            contactCountBefore,
            [SELECT COUNT() FROM Contact WHERE AccountId = :account.Id],
            'Duplicate contact should not have been inserted.'
        );
    }

    @isTest
    static void testValidateLineRoutingMatches_blocksUnmatchedLine() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'serialized' => false,
                'product2Id' => asset.Product2Id,
                'productLine' => 'Unknown',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        CreateReturnOrderController.LineRoutingValidation validation =
            CreateReturnOrderController.validateLineRoutingMatches(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        Test.stopTest();

        System.assertEquals(false, validation.isValid);
        System.assertEquals(1, validation.messages.size());
        System.assert(validation.messages[0].contains('Line 1'));
        System.assert(validation.messages[0].contains('routing rule'));
    }

    @isTest
    static void testValidateLineRoutingMatches_passesMatchedLine() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Schema.Location serialRepairCenter = new Schema.Location(
            Name = 'Validation Repair Center',
            LocationType = 'Repair Center'
        );
        insert serialRepairCenter;

        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'Surgical',
            RepairCenter__c = serialRepairCenter.Id
        );

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'serialized' => true,
                'serialNumber' => 'SN-VALID',
                'product2Id' => asset.Product2Id,
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        CreateReturnOrderController.LineRoutingValidation validation =
            CreateReturnOrderController.validateLineRoutingMatches(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        Test.stopTest();

        System.assertEquals(true, validation.isValid);
        System.assertEquals(0, validation.messages.size());
    }

    @isTest
    static void testBuildReturnOrderPlan_splitsSterilizedNoLines() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Schema.Location serialRepairCenter = new Schema.Location(
            Name = 'Non Steril Repair Center',
            LocationType = 'Repair Center'
        );
        insert serialRepairCenter;

        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'Surgical',
            RepairCenter__c = serialRepairCenter.Id
        );

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineKey' => 'line-yes',
                'serialized' => true,
                'serialNumber' => 'SN-YES',
                'product2Id' => asset.Product2Id,
                'model' => 'Model Yes',
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'estimateRequired' => 'Pre-Approved',
                'disinfected' => getDisinfectedYesValueForTest(),
                'quantityReturned' => 1,
                'reportedProblem' => 'Issue Yes'
            },
            new Map<String, Object>{
                'lineKey' => 'line-no-1',
                'serialized' => true,
                'serialNumber' => 'SN-NO-1',
                'product2Id' => asset.Product2Id,
                'model' => 'Model No 1',
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'estimateRequired' => 'Pre-Approved',
                'disinfected' => getDisinfectedNoValueForTest(),
                'quantityReturned' => 1,
                'reportedProblem' => 'Issue No 1'
            },
            new Map<String, Object>{
                'lineKey' => 'line-no-2',
                'serialized' => true,
                'serialNumber' => 'SN-NO-2',
                'product2Id' => asset.Product2Id,
                'model' => 'Model No 2',
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'estimateRequired' => 'Pre-Approved',
                'disinfected' => getDisinfectedNoValueForTest(),
                'quantityReturned' => 1,
                'reportedProblem' => 'Issue No 2'
            }
        };

        Test.startTest();
        List<CreateReturnOrderController.ProposedReturnOrderGroup> groups =
            CreateReturnOrderController.buildReturnOrderPlan(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        Test.stopTest();

        System.assertEquals(2, groups.size(), 'Expected sterilized Yes and batched No groups.');

        Integer totalLines = 0;
        Boolean foundYesGroup = false;
        Boolean foundNoBatchGroup = false;

        for (CreateReturnOrderController.ProposedReturnOrderGroup proposedGroup : groups) {
            totalLines += proposedGroup.lineCount;
            if (proposedGroup.groupKey ==
                groupKeyFor('Serialized', String.valueOf(serialRepairCenter.Id))) {
                foundYesGroup = true;
                System.assertEquals(1, proposedGroup.lineCount);
                System.assertEquals('Serialized', proposedGroup.returnOrderType);
            }
            if (proposedGroup.groupKey ==
                groupKeyFor(
                    'Serialized',
                    String.valueOf(serialRepairCenter.Id) + '|NOSTERIL'
                )) {
                foundNoBatchGroup = true;
                System.assertEquals(2, proposedGroup.lineCount);
            }
        }

        System.assertEquals(3, totalLines);
        System.assertEquals(true, foundYesGroup);
        System.assertEquals(true, foundNoBatchGroup);
    }

    @isTest
    static void testBuildReturnOrderPlan_splitsSingleSterilizedNoLine() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Schema.Location serialRepairCenter = new Schema.Location(
            Name = 'Single Non Steril Repair Center',
            LocationType = 'Repair Center'
        );
        insert serialRepairCenter;

        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'Surgical',
            RepairCenter__c = serialRepairCenter.Id
        );

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineKey' => 'line-no-only',
                'serialized' => true,
                'serialNumber' => 'SN-NO-ONLY',
                'product2Id' => asset.Product2Id,
                'model' => 'Model No Only',
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'estimateRequired' => 'Pre-Approved',
                'disinfected' => getDisinfectedNoValueForTest(),
                'quantityReturned' => 1,
                'reportedProblem' => 'Issue No Only'
            }
        };

        Test.startTest();
        List<CreateReturnOrderController.ProposedReturnOrderGroup> groups =
            CreateReturnOrderController.buildReturnOrderPlan(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        Test.stopTest();

        System.assertEquals(1, groups.size());
        System.assertEquals(1, groups[0].lineCount);
        System.assert(groups[0].groupKey.contains('|NOSTERIL|line-no-only'));
    }

    @isTest
    static void testBuildReturnOrderPlan_splitsModRequestLine() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Account shipTo = insertRoutingShipTo(
            account.Id,
            'Mod Request Ship-To',
            'TEST-ORACLE-MOD-SHIPTO',
            'OH'
        );

        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Schema.Location repairCenter = new Schema.Location(
            Name = 'Mod Request Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'Surgical',
            ShipState__c = 'OH',
            RepairCenter__c = repairCenter.Id
        );

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineKey' => 'line-standard',
                'serialized' => false,
                'product2Id' => asset.Product2Id,
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'modRequest' => false,
                'shipToAccountId' => String.valueOf(shipTo.Id),
                'quantityReturned' => 1
            },
            new Map<String, Object>{
                'lineKey' => 'line-mod',
                'serialized' => false,
                'product2Id' => asset.Product2Id,
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'modRequest' => true,
                'shipToAccountId' => String.valueOf(shipTo.Id),
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        List<CreateReturnOrderController.ProposedReturnOrderGroup> groups =
            CreateReturnOrderController.buildReturnOrderPlan(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        Test.stopTest();

        System.assertEquals(2, groups.size(), 'Mod Request line should be split into its own RO.');

        Boolean foundStandardGroup = false;
        Boolean foundModRequestGroup = false;

        for (CreateReturnOrderController.ProposedReturnOrderGroup proposedGroup : groups) {
            if (proposedGroup.groupKey ==
                groupKeyFor('Instruments', String.valueOf(repairCenter.Id))) {
                foundStandardGroup = true;
                System.assertEquals(1, proposedGroup.lineCount);
                System.assertEquals('Instruments', proposedGroup.returnOrderType);
            }
            if (proposedGroup.groupKey.contains('|MODREQUEST|line-mod')) {
                foundModRequestGroup = true;
                System.assertEquals(1, proposedGroup.lineCount);
            }
        }

        System.assertEquals(true, foundStandardGroup);
        System.assertEquals(true, foundModRequestGroup);
    }

    @isTest
    static void testBuildReturnOrderPlan_groupsByRoutingRules() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Schema.Location serialRepairCenter = new Schema.Location(
            Name = 'Serial Repair Center',
            LocationType = 'Repair Center'
        );
        insert serialRepairCenter;

        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'Surgical',
            RepairCenter__c = serialRepairCenter.Id
        );

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];

        Product2 unmatchedProduct = new Product2(
            Name = 'Unmatched Instrument Product',
            ProductType__c = 'Service Asset',
            ProductLine__c = 'Unknown',
            IsActive = true
        );
        insert unmatchedProduct;

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineKey' => 'line-1',
                'serialized' => true,
                'serialNumber' => 'SN-100',
                'product2Id' => asset.Product2Id,
                'model' => 'Model A',
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'estimateRequired' => 'Pre-Approved',
                'quantityReturned' => 1,
                'reportedProblem' => 'Issue A'
            },
            new Map<String, Object>{
                'lineKey' => 'line-2',
                'serialized' => false,
                'product2Id' => unmatchedProduct.Id,
                'model' => 'Model B',
                'productLine' => 'Unknown',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        List<CreateReturnOrderController.ProposedReturnOrderGroup> groups =
            CreateReturnOrderController.buildReturnOrderPlan(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        Test.stopTest();

        System.assertEquals(2, groups.size(), 'Expected two return order groups.');

        Map<String, CreateReturnOrderController.ProposedReturnOrderGroup> groupsByKey =
            new Map<String, CreateReturnOrderController.ProposedReturnOrderGroup>();
        for (CreateReturnOrderController.ProposedReturnOrderGroup proposedGroup : groups) {
            groupsByKey.put(proposedGroup.groupKey, proposedGroup);
        }

        CreateReturnOrderController.ProposedReturnOrderGroup serialGroup =
            groupsByKey.get(groupKeyFor('Serialized', String.valueOf(serialRepairCenter.Id)));
        System.assertNotEquals(null, serialGroup);
        System.assertEquals(false, serialGroup.requiresRepairCenterSelection);
        System.assertEquals(1, serialGroup.lineCount);
        System.assertEquals('Serialized', serialGroup.returnOrderType);

        CreateReturnOrderController.ProposedReturnOrderGroup unassignedGroup =
            groupsByKey.get(groupKeyFor('Instruments', 'UNASSIGNED'));
        System.assertNotEquals(null, unassignedGroup);
        System.assertEquals(true, unassignedGroup.requiresRepairCenterSelection);
        System.assertEquals(1, unassignedGroup.lineCount);
        System.assertEquals('Instruments', unassignedGroup.returnOrderType);
    }

    @isTest
    static void testBuildReturnOrderPlan_splitsMixedLineTypesAtSameRepairCenter() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Schema.Location repairCenter = new Schema.Location(
            Name = 'Mixed Type Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'Surgical',
            RepairCenter__c = repairCenter.Id
        );

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineKey' => 'line-serialized',
                'lineType' => 'serialized',
                'serialized' => true,
                'serialNumber' => 'SN-MIX-1',
                'product2Id' => asset.Product2Id,
                'model' => 'Model A',
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'estimateRequired' => 'Pre-Approved',
                'disinfected' => getDisinfectedYesValueForTest(),
                'quantityReturned' => 1,
                'reportedProblem' => 'Issue A'
            },
            new Map<String, Object>{
                'lineKey' => 'line-instruments',
                'lineType' => 'instruments',
                'serialized' => false,
                'product2Id' => asset.Product2Id,
                'productLine' => 'INSTRUMENT',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'disinfected' => getDisinfectedYesValueForTest(),
                'reportedProblem' => 'Issue B',
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        List<CreateReturnOrderController.ProposedReturnOrderGroup> groups =
            CreateReturnOrderController.buildReturnOrderPlan(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        Test.stopTest();

        System.assertEquals(
            2,
            groups.size(),
            'Serialized and Instruments lines should split into separate return orders.'
        );

        Set<String> returnOrderTypes = new Set<String>();
        for (CreateReturnOrderController.ProposedReturnOrderGroup proposedGroup : groups) {
            returnOrderTypes.add(proposedGroup.returnOrderType);
            System.assertEquals(1, proposedGroup.lineCount);
        }
        System.assert(returnOrderTypes.contains('Serialized'));
        System.assert(returnOrderTypes.contains('Instruments'));
    }

    @isTest
    static void testBuildReturnOrderPlan_splitsProductLinesAtSameRepairCenter() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Product2 rigidProduct = new Product2(
            Name = 'Rigid Product',
            ProductType__c = 'Service Asset',
            ProductLine__c = 'RIGID',
            IsActive = true
        );
        Product2 powerProduct = new Product2(
            Name = 'Power Product',
            ProductType__c = 'Service Asset',
            ProductLine__c = 'POWER',
            IsActive = true
        );
        insert new List<Product2>{ rigidProduct, powerProduct };

        Schema.Location repairCenter = new Schema.Location(
            Name = 'Shared Product Line Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        insert new List<RepairCenterRoutingRule__c>{
            new RepairCenterRoutingRule__c(
                OperatingUnit__c = '82',
                ProductLine__c = 'RIGID',
                RepairCenter__c = repairCenter.Id
            ),
            new RepairCenterRoutingRule__c(
                OperatingUnit__c = '82',
                ProductLine__c = 'POWER',
                RepairCenter__c = repairCenter.Id
            )
        };

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };
        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineKey' => 'line-rigid',
                'lineType' => 'serialized',
                'serialized' => true,
                'product2Id' => rigidProduct.Id,
                'productLine' => 'RIGID',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'disinfected' => getDisinfectedYesValueForTest()
            },
            new Map<String, Object>{
                'lineKey' => 'line-power',
                'lineType' => 'serialized',
                'serialized' => true,
                'product2Id' => powerProduct.Id,
                'productLine' => 'POWER',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'disinfected' => getDisinfectedYesValueForTest()
            }
        };

        Test.startTest();
        List<CreateReturnOrderController.ProposedReturnOrderGroup> groups =
            CreateReturnOrderController.buildReturnOrderPlan(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        Test.stopTest();

        System.Assert.areEqual(
            2,
            groups.size(),
            'Different product lines routed to the same center must use separate return orders.'
        );
        for (CreateReturnOrderController.ProposedReturnOrderGroup proposedGroup : groups) {
            System.Assert.areEqual(1, proposedGroup.lineCount);
            System.Assert.areEqual(String.valueOf(repairCenter.Id), proposedGroup.repairCenterId);
        }
    }

    @isTest
    static void testBuildReturnOrderPlan_splitsCustomerPoAtSameRepairCenter() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Product2 product = new Product2(
            Name = 'Other PO Split Product',
            ProductType__c = 'Service Asset',
            ProductLine__c = 'VIDEO',
            IsActive = true
        );
        insert product;

        Schema.Location repairCenter = new Schema.Location(
            Name = 'Shared PO Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'VIDEO',
            RepairCenter__c = repairCenter.Id
        );

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };
        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineKey' => 'po-100-a',
                'lineType' => 'other-non-serialized',
                'serialized' => false,
                'product2Id' => product.Id,
                'productLine' => 'VIDEO',
                'itemType' => 'Cable',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'customerPo' => 'PO-100',
                'disinfected' => getDisinfectedYesValueForTest(),
                'reportedProblem' => 'Cable issue',
                'quantityReturned' => 1
            },
            new Map<String, Object>{
                'lineKey' => 'po-100-b',
                'lineType' => 'other-non-serialized',
                'serialized' => false,
                'product2Id' => product.Id,
                'productLine' => 'VIDEO',
                'itemType' => 'Cable',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'customerPo' => 'po-100',
                'disinfected' => getDisinfectedYesValueForTest(),
                'reportedProblem' => 'Cable issue two',
                'quantityReturned' => 1
            },
            new Map<String, Object>{
                'lineKey' => 'po-200',
                'lineType' => 'other-non-serialized',
                'serialized' => false,
                'product2Id' => product.Id,
                'productLine' => 'VIDEO',
                'itemType' => 'Cable',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'customerPo' => 'PO-200',
                'disinfected' => getDisinfectedYesValueForTest(),
                'reportedProblem' => 'Cable issue three',
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        List<CreateReturnOrderController.ProposedReturnOrderGroup> groups =
            CreateReturnOrderController.buildReturnOrderPlan(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        Test.stopTest();

        System.Assert.areEqual(
            2,
            groups.size(),
            'Different customer PO numbers must use separate return orders.'
        );
        Set<Integer> lineCounts = new Set<Integer>();
        for (CreateReturnOrderController.ProposedReturnOrderGroup proposedGroup : groups) {
            lineCounts.add(proposedGroup.lineCount);
            System.Assert.areEqual(String.valueOf(repairCenter.Id), proposedGroup.repairCenterId);
        }
        System.Assert.areEqual(new Set<Integer>{ 1, 2 }, lineCounts);
    }

    @isTest
    static void testBuildReturnOrderPlan_splitsShipToAtSameRepairCenter() {
        Account account = [SELECT Id FROM Account WHERE Name = 'Return Order Test Account' LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];

        List<Account> shipToAccounts = new List<Account>{
            new Account(
                Name = 'Split Primary Ship-To',
                ParentId = account.Id,
                SourceSystemID__c = 'TEST-ORACLE-SPLIT-SHIPTO-P',
                Type = 'Address',
                ShiptoAddressStatus__c = 'Primary'
            ),
            new Account(
                Name = 'Split Active Ship-To',
                ParentId = account.Id,
                SourceSystemID__c = 'TEST-ORACLE-SPLIT-SHIPTO-A',
                Type = 'Address',
                ShiptoAddressStatus__c = 'Active'
            )
        };
        insert shipToAccounts;

        Schema.Location repairCenter = new Schema.Location(
            Name = 'Shared Ship-To Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'Surgical',
            RepairCenter__c = repairCenter.Id
        );

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };
        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineKey' => 'line-ship-to-1',
                'lineType' => 'serialized',
                'serialized' => true,
                'product2Id' => asset.Product2Id,
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'disinfected' => getDisinfectedYesValueForTest(),
                'shipToAccountId' => String.valueOf(shipToAccounts[0].Id)
            },
            new Map<String, Object>{
                'lineKey' => 'line-ship-to-2',
                'lineType' => 'serialized',
                'serialized' => true,
                'product2Id' => asset.Product2Id,
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'disinfected' => getDisinfectedYesValueForTest(),
                'shipToAccountId' => String.valueOf(shipToAccounts[1].Id)
            }
        };

        Test.startTest();
        List<CreateReturnOrderController.ProposedReturnOrderGroup> groups =
            CreateReturnOrderController.buildReturnOrderPlan(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        Test.stopTest();

        System.Assert.areEqual(
            2,
            groups.size(),
            'Lines with different Ship-To accounts must use separate return orders.'
        );
        for (CreateReturnOrderController.ProposedReturnOrderGroup proposedGroup : groups) {
            System.Assert.areEqual(1, proposedGroup.lineCount);
            System.Assert.areEqual(String.valueOf(repairCenter.Id), proposedGroup.repairCenterId);
        }
    }

    @isTest
    static void testBuildReturnOrderPlan_keepsSharedShipToAndProductLineTogether() {
        Account account = [SELECT Id FROM Account WHERE Name = 'Return Order Test Account' LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];

        Account shipTo = new Account(
            Name = 'Shared Ship-To',
            ParentId = account.Id,
            SourceSystemID__c = 'TEST-ORACLE-SHARED-SHIPTO',
            Type = 'Address',
            ShiptoAddressStatus__c = 'Primary'
        );
        insert shipTo;

        Schema.Location repairCenter = new Schema.Location(
            Name = 'Shared Everything Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'Surgical',
            RepairCenter__c = repairCenter.Id
        );

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };
        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineKey' => 'line-shared-1',
                'lineType' => 'serialized',
                'serialized' => true,
                'product2Id' => asset.Product2Id,
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'disinfected' => getDisinfectedYesValueForTest(),
                'shipToAccountId' => String.valueOf(shipTo.Id)
            },
            new Map<String, Object>{
                'lineKey' => 'line-shared-2',
                'lineType' => 'serialized',
                'serialized' => true,
                'product2Id' => asset.Product2Id,
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'disinfected' => getDisinfectedYesValueForTest(),
                'shipToAccountId' => String.valueOf(shipTo.Id)
            }
        };

        Test.startTest();
        List<CreateReturnOrderController.ProposedReturnOrderGroup> groups =
            CreateReturnOrderController.buildReturnOrderPlan(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        Test.stopTest();

        System.Assert.areEqual(
            1,
            groups.size(),
            'Same Product Line and Ship-To at one repair center should stay on one return order.'
        );
        System.Assert.areEqual(2, groups[0].lineCount);
    }

    @isTest
    static void testBuildReturnOrderPlan_groupsOtherLinesByProductLineRouting() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Account shipTo = insertRoutingShipTo(
            account.Id,
            'Other Routing Ship-To',
            'TEST-ORACLE-OTHER-SHIPTO',
            'OH'
        );

        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Product2 endocamProduct = new Product2(
            Name = 'Other Routing Endocam Product',
            ProductType__c = 'Service Asset',
            ProductLine__c = 'ENDOCAM',
            IsActive = true
        );
        insert endocamProduct;
        Schema.Location otherRepairCenter = new Schema.Location(
            Name = 'Other Routing Repair Center',
            LocationType = 'Repair Center'
        );
        insert otherRepairCenter;

        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'ENDOCAM',
            ShipState__c = 'OH',
            RepairCenter__c = otherRepairCenter.Id
        );
        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'ENDOCAM',
            RepairCenter__c = otherRepairCenter.Id
        );

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineKey' => 'other-line-1',
                'lineType' => 'other-non-serialized',
                'serialized' => false,
                'product2Id' => endocamProduct.Id,
                'productLine' => 'ENDOCAM',
                'itemType' => 'Endocam',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'disinfected' => getDisinfectedYesValueForTest(),
                'reportedProblem' => 'Needs repair',
                'shipToAccountId' => String.valueOf(shipTo.Id),
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        List<CreateReturnOrderController.ProposedReturnOrderGroup> groups =
            CreateReturnOrderController.buildReturnOrderPlan(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        Test.stopTest();

        System.assertEquals(1, groups.size(), 'Other lines should route by product line only.');
        System.assertEquals(
            groupKeyFor('Other (Non-Serialized)', String.valueOf(otherRepairCenter.Id)),
            groups[0].groupKey
        );
        System.assertEquals('Other (Non-Serialized)', groups[0].returnOrderType);
        System.assertEquals(false, groups[0].requiresRepairCenterSelection);
        System.assertEquals(1, groups[0].lineCount);
    }

    @isTest
    static void testBuildReturnOrderPlan_splitsOtherDisinfectedNoLines() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Product2 endocamProduct = new Product2(
            Name = 'Other Non Disinfected Endocam Product',
            ProductType__c = 'Service Asset',
            ProductLine__c = 'ENDOCAM',
            IsActive = true
        );
        insert endocamProduct;
        Schema.Location otherRepairCenter = new Schema.Location(
            Name = 'Other Non Disinfected Repair Center',
            LocationType = 'Repair Center'
        );
        insert otherRepairCenter;

        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'ENDOCAM',
            RepairCenter__c = otherRepairCenter.Id
        );

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineKey' => 'other-yes',
                'lineType' => 'other-non-serialized',
                'serialized' => false,
                'product2Id' => endocamProduct.Id,
                'productLine' => 'ENDOCAM',
                'itemType' => 'Endocam',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'disinfected' => getDisinfectedYesValueForTest(),
                'reportedProblem' => 'Issue Yes',
                'quantityReturned' => 1
            },
            new Map<String, Object>{
                'lineKey' => 'other-no-1',
                'lineType' => 'other-non-serialized',
                'serialized' => false,
                'product2Id' => endocamProduct.Id,
                'productLine' => 'ENDOCAM',
                'itemType' => 'Endocam',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'disinfected' => getDisinfectedNoValueForTest(),
                'reportedProblem' => 'Issue No 1',
                'quantityReturned' => 1
            },
            new Map<String, Object>{
                'lineKey' => 'other-no-2',
                'lineType' => 'other-non-serialized',
                'serialized' => false,
                'product2Id' => endocamProduct.Id,
                'productLine' => 'ENDOCAM',
                'itemType' => 'Endocam',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'disinfected' => getDisinfectedNoValueForTest(),
                'reportedProblem' => 'Issue No 2',
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        List<CreateReturnOrderController.ProposedReturnOrderGroup> groups =
            CreateReturnOrderController.buildReturnOrderPlan(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        Test.stopTest();

        System.assertEquals(2, groups.size(), 'Expected disinfected Yes and batched No groups for Other.');

        Integer totalLines = 0;
        Boolean foundYesGroup = false;
        Boolean foundNoBatchGroup = false;

        for (CreateReturnOrderController.ProposedReturnOrderGroup proposedGroup : groups) {
            totalLines += proposedGroup.lineCount;
            if (proposedGroup.groupKey ==
                groupKeyFor('Other (Non-Serialized)', String.valueOf(otherRepairCenter.Id))) {
                foundYesGroup = true;
                System.assertEquals(1, proposedGroup.lineCount);
                System.assertEquals('Other (Non-Serialized)', proposedGroup.returnOrderType);
            }
            if (proposedGroup.groupKey ==
                groupKeyFor(
                    'Other (Non-Serialized)',
                    String.valueOf(otherRepairCenter.Id) + '|NOSTERIL'
                )) {
                foundNoBatchGroup = true;
                System.assertEquals(2, proposedGroup.lineCount);
            }
        }

        System.assertEquals(3, totalLines);
        System.assertEquals(true, foundYesGroup);
        System.assertEquals(true, foundNoBatchGroup);
    }

    @isTest
    static void testBuildReturnOrderPlan_splitsInstrumentsDisinfectedNoLines() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Product2 instrumentProduct = new Product2(
            Name = 'Instrument Non Disinfected Product',
            ProductType__c = 'Service Asset',
            ProductLine__c = 'INSTRUMENT',
            IsActive = true
        );
        insert instrumentProduct;
        Schema.Location instrumentRepairCenter = new Schema.Location(
            Name = 'Instrument Non Disinfected Repair Center',
            LocationType = 'Repair Center'
        );
        insert instrumentRepairCenter;

        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'INSTRUMENT',
            RepairCenter__c = instrumentRepairCenter.Id
        );

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineKey' => 'inst-yes',
                'lineType' => 'instruments',
                'serialized' => false,
                'product2Id' => instrumentProduct.Id,
                'productLine' => 'INSTRUMENT',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'disinfected' => getDisinfectedYesValueForTest(),
                'reportedProblem' => 'Issue Yes',
                'quantityReturned' => 1
            },
            new Map<String, Object>{
                'lineKey' => 'inst-no-1',
                'lineType' => 'instruments',
                'serialized' => false,
                'product2Id' => instrumentProduct.Id,
                'productLine' => 'INSTRUMENT',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'disinfected' => getDisinfectedNoValueForTest(),
                'reportedProblem' => 'Issue No 1',
                'quantityReturned' => 1
            },
            new Map<String, Object>{
                'lineKey' => 'inst-no-2',
                'lineType' => 'instruments',
                'serialized' => false,
                'product2Id' => instrumentProduct.Id,
                'productLine' => 'INSTRUMENT',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'disinfected' => getDisinfectedNoValueForTest(),
                'reportedProblem' => 'Issue No 2',
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        List<CreateReturnOrderController.ProposedReturnOrderGroup> groups =
            CreateReturnOrderController.buildReturnOrderPlan(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        Test.stopTest();

        System.assertEquals(
            2,
            groups.size(),
            'Expected disinfected Yes and batched No groups for Instruments.'
        );

        Integer totalLines = 0;
        Boolean foundYesGroup = false;
        Boolean foundNoBatchGroup = false;

        for (CreateReturnOrderController.ProposedReturnOrderGroup proposedGroup : groups) {
            totalLines += proposedGroup.lineCount;
            if (proposedGroup.groupKey ==
                groupKeyFor('Instruments', String.valueOf(instrumentRepairCenter.Id))) {
                foundYesGroup = true;
                System.assertEquals(1, proposedGroup.lineCount);
                System.assertEquals('Instruments', proposedGroup.returnOrderType);
            }
            if (proposedGroup.groupKey ==
                groupKeyFor(
                    'Instruments',
                    String.valueOf(instrumentRepairCenter.Id) + '|NOSTERIL'
                )) {
                foundNoBatchGroup = true;
                System.assertEquals(2, proposedGroup.lineCount);
            }
        }

        System.assertEquals(3, totalLines);
        System.assertEquals(true, foundYesGroup);
        System.assertEquals(true, foundNoBatchGroup);
    }

    @isTest
    static void testCreateReturnOrders_createsFromGroupedPayload() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        Schema.Location repairCenter = [SELECT Id, Name FROM Location LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82',
            'creationSource' => 'Salesforce',
            'salesRepId' => UserInfo.getUserId(),
            'caseId' => testCase.Id
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'assetId' => asset.Id,
                'product2Id' => asset.Product2Id,
                'model' => 'Test Model',
                'departmentId' => testDepartment.Id,
                'disinfected' => getDisinfectedYesValueForTest(),
                'contactId' => contact.Id,
                'estimateRequired' => 'Pre-Approved',
                'productLine' => 'Surgical',
                'reportedProblem' => 'Unit not powering on',
                'quantityReturned' => 1
            }
        };

        List<Object> groups = new List<Object>{
            new Map<String, Object>{
                'groupKey' => String.valueOf(repairCenter.Id),
                'repairCenterId' => String.valueOf(repairCenter.Id),
                'requiresRepairCenterSelection' => false,
                'lineItemsJson' => JSON.serialize(lines)
            }
        };

        Test.startTest();
        CreateReturnOrderController.CreateOrdersResult result =
            CreateReturnOrderController.createReturnOrders(
                JSON.serialize(header),
                JSON.serialize(groups)
            );
        Test.stopTest();

        System.assertEquals(1, result.returnOrders.size());
        System.assertNotEquals(null, result.returnOrders[0].returnOrderNumber);
        System.assertEquals('Serialized', result.returnOrders[0].returnOrderType);
        System.assertEquals(
            repairCenter.Name,
            result.returnOrders[0].repairCenterName
        );
        System.assertEquals(1, result.returnOrders[0].lineCount);

        ReturnOrder created = [
            SELECT Id, DestinationLocationId
            FROM ReturnOrder
            WHERE Id = :result.returnOrders[0].returnOrderId
            LIMIT 1
        ];
        System.assertEquals(repairCenter.Id, created.DestinationLocationId);
        assertReturnOrderType(created.Id, 'Serialized');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM ReturnOrderLineItem WHERE ReturnOrderId = :created.Id]
        );
    }

    @isTest
    static void testCreateReturnOrders_requiresRepairCenterForUnassignedGroup() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'serialized' => true,
                'product2Id' => asset.Product2Id,
                'model' => 'Needs Center',
                'productLine' => 'Unknown',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'estimateRequired' => 'Pre-Approved',
                'reportedProblem' => 'Needs routing',
                'quantityReturned' => 1
            }
        };

        List<Object> groups = new List<Object>{
            new Map<String, Object>{
                'groupKey' => 'UNASSIGNED',
                'requiresRepairCenterSelection' => true,
                'lineItemsJson' => JSON.serialize(lines)
            }
        };

        Boolean thrown = false;

        Test.startTest();
        try {
            CreateReturnOrderController.createReturnOrders(
                JSON.serialize(header),
                JSON.serialize(groups)
            );
        } catch (Exception e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'Expected repair center validation error.');
    }

    @isTest
    static void testCreateReturnOrder_instruments_success() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineType' => 'instruments',
                'serialized' => false,
                'product2Id' => asset.Product2Id,
                'productLine' => 'INSTRUMENT',
                'itemDescription' => 'Tray insert',
                'disinfected' => getDisinfectedYesValueForTest(),
                'serialNumber' => 'INST-SN-1',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'customerPo' => 'PO-999',
                'repairWarranty' => 'Yes',
                'previousReturnOrder' => 'RO-12345',
                'hospitalReferencedTrayName' => 'Tray A',
                'modRequest' => true,
                'reportedProblem' => 'Tray damaged',
                'estimateRequired' => 'Pre-Approved',
                'quantityReturned' => 2
            }
        };

        Test.startTest();
        CreateReturnOrderController.CreateResult result = CreateReturnOrderController.createReturnOrder(
            JSON.serialize(header),
            JSON.serialize(lines)
        );
        Test.stopTest();

        ReturnOrderLineItem lineItem = [
            SELECT
                Serialized__c,
                Product2Id,
                ProductLine__c,
                LineType__c,
                ItemDescription__c,
                Disinfected__c,
                SerialNumber__c,
                RepairWarranty__c,
                PreviousReturnOrder__c,
                HospitalReferencedTrayName__c,
                ModRequest__c,
                ReportedProblem__c,
                QuantityReturned,
                ReturnOrderId
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :result.returnOrderId
            LIMIT 1
        ];

        assertReturnOrderType(lineItem.ReturnOrderId, 'Instruments');

        System.assertEquals(false, lineItem.Serialized__c);
        System.assertEquals(asset.Product2Id, lineItem.Product2Id);
        System.assertEquals('INSTRUMENT', lineItem.ProductLine__c);
        System.assertEquals('Instrument', lineItem.LineType__c);
        System.assertEquals('Tray insert', lineItem.ItemDescription__c);
        System.assertEquals(getDisinfectedYesValueForTest(), lineItem.Disinfected__c);
        System.assertEquals('INST-SN-1', lineItem.SerialNumber__c);
        System.assertEquals('Yes', lineItem.RepairWarranty__c);
        System.assertEquals('RO-12345', lineItem.PreviousReturnOrder__c);
        System.assertEquals('Tray A', lineItem.HospitalReferencedTrayName__c);
        System.assertEquals(true, lineItem.ModRequest__c);
        System.assertEquals('Tray damaged', lineItem.ReportedProblem__c);
        System.assertEquals(2, lineItem.QuantityReturned);
    }

    @isTest
    static void testCreateReturnOrder_instruments_serialWithDefaultProduct_throws() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Product2 defaultProduct = CreateReturnOrderController.getDefaultProduct();

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineType' => 'instruments',
                'serialized' => false,
                'product2Id' => defaultProduct.Id,
                'productLine' => 'INSTRUMENT',
                'itemDescription' => 'Tray insert',
                'disinfected' => getDisinfectedYesValueForTest(),
                'serialNumber' => 'INST-SN-DEFAULT',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'reportedProblem' => 'Tray damaged',
                'estimateRequired' => 'Pre-Approved',
                'quantityReturned' => 1
            }
        };

        Boolean thrown = false;

        Test.startTest();
        try {
            CreateReturnOrderController.createReturnOrder(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        } catch (Exception e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(
            true,
            thrown,
            'Expected validation error when instrument line has serial number and Default Product.'
        );
    }

    @isTest
    static void testCreateReturnOrder_instruments_additionalServiceFields() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineType' => 'instruments',
                'serialized' => false,
                'product2Id' => asset.Product2Id,
                'productLine' => 'INSTRUMENT',
                'itemDescription' => 'Forceps set',
                'disinfected' => getDisinfectedYesValueForTest(),
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'additionalServices' => true,
                'modRequest' => true,
                'insulationPowderCoating' => 'Navy Blue',
                'reportedProblem' => 'Handle worn',
                'estimateRequired' => 'Pre-Approved',
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        CreateReturnOrderController.CreateResult result = CreateReturnOrderController.createReturnOrder(
            JSON.serialize(header),
            JSON.serialize(lines)
        );
        Test.stopTest();

        assertInstrumentAdditionalServiceFields(
            result.returnOrderId,
            true,
            'Navy Blue',
            null,
            null
        );
    }

    @isTest
    static void testCreateReturnOrder_instruments_legPositionersAdditionalServiceFields() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineType' => 'instruments',
                'serialized' => false,
                'product2Id' => asset.Product2Id,
                'productLine' => 'INSTRUMENT',
                'itemDescription' => 'Stirrup set',
                'serialNumber' => 'LEG-001',
                'disinfected' => getDisinfectedYesValueForTest(),
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'additionalServices' => true,
                'modRequest' => false,
                'legPositionersStirrup' => 'Repair;Replace Pads - Right',
                'reportedProblem' => 'Pad worn',
                'estimateRequired' => 'Pre-Approved',
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        CreateReturnOrderController.CreateResult result = CreateReturnOrderController.createReturnOrder(
            JSON.serialize(header),
            JSON.serialize(lines)
        );
        Test.stopTest();

        assertInstrumentLegPositionersField(
            result.returnOrderId,
            'Repair;Replace Pads - Right',
            'LEG-001'
        );
    }

    @isTest
    static void testCreateReturnOrder_instruments_noSerialAdditionalServiceFields() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineType' => 'instruments',
                'serialized' => false,
                'product2Id' => asset.Product2Id,
                'productLine' => 'INSTRUMENT',
                'itemDescription' => 'Forceps set',
                'disinfected' => getDisinfectedYesValueForTest(),
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'additionalServices' => true,
                'modRequest' => false,
                'additionalServiceRepair' => true,
                'laserMarking' => 'Room 12',
                'colorDipping' => 'Mint Green;Pink',
                'numberOfRings' => '2',
                'reportedProblem' => 'Handle worn',
                'estimateRequired' => 'Pre-Approved',
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        CreateReturnOrderController.CreateResult result = CreateReturnOrderController.createReturnOrder(
            JSON.serialize(header),
            JSON.serialize(lines)
        );
        Test.stopTest();

        assertInstrumentNoSerialAdditionalServiceFields(
            result.returnOrderId,
            true,
            'Room 12',
            'Mint Green;Pink',
            '2'
        );
    }

    @isTest
    static void testCreateReturnOrder_instruments_warrantyNotesWithoutPreviousRo() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineType' => 'instruments',
                'serialized' => false,
                'product2Id' => asset.Product2Id,
                'productLine' => 'INSTRUMENT',
                'itemDescription' => 'Forceps',
                'disinfected' => getDisinfectedYesValueForTest(),
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'repairWarranty' => 'Yes',
                'warrantyNotes' => 'Covered under annual service contract.',
                'reportedProblem' => 'Worn component',
                'estimateRequired' => 'Pre-Approved',
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        CreateReturnOrderController.CreateResult result = CreateReturnOrderController.createReturnOrder(
            JSON.serialize(header),
            JSON.serialize(lines)
        );
        Test.stopTest();

        ReturnOrderLineItem lineItem = [
            SELECT PreviousReturnOrder__c, WarrantyNotes__c, RepairWarranty__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :result.returnOrderId
            LIMIT 1
        ];

        System.assertEquals('Yes', lineItem.RepairWarranty__c);
        System.assertEquals(null, lineItem.PreviousReturnOrder__c);
        System.assertEquals(
            'Covered under annual service contract.',
            lineItem.WarrantyNotes__c
        );
    }

    @isTest
    static void testCreateReturnOrder_instruments_warrantyYesRequiresPreviousRoOrNotes() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineType' => 'instruments',
                'serialized' => false,
                'product2Id' => asset.Product2Id,
                'productLine' => 'INSTRUMENT',
                'itemDescription' => 'Forceps',
                'disinfected' => getDisinfectedYesValueForTest(),
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'repairWarranty' => 'Yes',
                'reportedProblem' => 'Worn component',
                'estimateRequired' => 'Pre-Approved',
                'quantityReturned' => 1
            }
        };

        Boolean thrown = false;

        Test.startTest();
        try {
            CreateReturnOrderController.createReturnOrder(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        } catch (Exception e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(
            true,
            thrown,
            'Expected validation error when Repair Warranty is Yes without Previous RO and without Warranty Notes.'
        );
    }

    @isTest
    static void testCreateReturnOrder_instruments_requiresReportedProblem() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'serialized' => false,
                'product2Id' => asset.Product2Id,
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'quantityReturned' => 1
            }
        };

        Boolean thrown = false;

        Test.startTest();
        try {
            CreateReturnOrderController.createReturnOrder(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        } catch (Exception e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'Expected validation error when Reported Problem is missing.');
    }

    @isTest
    static void testCreateReturnOrder_other_success() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        account.BillingCountryCode = 'US';
        account.BillingStateCode = 'OH';
        update account;

        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        // GW-5866 removed Endocam from Item Type; use an active Other (Non-Serialized) type.
        Product2 cableProduct = new Product2(
            Name = 'Create Other Fiber Optic Cable Product',
            ProductType__c = 'Service Asset',
            ProductLine__c = 'VIDEO',
            IsActive = true
        );
        insert cableProduct;
        Schema.Location repairCenter = new Schema.Location(
            Name = 'Bulk Instrument Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'VIDEO',
            ShipState__c = 'OH',
            RepairCenter__c = repairCenter.Id
        );

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineType' => 'other-non-serialized',
                'serialized' => false,
                'product2Id' => cableProduct.Id,
                'productLine' => 'VIDEO',
                'hospitalReferencedTrayName' => 'Tray Alpha',
                'itemType' => 'Cable: Fiber Optic',
                'itemDescription' => 'Instrument tray',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'reportedProblem' => 'Missing instrument',
                'disinfected' => getDisinfectedYesValueForTest(),
                'estimateRequired' => 'Pre-Approved',
                'quantityReturned' => 3
            }
        };

        Test.startTest();
        CreateReturnOrderController.CreateResult result = CreateReturnOrderController.createReturnOrder(
            JSON.serialize(header),
            JSON.serialize(lines)
        );
        Test.stopTest();

        ReturnOrderLineItem lineItem = [
            SELECT
                Serialized__c,
                HospitalReferencedTrayName__c,
                ItemType__c,
                ProductLine__c,
                LineType__c,
                QuantityReturned,
                ReportedProblem__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :result.returnOrderId
            LIMIT 1
        ];

        System.assertEquals(false, lineItem.Serialized__c);
        System.assertEquals('Tray Alpha', lineItem.HospitalReferencedTrayName__c);
        System.assertEquals('Cable: Fiber Optic', lineItem.ItemType__c);
        System.assertEquals('VIDEO', lineItem.ProductLine__c);
        System.assertEquals('Other (Non-Serialized)', lineItem.LineType__c);
        System.assertEquals(3, lineItem.QuantityReturned);
        System.assertEquals('Missing instrument', lineItem.ReportedProblem__c);
    }

    @isTest
    static void testCreateReturnOrder_other_succeedsWithoutHospitalReferencedTrayName() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        account.BillingCountryCode = 'US';
        account.BillingStateCode = 'OH';
        update account;

        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Product2 cableProduct = new Product2(
            Name = 'Create Other Fiber Optic Cable Product Optional Tray',
            ProductType__c = 'Service Asset',
            ProductLine__c = 'VIDEO',
            IsActive = true
        );
        insert cableProduct;
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Schema.Location repairCenter = new Schema.Location(
            Name = 'Bulk Instrument Repair Center Optional Tray',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'VIDEO',
            ShipState__c = 'OH',
            RepairCenter__c = repairCenter.Id
        );

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineType' => 'other-non-serialized',
                'serialized' => false,
                'product2Id' => cableProduct.Id,
                'itemType' => 'Cable: Fiber Optic',
                'itemDescription' => 'Scope cable',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'reportedProblem' => 'Missing instrument',
                'disinfected' => getDisinfectedYesValueForTest(),
                'estimateRequired' => 'Pre-Approved',
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        CreateReturnOrderController.CreateResult result = CreateReturnOrderController.createReturnOrder(
            JSON.serialize(header),
            JSON.serialize(lines)
        );
        Test.stopTest();

        ReturnOrderLineItem lineItem = [
            SELECT HospitalReferencedTrayName__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :result.returnOrderId
            LIMIT 1
        ];

        System.assertEquals(
            null,
            lineItem.HospitalReferencedTrayName__c,
            'Hospital Referenced Tray Name should be optional on Other line items.'
        );
    }

    @isTest
    static void testCreateReturnOrder_other_requiresItemType() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineType' => 'other-non-serialized',
                'serialized' => false,
                'product2Id' => asset.Product2Id,
                'hospitalReferencedTrayName' => 'Tray Beta',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'reportedProblem' => 'Missing instrument',
                'disinfected' => getDisinfectedYesValueForTest(),
                'quantityReturned' => 1
            }
        };

        Boolean thrown = false;

        Test.startTest();
        try {
            CreateReturnOrderController.createReturnOrder(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        } catch (Exception e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'Expected validation error when Item Type is missing.');
    }

    @isTest
    static void testGetProductsForReturnOrderLine_otherLine_includesActiveProductsWithoutServiceAssetType() {
        Product2 endocamProduct = new Product2(
            Name = 'Other Line Endocam Product',
            ProductCode = 'ENDO-001',
            Model__c = 'MODEL-ENDO',
            ProductLine__c = 'ENDOCAM',
            IsActive = true
        );
        insert endocamProduct;

        Test.startTest();
        List<CreateReturnOrderController.ProductPicklistOption> options =
            CreateReturnOrderController.getProductsForReturnOrderLine('ENDOCAM', false, null);
        Test.stopTest();

        System.assert(!options.isEmpty(), 'Expected at least one ENDOCAM product option.');
        Boolean found = false;
        for (CreateReturnOrderController.ProductPicklistOption option : options) {
            if (option.value == endocamProduct.Id) {
                found = true;
                System.assert(option.label.contains('Other Line Endocam Product'));
                System.assert(option.label.contains('ENDO-001'));
                System.assert(option.label.contains('MODEL-ENDO'));
            }
        }
        System.assertEquals(true, found, 'Expected inserted ENDOCAM product in option list.');
    }

    @isTest
    static void testGetProductsForReturnOrderLine_requiresServiceAssetTypeWhenRequested() {
        Product2 serviceAssetProduct = new Product2(
            Name = 'Instrument Service Asset Product',
            ProductCode = 'INST-001',
            ProductLine__c = 'INSTRUMENT',
            ProductType__c = 'Service Asset',
            IsActive = true
        );
        insert serviceAssetProduct;

        Product2 nonServiceAssetProduct = new Product2(
            Name = 'Instrument Non Service Asset Product',
            ProductCode = 'INST-002',
            ProductLine__c = 'INSTRUMENT',
            IsActive = true
        );
        insert nonServiceAssetProduct;

        Test.startTest();
        List<CreateReturnOrderController.ProductPicklistOption> options =
            CreateReturnOrderController.getProductsForReturnOrderLine('INSTRUMENT', true, null);
        Test.stopTest();

        // Org may already contain INSTRUMENT Service Asset products (e.g. routing test data).
        // Assert the Service Asset filter includes our product and excludes the non-Service Asset one.
        Boolean foundServiceAsset = false;
        Boolean foundNonServiceAsset = false;
        for (CreateReturnOrderController.ProductPicklistOption option : options) {
            if (option.value == serviceAssetProduct.Id) {
                foundServiceAsset = true;
            }
            if (option.value == nonServiceAssetProduct.Id) {
                foundNonServiceAsset = true;
            }
        }
        System.assertEquals(true, foundServiceAsset, 'Expected Service Asset product in results.');
        System.assertEquals(false, foundNonServiceAsset, 'Non-Service Asset product must be excluded.');
    }

    @isTest
    static void testGetProductsForReturnOrderLine_serialized_includesActiveServiceAssetProductsOnly() {
        Product2 serializedProduct = new Product2(
            Name = 'Serialized Service Asset Product',
            ProductCode = 'SER-001',
            Model__c = 'MODEL-SER',
            ProductLine__c = 'FLEXIBLE',
            ProductType__c = 'Service Asset',
            IsActive = true
        );
        insert serializedProduct;

        insert new Product2(
            Name = 'Serialized Inactive Service Asset Product',
            ProductCode = 'SER-002',
            ProductLine__c = 'FLEXIBLE',
            ProductType__c = 'Service Asset',
            IsActive = false
        );

        insert new Product2(
            Name = 'Serialized Non Service Asset Product',
            ProductCode = 'SER-003',
            ProductLine__c = 'FLEXIBLE',
            IsActive = true
        );

        Test.startTest();
        List<CreateReturnOrderController.ProductPicklistOption> options =
            CreateReturnOrderController.getProductsForReturnOrderLine(null, true, null);
        Test.stopTest();

        System.assert(!options.isEmpty(), 'Expected active service asset products.');
        Boolean foundSerializedProduct = false;
        for (CreateReturnOrderController.ProductPicklistOption option : options) {
            if (option.value == serializedProduct.Id) {
                foundSerializedProduct = true;
                System.assert(option.label.contains('Serialized Service Asset Product'));
                System.assert(option.label.contains('SER-001'));
                System.assert(option.label.contains('MODEL-SER'));
            }
            System.assertNotEquals('SER-002', option.productCode);
            System.assertNotEquals('SER-003', option.productCode);
        }
        System.assertEquals(true, foundSerializedProduct);
    }

    @isTest
    static void testGetProductsForReturnOrderLine_serialized_searchTerm_filtersByNameOrCodeOrModel() {
        Product2 matchingProduct = new Product2(
            Name = 'Searchable Serialized Product',
            ProductCode = 'SEARCH-SER',
            Model__c = 'MODEL-SER-SEARCH',
            ProductLine__c = 'RIGID',
            ProductType__c = 'Service Asset',
            IsActive = true
        );
        insert matchingProduct;

        insert new Product2(
            Name = 'Other Serialized Product',
            ProductCode = 'OTHER-SER',
            ProductLine__c = 'RIGID',
            ProductType__c = 'Service Asset',
            IsActive = true
        );

        Test.startTest();
        List<CreateReturnOrderController.ProductPicklistOption> options =
            CreateReturnOrderController.getProductsForReturnOrderLine(null, true, 'SEARCH-SER');
        Test.stopTest();

        System.assertEquals(1, options.size());
        System.assertEquals(matchingProduct.Id, options[0].value);
    }

    @isTest
    static void testGetProductsForReturnOrderLine_searchTerm_filtersByNameOrCodeOrModel() {
        Product2 matchingProduct = new Product2(
            Name = 'Searchable Endocam Product',
            ProductCode = 'SEARCH-ENDO',
            Model__c = 'MODEL-SEARCH',
            ProductLine__c = 'ENDOCAM',
            IsActive = true
        );
        insert matchingProduct;

        insert new Product2(
            Name = 'Other Endocam Product',
            ProductCode = 'OTHER-ENDO',
            ProductLine__c = 'ENDOCAM',
            IsActive = true
        );

        Test.startTest();
        List<CreateReturnOrderController.ProductPicklistOption> options =
            CreateReturnOrderController.getProductsForReturnOrderLine('ENDOCAM', false, 'SEARCH-ENDO');
        Test.stopTest();

        System.assertEquals(1, options.size());
        System.assertEquals(matchingProduct.Id, options[0].value);
    }

    @isTest
    static void testGetProductsForReturnOrderLine_filtersByDeviceType() {
        Product2 stirrupProduct = new Product2(
            Name = 'Stirrup Filter Product',
            ProductCode = 'STIRRUP-FILT',
            ProductLine__c = 'INSTRUMENT',
            DeviceType__c = 'STIRRUP',
            IsActive = true
        );
        insert stirrupProduct;

        Product2 otherInstrument = new Product2(
            Name = 'Non Stirrup Instrument Product',
            ProductCode = 'INST-NO-STIRRUP',
            ProductLine__c = 'INSTRUMENT',
            IsActive = true
        );
        insert otherInstrument;

        Test.startTest();
        List<CreateReturnOrderController.ProductPicklistOption> options =
            CreateReturnOrderController.getProductsForReturnOrderLine(
                'INSTRUMENT',
                false,
                null,
                'Stirrup'
            );
        Test.stopTest();

        Boolean foundStirrup = false;
        Boolean foundOther = false;
        for (CreateReturnOrderController.ProductPicklistOption option : options) {
            if (option.value == stirrupProduct.Id) {
                foundStirrup = true;
            }
            if (option.value == otherInstrument.Id) {
                foundOther = true;
            }
        }
        System.assertEquals(true, foundStirrup, 'Expected Stirrup device-type product.');
        System.assertEquals(false, foundOther, 'Non-Stirrup products must be excluded.');
    }

    @isTest
    static void testBuildReturnOrderPlan_splitsStirrupLinesOnePerReturnOrder() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Product2 stirrupProduct = new Product2(
            Name = 'Stirrup Split Product',
            ProductType__c = 'Service Asset',
            ProductLine__c = 'INSTRUMENT',
            DeviceType__c = 'STIRRUP',
            IsActive = true
        );
        insert stirrupProduct;
        Schema.Location repairCenter = new Schema.Location(
            Name = 'Stirrup Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;
        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'INSTRUMENT',
            RepairCenter__c = repairCenter.Id
        );

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };
        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineKey' => 'stirrup-1',
                'lineType' => 'other-serialized',
                'serialized' => true,
                'product2Id' => stirrupProduct.Id,
                'productLine' => 'INSTRUMENT',
                'itemType' => 'Stirrup',
                'serialNumber' => 'STIRRUP-001',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'disinfected' => getDisinfectedYesValueForTest(),
                'reportedProblem' => 'Pad worn',
                'quantityReturned' => 1
            },
            new Map<String, Object>{
                'lineKey' => 'stirrup-2',
                'lineType' => 'other-serialized',
                'serialized' => true,
                'product2Id' => stirrupProduct.Id,
                'productLine' => 'INSTRUMENT',
                'itemType' => 'Stirrup',
                'serialNumber' => 'STIRRUP-002',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'disinfected' => getDisinfectedYesValueForTest(),
                'reportedProblem' => 'Pad torn',
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        List<CreateReturnOrderController.ProposedReturnOrderGroup> groups =
            CreateReturnOrderController.buildReturnOrderPlan(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        Test.stopTest();

        System.assertEquals(2, groups.size(), 'Each Stirrup line must be its own Return Order.');
        for (CreateReturnOrderController.ProposedReturnOrderGroup proposedGroup : groups) {
            System.assertEquals(1, proposedGroup.lineCount);
            System.assertEquals('Other (Serialized)', proposedGroup.returnOrderType);
            System.assert(
                proposedGroup.groupKey.contains('|STIRRUP|'),
                'Stirrup group key should include STIRRUP suffix.'
            );
            System.assertEquals(
                false,
                proposedGroup.requiresRepairCenterSelection,
                'Matched Stirrup routing must not require manual repair center selection.'
            );
            System.assertEquals(
                repairCenter.Id,
                proposedGroup.repairCenterId,
                'Stirrup group key suffix must not corrupt the repair center Id.'
            );
            System.assertEquals(
                'Stirrup Repair Center',
                proposedGroup.repairCenterName,
                'Review step must show the Location name, not the fallback label.'
            );
        }
    }

    @isTest
    static void testCreateReturnOrder_otherSerialized_mapsLineAndReturnOrderType() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        account.BillingCountryCode = 'US';
        account.BillingStateCode = 'OH';
        update account;
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Product2 phacoProduct = new Product2(
            Name = 'Other Serialized Phaco Product',
            ProductType__c = 'Service Asset',
            ProductLine__c = 'OPHTHALMIC',
            IsActive = true
        );
        insert phacoProduct;
        Schema.Location repairCenter = new Schema.Location(
            Name = 'Other Serialized Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;
        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'OPHTHALMIC',
            ShipState__c = 'OH',
            RepairCenter__c = repairCenter.Id
        );

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };
        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineType' => 'other-serialized',
                'roliLineType' => 'Other (Serialized)',
                'serialized' => true,
                'product2Id' => phacoProduct.Id,
                'itemType' => 'Phaco Handpiece',
                'serialNumber' => 'PHACO-100',
                'model' => 'PHACO-MODEL',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'reportedProblem' => 'Failed seal',
                'disinfected' => getDisinfectedYesValueForTest(),
                'estimateRequired' => 'Pre-Approved',
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        CreateReturnOrderController.CreateResult result = CreateReturnOrderController.createReturnOrder(
            JSON.serialize(header),
            JSON.serialize(lines)
        );
        Test.stopTest();

        ReturnOrder createdOrder = [
            SELECT ReturnOrderType__c
            FROM ReturnOrder
            WHERE Id = :result.returnOrderId
            LIMIT 1
        ];
        ReturnOrderLineItem lineItem = [
            SELECT LineType__c, Serialized__c, SerialNumber__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :result.returnOrderId
            LIMIT 1
        ];

        System.assertEquals('Other (Serialized)', createdOrder.ReturnOrderType__c);
        System.assertEquals('Other (Serialized)', lineItem.LineType__c);
        System.assertEquals(true, lineItem.Serialized__c);
        System.assertEquals('PHACO-100', lineItem.SerialNumber__c);
    }

    @isTest
    static void testBuildReturnOrderPlan_splitsByMaxItemsPerReturn() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        // Routing matches Product2 segments (not line.productLine), so align Product Line with the rule.
        Product2 flexibleScopeProduct = new Product2(
            Name = 'Flexible Scope Max Items Product',
            ProductCode = 'FS-MAX-001',
            ProductType__c = 'Service Asset',
            ProductLine__c = 'FLEXIBLE SCOPE',
            IsActive = true
        );
        insert flexibleScopeProduct;

        Schema.Location repairCenter = new Schema.Location(
            Name = 'Flexible Scope Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'FLEXIBLE SCOPE',
            RepairCenter__c = repairCenter.Id,
            MaxItemsPerReturn__c = 1
        );

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineKey' => 'flex-line-1',
                'serialized' => true,
                'serialNumber' => 'FS-001',
                'product2Id' => flexibleScopeProduct.Id,
                'model' => 'Flex Model 1',
                'productLine' => 'FLEXIBLE SCOPE',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'estimateRequired' => 'Pre-Approved',
                'disinfected' => getDisinfectedYesValueForTest(),
                'quantityReturned' => 1,
                'reportedProblem' => 'Issue 1'
            },
            new Map<String, Object>{
                'lineKey' => 'flex-line-2',
                'serialized' => true,
                'serialNumber' => 'FS-002',
                'product2Id' => flexibleScopeProduct.Id,
                'model' => 'Flex Model 2',
                'productLine' => 'FLEXIBLE SCOPE',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'estimateRequired' => 'Pre-Approved',
                'disinfected' => getDisinfectedYesValueForTest(),
                'quantityReturned' => 1,
                'reportedProblem' => 'Issue 2'
            }
        };

        Test.startTest();
        List<CreateReturnOrderController.ProposedReturnOrderGroup> groups =
            CreateReturnOrderController.buildReturnOrderPlan(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        Test.stopTest();

        System.assertEquals(2, groups.size(), 'Max items per return of 1 should split lines.');
        for (CreateReturnOrderController.ProposedReturnOrderGroup proposedGroup : groups) {
            System.assertEquals(1, proposedGroup.lineCount);
            System.assertEquals('Serialized', proposedGroup.returnOrderType);
            System.assert(
                proposedGroup.groupKey.contains('|MAXITEMS|'),
                'Expected max-items group suffix.'
            );
        }
    }

    @isTest
    static void testBuildReturnOrderPlan_batchesByMaxItemsPerReturn() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Schema.Location repairCenter = new Schema.Location(
            Name = 'Surgical Max Items Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'Surgical',
            RepairCenter__c = repairCenter.Id,
            MaxItemsPerReturn__c = 2
        );

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };

        List<Object> lines = new List<Object>();
        for (Integer index = 1; index <= 3; index++) {
            lines.add(
                new Map<String, Object>{
                    'lineKey' => 'surgical-line-' + index,
                    'serialized' => true,
                    'serialNumber' => 'SRG-' + index,
                    'product2Id' => asset.Product2Id,
                    'model' => 'Surgical Model ' + index,
                    'productLine' => 'Surgical',
                    'departmentId' => testDepartment.Id,
                    'contactId' => contact.Id,
                    'estimateRequired' => 'Pre-Approved',
                    'disinfected' => getDisinfectedYesValueForTest(),
                    'quantityReturned' => 1,
                    'reportedProblem' => 'Issue ' + index
                }
            );
        }

        Test.startTest();
        List<CreateReturnOrderController.ProposedReturnOrderGroup> groups =
            CreateReturnOrderController.buildReturnOrderPlan(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        Test.stopTest();

        System.assertEquals(2, groups.size(), 'Expected two return orders for max items of 2.');
        Integer totalLines = 0;
        Boolean foundTwoLineGroup = false;
        Boolean foundOneLineGroup = false;
        for (CreateReturnOrderController.ProposedReturnOrderGroup proposedGroup : groups) {
            totalLines += proposedGroup.lineCount;
            if (proposedGroup.lineCount == 2) {
                foundTwoLineGroup = true;
            }
            if (proposedGroup.lineCount == 1) {
                foundOneLineGroup = true;
            }
        }
        System.assertEquals(3, totalLines);
        System.assertEquals(true, foundTwoLineGroup);
        System.assertEquals(true, foundOneLineGroup);
    }

    @isTest
    static void testCreateReturnOrder_forcesQuantityOneForFlexibleScope() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        Schema.Location repairCenter = [SELECT Id FROM Location LIMIT 1];
        Asset asset = [SELECT Id, Product2Id, Department__c FROM Asset LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82',
            'creationSource' => 'Salesforce',
            'salesRepId' => UserInfo.getUserId(),
            'caseId' => testCase.Id,
            'repairCenterId' => repairCenter.Id
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'assetId' => asset.Id,
                'product2Id' => asset.Product2Id,
                'model' => 'Flexible Scope Model',
                'departmentId' => testDepartment.Id,
                'disinfected' => getDisinfectedYesValueForTest(),
                'contactId' => contact.Id,
                'estimateRequired' => 'Pre-Approved',
                'productLine' => 'FLEXIBLE SCOPE',
                'reportedProblem' => 'Scope damage',
                'status' => 'Created',
                'quantityReturned' => 5
            }
        };

        Test.startTest();
        CreateReturnOrderController.CreateResult result = CreateReturnOrderController.createReturnOrder(
            JSON.serialize(header),
            JSON.serialize(lines)
        );
        Test.stopTest();

        ReturnOrderLineItem lineItem = [
            SELECT QuantityReturned, ProductLine__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :result.returnOrderId
            LIMIT 1
        ];
        System.assertEquals('FLEXIBLE SCOPE', lineItem.ProductLine__c);
        System.assertEquals(1, lineItem.QuantityReturned);
    }

    @isTest
    static void testCreateReturnOrders_instruments_usesOrderHeader() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Schema.Location repairCenter = [SELECT Id, Name FROM Location LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82',
            'creationSource' => 'Salesforce',
            'salesRepId' => UserInfo.getUserId()
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineType' => 'instruments',
                'serialized' => false,
                'product2Id' => asset.Product2Id,
                'productLine' => 'INSTRUMENT',
                'itemDescription' => 'Tray insert',
                'disinfected' => getDisinfectedYesValueForTest(),
                'departmentId' => testDepartment.Id,
                'reportedProblem' => 'Tray damaged',
                'quantityReturned' => 2
            }
        };

        List<Object> groups = new List<Object>{
            new Map<String, Object>{
                'groupKey' => 'instruments-group',
                'repairCenterId' => String.valueOf(repairCenter.Id),
                'requiresRepairCenterSelection' => false,
                'lineItemsJson' => JSON.serialize(lines),
                'orderHeader' => new Map<String, Object>{
                    'contactId' => String.valueOf(contact.Id),
                    'estimateRequired' => 'Pre-Approved',
                    'repairWarranty' => 'Yes',
                    'previousReturnOrder' => 'RO-99999',
                    'customerPo' => 'PO-INST-1'
                }
            }
        };

        Test.startTest();
        CreateReturnOrderController.CreateOrdersResult result =
            CreateReturnOrderController.createReturnOrders(
                JSON.serialize(header),
                JSON.serialize(groups)
            );
        Test.stopTest();

        System.assertEquals(1, result.returnOrders.size());
        System.assertEquals('Instruments', result.returnOrders[0].returnOrderType);

        ReturnOrder created = [
            SELECT Id, ContactId, CustomerPO__c, RepairWarranty__c, PreviousReturnOrder__c
            FROM ReturnOrder
            WHERE Id = :result.returnOrders[0].returnOrderId
            LIMIT 1
        ];
        System.assertEquals(contact.Id, created.ContactId);
        System.assertEquals('PO-INST-1', created.CustomerPO__c);
        System.assertEquals('Yes', created.RepairWarranty__c);
        System.assertEquals('RO-99999', created.PreviousReturnOrder__c);

        ReturnOrderLineItem lineItem = [
            SELECT Contact__c, CustomerPO__c, EstimateRequired__c, RepairWarranty__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :created.Id
            LIMIT 1
        ];
        System.assertEquals(contact.Id, lineItem.Contact__c);
        System.assertEquals(null, lineItem.CustomerPO__c);
        System.assertEquals(null, lineItem.RepairWarranty__c);
    }

    @isTest
    static void testCreateAccountContact_requireEmail() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Boolean thrown = false;

        Test.startTest();
        try {
            CreateReturnOrderController.createAccountContact(
                account.Id,
                'Quote',
                'Contact',
                null,
                null,
                null,
                true
            );
        } catch (Exception e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'Expected validation error when email is required.');
    }

    @isTest
    static void testCreateReturnOrders_instruments_setsEstimateContact() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        contact.Email = 'quote.contact@example.com';
        update contact;
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Schema.Location repairCenter = [SELECT Id, Name FROM Location LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82',
            'creationSource' => 'Salesforce',
            'salesRepId' => UserInfo.getUserId()
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineType' => 'instruments',
                'serialized' => false,
                'product2Id' => asset.Product2Id,
                'productLine' => 'INSTRUMENT',
                'itemDescription' => 'Tray insert',
                'disinfected' => getDisinfectedYesValueForTest(),
                'departmentId' => testDepartment.Id,
                'reportedProblem' => 'Tray damaged',
                'quantityReturned' => 1
            }
        };

        List<Object> groups = new List<Object>{
            new Map<String, Object>{
                'groupKey' => 'instruments-quote-group',
                'repairCenterId' => String.valueOf(repairCenter.Id),
                'requiresRepairCenterSelection' => false,
                'lineItemsJson' => JSON.serialize(lines),
                'orderHeader' => new Map<String, Object>{
                    'contactId' => String.valueOf(contact.Id),
                    'estimateContactId' => String.valueOf(contact.Id),
                    'estimateRequired' => 'Estimate Required',
                    'customerPo' => 'PO-QUOTE-1',
                    'customerReference' => 'REF-HEADER-1',
                    'hospitalReferencedTrayName' => 'Tray Header A'
                }
            }
        };

        Test.startTest();
        CreateReturnOrderController.CreateOrdersResult result =
            CreateReturnOrderController.createReturnOrders(
                JSON.serialize(header),
                JSON.serialize(groups)
            );
        Test.stopTest();

        System.assertEquals(1, result.returnOrders.size());

        ReturnOrder created = [
            SELECT Id, ContactId, EstimateContact__c, EstimateRequired__c, CustomerPO__c,
                CustomerReference__c, HospitalReferencedTrayName__c
            FROM ReturnOrder
            WHERE Id = :result.returnOrders[0].returnOrderId
            LIMIT 1
        ];
        System.assertEquals(contact.Id, created.ContactId);
        System.assertEquals(contact.Id, created.EstimateContact__c);
        System.assertEquals('Estimate Required', created.EstimateRequired__c);
        System.assertEquals('PO-QUOTE-1', created.CustomerPO__c);
        System.assertEquals('REF-HEADER-1', created.CustomerReference__c);
        System.assertEquals('Tray Header A', created.HospitalReferencedTrayName__c);
    }

    @isTest
    static void testCreateReturnOrder_serialized_setsLineEstimateContact() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        contact.Email = 'line.estimate.contact@example.com';
        update contact;
        Schema.Location repairCenter = [SELECT Id FROM Location LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82',
            'creationSource' => 'Salesforce',
            'salesRepId' => UserInfo.getUserId(),
            'repairCenterId' => repairCenter.Id
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineType' => 'serialized',
                'serialized' => true,
                'assetId' => asset.Id,
                'product2Id' => asset.Product2Id,
                'model' => 'Test Model',
                'serialNumber' => 'SER-EST-1',
                'departmentId' => testDepartment.Id,
                'disinfected' => getDisinfectedYesValueForTest(),
                'contactId' => contact.Id,
                'estimateContactId' => String.valueOf(contact.Id),
                'estimateRequired' => 'Estimate Required',
                'productLine' => 'Surgical',
                'reportedProblem' => 'Needs estimate',
                'status' => 'Created',
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        CreateReturnOrderController.CreateResult result = CreateReturnOrderController.createReturnOrder(
            JSON.serialize(header),
            JSON.serialize(lines)
        );
        Test.stopTest();

        ReturnOrderLineItem lineItem = [
            SELECT Id, Contact__c, EstimateContact__c, EstimateRequired__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :result.returnOrderId
            LIMIT 1
        ];
        System.assertEquals(contact.Id, lineItem.Contact__c);
        System.assertEquals(contact.Id, lineItem.EstimateContact__c);
        System.assertEquals('Estimate Required', lineItem.EstimateRequired__c);
    }

    @isTest
    static void testValidateLineRoutingMatches_prefersMoreSpecificRule() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Product2 scopedProduct = new Product2(
            Name = 'Scoped Scope Product',
            ProductType__c = 'Service Asset',
            ProductLine__c = 'FLEXIBLE SCOPE',
            SubProductLine__c = 'ULTRASOUND',
            Manufacturer__c = 'OLYMPUS',
            DeviceType__c = 'VIDEO BRONCHOSCOPE',
            Model__c = 'BF-Q180',
            IsActive = true
        );
        insert scopedProduct;

        Schema.Location broadCenter = new Schema.Location(
            Name = 'Broad Flexible Scope Center',
            LocationType = 'Repair Center'
        );
        Schema.Location specificCenter = new Schema.Location(
            Name = 'Specific Bronchoscope Center',
            LocationType = 'Repair Center'
        );
        insert new List<Schema.Location>{ broadCenter, specificCenter };

        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'FLEXIBLE SCOPE',
            RepairCenter__c = broadCenter.Id
        );
        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'FLEXIBLE SCOPE',
            SubProductLine__c = 'ULTRASOUND',
            Manufacturer__c = 'OLYMPUS',
            DeviceType__c = 'VIDEO BRONCHOSCOPE',
            Model__c = 'BF%',
            RepairCenter__c = specificCenter.Id
        );

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };
        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineKey' => 'scope-1',
                'serialized' => true,
                'serialNumber' => 'SN-SCOPE-1',
                'product2Id' => scopedProduct.Id,
                'model' => 'BF-Q180',
                'productLine' => 'FLEXIBLE SCOPE',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        List<CreateReturnOrderController.ProposedReturnOrderGroup> groups =
            CreateReturnOrderController.buildReturnOrderPlan(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        Test.stopTest();

        System.assertEquals(1, groups.size());
        System.assertEquals(
            groupKeyFor('Serialized', String.valueOf(specificCenter.Id)),
            groups[0].groupKey,
            'More specific LIKE/exact rule should win over Product Line-only rule.'
        );
    }

    @isTest
    static void testBuildReturnOrderPlan_matchesContainsDeviceTypePattern() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Product2 product = new Product2(
            Name = 'EBUS Pattern Product',
            ProductType__c = 'Service Asset',
            ProductLine__c = 'FLEXIBLE SCOPE',
            SubProductLine__c = 'ULTRASOUND',
            Manufacturer__c = 'OLYMPUS',
            DeviceType__c = 'VIDEO EBUS SCOPE',
            IsActive = true
        );
        insert product;

        Schema.Location repairCenter = new Schema.Location(
            Name = 'EBUS Pattern Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'FLEXIBLE SCOPE',
            SubProductLine__c = 'ULTRASOUND',
            Manufacturer__c = 'OLYMPUS',
            DeviceType__c = '%EBUS%',
            RepairCenter__c = repairCenter.Id
        );

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };
        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineKey' => 'ebus-1',
                'serialized' => true,
                'serialNumber' => 'SN-EBUS-1',
                'product2Id' => product.Id,
                'productLine' => 'FLEXIBLE SCOPE',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        List<CreateReturnOrderController.ProposedReturnOrderGroup> groups =
            CreateReturnOrderController.buildReturnOrderPlan(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        Test.stopTest();

        System.assertEquals(1, groups.size());
        System.assertEquals(
            groupKeyFor('Serialized', String.valueOf(repairCenter.Id)),
            groups[0].groupKey
        );
    }

    @isTest
    static void testCreateReturnOrders_instruments_modRequestContactAndForm() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        contact.Email = 'mod.request.contact@example.com';
        update contact;
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Schema.Location repairCenter = [SELECT Id, Name FROM Location LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];

        ContentVersion contentVersion = new ContentVersion(
            Title = 'Mod Request Form',
            PathOnClient = 'mod-request.pdf',
            VersionData = Blob.valueOf('mod-form-bytes'),
            IsMajorVersion = true
        );
        insert contentVersion;
        contentVersion = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersion.Id
            LIMIT 1
        ];

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82',
            'creationSource' => 'Salesforce',
            'salesRepId' => UserInfo.getUserId()
        };

        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineType' => 'instruments',
                'serialized' => false,
                'product2Id' => asset.Product2Id,
                'productLine' => 'INSTRUMENT',
                'itemDescription' => 'Mod tray',
                'disinfected' => getDisinfectedYesValueForTest(),
                'departmentId' => testDepartment.Id,
                'reportedProblem' => 'Needs mod',
                'modRequest' => true,
                'quantityReturned' => 1,
                'modFormContentDocumentIds' => new List<String>{
                    String.valueOf(contentVersion.ContentDocumentId)
                }
            }
        };

        List<Object> groups = new List<Object>{
            new Map<String, Object>{
                'groupKey' => 'instruments-mod-group',
                'repairCenterId' => String.valueOf(repairCenter.Id),
                'requiresRepairCenterSelection' => false,
                'lineItemsJson' => JSON.serialize(lines),
                'orderHeader' => new Map<String, Object>{
                    'contactId' => String.valueOf(contact.Id),
                    'estimateContactId' => String.valueOf(contact.Id),
                    'estimateRequired' => 'Estimate Required',
                    'modRequestContactId' => String.valueOf(contact.Id),
                    'hasModRequest' => true
                }
            }
        };

        Test.startTest();
        CreateReturnOrderController.CreateOrdersResult result =
            CreateReturnOrderController.createReturnOrders(
                JSON.serialize(header),
                JSON.serialize(groups)
            );
        Test.stopTest();

        System.assertEquals(1, result.returnOrders.size());

        ReturnOrder created = [
            SELECT Id, EstimateRequired__c, EstimateContact__c, ModRequestContact__c
            FROM ReturnOrder
            WHERE Id = :result.returnOrders[0].returnOrderId
            LIMIT 1
        ];
        System.assertEquals('Estimate Required', created.EstimateRequired__c);
        System.assertEquals(contact.Id, created.EstimateContact__c);
        System.assertEquals(contact.Id, created.ModRequestContact__c);

        ReturnOrderLineItem lineItem = [
            SELECT Id, ModRequest__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :created.Id
            LIMIT 1
        ];
        System.assertEquals(true, lineItem.ModRequest__c);

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :lineItem.Id
        ];
        System.assertEquals(1, links.size());
        System.assertEquals(contentVersion.ContentDocumentId, links[0].ContentDocumentId);
    }

    @isTest
    static void testGetShipToAddressesForAccount_returnsPrimaryAndActive() {
        Account customer = [SELECT Id FROM Account WHERE Name = 'Return Order Test Account' LIMIT 1];
        insert new List<Account>{
            new Account(
                Name = 'Primary Ship-To',
                ParentId = customer.Id,
                SourceSystemID__c = 'TEST-ORACLE-SHIPTO-P',
                Type = 'Address',
                ShiptoAddressStatus__c = 'Primary',
                BillingStreet = '100 Main St',
                BillingCity = 'Mentor',
                BillingStateCode = 'OH',
                BillingPostalCode = '44060',
                BillingCountryCode = 'US'
            ),
            new Account(
                Name = 'Active Ship-To',
                ParentId = customer.Id,
                SourceSystemID__c = 'TEST-ORACLE-SHIPTO-A',
                Type = 'Address',
                ShiptoAddressStatus__c = 'Active',
                BillingStreet = '200 Oak Ave',
                BillingCity = 'Cleveland',
                BillingStateCode = 'OH',
                BillingPostalCode = '44114',
                BillingCountryCode = 'US'
            )
        };

        Test.startTest();
        List<CreateReturnOrderController.ShipToAddressOption> options =
            CreateReturnOrderController.getShipToAddressesForAccount(customer.Id);
        Test.stopTest();

        System.assertEquals(2, options.size());
        System.assertEquals(true, options[0].isPrimary);
        System.assertEquals(
            options[0].name + ' - ' + options[0].addressDisplay,
            options[0].label,
            'Ship-To label should show the name and address without status'
        );
        System.assertEquals(
            options[1].name + ' - ' + options[1].addressDisplay,
            options[1].label,
            'Active Ship-To label should omit the status'
        );
        System.assertEquals(false, options[0].label.contains(' - Primary'));
        System.assertEquals(false, options[1].label.contains(' - Active'));
        System.assert(
            options[0].addressDisplay.contains('100 Main St'),
            'Option should show billing address'
        );
    }

    @isTest
    static void testCreateReturnOrder_appliesSelectedShipToAddress() {
        Account customer = [SELECT Id FROM Account WHERE Name = 'Return Order Test Account' LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Schema.Location repairCenter = [SELECT Id FROM Location LIMIT 1];
        Asset asset = [SELECT Id, Product2Id, Department__c FROM Asset LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];

        Account shipTo = new Account(
            Name = 'Active Ship-To',
            ParentId = customer.Id,
            SourceSystemID__c = 'TEST-ORACLE-SHIPTO-A2',
            Type = 'Address',
            ShiptoAddressStatus__c = 'Active',
            BillingStreet = '200 Oak Ave',
            BillingCity = 'Cleveland',
            BillingStateCode = 'OH',
            BillingPostalCode = '44114',
            BillingCountryCode = 'US'
        );
        insert shipTo;
        insert new Account(
            Name = 'Primary Ship-To',
            ParentId = customer.Id,
            SourceSystemID__c = 'TEST-ORACLE-SHIPTO-P2',
            Type = 'Address',
            ShiptoAddressStatus__c = 'Primary',
            BillingStreet = '100 Main St',
            BillingCity = 'Mentor',
            BillingStateCode = 'OH',
            BillingPostalCode = '44060',
            BillingCountryCode = 'US'
        );

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => customer.Id,
            'operatingUnit' => '82',
            'creationSource' => 'Salesforce',
            'salesRepId' => UserInfo.getUserId(),
            'repairCenterId' => repairCenter.Id
        };
        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'assetId' => asset.Id,
                'product2Id' => asset.Product2Id,
                'model' => 'Test Model',
                'departmentId' => testDepartment.Id,
                'disinfected' => getDisinfectedYesValueForTest(),
                'contactId' => contact.Id,
                'estimateRequired' => 'Pre-Approved',
                'productLine' => 'Surgical',
                'reportedProblem' => 'Unit not powering on',
                'shipToAccountId' => String.valueOf(shipTo.Id),
                'status' => 'Created',
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        CreateReturnOrderController.CreateResult result = CreateReturnOrderController.createReturnOrder(
            JSON.serialize(header),
            JSON.serialize(lines)
        );
        Test.stopTest();

        ReturnOrder created = [
            SELECT
                Id,
                ShipToAddressAccount__c,
                ShipToAddress__Street__s,
                ShipToAddress__City__s,
                ShipToAddress__PostalCode__s
            FROM ReturnOrder
            WHERE Id = :result.returnOrderId
            LIMIT 1
        ];
        System.assertEquals(shipTo.Id, created.ShipToAddressAccount__c);
        System.assertEquals('200 Oak Ave', created.ShipToAddress__Street__s);
        System.assertEquals('Cleveland', created.ShipToAddress__City__s);
        System.assertEquals('44114', created.ShipToAddress__PostalCode__s);
    }

    @isTest
    static void testBuildReturnOrderPlan_routesByShipToStateCode() {
        Account account = [SELECT Id FROM Account WHERE Name = 'Return Order Test Account' LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];

        Account ohioShipTo = insertRoutingShipTo(
            account.Id,
            'Ohio Routing Ship-To',
            'TEST-ORACLE-ROUTE-OH',
            'OH'
        );
        Account texasShipTo = new Account(
            Name = 'Texas Routing Ship-To',
            ParentId = account.Id,
            SourceSystemID__c = 'TEST-ORACLE-ROUTE-TX',
            Type = 'Address',
            ShiptoAddressStatus__c = 'Active',
            BillingCountryCode = 'US',
            BillingStateCode = 'TX'
        );
        insert texasShipTo;

        Schema.Location ohioCenter = new Schema.Location(
            Name = 'Ohio State Repair Center',
            LocationType = 'Repair Center'
        );
        Schema.Location texasCenter = new Schema.Location(
            Name = 'Texas State Repair Center',
            LocationType = 'Repair Center'
        );
        insert new List<Schema.Location>{ ohioCenter, texasCenter };

        insert new List<RepairCenterRoutingRule__c>{
            new RepairCenterRoutingRule__c(
                OperatingUnit__c = '82',
                ProductLine__c = 'Surgical',
                ShipState__c = 'OH',
                RepairCenter__c = ohioCenter.Id
            ),
            new RepairCenterRoutingRule__c(
                OperatingUnit__c = '82',
                ProductLine__c = 'Surgical',
                ShipState__c = 'TX',
                RepairCenter__c = texasCenter.Id
            )
        };

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };
        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineKey' => 'line-oh',
                'serialized' => true,
                'product2Id' => asset.Product2Id,
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'disinfected' => getDisinfectedYesValueForTest(),
                'shipToAccountId' => String.valueOf(ohioShipTo.Id)
            },
            new Map<String, Object>{
                'lineKey' => 'line-tx',
                'serialized' => true,
                'product2Id' => asset.Product2Id,
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'disinfected' => getDisinfectedYesValueForTest(),
                'shipToAccountId' => String.valueOf(texasShipTo.Id)
            }
        };

        Test.startTest();
        List<CreateReturnOrderController.ProposedReturnOrderGroup> groups =
            CreateReturnOrderController.buildReturnOrderPlan(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        Test.stopTest();

        System.Assert.areEqual(2, groups.size(), 'Each Ship-To state code routes separately.');
        Set<String> repairCenterIds = new Set<String>();
        for (CreateReturnOrderController.ProposedReturnOrderGroup proposedGroup : groups) {
            System.Assert.areEqual(1, proposedGroup.lineCount);
            System.Assert.areEqual(false, proposedGroup.requiresRepairCenterSelection);
            repairCenterIds.add(proposedGroup.repairCenterId);
        }
        System.Assert.isTrue(repairCenterIds.contains(String.valueOf(ohioCenter.Id)));
        System.Assert.isTrue(repairCenterIds.contains(String.valueOf(texasCenter.Id)));
    }

    @isTest
    static void testBuildReturnOrderPlan_doesNotRouteFromCustomerState() {
        Account account = [SELECT Id FROM Account WHERE Name = 'Return Order Test Account' LIMIT 1];
        account.BillingStreet = '100 Customer Way';
        account.BillingCity = 'Mentor';
        account.BillingStateCode = 'OH';
        account.BillingPostalCode = '44060';
        account.BillingCountryCode = 'US';
        update account;

        Account shipTo = insertRoutingShipTo(
            account.Id,
            'No State Ship-To',
            'TEST-ORACLE-ROUTE-BLANK',
            null
        );
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Asset asset = [SELECT Id, Product2Id FROM Asset LIMIT 1];
        Schema.Location ohioCenter = new Schema.Location(
            Name = 'Customer State Repair Center',
            LocationType = 'Repair Center'
        );
        insert ohioCenter;
        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'Surgical',
            ShipState__c = 'OH',
            RepairCenter__c = ohioCenter.Id
        );

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82'
        };
        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineKey' => 'line-blank-state',
                'serialized' => true,
                'product2Id' => asset.Product2Id,
                'productLine' => 'Surgical',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'disinfected' => getDisinfectedYesValueForTest(),
                'shipToAccountId' => String.valueOf(shipTo.Id)
            }
        };

        Test.startTest();
        List<CreateReturnOrderController.ProposedReturnOrderGroup> groups =
            CreateReturnOrderController.buildReturnOrderPlan(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        Test.stopTest();

        System.Assert.areEqual(1, groups.size());
        System.Assert.areEqual(
            true,
            groups[0].requiresRepairCenterSelection,
            'Customer Account state must not satisfy a Ship-To state rule.'
        );
    }

    @IsTest
    static void testGetSiteVisitRepairCenterLines_returnsMarkedChildLines() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Product2 product = [SELECT Id, Name FROM Product2 WHERE Name = 'Test Service Asset Product' LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Id pricebookId = Test.getStandardPricebookId();
        PricebookEntry pricebookEntry = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );
        insert pricebookEntry;

        WorkOrder siteVisit = new WorkOrder(
            AccountId = account.Id,
            ContactId = contact.Id,
            Status = 'New',
            Pricebook2Id = pricebookId
        );
        insert siteVisit;

        WorkOrder childWorkOrder = new WorkOrder(
            AccountId = account.Id,
            ParentWorkOrderId = siteVisit.Id,
            Status = 'New',
            Pricebook2Id = pricebookId
        );
        insert childWorkOrder;

        WorkOrderLineItem marked = new WorkOrderLineItem(
            WorkOrderId = childWorkOrder.Id,
            PricebookEntryId = pricebookEntry.Id,
            SendToRepairCenter__c = true,
            SerialNumber__c = 'SN-RC-1',
            Model__c = 'Forceps',
            Department__c = testDepartment.Id,
            ReportedProblem__c = 'Tip bent',
            AdditionalServices__c = true,
            InsulationPowderCoating__c = 'Black',
            Quantity = 2,
            Description = 'Bent forceps'
        );
        WorkOrderLineItem unmarked = new WorkOrderLineItem(
            WorkOrderId = childWorkOrder.Id,
            SendToRepairCenter__c = false
        );
        WorkOrderLineItem parentLine = new WorkOrderLineItem(
            WorkOrderId = siteVisit.Id,
            SendToRepairCenter__c = true
        );
        insert new List<WorkOrderLineItem>{ marked, unmarked, parentLine };

        Test.startTest();
        List<CreateReturnOrderController.SiteVisitInstrumentLine> lines =
            CreateReturnOrderController.getSiteVisitRepairCenterLines(siteVisit.Id);
        Test.stopTest();

        System.assertEquals(1, lines.size());
        System.assertEquals(String.valueOf(marked.Id), lines[0].workOrderLineItemId);
        System.assertEquals(String.valueOf(product.Id), lines[0].product2Id);
        System.assertEquals(product.Name, lines[0].productName);
        System.assertEquals('Bent forceps', lines[0].itemDescription);
        System.assertEquals(null, lines[0].serialNumber, 'Make on the work order line must not become the serial number');
        System.assertEquals('Forceps', lines[0].model);
        System.assertEquals(String.valueOf(testDepartment.Id), lines[0].departmentId);
        System.assertEquals('Tip bent', lines[0].reportedProblem);
        System.assertEquals(true, lines[0].additionalServices);
        System.assertEquals('Black', lines[0].insulationPowderCoating);
        System.assertEquals(Decimal.valueOf(2), lines[0].quantityReturned);
    }

    @IsTest
    static void testCreateReturnOrder_siteVisitClearsSendToRepairCenter() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        Department__c testDepartment = [SELECT Id FROM Department__c LIMIT 1];
        Schema.Location repairCenter = [SELECT Id FROM Location LIMIT 1];

        WorkOrder siteVisit = new WorkOrder(
            AccountId = account.Id,
            ContactId = contact.Id,
            Status = 'New'
        );
        insert siteVisit;

        WorkOrder childWorkOrder = new WorkOrder(
            AccountId = account.Id,
            ParentWorkOrderId = siteVisit.Id,
            Status = 'New'
        );
        insert childWorkOrder;

        WorkOrderLineItem included = new WorkOrderLineItem(
            WorkOrderId = childWorkOrder.Id,
            SendToRepairCenter__c = true
        );
        WorkOrderLineItem leftForNextOrder = new WorkOrderLineItem(
            WorkOrderId = childWorkOrder.Id,
            SendToRepairCenter__c = true
        );
        insert new List<WorkOrderLineItem>{ included, leftForNextOrder };

        Map<String, Object> header = new Map<String, Object>{
            'accountId' => account.Id,
            'operatingUnit' => '82',
            'workOrderId' => siteVisit.Id
        };
        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'lineType' => 'instruments',
                'serialized' => false,
                'sourceWorkOrderLineItemId' => included.Id,
                'product2Id' => product.Id,
                'productLine' => 'INSTRUMENT',
                'serialNumber' => 'SN-RC-1',
                'model' => 'Forceps',
                'departmentId' => testDepartment.Id,
                'contactId' => contact.Id,
                'estimateRequired' => 'Pre-Approved',
                'disinfected' => getDisinfectedYesValueForTest(),
                'reportedProblem' => 'Tip bent',
                'quantityReturned' => 1
            }
        };
        List<Object> groups = new List<Object>{
            new Map<String, Object>{
                'groupKey' => String.valueOf(repairCenter.Id),
                'repairCenterId' => String.valueOf(repairCenter.Id),
                'requiresRepairCenterSelection' => false,
                'lineItemsJson' => JSON.serialize(lines)
            }
        };

        Test.startTest();
        CreateReturnOrderController.CreateOrdersResult result =
            CreateReturnOrderController.createReturnOrders(
                JSON.serialize(header),
                JSON.serialize(groups)
            );
        Test.stopTest();

        ReturnOrder created = [
            SELECT WorkOrder__c
            FROM ReturnOrder
            WHERE Id = :result.returnOrders[0].returnOrderId
        ];
        System.assertEquals(siteVisit.Id, created.WorkOrder__c);

        Map<Id, WorkOrderLineItem> savedLines = new Map<Id, WorkOrderLineItem>([
            SELECT SendToRepairCenter__c
            FROM WorkOrderLineItem
            WHERE Id IN :new Set<Id>{ included.Id, leftForNextOrder.Id }
        ]);
        System.assertEquals(false, savedLines.get(included.Id).SendToRepairCenter__c);
        System.assertEquals(true, savedLines.get(leftForNextOrder.Id).SendToRepairCenter__c);
    }
}