/**
 * @description Tests for CancelReturnOrderController (GW-1203).
 */
@IsTest(isParallel=false)
private class CancelReturnOrderControllerTest {

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
            insert new PermissionSetAssignment(
                AssigneeId = UserInfo.getUserId(),
                PermissionSetId = permissionSets[0].Id
            );
        }
    }

    @TestSetup
    static void setupData() {
        assignPermissionSetIfNeeded('System_Administrator');
        assignPermissionSetIfNeeded('Return_Order_Line_Items_Access');

        Account account = new Account(
            Name = 'Cancel Return Order Test Account',
            SystemID__c = 'LEG-1203',
            CustomerAddressOperatingUnit__c = '82',
            SourceSystemID__c = 'TEST-ORACLE-1203'
        );
        insert account;

        Schema.Location repairCenter = new Schema.Location(
            Name = 'Cancel Test Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        ReturnOrder returnOrder = new ReturnOrder(
            AccountId = account.Id,
            Status = 'Created',
            DestinationLocationId = repairCenter.Id,
            OperatingUnit__c = '82'
        );
        insert returnOrder;

        Product2 product = new Product2(
            Name = 'Cancel Test Product',
            IsActive = true
        );
        insert product;

        insert new ReturnOrderLineItem(
            ReturnOrderId = returnOrder.Id,
            Product2Id = product.Id,
            QuantityReturned = 1,
            Status__c = 'Created',
            ProductLine__c = 'Test Line',
            CustomerPO__c = 'PO-CANCEL'
        );
    }

    @IsTest
    static void testGetCancelContextForCreatedReturnOrder() {
        ReturnOrder returnOrder = [
            SELECT Id, ReturnOrderNumber
            FROM ReturnOrder
            LIMIT 1
        ];

        Test.startTest();
        CancelReturnOrderController.CancelContext context =
            CancelReturnOrderController.getCancelContext(returnOrder.Id);
        Test.stopTest();

        System.assertEquals(returnOrder.Id, context.returnOrderId);
        System.assertEquals(returnOrder.ReturnOrderNumber, context.returnOrderNumber);
        System.assertEquals('Created', context.status);
        System.assertEquals(true, context.canCancel);
        System.assert(context.cancelReasonOptions.size() > 0);
    }

    @IsTest
    static void testCancelReturnOrderSuccess() {
        ReturnOrder returnOrder = [
            SELECT Id
            FROM ReturnOrder
            LIMIT 1
        ];

        Test.startTest();
        CancelReturnOrderController.CancelResult result =
            CancelReturnOrderController.cancelReturnOrder(
                returnOrder.Id,
                'Lost In-Transit',
                'Package never arrived.'
            );
        Test.stopTest();

        System.assertEquals(returnOrder.Id, result.returnOrderId);
        System.assertEquals('Canceled', result.status);

        ReturnOrder updatedReturnOrder = [
            SELECT Status, CancelReason__c, CancelReasonNotes__c
            FROM ReturnOrder
            WHERE Id = :returnOrder.Id
        ];
        System.assertEquals('Canceled', updatedReturnOrder.Status);
        System.assertEquals('Lost In-Transit', updatedReturnOrder.CancelReason__c);
        System.assertEquals(
            'Package never arrived.',
            updatedReturnOrder.CancelReasonNotes__c
        );

        List<ReturnOrderLineItem> lineItems = [
            SELECT Status__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrder.Id
        ];
        System.assertEquals(1, lineItems.size());
        System.assertEquals('Canceled', lineItems[0].Status__c);
    }

    @IsTest
    static void testCancelReturnOrderRejectsAlreadyCanceled() {
        ReturnOrder returnOrder = [
            SELECT Id
            FROM ReturnOrder
            LIMIT 1
        ];
        returnOrder.Status = 'Canceled';
        returnOrder.CancelReason__c = 'Lost In-Transit';
        update returnOrder;

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            CancelReturnOrderController.cancelReturnOrder(
                returnOrder.Id,
                'No Movement in 90 Days',
                null
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testCancelReturnOrderRejectsWorkOrderCount() {
        ReturnOrder returnOrder = [
            SELECT Id
            FROM ReturnOrder
            LIMIT 1
        ];
        returnOrder.WOCount__c = 1;
        update returnOrder;

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            CancelReturnOrderController.cancelReturnOrder(
                returnOrder.Id,
                'Lost In-Transit',
                null
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testCancelReturnOrderRequiresReason() {
        ReturnOrder returnOrder = [
            SELECT Id
            FROM ReturnOrder
            LIMIT 1
        ];

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            CancelReturnOrderController.cancelReturnOrder(returnOrder.Id, null, null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testCancelReturnOrderRejectsReceivedLineItems() {
        ReturnOrder returnOrder = [
            SELECT Id
            FROM ReturnOrder
            LIMIT 1
        ];
        ReturnOrderLineItem lineItem = [
            SELECT Id
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrder.Id
            LIMIT 1
        ];
        lineItem.Status__c = 'Received';
        update lineItem;

        CancelReturnOrderController.CancelContext context =
            CancelReturnOrderController.getCancelContext(returnOrder.Id);
        System.assertEquals(false, context.canCancel);

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            CancelReturnOrderController.cancelReturnOrder(
                returnOrder.Id,
                'Lost In-Transit',
                null
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testGetCancelContextRequiresId() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            CancelReturnOrderController.getCancelContext(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testGetCancelContextForCanceledReturnOrder() {
        ReturnOrder returnOrder = [
            SELECT Id
            FROM ReturnOrder
            LIMIT 1
        ];
        returnOrder.Status = 'Canceled';
        returnOrder.CancelReason__c = 'Lost In-Transit';
        update returnOrder;

        CancelReturnOrderController.CancelContext context =
            CancelReturnOrderController.getCancelContext(returnOrder.Id);

        System.assertEquals(false, context.canCancel);
        System.assertNotEquals(null, context.blockReason);
    }

    @IsTest
    static void testGetCancelContextForReceivedReturnOrder() {
        ReturnOrder returnOrder = [
            SELECT Id
            FROM ReturnOrder
            LIMIT 1
        ];
        returnOrder.Status = 'Received';
        update returnOrder;

        CancelReturnOrderController.CancelContext context =
            CancelReturnOrderController.getCancelContext(returnOrder.Id);

        System.assertEquals(false, context.canCancel);
        System.assert(
            context.blockReason.contains('received'),
            'Expected received status block reason.'
        );
    }

    @IsTest
    static void testCancelReturnOrderRejectsClosedStatus() {
        ReturnOrder returnOrder = [
            SELECT Id
            FROM ReturnOrder
            LIMIT 1
        ];
        returnOrder.Status = 'Closed';
        update returnOrder;

        CancelReturnOrderController.CancelContext context =
            CancelReturnOrderController.getCancelContext(returnOrder.Id);
        System.assertEquals(false, context.canCancel);

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            CancelReturnOrderController.cancelReturnOrder(
                returnOrder.Id,
                'Lost In-Transit',
                null
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }
}