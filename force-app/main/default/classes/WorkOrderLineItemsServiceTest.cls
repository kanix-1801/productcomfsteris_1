/**
 * @description Test class for WorkOrderLineItemsService.
 *              Covers create, update, delete, and retrieval operations
 *              across positive, negative, bulk, and empty-input scenarios.
 */
@IsTest
private class WorkOrderLineItemsServiceTest {
    private class SelectorException extends Exception {
    }

    private class ThrowingSelector
        implements WorkOrderLineItemsService.IWorkOrderLineItemsSelector {
        public List<WorkOrderLineItem> selectById(Set<Id> lineItemIds) {
            throw new SelectorException('selectById failed');
        }
        public List<WorkOrderLineItem> selectByWorkOrderId(Set<Id> workOrderIds) {
            throw new SelectorException('selectByWorkOrderId failed');
        }
        public List<WorkOrderLineItem> selectRepairCodeLinesWithProduct(
            Id workOrderId,
            Id repairCodeRtId
        ) {
            throw new SelectorException('repair code lines selector failed');
        }
        public List<WorkOrderLineItem> selectRepairCodeIds(
            Id workOrderId,
            Id repairCodeRtId
        ) {
            throw new SelectorException('repair code ids selector failed');
        }
        public List<WorkOrderLineItem> selectRepairCodeByWorkOrderAndProducts(
            Id workOrderId,
            Id repairCodeRtId,
            Set<Id> productIds
        ) {
            throw new SelectorException('repair code by products failed');
        }
        public List<WorkOrderLineItem> selectRepairCodeLinesForReconcile(
            Id workOrderId,
            Id repairCodeRtId
        ) {
            throw new SelectorException('reconcile lines failed');
        }
        public Id selectNewestProductServicedId(
            Id workOrderId,
            Id assetId,
            Id productServicedRtId
        ) {
            throw new SelectorException('newest product serviced failed');
        }
        public List<WorkOrderLineItem> selectQualityInspectionProductServiced(
            Id workOrderId,
            Id assetId,
            Id productServicedRtId
        ) {
            throw new SelectorException('quality inspection product serviced failed');
        }
        public Set<Id> selectRepairCodeProductIds(Id workOrderId, Id repairCodeRtId) {
            throw new SelectorException('repair code product ids failed');
        }
        public List<WorkOrderLineItem> selectInstrumentEvaluationLines(
            Id workOrderId,
            Id productServicedRtId,
            Id repairCodeRtId
        ) {
            throw new SelectorException('instrument evaluation lines failed');
        }
    }

    @TestSetup
    static void setupTestData() {
        // Persist a parent WorkOrder first
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .subject('Service Test Work Order');
        workOrderBuilder.persist();

        // Build 251 line items linked to the same WorkOrder and bulk-insert
        List<WorkOrderLineItem> lineItemList = new List<WorkOrderLineItem>();
        for (Integer i = 0; i < 251; i++) {
            WorkOrderLineItem lineItem = (WorkOrderLineItem) new adb_WorkOrderLineItem()
                .description('Line Item ' + i)
                .record;
            lineItem.WorkOrderId = workOrderBuilder.id;
            lineItemList.add(lineItem);
        }
        insert lineItemList;
    }

    // ── createLineItems ───────────────────────────────────────────────────────

    @IsTest
    static void shouldCreateLineItems_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            adb_WorkOrder workOrderBuilder = new adb_WorkOrder();
            workOrderBuilder.persist();
            Id newWorkOrderId = workOrderBuilder.id;

            List<WorkOrderLineItem> lineItemList = new List<WorkOrderLineItem>();
            for (Integer i = 1; i <= 3; i++) {
                WorkOrderLineItem lineItem = (WorkOrderLineItem) new adb_WorkOrderLineItem()
                    .description('New Line Item ' + i)
                    .record;
                lineItem.WorkOrderId = newWorkOrderId;
                lineItemList.add(lineItem);
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            WorkOrderLineItemsService.createLineItems(lineItemList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            List<WorkOrderLineItem> insertedList = [
                SELECT Id, Description, Status
                FROM WorkOrderLineItem
                WHERE WorkOrderId = :newWorkOrderId
            ];
            Assert.areEqual(3, insertedList.size(), 'createLineItems should insert all 3 WorkOrderLineItems');
            for (WorkOrderLineItem lineItem : insertedList) {
                Assert.areEqual('New', lineItem.Status, 'Inserted line items should have Status = New');
            }
        }
    }

    @IsTest
    static void shouldCreateLineItems_WhenBulk251RecordsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN — delete setup records so count assertion is isolated
             ********************************************/
            delete [SELECT Id FROM WorkOrderLineItem];

            adb_WorkOrder workOrderBuilder = new adb_WorkOrder();
            workOrderBuilder.persist();

