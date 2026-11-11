/**
 * @description Test class for ReturnOrdersService.
 *              Covers create, update, delete, and retrieval operations
 *              across positive, negative, bulk, and empty-input scenarios.
 */
@IsTest
private class ReturnOrdersServiceTest {

    @TestSetup
    static void setupTestData() {
        // GW-6358: Shipment and Work Order Shipment access for the user-mode DML in the service
        assignPermissionSetIfNeeded('ProcessReturnOrders');
        assignPermissionSetIfNeeded('ManageWorkOrders');

        System.runAs(new User(Id = UserInfo.getUserId())) {
            // Build and persist an Account to parent the ReturnOrders
            adb_Account accountBuilder = new adb_Account();
            accountBuilder.persist();

            // Build and persist 10 ReturnOrders for test coverage
            List<ReturnOrder> returnOrderList = new List<ReturnOrder>();
            for (Integer i = 0; i < 10; i++) {
                ReturnOrder ro = newDraftReturnOrder();
                ro.AccountId = accountBuilder.id;
                returnOrderList.add(ro);
            }
            insert returnOrderList;
        }
    }

    /**
     * @description GW-6358 - Assigns a permission set to the running user when it is not assigned yet.
     * @param permissionSetName Permission set API name
     */
    private static void assignPermissionSetIfNeeded(String permissionSetName) {
        List<PermissionSet> permissionSets = [SELECT Id FROM PermissionSet WHERE Name = :permissionSetName LIMIT 1];
        if (permissionSets.isEmpty()) {
            return;
        }
        List<PermissionSetAssignment> existingAssignments = [
            SELECT Id
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :permissionSets[0].Id
            LIMIT 1
        ];
        if (existingAssignments.isEmpty()) {
            new adb_PermissionSetAssignment()
                .assigneeId(UserInfo.getUserId())
                .permissionSetId(permissionSets[0].Id)
                .persist();
        }
    }

    // ── createReturnOrders ────────────────────────────────────────────────────

