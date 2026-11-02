/**
 * @description Test class for ReturnOrderLineItemsService.
 *              Covers create, update, delete, and retrieval operations
 *              across positive, negative, and empty-input scenarios.
 */
@IsTest
private class ReturnOrderLineItemsServiceTest {

    @TestSetup
    static void setupTestData() {
        // Build and persist a ReturnOrder, then line items under it
        adb_Account accountBuilder = new adb_Account();
        accountBuilder.persist();

        adb_Product2 productBuilder = new adb_Product2();
        productBuilder.persist();

        adb_ReturnOrder roBuilder = new adb_ReturnOrder().status('Draft');
        roBuilder.persist();

        // Set AccountId post-insert since ReturnOrder.AccountId is not required
        ReturnOrder ro = [SELECT Id FROM ReturnOrder WHERE Id = :roBuilder.id];
        ro.AccountId = accountBuilder.id;
        update ro;

        // ReturnOrderLineItem requires an item reference (Product2Id) to indicate what is being returned
        List<ReturnOrderLineItem> lineItemList = new List<ReturnOrderLineItem>();
        for (Integer i = 0; i < 5; i++) {
            ReturnOrderLineItem li = (ReturnOrderLineItem) new adb_ReturnOrderLineItem().quantityReturned(1).record;
            li.ReturnOrderId = roBuilder.id;
            li.Product2Id = productBuilder.id;
            lineItemList.add(li);
        }
        insert lineItemList;
    }

    // ── createReturnOrderLineItems ────────────────────────────────────────────

