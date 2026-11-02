/**
 * @description Tests for ReturnOrderReceivingController.
 */
@IsTest(isParallel=false)
private class ReturnOrderReceivingControllerTest {

    private static void assignPermissionSetIfNeeded(String permissionSetName) {
        List<PermissionSet> permissionSets = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :permissionSetName
            LIMIT 1
        ];
        if (permissionSets.isEmpty()) {
            return;
        }

        List<PermissionSetAssignment> existingAssignments = [
            SELECT Id
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
            AND PermissionSetId = :permissionSets[0].Id
            LIMIT 1
        ];
        if (existingAssignments.isEmpty()) {
            new adb_PermissionSetAssignment()
                .assigneeId(UserInfo.getUserId())
                .permissionSetId(permissionSets[0].Id)
                .persist();
        }
    }

    @TestSetup
    static void setupData() {
        assignPermissionSetIfNeeded('System_Administrator');
        assignPermissionSetIfNeeded('ProcessReturnOrders');

        User runAsUser = [
            SELECT Id
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        System.runAs(runAsUser) {
            createTestData();
        }
    }

    private static String resolveDisinfectedNoValueForTest() {
        for (Schema.PicklistEntry entry : ReturnOrderLineItem.Disinfected__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue().toLowerCase().startsWith('no')) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static Pricebook2 ensureDefaultPricebookForTest(Id productId) {
        ReturnOrderReceivingController.resetRepairCenterDefaultsCacheForTest();

        Id standardPricebookId = Test.getStandardPricebookId();
        update new Pricebook2(Id = standardPricebookId, IsActive = true);

        Integer standardEntryCount = [
            SELECT COUNT()
            FROM PricebookEntry
            WHERE Pricebook2Id = :standardPricebookId
            AND Product2Id = :productId
        ];
        if (standardEntryCount == 0) {
            adb_PricebookEntry standardEntryBuilder = new adb_PricebookEntry()
                .pricebook2Id(standardPricebookId)
                .unitPrice(1)
                .isActive(true);
            standardEntryBuilder.set(PricebookEntry.Product2Id, productId);
            standardEntryBuilder.persist();
        }

        List<Pricebook2> existingPricebooks = [
            SELECT Id
            FROM Pricebook2
            WHERE Name = 'IMS Service Pricebook'
            AND IsActive = true
            LIMIT 1
        ];
        Id pricebookId;
        if (existingPricebooks.isEmpty()) {
            adb_Pricebook2 pricebookBuilder = new adb_Pricebook2()
                .name('IMS Service Pricebook')
                .isActive(true);
            pricebookBuilder.persist();
            pricebookId = pricebookBuilder.id;
        } else {
            pricebookId = existingPricebooks[0].Id;
        }

        Integer existingEntryCount = [
            SELECT COUNT()
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId
            AND Product2Id = :productId
        ];
        if (existingEntryCount == 0) {
            adb_PricebookEntry imsEntryBuilder = new adb_PricebookEntry()
                .pricebook2Id(pricebookId)
                .unitPrice(1)
                .isActive(true);
            imsEntryBuilder.set(PricebookEntry.Product2Id, productId);
            imsEntryBuilder.persist();
        }

        return new Pricebook2(Id = pricebookId);
    }

    private static void createTestData() {
        adb_Department departmentBuilder = new adb_Department()
            .name('Receiving Test Department');

        adb_Account accountBuilder = new adb_Account()
            .name('Return Order Receiving Test Account')
            .systemId('LEG-RECEIVE')
            .sourceSystemId('TEST-ORACLE-RECEIVE');
        adb_Contact contactBuilder = new adb_Contact()
            .lastName('Receiving Test Contact')
            .email('receiving.test@example.com')
            .account(accountBuilder);
        adb_Contact estimateContactBuilder = new adb_Contact()
            .lastName('Receiving Estimate Contact')
            .email('estimate.test@example.com')
            .account(accountBuilder);
        adb_Location repairCenterBuilder = new adb_Location()
            .name('Receiving Test Repair Center')
            .locationType('Repair Center');
        adb_Product2 productBuilder = new adb_Product2()
            .name('Receiving Test Product')
            .productCode('RCV-TEST-ITEM')
            .description('Receiving test product description')
            .isActive(true);

        adb_ReturnOrder serializedReturnOrderBuilder = new adb_ReturnOrder()
            .account(accountBuilder)
            .status('Created');
        serializedReturnOrderBuilder.setParent(ReturnOrder.DestinationLocationId, repairCenterBuilder);
        serializedReturnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
        serializedReturnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Serialized');

        adb_ReturnOrder contaminatedReturnOrderBuilder = new adb_ReturnOrder()
            .account(accountBuilder)
            .status('Created');
        contaminatedReturnOrderBuilder.setParent(ReturnOrder.DestinationLocationId, repairCenterBuilder);
        contaminatedReturnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
        contaminatedReturnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Serialized');

        adb_ReturnOrder instrumentsReturnOrderBuilder = new adb_ReturnOrder()
            .account(accountBuilder)
            .contact(contactBuilder)
            .status('Created');
        instrumentsReturnOrderBuilder.setParent(ReturnOrder.DestinationLocationId, repairCenterBuilder);
        instrumentsReturnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
        instrumentsReturnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Instruments');
        instrumentsReturnOrderBuilder.set(ReturnOrder.CustomerPO__c, 'RO-PO-INST');
        instrumentsReturnOrderBuilder.set(ReturnOrder.HospitalReferencedTrayName__c, 'RO Tray One');
        instrumentsReturnOrderBuilder.set(ReturnOrder.RepairWarranty__c, 'Yes');
        instrumentsReturnOrderBuilder.set(ReturnOrder.WarrantyNotes__c, 'RO warranty notes');
        instrumentsReturnOrderBuilder.set(ReturnOrder.EstimateRequired__c, 'Pre-Approved');
        instrumentsReturnOrderBuilder.setParent(ReturnOrder.EstimateContact__c, estimateContactBuilder);
        instrumentsReturnOrderBuilder.set(ReturnOrder.PreviousReturnOrder__c, 'RO-PREV-12345');
        instrumentsReturnOrderBuilder.set(ReturnOrder.CustomerReference__c, 'RO-CUST-REF');

        adb_ReturnOrder otherReturnOrderBuilder = new adb_ReturnOrder()
            .account(accountBuilder)
            .status('Created');
        otherReturnOrderBuilder.setParent(ReturnOrder.DestinationLocationId, repairCenterBuilder);
        otherReturnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
        otherReturnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Other');

        adb_ReturnOrderLineItem serialLineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(serializedReturnOrderBuilder)
            .quantityReturned(1);
        serialLineBuilder.setParent(ReturnOrderLineItem.Product2Id, productBuilder);
        serialLineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        serialLineBuilder.set(ReturnOrderLineItem.ProductLine__c, 'Device Line');
        serialLineBuilder.set(ReturnOrderLineItem.CustomerPO__c, 'PO-SERIAL');
        serialLineBuilder.set(ReturnOrderLineItem.CustomerReference__c, 'ROLI-CUST-REF');
        serialLineBuilder.set(ReturnOrderLineItem.Model__c, 'Device Model');
        serialLineBuilder.set(ReturnOrderLineItem.SerialNumber__c, 'ABC12345');
        serialLineBuilder.set(ReturnOrderLineItem.ReportedProblem__c, 'Device will not power on');

        adb_ReturnOrderLineItem instrumentsLineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(instrumentsReturnOrderBuilder)
            .quantityReturned(5);
        instrumentsLineBuilder.setParent(ReturnOrderLineItem.Product2Id, productBuilder);
        instrumentsLineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        instrumentsLineBuilder.set(ReturnOrderLineItem.ProductLine__c, 'INSTRUMENT');
        instrumentsLineBuilder.set(ReturnOrderLineItem.CustomerPO__c, 'PO-INST');
        instrumentsLineBuilder.set(ReturnOrderLineItem.HospitalReferencedTrayName__c, 'Tray One');
        instrumentsLineBuilder.set(ReturnOrderLineItem.Model__c, 'Instrument Model');

        adb_ReturnOrderLineItem otherLineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(otherReturnOrderBuilder)
            .quantityReturned(2);
        otherLineBuilder.setParent(ReturnOrderLineItem.Product2Id, productBuilder);
        otherLineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        otherLineBuilder.set(ReturnOrderLineItem.ProductLine__c, 'Other Line');
        otherLineBuilder.set(ReturnOrderLineItem.CustomerPO__c, 'PO-OTHER');
        otherLineBuilder.set(ReturnOrderLineItem.CustomerReference__c, 'OTHER-CUST-REF');
        otherLineBuilder.set(ReturnOrderLineItem.HospitalReferencedTrayName__c, 'Other Tray');
        otherLineBuilder.set(ReturnOrderLineItem.Model__c, 'Other Model');
        otherLineBuilder.set(ReturnOrderLineItem.SerialNumber__c, 'OTHER-123');
        otherLineBuilder.setParent(ReturnOrderLineItem.Contact__c, contactBuilder);
        otherLineBuilder.setParent(ReturnOrderLineItem.Department__c, departmentBuilder);
        otherLineBuilder.set(ReturnOrderLineItem.RepairWarranty__c, 'Yes');
        otherLineBuilder.set(ReturnOrderLineItem.WarrantyNotes__c, 'Other warranty notes');
        otherLineBuilder.set(ReturnOrderLineItem.EstimateRequired__c, 'Pre-Approved');
        otherLineBuilder.setParent(ReturnOrderLineItem.EstimateContact__c, estimateContactBuilder);
        otherLineBuilder.set(ReturnOrderLineItem.PreviousReturnOrder__c, 'RO-OTHER-PREV');

        String disinfectedNoValue = resolveDisinfectedNoValueForTest();
        if (String.isNotBlank(disinfectedNoValue)) {
            adb_ReturnOrderLineItem contaminatedLineBuilder = new adb_ReturnOrderLineItem()
                .returnOrder(contaminatedReturnOrderBuilder)
                .quantityReturned(1);
            contaminatedLineBuilder.setParent(ReturnOrderLineItem.Product2Id, productBuilder);
            contaminatedLineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
            contaminatedLineBuilder.set(ReturnOrderLineItem.ProductLine__c, 'Device Line');
            contaminatedLineBuilder.set(ReturnOrderLineItem.CustomerPO__c, 'PO-CONTAMINATED');
            contaminatedLineBuilder.set(ReturnOrderLineItem.Disinfected__c, disinfectedNoValue);
        }

        adb_ReturnOrderLineItem serialLineTwoBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(serializedReturnOrderBuilder)
            .quantityReturned(1);
        serialLineTwoBuilder.setParent(ReturnOrderLineItem.Product2Id, productBuilder);
        serialLineTwoBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        serialLineTwoBuilder.set(ReturnOrderLineItem.ProductLine__c, 'Device Line Two');
        serialLineTwoBuilder.set(ReturnOrderLineItem.CustomerPO__c, 'PO-SERIAL-2');

        serialLineTwoBuilder.persist();
        ensureDefaultPricebookForTest(productBuilder.id);
    }

    private static Datetime testReceivedDateTime() {
        return Datetime.newInstance(2026, 6, 14, 10, 0, 0);
    }

    private static ReturnOrder getReturnOrderByType(String returnOrderType) {
        if (returnOrderType == 'Serialized') {
            return [
                SELECT Id, AccountId
                FROM ReturnOrder
                WHERE ReturnOrderType__c = 'Serialized'
                AND Id IN (
                    SELECT ReturnOrderId
                    FROM ReturnOrderLineItem
                    WHERE CustomerPO__c = 'PO-SERIAL'
                )
                LIMIT 1
            ];
        }
        return [
            SELECT Id, AccountId
            FROM ReturnOrder
            WHERE ReturnOrderType__c = :returnOrderType
            LIMIT 1
        ];
    }

    private static ReturnOrderLineItem getLineItemForReturnOrder(Id returnOrderId) {
        return [
            SELECT Id, Product2Id, Model__c, HospitalReferencedTrayName__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrderId
            LIMIT 1
        ];
    }

    private static List<ReturnOrderReceivingController.LineReceiveInput> buildLineInput(
        Id lineItemId,
        Decimal quantityReceived
    ) {
        ReturnOrderReceivingController.LineReceiveInput lineInput =
            new ReturnOrderReceivingController.LineReceiveInput();
        lineInput.lineItemId = String.valueOf(lineItemId);
        lineInput.quantityReceived = quantityReceived;
        lineInput.quantityReturned = quantityReceived;
        lineInput.hasCorrections = false;
        return new List<ReturnOrderReceivingController.LineReceiveInput>{ lineInput };
    }

    private static String toLineInputsJson(Id lineItemId, Decimal quantityReceived) {
        return JSON.serialize(buildLineInput(lineItemId, quantityReceived));
    }

    private static String toLineInputsJson(
        List<ReturnOrderReceivingController.LineReceiveInput> lineInputs
    ) {
        return JSON.serialize(lineInputs);
    }

    private static ReturnOrderReceivingController.LineReceiveInput buildAdHocSerializedLineInput(
        String serialNumber,
        String model,
        Id productId
    ) {
        ReturnOrderReceivingController.LineReceiveInput lineInput =
            new ReturnOrderReceivingController.LineReceiveInput();
        lineInput.isAdHocSerializedLine = true;
        lineInput.adHocLineKey = 'adhoc-test-1';
        lineInput.quantityReceived = 1;
        lineInput.serialNumber = serialNumber;
        lineInput.model = model;
        lineInput.productId = productId;
        return lineInput;
    }

    @IsTest
    static void testReceiveSerializedWithAdHocLineCreatesCustomerCareChildWorkOrder() {
        ReturnOrder returnOrder = getReturnOrderByType('Serialized');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);

        ReturnOrderReceivingController.LineReceiveInput roliLineInput =
            buildLineInput(lineItem.Id, 1)[0];
        ReturnOrderReceivingController.LineReceiveInput adHocLineInput =
            buildAdHocSerializedLineInput('ADHOC-123', 'Ad Hoc Model', lineItem.Product2Id);

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                null,
                toLineInputsJson(
                    new List<ReturnOrderReceivingController.LineReceiveInput>{
                        roliLineInput,
                        adHocLineInput
                    }
                ),
                null
            );
        Test.stopTest();

        System.assertEquals(
            2,
            result.expectedSerializedChildCount,
            'Expected the page to wait for both serialized children.'
        );
        System.assertEquals(
            2,
            ReturnOrderReceivingController.getSerializedChildWorkOrderCount(result.primaryWorkOrderId),
            'Expected both serialized children before the page opens the parent.'
        );
        System.assertEquals(
            0,
            ReturnOrderReceivingController.getSerializedChildWorkOrderCount(null),
            'Expected zero when no parent work order is provided.'
        );

        List<WorkOrder> adHocChildWorkOrders = [
            SELECT Id, SubStatus__c, SerialNumber__c, Model__c, Product__c, ReturnOrderLineItemId
            FROM WorkOrder
            WHERE ParentWorkOrderId = :result.primaryWorkOrderId
            AND ReturnOrderLineItemId = NULL
        ];
        System.assertEquals(1, adHocChildWorkOrders.size(), 'Expected one ad hoc child work order.');
        System.assertEquals(
            'Customer Care',
            adHocChildWorkOrders[0].SubStatus__c,
            'Expected Customer Care sub status on ad hoc child work order.'
        );
        System.assertEquals('ADHOC-123', adHocChildWorkOrders[0].SerialNumber__c);
        System.assertEquals('Ad Hoc Model', adHocChildWorkOrders[0].Model__c);
        System.assertEquals(lineItem.Product2Id, adHocChildWorkOrders[0].Product__c);
    }

    @IsTest
    static void testReceiveSerializedWithAdHocLineOnly() {
        ReturnOrder returnOrder = getReturnOrderByType('Serialized');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);

        ReturnOrderReceivingController.LineReceiveInput adHocLineInput =
            buildAdHocSerializedLineInput('ADHOC-ONLY', 'Only Ad Hoc Model', lineItem.Product2Id);

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                null,
                toLineInputsJson(
                    new List<ReturnOrderReceivingController.LineReceiveInput>{ adHocLineInput }
                ),
                null
            );
        Test.stopTest();

        System.assertNotEquals(null, result.primaryWorkOrderId, 'Expected parent work order.');
        List<WorkOrder> childWorkOrders = [
            SELECT SubStatus__c, SerialNumber__c
            FROM WorkOrder
            WHERE ParentWorkOrderId = :result.primaryWorkOrderId
        ];
        System.assertEquals(1, childWorkOrders.size(), 'Expected one ad hoc child work order.');
        System.assertEquals('Customer Care', childWorkOrders[0].SubStatus__c);
        System.assertEquals('ADHOC-ONLY', childWorkOrders[0].SerialNumber__c);
    }

    @IsTest
    static void testReceiveSerializedAdHocLineFromJsonPayload() {
        ReturnOrder returnOrder = getReturnOrderByType('Serialized');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);

        String lineInputsJson =
            '[{' +
            '"isAdHocSerializedLine":true,' +
            '"adHocLineKey":"adhoc-json-1",' +
            '"quantityReceived":1,' +
            '"serialNumber":"JSON-ADHOC",' +
            '"model":"Json Model",' +
            '"productId":"' +
            String.valueOf(lineItem.Product2Id) +
            '"' +
            '}]';

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                null,
                lineInputsJson,
                null
            );
        Test.stopTest();

        WorkOrder adHocChildWorkOrder = [
            SELECT SubStatus__c, SerialNumber__c, Model__c
            FROM WorkOrder
            WHERE ParentWorkOrderId = :result.primaryWorkOrderId
            LIMIT 1
        ];
        System.assertEquals('Customer Care', adHocChildWorkOrder.SubStatus__c);
        System.assertEquals('JSON-ADHOC', adHocChildWorkOrder.SerialNumber__c);
        System.assertEquals('Json Model', adHocChildWorkOrder.Model__c);
    }

    @IsTest
    static void testGetReceivingContext() {
        ReturnOrder returnOrder = getReturnOrderByType('Serialized');

        Test.startTest();
        ReturnOrderReceivingController.ReceivingContext context =
            ReturnOrderReceivingController.getReceivingContext(returnOrder.Id);
        Test.stopTest();

        System.assertEquals('Serialized', context.returnOrderType, 'Expected serialized type.');
        System.assertEquals(2, context.lineItems.size(), 'Expected two line items.');
        System.assertEquals(1, context.lineItems[0].quantityReceived, 'Serialized quantity should be 1.');
    }

    @IsTest
    static void testReceiveSerializedReturnOrder() {
        ReturnOrder returnOrder = getReturnOrderByType('Serialized');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);
        returnOrder.SalesRep__c = UserInfo.getUserId();
        update returnOrder;
        ReturnOrderReceivingController.resetRepairCenterDefaultsCacheForTest();
        Pricebook2 defaultPricebook = ensureDefaultPricebookForTest(lineItem.Product2Id);

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                null,
                toLineInputsJson(lineItem.Id, 1),
                null
            );
        Test.stopTest();

        lineItem = [
            SELECT Status__c, Receiver__c, ReceivedDateTime__c, Product2Id
            FROM ReturnOrderLineItem
            WHERE Id = :lineItem.Id
        ];
        System.assertEquals('Received', lineItem.Status__c, 'Expected line item received.');
        System.assertNotEquals(null, result.primaryWorkOrderId, 'Expected parent work order.');

        WorkOrder parentWorkOrderWithPricebook = [
            SELECT Id, Pricebook2Id
            FROM WorkOrder
            WHERE Id = :result.primaryWorkOrderId
            LIMIT 1
        ];
        System.assertEquals(
            defaultPricebook.Id,
            parentWorkOrderWithPricebook.Pricebook2Id,
            'Expected parent work order price book from repair center defaults.'
        );

        List<WorkOrder> childWorkOrders = [
            SELECT Id, SubStatus__c, ParentWorkOrderId, ReturnOrder__c, ReturnOrderLineItemId,
                AssetId, ContactId, Product__c, Model__c, RepairCenter__c, CustomerReference__c,
                Description, Pricebook2Id
            FROM WorkOrder
            WHERE ReturnOrderLineItemId = :lineItem.Id
            AND ParentWorkOrderId != null
        ];
        System.assertEquals(1, childWorkOrders.size(), 'Expected one child work order.');
        System.assertEquals('Ready for Eval', childWorkOrders[0].SubStatus__c, 'Expected ready for eval.');
        System.assertEquals(result.primaryWorkOrderId, childWorkOrders[0].ParentWorkOrderId, 'Expected parent link.');
        System.assertEquals(lineItem.Id, childWorkOrders[0].ReturnOrderLineItemId, 'Expected line item on child.');
        System.assertEquals(returnOrder.Id, childWorkOrders[0].ReturnOrder__c, 'Expected return order on child work order.');
        System.assertEquals(
            defaultPricebook.Id,
            childWorkOrders[0].Pricebook2Id,
            'Expected child work order price book from repair center defaults.'
        );
        System.assertEquals(lineItem.Product2Id, childWorkOrders[0].Product__c, 'Expected product on child work order.');
        System.assertEquals('Device Model', childWorkOrders[0].Model__c, 'Expected model on child work order.');
        System.assertEquals(
            'Device will not power on',
            childWorkOrders[0].Description,
            'Expected child work order description from reported problem.'
        );

        List<WorkOrderLineItem> productServicedLineItems = [
            SELECT Id, TopLevelWorkOrder__c, WorkOrderId, ReturnOrderLineItemId,
                RecordType.DeveloperName, LineType__c, Subject, Description, AssetId,
                SerialNumber__c, Model__c, TrayName__c, Quantity, PricebookEntryId, Product2Id,
                ProductCodeWoli__c, ProductDescription__c, Status
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :childWorkOrders[0].Id
            AND IsAccessory__c = false
        ];
        System.assertEquals(1, productServicedLineItems.size(), 'Expected one product serviced WOLI.');
        System.assertEquals(
            result.primaryWorkOrderId,
            productServicedLineItems[0].TopLevelWorkOrder__c,
            'Expected top level work order on product serviced WOLI.'
        );
        System.assertEquals(
            childWorkOrders[0].Id,
            productServicedLineItems[0].WorkOrderId,
            'Expected child work order on product serviced WOLI.'
        );
        System.assertEquals(
            lineItem.Id,
            productServicedLineItems[0].ReturnOrderLineItemId,
            'Expected return order line item on product serviced WOLI.'
        );
        System.assertEquals(
            'ProductServiced',
            productServicedLineItems[0].RecordType.DeveloperName,
            'Expected product serviced record type on WOLI.'
        );
        System.assertEquals(
            'Product Serviced',
            productServicedLineItems[0].LineType__c,
            'Expected product serviced line type on WOLI.'
        );
        System.assertEquals(1, productServicedLineItems[0].Quantity, 'Expected quantity 1 on WOLI.');
        System.assertNotEquals(
            null,
            productServicedLineItems[0].PricebookEntryId,
            'Expected price book entry on product serviced WOLI.'
        );
        System.assertEquals(
            lineItem.Product2Id,
            productServicedLineItems[0].Product2Id,
            'Expected product on product serviced WOLI.'
        );
        System.assertEquals(
            'Approved',
            productServicedLineItems[0].Status,
            'Expected approved WOLI status when estimate is not required.'
        );

        System.assertEquals(
            'ROLI-CUST-REF',
            childWorkOrders[0].CustomerReference__c,
            'Expected customer reference from return order line item.'
        );

        ReturnOrder updatedReturnOrder = [
            SELECT DestinationLocationId
            FROM ReturnOrder
            WHERE Id = :returnOrder.Id
        ];
        System.assertEquals(
            updatedReturnOrder.DestinationLocationId,
            childWorkOrders[0].RepairCenter__c,
            'Expected repair center on child work order.'
        );

        returnOrder = [
            SELECT Id, WorkOrder__c
            FROM ReturnOrder
            WHERE Id = :returnOrder.Id
        ];
        System.assertEquals(result.primaryWorkOrderId, returnOrder.WorkOrder__c, 'Expected return order linked to parent work order.');

        WorkOrder parentWorkOrder = [
            SELECT ContactId,
                ParentWorkOrderId,
                ReturnOrder__c,
                ReturnOrderLineItemId,
                RepairCenter__c,
                SubStatus__c,
                CustomerPO__c,
                CustomerReference__c,
                AssignedSalesPerson__c
            FROM WorkOrder
            WHERE Id = :result.primaryWorkOrderId
        ];
        System.assertEquals('Resolved', parentWorkOrder.SubStatus__c, 'Expected resolved parent sub status.');
        System.assertEquals('PO-SERIAL', parentWorkOrder.CustomerPO__c, 'Expected customer PO on parent work order.');
        System.assertEquals(
            'ROLI-CUST-REF',
            parentWorkOrder.CustomerReference__c,
            'Expected customer reference on parent work order from first line item.'
        );
        System.assertEquals(
            UserInfo.getUserId(),
            parentWorkOrder.AssignedSalesPerson__c,
            'Expected sales rep on parent work order.'
        );
        System.assertEquals(null, parentWorkOrder.ParentWorkOrderId, 'Parent work order must not have a parent.');
        System.assertEquals(
            null,
            parentWorkOrder.ReturnOrderLineItemId,
            'Parent work order must not link to a return order line item.'
        );
        System.assertEquals(
            returnOrder.Id,
            parentWorkOrder.ReturnOrder__c,
            'Expected return order on parent work order.'
        );
        System.assertEquals(
            updatedReturnOrder.DestinationLocationId,
            parentWorkOrder.RepairCenter__c,
            'Expected repair center on parent work order.'
        );
    }

    @IsTest
    static void testReceiveSerializedProductServicedWoliStatusWaitingForApproval() {
        ReturnOrder returnOrder = getReturnOrderByType('Serialized');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);
        lineItem.EstimateRequired__c = 'Estimate Required';
        update lineItem;
        ReturnOrderReceivingController.resetRepairCenterDefaultsCacheForTest();
        ensureDefaultPricebookForTest(lineItem.Product2Id);

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                null,
                toLineInputsJson(lineItem.Id, 1),
                null
            );
        Test.stopTest();

        WorkOrder childWorkOrder = [
            SELECT Id, EstimateRequired__c
            FROM WorkOrder
            WHERE ReturnOrderLineItemId = :lineItem.Id
            AND ParentWorkOrderId = :result.primaryWorkOrderId
            LIMIT 1
        ];
        System.assertEquals(
            'Estimate Required',
            childWorkOrder.EstimateRequired__c,
            'Expected estimate required on child work order.'
        );

        WorkOrderLineItem productServicedLineItem = [
            SELECT Status
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :childWorkOrder.Id
            AND LineType__c = 'Product Serviced'
            AND IsAccessory__c = FALSE
            LIMIT 1
        ];
        System.assertEquals(
            'Waiting for Approval',
            productServicedLineItem.Status,
            'Expected waiting for approval WOLI status when estimate is required.'
        );
    }

    @IsTest
    static void testGetReceivingContextDefaultsContaminated() {
        String disinfectedNoValue = resolveDisinfectedNoValueForTest();
        if (String.isBlank(disinfectedNoValue)) {
            System.assert(true, 'No disinfected picklist value available in org.');
            return;
        }

        ReturnOrder returnOrder = [
            SELECT Id
            FROM ReturnOrder
            WHERE ReturnOrderType__c = 'Serialized'
            AND Id IN (SELECT ReturnOrderId FROM ReturnOrderLineItem WHERE CustomerPO__c = 'PO-CONTAMINATED')
            LIMIT 1
        ];

        Test.startTest();
        ReturnOrderReceivingController.ReceivingContext context =
            ReturnOrderReceivingController.getReceivingContext(returnOrder.Id);
        Test.stopTest();

        System.assertEquals(true, context.defaultIsContaminated, 'Expected contaminated default.');
    }

    @IsTest
    static void testGetReceivingContextDefaultsContaminatedForLegacyDisinfectedValue() {
        Account account = [
            SELECT Id
            FROM Account
            WHERE Name = 'Return Order Receiving Test Account'
            LIMIT 1
        ];
        Schema.Location repairCenter = [
            SELECT Id
            FROM Location
            WHERE Name = 'Receiving Test Repair Center'
            LIMIT 1
        ];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];

        adb_ReturnOrder returnOrderBuilder = new adb_ReturnOrder()
            .status('Created');
        returnOrderBuilder.set(ReturnOrder.AccountId, account.Id);
        returnOrderBuilder.set(ReturnOrder.DestinationLocationId, repairCenter.Id);
        returnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
        returnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Other');

        String disinfectedNoValue = resolveDisinfectedNoValueForTest();
        System.assertNotEquals(null, disinfectedNoValue, 'Expected a No disinfected picklist value.');

        adb_ReturnOrderLineItem lineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(returnOrderBuilder)
            .quantityReturned(1);
        lineBuilder.set(ReturnOrderLineItem.Product2Id, product.Id);
        lineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        lineBuilder.set(ReturnOrderLineItem.CustomerPO__c, 'PO-LEGACY-DISINFECTED');
        lineBuilder.set(ReturnOrderLineItem.Disinfected__c, disinfectedNoValue);
        lineBuilder.persist();

        ReturnOrder returnOrder = [SELECT Id FROM ReturnOrder WHERE Id = :returnOrderBuilder.id];

        Test.startTest();
        ReturnOrderReceivingController.ReceivingContext context =
            ReturnOrderReceivingController.getReceivingContext(returnOrder.Id);
        Test.stopTest();

        System.assertEquals(true, context.defaultIsContaminated, 'Expected contaminated default.');
    }

    @IsTest
    static void testGetReceivingContextInstrumentsQuantityDefault() {
        ReturnOrder returnOrder = getReturnOrderByType('Instruments');

        Test.startTest();
        ReturnOrderReceivingController.ReceivingContext context =
            ReturnOrderReceivingController.getReceivingContext(returnOrder.Id);
        Test.stopTest();

        System.assertEquals(5, context.defaultInstrumentQuantityReceived, 'Expected summed quantity.');
    }

    @IsTest
    static void testReceiveInstrumentsReturnOrder() {
        Schema.RecordTypeInfo instrumentsRecordType = Schema.SObjectType.WorkOrder
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCenterInstruments');
        if (instrumentsRecordType == null || !instrumentsRecordType.isAvailable()) {
            System.assert(true, 'Instrument record type unavailable in this org.');
            return;
        }

        ReturnOrder returnOrder = getReturnOrderByType('Instruments');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                5,
                toLineInputsJson(lineItem.Id, 5),
                null
            );
        Test.stopTest();

        returnOrder = [
            SELECT Status, QuantityReceived__c
            FROM ReturnOrder
            WHERE Id = :returnOrder.Id
        ];
        System.assertEquals('Received', returnOrder.Status, 'Expected return order received.');
        System.assertEquals(5, returnOrder.QuantityReceived__c, 'Expected quantity on return order.');
        System.assertNotEquals(null, result.primaryWorkOrderId, 'Expected instrument work order.');

        WorkOrder instrumentWorkOrder = [
            SELECT
                Product__c,
                Pricebook2Id,
                Model__c,
                TrayName__c,
                QuantityReceived__c,
                RepairCenter__c,
                ReturnOrderLineItemId,
                ReturnOrder__c,
                ContactId,
                CustomerPO__c,
                RepairWarranty__c,
                WarrantyNotes__c,
                EstimateRequired__c,
                EstimateContact__c,
                PreviousReturnOrder__c,
                CustomerReference__c
            FROM WorkOrder
            WHERE Id = :result.primaryWorkOrderId
        ];
        ReturnOrder updatedReturnOrder = [
            SELECT DestinationLocationId, ContactId
            FROM ReturnOrder
            WHERE Id = :returnOrder.Id
        ];
        System.assertEquals(null, instrumentWorkOrder.Product__c, 'Instrument WO should not map product from line item.');
        System.assertNotEquals(null, instrumentWorkOrder.Pricebook2Id, 'Expected default pricebook on instrument work order.');
        System.assertEquals(null, instrumentWorkOrder.Model__c, 'Instrument WO should not map model from line item.');
        System.assertEquals('RO Tray One', instrumentWorkOrder.TrayName__c, 'Expected tray name from return order header.');
        System.assertEquals('RO-PO-INST', instrumentWorkOrder.CustomerPO__c, 'Expected customer PO from return order header.');
        System.assertEquals(
            updatedReturnOrder.ContactId,
            instrumentWorkOrder.ContactId,
            'Expected contact from return order header.'
        );
        System.assertEquals('Yes', instrumentWorkOrder.RepairWarranty__c, 'Expected repair warranty from return order header.');
        System.assertEquals(
            'RO warranty notes',
            instrumentWorkOrder.WarrantyNotes__c,
            'Expected warranty notes from return order header.'
        );
        System.assertEquals(
            'Pre-Approved',
            instrumentWorkOrder.EstimateRequired__c,
            'Expected estimate required from return order header.'
        );
        ReturnOrder sourceReturnOrder = [
            SELECT EstimateContact__c, PreviousReturnOrder__c
            FROM ReturnOrder
            WHERE Id = :returnOrder.Id
        ];
        System.assertEquals(
            sourceReturnOrder.EstimateContact__c,
            instrumentWorkOrder.EstimateContact__c,
            'Expected estimate contact from return order header.'
        );
        System.assertEquals(
            'RO-PREV-12345',
            instrumentWorkOrder.PreviousReturnOrder__c,
            'Expected previous return order from return order header.'
        );
        System.assertEquals(
            'RO-CUST-REF',
            instrumentWorkOrder.CustomerReference__c,
            'Expected customer reference from return order header.'
        );
        System.assertEquals(5, instrumentWorkOrder.QuantityReceived__c, 'Expected summarized quantity on instrument WO.');
        System.assertEquals(
            null,
            instrumentWorkOrder.ReturnOrderLineItemId,
            'Instrument header should not map return order line item.'
        );
        System.assertEquals(
            returnOrder.Id,
            instrumentWorkOrder.ReturnOrder__c,
            'Expected return order on instrument work order.'
        );
        System.assertEquals(
            updatedReturnOrder.DestinationLocationId,
            instrumentWorkOrder.RepairCenter__c,
            'Expected repair center on instrument work order.'
        );

        System.assertEquals(
            0,
            [SELECT COUNT() FROM WorkOrderLineItem WHERE WorkOrderId = :result.primaryWorkOrderId],
            'Instrument receive should not create work order line items.'
        );

        lineItem = [
            SELECT QuantityReceived
            FROM ReturnOrderLineItem
            WHERE Id = :lineItem.Id
        ];
        System.assertEquals(5, lineItem.QuantityReceived, 'Expected line quantity received to be saved.');
    }

    @IsTest
    static void testReceiveInstrumentsReturnOrderWithModRequestSetsModHoldSubStatus() {
        Schema.RecordTypeInfo instrumentsRecordType = Schema.SObjectType.WorkOrder
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCenterInstruments');
        if (instrumentsRecordType == null || !instrumentsRecordType.isAvailable()) {
            System.assert(true, 'Instrument record type unavailable in this org.');
            return;
        }

        ReturnOrder returnOrder = getReturnOrderByType('Instruments');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);
        lineItem.ModRequest__c = true;
        update lineItem;

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                5,
                toLineInputsJson(lineItem.Id, 5),
                null
            );
        Test.stopTest();

        WorkOrder instrumentWorkOrder = [
            SELECT SubStatus__c, ModRequest__c
            FROM WorkOrder
            WHERE Id = :result.primaryWorkOrderId
        ];
        System.assertEquals(
            'Mod Hold',
            instrumentWorkOrder.SubStatus__c,
            'Expected Mod Hold sub status when any line has Mod Request.'
        );
        System.assertEquals(
            true,
            instrumentWorkOrder.ModRequest__c,
            'Expected Mod Request on work order when sub status is Mod Hold.'
        );
    }

    @IsTest
    static void testReceiveInstrumentsUsesSummarizedQuantityAndUpdatesLineItems() {
        Schema.RecordTypeInfo instrumentsRecordType = Schema.SObjectType.WorkOrder
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCenterInstruments');
        if (instrumentsRecordType == null || !instrumentsRecordType.isAvailable()) {
            System.assert(true, 'Instrument record type unavailable in this org.');
            return;
        }

        ReturnOrder returnOrder = getReturnOrderByType('Instruments');
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        adb_ReturnOrderLineItem secondLineBuilder = new adb_ReturnOrderLineItem()
            .quantityReturned(2);
        secondLineBuilder.set(ReturnOrderLineItem.ReturnOrderId, returnOrder.Id);
        secondLineBuilder.set(ReturnOrderLineItem.Product2Id, product.Id);
        secondLineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        secondLineBuilder.set(ReturnOrderLineItem.ProductLine__c, 'INSTRUMENT');
        secondLineBuilder.set(ReturnOrderLineItem.CustomerPO__c, 'PO-INST-2');
        secondLineBuilder.set(ReturnOrderLineItem.HospitalReferencedTrayName__c, 'Tray Two');
        secondLineBuilder.set(ReturnOrderLineItem.Model__c, 'Instrument Model Two');
        secondLineBuilder.persist();
        ReturnOrderLineItem secondLineItem = [
            SELECT Id
            FROM ReturnOrderLineItem
            WHERE Id = :secondLineBuilder.id
        ];

        ReturnOrderLineItem firstLineItem = getLineItemForReturnOrder(returnOrder.Id);

        List<ReturnOrderReceivingController.LineReceiveInput> lineInputs =
            new List<ReturnOrderReceivingController.LineReceiveInput>();
        ReturnOrderReceivingController.LineReceiveInput firstInput =
            new ReturnOrderReceivingController.LineReceiveInput();
        firstInput.lineItemId = String.valueOf(firstLineItem.Id);
        firstInput.quantityReceived = 3;
        lineInputs.add(firstInput);

        ReturnOrderReceivingController.LineReceiveInput secondInput =
            new ReturnOrderReceivingController.LineReceiveInput();
        secondInput.lineItemId = String.valueOf(secondLineItem.Id);
        secondInput.quantityReceived = 2;
        lineInputs.add(secondInput);

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                5,
                toLineInputsJson(lineInputs),
                null
            );
        Test.stopTest();

        returnOrder = [
            SELECT QuantityReceived__c
            FROM ReturnOrder
            WHERE Id = :returnOrder.Id
        ];
        System.assertEquals(5, returnOrder.QuantityReceived__c, 'Expected summarized quantity on return order.');

        WorkOrder instrumentWorkOrder = [
            SELECT QuantityReceived__c
            FROM WorkOrder
            WHERE Id = :result.primaryWorkOrderId
        ];
        System.assertEquals(5, instrumentWorkOrder.QuantityReceived__c, 'Expected summarized quantity on work order.');

        Map<Id, ReturnOrderLineItem> updatedLineItems = new Map<Id, ReturnOrderLineItem>([
            SELECT Id, QuantityReceived
            FROM ReturnOrderLineItem
            WHERE Id IN :new Set<Id>{ firstLineItem.Id, secondLineItem.Id }
        ]);
        System.assertEquals(3, updatedLineItems.get(firstLineItem.Id).QuantityReceived, 'Expected first line quantity.');
        System.assertEquals(2, updatedLineItems.get(secondLineItem.Id).QuantityReceived, 'Expected second line quantity.');
    }

    @IsTest
    static void testReceiveOtherReturnOrder() {
        ReturnOrder returnOrder = getReturnOrderByType('Other');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                null,
                toLineInputsJson(lineItem.Id, 2),
                null
            );
        Test.stopTest();

        System.assertNotEquals(null, result.primaryWorkOrderId, 'Expected other work order.');
        WorkOrder createdWorkOrder = [
            SELECT RecordType.DeveloperName
            FROM WorkOrder
            WHERE Id = :result.primaryWorkOrderId
        ];
        System.assertEquals(
            'RepairCenterVendor',
            createdWorkOrder.RecordType.DeveloperName,
            'Direct-to-Vendor receiving should create Repair Center - Vendor work orders.'
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM WorkOrderLineItem WHERE WorkOrderId = :result.primaryWorkOrderId],
            'Expected one work order line item.'
        );

        WorkOrderLineItem workOrderLineItem = [
            SELECT
                Product__c,
                Product2Id,
                PricebookEntryId,
                ProductCodeWoli__c,
                LineType__c,
                Quantity,
                Model__c,
                TrayName__c,
                SerialNumber__c,
                ReturnOrderLineItemId,
                Contact__c,
                CustomerPO__c,
                CustomerReference__c,
                Department__c,
                RepairWarranty__c,
                WarrantyNotes__c,
                EstimateRequired__c,
                EstimateContact__c,
                PreviousReturnOrder__c
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :result.primaryWorkOrderId
            LIMIT 1
        ];
        System.assertEquals(null, workOrderLineItem.Product__c, 'Other WOLI should not use custom Product__c.');
        System.assert(
            workOrderLineItem.PricebookEntryId != null ||
                workOrderLineItem.Product2Id == lineItem.Product2Id,
            'Expected standard product on WOLI.'
        );
        System.assertEquals('Product Serviced', workOrderLineItem.LineType__c, 'Expected product serviced line type.');
        System.assertEquals(2, workOrderLineItem.Quantity, 'Expected quantity on WOLI.');
        System.assertEquals('Other Model', workOrderLineItem.Model__c, 'Expected model on WOLI.');
        System.assertEquals('Other Tray', workOrderLineItem.TrayName__c, 'Expected tray name on WOLI.');
        System.assertEquals('OTHER-123', workOrderLineItem.SerialNumber__c, 'Expected serial on WOLI.');
        System.assertEquals(lineItem.Id, workOrderLineItem.ReturnOrderLineItemId, 'Expected ROLI link on WOLI.');
        System.assertEquals('PO-OTHER', workOrderLineItem.CustomerPO__c, 'Expected customer PO on WOLI.');
        System.assertEquals(
            'OTHER-CUST-REF',
            workOrderLineItem.CustomerReference__c,
            'Expected customer reference on WOLI.'
        );
        System.assertEquals('Yes', workOrderLineItem.RepairWarranty__c, 'Expected repair warranty on WOLI.');
        System.assertEquals(
            'Other warranty notes',
            workOrderLineItem.WarrantyNotes__c,
            'Expected warranty notes on WOLI.'
        );
        System.assertEquals(
            'Pre-Approved',
            workOrderLineItem.EstimateRequired__c,
            'Expected estimate required on WOLI.'
        );
        System.assertEquals(
            'RO-OTHER-PREV',
            workOrderLineItem.PreviousReturnOrder__c,
            'Expected previous return order on WOLI.'
        );

        ReturnOrderLineItem sourceLineItem = [
            SELECT Contact__c, Department__c, EstimateContact__c
            FROM ReturnOrderLineItem
            WHERE Id = :lineItem.Id
        ];
        System.assertEquals(
            sourceLineItem.Contact__c,
            workOrderLineItem.Contact__c,
            'Expected contact on WOLI.'
        );
        System.assertEquals(
            sourceLineItem.Department__c,
            workOrderLineItem.Department__c,
            'Expected department on WOLI.'
        );
        System.assertEquals(
            sourceLineItem.EstimateContact__c,
            workOrderLineItem.EstimateContact__c,
            'Expected estimate contact on WOLI.'
        );

        ReturnOrder updatedReturnOrder = [
            SELECT DestinationLocationId
            FROM ReturnOrder
            WHERE Id = :returnOrder.Id
        ];
        WorkOrder otherWorkOrder = [
            SELECT Product__c, Pricebook2Id, TrayName__c, ReturnOrderLineItemId, ReturnOrder__c, RepairCenter__c, Model__c
            FROM WorkOrder
            WHERE Id = :result.primaryWorkOrderId
        ];
        System.assertEquals(null, otherWorkOrder.Product__c, 'Other header should not map product.');
        System.assertNotEquals(null, otherWorkOrder.Pricebook2Id, 'Expected default pricebook on other work order.');
        System.assertEquals(null, otherWorkOrder.TrayName__c, 'Other header should not map tray name.');
        System.assertEquals(returnOrder.Id, otherWorkOrder.ReturnOrder__c, 'Expected return order on other work order.');
        System.assertEquals(
            null,
            otherWorkOrder.ReturnOrderLineItemId,
            'Other header should not map return order line item.'
        );
        System.assertEquals(
            updatedReturnOrder.DestinationLocationId,
            otherWorkOrder.RepairCenter__c,
            'Expected repair center on other work order header.'
        );
        System.assertEquals('Other Model', otherWorkOrder.Model__c, 'Expected model on other work order header.');
    }

    @IsTest
    static void testReceiveContaminatedSerializedReturnOrder() {
        ReturnOrder returnOrder = getReturnOrderByType('Serialized');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                true,
                null,
                toLineInputsJson(lineItem.Id, 1),
                null
            );
        Test.stopTest();

        WorkOrder parentWorkOrder = [
            SELECT SubStatus__c
            FROM WorkOrder
            WHERE Id = :result.primaryWorkOrderId
        ];
        WorkOrder childWorkOrder = [
            SELECT SubStatus__c
            FROM WorkOrder
            WHERE ReturnOrderLineItemId = :lineItem.Id
            AND ParentWorkOrderId != null
            LIMIT 1
        ];
        System.assertEquals(
            'Contaminated',
            childWorkOrder.SubStatus__c,
            'Expected contaminated child sub status.'
        );
        System.assertEquals(
            'Resolved',
            parentWorkOrder.SubStatus__c,
            'Expected resolved parent sub status for contaminated serialized receive.'
        );
    }

    @IsTest
    static void testReceiveRequiresSelectedLines() {
        ReturnOrder returnOrder = getReturnOrderByType('Serialized');

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                null,
                '[]',
                null
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Expected validation when no lines selected.');
    }

    @IsTest
    static void testReceiveSerializedWithSmallSerialCorrectionSetsReadyForEval() {
        ReturnOrder returnOrder = getReturnOrderByType('Serialized');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);

        ReturnOrderReceivingController.LineReceiveInput lineInput =
            new ReturnOrderReceivingController.LineReceiveInput();
        lineInput.lineItemId = String.valueOf(lineItem.Id);
        lineInput.quantityReceived = 1;
        lineInput.hasCorrections = true;
        lineInput.serialNumber = 'ABC12346';
        lineInput.model = 'Device Model';
        lineInput.productLine = 'Device Line';

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                null,
                toLineInputsJson(new List<ReturnOrderReceivingController.LineReceiveInput>{ lineInput }),
                null
            );
        Test.stopTest();

        WorkOrder parentWorkOrder = [
            SELECT SubStatus__c
            FROM WorkOrder
            WHERE Id = :result.primaryWorkOrderId
        ];
        WorkOrder childWorkOrder = [
            SELECT SubStatus__c, CaseId
            FROM WorkOrder
            WHERE ReturnOrderLineItemId = :lineItem.Id
            AND ParentWorkOrderId != null
            LIMIT 1
        ];
        System.assertEquals(
            'Ready for Eval',
            childWorkOrder.SubStatus__c,
            'Expected ready for eval when serial correction is within two characters.'
        );
        System.assertEquals(
            null,
            childWorkOrder.CaseId,
            'Expected no Customer Care case for Ready for Eval work order.'
        );
        System.assertEquals(
            'Resolved',
            parentWorkOrder.SubStatus__c,
            'Expected resolved parent sub status for serialized receive.'
        );
    }

    @IsTest
    static void testReceiveSerializedWithProductCorrectionSetsCustomerCare() {
        ReturnOrder returnOrder = getReturnOrderByType('Serialized');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);

        adb_Product2 alternateProductBuilder = new adb_Product2()
            .name('Alternate Serialized Product')
            .isActive(true)
            .productLine('Device Line')
            .productType('Service Asset');
        alternateProductBuilder.persist();
        ensureDefaultPricebookForTest(alternateProductBuilder.id);
        Product2 alternateProduct = [
            SELECT Id
            FROM Product2
            WHERE Id = :alternateProductBuilder.id
        ];

        ReturnOrderReceivingController.LineReceiveInput lineInput =
            new ReturnOrderReceivingController.LineReceiveInput();
        lineInput.lineItemId = String.valueOf(lineItem.Id);
        lineInput.quantityReceived = 1;
        lineInput.hasCorrections = true;
        lineInput.serialNumber = 'ABC12345';
        lineInput.model = 'Device Model';
        lineInput.productLine = 'Device Line';
        lineInput.productId = alternateProduct.Id;

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                null,
                toLineInputsJson(new List<ReturnOrderReceivingController.LineReceiveInput>{ lineInput }),
                null
            );
        Test.stopTest();

        lineItem = [
            SELECT Product2Id
            FROM ReturnOrderLineItem
            WHERE Id = :lineItem.Id
        ];
        System.assertEquals(
            alternateProduct.Id,
            lineItem.Product2Id,
            'Expected product correction on return order line item.'
        );

        WorkOrder parentWorkOrder = [
            SELECT SubStatus__c
            FROM WorkOrder
            WHERE Id = :result.primaryWorkOrderId
        ];
        WorkOrder childWorkOrder = [
            SELECT SubStatus__c, Product__c, CaseId
            FROM WorkOrder
            WHERE ReturnOrderLineItemId = :lineItem.Id
            AND ParentWorkOrderId != null
            LIMIT 1
        ];
        System.assertEquals(
            'Customer Care',
            childWorkOrder.SubStatus__c,
            'Expected customer care when product is updated in modify.'
        );
        System.assertNotEquals(
            null,
            childWorkOrder.CaseId,
            'Expected linked Customer Care case for receive-created work order.'
        );

        Id queueId = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue'
            AND DeveloperName = 'QNAIMSCustCareCentralSupport'
            LIMIT 1
        ].Id;

        Case customerCareCase = [
            SELECT OwnerId, RecordType.DeveloperName, Status, Origin, Subject, AccountId
            FROM Case
            WHERE Id = :childWorkOrder.CaseId
        ];
        System.assertEquals('InboxSupport', customerCareCase.RecordType.DeveloperName);
        System.assertEquals(queueId, customerCareCase.OwnerId);
        System.assertEquals('New', customerCareCase.Status);
        System.assertEquals('Central Repair Support', customerCareCase.Origin);
        System.assert(customerCareCase.Subject.contains('Customer Care'));
        System.assertEquals(
            alternateProduct.Id,
            childWorkOrder.Product__c,
            'Expected corrected product on child work order.'
        );
        System.assertEquals(
            'Resolved',
            parentWorkOrder.SubStatus__c,
            'Expected resolved parent sub status for serialized receive.'
        );
    }

    @IsTest
    static void testReceiveSerializedAssetCorrectionUpdatesAssetInElevatedMode() {
        ReturnOrder returnOrder = getReturnOrderByType('Serialized');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);
        Product2 product = [SELECT Id FROM Product2 WHERE Name = 'Receiving Test Product' LIMIT 1];
        Department__c department = [
            SELECT Id
            FROM Department__c
            WHERE Name = 'Receiving Test Department'
            LIMIT 1
        ];

        adb_Asset assetBuilder = new adb_Asset()
            .name('Receiving Correction Asset')
            .serialNumber('ASSET-OLD-001');
        assetBuilder.set(Asset.AccountId, returnOrder.AccountId);
        assetBuilder.set(Asset.Product2Id, product.Id);
        assetBuilder.persist();
        Asset asset = [SELECT Id FROM Asset WHERE Id = :assetBuilder.id];
        update new ReturnOrderLineItem(Id = lineItem.Id, AssetId = asset.Id);

        ReturnOrderReceivingController.LineReceiveInput lineInput =
            new ReturnOrderReceivingController.LineReceiveInput();
        lineInput.lineItemId = String.valueOf(lineItem.Id);
        lineInput.quantityReceived = 1;
        lineInput.hasCorrections = true;
        lineInput.serialNumber = 'ASSET-NEW-001';
        lineInput.model = 'Device Model';
        lineInput.productLine = 'Device Line';
        lineInput.departmentId = department.Id;
        lineInput.selectedAssetId = asset.Id;

        Test.startTest();
        ReturnOrderReceivingController.receiveReturnOrder(
            returnOrder.Id,
            UserInfo.getUserId(),
            testReceivedDateTime(),
            false,
            null,
            toLineInputsJson(new List<ReturnOrderReceivingController.LineReceiveInput>{ lineInput }),
            null
        );
        Test.stopTest();

        Asset updatedAsset = [
            SELECT SerialNumber, Department__c
            FROM Asset
            WHERE Id = :asset.Id
        ];
        System.assertEquals(
            'ASSET-NEW-001',
            updatedAsset.SerialNumber,
            'Expected elevated receive correction to update Asset serial number.'
        );
        System.assertEquals(
            department.Id,
            updatedAsset.Department__c,
            'Expected elevated receive correction to update Asset department.'
        );
    }

    @IsTest
    static void testReceiveSerializedWithLargeCorrectionSetsCustomerCare() {
        ReturnOrder returnOrder = getReturnOrderByType('Serialized');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);

        ReturnOrderReceivingController.LineReceiveInput lineInput =
            new ReturnOrderReceivingController.LineReceiveInput();
        lineInput.lineItemId = String.valueOf(lineItem.Id);
        lineInput.quantityReceived = 1;
        lineInput.hasCorrections = true;
        lineInput.serialNumber = 'XYZ99999';
        lineInput.model = 'Device Model';
        lineInput.productLine = 'Device Line';

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                null,
                toLineInputsJson(new List<ReturnOrderReceivingController.LineReceiveInput>{ lineInput }),
                null
            );
        Test.stopTest();

        WorkOrder parentWorkOrder = [
            SELECT SubStatus__c
            FROM WorkOrder
            WHERE Id = :result.primaryWorkOrderId
        ];
        WorkOrder childWorkOrder = [
            SELECT SubStatus__c
            FROM WorkOrder
            WHERE ReturnOrderLineItemId = :lineItem.Id
            AND ParentWorkOrderId != null
            LIMIT 1
        ];
        System.assertEquals(
            'Customer Care',
            childWorkOrder.SubStatus__c,
            'Expected customer care when serial correction exceeds two characters.'
        );
        System.assertEquals(
            'Resolved',
            parentWorkOrder.SubStatus__c,
            'Expected resolved parent sub status for serialized receive.'
        );
    }

    @IsTest
    static void testReceiveSerializedWithModRequestSetsModHoldSubStatus() {
        ReturnOrder returnOrder = getReturnOrderByType('Serialized');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);
        lineItem.ModRequest__c = true;
        update lineItem;

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                null,
                toLineInputsJson(lineItem.Id, 1),
                null
            );
        Test.stopTest();

        WorkOrder parentWorkOrder = [
            SELECT SubStatus__c
            FROM WorkOrder
            WHERE Id = :result.primaryWorkOrderId
        ];
        WorkOrder childWorkOrder = [
            SELECT SubStatus__c, ModRequest__c
            FROM WorkOrder
            WHERE ReturnOrderLineItemId = :lineItem.Id
            AND ParentWorkOrderId != null
            LIMIT 1
        ];
        System.assertEquals(
            'Mod Hold',
            childWorkOrder.SubStatus__c,
            'Expected mod hold sub status when ROLI has mod request.'
        );
        System.assertEquals(
            true,
            childWorkOrder.ModRequest__c,
            'Expected Mod Request on child work order when sub status is Mod Hold.'
        );
        System.assertEquals(
            'Resolved',
            parentWorkOrder.SubStatus__c,
            'Expected resolved parent sub status for serialized receive.'
        );
    }

    @IsTest
    static void testReceiveContaminatedSerializedWithModRequestUsesContaminatedSubStatus() {
        ReturnOrder returnOrder = getReturnOrderByType('Serialized');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);
        lineItem.ModRequest__c = true;
        update lineItem;

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                true,
                null,
                toLineInputsJson(lineItem.Id, 1),
                null
            );
        Test.stopTest();

        WorkOrder parentWorkOrder = [
            SELECT SubStatus__c
            FROM WorkOrder
            WHERE Id = :result.primaryWorkOrderId
        ];
        WorkOrder childWorkOrder = [
            SELECT SubStatus__c
            FROM WorkOrder
            WHERE ReturnOrderLineItemId = :lineItem.Id
            AND ParentWorkOrderId != null
            LIMIT 1
        ];
        System.assertEquals(
            'Contaminated',
            childWorkOrder.SubStatus__c,
            'Expected contaminated to beat mod hold on child work order.'
        );
        System.assertEquals(
            'Resolved',
            parentWorkOrder.SubStatus__c,
            'Expected resolved parent sub status for contaminated serialized receive.'
        );
    }

    @IsTest
    static void testPartialSerializedReceiveDoesNotCompleteReturnOrder() {
        ReturnOrder returnOrder = getReturnOrderByType('Serialized');
        ReturnOrderLineItem firstLine = [
            SELECT Id
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrder.Id
            AND CustomerPO__c = 'PO-SERIAL'
            LIMIT 1
        ];

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                null,
                toLineInputsJson(firstLine.Id, 1),
                null
            );
        Test.stopTest();

        returnOrder = [SELECT Status FROM ReturnOrder WHERE Id = :returnOrder.Id];
        System.assertEquals('Created', returnOrder.Status, 'Expected partial receive to keep RO open.');
        System.assertEquals(false, result.returnOrderReceived, 'Expected partial receive result.');
    }

    @IsTest
    static void testReceiveOtherWithCorrectionsSetsCustomerCare() {
        ReturnOrder returnOrder = getReturnOrderByType('Other');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);

        ReturnOrderReceivingController.LineReceiveInput lineInput =
            new ReturnOrderReceivingController.LineReceiveInput();
        lineInput.lineItemId = lineItem.Id;
        lineInput.quantityReceived = 2;
        lineInput.hasCorrections = true;
        lineInput.serialNumber = 'COMPLETELY-DIFFERENT-SERIAL';
        lineInput.model = 'Other Model';
        lineInput.productLine = 'Other Line';

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                null,
                toLineInputsJson(new List<ReturnOrderReceivingController.LineReceiveInput>{ lineInput }),
                null
            );
        Test.stopTest();

        WorkOrder workOrder = [
            SELECT SubStatus__c
            FROM WorkOrder
            WHERE Id = :result.primaryWorkOrderId
        ];
        System.assertEquals(
            'Customer Care',
            workOrder.SubStatus__c,
            'Expected customer care when other line serial changes by more than two characters.'
        );
    }

    @IsTest
    static void testReceiveOtherSmallSerialCorrectionUsesReadyForEval() {
        ReturnOrder returnOrder = getReturnOrderByType('Other');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);

        ReturnOrderReceivingController.LineReceiveInput lineInput =
            new ReturnOrderReceivingController.LineReceiveInput();
        lineInput.lineItemId = lineItem.Id;
        lineInput.quantityReceived = 2;
        lineInput.hasCorrections = true;
        lineInput.serialNumber = 'OTHER-12';

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                null,
                toLineInputsJson(new List<ReturnOrderReceivingController.LineReceiveInput>{ lineInput }),
                null
            );
        Test.stopTest();

        WorkOrder workOrder = [
            SELECT SubStatus__c
            FROM WorkOrder
            WHERE Id = :result.primaryWorkOrderId
        ];
        System.assertEquals(
            'Ready for Eval',
            workOrder.SubStatus__c,
            'Expected ready for eval when other serial correction is within two characters.'
        );
    }

    @IsTest
    static void testReceiveOtherModRequestUsesModHoldOverCustomerCare() {
        ReturnOrder returnOrder = getReturnOrderByType('Other');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);
        lineItem.ModRequest__c = true;
        update lineItem;

        ReturnOrderReceivingController.LineReceiveInput lineInput =
            new ReturnOrderReceivingController.LineReceiveInput();
        lineInput.lineItemId = lineItem.Id;
        lineInput.quantityReceived = 2;
        lineInput.hasCorrections = true;
        lineInput.serialNumber = 'COMPLETELY-DIFFERENT-SERIAL';

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                null,
                toLineInputsJson(new List<ReturnOrderReceivingController.LineReceiveInput>{ lineInput }),
                null
            );
        Test.stopTest();

        WorkOrder workOrder = [
            SELECT SubStatus__c, ModRequest__c
            FROM WorkOrder
            WHERE Id = :result.primaryWorkOrderId
        ];
        System.assertEquals(
            'Mod Hold',
            workOrder.SubStatus__c,
            'Expected Mod Hold to beat Customer Care on other receive.'
        );
        System.assertEquals(
            true,
            workOrder.ModRequest__c,
            'Expected Mod Request on work order when sub status is Mod Hold.'
        );
    }

    @IsTest
    static void testReceiveContaminatedOtherWithModRequestUsesContaminatedSubStatus() {
        ReturnOrder returnOrder = getReturnOrderByType('Other');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);
        lineItem.ModRequest__c = true;
        update lineItem;

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                true,
                null,
                toLineInputsJson(lineItem.Id, 2),
                null
            );
        Test.stopTest();

        WorkOrder workOrder = [
            SELECT SubStatus__c, Contaminated__c
            FROM WorkOrder
            WHERE Id = :result.primaryWorkOrderId
        ];
        System.assertEquals('Contaminated', workOrder.SubStatus__c, 'Expected contaminated sub status.');
        System.assertEquals(true, workOrder.Contaminated__c, 'Expected contaminated flag.');
    }

    @IsTest
    static void testGetItemTypeProductLineMappings() {
        Test.startTest();
        List<ReturnOrderReceivingController.ItemTypeProductLineMapping> mappings =
            ReturnOrderReceivingController.getItemTypeProductLineMappings();
        Test.stopTest();

        System.assert(!mappings.isEmpty(), 'Expected item type mappings.');
        Boolean foundEndocamMapping = false;
        for (ReturnOrderReceivingController.ItemTypeProductLineMapping mapping : mappings) {
            if (mapping.itemType == 'Endocam' && mapping.productLine == 'ENDOCAM') {
                foundEndocamMapping = true;
                break;
            }
        }
        System.assertEquals(true, foundEndocamMapping, 'Expected Endocam mapping.');
    }

    @IsTest
    static void testGetItemTypeOptions() {
        Test.startTest();
        List<ReturnOrderReceivingController.PicklistOption> options =
            ReturnOrderReceivingController.getItemTypeOptions();
        Test.stopTest();

        System.assertNotEquals(null, options, 'Expected item type options.');
    }

    @IsTest
    static void testGetProductsForLineCorrectionOtherProductLine() {
        adb_Product2 otherLineProductBuilder = new adb_Product2()
            .name('Other Line Product')
            .isActive(true)
            .productLine('Other Line');
        otherLineProductBuilder.persist();
        Product2 otherLineProduct = [
            SELECT Id
            FROM Product2
            WHERE Id = :otherLineProductBuilder.id
        ];

        Test.startTest();
        List<ReturnOrderReceivingController.ProductPicklistOption> options =
            ReturnOrderReceivingController.getProductsForLineCorrection(
                'Other Line',
                otherLineProduct.Id,
                false
            );
        Test.stopTest();

        System.assert(!options.isEmpty(), 'Expected products for other product line.');
    }

    @IsTest
    static void testGetProductsForLineCorrectionBlankProductLineReturnsEmpty() {
        Test.startTest();
        List<ReturnOrderReceivingController.ProductPicklistOption> options =
            ReturnOrderReceivingController.getProductsForLineCorrection(null, null, false);
        Test.stopTest();

        System.assertEquals(0, options.size(), 'Expected empty product options.');
    }

    @IsTest
    static void testGetAccessoryTypeOptions() {
        Test.startTest();
        List<ReturnOrderReceivingController.PicklistOption> options =
            ReturnOrderReceivingController.getAccessoryTypeOptions();
        Test.stopTest();

        System.assertNotEquals(null, options, 'Expected accessory type options.');
    }

    @IsTest
    static void testGetAccessoryConditionOptions() {
        Test.startTest();
        List<ReturnOrderReceivingController.PicklistOption> options =
            ReturnOrderReceivingController.getAccessoryConditionOptions();
        Test.stopTest();

        System.assertNotEquals(null, options, 'Expected accessory condition options.');
    }

    @IsTest
    static void testReceiveSerializedWithAccessoriesCreatesAccessoryWorkOrderLineItems() {
        ReturnOrder returnOrder = getReturnOrderByType('Serialized');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);

        List<ReturnOrderReceivingController.PicklistOption> accessoryTypes =
            ReturnOrderReceivingController.getAccessoryTypeOptions();
        if (accessoryTypes == null || accessoryTypes.size() < 2) {
            return;
        }
        String firstAccessoryType = accessoryTypes[0].value;
        String secondAccessoryType = accessoryTypes[1].value;

        ReturnOrderReceivingController.AccessoryInput containerAccessory =
            new ReturnOrderReceivingController.AccessoryInput();
        containerAccessory.accessoryType = firstAccessoryType;
        containerAccessory.condition = 'Good';
        containerAccessory.storageLocation = 'Bin A';
        containerAccessory.quantity = 2;

        ReturnOrderReceivingController.AccessoryInput cableAccessory =
            new ReturnOrderReceivingController.AccessoryInput();
        cableAccessory.accessoryType = secondAccessoryType;
        cableAccessory.condition = 'Damaged';
        cableAccessory.storageLocation = 'Drawer 1';
        cableAccessory.quantity = 1;

        ReturnOrderReceivingController.LineReceiveInput lineInput =
            new ReturnOrderReceivingController.LineReceiveInput();
        lineInput.lineItemId = String.valueOf(lineItem.Id);
        lineInput.quantityReceived = 1;
        lineInput.accessories = new List<ReturnOrderReceivingController.AccessoryInput>{
            containerAccessory,
            cableAccessory
        };

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                null,
                toLineInputsJson(new List<ReturnOrderReceivingController.LineReceiveInput>{ lineInput }),
                null
            );
        Test.stopTest();

        WorkOrder childWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE ReturnOrderLineItemId = :lineItem.Id
            AND ParentWorkOrderId = :result.primaryWorkOrderId
            LIMIT 1
        ];
        System.assertNotEquals(null, childWorkOrder.Id, 'Expected child work order.');
        System.assertEquals(
            result.primaryWorkOrderId,
            result.navigationWorkOrderId,
            'Serialized receive should navigate to the parent work order.'
        );

        List<WorkOrderLineItem> accessoryLineItems = [
            SELECT
                WorkOrderId,
                IsAccessory__c,
                AccessoryType__c,
                Condition__c,
                StorageLocation__c,
                UnitQty__c,
                LineType__c,
                RecordType.DeveloperName,
                ParentWorkOrderLineItemId,
                Item__c,
                ItemCode__c,
                ItemDescription__c
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :childWorkOrder.Id
            AND IsAccessory__c = TRUE
        ];
        System.assertEquals(2, accessoryLineItems.size(), 'Expected two accessory WOLIs.');

        WorkOrderLineItem productServicedLineItem = [
            SELECT Id
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :childWorkOrder.Id
            AND LineType__c = 'Product Serviced'
            AND IsAccessory__c = FALSE
            LIMIT 1
        ];

        Map<String, WorkOrderLineItem> accessoriesByType = new Map<String, WorkOrderLineItem>();
        for (WorkOrderLineItem accessoryLineItem : accessoryLineItems) {
            accessoriesByType.put(accessoryLineItem.AccessoryType__c, accessoryLineItem);
        }

        WorkOrderLineItem cableLineItem = accessoriesByType.get(secondAccessoryType);
        WorkOrderLineItem containerLineItem = accessoriesByType.get(firstAccessoryType);
        System.assertNotEquals(null, cableLineItem, 'Expected second accessory WOLI.');
        System.assertNotEquals(null, containerLineItem, 'Expected first accessory WOLI.');
        System.assertEquals(childWorkOrder.Id, cableLineItem.WorkOrderId);
        System.assertEquals(true, cableLineItem.IsAccessory__c);
        System.assertEquals('Accessory', cableLineItem.LineType__c);
        System.assertEquals('ProductServiced', cableLineItem.RecordType.DeveloperName);
        System.assertEquals(
            productServicedLineItem.Id,
            cableLineItem.ParentWorkOrderLineItemId,
            'Expected parent product serviced WOLI on accessory WOLI.'
        );
        System.assertEquals(lineItem.Product2Id, cableLineItem.Item__c);
        System.assertEquals('RCV-TEST-ITEM', cableLineItem.ItemCode__c);
        System.assertEquals(
            'Receiving test product description',
            cableLineItem.ItemDescription__c
        );
        System.assertEquals('Damaged', cableLineItem.Condition__c);
        System.assertEquals(1, cableLineItem.UnitQty__c);
        System.assertEquals('Good', containerLineItem.Condition__c);
        System.assertEquals('Bin A', containerLineItem.StorageLocation__c);
        System.assertEquals(2, containerLineItem.UnitQty__c);
        System.assertNotEquals(null, result.primaryWorkOrderId, 'Expected parent work order.');
    }

    @IsTest
    static void testReceiveSerializedAccessoriesUseNewChildWorkOrderNotLegacy() {
        ReturnOrder returnOrder = getReturnOrderByType('Serialized');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);
        ReturnOrder returnOrderDetails = [
            SELECT AccountId, DestinationLocationId
            FROM ReturnOrder
            WHERE Id = :returnOrder.Id
            LIMIT 1
        ];

        Schema.RecordTypeInfo devicesRecordType = Schema.SObjectType.WorkOrder
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCenterDevices');
        if (devicesRecordType == null || !devicesRecordType.isAvailable()) {
            return;
        }

        adb_WorkOrder legacyChildWorkOrderBuilder = new adb_WorkOrder()
            .status('Received')
            .subject('Legacy Child Work Order')
            .setRecordType('RepairCenterDevices');
        legacyChildWorkOrderBuilder.set(WorkOrder.ReturnOrderLineItemId, lineItem.Id);
        legacyChildWorkOrderBuilder.set(WorkOrder.SubStatus__c, 'Ready for Eval');
        legacyChildWorkOrderBuilder.set(WorkOrder.AccountId, returnOrderDetails.AccountId);
        legacyChildWorkOrderBuilder.set(WorkOrder.LocationId, returnOrderDetails.DestinationLocationId);
        legacyChildWorkOrderBuilder.persist();
        WorkOrder legacyChildWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Id = :legacyChildWorkOrderBuilder.id
        ];

        List<ReturnOrderReceivingController.PicklistOption> accessoryTypes =
            ReturnOrderReceivingController.getAccessoryTypeOptions();
        if (accessoryTypes == null || accessoryTypes.isEmpty()) {
            return;
        }

        ReturnOrderReceivingController.AccessoryInput accessory =
            new ReturnOrderReceivingController.AccessoryInput();
        accessory.accessoryType = accessoryTypes[0].value;
        accessory.condition = 'Good';
        accessory.storageLocation = 'Shelf 1';
        accessory.quantity = 1;

        ReturnOrderReceivingController.LineReceiveInput lineInput =
            new ReturnOrderReceivingController.LineReceiveInput();
        lineInput.lineItemId = String.valueOf(lineItem.Id);
        lineInput.quantityReceived = 1;
        lineInput.accessories = new List<ReturnOrderReceivingController.AccessoryInput>{ accessory };

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                null,
                toLineInputsJson(new List<ReturnOrderReceivingController.LineReceiveInput>{ lineInput }),
                null
            );
        Test.stopTest();

        System.assertEquals(
            result.primaryWorkOrderId,
            result.navigationWorkOrderId,
            'Serialized receive should navigate to the parent work order.'
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM WorkOrderLineItem WHERE WorkOrderId = :legacyChildWorkOrder.Id],
            'Legacy work order should not receive accessory line items.'
        );

        WorkOrder newChildWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE ReturnOrderLineItemId = :lineItem.Id
            AND ParentWorkOrderId = :result.primaryWorkOrderId
            LIMIT 1
        ];
        System.assertNotEquals(
            legacyChildWorkOrder.Id,
            newChildWorkOrder.Id,
            'Expected a new child work order for this receive.'
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM WorkOrderLineItem
                WHERE WorkOrderId = :newChildWorkOrder.Id
                AND IsAccessory__c = TRUE
            ],
            'Expected accessory WOLI on the newly created child work order.'
        );
    }

    @IsTest
    static void testReceiveSerializedWithAccessoriesFromJsonPayload() {
        ReturnOrder returnOrder = getReturnOrderByType('Serialized');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);

        String accessoryType = ReturnOrderReceivingController.getAccessoryTypeOptions()[0].value;
        String accessoryCondition = ReturnOrderReceivingController.getAccessoryConditionOptions()[0].value;

        String lineInputsJson =
            '[{' +
            '"lineItemId":"' +
            String.valueOf(lineItem.Id) +
            '",' +
            '"quantityReceived":1,' +
            '"accessories":[{' +
            '"accessoryType":"' +
            accessoryType +
            '",' +
            '"condition":"' +
            accessoryCondition +
            '",' +
            '"storageLocation":"Shelf 3",' +
            '"quantity":3' +
            '}]' +
            '}]';

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                null,
                lineInputsJson,
                null
            );
        Test.stopTest();

        System.assertEquals(
            result.primaryWorkOrderId,
            result.navigationWorkOrderId,
            'Serialized receive should navigate to the parent work order.'
        );

        WorkOrder childWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE ReturnOrderLineItemId = :lineItem.Id
            AND ParentWorkOrderId = :result.primaryWorkOrderId
            LIMIT 1
        ];
        System.assertNotEquals(null, childWorkOrder.Id, 'Expected child work order.');
        WorkOrderLineItem accessoryLineItem = [
            SELECT IsAccessory__c, AccessoryType__c, Condition__c, StorageLocation__c, UnitQty__c,
                LineType__c, RecordType.DeveloperName, ParentWorkOrderLineItemId, Item__c,
                ItemCode__c, ItemDescription__c
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :childWorkOrder.Id
            AND IsAccessory__c = TRUE
            LIMIT 1
        ];
        System.assertEquals(true, accessoryLineItem.IsAccessory__c, 'Expected accessory WOLI.');
        System.assertEquals('Accessory', accessoryLineItem.LineType__c);
        System.assertEquals('ProductServiced', accessoryLineItem.RecordType.DeveloperName);
        System.assertNotEquals(null, accessoryLineItem.ParentWorkOrderLineItemId);
        System.assertEquals(lineItem.Product2Id, accessoryLineItem.Item__c);
        System.assertEquals(accessoryType, accessoryLineItem.AccessoryType__c);
        System.assertEquals(accessoryCondition, accessoryLineItem.Condition__c);
        System.assertEquals('Shelf 3', accessoryLineItem.StorageLocation__c);
        System.assertEquals(3, accessoryLineItem.UnitQty__c);
        System.assertNotEquals(null, result.primaryWorkOrderId, 'Expected parent work order.');
    }

    @IsTest
    static void testReceiveOtherWithItemTypeCorrectionUpdatesProductLine() {
        ReturnOrder returnOrder = getReturnOrderByType('Other');
        ReturnOrderLineItem lineItem = [
            SELECT Id, ItemType__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrder.Id
            LIMIT 1
        ];

        Set<String> validItemTypes = new Set<String>();
        for (
            Schema.PicklistEntry entry :
            ReturnOrderLineItem.ItemType__c.getDescribe().getPicklistValues()
        ) {
            if (entry.isActive()) {
                validItemTypes.add(entry.getValue());
            }
        }

        String newItemType = null;
        String newProductLine = null;
        for (
            ReturnOrderReceivingController.ItemTypeProductLineMapping mapping :
            ReturnOrderReceivingController.getItemTypeProductLineMappings()
        ) {
            if (
                mapping.itemType != lineItem.ItemType__c &&
                validItemTypes.contains(mapping.itemType) &&
                String.isNotBlank(mapping.productLine)
            ) {
                newItemType = mapping.itemType;
                newProductLine = mapping.productLine;
                break;
            }
        }
        System.assertNotEquals(
            null,
            newItemType,
            'Expected a valid alternate item type mapping in this org.'
        );

        adb_Product2 mappedProductBuilder = new adb_Product2()
            .name('Other Mapped Product')
            .isActive(true)
            .productLine(newProductLine);
        mappedProductBuilder.persist();
        ensureDefaultPricebookForTest(mappedProductBuilder.id);
        Product2 mappedProduct = [
            SELECT Id
            FROM Product2
            WHERE Id = :mappedProductBuilder.id
        ];

        ReturnOrderReceivingController.LineReceiveInput lineInput =
            new ReturnOrderReceivingController.LineReceiveInput();
        lineInput.lineItemId = String.valueOf(lineItem.Id);
        lineInput.quantityReceived = 2;
        lineInput.quantityReturned = 2;
        lineInput.hasCorrections = true;
        lineInput.itemType = newItemType;
        lineInput.productLine = newProductLine;
        lineInput.productId = mappedProduct.Id;
        lineInput.serialNumber = 'OTHER-123';
        lineInput.hospitalTrayName = 'Updated Tray';

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                null,
                toLineInputsJson(new List<ReturnOrderReceivingController.LineReceiveInput>{ lineInput }),
                null
            );
        Test.stopTest();

        lineItem = [
            SELECT ItemType__c, ProductLine__c, Product2Id, HospitalReferencedTrayName__c
            FROM ReturnOrderLineItem
            WHERE Id = :lineItem.Id
        ];
        System.assertEquals(newItemType, lineItem.ItemType__c, 'Expected item type correction.');
        System.assertEquals(newProductLine, lineItem.ProductLine__c, 'Expected mapped product line.');
        System.assertEquals(mappedProduct.Id, lineItem.Product2Id, 'Expected product correction.');
        System.assertEquals('Updated Tray', lineItem.HospitalReferencedTrayName__c, 'Expected tray correction.');

        WorkOrder workOrder = [
            SELECT SubStatus__c
            FROM WorkOrder
            WHERE Id = :result.primaryWorkOrderId
        ];
        System.assertEquals(
            'Customer Care',
            workOrder.SubStatus__c,
            'Expected customer care when other product is corrected.'
        );

        WorkOrderLineItem workOrderLineItem = [
            SELECT Product__c, Product2Id, PricebookEntryId, LineType__c, Quantity, TrayName__c, SerialNumber__c
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :result.primaryWorkOrderId
            LIMIT 1
        ];
        System.assertEquals(null, workOrderLineItem.Product__c, 'Other WOLI should not use custom Product__c.');
        System.assert(
            workOrderLineItem.PricebookEntryId != null ||
                workOrderLineItem.Product2Id == mappedProduct.Id,
            'Expected WOLI product from screen.'
        );
        System.assertEquals('Product Serviced', workOrderLineItem.LineType__c, 'Expected product serviced line type.');
        System.assertEquals(2, workOrderLineItem.Quantity, 'Expected WOLI quantity from screen.');
        System.assertEquals('Updated Tray', workOrderLineItem.TrayName__c, 'Expected WOLI tray from screen.');
        System.assertEquals('OTHER-123', workOrderLineItem.SerialNumber__c, 'Expected WOLI serial from screen.');
    }

    @IsTest
    static void testGetReceivingContextIncludesRepairCenterAddress() {
        ReturnOrder returnOrder = getReturnOrderByType('Serialized');

        Test.startTest();
        ReturnOrderReceivingController.ReceivingContext context =
            ReturnOrderReceivingController.getReceivingContext(returnOrder.Id);
        Test.stopTest();

        System.assertNotEquals(null, context.repairCenterName, 'Expected repair center name.');
    }

    @IsTest
    static void testReceiveContaminatedOtherReturnOrder() {
        ReturnOrder returnOrder = getReturnOrderByType('Other');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult result =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                true,
                null,
                toLineInputsJson(lineItem.Id, 2),
                null
            );
        Test.stopTest();

        WorkOrder workOrder = [
            SELECT SubStatus__c, Contaminated__c
            FROM WorkOrder
            WHERE Id = :result.primaryWorkOrderId
        ];
        System.assertEquals('Contaminated', workOrder.SubStatus__c, 'Expected contaminated sub status.');
        System.assertEquals(true, workOrder.Contaminated__c, 'Expected contaminated flag.');
    }

    @IsTest
    static void testReceiveSecondSerializedLineCreatesNewParentWorkOrder() {
        ReturnOrder returnOrder = getReturnOrderByType('Serialized');
        List<ReturnOrderLineItem> lineItems = [
            SELECT Id, CustomerPO__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrder.Id
            ORDER BY CustomerPO__c ASC
        ];

        ReturnOrderReceivingController.BulkReceiveResult firstResult =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                null,
                toLineInputsJson(lineItems[0].Id, 1),
                null
            );

        Test.startTest();
        ReturnOrderReceivingController.BulkReceiveResult secondResult =
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                null,
                toLineInputsJson(lineItems[1].Id, 1),
                null
            );
        Test.stopTest();

        System.assertNotEquals(
            firstResult.primaryWorkOrderId,
            secondResult.primaryWorkOrderId,
            'Expected second receive to create a new parent work order.'
        );
        System.assertEquals(
            secondResult.primaryWorkOrderId,
            [
                SELECT WorkOrder__c
                FROM ReturnOrder
                WHERE Id = :returnOrder.Id
            ]
            .WorkOrder__c,
            'Expected return order linked to latest parent work order.'
        );
        lineItems = [
            SELECT Status__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrder.Id
            ORDER BY CustomerPO__c ASC
        ];
        System.assertEquals('Received', lineItems[0].Status__c, 'Expected first line received.');
        System.assertEquals('Received', lineItems[1].Status__c, 'Expected second line received.');
        returnOrder = [
            SELECT Status
            FROM ReturnOrder
            WHERE Id = :returnOrder.Id
        ];
        System.assertEquals('Received', returnOrder.Status, 'Expected return order received when all lines received.');
    }

    @IsTest
    static void testReceiveValidationMissingReceiver() {
        ReturnOrder returnOrder = getReturnOrderByType('Serialized');
        ReturnOrderLineItem lineItem = [
            SELECT Id
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrder.Id
            AND CustomerPO__c = 'PO-SERIAL'
            LIMIT 1
        ];

        Boolean exceptionThrown = false;
        try {
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                null,
                testReceivedDateTime(),
                false,
                null,
                toLineInputsJson(lineItem.Id, 1),
                null
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }

        System.assertEquals(true, exceptionThrown, 'Expected receiver validation.');
    }

    @IsTest
    static void testGetReceivingContextRequiresReturnOrderId() {
        Boolean exceptionThrown = false;
        try {
            ReturnOrderReceivingController.getReceivingContext(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        System.assertEquals(true, exceptionThrown, 'Expected validation for missing return order.');
    }

    @IsTest
    static void testReceiveValidationMissingLineItemId() {
        ReturnOrder returnOrder = getReturnOrderByType('Serialized');
        ReturnOrderReceivingController.LineReceiveInput lineInput =
            new ReturnOrderReceivingController.LineReceiveInput();
        lineInput.quantityReceived = 1;

        Boolean exceptionThrown = false;
        try {
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                null,
                toLineInputsJson(new List<ReturnOrderReceivingController.LineReceiveInput>{ lineInput }),
                null
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }

        System.assertEquals(true, exceptionThrown, 'Expected line item Id validation.');
    }

    @IsTest
    static void testGetRecentCreatedReturnOrders() {
        Test.startTest();
        List<ReturnOrderReceivingController.ReturnOrderSummaryRow> rows =
            ReturnOrderReceivingController.getRecentCreatedReturnOrders();
        Test.stopTest();

        System.assert(!rows.isEmpty(), 'Expected at least one Created return order.');
        for (ReturnOrderReceivingController.ReturnOrderSummaryRow row : rows) {
            ReturnOrder returnOrder = [
                SELECT Status
                FROM ReturnOrder
                WHERE Id = :row.id
                LIMIT 1
            ];
            System.assertEquals('Created', returnOrder.Status, 'Expected only Created return orders.');
        }
    }

    @IsTest
    static void testFindReturnOrderByNumberSuccess() {
        ReturnOrder returnOrder = [
            SELECT Id, ReturnOrderNumber
            FROM ReturnOrder
            WHERE Status = 'Created'
            LIMIT 1
        ];

        Test.startTest();
        String returnOrderId = ReturnOrderReceivingController.findReturnOrderByNumber(
            returnOrder.ReturnOrderNumber
        );
        Test.stopTest();

        System.assertEquals(returnOrder.Id, returnOrderId, 'Expected matching return order id.');
    }

    @IsTest
    static void testRedirectLineItem() {
        Account account = [
            SELECT Id
            FROM Account
            WHERE Name = 'Return Order Receiving Test Account'
            LIMIT 1
        ];
        Schema.Location sourceRepairCenter = [
            SELECT Id
            FROM Location
            WHERE Name = 'Receiving Test Repair Center'
            LIMIT 1
        ];
        adb_Location alternateRepairCenterBuilder = new adb_Location()
            .name('Receiving Redirect Alternate Center')
            .locationType('Repair Center');
        alternateRepairCenterBuilder.persist();
        Schema.Location alternateRepairCenter = [
            SELECT Id
            FROM Location
            WHERE Id = :alternateRepairCenterBuilder.id
        ];

        adb_ReturnOrder returnOrderBuilder = new adb_ReturnOrder()
            .status('Created');
        returnOrderBuilder.set(ReturnOrder.AccountId, account.Id);
        returnOrderBuilder.set(ReturnOrder.DestinationLocationId, sourceRepairCenter.Id);
        returnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
        returnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Serialized');

        Product2 product = [SELECT Id FROM Product2 LIMIT 1];

        adb_ReturnOrderLineItem lineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(returnOrderBuilder)
            .quantityReturned(1);
        lineBuilder.set(ReturnOrderLineItem.Product2Id, product.Id);
        lineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        lineBuilder.set(ReturnOrderLineItem.ProductLine__c, 'Redirect Line');
        lineBuilder.set(ReturnOrderLineItem.CustomerPO__c, 'PO-RECEIVING-REDIRECT');
        lineBuilder.persist();
        ReturnOrderLineItem lineItem = [
            SELECT Id
            FROM ReturnOrderLineItem
            WHERE Id = :lineBuilder.id
        ];

        Test.startTest();
        ReturnOrderReceivingController.RedirectActionResult result =
            ReturnOrderReceivingController.redirectLineItem(
                lineItem.Id,
                alternateRepairCenter.Id,
                false
            );
        Test.stopTest();

        System.assertNotEquals(null, result.returnOrderId, 'Expected new return order id.');
        System.assertNotEquals(null, result.returnOrderNumber, 'Expected new return order number.');

        ReturnOrderLineItem redirectedLineItem = [
            SELECT Status__c
            FROM ReturnOrderLineItem
            WHERE Id = :lineItem.Id
        ];
        System.assertEquals('Redirected', redirectedLineItem.Status__c, 'Expected Redirected status.');
    }

    @IsTest
    static void testGetActiveInternalUsersAndRepairCenters() {
        Test.startTest();
        List<ReturnOrderReceivingController.PicklistOption> users =
            ReturnOrderReceivingController.getActiveInternalUsers();
        List<ReturnOrderReceivingController.PicklistOption> repairCenters =
            ReturnOrderReceivingController.getRepairCenterLocations();
        Test.stopTest();

        System.assert(!users.isEmpty(), 'Expected at least one internal user.');
        System.assert(!repairCenters.isEmpty(), 'Expected at least one repair center.');
    }

    @IsTest
    static void testGetAccountAssetsForCorrection() {
        Account account = [
            SELECT Id
            FROM Account
            WHERE Name = 'Return Order Receiving Test Account'
            LIMIT 1
        ];

        Test.startTest();
        List<ReturnOrderReceivingController.AccountAssetOption> options =
            ReturnOrderReceivingController.getAccountAssetsForCorrection(account.Id);
        Test.stopTest();

        System.assertNotEquals(null, options, 'Expected asset options list.');
    }

    @IsTest
    static void testValidateReturnOrderForReceiving() {
        ReturnOrder returnOrder = [
            SELECT Id
            FROM ReturnOrder
            WHERE Status = 'Created'
            LIMIT 1
        ];

        Test.startTest();
        String validatedId = ReturnOrderReceivingController.validateReturnOrderForReceiving(
            returnOrder.Id
        );
        Test.stopTest();

        System.assertEquals(returnOrder.Id, validatedId, 'Expected validated return order id.');
    }

    @IsTest
    static void testFindReturnOrderByNumberWithoutRoPrefix() {
        ReturnOrder returnOrder = [
            SELECT Id, ReturnOrderNumber
            FROM ReturnOrder
            WHERE Status = 'Created'
            LIMIT 1
        ];
        String numberWithoutPrefix = returnOrder.ReturnOrderNumber;
        if (numberWithoutPrefix.toUpperCase().startsWith('RO')) {
            numberWithoutPrefix = numberWithoutPrefix.substring(2).replaceFirst('^[-\\s]+', '');
        }

        Test.startTest();
        String returnOrderId = ReturnOrderReceivingController.findReturnOrderByNumber(
            numberWithoutPrefix
        );
        Test.stopTest();

        System.assertEquals(returnOrder.Id, returnOrderId, 'Expected lookup without RO prefix.');
    }

    @IsTest
    static void testGetProductsForLineCorrectionNullRequireServiceAssetType() {
        adb_Product2 productBuilder = new adb_Product2()
            .name('Nullable Require Line Product')
            .isActive(true)
            .productLine('Nullable Require Line')
            .productType('Service Asset');
        productBuilder.persist();

        Test.startTest();
        List<ReturnOrderReceivingController.ProductPicklistOption> options =
            ReturnOrderReceivingController.getProductsForLineCorrection(
                'Nullable Require Line',
                null,
                null
            );
        Test.stopTest();

        System.assert(!options.isEmpty(), 'Expected products when requireServiceAssetType is null.');
    }

    @IsTest
    static void testGetReceivingContextInvalidReturnOrderId() {
        Id invalidReturnOrderId =
            ReturnOrder.SObjectType.getDescribe().getKeyPrefix() + '000000000000';

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ReturnOrderReceivingController.getReceivingContext(invalidReturnOrderId);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Expected exception for invalid return order id.');
    }

    @IsTest
    static void testFindReturnOrderByNumberNotFound() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ReturnOrderReceivingController.findReturnOrderByNumber('RO-NONEXISTENT-99999');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Expected not found exception.');
    }

    @IsTest
    static void testGetAccountAssetsForCorrectionNullAccountId() {
        Test.startTest();
        List<ReturnOrderReceivingController.AccountAssetOption> options =
            ReturnOrderReceivingController.getAccountAssetsForCorrection(null);
        Test.stopTest();

        System.assertEquals(0, options.size(), 'Expected empty list for null account.');
    }

    @IsTest
    static void testValidateReturnOrderForReceivingNullId() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ReturnOrderReceivingController.validateReturnOrderForReceiving(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Expected validation for null id.');
    }

    @IsTest
    static void testValidateReturnOrderForReceivingCanceledReturnOrder() {
        Account account = [
            SELECT Id
            FROM Account
            WHERE Name = 'Return Order Receiving Test Account'
            LIMIT 1
        ];
        Schema.Location repairCenter = [
            SELECT Id
            FROM Location
            WHERE Name = 'Receiving Test Repair Center'
            LIMIT 1
        ];
        adb_ReturnOrder returnOrderBuilder = new adb_ReturnOrder()
            .status('Created');
        returnOrderBuilder.set(ReturnOrder.AccountId, account.Id);
        returnOrderBuilder.set(ReturnOrder.DestinationLocationId, repairCenter.Id);
        returnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
        returnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Serialized');

        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        adb_ReturnOrderLineItem lineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(returnOrderBuilder)
            .quantityReturned(1);
        lineBuilder.set(ReturnOrderLineItem.Product2Id, product.Id);
        lineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        lineBuilder.set(ReturnOrderLineItem.ProductLine__c, 'Canceled Validation Line');
        lineBuilder.set(ReturnOrderLineItem.CustomerPO__c, 'PO-CANCELED-VALIDATION');
        lineBuilder.persist();
        ReturnOrder returnOrder = [SELECT Id, Status, CancelReason__c FROM ReturnOrder WHERE Id = :returnOrderBuilder.id];

        String cancelReason = resolveCancelReasonForTest();
        returnOrder.Status = 'Canceled';
        returnOrder.CancelReason__c = cancelReason;
        update returnOrder;

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ReturnOrderReceivingController.validateReturnOrderForReceiving(returnOrder.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Expected canceled validation.');
    }

    @IsTest
    static void testRedirectLineItemMissingRepairCenter() {
        ReturnOrderLineItem lineItem = [
            SELECT Id
            FROM ReturnOrderLineItem
            WHERE Status__c = 'Created'
            LIMIT 1
        ];

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ReturnOrderReceivingController.redirectLineItem(lineItem.Id, null, false);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Expected repair center validation.');
    }

    @IsTest
    static void testRedirectLineItemSameRepairCenter() {
        ReturnOrder returnOrder = [
            SELECT Id, DestinationLocationId
            FROM ReturnOrder
            WHERE Status = 'Created'
            LIMIT 1
        ];
        ReturnOrderLineItem lineItem = [
            SELECT Id
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrder.Id
            AND Status__c = 'Created'
            LIMIT 1
        ];

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ReturnOrderReceivingController.redirectLineItem(
                lineItem.Id,
                returnOrder.DestinationLocationId,
                false
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Expected same repair center validation.');
    }

    @IsTest
    static void testRedirectLineItemBulkOpenLines() {
        Account account = [
            SELECT Id
            FROM Account
            WHERE Name = 'Return Order Receiving Test Account'
            LIMIT 1
        ];
        Schema.Location sourceRepairCenter = [
            SELECT Id
            FROM Location
            WHERE Name = 'Receiving Test Repair Center'
            LIMIT 1
        ];
        adb_Location alternateRepairCenterBuilder = new adb_Location()
            .name('Bulk Redirect Alternate Center')
            .locationType('Repair Center');
        alternateRepairCenterBuilder.persist();
        Schema.Location alternateRepairCenter = [
            SELECT Id
            FROM Location
            WHERE Id = :alternateRepairCenterBuilder.id
        ];

        adb_ReturnOrder returnOrderBuilder = new adb_ReturnOrder()
            .status('Created');
        returnOrderBuilder.set(ReturnOrder.AccountId, account.Id);
        returnOrderBuilder.set(ReturnOrder.DestinationLocationId, sourceRepairCenter.Id);
        returnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
        returnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Serialized');

        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        adb_ReturnOrderLineItem firstLineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(returnOrderBuilder)
            .quantityReturned(1);
        firstLineBuilder.set(ReturnOrderLineItem.Product2Id, product.Id);
        firstLineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        firstLineBuilder.set(ReturnOrderLineItem.ProductLine__c, 'Bulk Redirect');
        firstLineBuilder.set(ReturnOrderLineItem.CustomerPO__c, 'PO-BULK-1');

        adb_ReturnOrderLineItem secondLineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(returnOrderBuilder)
            .quantityReturned(1);
        secondLineBuilder.set(ReturnOrderLineItem.Product2Id, product.Id);
        secondLineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        secondLineBuilder.set(ReturnOrderLineItem.ProductLine__c, 'Bulk Redirect');
        secondLineBuilder.set(ReturnOrderLineItem.CustomerPO__c, 'PO-BULK-2');
        secondLineBuilder.persist();

        ReturnOrder returnOrder = [SELECT Id FROM ReturnOrder WHERE Id = :returnOrderBuilder.id];

        Test.startTest();
        ReturnOrderReceivingController.RedirectActionResult result =
            ReturnOrderReceivingController.redirectLineItem(
                firstLineBuilder.id,
                alternateRepairCenter.Id,
                true
            );
        Test.stopTest();

        System.assertNotEquals(null, result.returnOrderId, 'Expected new return order from bulk redirect.');
        ReturnOrder updatedSource = [
            SELECT Status
            FROM ReturnOrder
            WHERE Id = :returnOrder.Id
        ];
        System.assertEquals('Redirected', updatedSource.Status, 'Expected source return order redirected.');
    }

    @IsTest
    static void testLinkPhotosToWorkOrderWithContentDocument() {
        Account account = [
            SELECT Id
            FROM Account
            WHERE Name = 'Return Order Receiving Test Account'
            LIMIT 1
        ];
        Schema.RecordTypeInfo repairCenterDevicesRecordType = Schema.SObjectType.WorkOrder
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCenterDevices');
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .status('New');
        workOrderBuilder.set(WorkOrder.AccountId, account.Id);
        if (repairCenterDevicesRecordType != null && repairCenterDevicesRecordType.isAvailable()) {
            workOrderBuilder.setRecordType('RepairCenterDevices');
        }
        workOrderBuilder.persist();
        WorkOrder workOrder = [SELECT Id FROM WorkOrder WHERE Id = :workOrderBuilder.id];

        Id contentDocumentId = createTestContentDocumentId();

        Test.startTest();
        ReturnOrderReceivingController.linkPhotosToWorkOrder(
            workOrder.Id,
            new List<Id>{ contentDocumentId }
        );
        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :workOrder.Id
            AND ContentDocumentId = :contentDocumentId
        ];
        System.assertEquals(1, links.size(), 'Expected photo linked to work order.');
    }

    @IsTest
    static void testLinkPhotosToWorkOrderNullInputs() {
        Test.startTest();
        ReturnOrderReceivingController.linkPhotosToWorkOrder(null, null);
        ReturnOrderReceivingController.linkPhotosToWorkOrder(null, new List<Id>());
        Test.stopTest();

        System.assert(true, 'Null inputs should return without error.');
    }

    private static String resolveCancelReasonForTest() {
        for (Schema.PicklistEntry entry : ReturnOrder.CancelReason__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return 'Other';
    }

    private static Id createTestContentDocumentId() {
        adb_ContentVersion contentVersionBuilder = new adb_ContentVersion()
            .title('Receive Test Photo')
            .pathOnClient('photo.jpg')
            .versionData(Blob.valueOf('test photo content'))
            .isMajorVersion(true);
        contentVersionBuilder.persist();
        ContentVersion contentVersion = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersionBuilder.id
        ];
        return contentVersion.ContentDocumentId;
    }
    // --- START RELEVANT TO GW-3337 ---
    /**
     * @description
     * Tests that receiving a RIGID SCOPE line item successfully routes
     * the child WorkOrder directly to Evaluate status and Triage substatus.
     */
    @IsTest
    static void testReceiveRigidScopeSetsEvaluateAndTriage() {

        /********************************************
        * SETUP
        ********************************************/
        User contextUser = new User(Id = UserInfo.getUserId());
        
        ReturnOrder returnOrder = getReturnOrderByType('Serialized');
        ReturnOrderLineItem lineItem = getLineItemForReturnOrder(returnOrder.Id);
        
        // WO_003 validates Triage via Product__r.ProductLine__c (ProductLine_f__c),
        // so both ROLI and Product2 must be RIGID SCOPE.
        lineItem.ProductLine__c = 'RIGID SCOPE';
        update lineItem;
        update new Product2(Id = lineItem.Product2Id, ProductLine__c = 'RIGID SCOPE');
        ReturnOrderReceivingController.resetRepairCenterDefaultsCacheForTest();
        ensureDefaultPricebookForTest(lineItem.Product2Id);
        
        String lineInputsJson = toLineInputsJson(lineItem.Id, 1);

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(
            1, 
            [SELECT Count() FROM ReturnOrderLineItem WHERE Id = :lineItem.Id AND ProductLine__c = 'RIGID SCOPE'],
            'The ReturnOrderLineItem should be updated to the RIGID SCOPE product line.'
        );

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        System.runAs(contextUser) {
            ReturnOrderReceivingController.receiveReturnOrder(
                returnOrder.Id,
                UserInfo.getUserId(),
                testReceivedDateTime(),
                false,
                null,
                lineInputsJson,
                null
            );
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        WorkOrder childWorkOrder = [
            SELECT Status, SubStatus__c
            FROM WorkOrder
            WHERE ReturnOrderLineItemId = :lineItem.Id
            AND ParentWorkOrderId != null
            LIMIT 1
        ];
        
        System.assertEquals('Evaluate', childWorkOrder.Status, 'The child WorkOrder Status should be Evaluate for Rigid Scopes.');
        System.assertEquals('Triage', childWorkOrder.SubStatus__c, 'The child WorkOrder SubStatus should be Triage for Rigid Scopes.');
    }
    // --- END RELEVANT TO GW-3337 ---

}