    @IsTest
    static void shouldCreateReturnOrders_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<ReturnOrder> returnOrderList = new List<ReturnOrder>{
                newDraftReturnOrder(),
                newDraftReturnOrder()
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ReturnOrdersService.createReturnOrders(returnOrderList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> insertedIds = new Map<Id, ReturnOrder>(returnOrderList).keySet();
            List<ReturnOrder> insertedList = [SELECT Id FROM ReturnOrder WHERE Id IN :insertedIds];
            Assert.areEqual(2, insertedList.size(), 'createReturnOrders should insert all 2 ReturnOrders');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenCreateReturnOrdersCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM ReturnOrder];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ReturnOrdersService.createReturnOrders(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM ReturnOrder];
            Assert.areEqual(countBefore, countAfter, 'createReturnOrders with null should not insert any records');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenCreateReturnOrdersCalledWithEmptyList() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM ReturnOrder];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ReturnOrdersService.createReturnOrders(new List<ReturnOrder>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM ReturnOrder];
            Assert.areEqual(countBefore, countAfter, 'createReturnOrders with empty list should not insert any records');
        }
    }

    // ── updateReturnOrders ────────────────────────────────────────────────────

    @IsTest
    static void shouldUpdateReturnOrders_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<ReturnOrder> returnOrderList = [SELECT Id, Status FROM ReturnOrder LIMIT 3];
            for (ReturnOrder ro : returnOrderList) {
                ro.Status = 'Submitted';
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ReturnOrdersService.updateReturnOrders(returnOrderList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> updatedIds = new Map<Id, ReturnOrder>(returnOrderList).keySet();
            List<ReturnOrder> updatedList = [SELECT Id, Status FROM ReturnOrder WHERE Id IN :updatedIds];
            for (ReturnOrder ro : updatedList) {
                Assert.areEqual('Submitted', ro.Status, 'Status should be updated to Submitted');
            }
        }
    }

    @IsTest
    static void shouldDoNothing_WhenUpdateReturnOrdersCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ReturnOrdersService.updateReturnOrders(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(true, 'updateReturnOrders with null should complete without error');
        }
    }

    // ── deleteReturnOrders ────────────────────────────────────────────────────

    @IsTest
    static void shouldDeleteReturnOrders_WhenValidIdsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<ReturnOrder> returnOrderList = [SELECT Id FROM ReturnOrder LIMIT 3];
            Set<Id> returnOrderIdSet = new Map<Id, ReturnOrder>(returnOrderList).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ReturnOrdersService.deleteReturnOrders(returnOrderIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer remainingCount = [SELECT COUNT() FROM ReturnOrder WHERE Id IN :returnOrderIdSet];
            Assert.areEqual(0, remainingCount, 'deleteReturnOrders should delete all specified ReturnOrders');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenDeleteReturnOrdersCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM ReturnOrder];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ReturnOrdersService.deleteReturnOrders(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM ReturnOrder];
            Assert.areEqual(countBefore, countAfter, 'deleteReturnOrders with null should not delete any records');
        }
    }

    // ── getReturnOrdersById ───────────────────────────────────────────────────

    @IsTest
    static void shouldReturnReturnOrders_WhenGetByIdCalledWithValidIds() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> returnOrderIdSet = new Map<Id, ReturnOrder>([SELECT Id FROM ReturnOrder]).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<ReturnOrder> resultList = ReturnOrdersService.getReturnOrdersById(returnOrderIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(10, resultList.size(), 'getReturnOrdersById should return all 10 ReturnOrders');
        }
    }

    @IsTest
    static void shouldReturnEmpty_WhenGetByIdCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<ReturnOrder> resultList = ReturnOrdersService.getReturnOrdersById(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getReturnOrdersById with null should return an empty list');
        }
    }

    @IsTest
    static void shouldReturnEmpty_WhenGetByIdCalledWithEmptySet() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<ReturnOrder> resultList = ReturnOrdersService.getReturnOrdersById(new Set<Id>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getReturnOrdersById with empty Set should return an empty list');
        }
    }

    // ── requestInboundShippingLabel (GW-2793) ─────────────────────────────────

    @IsTest
    static void testRequestInboundShippingLabel_persistsTrackingAndLabel() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        account.BillingStreet = null;
        account.BillingCity = 'Stanford';
        account.BillingStateCode = 'CA';
        account.BillingPostalCode = '94305';
        account.BillingCountryCode = 'US';
        update account;

        Schema.Location repairCenter = new Schema.Location(
            Name = 'IE FedEx Test Repair Center',
            LocationType = 'Repair Center',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert repairCenter;

        Schema.SObjectType addressType = Schema.getGlobalDescribe().get('Address');
        SObject labAddress = addressType.newSObject();
        labAddress.put('ParentId', repairCenter.Id);
        labAddress.put('LocationType', 'Repair Center');
        labAddress.put('Street', '5960 Heisley Road');
        labAddress.put('City', 'Mentor');
        labAddress.put('StateCode', 'OH');
        labAddress.put('PostalCode', '44060');
        labAddress.put('CountryCode', 'US');
        insert labAddress;

        repairCenter.VisitorAddressId = (Id) labAddress.get('Id');
        update repairCenter;

        ReturnOrder returnOrderRecord = newDraftReturnOrder();
        returnOrderRecord.AccountId = account.Id;
        returnOrderRecord.DestinationLocationId = repairCenter.Id;
        returnOrderRecord.CustomerPO__c = 'PO-FEDEX-001';
        returnOrderRecord.ShipToAddress__Street__s = '20 UNIVERSITY ROAD STE 700';
        returnOrderRecord.ShipToAddress__City__s = 'Cambridge';
        returnOrderRecord.ShipToAddress__StateCode__s = 'MA';
        returnOrderRecord.ShipToAddress__PostalCode__s = '02138';
        returnOrderRecord.ShipToAddress__CountryCode__s = 'US';
        insert returnOrderRecord;

        FedExService.testCalloutResponseMap = FedExService.buildTestSuccessResponse(
            'TRACK-INBOUND-001',
            Blob.valueOf('%PDF-MOCK-LABEL%')
        );

        try {
            Test.startTest();
            ReturnOrdersService.requestInboundShippingLabel(returnOrderRecord.Id);
            Test.stopTest();
        } finally {
            FedExService.testCalloutResponseMap = null;
        }

        ReturnOrder refreshed = [
            SELECT Id, ReturnOrderNumber
            FROM ReturnOrder
            WHERE Id = :returnOrderRecord.Id
        ];
        // GW-6358: the tracking number is stored on a new Shipment of the Return Order
        Shipment shipment = [
            SELECT TrackingNumber, TrackingUrl, Status, Carrier__c
            FROM Shipment
            WHERE ReturnOrderId = :returnOrderRecord.Id
        ];
        Assert.areEqual('TRACK-INBOUND-001', shipment.TrackingNumber);
        Assert.areEqual('https://www.fedex.com/fedextrack/?trknbr=TRACK-INBOUND-001', shipment.TrackingUrl);
        Assert.areEqual('Created', shipment.Status);
        Assert.areEqual('FedEx', shipment.Carrier__c);
        assertInboundCustomerReference(refreshed);

        List<ContentDocumentLink> links = [
            SELECT ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :returnOrderRecord.Id
        ];
        Assert.isFalse(links.isEmpty(), 'Shipping label file should be linked to the RO');
        Boolean foundLabel = false;
        for (ContentDocumentLink linkRow : links) {
            if (linkRow.ContentDocument.Title != null &&
                linkRow.ContentDocument.Title.startsWith('Shipping Label')) {
                foundLabel = true;
            }
        }
        Assert.isTrue(foundLabel, 'Expected Shipping Label file title on the RO');
    }

    @IsTest
    static void testRequestInboundShippingLabel_nullIdThrows() {
        Boolean threw = false;
        try {
            ReturnOrdersService.requestInboundShippingLabel(null);
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('required'));
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void testReturnOrderDisplayNumber_formatsReturnOrderNumber() {
        ReturnOrder returnOrderRecord = [
            SELECT Id, ReturnOrderNumber
            FROM ReturnOrder
            LIMIT 1
        ];

        String reference = ReturnOrdersService.returnOrderDisplayNumber(
            returnOrderRecord.ReturnOrderNumber
        );
        String expected = expectedFedExCustomerReference(returnOrderRecord.ReturnOrderNumber);

        Assert.areEqual(expected, reference);
        Assert.areNotEqual(String.valueOf(returnOrderRecord.Id), reference);
        Assert.areEqual('RO', ReturnOrdersService.returnOrderDisplayNumber(null));
        Assert.areEqual('RO', ReturnOrdersService.returnOrderDisplayNumber(''));
    }

    @IsTest
    static void testCreateVendorFedExShipments_setsCustomerReferenceToReturnOrderNumber() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        account.BillingStreet = '100 Vendor Way';
        account.BillingCity = 'Mentor';
        account.BillingStateCode = 'OH';
        account.BillingPostalCode = '44060';
        account.BillingCountryCode = 'US';
        update account;

        Schema.Location repairCenter = new Schema.Location(
            Name = 'Vendor FedEx REF Repair Center',
            LocationType = 'Repair Center',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert repairCenter;

        Schema.SObjectType addressType = Schema.getGlobalDescribe().get('Address');
        SObject labAddress = addressType.newSObject();
        labAddress.put('ParentId', repairCenter.Id);
        labAddress.put('LocationType', 'Repair Center');
        labAddress.put('Street', '5960 Heisley Road');
        labAddress.put('City', 'Mentor');
        labAddress.put('StateCode', 'OH');
        labAddress.put('PostalCode', '44060');
        labAddress.put('CountryCode', 'US');
        insert labAddress;

        ReturnOrder returnOrderRecord = newDraftReturnOrder();
        returnOrderRecord.AccountId = account.Id;
        returnOrderRecord.SourceLocationId = repairCenter.Id;
        returnOrderRecord.CustomerPO__c = 'PO-VENDOR-REF';
        insert returnOrderRecord;

        FedExService.testCalloutResponseMap = FedExService.buildTestSuccessResponse(
            'TRACK-VENDOR-REF',
            Blob.valueOf('%PDF-MOCK-LABEL%')
        );

        try {
            Test.startTest();
            ReturnOrdersService.createVendorFedExShipments(
                new Map<Id, List<Id>>{ returnOrderRecord.Id => new List<Id>() }
            );
            Test.stopTest();
        } finally {
            FedExService.testCalloutResponseMap = null;
        }

        ReturnOrder refreshed = [
            SELECT Id, ReturnOrderNumber
            FROM ReturnOrder
            WHERE Id = :returnOrderRecord.Id
        ];
        // GW-6358: the tracking number is stored on a Shipment of the Vendor Return Order
        Shipment shipment = [SELECT TrackingNumber FROM Shipment WHERE ReturnOrderId = :returnOrderRecord.Id];
        Assert.areEqual('TRACK-VENDOR-REF', shipment.TrackingNumber);
        assertVendorCustomerReference(refreshed);
    }

    private static void assertInboundCustomerReference(ReturnOrder returnOrderRecord) {
        ReturnOrder loaded = selectReturnOrderForFedExRequest(returnOrderRecord.Id);
        ReturnOrdersService.ResolvedAddress address = sampleFedExAddress();
        ReturnOrdersService.InboundShippingRequestDTO request =
            ReturnOrdersService.buildInboundShippingRequest(loaded, address, address);
        assertCustomerReferenceValue(request.CustomerReference, loaded);
    }

    private static void assertVendorCustomerReference(ReturnOrder returnOrderRecord) {
        ReturnOrder loaded = selectReturnOrderForFedExRequest(returnOrderRecord.Id);
        ReturnOrdersService.ResolvedAddress address = sampleFedExAddress();
        ReturnOrdersService.VendorFedExShipmentRequestDTO request =
            ReturnOrdersService.buildVendorFedExRequest(
                loaded,
                address,
                address,
                UserInfo.getName()
            );
        assertCustomerReferenceValue(request.CustomerReference, loaded);
    }

    private static ReturnOrder selectReturnOrderForFedExRequest(Id returnOrderId) {
        return [
            SELECT Id, ReturnOrderNumber, AccountId, Account.Name, Contact.Name, CustomerPO__c
            FROM ReturnOrder
            WHERE Id = :returnOrderId
        ];
    }

    private static ReturnOrdersService.ResolvedAddress sampleFedExAddress() {
        ReturnOrdersService.ResolvedAddress address = new ReturnOrdersService.ResolvedAddress();
        address.line1 = '5960 Heisley Road';
        address.city = 'Mentor';
        address.stateCode = 'OH';
        address.postalCode = '44060';
        address.countryCode = 'US';
        return address;
    }

    private static void assertCustomerReferenceValue(String actual, ReturnOrder returnOrderRecord) {
        String expected = expectedFedExCustomerReference(returnOrderRecord.ReturnOrderNumber);
        Assert.areEqual(
            expected,
            actual,
            'FedEx CustomerReference should be the Return Order number'
        );
        Assert.areNotEqual(
            String.valueOf(returnOrderRecord.Id),
            actual,
            'FedEx CustomerReference should not be the Return Order Id'
        );
    }

    private static String expectedFedExCustomerReference(String returnOrderNumber) {
        if (String.isBlank(returnOrderNumber)) {
            return 'RO';
        }
        return returnOrderNumber.startsWith('RO-')
            ? returnOrderNumber
            : 'RO-' + returnOrderNumber;
    }

    // ── GW-3880 vendor FedEx / consolidation ───────────────────────────────────

    @IsTest
    static void testRequestVendorFedExShipmentDelegatesToFedExService() {
        FedExService.testCalloutResponseMap = FedExService.buildTestSuccessResponse(
            'FEDEX-TEST-123',
            Blob.valueOf('label')
        );

        Test.startTest();
        FedExService.TrackingResponseDTO response =
            ReturnOrdersService.requestVendorFedExShipment('{"ShippingMethod":"FEDEX_GROUND"}');
        Test.stopTest();

        Assert.areEqual('FEDEX-TEST-123', response.trackingNumber);
        Assert.areEqual(Blob.valueOf('label'), response.shippingLabel);
        FedExService.testCalloutResponseMap = null;
    }

    @IsTest
    static void testCreateVendorFedExShipmentsMissingReturnOrderThrows() {
        Map<Id, List<Id>> returnOrderIdToWorkOrderIdsMap = new Map<Id, List<Id>>{
            UserInfo.getUserId() => new List<Id>()
        };

        Boolean threw = false;
        try {
            Test.startTest();
            ReturnOrdersService.createVendorFedExShipments(returnOrderIdToWorkOrderIdsMap);
            Test.stopTest();
            Assert.fail('Expected ReturnOrdersServiceException');
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('was not found'), e.getMessage());
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void testRequestVendorFedExShipmentRetriesThenSucceeds() {
        ReturnOrdersService.testRemainingVendorCalloutFailures = 2;
        FedExService.testCalloutResponseMap = FedExService.buildTestSuccessResponse(
            '794900000001',
            Blob.valueOf('retry-success')
        );

        Test.startTest();
        FedExService.TrackingResponseDTO response = ReturnOrdersService.requestVendorFedExShipment('{}');
        Test.stopTest();

        Assert.areEqual('794900000001', response.trackingNumber);
        Assert.areEqual(0, ReturnOrdersService.testRemainingVendorCalloutFailures);
        FedExService.testCalloutResponseMap = null;
    }

    @IsTest
    static void testRequestVendorFedExShipmentBlankTrackingThrowsAfterRetries() {
        FedExService.testCalloutResponseMap = FedExService.buildTestSuccessResponse('', null);

        Boolean threw = false;
        try {
            Test.startTest();
            ReturnOrdersService.requestVendorFedExShipment('{}');
            Test.stopTest();
            Assert.fail('Expected ReturnOrdersServiceException');
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('did not return a tracking number'),
                e.getMessage()
            );
        } finally {
            FedExService.testCalloutResponseMap = null;
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void testCreateVendorFedExShipments_nullOrEmpty_noOp() {
        /********************************************
         * WHEN / THEN
         ********************************************/
        Test.startTest();
        ReturnOrdersService.createVendorFedExShipments(null);
        ReturnOrdersService.createVendorFedExShipments(new Map<Id, List<Id>>());
        Test.stopTest();
        Assert.isTrue(true, 'Null/empty maps should no-op without error');
    }

    @IsTest
    static void testGetShipmentAddressValidationError_andHasRepairCenterAddress() {
        /********************************************
         * SETUP
         ********************************************/
        Assert.areEqual(
            'Vendor account is required for FedEx shipment.',
            ReturnOrdersService.getShipmentAddressValidationError(null, null, null, null)
        );

        Schema.Location bareRepairCenter = new Schema.Location(
            Name = 'ROS Bare RC',
            LocationType = 'Repair Center',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert bareRepairCenter;
        Assert.areEqual(
            'Repair Center is required for FedEx shipment.',
            ReturnOrdersService.getShipmentAddressValidationError(
                UserInfo.getUserId(),
                'Vendor X',
                null,
                null
            )
        );
        Assert.isFalse(ReturnOrdersService.hasRepairCenterAddress(null));
        Assert.isFalse(ReturnOrdersService.hasRepairCenterAddress(bareRepairCenter.Id));

        Account incompleteVendor = new Account(
            Name = 'ROS Incomplete Vendor',
            SystemID__c = 'LEG-ROS-IV01',
            SourceSystemID__c = 'ORCL-ROS-IV01',
            OrgIDs__c = '82',
            BillingCity = 'Cleveland'
        );
        insert incompleteVendor;

        String vendorError = ReturnOrdersService.getShipmentAddressValidationError(
            incompleteVendor.Id,
            'ROS Incomplete Vendor',
            bareRepairCenter.Id,
            'ROS Bare RC'
        );
        Assert.isTrue(
            vendorError != null && vendorError.contains('ship-to address is incomplete'),
            vendorError
        );
        Assert.isTrue(vendorError.contains('missing:'), vendorError);

        Account completeVendor = new Account(
            Name = 'ROS Complete Vendor',
            SystemID__c = 'LEG-ROS-CV01',
            SourceSystemID__c = 'ORCL-ROS-CV01',
            OrgIDs__c = '82',
            BillingStreet = '100 Vendor Way',
            BillingCity = 'Mentor',
            BillingStateCode = 'OH',
            BillingPostalCode = '44060',
            BillingCountryCode = 'US'
        );
        insert completeVendor;

        String repairCenterError = ReturnOrdersService.getShipmentAddressValidationError(
            completeVendor.Id,
            'ROS Complete Vendor',
            bareRepairCenter.Id,
            'ROS Bare RC'
        );
        Assert.isTrue(
            repairCenterError != null && repairCenterError.contains('address is incomplete'),
            repairCenterError
        );

        Schema.Location addressedRepairCenter = insertRepairCenterWithAddress(
            'ROS Addressed RC',
            '5960 Heisley Road',
            'Mentor',
            'OH',
            '44060'
        );
        Assert.isTrue(ReturnOrdersService.hasRepairCenterAddress(addressedRepairCenter.Id));

        Test.startTest();
        String noError = ReturnOrdersService.getShipmentAddressValidationError(
            completeVendor.Id,
            null,
            addressedRepairCenter.Id,
            null
        );
        Test.stopTest();

        Assert.isNull(noError, 'Complete vendor + RC addresses should pass validation');
    }

    @IsTest
    static void testToCountryCode_mapsCommonValues() {
        Assert.isNull(ReturnOrdersService.toCountryCode(null));
        Assert.isNull(ReturnOrdersService.toCountryCode(''));
        Assert.areEqual('US', ReturnOrdersService.toCountryCode('us'));
        Assert.areEqual('US', ReturnOrdersService.toCountryCode('United States'));
        Assert.areEqual('US', ReturnOrdersService.toCountryCode('USA'));
        Assert.areEqual('Canada', ReturnOrdersService.toCountryCode('Canada'));
    }

    @IsTest
    static void testBuildVendorPackingSlipHtml_replacesTokens() {
        /********************************************
         * GIVEN
         ********************************************/
        Account vendorAccount = new Account(Name = 'Pack Slip Vendor', AccountNumber = 'V-88');
        ReturnOrder returnOrder = (ReturnOrder) JSON.deserialize(
            '{"ReturnOrderNumber":"0188"}',
            ReturnOrder.class
        );
        returnOrder.Account = vendorAccount;
        WorkOrder workOrder = (WorkOrder) JSON.deserialize(
            '{"WorkOrderNumber":"9001"}',
            WorkOrder.class
        );
        Product2 product = new Product2(Description = 'Scope tip');
        ReturnOrderLineItem outbound = new ReturnOrderLineItem(
            QuantityReturned = 2,
            Product2 = product
        );
        outbound.put('Model__c', 'GF-UCT180');
        outbound.put('SerialNumber__c', 'SN-88');

        /********************************************
         * WHEN
         ********************************************/
        Test.startTest();
        String html = ReturnOrdersService.buildVendorPackingSlipHtml(
            returnOrder,
            new List<WorkOrder>{ workOrder },
            new List<ReturnOrderLineItem>{ outbound },
            'TRACK-PACK-001'
        );
        Blob pdfBlob = ReturnOrdersService.buildVendorPackingSlip(
            returnOrder,
            new List<WorkOrder>{ workOrder },
            new List<ReturnOrderLineItem>{ outbound },
            'TRACK-PACK-001'
        );
        Test.stopTest();

        /********************************************
         * THEN
         ********************************************/
        Assert.isTrue(html.contains('Pack Slip Vendor'), html);
        Assert.isTrue(html.contains('V-88'), html);
        Assert.isTrue(html.contains('RO-0188'), html);
        Assert.isTrue(html.contains('WO-9001'), html);
        Assert.isTrue(html.contains('TRACK-PACK-001'), html);
        Assert.isTrue(html.contains('Scope tip'), html);
        Assert.isTrue(html.contains('GF-UCT180'), html);
        Assert.isTrue(html.contains('SN-88'), html);
        Assert.isNotNull(pdfBlob);
        Assert.isTrue(pdfBlob.size() > 0);
    }

    @IsTest
    static void testBuildVendorPackingSlipHtml_fallsBackToWorkOrderRows() {
        ReturnOrder returnOrder = (ReturnOrder) JSON.deserialize(
            '{"ReturnOrderNumber":"RO-77"}',
            ReturnOrder.class
        );
        WorkOrder workOrder = (WorkOrder) JSON.deserialize(
            '{"WorkOrderNumber":"WO-77"}',
            WorkOrder.class
        );

        String html = ReturnOrdersService.buildVendorPackingSlipHtml(
            returnOrder,
            new List<WorkOrder>{ workOrder },
            null,
            'TRACK-77'
        );

        Assert.isTrue(html.contains('WO-77'), html);
        Assert.isTrue(html.contains('TRACK-77'), html);
    }

    @IsTest
    static void testCompleteVendorShipment_emptyListThrows() {
        Boolean threw = false;
        try {
            ReturnOrdersService.completeVendorShipment(new List<Id>());
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('Select at least one'), e.getMessage());
        }
        Assert.isTrue(threw);

        threw = false;
        try {
            ReturnOrdersService.completeVendorShipment(null);
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('Select at least one'), e.getMessage());
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void testCompleteVendorShipment_noRepairCenterThrows() {
        /********************************************
         * SETUP
         ********************************************/
        deactivateServiceResourcesForCurrentUser();

        /********************************************
         * WHEN / THEN
         ********************************************/
        Boolean threw = false;
        try {
            Test.startTest();
            ReturnOrdersService.completeVendorShipment(new List<Id>{ UserInfo.getUserId() });
            Test.stopTest();
            Assert.fail('Expected ReturnOrdersServiceException');
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('No active Service Resource'),
                e.getMessage()
            );
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void testCompleteVendorShipment_createsVendorReturnOrderAndOutbounds() {
        /********************************************
         * SETUP
         ********************************************/
        VendorConsolidationFixture fixture = buildVendorConsolidationFixture('CVS');

        FedExService.testCalloutResponseMap = FedExService.buildTestSuccessResponse(
            '7949CVS00001',
            Blob.valueOf('%PDF-VENDOR-LABEL%')
        );

        /********************************************
         * WHEN
         ********************************************/
        ReturnOrdersService.VendorConsolidationCompleteResult result;
        try {
            Test.startTest();
            result = ReturnOrdersService.completeVendorShipment(
                new List<Id>{ fixture.vendorWorkOrder.Id }
            );
            Test.stopTest();
        } finally {
            FedExService.testCalloutResponseMap = null;
        }

        /********************************************
         * THEN
         ********************************************/
        Assert.isNotNull(result);
        Assert.areEqual(1, result.returnOrderIds.size());
        Assert.areEqual(1, result.workOrderCount);
        Assert.isTrue(
            result.message.contains('Vendor Return Order'),
            result.message
        );

        Id vendorRoId = result.returnOrderIds[0];
        ReturnOrder vendorRo = [
            SELECT
                Id,
                AccountId,
                SourceLocationId,
                DestinationLocationId,
                ReturnOrderType__c,
                RecordType.DeveloperName
            FROM ReturnOrder
            WHERE Id = :vendorRoId
        ];
        Assert.areEqual(fixture.vendorAccount.Id, vendorRo.AccountId);
        Assert.areEqual(fixture.repairCenter.Id, vendorRo.SourceLocationId);
        Assert.areEqual('Vendor', vendorRo.ReturnOrderType__c);
        Assert.areEqual('VendorReturn', vendorRo.RecordType.DeveloperName);
        // GW-6358: tracking is on a Shipment of the Vendor Return Order
        Shipment vendorShipment = [SELECT Id, TrackingNumber FROM Shipment WHERE ReturnOrderId = :vendorRoId];
        Assert.areEqual('7949CVS00001', vendorShipment.TrackingNumber);

        List<ReturnOrderLineItem> lines = [
            SELECT Id, LineType__c, RecordType.DeveloperName, Product2Id
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :vendorRoId
        ];
        Assert.isTrue(lines.size() >= 2, 'Expected outbound and inbound ROLIs');
        Boolean foundOutbound = false;
        Boolean foundInbound = false;
        for (ReturnOrderLineItem line : lines) {
            if (line.LineType__c == 'Outbound' || line.RecordType.DeveloperName == 'Outbound') {
                foundOutbound = true;
            }
            if (line.LineType__c == 'Inbound' || line.RecordType.DeveloperName == 'Inbound') {
                foundInbound = true;
            }
        }
        Assert.isTrue(foundOutbound, 'Expected outbound ROLI');
        Assert.isTrue(foundInbound, 'Expected inbound ROLI');

        WorkOrder refreshedWo = [
            SELECT Status, SubStatus__c, VendorReturnOrder__c, Shipment__c
            FROM WorkOrder
            WHERE Id = :fixture.vendorWorkOrder.Id
        ];
        Assert.areEqual('Ship to Vendor', refreshedWo.Status);
        Assert.isNull(refreshedWo.SubStatus__c);
        Assert.areEqual(vendorRoId, refreshedWo.VendorReturnOrder__c);
        Assert.areEqual(vendorShipment.Id, refreshedWo.Shipment__c);

        List<ContentDocumentLink> links = [
            SELECT ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :vendorRoId
        ];
        Assert.isFalse(links.isEmpty(), 'Expected FedEx label and/or packing slip files');
    }

    @IsTest
    static void testCreateVendorFedExShipments_happyPath_persistsTrackingAndLabel() {
        /********************************************
         * SETUP
         ********************************************/
        VendorConsolidationFixture fixture = buildVendorConsolidationFixture('FED');

        Id vendorReturnRtId = Schema.SObjectType.ReturnOrder.getRecordTypeInfosByDeveloperName()
            .get('VendorReturn')
            ?.getRecordTypeId();
        Id outboundRtId = Schema.SObjectType.ReturnOrderLineItem.getRecordTypeInfosByDeveloperName()
            .get('Outbound')
            ?.getRecordTypeId();
        Assert.isNotNull(vendorReturnRtId, 'VendorReturn RT required');
        Assert.isNotNull(outboundRtId, 'Outbound RT required');

        ReturnOrder vendorRo = new ReturnOrder(
            AccountId = fixture.vendorAccount.Id,
            SourceLocationId = fixture.repairCenter.Id,
            DestinationLocationId = fixture.repairCenter.Id,
            RecordTypeId = vendorReturnRtId,
            Status = 'Created',
            CreationSource__c = 'Salesforce',
            ReturnOrderType__c = 'Vendor',
            CustomerPO__c = 'PO-FED-1'
        );
        insert vendorRo;

        ReturnOrderLineItem outbound = new ReturnOrderLineItem(
            ReturnOrderId = vendorRo.Id,
            RecordTypeId = outboundRtId,
            QuantityReturned = 1,
            Product2Id = fixture.product.Id
        );
        outbound.put('Status__c', 'Created');
        outbound.put('LineType__c', 'Outbound');
        outbound.put('Model__c', 'FED-MODEL');
        outbound.put('SerialNumber__c', 'FED-SN-1');
        insert outbound;

        WorkOrder woUpdate = new WorkOrder(Id = fixture.vendorWorkOrder.Id);
        woUpdate.put('VendorReturnOrder__c', vendorRo.Id);
        update woUpdate;

        FedExService.testCalloutResponseMap = FedExService.buildTestSuccessResponse(
            '7949FED00002',
            Blob.valueOf('%PDF-FED-LABEL%')
        );

        Map<Id, List<Id>> shipmentMap = new Map<Id, List<Id>>{
            vendorRo.Id => new List<Id>{ fixture.vendorWorkOrder.Id }
        };

        /********************************************
         * WHEN
         ********************************************/
        try {
            Test.startTest();
            ReturnOrdersService.createVendorFedExShipments(shipmentMap);
            Test.stopTest();
        } finally {
            FedExService.testCalloutResponseMap = null;
        }

        /********************************************
         * THEN
         ********************************************/
        ReturnOrder refreshedRo = [
            SELECT ReturnOrderNumber
            FROM ReturnOrder
            WHERE Id = :vendorRo.Id
        ];
        // GW-6358: one Shipment for the shipped set; the Work Order looks up to it
        Shipment shipment = [
            SELECT Id, TrackingNumber, WorkOrder__c
            FROM Shipment
            WHERE ReturnOrderId = :vendorRo.Id
        ];
        Assert.areEqual('7949FED00002', shipment.TrackingNumber);

        WorkOrder refreshedWo = [
            SELECT Shipment__c, ParentWorkOrderId
            FROM WorkOrder
            WHERE Id = :fixture.vendorWorkOrder.Id
        ];
        Assert.areEqual(shipment.Id, refreshedWo.Shipment__c);
        Assert.areEqual(refreshedWo.ParentWorkOrderId, shipment.WorkOrder__c, 'The parent Work Order should be on the shipment');

        List<ContentVersion> files = [
            SELECT Title, PathOnClient
            FROM ContentVersion
            WHERE FirstPublishLocationId = :vendorRo.Id
            AND IsLatest = TRUE
        ];
        Assert.isTrue(files.size() >= 2, 'Expected shipping label and packing slip');
        Boolean foundLabel = false;
        Boolean foundPackingSlip = false;
        for (ContentVersion fileRow : files) {
            if (fileRow.Title != null && fileRow.Title.startsWith('Shipping Label')) {
                foundLabel = true;
            }
            if (fileRow.Title != null && fileRow.Title.startsWith('Packing Slip')) {
                foundPackingSlip = true;
            }
        }
        Assert.isTrue(foundLabel, 'Expected Shipping Label ContentVersion');
        Assert.isTrue(foundPackingSlip, 'Expected Packing Slip ContentVersion');
    }

    @IsTest
    static void testCreateVendorFedExShipments_incompleteVendorAddressThrows() {
        /********************************************
         * SETUP
         ********************************************/
        Schema.Location repairCenter = insertRepairCenterWithAddress(
            'ROS FedEx Bad Vendor RC',
            '1 Lab Rd',
            'Mentor',
            'OH',
            '44060'
        );
        Account incompleteVendor = new Account(
            Name = 'ROS FedEx Bad Vendor',
            SystemID__c = 'LEG-ROS-BV01',
            SourceSystemID__c = 'ORCL-ROS-BV01',
            OrgIDs__c = '82'
        );
        insert incompleteVendor;

        Id vendorReturnRtId = Schema.SObjectType.ReturnOrder.getRecordTypeInfosByDeveloperName()
            .get('VendorReturn')
            ?.getRecordTypeId();
        Assert.isNotNull(vendorReturnRtId, 'VendorReturn RT required');

        ReturnOrder vendorRo = new ReturnOrder(
            AccountId = incompleteVendor.Id,
            SourceLocationId = repairCenter.Id,
            DestinationLocationId = repairCenter.Id,
            RecordTypeId = vendorReturnRtId,
            Status = 'Created',
            CreationSource__c = 'Salesforce',
            ReturnOrderType__c = 'Vendor'
        );
        insert vendorRo;

        Boolean threw = false;
        try {
            Test.startTest();
            ReturnOrdersService.createVendorFedExShipments(
                new Map<Id, List<Id>>{ vendorRo.Id => new List<Id>() }
            );
            Test.stopTest();
            Assert.fail('Expected ReturnOrdersServiceException');
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('ship-to address is incomplete') ||
                    e.getMessage().contains('FedEx shipment failed'),
                e.getMessage()
            );
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void testRequestInboundShippingLabel_notFoundThrows() {
        Boolean threw = false;
        try {
            ReturnOrdersService.requestInboundShippingLabel(UserInfo.getUserId());
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('was not found') ||
                    e.getMessage().contains('Return Order'),
                e.getMessage()
            );
        }
        Assert.isTrue(threw);
    }

    // ── saveRoFormPdf / RO Form HTML (GW-1347) ────────────────────────────────

    private static final String RO_FORM_TEMPLATE_TITLE = 'Return Order North America Template';

    private static ReturnOrder createPaperworkReturnOrderWithTemplate() {
        Account account = new Account(
            Name = 'RO Paperwork Account',
            AccountNumber = '87788',
            SystemID__c = 'LEG-ROPW' + String.valueOf(Crypto.getRandomInteger()).right(6),
            SourceSystemID__c = 'TEST-ORACLE-ROPW' + String.valueOf(Crypto.getRandomInteger()).right(6),
            OrgIDs__c = '82'
        );
        insert account;

        Schema.Location repairCenter = new Schema.Location(
            Name = 'DAL',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        ReturnOrder returnOrder = new ReturnOrder(
            AccountId = account.Id,
            DestinationLocationId = repairCenter.Id,
            Status = 'Created',
            EstimateRequired__c = 'Pre-Approved',
            ReturnOrderType__c = 'Serialized',
            CustomerPO__c = 'PO-123',
            CustomerReference__c = 'REF-9',
            ShipFromStreet = '10TH AND SANSOM ST',
            ShipFromCity = 'Philadelphia',
            ShipFromStateCode = 'PA',
            ShipFromCountryCode = 'US',
            ShipFromPostalCode = '19107',
            ShipToAddress__Street__s = '20 UNIVERSITY ROAD STE 700',
            ShipToAddress__City__s = 'Cambridge',
            ShipToAddress__StateCode__s = 'MA',
            ShipToAddress__PostalCode__s = '02138',
            ShipToAddress__CountryCode__s = 'US',
            CreationSource__c = 'Salesforce'
        );
        insert returnOrder;

        Product2 product = new Product2(
            Name = 'EUS VIDEO GASTROSCOPE',
            Manufacturer__c = 'OLYMPUS',
            Model__c = 'GF-UCT180',
            IsActive = true
        );
        insert product;

        insert new ReturnOrderLineItem(
            ReturnOrderId = returnOrder.Id,
            QuantityReturned = 1,
            QuantityExpected = 1,
            SerialNumber__c = '1110484',
            Model__c = 'GF-UCT180',
            Product2Id = product.Id,
            ReportedProblem__c = 'Broken elevator',
            Disinfected__c = 'Yes, Item is Disinfected'
        );

        ContentVersion templateVersion = new ContentVersion();
        templateVersion.Title = RO_FORM_TEMPLATE_TITLE;
        templateVersion.PathOnClient = 'ReturnOrderNorthAmericaTemplate.html';
        templateVersion.VersionData = Blob.valueOf(
            '<html><body>'
            + 'SRN:{!srnNumber}|AM:{!accountManager}|Banner:{!estimateRequiredLabel}|'
            + 'Vendor:{!vendorLab}|Return:{!returnAddressLine2}|Cust:{!customerDisplay}|PO:{!poNumber}|'
            + 'Type:{!orderType}|Rows:{!repairItemRows}|Logo:{!logoUrl}|'
            + 'Barcode:{!barcodeMarkup}|HasBeen:{!reprocessHasBeenContent}|'
            + 'HasNot:{!reprocessHasNotBeenContent}'
            + '</body></html>'
        );
        insert templateVersion;

        return returnOrder;
    }

    @IsTest
    static void testBuildMergedPaperworkHtml_includesBarcode() {
        ReturnOrder returnOrder = createPaperworkReturnOrderWithTemplate();

        Test.startTest();
        String html = ReturnOrdersService.buildMergedPaperworkHtml(returnOrder.Id);
        Test.stopTest();

        Assert.isTrue(html.contains('bgcolor="#000000"'), 'Expected barcode bars in merged HTML');
        Assert.isTrue(html.contains('SRN:'), 'Expected merged SRN token');
        Assert.isTrue(
            html.contains('20 UNIVERSITY ROAD STE 700'),
            'Return Address should use the shipping address selected on the Return Order'
        );
        Assert.isFalse(
            html.contains('10TH AND SANSOM ST'),
            'Return Address should not use the standard Ship From fields'
        );
        String idBarcode = ReturnOrdersService.buildCode128BarcodeHtml(String.valueOf(returnOrder.Id));
        Assert.isTrue(
            html.contains(idBarcode.substring(0, Math.min(80, idBarcode.length()))),
            'Expected barcode markup for Return Order Id'
        );
    }

    @IsTest
    static void testSaveRoFormPdf_attachesFileToReturnOrder() {
        ReturnOrder returnOrder = createPaperworkReturnOrderWithTemplate();
        returnOrder = [
            SELECT Id, ReturnOrderNumber
            FROM ReturnOrder
            WHERE Id = :returnOrder.Id
        ];

        Test.startTest();
        Id contentVersionId = ReturnOrdersService.saveRoFormPdf(returnOrder.Id);
        Test.stopTest();

        Assert.isNotNull(contentVersionId, 'Expected ContentVersion Id');

        ContentVersion saved = [
            SELECT Id, Title, PathOnClient, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersionId
        ];
        String expectedTitle = ReturnOrdersService.roFormFileBaseName(returnOrder.ReturnOrderNumber);
        Assert.areEqual(expectedTitle, saved.Title, 'Expected RO Form title');
        Assert.isTrue(saved.PathOnClient.endsWith('.pdf'), 'Expected PDF path');

        Integer links = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :returnOrder.Id
            AND ContentDocumentId = :saved.ContentDocumentId
        ];
        Assert.areEqual(1, links, 'RO Form must be linked to the Return Order');
    }

    @IsTest
    static void testSaveRoFormPdf_nullReturnOrderId() {
        Boolean threw = false;
        try {
            ReturnOrdersService.saveRoFormPdf(null);
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('Return Order Id'),
                'Expected missing Id message'
            );
        }
        Assert.isTrue(threw, 'Expected ReturnOrdersServiceException');
    }

    @IsTest
    static void testSaveRoFormPdf_missingTemplate() {
        ReturnOrder returnOrder = createPaperworkReturnOrderWithTemplate();
        List<ContentDocument> templates = [
            SELECT Id
            FROM ContentDocument
            WHERE Title = :RO_FORM_TEMPLATE_TITLE
        ];
        delete templates;

        Boolean threw = false;
        try {
            ReturnOrdersService.saveRoFormPdf(returnOrder.Id);
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('template'),
                'Expected missing template message'
            );
        }
        Assert.isTrue(threw, 'Expected ReturnOrdersServiceException');
    }

    @IsTest
    static void testRoFormFileBaseName() {
        Assert.areEqual('RO Form RO-0183', ReturnOrdersService.roFormFileBaseName('RO-0183'));
        Assert.areEqual('RO Form RO-99', ReturnOrdersService.roFormFileBaseName('99'));
        Assert.areEqual('RO Form RO', ReturnOrdersService.roFormFileBaseName(null));
    }

    @IsTest
    static void testBuildCode128BarcodeHtml_encodesValue() {
        String html = ReturnOrdersService.buildCode128BarcodeHtml('RO-1');
        Assert.isTrue(html.contains('bgcolor="#000000"'), 'Expected barcode bars');
        Assert.isTrue(html.contains('<table'), 'Expected table markup');
    }

    @IsTest
    static void testBuildCode128BarcodeHtml_blankReturnsNbsp() {
        Assert.areEqual('&nbsp;', ReturnOrdersService.buildCode128BarcodeHtml(''));
        Assert.areEqual('&nbsp;', ReturnOrdersService.buildCode128BarcodeHtml(null));
    }

    @IsTest
    static void testBuildMergedPaperworkHtml_missingReturnOrderId() {
        Boolean threw = false;
        try {
            ReturnOrdersService.buildMergedPaperworkHtml(null);
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('Return Order Id'));
        }
        Assert.isTrue(threw, 'Expected ReturnOrdersServiceException');
    }

    @IsTest
    static void testBuildMergedPaperworkHtml_notDisinfectedBuildsHasNotBeen() {
        ReturnOrder returnOrder = createPaperworkReturnOrderWithTemplate();
        ReturnOrderLineItem lineItem = [
            SELECT Id
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrder.Id
            LIMIT 1
        ];
        lineItem.Disinfected__c = 'No, Item is not Disinfected';
        update lineItem;

        Test.startTest();
        String html = ReturnOrdersService.buildMergedPaperworkHtml(returnOrder.Id);
        Test.stopTest();

        Assert.isTrue(html.contains('HasNot:'), 'Expected HasNot token present');
        Assert.isTrue(
            html.contains('checkbox_checked') || html.contains('/resource/'),
            'Expected checked image markup for HasNot path'
        );
    }

    // ── Create RO paperwork orchestration (GW-1347) ───────────────────────────

    @IsTest
    static void testAttachCombinedPdf_savesFile() {
        Account account = new Account(
            Name = 'Combined PDF Account',
            AccountNumber = 'CMB-001',
            SystemID__c = 'LEG-CMB-001',
            SourceSystemID__c = 'TEST-ORACLE-CMB-001',
            OrgIDs__c = '82'
        );
        insert account;

        ReturnOrder returnOrderRecord = newDraftReturnOrder();
        returnOrderRecord.AccountId = account.Id;
        insert returnOrderRecord;
        returnOrderRecord = [
            SELECT Id, ReturnOrderNumber
            FROM ReturnOrder
            WHERE Id = :returnOrderRecord.Id
        ];

        String tinyPdfBase64 = EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4 combined'));

        Test.startTest();
        Id contentVersionId = ReturnOrdersService.attachCombinedPdf(
            returnOrderRecord.Id,
            tinyPdfBase64,
            returnOrderRecord.ReturnOrderNumber
        );
        Test.stopTest();

        Assert.isNotNull(contentVersionId);
        ContentVersion saved = [
            SELECT Title, FirstPublishLocationId
            FROM ContentVersion
            WHERE Id = :contentVersionId
        ];
        Assert.isTrue(
            saved.Title.startsWith('RO Form and Shipping Label'),
            'Combined file title should use expected prefix'
        );
        Assert.areEqual(returnOrderRecord.Id, saved.FirstPublishLocationId);
    }

    @IsTest
    static void testGeneratePaperworkForReturnOrder_whenNoSelectedShippingAddress_setsLabelError() {
        Account account = new Account(
            Name = 'No Bill To Account',
            AccountNumber = 'CMB-002',
            SystemID__c = 'LEG-CMB-002',
            SourceSystemID__c = 'TEST-ORACLE-CMB-002',
            OrgIDs__c = '82',
            BillingStreet = '500 Pasteur Drive',
            BillingCity = 'Stanford',
            BillingStateCode = 'CA',
            BillingPostalCode = '94305',
            BillingCountryCode = 'US'
        );
        insert account;

        Schema.Location repairCenter = new Schema.Location(
            Name = 'Paperwork RC',
            LocationType = 'Repair Center',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert repairCenter;

        ReturnOrder returnOrderRecord = newDraftReturnOrder();
        returnOrderRecord.AccountId = account.Id;
        returnOrderRecord.DestinationLocationId = repairCenter.Id;
        insert returnOrderRecord;

        Test.startTest();
        ReturnOrdersService.PaperworkResult result =
            ReturnOrdersService.generatePaperworkForReturnOrder(returnOrderRecord.Id);
        Test.stopTest();

        Assert.areEqual(returnOrderRecord.Id, result.returnOrderId);
        Assert.isFalse(result.shippingLabelCreated);
        Assert.isTrue(
            String.isNotBlank(result.shippingLabelError),
            'Missing selected shipping address should surface a shipping label error'
        );
        Assert.isTrue(
            result.shippingLabelError.contains('selected shipping address'),
            'Error should mention the selected shipping address: ' + result.shippingLabelError
        );
    }

    @IsTest
    static void testAttachCombinedPdf_requiresPayload() {
        Boolean threw = false;
        try {
            ReturnOrdersService.attachCombinedPdf(UserInfo.getUserId(), null, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Blank PDF payload should throw AuraHandledException');
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private class VendorConsolidationFixture {
        Account customerAccount;
        Account vendorAccount;
        Schema.Location repairCenter;
        Product2 product;
        WorkOrder vendorWorkOrder;
        WorkOrderLineItem vendorLineItem;
    }

    private static VendorConsolidationFixture buildVendorConsolidationFixture(String key) {
        String shortKey = key == null ? 'X' : key.left(3);
        VendorConsolidationFixture fixture = new VendorConsolidationFixture();

        fixture.customerAccount = new Account(
            Name = 'ROS Cust ' + shortKey,
            SystemID__c = ('LEG-RSC' + shortKey).left(15),
            SourceSystemID__c = ('ORCL-RSC' + shortKey).left(40),
            OrgIDs__c = '82'
        );
        fixture.vendorAccount = new Account(
            Name = 'ROS Vend ' + shortKey,
            SystemID__c = ('LEG-RSV' + shortKey).left(15),
            SourceSystemID__c = ('ORCL-RSV' + shortKey).left(40),
            OrgIDs__c = '82',
            BillingStreet = '200 Vendor Blvd',
            BillingCity = 'Cleveland',
            BillingStateCode = 'OH',
            BillingPostalCode = '44114',
            BillingCountryCode = 'US'
        );
        insert new List<Account>{ fixture.customerAccount, fixture.vendorAccount };

        fixture.repairCenter = insertRepairCenterWithAddress(
            'ROS RC ' + shortKey,
            '5960 Heisley Road',
            'Mentor',
            'OH',
            '44060'
        );
        linkServiceResourceToRepairCenter(fixture.repairCenter.Id);

        fixture.product = new Product2(
            Name = 'ROS Product ' + shortKey,
            ProductCode = ('ROS-' + shortKey).left(15),
            IsActive = true
        );
        insert fixture.product;

        Id pricebookId = Test.getStandardPricebookId();
        insert new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = fixture.product.Id,
            UnitPrice = 1,
            IsActive = true
        );
        PricebookEntry pbe = [
            SELECT Id
            FROM PricebookEntry
            WHERE Product2Id = :fixture.product.Id
            LIMIT 1
        ];

        Id otherRtId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterVendor')
            ?.getRecordTypeId();
        Assert.isNotNull(otherRtId, 'RepairCenterVendor RT required');

        fixture.vendorWorkOrder = new WorkOrder(
            Subject = 'ROS Vendor WO ' + shortKey,
            Status = 'Received',
            AccountId = fixture.customerAccount.Id,
            RecordTypeId = otherRtId,
            Pricebook2Id = pricebookId,
            Vendor__c = fixture.vendorAccount.Id,
            InstructionsToVendor__c = 'Ship carefully',
            VendorNotes__c = 'Handle as fragile',
            VendorReferenceNumber__c = 'VREF-' + shortKey,
            VendorCost__c = 25,
            QuantityReceived__c = 1
        );
        fixture.vendorWorkOrder.put('SubStatus__c', 'Ship to Vendor');
        fixture.vendorWorkOrder.put('RepairCenter__c', fixture.repairCenter.Id);
        fixture.vendorWorkOrder.put('CustomerPO__c', 'PO-' + shortKey);
        insert fixture.vendorWorkOrder;

        fixture.vendorLineItem = new WorkOrderLineItem(
            WorkOrderId = fixture.vendorWorkOrder.Id,
            Subject = 'ROS Vendor Line ' + shortKey,
            Quantity = 1,
            PricebookEntryId = pbe.Id
        );
        fixture.vendorLineItem.put('SerialNumber__c', 'SN-' + shortKey);
        fixture.vendorLineItem.put('Model__c', 'MDL-' + shortKey);
        insert fixture.vendorLineItem;

        return fixture;
    }

    private static Schema.Location insertRepairCenterWithAddress(
        String name,
        String street,
        String city,
        String stateCode,
        String postalCode
    ) {
        Schema.Location repairCenter = new Schema.Location(
            Name = name,
            LocationType = 'Repair Center',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert repairCenter;

        Schema.SObjectType addressType = Schema.getGlobalDescribe().get('Address');
        SObject addressRecord = addressType.newSObject();
        addressRecord.put('ParentId', repairCenter.Id);
        addressRecord.put('LocationType', 'Repair Center');
        addressRecord.put('Street', street);
        addressRecord.put('City', city);
        addressRecord.put('StateCode', stateCode);
        addressRecord.put('PostalCode', postalCode);
        addressRecord.put('CountryCode', 'US');
        insert addressRecord;

        repairCenter.VisitorAddressId = (Id) addressRecord.get('Id');
        update repairCenter;
        return repairCenter;
    }

    private static void linkServiceResourceToRepairCenter(Id repairCenterId) {
        deactivateServiceResourcesForCurrentUser();

        ServiceResource resource = new ServiceResource(
            Name = 'ROS Service Resource',
            RelatedRecordId = UserInfo.getUserId(),
            LocationId = repairCenterId,
            IsActive = true,
            ResourceType = 'T'
        );
        insert resource;
        resource.put('RepairCenter__c', repairCenterId);
        update resource;
    }

    private static void deactivateServiceResourcesForCurrentUser() {
        List<ServiceResource> resources = [
            SELECT Id, IsActive
            FROM ServiceResource
            WHERE RelatedRecordId = :UserInfo.getUserId()
            AND IsActive = TRUE
        ];
        for (ServiceResource resource : resources) {
            resource.IsActive = false;
        }
        if (!resources.isEmpty()) {
            update resources;
        }
    }

    private static User buildTestUser() {
        adb_User builder = new adb_User();
        builder.persist();
        return (User) builder.record;
    }

    /**
     * @description Draft Return Order from adb_ReturnOrder, keeping only createable fields.
     *              The builder loads defaults such as StatusCategory, which user-mode DML rejects.
     * @return Unsaved Draft Return Order
     */
    private static ReturnOrder newDraftReturnOrder() {
        ReturnOrder builderRecord = (ReturnOrder) new adb_ReturnOrder().status('Draft').record;
        Map<String, SObjectField> fieldMap = Schema.SObjectType.ReturnOrder.fields.getMap();
        ReturnOrder draftReturnOrder = new ReturnOrder();
        for (String fieldName : builderRecord.getPopulatedFieldsAsMap().keySet()) {
            SObjectField field = fieldMap.get(fieldName);
            if (field != null && field.getDescribe().isCreateable()) {
                draftReturnOrder.put(field, builderRecord.get(fieldName));
            }
        }
        return draftReturnOrder;
    }

    /**
     * @description Covers catch wrappers via simulateGenericException / simulateFedExException.
     */
    @IsTest
    static void testSimulatedExceptions_coverServiceCatchBlocks() {
        Id fakeRoId = Schema.SObjectType.ReturnOrder.getKeyPrefix() + '000000000001AAA';
        Integer caught = 0;

        ReturnOrdersService.simulateGenericException = true;
        try {
            ReturnOrdersService.createReturnOrders(
                new List<ReturnOrder>{ new ReturnOrder(Status = 'Draft') }
            );
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            caught++;
        }
        try {
            ReturnOrdersService.updateReturnOrders(
                new List<ReturnOrder>{ new ReturnOrder(Id = fakeRoId, Status = 'Draft') }
            );
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            caught++;
        }
        try {
            ReturnOrdersService.deleteReturnOrders(new Set<Id>{ fakeRoId });
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            caught++;
        }
        try {
            ReturnOrdersService.getReturnOrdersById(new Set<Id>{ fakeRoId });
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            caught++;
        }
        try {
            ReturnOrdersService.requestInboundShippingLabel(fakeRoId);
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            caught++;
        }
        try {
            ReturnOrdersService.saveRoFormPdf(fakeRoId);
        } catch (Exception e) {
            caught++;
        }
        try {
            ReturnOrdersService.generatePaperworkForReturnOrder(fakeRoId);
        } catch (Exception e) {
            caught++;
        }
        try {
            ReturnOrdersService.attachCombinedPdf(fakeRoId, 'AAAA', 'RO-1');
        } catch (Exception e) {
            caught++;
        }
        try {
            ReturnOrdersService.completeVendorShipment(new List<Id>{ UserInfo.getUserId() });
        } catch (Exception e) {
            caught++;
        }
        ReturnOrdersService.simulateGenericException = false;

        ReturnOrdersService.simulateFedExException = true;
        try {
            ReturnOrdersService.requestInboundShippingLabel(fakeRoId);
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            caught++;
        }
        ReturnOrdersService.simulateFedExException = false;

        Assert.isTrue(caught >= 8, 'Expected simulated catch paths, got ' + caught);
    }

    @IsTest
    static void testCreateSingleReturnOrder_serialized_createsOrderAndLine() {
        CreateOrderFixture fixture = insertCreateOrderFixture();
        Map<String, Object> header = createOrderHeader(fixture, true);
        List<Object> lines = new List<Object>{ serializedCreateLine(fixture) };

        Test.startTest();
        ReturnOrdersService.GroupedReturnOrderResult created =
            ReturnOrdersService.createSingleReturnOrder(
                JSON.serialize(header),
                JSON.serialize(lines)
            );
        Test.stopTest();

        Assert.isNotNull(created.returnOrderId, 'Serialized create should return a Return Order Id');
        Assert.areEqual(1, created.lineCount);
        Assert.isTrue(String.isNotBlank(created.returnOrderNumber));

        ReturnOrder createdOrder = [
            SELECT AccountId, Status, OperatingUnit__c, DestinationLocationId, ReturnOrderType__c
            FROM ReturnOrder
            WHERE Id = :created.returnOrderId
        ];
        Assert.areEqual(fixture.accountId, createdOrder.AccountId);
        Assert.areEqual('Created', createdOrder.Status);
        Assert.areEqual('82', createdOrder.OperatingUnit__c);
        Assert.areEqual(fixture.repairCenterId, createdOrder.DestinationLocationId);
        Assert.areEqual('Serialized', createdOrder.ReturnOrderType__c);

        ReturnOrderLineItem lineItem = [
            SELECT LineType__c, ReportedProblem__c, ProductLine__c, Model__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :created.returnOrderId
        ];
        Assert.areEqual('Serialized', lineItem.LineType__c);
        Assert.areEqual('Surgical', lineItem.ProductLine__c);
        Assert.areEqual('TEST MODEL', lineItem.Model__c);
        Assert.areEqual('Unit not powering on', lineItem.ReportedProblem__c);
    }

    @IsTest
    static void testCreateGroupedReturnOrders_createsOneOrderPerGroup() {
        CreateOrderFixture fixture = insertCreateOrderFixture();
        Map<String, Object> header = createOrderHeader(fixture, false);
        List<Object> groups = new List<Object>{
            createOrderGroup(fixture, new List<Object>{ serializedCreateLine(fixture) }, null)
        };

        Test.startTest();
        List<ReturnOrdersService.GroupedReturnOrderResult> createdOrders =
            ReturnOrdersService.createGroupedReturnOrders(
                JSON.serialize(header),
                JSON.serialize(groups)
            );
        Test.stopTest();

        Assert.areEqual(1, createdOrders.size());
        Assert.isNotNull(createdOrders[0].returnOrderId);
        Assert.areEqual(1, [
            SELECT COUNT()
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :createdOrders[0].returnOrderId
        ]);
    }

    @IsTest
    static void testCreateGroupedReturnOrders_instruments_appliesOrderHeader() {
        CreateOrderFixture fixture = insertCreateOrderFixture();
        ContentVersion contentVersion = new ContentVersion(
            Title = 'ROS Mod Form',
            PathOnClient = 'ros-mod.pdf',
            VersionData = Blob.valueOf('mod form')
        );
        insert contentVersion;
        contentVersion = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersion.Id
        ];

        Map<String, Object> line = new Map<String, Object>{
            'lineType' => 'instruments',
            'serialized' => false,
            'product2Id' => fixture.productId,
            'productLine' => 'INSTRUMENT',
            'itemDescription' => 'Tray insert',
            'disinfected' => disinfectedYesValue(),
            'departmentId' => fixture.departmentId,
            'reportedProblem' => 'Tray damaged',
            'modRequest' => true,
            'quantityReturned' => 2,
            'modFormContentDocumentIds' => new List<String>{
                String.valueOf(contentVersion.ContentDocumentId)
            }
        };
        Map<String, Object> orderHeader = new Map<String, Object>{
            'contactId' => String.valueOf(fixture.contactId),
            'estimateContactId' => String.valueOf(fixture.contactId),
            'estimateRequired' => 'Estimate Required',
            'modRequestContactId' => String.valueOf(fixture.contactId),
            'hasModRequest' => true,
            'repairWarranty' => 'Yes',
            'warrantyNotes' => 'Covered under prior repair',
            'customerPo' => 'PO-INST-1',
            'customerReference' => 'REF-HEADER-1',
            'hospitalReferencedTrayName' => 'Tray Header A'
        };

        Test.startTest();
        List<ReturnOrdersService.GroupedReturnOrderResult> createdOrders =
            ReturnOrdersService.createGroupedReturnOrders(
                JSON.serialize(createOrderHeader(fixture, false)),
                JSON.serialize(new List<Object>{
                    createOrderGroup(fixture, new List<Object>{ line }, orderHeader)
                })
            );
        Test.stopTest();

        Assert.areEqual(1, createdOrders.size());
        Assert.areEqual('Instruments', createdOrders[0].returnOrderType);

        ReturnOrder createdOrder = [
            SELECT ContactId, EstimateContact__c, EstimateRequired__c, ModRequestContact__c,
                CustomerPO__c, HospitalReferencedTrayName__c, WarrantyNotes__c
            FROM ReturnOrder
            WHERE Id = :createdOrders[0].returnOrderId
        ];
        Assert.areEqual(fixture.contactId, createdOrder.ContactId);
        Assert.areEqual(fixture.contactId, createdOrder.EstimateContact__c);
        Assert.areEqual('Estimate Required', createdOrder.EstimateRequired__c);
        Assert.areEqual(fixture.contactId, createdOrder.ModRequestContact__c);
        Assert.areEqual('PO-INST-1', createdOrder.CustomerPO__c);
        Assert.areEqual('Tray Header A', createdOrder.HospitalReferencedTrayName__c);
        Assert.areEqual('Covered under prior repair', createdOrder.WarrantyNotes__c);

        ReturnOrderLineItem lineItem = [
            SELECT Id, ModRequest__c, Contact__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :createdOrder.Id
        ];
        Assert.areEqual(true, lineItem.ModRequest__c);
        Assert.areEqual(fixture.contactId, lineItem.Contact__c);
        Assert.areEqual(1, [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :lineItem.Id
            AND ContentDocumentId = :contentVersion.ContentDocumentId
        ]);
    }

    @IsTest
    static void testCreateSingleReturnOrder_otherLines_mapProductLineAndType() {
        CreateOrderFixture fixture = insertCreateOrderFixture();
        Map<String, Object> header = createOrderHeader(fixture, true);
        List<Object> serializedOther = new List<Object>{
            new Map<String, Object>{
                'lineType' => 'other-serialized',
                'serialized' => true,
                'product2Id' => fixture.productId,
                'itemType' => 'Phaco Handpiece',
                'serialNumber' => 'phaco-100',
                'model' => 'phaco-model',
                'departmentId' => fixture.departmentId,
                'contactId' => fixture.contactId,
                'reportedProblem' => 'Failed seal',
                'disinfected' => disinfectedYesValue(),
                'estimateRequired' => 'Pre-Approved',
                'quantityReturned' => 1
            }
        };

        Test.startTest();
        ReturnOrdersService.GroupedReturnOrderResult serializedCreated =
            ReturnOrdersService.createSingleReturnOrder(
                JSON.serialize(header),
                JSON.serialize(serializedOther)
            );
        List<Object> nonSerializedOther = new List<Object>{
            new Map<String, Object>{
                'lineType' => 'other-non-serialized',
                'serialized' => false,
                'product2Id' => fixture.productId,
                'itemType' => 'Cable: Fiber Optic',
                'itemDescription' => 'Fiber cable',
                'departmentId' => fixture.departmentId,
                'contactId' => fixture.contactId,
                'reportedProblem' => 'Missing cable',
                'disinfected' => disinfectedYesValue(),
                'estimateRequired' => 'Pre-Approved',
                'quantityReturned' => 3
            }
        };
        ReturnOrdersService.GroupedReturnOrderResult nonSerializedCreated =
            ReturnOrdersService.createSingleReturnOrder(
                JSON.serialize(header),
                JSON.serialize(nonSerializedOther)
            );
        Test.stopTest();

        ReturnOrder serializedOrder = [
            SELECT ReturnOrderType__c
            FROM ReturnOrder
            WHERE Id = :serializedCreated.returnOrderId
        ];
        ReturnOrderLineItem serializedLine = [
            SELECT LineType__c, SerialNumber__c, ProductLine__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :serializedCreated.returnOrderId
        ];
        Assert.areEqual('Other (Serialized)', serializedOrder.ReturnOrderType__c);
        Assert.areEqual('Other (Serialized)', serializedLine.LineType__c);
        Assert.areEqual('PHACO-100', serializedLine.SerialNumber__c);
        Assert.isTrue(String.isNotBlank(serializedLine.ProductLine__c));

        ReturnOrder nonSerializedOrder = [
            SELECT ReturnOrderType__c
            FROM ReturnOrder
            WHERE Id = :nonSerializedCreated.returnOrderId
        ];
        ReturnOrderLineItem nonSerializedLine = [
            SELECT LineType__c, QuantityReturned, ProductLine__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :nonSerializedCreated.returnOrderId
        ];
        Assert.areEqual('Other (Non-Serialized)', nonSerializedOrder.ReturnOrderType__c);
        Assert.areEqual('Other (Non-Serialized)', nonSerializedLine.LineType__c);
        Assert.areEqual(3, nonSerializedLine.QuantityReturned);
        Assert.isTrue(String.isNotBlank(nonSerializedLine.ProductLine__c));
    }

    @IsTest
    static void testCreateSingleReturnOrder_flexibleScope_usesDefaultQuantity() {
        CreateOrderFixture fixture = insertCreateOrderFixture();
        List<Object> lines = new List<Object>{
            new Map<String, Object>{
                'serialized' => true,
                'product2Id' => fixture.productId,
                'productLine' => 'FLEXIBLE SCOPE',
                'model' => 'scope-1',
                'departmentId' => fixture.departmentId,
                'contactId' => fixture.contactId,
                'reportedProblem' => 'Image drift',
                'disinfected' => disinfectedYesValue(),
                'estimateRequired' => 'Pre-Approved',
                'quantityReturned' => 5
            }
        };

        Test.startTest();
        ReturnOrdersService.GroupedReturnOrderResult created =
            ReturnOrdersService.createSingleReturnOrder(
                JSON.serialize(createOrderHeader(fixture, true)),
                JSON.serialize(lines)
            );
        Test.stopTest();

        ReturnOrderLineItem lineItem = [
            SELECT QuantityReturned, ProductLine__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :created.returnOrderId
        ];
        Assert.areEqual('FLEXIBLE SCOPE', lineItem.ProductLine__c);
        Assert.areEqual(1, lineItem.QuantityReturned);
    }

    @IsTest
    static void testCreateGroupedReturnOrders_whenNoGroups_throws() {
        CreateOrderFixture fixture = insertCreateOrderFixture();

        Test.startTest();
        try {
            ReturnOrdersService.createGroupedReturnOrders(
                JSON.serialize(createOrderHeader(fixture, true)),
                '[]'
            );
            Assert.fail('Empty groups should throw');
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            Assert.isTrue(e.getMessage().contains('No return orders to create'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateGroupedReturnOrders_whenRepairCenterMissing_throws() {
        CreateOrderFixture fixture = insertCreateOrderFixture();
        Map<String, Object> groupPayload = new Map<String, Object>{
            'groupKey' => 'missing-center',
            'requiresRepairCenterSelection' => true,
            'lineItemsJson' => JSON.serialize(new List<Object>{ serializedCreateLine(fixture) })
        };

        Test.startTest();
        try {
            ReturnOrdersService.createGroupedReturnOrders(
                JSON.serialize(createOrderHeader(fixture, false)),
                JSON.serialize(new List<Object>{ groupPayload })
            );
            Assert.fail('Missing repair center should throw');
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            Assert.isTrue(e.getMessage().contains('Select a repair center'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateSingleReturnOrder_whenAccountMissing_throws() {
        Test.startTest();
        try {
            ReturnOrdersService.createSingleReturnOrder(
                JSON.serialize(new Map<String, Object>{ 'operatingUnit' => '82' }),
                '[]'
            );
            Assert.fail('Missing account should throw');
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            Assert.isTrue(e.getMessage().contains('Account is required'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateSingleReturnOrder_whenOperatingUnitMissing_throws() {
        Account account = new Account(
            Name = 'ROS No OU Account',
            SystemID__c = 'LEG-ROS-NOOU',
            SourceSystemID__c = 'TEST-ROS-NOOU'
        );
        insert account;

        Test.startTest();
        try {
            ReturnOrdersService.createSingleReturnOrder(
                JSON.serialize(new Map<String, Object>{ 'accountId' => account.Id }),
                '[]'
            );
            Assert.fail('Missing operating unit should throw');
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            Assert.isTrue(e.getMessage().contains('Operating Unit is required'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateGroupedReturnOrders_whenJsonInvalid_throws() {
        Test.startTest();
        try {
            ReturnOrdersService.createGroupedReturnOrders('{', null);
            Assert.fail('Invalid JSON should throw');
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            Assert.isTrue(e.getMessage().contains('Error creating return orders'));
        }
        Test.stopTest();
    }

    // ── GW-5492 receiving helpers ─────────────────────────────────────────────

    @IsTest
    static void testLinkWorkOrderForReceiving_WhenIdsProvided_SetsLookup() {
        ReceivingFixture fixture = insertReceivingFixture(1);
        WorkOrder workOrder = new WorkOrder(
            Subject = 'ROS Receiving Link WO',
            Status = 'Received',
            AccountId = fixture.accountId
        );
        insert workOrder;

        Test.startTest();
        ReturnOrdersService.linkWorkOrderForReceiving(null, workOrder.Id);
        ReturnOrdersService.linkWorkOrderForReceiving(fixture.returnOrderId, null);
        ReturnOrdersService.linkWorkOrderForReceiving(fixture.returnOrderId, workOrder.Id);
        Test.stopTest();

        ReturnOrder refreshed = [
            SELECT WorkOrder__c
            FROM ReturnOrder
            WHERE Id = :fixture.returnOrderId
        ];
        Assert.areEqual(workOrder.Id, refreshed.WorkOrder__c);
    }

    @IsTest
    static void testSyncReceivingWorkOrderCount_WhenWorkOrdersExist_UpdatesCount() {
        ReceivingFixture fixture = insertReceivingFixture(1);
        WorkOrder workOrder = new WorkOrder(
            Subject = 'ROS Receiving Count WO',
            Status = 'Received',
            AccountId = fixture.accountId
        );
        workOrder.put('ReturnOrder__c', fixture.returnOrderId);
        insert workOrder;

        Test.startTest();
        ReturnOrdersService.syncReceivingWorkOrderCount(null);
        ReturnOrdersService.syncReceivingWorkOrderCount(fixture.returnOrderId);
        Test.stopTest();

        ReturnOrder refreshed = [
            SELECT WOCount__c
            FROM ReturnOrder
            WHERE Id = :fixture.returnOrderId
        ];
        Assert.areEqual(1, refreshed.WOCount__c);
    }

    @IsTest
    static void testSetQuantityReceivedForReceiving_WhenValid_UpdatesQuantity() {
        ReceivingFixture fixture = insertReceivingFixture(1);

        Test.startTest();
        ReturnOrdersService.setQuantityReceivedForReceiving(null, 3);
        ReturnOrdersService.setQuantityReceivedForReceiving(fixture.returnOrderId, null);
        ReturnOrdersService.setQuantityReceivedForReceiving(fixture.returnOrderId, 3);
        Test.stopTest();

        ReturnOrder refreshed = [
            SELECT QuantityReceived__c
            FROM ReturnOrder
            WHERE Id = :fixture.returnOrderId
        ];
        Assert.areEqual(3, refreshed.QuantityReceived__c);
    }

    @IsTest
    static void testMarkReturnOrderReceivedIfComplete_WhenNoCreatedLines_SetsReceived() {
        ReceivingFixture openFixture = insertReceivingFixture(1);
        ReceivingFixture completeFixture = insertReceivingFixture(1);
        update new ReturnOrderLineItem(
            Id = completeFixture.lineItemIds[0],
            Status__c = 'Received'
        );

        Test.startTest();
        Boolean nullResult = ReturnOrdersService.markReturnOrderReceivedIfComplete(null);
        Boolean stillOpen = ReturnOrdersService.markReturnOrderReceivedIfComplete(
            openFixture.returnOrderId
        );
        Boolean completed = ReturnOrdersService.markReturnOrderReceivedIfComplete(
            completeFixture.returnOrderId
        );
        Test.stopTest();

        Assert.isFalse(nullResult);
        Assert.isFalse(stillOpen, 'Created lines should block Received status');
        Assert.isTrue(completed);
        ReturnOrder refreshed = [
            SELECT Status
            FROM ReturnOrder
            WHERE Id = :completeFixture.returnOrderId
        ];
        Assert.areEqual('Received', refreshed.Status);
    }

    @IsTest
    static void testRedirectLinesForReceiving_WhenValid_ClonesAndMarksRedirected() {
        ReceivingFixture fixture = insertReceivingFixture(1);
        Schema.Location destinationRepairCenter = new Schema.Location(
            Name = 'ROS Redirect Destination RC',
            LocationType = 'Repair Center'
        );
        insert destinationRepairCenter;

        Test.startTest();
        ReturnOrdersService.ReceivingRedirectResult viaWrapper =
            ReturnOrdersService.redirectLinesForReceiving(
                fixture.returnOrderId,
                new Set<Id>{ fixture.lineItemIds[0] },
                destinationRepairCenter.Id,
                'Move to alternate RC'
            );
        Test.stopTest();

        Assert.isNotNull(viaWrapper.returnOrderId);
        Assert.isNotNull(viaWrapper.returnOrderNumber);
        Assert.isTrue(
            viaWrapper.sourceReturnOrderFullyRedirected,
            'Single Created line redirect should fully redirect source'
        );

        ReturnOrderLineItem sourceLine = [
            SELECT Status__c
            FROM ReturnOrderLineItem
            WHERE Id = :fixture.lineItemIds[0]
        ];
        Assert.areEqual('Redirected', sourceLine.Status__c);

        ReturnOrder sourceOrder = [
            SELECT Status, ParentReturnOrder__c
            FROM ReturnOrder
            WHERE Id = :fixture.returnOrderId
        ];
        Assert.areEqual('Redirected', sourceOrder.Status);

        ReturnOrder clonedOrder = [
            SELECT ParentReturnOrder__c, DestinationLocationId, Status, Description
            FROM ReturnOrder
            WHERE Id = :viaWrapper.returnOrderId
        ];
        Assert.areEqual(fixture.returnOrderId, clonedOrder.ParentReturnOrder__c);
        Assert.areEqual(destinationRepairCenter.Id, clonedOrder.DestinationLocationId);
        Assert.areEqual('Created', clonedOrder.Status);
        Assert.isTrue(
            clonedOrder.Description != null &&
                clonedOrder.Description.contains('Move to alternate RC'),
            'Redirection notes should append to description'
        );

        List<ReturnOrderLineItem> clonedLines = [
            SELECT Status__c, ParentROLI__c, DestinationLocationId
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :viaWrapper.returnOrderId
        ];
        Assert.areEqual(1, clonedLines.size());
        Assert.areEqual('Created', clonedLines[0].Status__c);
        Assert.areEqual(fixture.lineItemIds[0], clonedLines[0].ParentROLI__c);
        Assert.areEqual(destinationRepairCenter.Id, clonedLines[0].DestinationLocationId);
    }

    @IsTest
    static void testRedirectLinesForReceiving_WhenMissing_Throws() {
        ReceivingFixture fixture = insertReceivingFixture(1);
        Boolean missingRo = false;
        Boolean missingLine = false;

        try {
            ReturnOrdersService.redirectLinesForReceiving(
                UserInfo.getUserId(),
                new Set<Id>{ fixture.lineItemIds[0] },
                fixture.repairCenterId,
                null
            );
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            missingRo = e.getMessage().contains('Return Order was not found');
        }
        try {
            ReturnOrdersService.redirectLinesForReceiving(
                fixture.returnOrderId,
                new Set<Id>{ UserInfo.getUserId() },
                fixture.repairCenterId,
                null
            );
        } catch (ReturnOrdersService.ReturnOrdersServiceException e) {
            missingLine = e.getMessage().contains('Return Order Line Item was not found');
        }

        Assert.isTrue(missingRo);
        Assert.isTrue(missingLine);
    }

    private class ReceivingFixture {
        Id accountId;
        Id returnOrderId;
        Id repairCenterId;
        List<Id> lineItemIds;
    }

    private static ReceivingFixture insertReceivingFixture(Integer lineCount) {
        String uniqueSuffix = String.valueOf(Math.abs(Crypto.getRandomInteger())).right(8);
        Account account = new Account(
            Name = 'ROS Receiving Account',
            SystemID__c = ('ROS' + uniqueSuffix).left(15),
            SourceSystemID__c = ('TEST-ROS-RECV-' + uniqueSuffix).left(40),
            OrgIDs__c = '82'
        );
        insert account;

        Product2 product = new Product2(
            Name = 'ROS Receiving Product',
            IsActive = true
        );
        insert product;

        Schema.Location repairCenter = new Schema.Location(
            Name = 'ROS Receiving Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        // Match working anon-apex / receiving test shape; Status__c defaults to Created.
        ReturnOrder returnOrder = new ReturnOrder(
            AccountId = account.Id,
            Status = 'Created',
            OperatingUnit__c = '82',
            ReturnOrderType__c = 'Serialized',
            DestinationLocationId = repairCenter.Id
        );
        insert returnOrder;

        List<ReturnOrderLineItem> lines = new List<ReturnOrderLineItem>();
        for (Integer i = 0; i < lineCount; i++) {
            lines.add(
                new ReturnOrderLineItem(
                    ReturnOrderId = returnOrder.Id,
                    Product2Id = product.Id,
                    QuantityReturned = 1
                )
            );
        }
        insert lines;

        ReceivingFixture fixture = new ReceivingFixture();
        fixture.accountId = account.Id;
        fixture.returnOrderId = returnOrder.Id;
        fixture.repairCenterId = repairCenter.Id;
        fixture.lineItemIds = new List<Id>(new Map<Id, ReturnOrderLineItem>(lines).keySet());
        return fixture;
    }

    private class CreateOrderFixture {
        Id accountId;
        Id contactId;
        Id departmentId;
        Id productId;
        Id repairCenterId;
    }

    private static CreateOrderFixture insertCreateOrderFixture() {
        Account account = new Account(
            Name = 'ROS Create Order Account',
            SystemID__c = 'LEG-ROS-CO',
            SourceSystemID__c = 'TEST-ROS-CO',
            OrgIDs__c = '82'
        );
        insert account;
        Contact contact = new Contact(
            FirstName = 'ROS',
            LastName = 'Create',
            Email = 'ros.create@example.com',
            AccountId = account.Id
        );
        insert contact;
        Department__c department = new Department__c(Name = 'ROS Surgery');
        insert department;
        Product2 product = new Product2(
            Name = 'ROS Create Product',
            ProductType__c = 'Service Asset',
            ProductLine__c = 'Surgical',
            IsActive = true
        );
        insert product;
        Schema.Location repairCenter = new Schema.Location(
            Name = 'ROS Create Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        CreateOrderFixture fixture = new CreateOrderFixture();
        fixture.accountId = account.Id;
        fixture.contactId = contact.Id;
        fixture.departmentId = department.Id;
        fixture.productId = product.Id;
        fixture.repairCenterId = repairCenter.Id;
        return fixture;
    }

    private static Map<String, Object> createOrderHeader(
        CreateOrderFixture fixture,
        Boolean includeRepairCenter
    ) {
        Map<String, Object> header = new Map<String, Object>{
            'accountId' => fixture.accountId,
            'operatingUnit' => '82',
            'creationSource' => 'Salesforce',
            'salesRepId' => UserInfo.getUserId()
        };
        if (includeRepairCenter) {
            header.put('repairCenterId', fixture.repairCenterId);
        }
        return header;
    }

    private static Map<String, Object> serializedCreateLine(CreateOrderFixture fixture) {
        return new Map<String, Object>{
            'lineType' => 'serialized',
            'serialized' => true,
            'product2Id' => fixture.productId,
            'model' => 'Test Model',
            'departmentId' => fixture.departmentId,
            'disinfected' => disinfectedYesValue(),
            'contactId' => fixture.contactId,
            'estimateRequired' => 'Pre-Approved',
            'productLine' => 'Surgical',
            'reportedProblem' => 'Unit not powering on',
            'quantityReturned' => 1
        };
    }

    private static Map<String, Object> createOrderGroup(
        CreateOrderFixture fixture,
        List<Object> lines,
        Map<String, Object> orderHeader
    ) {
        Map<String, Object> groupPayload = new Map<String, Object>{
            'groupKey' => 'ros-group',
            'repairCenterId' => String.valueOf(fixture.repairCenterId),
            'requiresRepairCenterSelection' => false,
            'lineItemsJson' => JSON.serialize(lines)
        };
        if (orderHeader != null) {
            groupPayload.put('orderHeader', orderHeader);
        }
        return groupPayload;
    }

    private static String disinfectedYesValue() {
        for (Schema.PicklistEntry entry : ReturnOrderLineItem.Disinfected__c.getDescribe()
            .getPicklistValues()) {
            if (entry.isActive() && entry.getValue().toLowerCase().startsWith('yes')) {
                return entry.getValue();
            }
        }
        return 'Yes, Item is Disinfected';
    }
}