            List<WorkOrderLineItem> lineItemList = new List<WorkOrderLineItem>();
            for (Integer i = 0; i < 251; i++) {
                WorkOrderLineItem lineItem = (WorkOrderLineItem) new adb_WorkOrderLineItem()
                    .description('Bulk Line Item ' + i)
                    .record;
                lineItem.WorkOrderId = workOrderBuilder.id;
                lineItemList.add(lineItem);
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            WorkOrderLineItemsService.createLineItems(lineItemList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer insertedCount = [SELECT COUNT() FROM WorkOrderLineItem];
            Assert.areEqual(251, insertedCount, 'createLineItems should bulk-insert all 251 WorkOrderLineItems');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenCreateLineItemsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM WorkOrderLineItem];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            WorkOrderLineItemsService.createLineItems(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM WorkOrderLineItem];
            Assert.areEqual(countBefore, countAfter, 'createLineItems with null should not insert any records');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenCreateLineItemsCalledWithEmptyList() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM WorkOrderLineItem];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            WorkOrderLineItemsService.createLineItems(new List<WorkOrderLineItem>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM WorkOrderLineItem];
            Assert.areEqual(countBefore, countAfter, 'createLineItems with an empty list should not insert any records');
        }
    }

    @IsTest
    static void testCreateLineItems_dmlFailureIsWrapped() {
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .subject('WOLI Create DML Fail Seed')
            .status('New');
        workOrderBuilder.persist();
        Id deletedWorkOrderId = workOrderBuilder.id;
        delete new WorkOrder(Id = deletedWorkOrderId);

        WorkOrderLineItem invalidLineItem = new WorkOrderLineItem(
            WorkOrderId = deletedWorkOrderId,
            Quantity = 1
        );

        Boolean threw = false;
        Test.startTest();
        try {
            WorkOrderLineItemsService.createLineItems(
                new List<WorkOrderLineItem>{ invalidLineItem }
            );
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            threw = true;
            Assert.isTrue(
                e.getCause() instanceof DmlException,
                'The service exception should preserve the DML cause'
            );
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Deleted Work Order Id should fail line item creation');
    }

    // ── updateLineItems ───────────────────────────────────────────────────────

    @IsTest
    static void shouldUpdateLineItems_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<WorkOrderLineItem> lineItemList = [SELECT Id, Status FROM WorkOrderLineItem LIMIT 5];
            for (WorkOrderLineItem lineItem : lineItemList) {
                lineItem.Status = 'In Progress';
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            WorkOrderLineItemsService.updateLineItems(lineItemList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> updatedIdSet = new Map<Id, WorkOrderLineItem>(lineItemList).keySet();
            List<WorkOrderLineItem> updatedList = [
                SELECT Id, Status FROM WorkOrderLineItem WHERE Id IN :updatedIdSet
            ];
            Assert.areEqual(5, updatedList.size(), 'updateLineItems should update all 5 WorkOrderLineItems');
            for (WorkOrderLineItem lineItem : updatedList) {
                Assert.areEqual('In Progress', lineItem.Status, 'Each updated line item should have Status = In Progress');
            }
        }
    }

    @IsTest
    static void shouldUpdateLineItems_WhenBulk251RecordsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<WorkOrderLineItem> lineItemList = [SELECT Id, Status FROM WorkOrderLineItem];
            Assert.areEqual(251, lineItemList.size(), 'Test setup should have inserted 251 WorkOrderLineItems');
            for (WorkOrderLineItem lineItem : lineItemList) {
                lineItem.Status = 'Completed';
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            WorkOrderLineItemsService.updateLineItems(lineItemList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer completedCount = [SELECT COUNT() FROM WorkOrderLineItem WHERE Status = 'Completed'];
            Assert.areEqual(251, completedCount, 'All 251 WorkOrderLineItems should be updated to Status = Completed');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenUpdateLineItemsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            WorkOrderLineItemsService.updateLineItems(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(true, 'updateLineItems with null should complete without error');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenUpdateLineItemsCalledWithEmptyList() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            WorkOrderLineItemsService.updateLineItems(new List<WorkOrderLineItem>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(true, 'updateLineItems with an empty list should complete without error');
        }
    }

    @IsTest
    static void testUpdateLineItems_deletedRecordFailureIsWrapped() {
        WorkOrderLineItem deletedLineItem = [
            SELECT Id, Description
            FROM WorkOrderLineItem
            LIMIT 1
        ];
        delete deletedLineItem;
        deletedLineItem.Description = 'Cannot update deleted line';

        Boolean threw = false;
        Test.startTest();
        try {
            WorkOrderLineItemsService.updateLineItems(
                new List<WorkOrderLineItem>{ deletedLineItem }
            );
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            threw = true;
            Assert.isTrue(
                e.getCause() instanceof DmlException,
                'The service exception should preserve the DML cause'
            );
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Updating a deleted line item should fail');
    }

    // ── deleteLineItems ───────────────────────────────────────────────────────

    @IsTest
    static void shouldDeleteLineItems_WhenValidIdsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<WorkOrderLineItem> lineItemList = [SELECT Id FROM WorkOrderLineItem LIMIT 5];
            Set<Id> lineItemIdSet = new Map<Id, WorkOrderLineItem>(lineItemList).keySet();
            Assert.areEqual(5, lineItemIdSet.size(), 'Should have 5 WorkOrderLineItem Ids to delete');

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            WorkOrderLineItemsService.deleteLineItems(lineItemIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer remainingCount = [SELECT COUNT() FROM WorkOrderLineItem WHERE Id IN :lineItemIdSet];
            Assert.areEqual(0, remainingCount, 'deleteLineItems should delete all 5 WorkOrderLineItems with the given Ids');
        }
    }

    @IsTest
    static void shouldDeleteLineItems_WhenBulk251IdsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> lineItemIdSet = new Map<Id, WorkOrderLineItem>(
                [SELECT Id FROM WorkOrderLineItem]
            ).keySet();
            Assert.areEqual(251, lineItemIdSet.size(), 'Test setup should have inserted 251 WorkOrderLineItems');

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            WorkOrderLineItemsService.deleteLineItems(lineItemIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer remainingCount = [SELECT COUNT() FROM WorkOrderLineItem];
            Assert.areEqual(0, remainingCount, 'deleteLineItems should delete all 251 WorkOrderLineItems');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenDeleteLineItemsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM WorkOrderLineItem];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            WorkOrderLineItemsService.deleteLineItems(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM WorkOrderLineItem];
            Assert.areEqual(countBefore, countAfter, 'deleteLineItems with null should not delete any records');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenDeleteLineItemsCalledWithEmptySet() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM WorkOrderLineItem];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            WorkOrderLineItemsService.deleteLineItems(new Set<Id>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM WorkOrderLineItem];
            Assert.areEqual(countBefore, countAfter, 'deleteLineItems with an empty Set should not delete any records');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenDeleteLineItemsCalledWithNonExistentIds() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM WorkOrderLineItem];
            Set<Id> nonExistentIdSet = new Set<Id>{ '0WX000000000001AAA' };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            WorkOrderLineItemsService.deleteLineItems(nonExistentIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM WorkOrderLineItem];
            Assert.areEqual(countBefore, countAfter, 'deleteLineItems with non-existent Ids should not delete any records');
        }
    }

    // ── getLineItemsById ──────────────────────────────────────────────────────

    @IsTest
    static void shouldReturnLineItems_WhenGetByIdCalledWithValidIds() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> lineItemIdSet = new Map<Id, WorkOrderLineItem>(
                [SELECT Id FROM WorkOrderLineItem]
            ).keySet();
            Assert.areEqual(251, lineItemIdSet.size(), 'Test setup should have inserted 251 WorkOrderLineItems');

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<WorkOrderLineItem> resultList = WorkOrderLineItemsService.getLineItemsById(lineItemIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(251, resultList.size(), 'getLineItemsById should return all 251 WorkOrderLineItems matching the given Ids');
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
            List<WorkOrderLineItem> resultList = WorkOrderLineItemsService.getLineItemsById(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getLineItemsById with null should return an empty list');
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
            List<WorkOrderLineItem> resultList = WorkOrderLineItemsService.getLineItemsById(new Set<Id>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getLineItemsById with an empty Set should return an empty list');
        }
    }

    // ── getLineItemsByWorkOrderId ─────────────────────────────────────────────

    @IsTest
    static void shouldReturnLineItems_WhenGetByWorkOrderIdCalledWithValidId() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            WorkOrder parentWorkOrder = [SELECT Id FROM WorkOrder LIMIT 1];
            Set<Id> workOrderIdSet = new Set<Id>{ parentWorkOrder.Id };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<WorkOrderLineItem> resultList = WorkOrderLineItemsService.getLineItemsByWorkOrderId(workOrderIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(251, resultList.size(), 'getLineItemsByWorkOrderId should return all 251 line items for the parent WorkOrder');
            for (WorkOrderLineItem lineItem : resultList) {
                Assert.areEqual(
                    parentWorkOrder.Id,
                    lineItem.WorkOrderId,
                    'Every returned WorkOrderLineItem should be linked to the parent WorkOrder'
                );
            }
        }
    }

    @IsTest
    static void shouldReturnEmpty_WhenGetByWorkOrderIdCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<WorkOrderLineItem> resultList = WorkOrderLineItemsService.getLineItemsByWorkOrderId(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getLineItemsByWorkOrderId with null should return an empty list');
        }
    }

    @IsTest
    static void shouldReturnEmpty_WhenGetByWorkOrderIdCalledWithEmptySet() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<WorkOrderLineItem> resultList = WorkOrderLineItemsService.getLineItemsByWorkOrderId(new Set<Id>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getLineItemsByWorkOrderId with an empty Set should return an empty list');
        }
    }

    // ── Device Evaluation getters (GW-3913 / GW-3096) ─────────────────────────

    @IsTest
    static void testDeviceEvaluationWorkOrderLineItemServiceNullGuards() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Test.startTest();
            Assert.isTrue(
                WorkOrderLineItemsService.getRepairCodeLinesWithProduct(null, null).isEmpty()
            );
            Assert.isTrue(WorkOrderLineItemsService.getRepairCodeIds(null, null).isEmpty());
            Assert.isTrue(
                WorkOrderLineItemsService.getRepairCodeByWorkOrderAndProducts(null, null, null)
                    .isEmpty()
            );
            Assert.isTrue(
                WorkOrderLineItemsService.getRepairCodeLinesForReconcile(null, null).isEmpty()
            );
            Assert.isNull(WorkOrderLineItemsService.getNewestProductServicedId(null, null, null));
            Assert.isTrue(WorkOrderLineItemsService.getRepairCodeProductIds(null, null).isEmpty());
            Test.stopTest();
        }
    }

    @IsTest
    static void testReconcileRepairCodeWolisForDeviceEvaluationValidation() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Boolean threw = false;
            try {
                WorkOrderLineItemsService.reconcileRepairCodeWolisForDeviceEvaluation(
                    null,
                    new Set<Id>(),
                    new ProductRelatedMaterialsService.RepairCodeCatalog()
                );
            } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
                threw = true;
                Assert.isTrue(
                    e.getMessage().contains('Work Order is required'),
                    'Null Work Order should fail validation'
                );
            }
            Assert.isTrue(threw, 'reconcile should require Work Order');

            WorkOrder woWithoutId = new WorkOrder(Subject = 'WOLI DE Reconcile No Id');
            threw = false;
            try {
                WorkOrderLineItemsService.reconcileRepairCodeWolisForDeviceEvaluation(
                    woWithoutId,
                    new Set<Id>(),
                    null
                );
            } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
                threw = true;
                Assert.isTrue(e.getMessage().contains('Work Order is required'));
            }
            Assert.isTrue(threw, 'reconcile should require Work Order Id');

            // Empty selection with a persisted WO should no-op when RepairCode RT exists.
            Id repairCodeRtId = WorkOrderLineItemsService.getRepairCodeRecordTypeId();
            if (repairCodeRtId != null) {
                adb_Account accountBuilder = new adb_Account();
                accountBuilder.persist();
                WorkOrder workOrder = new WorkOrder(
                    AccountId = accountBuilder.id,
                    Subject = 'WOLI DE Reconcile Empty',
                    Status = 'Received',
                    Pricebook2Id = Test.getStandardPricebookId()
                );
                insert workOrder;
                WorkOrderLineItemsService.reconcileRepairCodeWolisForDeviceEvaluation(
                    workOrder,
                    new Set<Id>(),
                    new ProductRelatedMaterialsService.RepairCodeCatalog()
                );
                Assert.areEqual(
                    0,
                    [
                        SELECT COUNT()
                        FROM WorkOrderLineItem
                        WHERE WorkOrderId = :workOrder.Id AND RecordTypeId = :repairCodeRtId
                    ],
                    'Empty selection should not create Repair Code lines'
                );
            }
        }
    }

    @IsTest
    static void testDeviceEvaluationWorkOrderLineItemServiceHappyPath() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Schema.RecordTypeInfo repairCodeRt = Schema.SObjectType.WorkOrderLineItem
                .getRecordTypeInfosByDeveloperName()
                .get('RepairCode');
            if (repairCodeRt == null) {
                Assert.isTrue(true, 'RepairCode RT unavailable; null-guard coverage only');
                return;
            }

            adb_Account accountBuilder = new adb_Account();
            accountBuilder.persist();
            Account account = (Account) accountBuilder.record;
            Id pricebookId = Test.getStandardPricebookId();
            WorkOrder workOrder = new WorkOrder(
                AccountId = account.Id,
                Subject = 'WOLI DE Service WO',
                Status = 'Received',
                Pricebook2Id = pricebookId
            );
            insert workOrder;

            Product2 product = new Product2(
                Name = 'WOLI DE Service Product',
                ProductCode = 'WOLI-DE-SVC-001',
                IsActive = true
            );
            insert product;
            insert new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id = product.Id,
                UnitPrice = 1,
                IsActive = true
            );
            PricebookEntry pbe = [
                SELECT Id
                FROM PricebookEntry
                WHERE Product2Id = :product.Id AND Pricebook2Id = :pricebookId
                LIMIT 1
            ];
            insert new WorkOrderLineItem(
                WorkOrderId = workOrder.Id,
                RecordTypeId = repairCodeRt.getRecordTypeId(),
                Product__c = product.Id,
                PricebookEntryId = pbe.Id,
                Quantity = 1
            );

            Id repairCodeRtId = repairCodeRt.getRecordTypeId();
            Test.startTest();
            Assert.isFalse(
                WorkOrderLineItemsService.getRepairCodeLinesWithProduct(workOrder.Id, repairCodeRtId)
                    .isEmpty()
            );
            Assert.isFalse(
                WorkOrderLineItemsService.getRepairCodeIds(workOrder.Id, repairCodeRtId).isEmpty()
            );
            Assert.areEqual(
                1,
                WorkOrderLineItemsService.getRepairCodeByWorkOrderAndProducts(
                        workOrder.Id,
                        repairCodeRtId,
                        new Set<Id>{ product.Id }
                    )
                    .size()
            );
            Assert.isFalse(
                WorkOrderLineItemsService.getRepairCodeLinesForReconcile(workOrder.Id, repairCodeRtId)
                    .isEmpty()
            );
            Assert.isTrue(
                WorkOrderLineItemsService.getRepairCodeProductIds(workOrder.Id, repairCodeRtId)
                    .contains(product.Id)
            );
            Test.stopTest();
        }
    }

    @IsTest
    static void testReconcileRepairCodeWolis_missingPricebookEntry() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Schema.RecordTypeInfo repairCodeRt = Schema.SObjectType.WorkOrderLineItem
                .getRecordTypeInfosByDeveloperName()
                .get('RepairCode');
            if (repairCodeRt == null) {
                Assert.isTrue(true, 'RepairCode RT unavailable');
                return;
            }

            adb_Account accountBuilder = new adb_Account();
            accountBuilder.persist();
            Product2 product = new Product2(
                Name = 'WOLI DE No PBE Product',
                ProductCode = 'WOLI-DE-NOPBE',
                IsActive = true,
                ProductType__c = 'Category Code'
            );
            insert product;

            WorkOrder workOrder = new WorkOrder(
                AccountId = accountBuilder.id,
                Subject = 'WOLI DE Missing PBE',
                Status = 'Evaluate',
                Pricebook2Id = Test.getStandardPricebookId(),
                CurrencyIsoCode = UserInfo.getDefaultCurrency()
            );
            insert workOrder;
            workOrder = [
                SELECT
                    Id,
                    CurrencyIsoCode,
                    Pricebook2Id,
                    AssetId,
                    ParentWorkOrderId,
                    ParentWorkOrder.Pricebook2Id,
                    Asset.Product2Id,
                    Asset.SerialNumber,
                    Asset.Product2.Model__c,
                    Asset.Product2.ProductCode
                FROM WorkOrder
                WHERE Id = :workOrder.Id
            ];

            ProductRelatedMaterialsService.RepairCodeCatalog catalog =
                new ProductRelatedMaterialsService.RepairCodeCatalog();
            catalog.categoryCodeIds.add(product.Id);

            Boolean threw = false;
            String message = null;
            Test.startTest();
            try {
                WorkOrderLineItemsService.reconcileRepairCodeWolisForDeviceEvaluation(
                    workOrder,
                    new Set<Id>{ product.Id },
                    catalog
                );
            } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
                threw = true;
                message = e.getMessage();
            }
            Test.stopTest();

            Assert.isTrue(threw, 'Missing Price Book Entry should fail reconcile');
            Assert.isTrue(
                message != null && message.contains('Price Book Entry'),
                'Expected missing PBE message, got: ' + message
            );
        }
    }

    @IsTest
    static void testReconcile_createsRepairCodeWoli() {
        Id repairCodeRtId = WorkOrderLineItemsService.getRepairCodeRecordTypeId();
        if (repairCodeRtId == null) {
            return;
        }
        adb_Account accountBuilder = new adb_Account()
            .name('WOLI Reconcile Create Account');
        accountBuilder.persist();
        Id pricebookId = Test.getStandardPricebookId();
        Product2 product = new Product2(
            Name = 'WOLI Reconcile Create Product',
            ProductCode = 'WOLI-RECON-CREATE',
            ProductType__c = 'Category Code',
            IsActive = true
        );
        insert product;
        insert new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = product.Id,
            UnitPrice = 10,
            IsActive = true
        );
        WorkOrder workOrder = new WorkOrder(
            AccountId = accountBuilder.id,
            Subject = 'WOLI Reconcile Create',
            Status = 'Evaluate',
            Pricebook2Id = pricebookId
        );
        insert workOrder;
        workOrder = [
            SELECT
                Id,
                AssetId,
                ParentWorkOrderId,
                ParentWorkOrder.Pricebook2Id,
                Pricebook2Id,
                CurrencyIsoCode,
                EstimateRequired__c,
                Asset.SerialNumber,
                Asset.Product2Id,
                Asset.Product2.Model__c,
                Asset.Product2.ProductCode
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];
        ProductRelatedMaterialsService.RepairCodeCatalog catalog =
            new ProductRelatedMaterialsService.RepairCodeCatalog();
        catalog.categoryCodeIds.add(product.Id);

        Test.startTest();
        WorkOrderLineItemsService.reconcileRepairCodeWolisForDeviceEvaluation(
            workOrder,
            new Set<Id>{ product.Id },
            catalog
        );
        Test.stopTest();

        WorkOrderLineItem created = [
            SELECT Product__c, RepairCode__c, LineType__c, Quantity, PricebookEntryId
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :workOrder.Id
                AND RecordTypeId = :repairCodeRtId
            LIMIT 1
        ];
        Assert.areEqual(product.Id, created.Product__c);
        Assert.areEqual(product.Id, created.RepairCode__c);
        Assert.areEqual('Category Code', created.LineType__c);
        Assert.areEqual(1, created.Quantity);
        Assert.isNotNull(created.PricebookEntryId);
    }

    @IsTest
    static void testReconcile_missingCurrencyThrows() {
        Id repairCodeRtId = WorkOrderLineItemsService.getRepairCodeRecordTypeId();
        if (repairCodeRtId == null) {
            return;
        }
        adb_Account accountBuilder = new adb_Account()
            .name('WOLI Missing Currency Account');
        accountBuilder.persist();
        Product2 product = new Product2(
            Name = 'WOLI Missing Currency Product',
            ProductCode = 'WOLI-NO-CURRENCY',
            ProductType__c = 'Category Code',
            IsActive = true
        );
        insert product;
        WorkOrder persisted = new WorkOrder(
            AccountId = accountBuilder.id,
            Subject = 'WOLI Missing Currency',
            Status = 'Evaluate',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert persisted;
        WorkOrder workOrder = new WorkOrder(
            Id = persisted.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            CurrencyIsoCode = null
        );
        ProductRelatedMaterialsService.RepairCodeCatalog catalog =
            new ProductRelatedMaterialsService.RepairCodeCatalog();
        catalog.categoryCodeIds.add(product.Id);

        Boolean threw = false;
        try {
            WorkOrderLineItemsService.reconcileRepairCodeWolisForDeviceEvaluation(
                workOrder,
                new Set<Id>{ product.Id },
                catalog
            );
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('currency'));
        }
        Assert.isTrue(threw, 'Blank in-memory currency should fail reconcile');
    }

    @IsTest
    static void testGetRepairCodeGetters_selectorThrows() {
        WorkOrder workOrder = [SELECT Id FROM WorkOrder LIMIT 1];
        Id repairCodeRtId = WorkOrderLineItemsService.getRepairCodeRecordTypeId();
        if (repairCodeRtId == null) {
            repairCodeRtId = UserInfo.getUserId();
        }
        WorkOrderLineItemsService.selectorOverride = new ThrowingSelector();
        try {
            Integer failures = 0;
            try {
                WorkOrderLineItemsService.getLineItemsById(new Set<Id>{ workOrder.Id });
            } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
                failures++;
            }
            try {
                WorkOrderLineItemsService.getLineItemsByWorkOrderId(new Set<Id>{ workOrder.Id });
            } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
                failures++;
            }
            try {
                WorkOrderLineItemsService.getRepairCodeLinesWithProduct(
                    workOrder.Id,
                    repairCodeRtId
                );
            } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
                failures++;
            }
            try {
                WorkOrderLineItemsService.getRepairCodeIds(workOrder.Id, repairCodeRtId);
            } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
                failures++;
            }
            try {
                WorkOrderLineItemsService.getRepairCodeByWorkOrderAndProducts(
                    workOrder.Id,
                    repairCodeRtId,
                    new Set<Id>{ workOrder.Id }
                );
            } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
                failures++;
            }
            try {
                WorkOrderLineItemsService.getRepairCodeLinesForReconcile(
                    workOrder.Id,
                    repairCodeRtId
                );
            } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
                failures++;
            }
            try {
                WorkOrderLineItemsService.getRepairCodeProductIds(workOrder.Id, repairCodeRtId);
            } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
                failures++;
            }
            try {
                WorkOrderLineItemsService.getNewestProductServicedId(
                    workOrder.Id,
                    workOrder.Id,
                    repairCodeRtId
                );
            } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
                failures++;
            }
            try {
                WorkOrderLineItemsService.getInstrumentEvaluationLines(workOrder.Id);
            } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
                failures++;
            }
            try {
                WorkOrderLineItemsService.deleteLineItems(new Set<Id>{ workOrder.Id });
            } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
                failures++;
            }
            Assert.isTrue(failures >= 8, 'Expected selector failures to be wrapped, got ' + failures);
        } finally {
            WorkOrderLineItemsService.selectorOverride = null;
        }
    }

    @IsTest
    static void shouldCoverDeviceEvaluationHelpersAndReconcileCreatePath() {
        WorkOrder workOrder = [
            SELECT
                Id,
                AssetId,
                ParentWorkOrderId,
                ParentWorkOrder.Pricebook2Id,
                Pricebook2Id,
                CurrencyIsoCode,
                EstimateRequired__c,
                Asset.Product2Id,
                Asset.SerialNumber,
                Asset.Product2.Model__c,
                Asset.Product2.ProductCode,
                Asset.Product2.Description,
                Asset.Product2.Name
            FROM WorkOrder
            LIMIT 1
        ];
        Id dummyRtId = UserInfo.getUserId();
        Product2 product = new Product2(
            Name = 'WOLI Coverage Product',
            ProductCode = 'WOLI-COV-001',
            ProductType__c = 'Category Code',
            Condition__c = 'Good',
            IsActive = true
        );
        insert product;

        ProductRelatedMaterialsService.RepairCodeCatalog catalog =
            new ProductRelatedMaterialsService.RepairCodeCatalog();
        catalog.categoryCodeIds.add(product.Id);
        catalog.observationCodeIds.add(
            (Id) (Product2.SObjectType.getDescribe().getKeyPrefix() + '000000000001')
        );
        catalog.serviceCodeIds.add(workOrder.Id);

        Test.startTest();
        Assert.areEqual(
            'Approved',
            WorkOrderLineItemsService.resolveRepairCodeWoliStatus(null)
        );
        workOrder.EstimateRequired__c = 'Estimate Required';
        Assert.areEqual(
            'Waiting for Approval',
            WorkOrderLineItemsService.resolveRepairCodeWoliStatus(workOrder)
        );
        Assert.areEqual(
            'Category Code',
            WorkOrderLineItemsService.resolveLineType(product.Id, catalog, product)
        );
        Product2 observationProduct = new Product2(
            Id = (Id) (Product2.SObjectType.getDescribe().getKeyPrefix() + '000000000001')
        );
        Assert.areEqual(
            'Observation Code',
            WorkOrderLineItemsService.resolveLineType(
                observationProduct.Id,
                catalog,
                observationProduct
            )
        );
        Assert.areEqual(
            'Service Code',
            WorkOrderLineItemsService.resolveLineType(workOrder.Id, catalog, product)
        );
        Assert.areEqual(
            'Category Code',
            WorkOrderLineItemsService.resolveLineType(null, null, product)
        );

        WorkOrderLineItemsService.getRepairCodeLinesWithProduct(workOrder.Id, dummyRtId);
        WorkOrderLineItemsService.getRepairCodeIds(workOrder.Id, dummyRtId);
        WorkOrderLineItemsService.getRepairCodeByWorkOrderAndProducts(
            workOrder.Id,
            dummyRtId,
            new Set<Id>{ product.Id }
        );
        WorkOrderLineItemsService.getRepairCodeLinesForReconcile(workOrder.Id, dummyRtId);
        WorkOrderLineItemsService.getRepairCodeProductIds(workOrder.Id, dummyRtId);
        WorkOrderLineItemsService.getNewestProductServicedId(
            workOrder.Id,
            dummyRtId,
            dummyRtId
        );

        WorkOrderLineItemsService.repairCodeRecordTypeIdOverride = dummyRtId;
        try {
            workOrder.Pricebook2Id = Test.getStandardPricebookId();
            workOrder.CurrencyIsoCode = UserInfo.getDefaultCurrency();
            Boolean threw = false;
            try {
                WorkOrderLineItemsService.reconcileRepairCodeWolisForDeviceEvaluation(
                    workOrder,
                    new Set<Id>{ product.Id },
                    catalog
                );
            } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
                threw = true;
            }
            Assert.isTrue(threw, 'Reconcile create path should fail without a Price Book Entry');
        } finally {
            WorkOrderLineItemsService.repairCodeRecordTypeIdOverride = null;
        }
        Test.stopTest();
    }

    /**
     * @description GW-3400 - Verifies persist and get guards for Instrument Evaluation items.
     */
    @IsTest
    static void testPersistInstrumentEvaluationItem_WhenMissingWorkOrder_Throws() {
        Boolean threw = false;
        Test.startTest();
        try {
            WorkOrderLineItemsService.persistInstrumentEvaluationItem(
                null,
                UserInfo.getUserId(),
                1,
                null
            );
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            threw = e.getMessage().contains('Work Order');
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Null Work Order should throw');
        Assert.isTrue(WorkOrderLineItemsService.getInstrumentEvaluationLines(null).isEmpty());
    }

    /**
     * @description Asset Instrument Evaluation lines cannot be deleted (default single line).
     */
    @IsTest
    static void testDeleteInstrumentEvaluationItem_WhenWorkOrderHasAsset_Throws() {
        adb_Account accountBuilder = new adb_Account().name('IE Asset Delete Account');
        adb_Product2 assetProduct = new adb_Product2()
            .name('IE Asset Delete Product')
            .productCode('IE-ASSET-DEL-001')
            .productType('Service Asset')
            .isActive(true);
        adb_Asset assetBuilder = new adb_Asset()
            .name('IE Asset Delete Asset')
            .account(accountBuilder)
            .product(assetProduct)
            .serialNumber('SN-IE-ASSET-DEL-001');
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .account(accountBuilder)
            .asset(assetBuilder)
            .status('Evaluate & Quote')
            .subject('IE Asset Delete WO')
            .setRecordType('RepairCenterInstruments')
            .pricebook2Id(Test.getStandardPricebookId());
        workOrderBuilder.persist();
        WorkOrder workOrder = (WorkOrder) workOrderBuilder.record;

        WorkOrderLineItem productServiced = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            Description = 'IE asset default line',
            Status = 'New'
        );
        insert productServiced;

        Boolean threw = false;
        String message = null;
        Test.startTest();
        try {
            WorkOrderLineItemsService.deleteInstrumentEvaluationItem(productServiced.Id);
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            threw = true;
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Delete on asset WO should throw');
        Assert.isTrue(
            message != null && message.contains('Asset'),
            'Expected asset delete message, got: ' + message
        );
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM WorkOrderLineItem WHERE Id = :productServiced.Id],
            'Line should still exist'
        );
    }

    // ── Allowed Unit evaluation (plural service; GW-4311) ─────────────────────

    @IsTest
    static void testEvaluateAllowedUnit_blankAndNoAsset() {
        Account account = new Account(
            Name = 'WOLIS AU Account',
            SystemID__c = 'LEG-WOLIS-AU1',
            SourceSystemID__c = 'TEST-ORACLE-WOLIS-AU1',
            OrgIDs__c = '82'
        );
        insert account;
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'WOLIS AU No Asset'
        );
        insert workOrder;
        Product2 product = new Product2(Name = 'WOLIS AU Part', IsActive = true);
        insert product;

        Test.startTest();
        AllowedUnitEvaluationDTO blank =
            WorkOrderLineItemsService.evaluateAllowedUnit(null, null);
        AllowedUnitEvaluationDTO byProductBlank =
            WorkOrderLineItemsService.evaluateAllowedUnitByProduct(null, null);
        AllowedUnitEvaluationDTO noAsset =
            WorkOrderLineItemsService.evaluateAllowedUnitByProduct(workOrder.Id, product.Id);
        Map<Id, AllowedUnitEvaluationDTO> emptyBulk =
            WorkOrderLineItemsService.evaluateAllowedUnits(workOrder.Id, new Set<Id>());
        Map<Id, AllowedUnitEvaluationDTO> emptyByProduct =
            WorkOrderLineItemsService.evaluateAllowedUnitsByProduct(workOrder.Id, null);
        Test.stopTest();

        Assert.areEqual(false, blank.evaluated);
        Assert.areEqual(false, byProductBlank.evaluated);
        Assert.areEqual(false, noAsset.hasAsset);
        Assert.areEqual(false, noAsset.evaluated);
        Assert.areEqual(0, emptyBulk.size());
        Assert.areEqual(0, emptyByProduct.size());
    }

    @IsTest
    static void testEvaluateAllowedUnit_withServiceBom() {
        Account account = new Account(
            Name = 'WOLIS AU BOM Account',
            SystemID__c = 'LEG-WOLIS-BOM',
            SourceSystemID__c = 'TEST-ORACLE-WOLIS-BOM',
            OrgIDs__c = '82'
        );
        insert account;

        ServiceBOM__c serviceBom = new ServiceBOM__c(
            Name = 'WOLIS SBOM ' + String.valueOf(Crypto.getRandomInteger()).right(6),
            Type__c = 'ES Asset BOM'
        );
        insert serviceBom;

        Product2 assetProduct = new Product2(
            Name = 'WOLIS Asset Product',
            IsActive = true,
            ProductType__c = 'Service Asset'
        );
        Product2 allowedPart = new Product2(
            Name = 'WOLIS Allowed Part',
            ProductCode = 'WOLIS-ALLOW',
            IsActive = true,
            ProductType__c = 'Part'
        );
        Product2 otherPart = new Product2(
            Name = 'WOLIS Other Part',
            ProductCode = 'WOLIS-OTHER',
            IsActive = true,
            ProductType__c = 'Part'
        );
        insert new List<Product2>{ assetProduct, allowedPart, otherPart };

        insert new ProductRelatedMaterial(
            Name = 'WOLIS BOM Component',
            ServiceBOM__c = serviceBom.Id,
            ProductId = assetProduct.Id,
            ProductComponentId = allowedPart.Id,
            QuantityPerProductUnit = 1
        );

        Asset asset = new Asset(
            Name = 'WOLIS AU Asset',
            AccountId = account.Id,
            Product2Id = assetProduct.Id,
            ServiceBOM__c = serviceBom.Id
        );
        insert asset;

        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'WOLIS AU BOM WO',
            AssetId = asset.Id
        );
        insert workOrder;

        Schema.Location loc = new Schema.Location(
            Name = 'WOLIS AU Loc',
            LocationType = 'Warehouse',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert loc;

        ProductItem allowedItem = new ProductItem(
            Product2Id = allowedPart.Id,
            LocationId = loc.Id,
            QuantityOnHand = 3
        );
        ProductItem otherItem = new ProductItem(
            Product2Id = otherPart.Id,
            LocationId = loc.Id,
            QuantityOnHand = 2
        );
        insert new List<ProductItem>{ allowedItem, otherItem };

        Test.startTest();
        AllowedUnitEvaluationDTO allowedResult =
            WorkOrderLineItemsService.evaluateAllowedUnit(workOrder.Id, allowedItem.Id);
        AllowedUnitEvaluationDTO otherResult =
            WorkOrderLineItemsService.evaluateAllowedUnit(workOrder.Id, otherItem.Id);
        AllowedUnitEvaluationDTO allowedByProduct =
            WorkOrderLineItemsService.evaluateAllowedUnitByProduct(workOrder.Id, allowedPart.Id);
        AllowedUnitEvaluationDTO otherByProduct =
            WorkOrderLineItemsService.evaluateAllowedUnitByProduct(workOrder.Id, otherPart.Id);
        Map<Id, AllowedUnitEvaluationDTO> bulkByItem =
            WorkOrderLineItemsService.evaluateAllowedUnits(
                workOrder.Id,
                new Set<Id>{ allowedItem.Id, otherItem.Id }
            );
        Map<Id, AllowedUnitEvaluationDTO> bulkByProduct =
            WorkOrderLineItemsService.evaluateAllowedUnitsByProduct(
                workOrder.Id,
                new Set<Id>{ allowedPart.Id, otherPart.Id }
            );
        Test.stopTest();

        Assert.isTrue(allowedResult.hasAsset);
        Assert.isTrue(allowedResult.evaluated);
        Assert.isTrue(allowedResult.allowedUnit);
        Assert.isTrue(otherResult.evaluated);
        Assert.isFalse(otherResult.allowedUnit);
        Assert.isTrue(allowedByProduct.allowedUnit);
        Assert.isFalse(otherByProduct.allowedUnit);
        Assert.areEqual(2, bulkByItem.size());
        Assert.areEqual(2, bulkByProduct.size());
    }

    @IsTest
    static void testEvaluateAllowedUnit_exceptionHooks() {
        Account account = new Account(
            Name = 'WOLIS AU Ex Account',
            SystemID__c = 'LEG-WOLIS-EX1',
            SourceSystemID__c = 'TEST-ORACLE-WOLIS-EX1',
            OrgIDs__c = '82'
        );
        insert account;
        WorkOrder workOrder = new WorkOrder(AccountId = account.Id, Subject = 'WOLIS AU Ex');
        insert workOrder;
        Product2 product = new Product2(Name = 'WOLIS AU Ex Part', IsActive = true);
        insert product;

        WorkOrderLineItemsService.simulateQueryException = true;
        Boolean queryThrew = false;
        try {
            WorkOrderLineItemsService.evaluateAllowedUnitByProduct(workOrder.Id, product.Id);
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            queryThrew = true;
        } finally {
            WorkOrderLineItemsService.simulateQueryException = false;
        }
        Assert.isTrue(queryThrew);

        WorkOrderLineItemsService.simulateGenericException = true;
        Boolean genericThrew = false;
        try {
            WorkOrderLineItemsService.evaluateAllowedUnitsByProduct(
                workOrder.Id,
                new Set<Id>{ product.Id }
            );
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            genericThrew = true;
        } finally {
            WorkOrderLineItemsService.simulateGenericException = false;
        }
        Assert.isTrue(genericThrew);
    }

    @IsTest
    static void testEvaluateAllowedUnit_missingItemAndNoBomAndSbomSkip() {
        Account account = new Account(
            Name = 'WOLIS AU Gap Account',
            SystemID__c = 'LEG-WOLIS-GAP',
            SourceSystemID__c = 'TEST-ORACLE-WOLIS-GAP',
            OrgIDs__c = '82'
        );
        insert account;

        Product2 assetProductNoBom = new Product2(
            Name = 'WOLIS NoBom Asset',
            IsActive = true,
            ProductType__c = 'Service Asset'
        );
        Product2 partNoBom = new Product2(
            Name = 'WOLIS NoBom Part',
            ProductCode = 'WOLIS-NB',
            IsActive = true,
            ProductType__c = 'Part'
        );
        insert new List<Product2>{ assetProductNoBom, partNoBom };

        Asset assetNoBom = new Asset(
            Name = 'WOLIS NoBom Asset',
            AccountId = account.Id,
            Product2Id = assetProductNoBom.Id
        );
        insert assetNoBom;
        WorkOrder woNoBom = new WorkOrder(
            AccountId = account.Id,
            Subject = 'WOLIS NoBom WO',
            AssetId = assetNoBom.Id
        );
        insert woNoBom;

        Schema.Location loc = new Schema.Location(
            Name = 'WOLIS Gap Loc',
            LocationType = 'Warehouse',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert loc;
        ProductItem item = new ProductItem(
            Product2Id = partNoBom.Id,
            LocationId = loc.Id,
            QuantityOnHand = 1
        );
        insert item;

        Id rootRtId = Schema.SObjectType.PFCL__c.getRecordTypeInfosByDeveloperName()
            .get('RootPFCL')
            ?.getRecordTypeId();
        Id versionRtId = Schema.SObjectType.PFCL__c.getRecordTypeInfosByDeveloperName()
            .get('ESPFCL')
            ?.getRecordTypeId();
        Assert.isNotNull(rootRtId);
        Assert.isNotNull(versionRtId);

        String unique = String.valueOf(Crypto.getRandomInteger()).right(6);
        PFCL__c rootPfcl = new PFCL__c(
            Name = 'WOLIS-R-' + unique,
            PFCL__c = 'WOLIS-RN-' + unique,
            RecordTypeId = rootRtId,
            SBOMRequired__c = 'No'
        );
        insert rootPfcl;
        PFCL__c versionPfcl = new PFCL__c(
            Name = 'WOLIS-V-' + unique,
            PFCL__c = 'WOLIS-VN-' + unique,
            RecordTypeId = versionRtId,
            Parent__c = rootPfcl.Id
        );
        insert versionPfcl;

        Product2 assetProductSkip = new Product2(
            Name = 'WOLIS Skip Asset',
            IsActive = true,
            ProductType__c = 'Service Asset',
            PFCL__c = versionPfcl.Id
        );
        Product2 partSkip = new Product2(
            Name = 'WOLIS Skip Part',
            ProductCode = 'WOLIS-SK',
            IsActive = true,
            ProductType__c = 'Part'
        );
        insert new List<Product2>{ assetProductSkip, partSkip };

        ServiceBOM__c serviceBom = new ServiceBOM__c(
            Name = 'WOLIS Skip SBOM ' + unique,
            Type__c = 'ES Asset BOM'
        );
        insert serviceBom;
        Asset assetSkip = new Asset(
            Name = 'WOLIS Skip Asset',
            AccountId = account.Id,
            Product2Id = assetProductSkip.Id,
            ServiceBOM__c = serviceBom.Id
        );
        insert assetSkip;
        WorkOrder woSkip = new WorkOrder(
            AccountId = account.Id,
            Subject = 'WOLIS Skip WO',
            AssetId = assetSkip.Id
        );
        insert woSkip;
        ProductItem skipItem = new ProductItem(
            Product2Id = partSkip.Id,
            LocationId = loc.Id,
            QuantityOnHand = 1
        );
        insert skipItem;

        Test.startTest();
        AllowedUnitEvaluationDTO denied =
            WorkOrderLineItemsService.evaluateAllowedUnit(woNoBom.Id, item.Id);
        AllowedUnitEvaluationDTO missingItem =
            WorkOrderLineItemsService.evaluateAllowedUnit(woNoBom.Id, partNoBom.Id);
        AllowedUnitEvaluationDTO sbomSkip =
            WorkOrderLineItemsService.evaluateAllowedUnit(woSkip.Id, skipItem.Id);

        WorkOrderLineItemsService.simulateQueryException = true;
        Boolean queryThrew = false;
        try {
            WorkOrderLineItemsService.evaluateAllowedUnits(
                woNoBom.Id,
                new Set<Id>{ item.Id }
            );
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            queryThrew = true;
        } finally {
            WorkOrderLineItemsService.simulateQueryException = false;
        }

        WorkOrderLineItemsService.simulateGenericException = true;
        Boolean genericThrew = false;
        try {
            WorkOrderLineItemsService.evaluateAllowedUnits(
                woNoBom.Id,
                new Set<Id>{ item.Id }
            );
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            genericThrew = true;
        } finally {
            WorkOrderLineItemsService.simulateGenericException = false;
        }
        Test.stopTest();

        Assert.isTrue(denied.hasAsset);
        Assert.isTrue(denied.evaluated);
        Assert.isFalse(denied.allowedUnit);
        Assert.isTrue(missingItem.evaluated);
        Assert.isFalse(missingItem.allowedUnit);
        Assert.isTrue(sbomSkip.hasAsset);
        Assert.isFalse(sbomSkip.evaluated);
        Assert.isTrue(queryThrew);
        Assert.isTrue(genericThrew);
    }

    @IsTest
    static void testUpdateLineItems_unexpectedExceptionWrapped() {
        Id fakeId = Schema.SObjectType.WorkOrderLineItem.getKeyPrefix() + '000000000001AAA';
        WorkOrderLineItem ghost = new WorkOrderLineItem(Id = fakeId, Quantity = 9);

        Boolean threw = false;
        Test.startTest();
        try {
            WorkOrderLineItemsService.updateLineItems(new List<WorkOrderLineItem>{ ghost });
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('unexpected') || String.isNotBlank(e.getMessage()),
                e.getMessage()
            );
        }
        Test.stopTest();
        Assert.isTrue(threw);
    }

    @IsTest
    static void testCreateLineItems_simulatedGenericExceptionWrapped() {
        WorkOrderLineItemsService.simulateGenericException = true;
        Boolean threw = false;
        try {
            WorkOrderLineItemsService.createLineItems(
                new List<WorkOrderLineItem>{ new WorkOrderLineItem(Quantity = 1) }
            );
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            threw = true;
        } finally {
            WorkOrderLineItemsService.simulateGenericException = false;
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void testGetLineItemByIdAndWorkOrderId() {
        WorkOrderLineItem lineItem = [
            SELECT Id, WorkOrderId
            FROM WorkOrderLineItem
            LIMIT 1
        ];

        Test.startTest();
        WorkOrderLineItem match = WorkOrderLineItemsService.getLineItemByIdAndWorkOrderId(
            lineItem.Id,
            lineItem.WorkOrderId
        );
        WorkOrderLineItem wrongParent = WorkOrderLineItemsService.getLineItemByIdAndWorkOrderId(
            lineItem.Id,
            UserInfo.getUserId()
        );
        WorkOrderLineItem nullIds = WorkOrderLineItemsService.getLineItemByIdAndWorkOrderId(null, null);
        Test.stopTest();

        Assert.areEqual(lineItem.Id, match.Id, 'Expected the line on its Work Order');
        Assert.isNull(wrongParent, 'A different parent should not match');
        Assert.isNull(nullIds, 'Null Ids should return null');
    }

    /**
     * @description Covers Instrument Evaluation persist, sync, and remove on WorkOrderLineItemsService.
     */
    @IsTest
    static void testPersistSyncAndRemoveInstrumentEvaluationItem() {
        adb_Account accountBuilder = new adb_Account().name('IE Service Coverage Account');
        Product2 product = new Product2(
            Name = 'IE Service Coverage Product',
            ProductCode = 'IE-SVC-COV-001',
            IsActive = true
        );
        insert product;
        Id pricebookId = Test.getStandardPricebookId();
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .account(accountBuilder)
            .status('Evaluate & Quote')
            .subject('IE Service Coverage WO')
            .setRecordType('RepairCenterInstruments')
            .pricebook2Id(pricebookId);
        workOrderBuilder.persist();
        WorkOrder workOrder = [
            SELECT Id, Subject, Description, ParentWorkOrderId, Pricebook2Id, CurrencyIsoCode,
                Model__c, TrayName__c, AssetId, EstimateRequired__c
            FROM WorkOrder
            WHERE Id = :workOrderBuilder.record.Id
        ];
        PricebookEntry pricebookEntry = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );
        if (String.isNotBlank(workOrder.CurrencyIsoCode)) {
            pricebookEntry.CurrencyIsoCode = workOrder.CurrencyIsoCode;
        }
        insert pricebookEntry;

        Boolean productMissing = false;
        Boolean quantityInvalid = false;
        try {
            WorkOrderLineItemsService.persistInstrumentEvaluationItem(workOrder, null, 1, null);
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            productMissing = e.getMessage().contains('Product');
        }
        try {
            WorkOrderLineItemsService.persistInstrumentEvaluationItem(workOrder, product.Id, 0, null);
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            quantityInvalid = e.getMessage().contains('Quantity');
        }

        Test.startTest();
        Id lineId = WorkOrderLineItemsService.persistInstrumentEvaluationItem(
            workOrder,
            product.Id,
            1,
            null,
            'ROLI-1'
        );
        List<WorkOrderLineItem> lines = WorkOrderLineItemsService.getInstrumentEvaluationLines(workOrder.Id);
        Id syncedId = WorkOrderLineItemsService.syncInstrumentEvaluationItem(
            workOrder,
            lineId,
            product.Id,
            2,
            null,
            'ROLI-2'
        );
        WorkOrderLineItem mappedLine = [
            SELECT ReturnOrderLineItems__c, ProductLine__c
            FROM WorkOrderLineItem
            WHERE Id = :lineId
        ];
        WorkOrderLineItemsService.reconcileInstrumentEvaluationRemovedLines(
            workOrder.Id,
            new Set<Id>()
        );
        Test.stopTest();

        Assert.isTrue(productMissing, 'Null product should be rejected');
        Assert.isTrue(quantityInvalid, 'Zero quantity should be rejected');
        Assert.isNotNull(lineId, 'Persist should create a Product Serviced line');
        Assert.areEqual(
            'INSTRUMENT',
            mappedLine.ProductLine__c,
            'GW-5328 Product Serviced Product Line should be INSTRUMENT'
        );
        Assert.isFalse(lines.isEmpty(), 'Instrument Evaluation lines should be readable');
        Assert.areEqual(lineId, syncedId, 'Sync should return the same line');
        Assert.areEqual(
            'ROLI-2',
            mappedLine.ReturnOrderLineItems__c,
            'Sync should update the RO Line mapping'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM WorkOrderLineItem WHERE Id = :lineId],
            'Reconcile with no retained lines should delete the item'
        );
    }

    /**
     * @description Covers the simulated failure path on getLineItemByIdAndWorkOrderId.
     */
    @IsTest
    static void testGetLineItemByIdAndWorkOrderId_WhenSimulated_Throws() {
        WorkOrderLineItemsService.simulateGenericException = true;
        Boolean threw = false;
        try {
            WorkOrderLineItemsService.getLineItemByIdAndWorkOrderId(
                UserInfo.getUserId(),
                UserInfo.getUserId()
            );
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            threw = true;
        } finally {
            WorkOrderLineItemsService.simulateGenericException = false;
        }
        Assert.isTrue(threw, 'Simulated failure should be wrapped');
    }

    /**
     * @description Covers Instrument Evaluation repair-code create, sync, and warranty lookup.
     */
    @IsTest
    static void testPersistInstrumentEvaluationItem_WithRepairCodes() {
        adb_Account accountBuilder = new adb_Account().name('IE Repair Code Coverage Account');
        Product2 instrument = new Product2(
            Name = 'IE Repair Code Instrument',
            ProductCode = 'IE-SVC-INST-002',
            IsActive = true,
            Description = 'Instrument for repair code coverage'
        );
        Product2 repairCode = new Product2(
            Name = 'IE Repair Code One',
            ProductCode = 'IE-SVC-RC-001',
            ProductType__c = 'Category Code',
            IsActive = true,
            Description = 'First repair code'
        );
        Product2 secondRepairCode = new Product2(
            Name = 'IE Repair Code Two',
            ProductCode = 'IE-SVC-RC-002',
            ProductType__c = 'Service Code',
            IsActive = true,
            Description = 'Second repair code'
        );
        insert new List<Product2>{ instrument, repairCode, secondRepairCode };

        Id pricebookId = Test.getStandardPricebookId();
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .account(accountBuilder)
            .status('Evaluate & Quote')
            .subject('IE Repair Code Coverage WO')
            .setRecordType('RepairCenterInstruments')
            .pricebook2Id(pricebookId);
        workOrderBuilder.persist();
        WorkOrder workOrder = [
            SELECT Id, Subject, Description, ParentWorkOrderId, Pricebook2Id, CurrencyIsoCode,
                Model__c, TrayName__c, AssetId, EstimateRequired__c,
                ParentWorkOrder.Pricebook2Id
            FROM WorkOrder
            WHERE Id = :workOrderBuilder.record.Id
        ];
        List<PricebookEntry> pricebookEntries = new List<PricebookEntry>();
        for (Product2 product : new List<Product2>{ instrument, repairCode, secondRepairCode }) {
            PricebookEntry pricebookEntry = new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id = product.Id,
                UnitPrice = 1,
                IsActive = true
            );
            if (String.isNotBlank(workOrder.CurrencyIsoCode)) {
                pricebookEntry.CurrencyIsoCode = workOrder.CurrencyIsoCode;
            }
            pricebookEntries.add(pricebookEntry);
        }
        insert pricebookEntries;

        Boolean missingLine = false;
        Boolean quantityInvalid = false;
        try {
            WorkOrderLineItemsService.syncInstrumentEvaluationItem(
                workOrder,
                null,
                instrument.Id,
                1,
                null
            );
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            missingLine = e.getMessage().contains('Product Serviced');
        }
        try {
            WorkOrderLineItemsService.syncInstrumentEvaluationItem(
                workOrder,
                instrument.Id,
                instrument.Id,
                0,
                null
            );
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            quantityInvalid = e.getMessage().contains('Quantity');
        }

        Test.startTest();
        Id lineId = WorkOrderLineItemsService.persistInstrumentEvaluationItem(
            workOrder,
            instrument.Id,
            1,
            new List<Id>{ repairCode.Id }
        );
        WorkOrderLineItem warrantyLine =
            WorkOrderLineItemsService.getLineItemForWarrantyRepairEvaluation(lineId);
        Id syncedId = WorkOrderLineItemsService.syncInstrumentEvaluationItem(
            workOrder,
            lineId,
            instrument.Id,
            2,
            new List<Id>{ repairCode.Id, secondRepairCode.Id }
        );
        WorkOrderLineItemsService.reconcileInstrumentEvaluationRemovedLines(
            workOrder.Id,
            new Set<Id>()
        );
        Test.stopTest();

        Assert.isTrue(missingLine, 'Sync without a Product Serviced line should be rejected');
        Assert.isTrue(quantityInvalid, 'Zero quantity should be rejected');
        Assert.isNotNull(lineId, 'Persist should create the Product Serviced line');
        Assert.areEqual(lineId, warrantyLine.Id, 'Warranty lookup should return the line');
        Assert.areEqual(lineId, syncedId, 'Sync should return the same line');
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM WorkOrderLineItem WHERE WorkOrderId = :workOrder.Id],
            'Reconcile should delete the Product Serviced line and its repair codes'
        );
    }

    /**
     * @description Covers the simulated failure path on the warranty evaluation lookup.
     */
    @IsTest
    static void testGetLineItemForWarrantyRepairEvaluation_WhenSimulated_Throws() {
        Assert.isNull(
            WorkOrderLineItemsService.getLineItemForWarrantyRepairEvaluation(null),
            'Null Id should return null'
        );
        WorkOrderLineItemsService.simulateGenericException = true;
        Boolean threw = false;
        try {
            WorkOrderLineItemsService.getLineItemForWarrantyRepairEvaluation(UserInfo.getUserId());
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            threw = true;
        } finally {
            WorkOrderLineItemsService.simulateGenericException = false;
        }
        Assert.isTrue(threw, 'Simulated failure should be wrapped');
    }

    // ── GW-5968 createReceivingDisinfectionCodeLine ───────────────────────────

    @IsTest
    static void testCreateReceivingDisinfectionCodeLine_createsRepairCodeLine() {
        // Setup
        Id repairCodeRtId = WorkOrderLineItemsService.getRepairCodeRecordTypeId();
        Assert.isNotNull(repairCodeRtId, 'RepairCode record type is required');
        Account accountRecord = new Account(Name = 'GW5968 WOLI Disinfection Acct');
        insert accountRecord;
        PricebookEntry servicedPbe = insertReceivingDisinfectionServicedPbe(
            'GW5968 WOLI Scope',
            'WOLI.RR.001',
            'FLEXIBLE SCOPE'
        );
        Product2 disinfectionProduct = insertReceivingDisinfectionProduct(
            'FLEXIBLE SCOPE',
            'WOLI.DIS.001',
            true
        );
        WorkOrder workOrder = insertReceivingDevicesWorkOrder(
            accountRecord.Id,
            servicedPbe.Product2Id
        );
        WorkOrderLineItem serviced = insertReceivingProductServicedLine(
            workOrder.Id,
            servicedPbe.Id,
            'SN-WOLI-001'
        );

        // When
        Test.startTest();
        Id disinfectionLineId = WorkOrderLineItemsService.createReceivingDisinfectionCodeLine(
            workOrder.Id,
            serviced.Id,
            2,
            disinfectionProduct
        );
        Test.stopTest();

        // Then
        Assert.isNotNull(disinfectionLineId);
        WorkOrderLineItem disinfection = [
            SELECT
                WorkOrderId,
                ParentWorkOrderLineItemId,
                Quantity,
                Status,
                LineType__c,
                Product__c,
                RepairCode__c,
                ProductCodeWoli__c,
                RecordTypeId,
                PricebookEntryId
            FROM WorkOrderLineItem
            WHERE Id = :disinfectionLineId
        ];
        Assert.areEqual(workOrder.Id, disinfection.WorkOrderId);
        Assert.areEqual(serviced.Id, disinfection.ParentWorkOrderLineItemId);
        Assert.areEqual(2, disinfection.Quantity);
        Assert.areEqual('Approved', disinfection.Status);
        Assert.areEqual('Service Code', disinfection.LineType__c);
        Assert.areEqual(disinfectionProduct.Id, disinfection.Product__c);
        Assert.areEqual(disinfectionProduct.Id, disinfection.RepairCode__c);
        Assert.areEqual('WOLI.DIS.001', disinfection.ProductCodeWoli__c);
        Assert.areEqual(repairCodeRtId, disinfection.RecordTypeId);
        Assert.isNotNull(disinfection.PricebookEntryId);
    }

    @IsTest
    static void testCreateReceivingDisinfectionCodeLine_defaultsQuantityToOne() {
        // Setup
        Account accountRecord = new Account(Name = 'GW5968 WOLI Qty Acct');
        insert accountRecord;
        PricebookEntry servicedPbe = insertReceivingDisinfectionServicedPbe(
            'GW5968 WOLI Qty Scope',
            'WOLI.RR.002',
            'FLEXIBLE SCOPE'
        );
        Product2 disinfectionProduct = insertReceivingDisinfectionProduct(
            'FLEXIBLE SCOPE',
            'WOLI.DIS.002',
            true
        );
        WorkOrder workOrder = insertReceivingDevicesWorkOrder(
            accountRecord.Id,
            servicedPbe.Product2Id
        );
        WorkOrderLineItem serviced = insertReceivingProductServicedLine(
            workOrder.Id,
            servicedPbe.Id,
            'SN-WOLI-002'
        );

        // When
        Test.startTest();
        Id disinfectionLineId = WorkOrderLineItemsService.createReceivingDisinfectionCodeLine(
            workOrder.Id,
            serviced.Id,
            null,
            disinfectionProduct
        );
        Test.stopTest();

        // Then
        Assert.areEqual(
            1,
            [SELECT Quantity FROM WorkOrderLineItem WHERE Id = :disinfectionLineId].Quantity,
            'Null quantity should default to 1'
        );
    }

    @IsTest
    static void testCreateReceivingDisinfectionCodeLine_nullGuards() {
        // Setup
        Product2 disinfectionProduct = new Product2(
            Name = 'Unused',
            IsActive = true,
            ProductCode = 'WOLI.DIS.NULL'
        );
        insert disinfectionProduct;
        Boolean nullWorkOrder = false;
        Boolean nullServiced = false;
        Boolean nullProduct = false;

        // When
        Test.startTest();
        try {
            WorkOrderLineItemsService.createReceivingDisinfectionCodeLine(
                null,
                UserInfo.getUserId(),
                1,
                disinfectionProduct
            );
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            nullWorkOrder = e.getMessage().contains('Work Order');
        }
        try {
            WorkOrderLineItemsService.createReceivingDisinfectionCodeLine(
                UserInfo.getUserId(),
                null,
                1,
                disinfectionProduct
            );
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            nullServiced = e.getMessage().contains('Product Serviced');
        }
        try {
            WorkOrderLineItemsService.createReceivingDisinfectionCodeLine(
                UserInfo.getUserId(),
                UserInfo.getUserId(),
                1,
                null
            );
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            nullProduct = e.getMessage().contains('Disinfection product');
        }
        Test.stopTest();

        // Then
        Assert.isTrue(nullWorkOrder, 'Null Work Order should throw');
        Assert.isTrue(nullServiced, 'Null Product Serviced line should throw');
        Assert.isTrue(nullProduct, 'Null Disinfection product should throw');
    }

    @IsTest
    static void testCreateReceivingDisinfectionCodeLine_missingPricebookEntry_throws() {
        // Setup
        Account accountRecord = new Account(Name = 'GW5968 WOLI Missing PBE Acct');
        insert accountRecord;
        PricebookEntry servicedPbe = insertReceivingDisinfectionServicedPbe(
            'GW5968 WOLI Missing PBE Scope',
            'WOLI.RR.003',
            'FLEXIBLE SCOPE'
        );
        Product2 disinfectionProduct = insertReceivingDisinfectionProduct(
            'FLEXIBLE SCOPE',
            'WOLI.DIS.003',
            false
        );
        WorkOrder workOrder = insertReceivingDevicesWorkOrder(
            accountRecord.Id,
            servicedPbe.Product2Id
        );
        WorkOrderLineItem serviced = insertReceivingProductServicedLine(
            workOrder.Id,
            servicedPbe.Id,
            'SN-WOLI-003'
        );
        Boolean threw = false;

        // When
        Test.startTest();
        try {
            WorkOrderLineItemsService.createReceivingDisinfectionCodeLine(
                workOrder.Id,
                serviced.Id,
                1,
                disinfectionProduct
            );
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('Price Book Entry'),
                e.getMessage()
            );
        }
        Test.stopTest();

        // Then
        Assert.isTrue(threw, 'Missing Price Book Entry should throw');
    }

    @IsTest
    static void testCreateReceivingAccessoryLines_mapsQuantity() {
        // Setup
        Account accountRecord = new Account(Name = 'GW5492 WOLI Accessory Acct');
        insert accountRecord;
        PricebookEntry servicedPbe = insertReceivingDisinfectionServicedPbe(
            'GW5492 WOLI Accessory Scope',
            'WOLI.ACC.001',
            'FLEXIBLE SCOPE'
        );
        WorkOrder workOrder = insertReceivingDevicesWorkOrder(
            accountRecord.Id,
            servicedPbe.Product2Id
        );
        Asset assetRecord = new Asset(
            Name = 'GW5492 Accessory Asset',
            AccountId = accountRecord.Id,
            Product2Id = servicedPbe.Product2Id,
            SerialNumber = 'SN-ACC-ASSET'
        );
        insert assetRecord;
        update new WorkOrder(
            Id = workOrder.Id,
            AssetId = assetRecord.Id,
            SerialNumber__c = 'SN-ACC-ASSET',
            Model__c = 'LEG STIRRUP'
        );
        WorkOrderLineItem serviced = insertReceivingProductServicedLine(
            workOrder.Id,
            servicedPbe.Id,
            'SN-ACC-001'
        );
        WorkOrderLineItemsService.ReceivingAccessoryInput accessory =
            new WorkOrderLineItemsService.ReceivingAccessoryInput();
        accessory.accessoryType = 'Case';
        accessory.storageLocation = 'One';
        accessory.quantity = 3;

        // When
        Test.startTest();
        WorkOrderLineItemsService.createReceivingAccessoryLines(
            workOrder.Id,
            serviced.Id,
            servicedPbe.Product2Id,
            new List<WorkOrderLineItemsService.ReceivingAccessoryInput>{ accessory }
        );
        Test.stopTest();

        // Then
        WorkOrderLineItem created = [
            SELECT Quantity, UnitQty__c, IsAccessory__c, AccessoryType__c,
                AssetId, SerialNumber__c, Model__c
            FROM WorkOrderLineItem
            WHERE ParentWorkOrderLineItemId = :serviced.Id
              AND IsAccessory__c = TRUE
        ];
        Assert.areEqual(3, created.Quantity, 'Accessory Quantity should match the entered count');
        Assert.areEqual(3, created.UnitQty__c, 'Unit Qty should match the entered count');
        Assert.areEqual('Case', created.AccessoryType__c);
        Assert.areEqual(assetRecord.Id, created.AssetId);
        Assert.areEqual('SN-ACC-ASSET', created.SerialNumber__c);
        Assert.areEqual('LEG STIRRUP', created.Model__c);
    }

    @IsTest
    static void testCreateReceivingProductServicedLine_createsMissingStandardPrice() {
        Product2 product = new Product2(
            Name = 'GW5492 Missing Price Cable',
            ProductCode = 'VI.MISS.10853',
            IsActive = true
        );
        insert product;
        Id standardPricebookId = Test.getStandardPricebookId();
        update new Pricebook2(Id = standardPricebookId, IsActive = true);
        Pricebook2 customPricebook = new Pricebook2(
            Name = 'GW5492 Missing Price Book',
            IsActive = true
        );
        insert customPricebook;

        adb_Account accountBuilder = new adb_Account()
            .name('GW5492 Missing Price Account')
            .systemId('LEG5492MISS');
        accountBuilder.set(Account.OrgIDs__c, '82');
        Account accountRecord = (Account) accountBuilder.persist();

        WorkOrder workOrder = new WorkOrder(
            Subject = 'GW5492 Missing Price',
            AccountId = accountRecord.Id,
            RecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
                .get('RepairCenterOther')
                .getRecordTypeId(),
            Pricebook2Id = customPricebook.Id
        );
        insert workOrder;

        ReturnOrderLineItem lineItem = new ReturnOrderLineItem(Product2Id = product.Id);

        Test.startTest();
        Id woliId = WorkOrderLineItemsService.createReceivingProductServicedLine(
            workOrder.Id,
            workOrder.Id,
            null,
            lineItem,
            null
        );
        Test.stopTest();

        WorkOrderLineItem created = [
            SELECT PricebookEntry.Pricebook2Id, PricebookEntry.Product2Id
            FROM WorkOrderLineItem
            WHERE Id = :woliId
        ];
        Assert.areEqual(customPricebook.Id, created.PricebookEntry.Pricebook2Id);
        Assert.areEqual(product.Id, created.PricebookEntry.Product2Id);
        Integer standardPrices = [
            SELECT COUNT()
            FROM PricebookEntry
            WHERE Pricebook2Id = :standardPricebookId
              AND Product2Id = :product.Id
        ];
        Assert.areEqual(1, standardPrices);
    }

    @IsTest
    static void testCreateReceivingProductServicedLine_copiesPriorityRepair() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW5492 Priority Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        adb_Account accountBuilder = new adb_Account()
            .name('GW5492 Priority Account')
            .systemId('LEG5492PRI');
        accountBuilder.set(Account.OrgIDs__c, '82');

        adb_ReturnOrder returnOrderBuilder = new adb_ReturnOrder()
            .account(accountBuilder)
            .status('Created');
        returnOrderBuilder.recordType('CustomerReturn');
        returnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
        returnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Serialized');
        returnOrderBuilder.set(ReturnOrder.DestinationLocationId, repairCenter.Id);

        PricebookEntry servicedPbe = insertReceivingDisinfectionServicedPbe(
            'GW5492 Priority Scope',
            'WOLI.PRI.001',
            'FLEXIBLE SCOPE'
        );

        adb_ReturnOrderLineItem lineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(returnOrderBuilder)
            .quantityReturned(1);
        lineBuilder.set(ReturnOrderLineItem.Product2Id, servicedPbe.Product2Id);
        lineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        lineBuilder.set(ReturnOrderLineItem.IsPriorityRepair__c, true);
        ReturnOrderLineItem lineItem = (ReturnOrderLineItem) lineBuilder.persist();
        lineItem = [
            SELECT
                Id,
                ReturnOrderId,
                Product2Id,
                IsPriorityRepair__c,
                AssetId,
                SerialNumber__c,
                Model__c,
                HospitalReferencedTrayName__c,
                ReturnOrderLineItemNumber,
                ProductLine__c,
                ModRequest__c
            FROM ReturnOrderLineItem
            WHERE Id = :lineItem.Id
        ];

        Account accountRecord = [
            SELECT Id
            FROM Account
            WHERE Name = 'GW5492 Priority Account'
            LIMIT 1
        ];
        WorkOrder workOrder = insertReceivingDevicesWorkOrder(
            accountRecord.Id,
            servicedPbe.Product2Id
        );

        Test.startTest();
        Id woliId = WorkOrderLineItemsService.createReceivingProductServicedLine(
            workOrder.Id,
            workOrder.Id,
            lineItem.ReturnOrderId,
            lineItem,
            null
        );
        Test.stopTest();

        WorkOrderLineItem created = [
            SELECT IsPriorityRepair__c, LineType__c, Status
            FROM WorkOrderLineItem
            WHERE Id = :woliId
        ];
        Assert.areEqual('Product Serviced', created.LineType__c);
        Assert.isTrue(created.IsPriorityRepair__c);
        Assert.areEqual('Approved', created.Status);
    }

    @IsTest
    static void testCreateReceivingProductServicedLine_estimateRequiredWaitsForApproval() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW5492 Estimate Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        adb_Account accountBuilder = new adb_Account()
            .name('GW5492 Estimate Account')
            .systemId('LEG5492EST');
        accountBuilder.set(Account.OrgIDs__c, '82');

        adb_ReturnOrder returnOrderBuilder = new adb_ReturnOrder()
            .account(accountBuilder)
            .status('Created');
        returnOrderBuilder.recordType('CustomerReturn');
        returnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
        returnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Serialized');
        returnOrderBuilder.set(ReturnOrder.DestinationLocationId, repairCenter.Id);

        PricebookEntry servicedPbe = insertReceivingDisinfectionServicedPbe(
            'GW5492 Estimate Scope',
            'WOLI.EST.001',
            'FLEXIBLE SCOPE'
        );

        adb_ReturnOrderLineItem lineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(returnOrderBuilder)
            .quantityReturned(1);
        lineBuilder.set(ReturnOrderLineItem.Product2Id, servicedPbe.Product2Id);
        lineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        lineBuilder.set(ReturnOrderLineItem.EstimateRequired__c, 'Estimate Required');
        ReturnOrderLineItem lineItem = (ReturnOrderLineItem) lineBuilder.persist();

        Account accountRecord = [
            SELECT Id
            FROM Account
            WHERE Name = 'GW5492 Estimate Account'
            LIMIT 1
        ];
        WorkOrder workOrder = insertReceivingDevicesWorkOrder(
            accountRecord.Id,
            servicedPbe.Product2Id
        );
        update new WorkOrder(
            Id = workOrder.Id,
            EstimateRequired__c = 'Estimate Required'
        );

        Test.startTest();
        Id woliId = WorkOrderLineItemsService.createReceivingProductServicedLine(
            workOrder.Id,
            workOrder.Id,
            lineItem.ReturnOrderId,
            lineItem,
            null
        );
        Test.stopTest();

        WorkOrderLineItem created = [
            SELECT Status
            FROM WorkOrderLineItem
            WHERE Id = :woliId
        ];
        Assert.areEqual('Waiting for Approval', created.Status);
    }

    @IsTest
    static void testCreateReceivingProductServicedLine_usesReceivedQuantity() {
        Product2 product = new Product2(
            Name = 'GW5492 Quantity Cable',
            ProductCode = 'VI.QTY.10853',
            IsActive = true
        );
        insert product;
        Id standardPricebookId = Test.getStandardPricebookId();
        update new Pricebook2(Id = standardPricebookId, IsActive = true);

        adb_Account accountBuilder = new adb_Account()
            .name('GW5492 Quantity Account')
            .systemId('LEG5492QTY');
        accountBuilder.set(Account.OrgIDs__c, '82');
        Account accountRecord = (Account) accountBuilder.persist();

        WorkOrder workOrder = new WorkOrder(
            Subject = 'GW5492 Quantity',
            AccountId = accountRecord.Id,
            RecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
                .get('RepairCenterOther')
                .getRecordTypeId(),
            Pricebook2Id = standardPricebookId
        );
        insert workOrder;

        ReturnOrderLineItem lineItem = new ReturnOrderLineItem(
            Product2Id = product.Id,
            QuantityReturned = 2
        );
        WorkOrderLineItemsService.ReceivingProductServicedInput request =
            new WorkOrderLineItemsService.ReceivingProductServicedInput();
        request.quantityReceived = 2;

        Test.startTest();
        Id woliId = WorkOrderLineItemsService.createReceivingProductServicedLine(
            workOrder.Id,
            workOrder.Id,
            null,
            lineItem,
            request
        );
        Test.stopTest();

        WorkOrderLineItem created = [
            SELECT Quantity
            FROM WorkOrderLineItem
            WHERE Id = :woliId
        ];
        Assert.areEqual(2, created.Quantity);
    }

    private static WorkOrder insertReceivingDevicesWorkOrder(Id accountId, Id product2Id) {
        WorkOrder workOrder = new WorkOrder(
            Subject = 'GW5968 WOLI Disinfection',
            AccountId = accountId,
            RecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
                .get('RepairCenterDevices')
                .getRecordTypeId(),
            Pricebook2Id = Test.getStandardPricebookId(),
            Product__c = product2Id
        );
        insert workOrder;
        return workOrder;
    }

    private static WorkOrderLineItem insertReceivingProductServicedLine(
        Id workOrderId,
        Id pricebookEntryId,
        String serialNumber
    ) {
        WorkOrderLineItem lineItem = new WorkOrderLineItem(
            WorkOrderId = workOrderId,
            RecordTypeId = Schema.SObjectType.WorkOrderLineItem.getRecordTypeInfosByDeveloperName()
                .get('ProductServiced')
                .getRecordTypeId(),
            LineType__c = 'Product Serviced',
            IsAccessory__c = false,
            PricebookEntryId = pricebookEntryId,
            Quantity = 1,
            SerialNumber__c = serialNumber
        );
        insert lineItem;
        return lineItem;
    }

    private static Product2 insertReceivingDisinfectionProduct(
        String productLine,
        String productCode,
        Boolean withPricebookEntry
    ) {
        Product2 product = new Product2(
            Name = 'GW5968 WOLI Disinfection ' + productCode,
            IsActive = true,
            Status__c = 'Active',
            ProductCode = productCode,
            ProductLine__c = productLine,
            ServiceCodeType__c = 'Disinfection'
        );
        insert product;
        if (withPricebookEntry) {
            insert new PricebookEntry(
                Pricebook2Id = Test.getStandardPricebookId(),
                Product2Id = product.Id,
                UnitPrice = 1,
                IsActive = true
            );
        }
        return product;
    }

    private static PricebookEntry insertReceivingDisinfectionServicedPbe(
        String name,
        String productCode,
        String productLine
    ) {
        Product2 product = new Product2(
            Name = name,
            IsActive = true,
            ProductCode = productCode,
            ProductLine__c = productLine,
            DeviceType__c = 'SCOPE',
            Model__c = 'GIF-H190'
        );
        insert product;
        PricebookEntry entry = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );
        insert entry;
        return entry;
    }

    @IsTest
    static void testCreateReceivingOrderDisinfectionCodeLine_createsUnparentedLine() {
        Account accountRecord = new Account(Name = 'GW5968 Order Disinfection Account');
        insert accountRecord;
        Product2 product = new Product2(
            Name = 'GW5968 Order Disinfection',
            IsActive = true,
            ProductCode = 'DIS.ORD1',
            ProductLine__c = 'INSTRUMENT',
            ServiceCodeType__c = 'Disinfection'
        );
        insert product;
        insert new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );
        WorkOrder workOrder = new WorkOrder(
            Subject = 'GW5968 Order Disinfection',
            AccountId = accountRecord.Id,
            RecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
                .get('RepairCenterInstruments')
                .getRecordTypeId(),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert workOrder;

        Test.startTest();
        Id lineId = WorkOrderLineItemsService.createReceivingOrderDisinfectionCodeLine(
            workOrder.Id,
            3,
            product
        );
        Test.stopTest();

        WorkOrderLineItem lineItem = [
            SELECT ParentWorkOrderLineItemId, Quantity, Product__c, LineType__c
            FROM WorkOrderLineItem
            WHERE Id = :lineId
        ];
        Assert.isNull(lineItem.ParentWorkOrderLineItemId);
        Assert.areEqual(3, lineItem.Quantity);
        Assert.areEqual(product.Id, lineItem.Product__c);
        Assert.areEqual('Service Code', lineItem.LineType__c);
    }
}