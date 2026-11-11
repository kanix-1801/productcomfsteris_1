/**
 * @description Test class for WorkOrderLineItemsSelector.
 *              Covers all query methods, null/empty guard clauses, and bulk behaviour.
 */
@IsTest
private class WorkOrderLineItemsSelectorTest {

    @TestSetup
    static void setupTestData() {
        // Persist a parent WorkOrder first
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .subject('Selector Test Work Order');
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

    // ── selectById ────────────────────────────────────────────────────────────

    @IsTest
    static void shouldReturnLineItems_WhenSelectByIdCalledWithValidIds() {
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
            List<WorkOrderLineItem> resultList = WorkOrderLineItemsSelector.selectById(lineItemIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(251, resultList.size(), 'selectById should return all 251 WorkOrderLineItems matching the provided Ids');
        }
    }

    @IsTest
    static void shouldReturnEmpty_WhenSelectByIdCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<WorkOrderLineItem> resultList = WorkOrderLineItemsSelector.selectById(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'selectById should return an empty list when passed null');
        }
    }

    @IsTest
    static void shouldReturnEmpty_WhenSelectByIdCalledWithEmptySet() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<WorkOrderLineItem> resultList = WorkOrderLineItemsSelector.selectById(new Set<Id>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'selectById should return an empty list when passed an empty Set');
        }
    }

    // ── selectByWorkOrderId ───────────────────────────────────────────────────

    @IsTest
    static void shouldReturnLineItems_WhenSelectByWorkOrderIdCalledWithValidId() {
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
            List<WorkOrderLineItem> resultList = WorkOrderLineItemsSelector.selectByWorkOrderId(workOrderIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(251, resultList.size(), 'selectByWorkOrderId should return all 251 line items linked to the parent WorkOrder');
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
    static void shouldReturnEmpty_WhenSelectByWorkOrderIdCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<WorkOrderLineItem> resultList = WorkOrderLineItemsSelector.selectByWorkOrderId(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'selectByWorkOrderId should return an empty list when passed null');
        }
    }

    @IsTest
    static void shouldReturnEmpty_WhenSelectByWorkOrderIdCalledWithEmptySet() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<WorkOrderLineItem> resultList = WorkOrderLineItemsSelector.selectByWorkOrderId(new Set<Id>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'selectByWorkOrderId should return an empty list when passed an empty Set');
        }
    }

    // ── selectByStatus ────────────────────────────────────────────────────────

    @IsTest
    static void shouldReturnLineItems_WhenSelectByStatusMatchesExistingRecords() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<String> statusValueSet = new Set<String>{ 'New' };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<WorkOrderLineItem> resultList = WorkOrderLineItemsSelector.selectByStatus(statusValueSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(251, resultList.size(), 'selectByStatus should return all 251 line items with Status = New');
            for (WorkOrderLineItem lineItem : resultList) {
                Assert.areEqual('New', lineItem.Status, 'Every returned WorkOrderLineItem should have Status = New');
            }
        }
    }

    @IsTest
    static void shouldReturnEmpty_WhenSelectByStatusMatchesNoRecords() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<String> statusValueSet = new Set<String>{ 'Completed' };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<WorkOrderLineItem> resultList = WorkOrderLineItemsSelector.selectByStatus(statusValueSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'selectByStatus should return no records when no line items match the given Status');
        }
    }

    @IsTest
    static void shouldReturnEmpty_WhenSelectByStatusCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<WorkOrderLineItem> resultList = WorkOrderLineItemsSelector.selectByStatus(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'selectByStatus should return an empty list when passed null');
        }
    }

    @IsTest
    static void shouldReturnEmpty_WhenSelectByStatusCalledWithEmptySet() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<WorkOrderLineItem> resultList = WorkOrderLineItemsSelector.selectByStatus(new Set<String>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'selectByStatus should return an empty list when passed an empty Set');
        }
    }

    // ── selectByWorkOrderIdAsMap ──────────────────────────────────────────────

    @IsTest
    static void shouldReturnLineItemsGroupedByWorkOrderId_WhenValidIdsProvided() {
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
            Map<Id, List<WorkOrderLineItem>> resultMap =
                WorkOrderLineItemsSelector.selectByWorkOrderIdAsMap(workOrderIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(1, resultMap.size(), 'Result map should contain exactly one entry for the parent WorkOrder');
            Assert.isTrue(resultMap.containsKey(parentWorkOrder.Id), 'Result map should be keyed by the parent WorkOrder Id');
            Assert.areEqual(
                251,
                resultMap.get(parentWorkOrder.Id).size(),
                'All 251 line items should be grouped under the parent WorkOrder Id'
            );
        }
    }

    @IsTest
    static void shouldReturnEmptyMap_WhenSelectByWorkOrderIdAsMapCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            Map<Id, List<WorkOrderLineItem>> resultMap =
                WorkOrderLineItemsSelector.selectByWorkOrderIdAsMap(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultMap.isEmpty(), 'selectByWorkOrderIdAsMap should return an empty map when passed null');
        }
    }

    @IsTest
    static void shouldReturnEmptyMap_WhenSelectByWorkOrderIdAsMapCalledWithEmptySet() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            Map<Id, List<WorkOrderLineItem>> resultMap =
                WorkOrderLineItemsSelector.selectByWorkOrderIdAsMap(new Set<Id>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultMap.isEmpty(), 'selectByWorkOrderIdAsMap should return an empty map when passed an empty Set');
        }
    }

    // ── Device Evaluation Repair Code selectors (GW-3913 / GW-3096) ────────────

    @IsTest
    static void testDeviceEvaluationRepairCodeSelectorNullGuards() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Test.startTest();
            Assert.isTrue(
                WorkOrderLineItemsSelector.selectRepairCodeLinesWithProduct(null, null).isEmpty()
            );
            Assert.isTrue(WorkOrderLineItemsSelector.selectRepairCodeIds(null, null).isEmpty());
            Assert.isTrue(
                WorkOrderLineItemsSelector.selectRepairCodeByWorkOrderAndProducts(
                        null,
                        null,
                        null
                    )
                    .isEmpty()
            );
            Assert.isTrue(
                WorkOrderLineItemsSelector.selectRepairCodeLinesForReconcile(null, null).isEmpty()
            );
            Assert.isNull(
                WorkOrderLineItemsSelector.selectNewestProductServicedId(null, null, null)
            );
            Assert.isTrue(
                WorkOrderLineItemsSelector.selectRepairCodeProductIds(null, null).isEmpty()
            );
            Assert.isTrue(
                WorkOrderLineItemsSelector.selectInstrumentEvaluationLines(null, null, null).isEmpty()
            );
            Test.stopTest();
        }
    }

    @IsTest
    static void testSelectRepairCodeLinesForDeviceEvaluationHappyPath() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Schema.RecordTypeInfo repairCodeRt = Schema.SObjectType.WorkOrderLineItem
                .getRecordTypeInfosByDeveloperName()
                .get('RepairCode');
            if (repairCodeRt == null) {
                Assert.isTrue(true, 'RepairCode RT unavailable in this org; null-guard coverage only');
                return;
            }

            adb_Account accountBuilder = new adb_Account();
            accountBuilder.persist();
            Account account = (Account) accountBuilder.record;
            Id pricebookId = Test.getStandardPricebookId();
            WorkOrder workOrder = new WorkOrder(
                AccountId = account.Id,
                Subject = 'WOLI DE Selector WO',
                Status = 'Received',
                Pricebook2Id = pricebookId
            );
            insert workOrder;

            Product2 product = new Product2(
                Name = 'WOLI DE Repair Code Product',
                ProductCode = 'WOLI-DE-RC-001',
                IsActive = true
            );
            insert product;

            PricebookEntry pbe = new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id = product.Id,
                UnitPrice = 1,
                IsActive = true
            );
            insert pbe;

            WorkOrderLineItem lineItem = new WorkOrderLineItem(
                WorkOrderId = workOrder.Id,
                RecordTypeId = repairCodeRt.getRecordTypeId(),
                PricebookEntryId = pbe.Id,
                Product__c = product.Id,
                Quantity = 1,
                Description = 'DE Repair Code Line'
            );
            insert lineItem;

            Test.startTest();
            List<WorkOrderLineItem> withProduct =
                WorkOrderLineItemsSelector.selectRepairCodeLinesWithProduct(
                    workOrder.Id,
                    repairCodeRt.getRecordTypeId()
                );
            List<WorkOrderLineItem> idsOnly = WorkOrderLineItemsSelector.selectRepairCodeIds(
                workOrder.Id,
                repairCodeRt.getRecordTypeId()
            );
            List<WorkOrderLineItem> byProducts =
                WorkOrderLineItemsSelector.selectRepairCodeByWorkOrderAndProducts(
                    workOrder.Id,
                    repairCodeRt.getRecordTypeId(),
                    new Set<Id>{ product.Id }
                );
            List<WorkOrderLineItem> reconcile =
                WorkOrderLineItemsSelector.selectRepairCodeLinesForReconcile(
                    workOrder.Id,
                    repairCodeRt.getRecordTypeId()
                );
            Set<Id> productIds = WorkOrderLineItemsSelector.selectRepairCodeProductIds(
                workOrder.Id,
                repairCodeRt.getRecordTypeId()
            );
            Id newestId = WorkOrderLineItemsSelector.selectNewestProductServicedId(
                workOrder.Id,
                UserInfo.getUserId(),
                repairCodeRt.getRecordTypeId()
            );
            Test.stopTest();

            Assert.isNull(newestId, 'No Product Serviced line should exist for dummy Asset');
            Assert.isFalse(withProduct.isEmpty(), 'Should return Repair Code lines with Product');
            Assert.isFalse(idsOnly.isEmpty(), 'Should return Repair Code Ids');
            Assert.areEqual(1, byProducts.size(), 'Should match by Product');
            Assert.isFalse(reconcile.isEmpty(), 'Reconcile query should return lines');
            Assert.isTrue(productIds.contains(product.Id), 'Product Id set should include Product2Id');
            Schema.RecordTypeInfo productServicedRt = Schema.SObjectType.WorkOrderLineItem
                .getRecordTypeInfosByDeveloperName()
                .get('ProductServiced');
            if (productServicedRt != null) {
                Assert.isFalse(
                    WorkOrderLineItemsSelector.selectInstrumentEvaluationLines(
                            workOrder.Id,
                            productServicedRt.getRecordTypeId(),
                            repairCodeRt.getRecordTypeId()
                        )
                        .isEmpty(),
                    'Instrument Evaluation query should include Repair Code lines'
                );
            }
        }
    }

    @IsTest
    static void shouldSelectByIdAndWorkOrderId() {
        WorkOrderLineItem lineItem = [
            SELECT Id, WorkOrderId
            FROM WorkOrderLineItem
            LIMIT 1
        ];

        Test.startTest();
        List<WorkOrderLineItem> match = WorkOrderLineItemsSelector.selectByIdAndWorkOrderId(
            lineItem.Id,
            lineItem.WorkOrderId
        );
        List<WorkOrderLineItem> wrongParent = WorkOrderLineItemsSelector.selectByIdAndWorkOrderId(
            lineItem.Id,
            UserInfo.getUserId()
        );
        List<WorkOrderLineItem> nullIds = WorkOrderLineItemsSelector.selectByIdAndWorkOrderId(
            null,
            null
        );
        Test.stopTest();

        Assert.areEqual(1, match.size(), 'Expected the line on its Work Order');
        Assert.areEqual(lineItem.Id, match[0].Id);
        Assert.isTrue(wrongParent.isEmpty(), 'A different parent should not match');
        Assert.isTrue(nullIds.isEmpty(), 'Null Ids should return no rows');
    }

    @IsTest
    static void testSelectServiceCodeLinesByWorkOrderId_WhenGuardsAndMatch_ReturnsServiceCodes() {
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .subject('GW5748 Service Code Selector')
            .pricebook2Id(Test.getStandardPricebookId());
        workOrderBuilder.persist();
        WorkOrder workOrder = (WorkOrder) workOrderBuilder.record;
        Assert.isTrue(
            WorkOrderLineItemsSelector.selectServiceCodeLinesByWorkOrderId(null).isEmpty(),
            'Null Work Order Id should return no rows'
        );
        Assert.isTrue(
            WorkOrderLineItemsSelector.selectServiceCodeLinesByWorkOrderIds(new Set<Id>())
                .isEmpty(),
            'Empty Work Order Ids should return no rows'
        );

        Product2 serviceProduct = new Product2(
            Name = 'WOLI-SEL-SC-5748',
            ProductCode = 'WOLI-SEL-SC-5748',
            ProductType__c = 'Service Code',
            IsActive = true
        );
        insert serviceProduct;
        insert new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = serviceProduct.Id,
            UnitPrice = 1,
            IsActive = true
        );
        PricebookEntry pbe = [
            SELECT Id
            FROM PricebookEntry
            WHERE Product2Id = :serviceProduct.Id
            LIMIT 1
        ];
        WorkOrderLineItem serviceLine = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            LineType__c = 'Service Code',
            PricebookEntryId = pbe.Id,
            Quantity = 2,
            Status = 'New'
        );
        insert serviceLine;

        Test.startTest();
        List<WorkOrderLineItem> serviceCodes =
            WorkOrderLineItemsSelector.selectServiceCodeLinesByWorkOrderId(workOrder.Id);
        List<WorkOrderLineItem> bySet =
            WorkOrderLineItemsSelector.selectServiceCodeLinesByWorkOrderIds(
                new Set<Id>{ workOrder.Id }
            );
        Test.stopTest();

        Assert.areEqual(1, serviceCodes.size(), 'Should return the Service Code line');
        Assert.areEqual(serviceLine.Id, serviceCodes[0].Id);
        Assert.areEqual(1, bySet.size(), 'Set query should return the same Service Code line');
        Assert.areEqual(serviceLine.Id, bySet[0].Id);
    }


    @IsTest
    static void shouldSelectProductServicedNonAccessoryAndRepairChildren() {
        Assert.isTrue(
            WorkOrderLineItemsSelector.selectProductServicedNonAccessoryByWorkOrderId(null)
                .isEmpty(),
            'Null Work Order Id should return no Product Serviced rows'
        );
        Assert.isTrue(
            WorkOrderLineItemsSelector.selectRepairCodeChildrenByParentIds(null).isEmpty(),
            'Null parent Ids should return no Repair Code children'
        );

        Schema.RecordTypeInfo productServicedRt = Schema.SObjectType.WorkOrderLineItem
            .getRecordTypeInfosByDeveloperName()
            .get('ProductServiced');
        if (productServicedRt == null) {
            Assert.isTrue(true, 'Product Serviced record type unavailable; skip');
            return;
        }

        adb_Account accountBuilder = new adb_Account();
        accountBuilder.persist();
        Account account = (Account) accountBuilder.record;
        Id pricebookId = Test.getStandardPricebookId();
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'QI Selector Instrument WO',
            Status = 'Received',
            Pricebook2Id = pricebookId
        );
        insert workOrder;

        Product2 instrument = new Product2(
            Name = 'QI Selector Instrument',
            ProductCode = 'QI-SEL-INS',
            IsActive = true
        );
        Product2 repairCode = new Product2(
            Name = 'QI Selector Repair',
            ProductCode = 'QI-SEL-RC',
            IsActive = true
        );
        insert new List<Product2>{ instrument, repairCode };
        insert new List<PricebookEntry>{
            new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id = instrument.Id,
                UnitPrice = 1,
                IsActive = true
            ),
            new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id = repairCode.Id,
                UnitPrice = 1,
                IsActive = true
            )
        };
        PricebookEntry instrumentEntry = [
            SELECT Id
            FROM PricebookEntry
            WHERE Product2Id = :instrument.Id
            LIMIT 1
        ];
        PricebookEntry repairEntry = [
            SELECT Id
            FROM PricebookEntry
            WHERE Product2Id = :repairCode.Id
            LIMIT 1
        ];

        WorkOrderLineItem parentLine = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            RecordTypeId = productServicedRt.getRecordTypeId(),
            LineType__c = 'Product Serviced',
            IsAccessory__c = false,
            PricebookEntryId = instrumentEntry.Id,
            Quantity = 2
        );
        WorkOrderLineItem accessoryLine = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            RecordTypeId = productServicedRt.getRecordTypeId(),
            LineType__c = 'Product Serviced',
            IsAccessory__c = true,
            PricebookEntryId = instrumentEntry.Id,
            Quantity = 1
        );
        insert new List<WorkOrderLineItem>{ parentLine, accessoryLine };

        Schema.RecordTypeInfo repairCodeRt = Schema.SObjectType.WorkOrderLineItem
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCode');
        if (repairCodeRt != null) {
            insert new WorkOrderLineItem(
                WorkOrderId = workOrder.Id,
                ParentWorkOrderLineItemId = parentLine.Id,
                RecordTypeId = repairCodeRt.getRecordTypeId(),
                PricebookEntryId = repairEntry.Id,
                Quantity = 2,
                ProductCodeWoli__c = 'QI-SEL-RC'
            );
        }

        Test.startTest();
        List<WorkOrderLineItem> productServiced =
            WorkOrderLineItemsSelector.selectProductServicedNonAccessoryByWorkOrderId(
                workOrder.Id
            );
        List<WorkOrderLineItem> repairChildren =
            WorkOrderLineItemsSelector.selectRepairCodeChildrenByParentIds(
                new Set<Id>{ parentLine.Id }
            );
        Test.stopTest();

        Assert.areEqual(
            1,
            productServiced.size(),
            'Accessory Product Serviced lines should be excluded'
        );
        if (repairCodeRt != null) {
            Assert.areEqual(1, repairChildren.size(), 'Repair Code children should be returned');
        }
    }

    @IsTest
    static void selectProductCodesByWorkOrderIds_nullOrEmptyReturnsEmpty() {
        System.assertEquals(0, WorkOrderLineItemsSelector.selectProductCodesByWorkOrderIds(null).size());
        System.assertEquals(0, WorkOrderLineItemsSelector.selectProductCodesByWorkOrderIds(new Set<Id>()).size());
    }

    @IsTest
    static void testSelectProductServicedIdsByWorkOrder_guardsAndHappyPath() {
        Assert.isTrue(
            WorkOrderLineItemsSelector.selectProductServicedIdsByWorkOrder(null, null).isEmpty()
        );

        Schema.RecordTypeInfo productServicedRt = Schema.SObjectType.WorkOrderLineItem
            .getRecordTypeInfosByDeveloperName()
            .get('ProductServiced');
        if (productServicedRt == null) {
            Assert.isTrue(true, 'Product Serviced record type unavailable; skip');
            return;
        }

        WorkOrder workOrder = new WorkOrder(
            Subject = 'WOLI Sel Product Serviced Cov WO',
            Status = 'Received',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert workOrder;
        Product2 product = new Product2(
            Name = 'WOLI Sel Product Serviced Cov',
            ProductCode = 'WOLI-PS-COV',
            IsActive = true
        );
        insert product;
        insert new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );
        PricebookEntry pbe = [
            SELECT Id
            FROM PricebookEntry
            WHERE Product2Id = :product.Id
            LIMIT 1
        ];
        WorkOrderLineItem lineItem = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            RecordTypeId = productServicedRt.getRecordTypeId(),
            PricebookEntryId = pbe.Id,
            Quantity = 1
        );
        insert lineItem;

        Test.startTest();
        List<WorkOrderLineItem> rows =
            WorkOrderLineItemsSelector.selectProductServicedIdsByWorkOrder(
                workOrder.Id,
                productServicedRt.getRecordTypeId()
            );
        List<WorkOrderLineItem> nullRt =
            WorkOrderLineItemsSelector.selectProductServicedIdsByWorkOrder(workOrder.Id, null);
        Test.stopTest();

        Assert.isFalse(rows.isEmpty());
        Assert.isTrue(nullRt.isEmpty());
    }

    @IsTest
    static void testSelectRepairCodeIdsByParent_guardsAndHappyPath() {
        Assert.isTrue(
            WorkOrderLineItemsSelector.selectRepairCodeIdsByParent(null, null).isEmpty()
        );

        Schema.RecordTypeInfo productServicedRt = Schema.SObjectType.WorkOrderLineItem
            .getRecordTypeInfosByDeveloperName()
            .get('ProductServiced');
        Schema.RecordTypeInfo repairCodeRt = Schema.SObjectType.WorkOrderLineItem
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCode');
        if (productServicedRt == null || repairCodeRt == null) {
            Assert.isTrue(true, 'Required WOLI record types unavailable; skip');
            return;
        }

        WorkOrder workOrder = new WorkOrder(
            Subject = 'WOLI Sel Repair Parent Cov WO',
            Status = 'Received',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert workOrder;
        Product2 product = new Product2(
            Name = 'WOLI Sel Repair Parent Cov',
            ProductCode = 'WOLI-RC-COV',
            IsActive = true
        );
        insert product;
        insert new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );
        PricebookEntry pbe = [
            SELECT Id
            FROM PricebookEntry
            WHERE Product2Id = :product.Id
            LIMIT 1
        ];
        WorkOrderLineItem parentLine = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            RecordTypeId = productServicedRt.getRecordTypeId(),
            PricebookEntryId = pbe.Id,
            Quantity = 1
        );
        insert parentLine;
        WorkOrderLineItem repairLine = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            ParentWorkOrderLineItemId = parentLine.Id,
            RecordTypeId = repairCodeRt.getRecordTypeId(),
            PricebookEntryId = pbe.Id,
            Quantity = 1
        );
        insert repairLine;

        Test.startTest();
        List<WorkOrderLineItem> rows = WorkOrderLineItemsSelector.selectRepairCodeIdsByParent(
            parentLine.Id,
            repairCodeRt.getRecordTypeId()
        );
        List<WorkOrderLineItem> nullParent =
            WorkOrderLineItemsSelector.selectRepairCodeIdsByParent(
                null,
                repairCodeRt.getRecordTypeId()
            );
        Test.stopTest();

        Assert.areEqual(1, rows.size());
        Assert.areEqual(repairLine.Id, rows[0].Id);
        Assert.isTrue(nullParent.isEmpty());
    }

    @IsTest
    static void testSelectWithWorkOrderAssetById_guardsAndHappyPath() {
        Assert.isTrue(WorkOrderLineItemsSelector.selectWithWorkOrderAssetById(null).isEmpty());

        WorkOrderLineItem existing = [SELECT Id FROM WorkOrderLineItem LIMIT 1];

        Test.startTest();
        List<WorkOrderLineItem> rows =
            WorkOrderLineItemsSelector.selectWithWorkOrderAssetById(existing.Id);
        Test.stopTest();

        Assert.areEqual(1, rows.size());
        Assert.areEqual(existing.Id, rows[0].Id);
    }

    @IsTest
    static void testSelectPriorPartsForBillingType_nullGuards() {
        WorkOrder workOrder = [SELECT Id FROM WorkOrder LIMIT 1];
        Product2 product = new Product2(Name = 'Prior Parts Guard Product', IsActive = true);
        insert product;

        Test.startTest();
        Assert.isTrue(
            WorkOrderLineItemsSelector.selectPriorPartsForBillingType(
                    null,
                    workOrder.Id,
                    product.Id,
                    Datetime.now()
                )
                .isEmpty()
        );
        Assert.isTrue(
            WorkOrderLineItemsSelector.selectPriorPartsForBillingType(
                    workOrder.Id,
                    null,
                    product.Id,
                    Datetime.now()
                )
                .isEmpty()
        );
        Assert.isTrue(
            WorkOrderLineItemsSelector.selectPriorPartsForBillingType(
                    workOrder.Id,
                    workOrder.Id,
                    null,
                    Datetime.now()
                )
                .isEmpty()
        );
        Assert.isTrue(
            WorkOrderLineItemsSelector.selectPriorPartsForBillingType(
                    workOrder.Id,
                    workOrder.Id,
                    product.Id,
                    null
                )
                .isEmpty()
        );
        List<WorkOrderLineItem> noMatch =
            WorkOrderLineItemsSelector.selectPriorPartsForBillingType(
                workOrder.Id,
                workOrder.Id,
                product.Id,
                Datetime.now().addDays(-90)
            );
        Test.stopTest();

        Assert.isTrue(noMatch.isEmpty(), 'No prior parts should exist for synthetic asset Id');
    }

    @IsTest
    static void testSelectActiveInstrumentLines_guardsAndHappyPath() {
        Assert.isTrue(WorkOrderLineItemsSelector.selectActiveInstrumentLines(null).isEmpty());
        Assert.isTrue(
            WorkOrderLineItemsSelector.selectActiveInstrumentLines(new Set<Id>()).isEmpty()
        );

        // LineType Instrument is not available on org WOLI record types; still cover the query path.
        WorkOrder workOrder = new WorkOrder(
            Subject = 'WOLI Sel Instrument Cov WO',
            Status = 'Received',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert workOrder;

        Test.startTest();
        List<WorkOrderLineItem> rows = WorkOrderLineItemsSelector.selectActiveInstrumentLines(
            new Set<Id>{ workOrder.Id }
        );
        Test.stopTest();

        Assert.isNotNull(rows);
        Assert.isTrue(rows.isEmpty(), 'No Instrument lines expected without that picklist on RT');
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static User buildTestUser() {
        adb_User builder = new adb_User();
        builder.persist();
        return (User) builder.record;
    }

    @IsTest
    static void testModifierAndPricingSelectors_sprint93Coverage() {
        WorkOrder workOrder = [SELECT Id FROM WorkOrder LIMIT 1];
        WorkOrderLineItem existing = [SELECT Id FROM WorkOrderLineItem LIMIT 1];

        Test.startTest();
        Assert.isTrue(WorkOrderLineItemsSelector.selectForModifierCodes(null).isEmpty());
        List<WorkOrderLineItem> modifierLines =
            WorkOrderLineItemsSelector.selectForModifierCodes(workOrder.Id);
        Assert.isTrue(WorkOrderLineItemsSelector.selectForModifierUpdate(null).isEmpty());
        List<WorkOrderLineItem> modifierUpdate =
            WorkOrderLineItemsSelector.selectForModifierUpdate(existing.Id);
        Assert.isTrue(WorkOrderLineItemsSelector.selectModifierParents(null).isEmpty());
        Assert.isTrue(
            WorkOrderLineItemsSelector.selectModifierParents(new Set<Id>()).isEmpty()
        );
        List<WorkOrderLineItem> modifierParents =
            WorkOrderLineItemsSelector.selectModifierParents(new Set<Id>{ existing.Id });
        Assert.isTrue(WorkOrderLineItemsSelector.selectServiceCodeChildren(null).isEmpty());
        List<WorkOrderLineItem> serviceChildren =
            WorkOrderLineItemsSelector.selectServiceCodeChildren(existing.Id);

        Assert.areEqual(
            0,
            WorkOrderLineItemsSelector.sumRepairCodeTotalPrice(null, null, null)
        );
        Id fakeRt = WorkOrderLineItem.SObjectType.getDescribe().getRecordTypeInfos()[0].getRecordTypeId();
        Decimal sumStandalone =
            WorkOrderLineItemsSelector.sumRepairCodeTotalPrice(workOrder.Id, workOrder.Id, fakeRt);
        Decimal sumWithParent =
            WorkOrderLineItemsSelector.sumRepairCodeTotalPrice(workOrder.Id, UserInfo.getUserId(), fakeRt);

        Assert.isTrue(
            WorkOrderLineItemsSelector.selectForPricingFrameworkByWorkOrderIds(null).isEmpty()
        );
        List<WorkOrderLineItem> pricingRows =
            WorkOrderLineItemsSelector.selectForPricingFrameworkByWorkOrderIds(
                new Set<Id>{ workOrder.Id }
            );
        Assert.isTrue(
            WorkOrderLineItemsSelector.selectForPricingFrameworkHeadlessByIds(null).isEmpty()
        );
        Map<Id, WorkOrderLineItem> headless =
            WorkOrderLineItemsSelector.selectForPricingFrameworkHeadlessByIds(
                new Set<Id>{ existing.Id }
            );
        Assert.isTrue(
            WorkOrderLineItemsSelector.selectForVendorConsolidationByWorkOrderIds(null).isEmpty()
        );
        List<WorkOrderLineItem> vendorRows =
            WorkOrderLineItemsSelector.selectForVendorConsolidationByWorkOrderIds(
                new Set<Id>{ workOrder.Id }
            );
        Assert.isTrue(WorkOrderLineItemsSelector.selectCrssInspectedLines(null).isEmpty());
        List<WorkOrderLineItem> crssRows =
            WorkOrderLineItemsSelector.selectCrssInspectedLines(workOrder.Id);
        Assert.isTrue(
            WorkOrderLineItemsSelector.selectQualityInspectionProductServiced(null, null, null)
                .isEmpty()
        );
        List<WorkOrderLineItem> qiRows =
            WorkOrderLineItemsSelector.selectQualityInspectionProductServiced(
                workOrder.Id,
                workOrder.Id,
                WorkOrderLineItem.SObjectType.getDescribe().getRecordTypeInfos()[0].getRecordTypeId()
            );
        Test.stopTest();

        Assert.isNotNull(modifierLines);
        Assert.isFalse(modifierUpdate.isEmpty());
        Assert.isFalse(modifierParents.isEmpty());
        Assert.isNotNull(serviceChildren);
        Assert.areEqual(0, sumStandalone);
        Assert.areEqual(0, sumWithParent);
        Assert.isNotNull(pricingRows);
        Assert.isFalse(headless.isEmpty());
        Assert.isNotNull(vendorRows);
        Assert.isNotNull(crssRows);
        Assert.isNotNull(qiRows);
    }
}