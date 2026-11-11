/**
 * @description Tests for ReturnOrdersSelector companion class (coverage for CBMQA dry-run).
 */
@IsTest
private class ReturnOrdersSelectorTest {
    @TestSetup
    static void setupData() {
        /********************************************
         * SETUP
         ********************************************/
        adb_Account accountBuilder = new adb_Account();
        accountBuilder.persist();

        adb_Product2 productBuilder = new adb_Product2();
        productBuilder.persist();

        adb_ReturnOrder roBuilder = new adb_ReturnOrder().status('Draft');
        roBuilder.persist();

        ReturnOrder returnOrder = [SELECT Id FROM ReturnOrder WHERE Id = :roBuilder.id];
        returnOrder.AccountId = accountBuilder.id;
        update returnOrder;

        // Outbound RT matches ReturnOrderLineItemsSelectorTest; avoids inaccessible defaults on insert.
        Id outboundRtId = Schema.SObjectType.ReturnOrderLineItem.getRecordTypeInfosByDeveloperName()
            .get('Outbound')
            .getRecordTypeId();

        ReturnOrderLineItem lineItem = (ReturnOrderLineItem) new adb_ReturnOrderLineItem()
            .quantityReturned(1)
            .record;
        lineItem.ReturnOrderId = returnOrder.Id;
        lineItem.Product2Id = productBuilder.id;
        lineItem.RecordTypeId = outboundRtId;
        insert lineItem;
    }

    @IsTest
    static void testSelectByIdVariants_WhenGuardsOrMatch_ReturnsExpected() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        ReturnOrder returnOrder = [SELECT Id FROM ReturnOrder LIMIT 1];

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            List<ReturnOrder> nullById = ReturnOrdersSelector.selectById(null);
            List<ReturnOrder> emptyById = ReturnOrdersSelector.selectById(new Set<Id>());
            List<ReturnOrder> byId = ReturnOrdersSelector.selectById(new Set<Id>{ returnOrder.Id });
            List<ReturnOrder> nullWithLines = ReturnOrdersSelector.selectByIdWithLineItems(null);
            List<ReturnOrder> emptyWithLines = ReturnOrdersSelector.selectByIdWithLineItems(
                new Set<Id>()
            );
            List<ReturnOrder> withLines = ReturnOrdersSelector.selectByIdWithLineItems(
                new Set<Id>{ returnOrder.Id }
            );
            List<ReturnOrder> nullInbound = ReturnOrdersSelector.selectForInboundShippingLabel(null);
            List<ReturnOrder> inbound = ReturnOrdersSelector.selectForInboundShippingLabel(
                returnOrder.Id
            );
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(0, nullById.size());
            Assert.areEqual(0, emptyById.size());
            Assert.areEqual(1, byId.size());
            Assert.areEqual(0, nullWithLines.size());
            Assert.areEqual(0, emptyWithLines.size());
            Assert.areEqual(1, withLines.size());
            Assert.areEqual(0, nullInbound.size());
            Assert.areEqual(1, inbound.size());
        }
    }

    @IsTest
    static void testSelectByAccountAndVendorHelpers_WhenGuardsOrMatch_ReturnsExpected() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        ReturnOrder returnOrder = [SELECT Id, AccountId FROM ReturnOrder LIMIT 1];

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            List<ReturnOrder> nullByAccount = ReturnOrdersSelector.selectByAccountId(null);
            List<ReturnOrder> emptyByAccount = ReturnOrdersSelector.selectByAccountId(new Set<Id>());
            List<ReturnOrder> byAccount = ReturnOrdersSelector.selectByAccountId(
                new Set<Id>{ returnOrder.AccountId }
            );
            List<ReturnOrder> nullParent =
                ReturnOrdersSelector.selectParentReturnOrdersForVendorConsolidation(null, null);
            List<ReturnOrder> emptyParent =
                ReturnOrdersSelector.selectParentReturnOrdersForVendorConsolidation(
                    new Set<Id>(),
                    new List<String>{ 'Description' }
                );
            List<ReturnOrder> parentRows =
                ReturnOrdersSelector.selectParentReturnOrdersForVendorConsolidation(
                    new Set<Id>{ returnOrder.Id },
                    new List<String>{ 'Description' }
                );
            List<ReturnOrder> nullFedEx = ReturnOrdersSelector.selectForVendorFedExShipment(null);
            List<ReturnOrder> emptyFedEx = ReturnOrdersSelector.selectForVendorFedExShipment(
                new Set<Id>()
            );
            List<ReturnOrder> fedExRows = ReturnOrdersSelector.selectForVendorFedExShipment(
                new Set<Id>{ returnOrder.Id }
            );
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(0, nullByAccount.size());
            Assert.areEqual(0, emptyByAccount.size());
            Assert.isTrue(byAccount.size() >= 1);
            Assert.areEqual(0, nullParent.size());
            Assert.areEqual(0, emptyParent.size());
            Assert.areEqual(1, parentRows.size());
            Assert.areEqual(0, nullFedEx.size());
            Assert.areEqual(0, emptyFedEx.size());
            Assert.areEqual(1, fedExRows.size());
        }
    }

    @IsTest
    static void testSelectByIdNullOrEmptyReturnsEmpty_sprint93Coverage() {
        Assert.areEqual(0, ReturnOrdersSelector.selectById(null).size());
        Assert.areEqual(0, ReturnOrdersSelector.selectById(new Set<Id>()).size());
    }

}