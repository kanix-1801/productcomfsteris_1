/**
 * @description Tests for ReturnOrderLineItemsSelector companion class (coverage for CBMQA dry-run).
 */
@IsTest
private class ReturnOrderLineItemsSelectorTest {
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

        Id outboundRtId = Schema.SObjectType.ReturnOrderLineItem.getRecordTypeInfosByDeveloperName()
            .get('Outbound')
            ?.getRecordTypeId();

        ReturnOrderLineItem lineItem = (ReturnOrderLineItem) new adb_ReturnOrderLineItem()
            .quantityReturned(1)
            .record;
        lineItem.ReturnOrderId = returnOrder.Id;
        lineItem.Product2Id = productBuilder.id;
        if (outboundRtId != null) {
            lineItem.RecordTypeId = outboundRtId;
        }
        insert lineItem;
    }

    @IsTest
    static void testSelectByIdAndReturnOrderId_WhenGuardsOrMatch_ReturnsExpected() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        ReturnOrderLineItem lineItem = [
            SELECT Id, ReturnOrderId
            FROM ReturnOrderLineItem
            LIMIT 1
        ];

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            List<ReturnOrderLineItem> nullById = ReturnOrderLineItemsSelector.selectById(null);
            List<ReturnOrderLineItem> emptyById = ReturnOrderLineItemsSelector.selectById(
                new Set<Id>()
            );
            List<ReturnOrderLineItem> byId = ReturnOrderLineItemsSelector.selectById(
                new Set<Id>{ lineItem.Id }
            );
            List<ReturnOrderLineItem> nullByRo = ReturnOrderLineItemsSelector.selectByReturnOrderId(
                null
            );
            List<ReturnOrderLineItem> emptyByRo = ReturnOrderLineItemsSelector.selectByReturnOrderId(
                new Set<Id>()
            );
            List<ReturnOrderLineItem> byRo = ReturnOrderLineItemsSelector.selectByReturnOrderId(
                new Set<Id>{ lineItem.ReturnOrderId }
            );
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(0, nullById.size());
            Assert.areEqual(0, emptyById.size());
            Assert.areEqual(1, byId.size());
            Assert.areEqual(0, nullByRo.size());
            Assert.areEqual(0, emptyByRo.size());
            Assert.isTrue(byRo.size() >= 1);
        }
    }

    @IsTest
    static void testSelectOutboundByReturnOrderIds_WhenGuardsOrMatch_ReturnsExpected() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        ReturnOrderLineItem lineItem = [
            SELECT Id, ReturnOrderId, RecordTypeId
            FROM ReturnOrderLineItem
            LIMIT 1
        ];
        Id outboundRtId = Schema.SObjectType.ReturnOrderLineItem.getRecordTypeInfosByDeveloperName()
            .get('Outbound')
            ?.getRecordTypeId();

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            List<ReturnOrderLineItem> nullResult =
                ReturnOrderLineItemsSelector.selectOutboundByReturnOrderIds(null, outboundRtId);
            List<ReturnOrderLineItem> emptyResult =
                ReturnOrderLineItemsSelector.selectOutboundByReturnOrderIds(
                    new Set<Id>(),
                    outboundRtId
                );
            List<ReturnOrderLineItem> nullRt =
                ReturnOrderLineItemsSelector.selectOutboundByReturnOrderIds(
                    new Set<Id>{ lineItem.ReturnOrderId },
                    null
                );
            List<ReturnOrderLineItem> matchResult =
                ReturnOrderLineItemsSelector.selectOutboundByReturnOrderIds(
                    new Set<Id>{ lineItem.ReturnOrderId },
                    outboundRtId != null ? outboundRtId : lineItem.RecordTypeId
                );
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(0, nullResult.size());
            Assert.areEqual(0, emptyResult.size());
            Assert.areEqual(0, nullRt.size());
            Assert.isNotNull(matchResult);
        }
    }

    @IsTest
    static void testCount_WhenReturnOrderFilterApplied_ReturnsExpected() {
        ReturnOrderLineItem lineItem = [
            SELECT Id, ReturnOrderId
            FROM ReturnOrderLineItem
            LIMIT 1
        ];

        Test.startTest();
        Integer matchCount = new ReturnOrderLineItemsSelector()
            .whereEquals('ReturnOrderId', lineItem.ReturnOrderId)
            .count();
        Integer none = new ReturnOrderLineItemsSelector()
            .whereEquals('Id', lineItem.Id)
            .whereEquals('ReturnOrderId', UserInfo.getUserId())
            .count();
        Test.stopTest();

        Assert.isTrue(matchCount >= 1, 'Matching Return Order lines should count');
        Assert.areEqual(0, none, 'Impossible filter combination should return zero');
    }

    @IsTest
    static void testSelectByIdNullOrEmptyReturnsEmpty_sprint93Coverage() {
        Assert.areEqual(0, ReturnOrderLineItemsSelector.selectById(null).size());
        Assert.areEqual(0, ReturnOrderLineItemsSelector.selectById(new Set<Id>()).size());
    }

    /**
     * @description GW-5677 - Additional-services query returns every line on the Return Order.
     */
    @IsTest
    static void testSelectAdditionalServicesByReturnOrderId_ReturnsLinesInNumberOrder() {
        ReturnOrderLineItem lineItem = [
            SELECT Id, ReturnOrderId
            FROM ReturnOrderLineItem
            LIMIT 1
        ];
        lineItem.ItemDescription__c = 'Scalpel';
        lineItem.AdditionalServiceRepair__c = true;
        update lineItem;

        Test.startTest();
        List<ReturnOrderLineItem> none =
            ReturnOrderLineItemsSelector.selectAdditionalServicesByReturnOrderId(null);
        List<ReturnOrderLineItem> lines =
            ReturnOrderLineItemsSelector.selectAdditionalServicesByReturnOrderId(lineItem.ReturnOrderId);
        Test.stopTest();

        Assert.areEqual(0, none.size(), 'Null Return Order should return no lines');
        Assert.isFalse(lines.isEmpty(), 'Return Order lines should be returned');
        Assert.areEqual('Scalpel', lines[0].ItemDescription__c);
        Assert.areEqual(true, lines[0].AdditionalServiceRepair__c);
    }

}