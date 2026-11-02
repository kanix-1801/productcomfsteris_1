/**
 * Temporary diagnostic test to surface the underlying receiving context error.
 */
@IsTest(isParallel=false)
private class ReceivingContextDiagTest {

    @TestSetup
    static void setupPermissionSets() {
        for (PermissionSet permissionSet : [
            SELECT Id
            FROM PermissionSet
            WHERE Name IN ('System_Administrator', 'ProcessReturnOrders')
        ]) {
            insert new PermissionSetAssignment(
                AssigneeId = UserInfo.getUserId(),
                PermissionSetId = permissionSet.Id
            );
        }
    }

    @IsTest
    static void surfaceReturnOrderQueryError() {
        ReturnOrder returnOrder = [
            SELECT Id
            FROM ReturnOrder
            WHERE ReturnOrderType__c = 'Serialized'
            LIMIT 1
        ];
        if (returnOrder == null) {
            Assert.fail('DIAGNOSTIC_ERROR: No serialized ReturnOrder found in org.');
        }

        try {
            List<ReturnOrder> rows = [
                SELECT
                    Id,
                    ReturnOrderNumber,
                    ReturnOrderType__c,
                    AccountId,
                    Account.Name,
                    DestinationLocationId,
                    DestinationLocation.Name,
                    QuantityReturned__c,
                    QuantityReceived__c
                FROM ReturnOrder
                WHERE Id = :returnOrder.Id
                WITH USER_MODE
                LIMIT 1
            ];
            Assert.isFalse(rows.isEmpty(), 'Expected return order row.');
        } catch (Exception e) {
            Assert.fail('DIAGNOSTIC_RO_QUERY: ' + e.getTypeName() + ': ' + e.getMessage());
        }
    }

    @IsTest
    static void surfaceLineItemQueryError() {
        ReturnOrder returnOrder = [
            SELECT Id
            FROM ReturnOrder
            WHERE ReturnOrderType__c = 'Serialized'
            LIMIT 1
        ];
        if (returnOrder == null) {
            Assert.fail('DIAGNOSTIC_ERROR: No serialized ReturnOrder found in org.');
        }

        try {
            List<ReturnOrderLineItem> rows = [
                SELECT
                    Id,
                    ReturnOrderLineItemNumber,
                    Status__c,
                    AssetId,
                    Asset.Name,
                    Asset.SerialNumber,
                    Product2Id,
                    Product2.Name,
                    ProductLine__c,
                    QuantityReturned,
                    QuantityReceived,
                    HospitalReferencedTrayName__c,
                    ItemDescription__c,
                    Disinfected__c,
                    Model__c,
                    Department__c,
                    LineType__c,
                    ItemType__c,
                    SerialNubmer__c
                FROM ReturnOrderLineItem
                WHERE ReturnOrderId = :returnOrder.Id
                WITH USER_MODE
                ORDER BY ReturnOrderLineItemNumber ASC
            ];
            Assert.isTrue(rows.size() >= 0, 'Line item query completed.');
        } catch (Exception e) {
            Assert.fail('DIAGNOSTIC_ROLI_QUERY: ' + e.getTypeName() + ': ' + e.getMessage());
        }
    }

    @IsTest
    static void surfaceGetReceivingContextError() {
        ReturnOrder returnOrder = [
            SELECT Id
            FROM ReturnOrder
            WHERE ReturnOrderType__c = 'Serialized'
            LIMIT 1
        ];
        if (returnOrder == null) {
            Assert.fail('DIAGNOSTIC_ERROR: No serialized ReturnOrder found in org.');
        }

        try {
            ReturnOrderReceivingController.getReceivingContext(returnOrder.Id);
            Assert.fail('Expected getReceivingContext to throw.');
        } catch (Exception e) {
            Assert.fail('DIAGNOSTIC_CONTEXT: ' + e.getTypeName() + ': ' + e.getMessage());
        }
    }
}