    @IsTest
    static void shouldCreateReturnOrderLineItems_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Id returnOrderId = [SELECT Id FROM ReturnOrder LIMIT 1].Id;
            Id productId = [SELECT Id FROM Product2 LIMIT 1].Id;
            List<ReturnOrderLineItem> lineItemList = new List<ReturnOrderLineItem>();
            for (Integer i = 0; i < 2; i++) {
                ReturnOrderLineItem li = (ReturnOrderLineItem) new adb_ReturnOrderLineItem().quantityReturned(1).record;
                li.ReturnOrderId = returnOrderId;
                li.Product2Id = productId;
                lineItemList.add(li);
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ReturnOrderLineItemsService.createReturnOrderLineItems(lineItemList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> insertedIds = new Map<Id, ReturnOrderLineItem>(lineItemList).keySet();
            List<ReturnOrderLineItem> insertedList = [SELECT Id FROM ReturnOrderLineItem WHERE Id IN :insertedIds];
            Assert.areEqual(2, insertedList.size(), 'createReturnOrderLineItems should insert all 2 records');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenCreateReturnOrderLineItemsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM ReturnOrderLineItem];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ReturnOrderLineItemsService.createReturnOrderLineItems(null);
            ReturnOrderLineItemsService.createReturnOrderLineItems(new List<ReturnOrderLineItem>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM ReturnOrderLineItem];
            Assert.areEqual(countBefore, countAfter, 'createReturnOrderLineItems with null should not insert any records');
        }
    }

    @IsTest
    static void shouldUpdateReturnOrderLineItems_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<ReturnOrderLineItem> lineItemList = [
                SELECT Id, Description
                FROM ReturnOrderLineItem
                LIMIT 2
            ];
            for (ReturnOrderLineItem lineItem : lineItemList) {
                lineItem.Description = 'Updated by service test';
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ReturnOrderLineItemsService.updateReturnOrderLineItems(lineItemList);
            ReturnOrderLineItemsService.updateReturnOrderLineItems(null);
            ReturnOrderLineItemsService.updateReturnOrderLineItems(new List<ReturnOrderLineItem>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> lineItemIds = new Map<Id, ReturnOrderLineItem>(lineItemList).keySet();
            List<ReturnOrderLineItem> updatedLineItems = [
                SELECT Id, Description
                FROM ReturnOrderLineItem
                WHERE Id IN :lineItemIds
            ];
            Assert.areEqual(2, updatedLineItems.size());
            for (ReturnOrderLineItem updatedLineItem : updatedLineItems) {
                Assert.areEqual('Updated by service test', updatedLineItem.Description);
            }
        }
    }

    @IsTest
    static void shouldDoNothing_WhenDeleteReturnOrderLineItemsCalledWithNullOrEmpty() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        Integer countBefore = [SELECT COUNT() FROM ReturnOrderLineItem];

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            ReturnOrderLineItemsService.deleteReturnOrderLineItems(null);
            ReturnOrderLineItemsService.deleteReturnOrderLineItems(new Set<Id>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(countBefore, [SELECT COUNT() FROM ReturnOrderLineItem]);
        }
    }

    // ── deleteReturnOrderLineItems ────────────────────────────────────────────

    @IsTest
    static void shouldDeleteReturnOrderLineItems_WhenValidIdsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> lineItemIdSet = new Map<Id, ReturnOrderLineItem>([SELECT Id FROM ReturnOrderLineItem LIMIT 3]).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ReturnOrderLineItemsService.deleteReturnOrderLineItems(lineItemIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer remainingCount = [SELECT COUNT() FROM ReturnOrderLineItem WHERE Id IN :lineItemIdSet];
            Assert.areEqual(0, remainingCount, 'deleteReturnOrderLineItems should delete all specified records');
        }
    }

    // ── getReturnOrderLineItemsById ───────────────────────────────────────────

    @IsTest
    static void shouldReturnReturnOrderLineItems_WhenGetByIdCalledWithValidIds() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> lineItemIdSet = new Map<Id, ReturnOrderLineItem>([SELECT Id FROM ReturnOrderLineItem]).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<ReturnOrderLineItem> resultList = ReturnOrderLineItemsService.getReturnOrderLineItemsById(lineItemIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(5, resultList.size(), 'getReturnOrderLineItemsById should return all 5 records');
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
            List<ReturnOrderLineItem> resultList = ReturnOrderLineItemsService.getReturnOrderLineItemsById(null);
            List<ReturnOrderLineItem> emptyResultList =
                ReturnOrderLineItemsService.getReturnOrderLineItemsById(new Set<Id>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getReturnOrderLineItemsById with null should return an empty list');
            Assert.isTrue(emptyResultList.isEmpty(), 'getReturnOrderLineItemsById with empty set should return an empty list');
        }
    }

    @IsTest
    static void shouldThrow_WhenCreateReturnOrderLineItemsFailsValidation() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        Boolean threw = false;

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            try {
                Test.startTest();
                ReturnOrderLineItemsService.createReturnOrderLineItems(
                    new List<ReturnOrderLineItem>{ new ReturnOrderLineItem() }
                );
                Test.stopTest();
            } catch (ReturnOrderLineItemsService.ReturnOrderLineItemsServiceException e) {
                threw = true;
            }

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(threw, 'Invalid create should throw service exception');
        }
    }

    @IsTest
    static void shouldThrow_WhenUpdateReturnOrderLineItemsWithUnknownId() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        Boolean threw = false;
        ReturnOrderLineItem disposable = [
            SELECT Id, Description
            FROM ReturnOrderLineItem
            LIMIT 1
        ];
        Id deletedId = disposable.Id;
        delete disposable;

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            try {
                Test.startTest();
                ReturnOrderLineItemsService.updateReturnOrderLineItems(
                    new List<ReturnOrderLineItem>{
                        new ReturnOrderLineItem(Id = deletedId, Description = 'Should fail')
                    }
                );
                Test.stopTest();
            } catch (ReturnOrderLineItemsService.ReturnOrderLineItemsServiceException e) {
                threw = true;
            }

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(threw, 'Update with deleted Id should throw service exception');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenDeleteReturnOrderLineItemsFindsNoRows() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        ReturnOrderLineItem disposable = [
            SELECT Id
            FROM ReturnOrderLineItem
            LIMIT 1
        ];
        Id deletedId = disposable.Id;
        delete disposable;
        Integer countBefore = [SELECT COUNT() FROM ReturnOrderLineItem];

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            ReturnOrderLineItemsService.deleteReturnOrderLineItems(new Set<Id>{ deletedId });
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(countBefore, [SELECT COUNT() FROM ReturnOrderLineItem]);
        }
    }

    @IsTest
    static void testGetInstrumentEvaluationLineItemsReturnsReturnOrderRows() {
        Id returnOrderId = [SELECT Id FROM ReturnOrder LIMIT 1].Id;

        Test.startTest();
        List<ReturnOrderLineItem> result =
            ReturnOrderLineItemsService.getInstrumentEvaluationLineItems(returnOrderId);
        List<ReturnOrderLineItem> emptyResult =
            ReturnOrderLineItemsService.getInstrumentEvaluationLineItems(null);
        Test.stopTest();

        Assert.areEqual(5, result.size(), 'All Return Order lines should be available');
        Assert.isNotNull(
            result[0].ReturnOrderLineItemNumber,
            'The assignment label should be queried'
        );
        Assert.isTrue(emptyResult.isEmpty(), 'Null Return Order should return no rows');
    }

    @IsTest
    static void testGetLinesForReceivingFinish_WhenIdsProvided_ReturnsRows() {
        /********************************************
         * SETUP
         ********************************************/
        List<ReturnOrderLineItem> setupLines = [
            SELECT Id
            FROM ReturnOrderLineItem
            LIMIT 2
        ];
        Assert.isTrue(setupLines.size() >= 2, 'Setup should provide line items');
        Set<Id> lineItemIds = new Map<Id, ReturnOrderLineItem>(setupLines).keySet();

        /********************************************
         * GIVEN / WHEN
         ********************************************/
        Test.startTest();
        List<ReturnOrderLineItem> results =
            ReturnOrderLineItemsService.getLinesForReceivingFinish(lineItemIds);
        List<ReturnOrderLineItem> nullResults =
            ReturnOrderLineItemsService.getLinesForReceivingFinish(null);
        List<ReturnOrderLineItem> emptyResults =
            ReturnOrderLineItemsService.getLinesForReceivingFinish(new Set<Id>());
        Test.stopTest();

        /********************************************
         * THEN
         ********************************************/
        Assert.areEqual(2, results.size(), 'Should return the requested receiving lines');
        Assert.isTrue(nullResults.isEmpty(), 'Null Ids should return no rows');
        Assert.isTrue(emptyResults.isEmpty(), 'Empty Ids should return no rows');
    }

    @IsTest
    static void testCountCreatedByReturnOrderId_WhenStatusesVary() {
        ReturnOrder returnOrder = [SELECT Id FROM ReturnOrder LIMIT 1];
        List<ReturnOrderLineItem> lines = [
            SELECT Id, Status__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrder.Id
            ORDER BY CreatedDate
        ];
        Assert.isTrue(lines.size() >= 2, 'Setup should provide multiple lines');
        for (ReturnOrderLineItem lineItem : lines) {
            lineItem.Status__c = 'Created';
        }
        lines[0].Status__c = 'Received';
        update lines;

        Test.startTest();
        Integer createdCount =
            ReturnOrderLineItemsService.countCreatedByReturnOrderId(returnOrder.Id);
        Integer nullCount = ReturnOrderLineItemsService.countCreatedByReturnOrderId(null);
        Integer selectorCount =
            ReturnOrderLineItemsSelector.countCreatedByReturnOrderId(returnOrder.Id);
        Test.stopTest();

        Assert.areEqual(lines.size() - 1, createdCount, 'Only Created lines should count');
        Assert.areEqual(0, nullCount, 'Null Return Order should return zero');
        Assert.areEqual(createdCount, selectorCount, 'Service should match selector count');
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static User buildTestUser() {
        adb_User builder = new adb_User();
        builder.persist();
        return (User) builder.record;
    }
}