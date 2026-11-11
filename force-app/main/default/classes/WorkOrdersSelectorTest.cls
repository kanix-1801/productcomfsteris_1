/**
 * @description Test class for WorkOrdersSelector.
 *              Covers all query methods, null/empty guard clauses, and bulk behaviour.
 *              Includes GW-2891 Divide Instruments selector tests.
 */
@IsTest
private class WorkOrdersSelectorTest {

    @TestSetup
    static void setupTestData() {
        adb_Account account = new adb_Account();
        adb_WorkOrder lastWorkOrderBuilder;
        for (Integer i = 0; i < 251; i++) {
            lastWorkOrderBuilder = new adb_WorkOrder()
                .subject('Test Work Order ' + i)
                .account(account);
        }
        lastWorkOrderBuilder.persist();
    }

    /**
     * @description GW-5687 - The selector can be constructed for SoqlQueryBuilder queries.
     */
    @IsTest
    static void testConstructor_createsWorkOrderSelector() {
        WorkOrdersSelector selector = new WorkOrdersSelector();
        Assert.isNotNull(selector, 'The Work Order selector should construct');
    }

    // ── selectById ────────────────────────────────────────────────────────────

    @IsTest
    static void shouldReturnWorkOrders_WhenSelectByIdCalledWithValidIds() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> workOrderIdSet = new Map<Id, WorkOrder>([SELECT Id FROM WorkOrder]).keySet();
            Assert.areEqual(251, workOrderIdSet.size(), 'Test setup should have inserted 251 WorkOrders');

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<WorkOrder> resultList = WorkOrdersSelector.selectById(workOrderIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(251, resultList.size(), 'selectById should return all 251 WorkOrders matching the provided Ids');
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
            List<WorkOrder> resultList = WorkOrdersSelector.selectById(null);
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
            List<WorkOrder> resultList = WorkOrdersSelector.selectById(new Set<Id>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'selectById should return an empty list when passed an empty Set');
        }
    }

    @IsTest
    static void shouldReturnWorkOrders_WhenSelectByIdsForAllowedUnitCalled() {
        User testUser = new User(id = UserInfo.getUserId());
        System.runAs(testUser) {
            WorkOrder workOrder = [SELECT Id FROM WorkOrder LIMIT 1];

            Test.startTest();
            List<WorkOrder> nullResult = WorkOrdersSelector.selectByIdsForAllowedUnit(null);
            List<WorkOrder> emptyResult = WorkOrdersSelector.selectByIdsForAllowedUnit(new Set<Id>());
            List<WorkOrder> results =
                WorkOrdersSelector.selectByIdsForAllowedUnit(new Set<Id>{ workOrder.Id });
            Test.stopTest();

            Assert.areEqual(0, nullResult.size(), 'Null Id set should return empty');
            Assert.areEqual(0, emptyResult.size(), 'Empty Id set should return empty');
            Assert.areEqual(1, results.size(), 'Should return the requested Work Order');
            Assert.areEqual(workOrder.Id, results[0].Id);
        }
    }

    @IsTest
    static void shouldReturnWorkOrders_WhenSelectByIdsForRateListCalled() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            WorkOrder workOrder = [SELECT Id FROM WorkOrder LIMIT 1];

            Test.startTest();
            List<WorkOrder> nullResult = WorkOrdersSelector.selectByIdsForRateList(null);
            List<WorkOrder> emptyResult = WorkOrdersSelector.selectByIdsForRateList(new Set<Id>());
            List<WorkOrder> results =
                WorkOrdersSelector.selectByIdsForRateList(new Set<Id>{ workOrder.Id });
            Test.stopTest();

            Assert.areEqual(0, nullResult.size(), 'Null Id set should return empty');
            Assert.areEqual(0, emptyResult.size(), 'Empty Id set should return empty');
            Assert.areEqual(1, results.size(), 'Should return the requested Work Order');
            Assert.areEqual(workOrder.Id, results[0].Id);
        }
    }

    // ── selectByStatus ────────────────────────────────────────────────────────

    @IsTest
    static void shouldReturnWorkOrders_WhenSelectByStatusMatchesExistingRecords() {
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
            List<WorkOrder> resultList = WorkOrdersSelector.selectByStatus(statusValueSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(251, resultList.size(), 'selectByStatus should return all 251 WorkOrders with Status = New');
            for (WorkOrder workOrder : resultList) {
                Assert.areEqual('New', workOrder.Status, 'Every returned WorkOrder should have Status = New');
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
            List<WorkOrder> resultList = WorkOrdersSelector.selectByStatus(statusValueSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'selectByStatus should return no records when no WorkOrders match the given Status');
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
            List<WorkOrder> resultList = WorkOrdersSelector.selectByStatus(null);
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
            List<WorkOrder> resultList = WorkOrdersSelector.selectByStatus(new Set<String>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'selectByStatus should return an empty list when passed an empty Set');
        }
    }

    // ── selectByAccountId ─────────────────────────────────────────────────────

    @IsTest
    static void shouldReturnWorkOrders_WhenSelectByAccountIdMatchesExistingRecords() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Account testAccount = [SELECT Id FROM Account LIMIT 1];
            Set<Id> accountIdSet = new Set<Id>{ testAccount.Id };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<WorkOrder> resultList = WorkOrdersSelector.selectByAccountId(accountIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(251, resultList.size(), 'selectByAccountId should return all 251 WorkOrders linked to the test Account');
            for (WorkOrder workOrder : resultList) {
                Assert.areEqual(testAccount.Id, workOrder.AccountId, 'Every returned WorkOrder should be linked to the test Account');
            }
        }
    }

    @IsTest
    static void shouldReturnEmpty_WhenSelectByAccountIdCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<WorkOrder> resultList = WorkOrdersSelector.selectByAccountId(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'selectByAccountId should return an empty list when passed null');
        }
    }

    @IsTest
    static void shouldReturnEmpty_WhenSelectByAccountIdCalledWithEmptySet() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<WorkOrder> resultList = WorkOrdersSelector.selectByAccountId(new Set<Id>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'selectByAccountId should return an empty list when passed an empty Set');
        }
    }

    // ── selectByIdWithLineItems ───────────────────────────────────────────────

    @IsTest
    static void shouldReturnWorkOrdersWithLineItems_WhenValidIdsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            WorkOrder parentWorkOrder = [SELECT Id FROM WorkOrder LIMIT 1];
            adb_WorkOrderLineItem lineItemBuilder = new adb_WorkOrderLineItem()
                .description('Subquery Line Item');
            lineItemBuilder.set(WorkOrderLineItem.WorkOrderId, parentWorkOrder.Id);
            lineItemBuilder.persist();

            Set<Id> workOrderIdSet = new Map<Id, WorkOrder>([SELECT Id FROM WorkOrder]).keySet();
            Assert.areEqual(251, workOrderIdSet.size(), 'Test setup should have inserted 251 WorkOrders');

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<WorkOrder> resultList = WorkOrdersSelector.selectByIdWithLineItems(workOrderIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(251, resultList.size(), 'selectByIdWithLineItems should return all 251 WorkOrders');
            for (WorkOrder workOrder : resultList) {
                if (workOrder.Id == parentWorkOrder.Id) {
                    Assert.areEqual(
                        1,
                        workOrder.getSObjects('WorkOrderLineItems').size(),
                        'The WorkOrder with a line item should carry its WorkOrderLineItems subquery result'
                    );
                }
            }
        }
    }

    @IsTest
    static void shouldReturnEmpty_WhenSelectByIdWithLineItemsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<WorkOrder> resultList = WorkOrdersSelector.selectByIdWithLineItems(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'selectByIdWithLineItems should return an empty list when passed null');
        }
    }

    @IsTest
    static void shouldReturnEmpty_WhenSelectByIdWithLineItemsCalledWithEmptySet() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<WorkOrder> resultList = WorkOrdersSelector.selectByIdWithLineItems(new Set<Id>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'selectByIdWithLineItems should return an empty list when passed an empty Set');
        }
    }

    // ── selectWorkOrdersWithOperatingHours / selectOperatingHoursHolidays (GW-3164) ─

    /**
     * @description GW-3164 - Verifies selectWorkOrdersWithOperatingHours returns Operating Hours and timezone.
     */
    @IsTest
    static void testSelectWorkOrdersWithOperatingHours_WhenValidIdsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            WorkOrder workOrder = createShipDateWorkOrder(
                Datetime.newInstanceGmt(2026, 8, 3, 13, 0, 0),
                5
            );

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<WorkOrder> resultList = WorkOrdersSelector.selectWorkOrdersWithOperatingHours(
                new Set<Id>{ workOrder.Id }
            );
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(1, resultList.size(), 'Should return the Work Order');
            Assert.isNotNull(
                resultList[0].RepairCenter__r.OperatingHours__c,
                'Repair Center Operating Hours should be queried'
            );
            Assert.areEqual(
                'America/New_York',
                resultList[0].RepairCenter__r.OperatingHours__r.TimeZone,
                'Timezone should be America/New_York'
            );
        }
    }

    /**
     * @description GW-3164 - Verifies selectOperatingHoursHolidays returns linked Holiday ActivityDate.
     */
    @IsTest
    static void testSelectOperatingHoursHolidays_WhenHolidayLinked() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Date holidayDate = Date.newInstance(2026, 8, 5);
            adb_OperatingHours operatingHours = new adb_OperatingHours();
            adb_Holiday holiday = new adb_Holiday().activityDate(holidayDate);
            new adb_OperatingHoursHoliday()
                .operatingHours(operatingHours)
                .holiday(holiday)
                .persist();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<OperatingHoursHoliday> resultList = WorkOrdersSelector.selectOperatingHoursHolidays(
                new Set<Id>{ operatingHours.id }
            );
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(1, resultList.size(), 'Should return the OperatingHoursHoliday');
            Assert.areEqual(
                holidayDate,
                resultList[0].Holiday.ActivityDate,
                'Holiday ActivityDate should match'
            );
        }
    }

    /**
     * @description GW-2891 / GW-3891 / GW-3816 / GW-3913 - Smoke coverage for additive selector queries,
     *              including Divide Instruments selectForDivideInstrumentsById.
     */
    @IsTest
    static void shouldCoverAdditiveSelectorQueries() {
        WorkOrder workOrder = [
            SELECT Id, WorkOrderNumber, AccountId
            FROM WorkOrder
            LIMIT 1
        ];
        Id dummyId = UserInfo.getUserId();

        Test.startTest();
        List<WorkOrder> preferences = WorkOrdersSelector.selectByIdForCustomerPreferences(
            new Set<Id>{ workOrder.Id }
        );
        List<WorkOrder> repairHistoryContext = WorkOrdersSelector.selectByIdForRepairHistory(
            new Set<Id>{ workOrder.Id }
        );
        List<WorkOrder> historyByAsset = WorkOrdersSelector.selectRepairHistoryByAsset(
            dummyId,
            workOrder.Id,
            new Set<Id>{ workOrder.Id }
        );
        Assert.isTrue(WorkOrdersSelector.selectForDeviceEvaluationByNumber(null).isEmpty());
        List<WorkOrder> byNumber = WorkOrdersSelector.selectForDeviceEvaluationByNumber(
            workOrder.WorkOrderNumber
        );
        Assert.isTrue(WorkOrdersSelector.selectForDeviceEvaluationById(null).isEmpty());
        List<WorkOrder> byId = WorkOrdersSelector.selectForDeviceEvaluationById(workOrder.Id);
        Assert.isTrue(WorkOrdersSelector.selectSubStatusById(null).isEmpty());
        List<WorkOrder> subStatusRows = WorkOrdersSelector.selectSubStatusById(workOrder.Id);
        Assert.areEqual(1, subStatusRows.size(), 'Expected Sub Status row for existing Work Order');
        Assert.isTrue(
            WorkOrdersSelector.selectRepairHistoryForDeviceEvaluation(null, null, null, null)
                .isEmpty()
        );
        List<WorkOrder> deHistory = WorkOrdersSelector.selectRepairHistoryForDeviceEvaluation(
            workOrder.AccountId,
            dummyId,
            workOrder.Id,
            new Set<Id>{ workOrder.Id }
        );
        Assert.isNull(WorkOrdersSelector.selectByIdOrNumber(null));
        Assert.isNull(WorkOrdersSelector.selectByIdOrNumber('not-an-id'));
        WorkOrder byIdOrNumber = WorkOrdersSelector.selectByIdOrNumber(String.valueOf(workOrder.Id));
        WorkOrder byNumberScan = WorkOrdersSelector.selectByIdOrNumber(workOrder.WorkOrderNumber);
        Assert.isTrue(WorkOrdersSelector.selectForDivideInstrumentsById(null).isEmpty());
        List<WorkOrder> divide = WorkOrdersSelector.selectForDivideInstrumentsById(workOrder.Id);
        List<WorkOrder> withHours = WorkOrdersSelector.selectWorkOrdersWithOperatingHours(
            new Set<Id>{ workOrder.Id }
        );
        List<OperatingHoursHoliday> holidays = WorkOrdersSelector.selectOperatingHoursHolidays(
            new Set<Id>{ dummyId }
        );
        Assert.isNull(WorkOrdersSelector.selectForWarrantyRepairEvaluationById(null));
        WorkOrder wreWorkOrder = WorkOrdersSelector.selectForWarrantyRepairEvaluationById(workOrder.Id);
        Id devicesRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterDevices')
            ?.getRecordTypeId();
        Assert.isNull(
            WorkOrdersSelector.selectMostRecentRepairCenterDeviceByAsset(null, workOrder.Id, devicesRecordTypeId)
        );
        WorkOrder priorDeviceWo = WorkOrdersSelector.selectMostRecentRepairCenterDeviceByAsset(
            dummyId,
            workOrder.Id,
            devicesRecordTypeId
        );
        Id instrumentsRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterInstruments')
            ?.getRecordTypeId();
        Assert.isNull(
            WorkOrdersSelector.selectMostRecentRepairCenterWorkOrderByAsset(
                null,
                workOrder.Id,
                instrumentsRecordTypeId
            )
        );
        WorkOrder priorInstrumentsWo = WorkOrdersSelector.selectMostRecentRepairCenterWorkOrderByAsset(
            dummyId,
            workOrder.Id,
            instrumentsRecordTypeId
        );
        Test.stopTest();

        Assert.isFalse(preferences.isEmpty());
        Assert.isFalse(repairHistoryContext.isEmpty());
        Assert.isNotNull(historyByAsset);
        Assert.isFalse(byNumber.isEmpty());
        Assert.isFalse(byId.isEmpty());
        String recordTypeName =
            byId[0].RecordType == null ? null : byId[0].RecordType.DeveloperName;
        Assert.isTrue(
            recordTypeName == null || String.isNotBlank(recordTypeName),
            'GW-3400 evaluation field list queries RecordType.DeveloperName'
        );
        Assert.isTrue(
            byId[0].getPopulatedFieldsAsMap().containsKey('Subject'),
            'GW-3400 evaluation field list queries Subject'
        );
        Assert.isNotNull(deHistory);
        Assert.areEqual(workOrder.Id, byIdOrNumber.Id);
        Assert.areEqual(workOrder.Id, byNumberScan.Id);
        Assert.isFalse(divide.isEmpty());
        Assert.isFalse(withHours.isEmpty());
        Assert.isNotNull(holidays);
        Assert.isNotNull(wreWorkOrder);
        Assert.isNull(priorDeviceWo);
    }


    // ΓפאΓפא selectByIdForCustomerPreferences (GW-2860) ΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפא
    @IsTest
    static void testSelectByIdForCustomerPreferencesReturnsAssetProductLineFields() {
        // Setup
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            Account account = [SELECT Id FROM Account LIMIT 1];
            adb_Product2 assetProductBuilder = new adb_Product2()
                .name('WO CP Selector Product')
                .productCode('WO-CP-SEL-001')
                .productType('Service Asset')
                .productLine('FLEXIBLE SCOPE')
                .isActive(true);
            adb_Asset assetBuilder = new adb_Asset()
                .name('WO CP Selector Asset')
                .serialNumber('SN-WO-CP-SEL-001')
                .product(assetProductBuilder);
            assetBuilder.set(Asset.AccountId, account.Id);
            assetBuilder.persist();

            WorkOrder workOrder = [SELECT Id FROM WorkOrder LIMIT 1];
            workOrder.AccountId = account.Id;
            workOrder.AssetId = assetBuilder.id;
            update workOrder;

            // Given / When
            Test.startTest();
            List<WorkOrder> results = WorkOrdersSelector.selectByIdForCustomerPreferences(
                new Set<Id>{ workOrder.Id }
            );
            Test.stopTest();

            // Then
            Assert.areEqual(1, results.size(), 'Should return the requested Work Order');
            Assert.areEqual(account.Id, results[0].AccountId, 'AccountId should be populated');
            Assert.areEqual(assetBuilder.id, results[0].AssetId, 'AssetId should be populated');
            Assert.isNotNull(results[0].WorkOrderNumber, 'WorkOrderNumber should be queried');
            Assert.areEqual(
                'FLEXIBLE SCOPE',
                results[0].Asset.Product2.ProductLine__c,
                'Asset Product2 ProductLine should be queried for GW-2860'
            );
        }
    }

    @IsTest
    static void testSelectByIdForCustomerPreferencesNullAndEmptyGuards() {
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            Test.startTest();
            List<WorkOrder> nullResult = WorkOrdersSelector.selectByIdForCustomerPreferences(null);
            List<WorkOrder> emptyResult = WorkOrdersSelector.selectByIdForCustomerPreferences(new Set<Id>());
            Test.stopTest();

            Assert.isTrue(nullResult.isEmpty(), 'Null ids should return empty list');
            Assert.isTrue(emptyResult.isEmpty(), 'Empty ids should return empty list');
        }
    }

    // ΓפאΓפא selectByIdForRepairHistory / selectRepairHistoryByAsset (GW-1295) ΓפאΓפאΓפאΓפאΓפא
    @IsTest
    static void testSelectByIdForRepairHistoryReturnsAssetFields() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            WorkOrder workOrder = [SELECT Id, AssetId FROM WorkOrder LIMIT 1];

            Test.startTest();
            List<WorkOrder> results = WorkOrdersSelector.selectByIdForRepairHistory(
                new Set<Id>{ workOrder.Id }
            );
            Test.stopTest();

            Assert.areEqual(1, results.size(), 'Should return the requested Work Order');
            Assert.isNotNull(results[0].WorkOrderNumber, 'WorkOrderNumber should be queried');
        }
    }

    @IsTest
    static void testSelectByIdForRepairHistoryNullAndEmptyGuards() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Assert.isTrue(
                WorkOrdersSelector.selectByIdForRepairHistory(null).isEmpty(),
                'Null ids should return empty list'
            );
            Assert.isTrue(
                WorkOrdersSelector.selectByIdForRepairHistory(new Set<Id>()).isEmpty(),
                'Empty ids should return empty list'
            );
        }
    }

    @IsTest
    static void testSelectRepairHistoryByAssetReturnsShippedRows() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Account account = [SELECT Id FROM Account LIMIT 1];
            adb_Asset assetBuilder = new adb_Asset()
                .name('Selector RH Asset')
                .serialNumber('SN-SEL-RH-001');
            assetBuilder.set(Asset.AccountId, account.Id);

            adb_WorkOrder currentWoBuilder = new adb_WorkOrder()
                .status('Received')
                .subject('Selector RH Current')
                .setRecordType('RepairCenterDevices')
                .asset(assetBuilder);
            currentWoBuilder.set(WorkOrder.AccountId, account.Id);

            adb_WorkOrder shippedBuilder = new adb_WorkOrder()
                .status('Closed')
                .subject('Selector RH Shipped')
                .setRecordType('RepairCenterDevices')
                .actualShipDate(Date.today().addDays(-5))
                .evaluator(UserInfo.getUserId())
                .asset(assetBuilder);
            shippedBuilder.set(WorkOrder.AccountId, account.Id);
            shippedBuilder.persist();

            Id devicesRtId = Schema.SObjectType.WorkOrder
                .getRecordTypeInfosByDeveloperName()
                .get('RepairCenterDevices')
                .getRecordTypeId();

            Test.startTest();
            List<WorkOrder> results = WorkOrdersSelector.selectRepairHistoryByAsset(
                assetBuilder.id,
                currentWoBuilder.id,
                new Set<Id>{ devicesRtId }
            );
            Test.stopTest();

            Assert.areEqual(1, results.size(), 'Should return prior shipped Work Order only');
            Assert.areEqual(shippedBuilder.id, results[0].Id);
            Assert.isNotNull(results[0].ActualShipDate__c);
            Assert.areEqual(UserInfo.getUserId(), results[0].Evaluator__c);
        }
    }

    @IsTest
    static void testSelectRepairHistoryByAssetNullGuards() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Id devicesRtId = Schema.SObjectType.WorkOrder
                .getRecordTypeInfosByDeveloperName()
                .get('RepairCenterDevices')
                .getRecordTypeId();

            Test.startTest();
            List<WorkOrder> nullAsset = WorkOrdersSelector.selectRepairHistoryByAsset(
                null,
                null,
                new Set<Id>{ devicesRtId }
            );
            List<WorkOrder> emptyRt = WorkOrdersSelector.selectRepairHistoryByAsset(
                UserInfo.getUserId(),
                null,
                new Set<Id>()
            );
            Test.stopTest();

            Assert.isTrue(nullAsset.isEmpty(), 'Null asset should return empty');
            Assert.isTrue(emptyRt.isEmpty(), 'Empty record types should return empty');
        }
    }

    // ΓפאΓפא selectRepairHistoryForDeviceEvaluation (GW-3913 / GW-3096) ΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפא
    @IsTest
    static void testSelectRepairHistoryForDeviceEvaluationReturnsSameAccountRows() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Account account = [SELECT Id FROM Account LIMIT 1];
            adb_Account otherAccountBuilder = new adb_Account();
            adb_Asset assetBuilder = new adb_Asset()
                .name('Selector DE RH Asset')
                .serialNumber('SN-SEL-DE-RH-001');
            assetBuilder.set(Asset.AccountId, account.Id);

            adb_WorkOrder currentWoBuilder = new adb_WorkOrder()
                .status('Received')
                .subject('Selector DE RH Current')
                .setRecordType('RepairCenterDevices')
                .asset(assetBuilder);
            currentWoBuilder.set(WorkOrder.AccountId, account.Id);

            adb_WorkOrder sameAccountShippedBuilder = new adb_WorkOrder()
                .status('Closed')
                .subject('Selector DE RH Same Account')
                .setRecordType('RepairCenterDevices')
                .actualShipDate(Date.today().addDays(-5))
                .evaluator(UserInfo.getUserId())
                .asset(assetBuilder);
            sameAccountShippedBuilder.set(WorkOrder.AccountId, account.Id);
            sameAccountShippedBuilder.set(
                WorkOrder.CompletedTimestamp__c,
                Datetime.now().addDays(-5)
            );

            adb_WorkOrder otherAccountShippedBuilder = new adb_WorkOrder()
                .status('Closed')
                .subject('Selector DE RH Other Account')
                .setRecordType('RepairCenterDevices')
                .actualShipDate(Date.today().addDays(-2))
                .account(otherAccountBuilder)
                .asset(assetBuilder);
            otherAccountShippedBuilder.persist();

            Id devicesRtId = Schema.SObjectType.WorkOrder
                .getRecordTypeInfosByDeveloperName()
                .get('RepairCenterDevices')
                .getRecordTypeId();

            Test.startTest();
            List<WorkOrder> results = WorkOrdersSelector.selectRepairHistoryForDeviceEvaluation(
                account.Id,
                assetBuilder.id,
                currentWoBuilder.id,
                new Set<Id>{ devicesRtId }
            );
            Test.stopTest();

            Assert.areEqual(1, results.size(), 'Should return same-account history only');
            Assert.areEqual(sameAccountShippedBuilder.id, results[0].Id);
            Assert.isNotNull(results[0].ActualShipDate__c);
            Assert.isNotNull(results[0].CompletedTimestamp__c);
            Assert.areEqual(UserInfo.getUserId(), results[0].Evaluator__c);
        }
    }

    @IsTest
    static void testSelectRepairHistoryForDeviceEvaluationNullGuards() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Id devicesRtId = Schema.SObjectType.WorkOrder
                .getRecordTypeInfosByDeveloperName()
                .get('RepairCenterDevices')
                .getRecordTypeId();
            Account account = [SELECT Id FROM Account LIMIT 1];

            Test.startTest();
            List<WorkOrder> nullAccount = WorkOrdersSelector.selectRepairHistoryForDeviceEvaluation(
                null,
                UserInfo.getUserId(),
                null,
                new Set<Id>{ devicesRtId }
            );
            List<WorkOrder> nullAsset = WorkOrdersSelector.selectRepairHistoryForDeviceEvaluation(
                account.Id,
                null,
                null,
                new Set<Id>{ devicesRtId }
            );
            List<WorkOrder> emptyRt = WorkOrdersSelector.selectRepairHistoryForDeviceEvaluation(
                account.Id,
                UserInfo.getUserId(),
                null,
                new Set<Id>()
            );
            Test.stopTest();

            Assert.isTrue(nullAccount.isEmpty(), 'Null account should return empty');
            Assert.isTrue(nullAsset.isEmpty(), 'Null asset should return empty');
            Assert.isTrue(emptyRt.isEmpty(), 'Empty record types should return empty');
        }
    }

    // ΓפאΓפא selectForDeviceEvaluationByNumber / ById (GW-3913 / GW-3096) ΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפאΓפא
    @IsTest
    static void testSelectForDeviceEvaluationByNumberAndId() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            WorkOrder existing = [
                SELECT Id, WorkOrderNumber
                FROM WorkOrder
                LIMIT 1
            ];

            Test.startTest();
            List<WorkOrder> byNumber = WorkOrdersSelector.selectForDeviceEvaluationByNumber(
                existing.WorkOrderNumber
            );
            List<WorkOrder> byId = WorkOrdersSelector.selectForDeviceEvaluationById(existing.Id);
            List<WorkOrder> blankNumber = WorkOrdersSelector.selectForDeviceEvaluationByNumber('  ');
            List<WorkOrder> nullId = WorkOrdersSelector.selectForDeviceEvaluationById(null);
            List<WorkOrder> missing = WorkOrdersSelector.selectForDeviceEvaluationByNumber(
                'WO-DOES-NOT-EXIST-DE'
            );
            Test.stopTest();

            Assert.areEqual(1, byNumber.size(), 'Should find WO by number');
            Assert.areEqual(existing.Id, byNumber[0].Id);
            Assert.isNotNull(byNumber[0].Status, 'DE field list should include Status');
            Assert.areEqual(1, byId.size(), 'Should find WO by Id');
            Assert.areEqual(existing.Id, byId[0].Id);
            Assert.isTrue(blankNumber.isEmpty(), 'Blank number should return empty');
            Assert.isTrue(nullId.isEmpty(), 'Null Id should return empty');
            Assert.isTrue(missing.isEmpty(), 'Unknown number should return empty');
        }
    }

    /**
     * @description GW-3816 / GW-2891 / GW-5783 - Verifies selectByIdOrNumber resolves by Id, Number,
     *              and blank/missing inputs, and queries Rack__c.
     */
    @IsTest
    static void testSelectByIdOrNumber_WhenIdOrNumberProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            WorkOrder existing = [
                SELECT Id, WorkOrderNumber
                FROM WorkOrder
                LIMIT 1
            ];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            WorkOrder byId = WorkOrdersSelector.selectByIdOrNumber(existing.Id);
            WorkOrder byNumber = WorkOrdersSelector.selectByIdOrNumber(existing.WorkOrderNumber);
            WorkOrder byNumberWithWhitespace = WorkOrdersSelector.selectByIdOrNumber(
                '  ' + existing.WorkOrderNumber + '  '
            );
            WorkOrder blankInput = WorkOrdersSelector.selectByIdOrNumber('  ');
            WorkOrder missing = WorkOrdersSelector.selectByIdOrNumber('WO-DOES-NOT-EXIST-3816');
            WorkOrder idShapedMissing = WorkOrdersSelector.selectByIdOrNumber(UserInfo.getUserId());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(existing.Id, byId.Id, 'Should find Work Order by Id');
            Assert.areEqual(existing.Id, byNumber.Id, 'Should find Work Order by Number');
            Assert.isNull(
                byNumberWithWhitespace,
                'Selector matches exact Work Order Number; callers trim scanned input'
            );
            Assert.isNull(blankInput, 'Blank input should return null');
            Assert.isNull(missing, 'Unknown number should return null');
            Assert.isNull(idShapedMissing, 'Id-shaped input that is not a Work Order should return null');
            Assert.areEqual(
                byId.Rack__c,
                (Id) byId.get('Rack__c'),
                'selectByIdOrNumber must query Rack__c'
            );
        }
    }

    /**
     * @description GW-2891 - Verifies parent Work Order select by Id, and null returns empty.
     */
    @IsTest
    static void testSelectForDivideInstrumentsById_WhenValidAndNull() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            WorkOrder existing = [SELECT Id FROM WorkOrder LIMIT 1];

            Test.startTest();
            List<WorkOrder> found = WorkOrdersSelector.selectForDivideInstrumentsById(existing.Id);
            List<WorkOrder> empty = WorkOrdersSelector.selectForDivideInstrumentsById(null);
            Test.stopTest();

            Assert.areEqual(1, found.size(), 'Should return the scanned Work Order');
            Assert.isTrue(empty.isEmpty(), 'Null Id should return empty');
        }
    }

    /**
     * @description GW-2891 - Verifies child Work Orders for Divide reconcile are returned by parent Id.
     */
    @IsTest
    static void testSelectChildWorkOrdersForDivideInstruments_WhenParentHasChildren() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            adb_WorkOrder parentBuilder = new adb_WorkOrder();
            parentBuilder.persist();
            WorkOrder parent = (WorkOrder) parentBuilder.record;

            adb_WorkOrder childBuilder = new adb_WorkOrder().parentWorkOrder(parentBuilder);
            childBuilder.set(WorkOrder.RepairCategory__c, 'Stainless');
            childBuilder.set(WorkOrder.QuantityReceived__c, 2);
            childBuilder.set(WorkOrder.TurnTime__c, 3);
            childBuilder.persist();

            Test.startTest();
            List<WorkOrder> children =
                WorkOrdersSelector.selectChildWorkOrdersForDivideInstruments(parent.Id);
            List<WorkOrder> empty =
                WorkOrdersSelector.selectChildWorkOrdersForDivideInstruments(null);
            Test.stopTest();

            Assert.areEqual(1, children.size(), 'Should return one child Work Order');
            Assert.areEqual('Stainless', children[0].RepairCategory__c);
            Assert.isTrue(empty.isEmpty(), 'Null parent Id should return empty');
        }
    }

    /**
     * @description GW-5492 - Child statuses used to align a receiving parent Work Order.
     */
    @IsTest
    static void testSelectChildStatusesForReceiving_returnsChildStatus() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            adb_WorkOrder parentBuilder = new adb_WorkOrder();
            parentBuilder.persist();
            WorkOrder parent = (WorkOrder) parentBuilder.record;

            adb_WorkOrder childBuilder = new adb_WorkOrder().parentWorkOrder(parentBuilder);
            childBuilder.persist();
            WorkOrder child = (WorkOrder) childBuilder.record;
            WorkOrder stored = [SELECT Status FROM WorkOrder WHERE Id = :child.Id];

            Test.startTest();
            List<WorkOrder> children = WorkOrdersSelector.selectChildStatusesForReceiving(
                parent.Id
            );
            List<WorkOrder> empty = WorkOrdersSelector.selectChildStatusesForReceiving(null);
            Test.stopTest();

            Assert.areEqual(1, children.size());
            Assert.areEqual(child.Id, children[0].Id);
            Assert.areEqual(stored.Status, children[0].Status);
            Assert.isTrue(empty.isEmpty());
        }
    }

    /**
     * @description GW-5231 - Verifies coordinator scan lookup by Id and Number includes assignment fields.
     */
    @IsTest
    static void testSelectForCoordinatorActionsByIdOrNumber_WhenIdOrNumberProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            WorkOrder existing = [
                SELECT Id, WorkOrderNumber, Status
                FROM WorkOrder
                LIMIT 1
            ];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            WorkOrder byId = WorkOrdersSelector.selectForCoordinatorActionsByIdOrNumber(
                String.valueOf(existing.Id)
            );
            WorkOrder byNumber = WorkOrdersSelector.selectForCoordinatorActionsByIdOrNumber(
                existing.WorkOrderNumber
            );
            WorkOrder blankInput = WorkOrdersSelector.selectForCoordinatorActionsByIdOrNumber('  ');
            WorkOrder missing = WorkOrdersSelector.selectForCoordinatorActionsByIdOrNumber('99999999');
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(existing.Id, byId.Id, 'Id lookup should resolve the Work Order');
            Assert.areEqual(existing.Id, byNumber.Id, 'Number lookup should resolve the Work Order');
            Assert.areEqual(existing.Status, byId.Status, 'Status should be included');
            Assert.isNull(blankInput, 'Blank scan should return null');
            Assert.isNull(missing, 'Unknown scan should return null');
        }
    }

    /**
     * @description GW-5231 - Verifies coordinator assignment lookup by Id, including a null guard.
     */
    @IsTest
    static void testSelectForCoordinatorActionsById_WhenIdProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            WorkOrder existing = [
                SELECT Id, Status
                FROM WorkOrder
                LIMIT 1
            ];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            WorkOrder result = WorkOrdersSelector.selectForCoordinatorActionsById(existing.Id);
            WorkOrder blankById = WorkOrdersSelector.selectForCoordinatorActionsById(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(existing.Id, result.Id, 'The Work Order should be returned');
            Assert.areEqual(existing.Status, result.Status, 'Status should be included');
            Assert.isNull(blankById, 'Null Id should return null');
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static User buildTestUser() {
        adb_User builder = new adb_User();
        builder.persist();
        return (User) builder.record;
    }

    /**
     * @description GW-3164 - Builds a Repair Center WO with Operating Hours for ship-date tests.
     */
    private static WorkOrder createShipDateWorkOrder(Datetime readyAt, Decimal turnTime) {
        adb_OperatingHours operatingHours = new adb_OperatingHours().timeZone('America/New_York');
        adb_Location repairCenter = new adb_Location().operatingHours(operatingHours);
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .turnTime(turnTime)
            .dateReadyforRepair(readyAt)
            .repairCenter(repairCenter);
        workOrderBuilder.persist();
        return (WorkOrder) workOrderBuilder.record;
    }

    /**
     * @description GW-5333 - Verifies Approve/Reject Quote selector guards and field set.
     */
    @IsTest
    static void testSelectForApproveRejectQuoteByIds_WhenIdsProvided() {
        WorkOrder workOrder = [SELECT Id FROM WorkOrder LIMIT 1];

        Test.startTest();
        List<WorkOrder> selected =
            WorkOrdersSelector.selectForApproveRejectQuoteByIds(new Set<Id>{ workOrder.Id });
        Test.stopTest();

        Assert.areEqual(1, selected.size());
        Assert.isNotNull(selected[0].WorkOrderNumber);
        Assert.isTrue(WorkOrdersSelector.selectForApproveRejectQuoteByIds(new Set<Id>()).isEmpty());
    }

    /**
     * @description GW-3400 - Instrument Evaluation lookup by Work Order Number returns every match.
     */
    @IsTest
    static void testSelectForInstrumentEvaluationByNumber_WhenNumberProvided() {
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            WorkOrder existing = [SELECT Id, WorkOrderNumber FROM WorkOrder LIMIT 1];

            Test.startTest();
            List<WorkOrder> byNumber =
                WorkOrdersSelector.selectForInstrumentEvaluationByNumber(existing.WorkOrderNumber);
            List<WorkOrder> blankInput =
                WorkOrdersSelector.selectForInstrumentEvaluationByNumber('   ');
            Test.stopTest();

            Assert.areEqual(1, byNumber.size(), 'Number lookup should resolve the Work Order');
            Assert.areEqual(existing.Id, byNumber[0].Id);
            Assert.isTrue(blankInput.isEmpty(), 'Blank number should return empty');
        }
    }

    /**
     * @description GW-4637 - Bin tag print selector returns merge fields and guards null/empty input.
     */
    @IsTest
    static void testSelectByIdForBinTagPrint_WhenIdsProvided() {
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            WorkOrder existing = [SELECT Id FROM WorkOrder LIMIT 1];

            Test.startTest();
            List<WorkOrder> selected =
                WorkOrdersSelector.selectByIdForBinTagPrint(new Set<Id>{ existing.Id });
            List<WorkOrder> nullInput = WorkOrdersSelector.selectByIdForBinTagPrint(null);
            List<WorkOrder> emptyInput = WorkOrdersSelector.selectByIdForBinTagPrint(new Set<Id>());
            Test.stopTest();

            Assert.areEqual(1, selected.size(), 'Should return the requested Work Order');
            Assert.isNotNull(selected[0].WorkOrderNumber, 'Work Order Number should be selected');
            Assert.isTrue(nullInput.isEmpty(), 'Null Id set should return empty');
            Assert.isTrue(emptyInput.isEmpty(), 'Empty Id set should return empty');
        }
    }

    /**
     * @description GW-3880 - Outside Vendor consolidation list filters by Repair Center, Sub Status,
     *              record type, and excludes Work Orders that already have a Vendor Return Order.
     */
    @IsTest
    static void testSelectOutsideVendorForConsolidation_WhenMatchingWorkOrders() {
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            Id otherRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
                .get('RepairCenterOther')
                ?.getRecordTypeId();
            if (otherRecordTypeId == null) {
                Assert.isTrue(true, 'RepairCenterOther record type unavailable; skip');
                return;
            }

            adb_Account vendorBuilder = new adb_Account()
                .name('WOSel Consolidation Vendor')
                .systemId('LEG-WOSEL-VND')
                .sourceSystemId('TEST-ORACLE-WOSEL-VND')
                .orgIds('82');
            adb_Location repairCenterBuilder = new adb_Location()
                .name('WOSel Consolidation RC')
                .locationType('Repair Center');
            adb_WorkOrder vendorWorkOrderBuilder = new adb_WorkOrder()
                .subject('WOSel Outside Vendor WO')
                .status('Received')
                .repairCenter(repairCenterBuilder);
            vendorWorkOrderBuilder.set(WorkOrder.SubStatus__c, 'Ship to Vendor');
            vendorWorkOrderBuilder.set(WorkOrder.RecordTypeId, otherRecordTypeId);
            vendorWorkOrderBuilder.setParent(WorkOrder.Vendor__c, vendorBuilder);
            vendorWorkOrderBuilder.persist();

            Test.startTest();
            List<WorkOrder> matches = WorkOrdersSelector.selectOutsideVendorForConsolidation(
                repairCenterBuilder.id,
                otherRecordTypeId,
                'Ship to Vendor'
            );
            List<WorkOrder> noRepairCenter = WorkOrdersSelector.selectOutsideVendorForConsolidation(
                null,
                otherRecordTypeId,
                'Ship to Vendor'
            );
            List<WorkOrder> noRecordType = WorkOrdersSelector.selectOutsideVendorForConsolidation(
                repairCenterBuilder.id,
                null,
                'Ship to Vendor'
            );
            Test.stopTest();

            Assert.areEqual(1, matches.size(), 'Should return the unconsolidated Vendor Work Order');
            Assert.areEqual(vendorWorkOrderBuilder.id, matches[0].Id);
            Assert.areEqual(vendorBuilder.id, matches[0].Vendor__c, 'Vendor should be selected');
            Assert.isTrue(noRepairCenter.isEmpty(), 'Null Repair Center should return empty');
            Assert.isTrue(noRecordType.isEmpty(), 'Null record type should return empty');
        }
    }

    /**
     * @description GW-3880 - Vendor consolidation complete selector returns vendor and address fields.
     */
    @IsTest
    static void testSelectForVendorConsolidationComplete_WhenIdsProvided() {
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            WorkOrder existing = [SELECT Id FROM WorkOrder LIMIT 1];

            Test.startTest();
            List<WorkOrder> selected =
                WorkOrdersSelector.selectForVendorConsolidationComplete(new Set<Id>{ existing.Id });
            List<WorkOrder> nullInput =
                WorkOrdersSelector.selectForVendorConsolidationComplete(null);
            List<WorkOrder> emptyInput =
                WorkOrdersSelector.selectForVendorConsolidationComplete(new Set<Id>());
            Test.stopTest();

            Assert.areEqual(1, selected.size(), 'Should return the requested Work Order');
            Assert.isNotNull(selected[0].WorkOrderNumber, 'Work Order Number should be selected');
            Assert.isTrue(nullInput.isEmpty(), 'Null Id set should return empty');
            Assert.isTrue(emptyInput.isEmpty(), 'Empty Id set should return empty');
        }
    }

    /**
     * @description GW-3880 - Vendor Return Order lookup resolves the linked Vendor Work Orders.
     */
    @IsTest
    static void testSelectByVendorReturnOrderIds_WhenReturnOrderLinked() {
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            adb_Account vendorBuilder = new adb_Account()
                .name('WOSel Vendor RO Account')
                .systemId('LEG-WOSEL-VRO')
                .sourceSystemId('TEST-ORACLE-WOSEL-VRO')
                .orgIds('82');
            adb_Location repairCenterBuilder = new adb_Location()
                .name('WOSel Vendor RO RC')
                .locationType('Repair Center');
            adb_ReturnOrder vendorReturnOrderBuilder = new adb_ReturnOrder()
                .account(vendorBuilder)
                .status('Submitted');
            vendorReturnOrderBuilder.setParent(ReturnOrder.DestinationLocationId, repairCenterBuilder);
            vendorReturnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
            vendorReturnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Serialized');
            vendorReturnOrderBuilder.persist();

            WorkOrder vendorWorkOrder = [SELECT Id FROM WorkOrder LIMIT 1];
            vendorWorkOrder.put('VendorReturnOrder__c', vendorReturnOrderBuilder.id);
            update vendorWorkOrder;

            Test.startTest();
            List<WorkOrder> selected = WorkOrdersSelector.selectByVendorReturnOrderIds(
                new Set<Id>{ vendorReturnOrderBuilder.id }
            );
            List<WorkOrder> nullInput = WorkOrdersSelector.selectByVendorReturnOrderIds(null);
            List<WorkOrder> emptyInput =
                WorkOrdersSelector.selectByVendorReturnOrderIds(new Set<Id>());
            Test.stopTest();

            Assert.areEqual(1, selected.size(), 'Should return the linked Vendor Work Order');
            Assert.areEqual(vendorReturnOrderBuilder.id, selected[0].VendorReturnOrder__c);
            Assert.isTrue(nullInput.isEmpty(), 'Null Id set should return empty');
            Assert.isTrue(emptyInput.isEmpty(), 'Empty Id set should return empty');
        }
    }

    /**
     * @description GW-3880 - Vendor FedEx shipment selector returns the vendor lookup fields.
     */
    @IsTest
    static void testSelectByIdForVendorFedExShipment_WhenIdsProvided() {
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            WorkOrder existing = [SELECT Id FROM WorkOrder LIMIT 1];

            Test.startTest();
            List<WorkOrder> selected =
                WorkOrdersSelector.selectByIdForVendorFedExShipment(new Set<Id>{ existing.Id });
            List<WorkOrder> nullInput = WorkOrdersSelector.selectByIdForVendorFedExShipment(null);
            List<WorkOrder> emptyInput =
                WorkOrdersSelector.selectByIdForVendorFedExShipment(new Set<Id>());
            Test.stopTest();

            Assert.areEqual(1, selected.size(), 'Should return the requested Work Order');
            Assert.isNotNull(selected[0].WorkOrderNumber, 'Work Order Number should be selected');
            Assert.isTrue(nullInput.isEmpty(), 'Null Id set should return empty');
            Assert.isTrue(emptyInput.isEmpty(), 'Empty Id set should return empty');
        }
    }

    /**
     * @description GW-4006 - Mod Request form email selector returns the contact email fields.
     */
    @IsTest
    static void testSelectByIdForModRequestFormEmail_WhenIdsProvided() {
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            WorkOrder existing = [SELECT Id FROM WorkOrder LIMIT 1];

            Test.startTest();
            List<WorkOrder> selected =
                WorkOrdersSelector.selectByIdForModRequestFormEmail(new Set<Id>{ existing.Id });
            List<WorkOrder> nullInput = WorkOrdersSelector.selectByIdForModRequestFormEmail(null);
            List<WorkOrder> emptyInput =
                WorkOrdersSelector.selectByIdForModRequestFormEmail(new Set<Id>());
            Test.stopTest();

            Assert.areEqual(1, selected.size(), 'Should return the requested Work Order');
            Assert.areEqual(existing.Id, selected[0].Id);
            Assert.isTrue(nullInput.isEmpty(), 'Null Id set should return empty');
            Assert.isTrue(emptyInput.isEmpty(), 'Empty Id set should return empty');
        }
    }

    /**
     * @description GW-5492 - Counts Work Orders linked to a Return Order via COUNT().
     */
    @IsTest
    static void testCountByReturnOrderId_WhenLinkedWorkOrdersExist() {
        User testUser = new User(Id = UserInfo.getUserId());
        adb_ReturnOrder returnOrderBuilder = new adb_ReturnOrder().status('Draft');
        returnOrderBuilder.persist();
        List<WorkOrder> workOrders = [
            SELECT Id, ReturnOrder__c
            FROM WorkOrder
            LIMIT 2
        ];
        Assert.areEqual(2, workOrders.size(), 'Setup should provide Work Orders');
        for (WorkOrder workOrder : workOrders) {
            workOrder.ReturnOrder__c = returnOrderBuilder.id;
        }
        update workOrders;

        System.runAs(testUser) {
            Test.startTest();
            Integer linkedCount =
                WorkOrdersSelector.countByReturnOrderId(returnOrderBuilder.id);
            Integer serviceCount =
                WorkOrdersService.countByReturnOrderId(returnOrderBuilder.id);
            Integer nullCount = WorkOrdersSelector.countByReturnOrderId(null);
            Test.stopTest();

            Assert.areEqual(2, linkedCount, 'Both linked Work Orders should count');
            Assert.areEqual(linkedCount, serviceCount, 'Service should match selector count');
            Assert.areEqual(0, nullCount, 'Null Return Order should return zero');
        }
    }

    /**
     * @description GW-5497 - Quality Inspection lookup resolves by Id and by Work Order Number,
     *              and returns null for blank or unknown input.
     */
    @IsTest
    static void testSelectForQualityInspection_WhenIdOrNumberProvided() {
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            WorkOrder existing = [SELECT Id, WorkOrderNumber FROM WorkOrder LIMIT 1];
            existing.ShipComplete__c = true;
            update existing;

            Test.startTest();
            WorkOrder byId = WorkOrdersSelector.selectForQualityInspection(
                String.valueOf(existing.Id)
            );
            WorkOrder byNumber =
                WorkOrdersSelector.selectForQualityInspection(existing.WorkOrderNumber);
            WorkOrder notAnId = WorkOrdersSelector.selectForQualityInspection('not-an-id');
            WorkOrder blankInput = WorkOrdersSelector.selectForQualityInspection('   ');
            Test.stopTest();

            Assert.areEqual(existing.Id, byId.Id, 'Id lookup should resolve the Work Order');
            Assert.areEqual(existing.Id, byNumber.Id, 'Number lookup should resolve the Work Order');
            Assert.isNotNull(byId.WorkOrderNumber, 'Work Order Number should be selected');
            Assert.isTrue(byId.ShipComplete__c, 'Quality Inspection query should select Ship Complete');
            Assert.isNull(notAnId, 'Unknown scan value should return null');
            Assert.isNull(blankInput, 'Blank scan should return null');
        }
    }

    @IsTest
    static void testSelectWorkOrderNumberById_returnsNumber() {
        WorkOrder existing = [SELECT Id, WorkOrderNumber FROM WorkOrder LIMIT 1];

        Test.startTest();
        WorkOrder found = WorkOrdersSelector.selectWorkOrderNumberById(existing.Id);
        WorkOrder missing = WorkOrdersSelector.selectWorkOrderNumberById(null);
        Test.stopTest();

        Assert.areEqual(existing.Id, found.Id, 'Lookup should return the Work Order');
        Assert.areEqual(existing.WorkOrderNumber, found.WorkOrderNumber);
        Assert.isNull(missing, 'Null Id should return null');
    }

    @IsTest
    static void selectAssetProductCodesByIds_nullOrEmptyReturnsEmpty() {
        System.assertEquals(0, WorkOrdersSelector.selectAssetProductCodesByIds(null).size());
        System.assertEquals(0, WorkOrdersSelector.selectAssetProductCodesByIds(new Set<Id>()).size());
    }

    @IsTest
    static void testSelectByIdForReceivingWoliCreate_happyPathAndNullGuard() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            WorkOrder existing = [SELECT Id FROM WorkOrder LIMIT 1];

            Test.startTest();
            List<WorkOrder> rows =
                WorkOrdersSelector.selectByIdForReceivingWoliCreate(existing.Id);
            List<WorkOrder> nullRows =
                WorkOrdersSelector.selectByIdForReceivingWoliCreate(null);
            Test.stopTest();

            Assert.areEqual(1, rows.size());
            Assert.areEqual(existing.Id, rows[0].Id);
            Assert.isTrue(nullRows.isEmpty());
        }
    }

    @IsTest
    static void testSelectAssetIdById_happyPathAndNullGuard() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            WorkOrder existing = [SELECT Id FROM WorkOrder LIMIT 1];

            Test.startTest();
            List<WorkOrder> rows = WorkOrdersSelector.selectAssetIdById(existing.Id);
            List<WorkOrder> nullRows = WorkOrdersSelector.selectAssetIdById(null);
            Test.stopTest();

            Assert.areEqual(1, rows.size());
            Assert.areEqual(existing.Id, rows[0].Id);
            Assert.isTrue(nullRows.isEmpty());
        }
    }

    @IsTest
    static void testSelectReceivingVendorWorkOrder_withRepairCenterOther() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Id otherRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
                .get('RepairCenterOther')
                ?.getRecordTypeId();
            if (otherRecordTypeId == null) {
                Assert.isTrue(true, 'RepairCenterOther record type unavailable; skip');
                return;
            }

            adb_Account vendorBuilder = new adb_Account()
                .name('WOSel Receiving Vendor')
                .systemId('LEGWORECVVND01')
                .sourceSystemId('TEST-ORACLE-WOSEL-RECV-VND')
                .orgIds('82');
            adb_Account accountBuilder = new adb_Account()
                .name('WOSel Receiving Customer')
                .systemId('LEGWORECVCST01')
                .sourceSystemId('TEST-ORACLE-WOSEL-RECV-CUST')
                .orgIds('82');
            adb_Location repairCenterBuilder = new adb_Location()
                .name('WOSel Receiving RC')
                .locationType('Repair Center');
            adb_ReturnOrder returnOrderBuilder = new adb_ReturnOrder()
                .account(accountBuilder)
                .status('Submitted');
            returnOrderBuilder.setParent(ReturnOrder.DestinationLocationId, repairCenterBuilder);
            returnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
            returnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Serialized');

            returnOrderBuilder.persist();
            vendorBuilder.persist();

            adb_WorkOrder vendorWorkOrderBuilder = new adb_WorkOrder()
                .subject('WOSel Receiving Vendor WO')
                .status('Received')
                .account(accountBuilder)
                .repairCenter(repairCenterBuilder);
            vendorWorkOrderBuilder.set(WorkOrder.RecordTypeId, otherRecordTypeId);
            vendorWorkOrderBuilder.setParent(WorkOrder.Vendor__c, vendorBuilder);
            vendorWorkOrderBuilder.persist();

            WorkOrder vendorWorkOrder = new WorkOrder(
                Id = vendorWorkOrderBuilder.id,
                ReturnOrder__c = returnOrderBuilder.id
            );
            update vendorWorkOrder;

            Test.startTest();
            WorkOrder matched = WorkOrdersSelector.selectReceivingVendorWorkOrder(
                returnOrderBuilder.id,
                vendorBuilder.id
            );
            WorkOrder nullReturnOrder =
                WorkOrdersSelector.selectReceivingVendorWorkOrder(null, vendorBuilder.id);
            WorkOrder nullVendor =
                WorkOrdersSelector.selectReceivingVendorWorkOrder(returnOrderBuilder.id, null);
            Test.stopTest();

            Assert.isNotNull(matched, 'Should find the RepairCenterOther vendor Work Order');
            Assert.areEqual(vendorWorkOrderBuilder.id, matched.Id);
            Assert.areEqual(vendorBuilder.id, matched.Vendor__c);
            Assert.isNull(nullReturnOrder);
            Assert.isNull(nullVendor);
        }
    }

    @IsTest
    static void testQuoteEmailAndModifierSelectors_sprint93Coverage() {
        WorkOrder workOrder = [
            SELECT Id, WorkOrderNumber
            FROM WorkOrder
            LIMIT 1
        ];

        Test.startTest();
        Assert.isNull(WorkOrdersSelector.selectForQuoteEmailReply(null));
        Assert.isNull(WorkOrdersSelector.selectForQuoteEmailReply('   '));
        WorkOrder byId = WorkOrdersSelector.selectForQuoteEmailReply(String.valueOf(workOrder.Id));
        WorkOrder byNumber =
            WorkOrdersSelector.selectForQuoteEmailReply(workOrder.WorkOrderNumber);
        Assert.isTrue(WorkOrdersSelector.selectShippedByAsset(null).isEmpty());
        List<WorkOrder> shipped = WorkOrdersSelector.selectShippedByAsset(workOrder.Id);
        Assert.isTrue(WorkOrdersSelector.selectActiveQuoteGrandTotalById(null).isEmpty());
        List<WorkOrder> quoteTotals =
            WorkOrdersSelector.selectActiveQuoteGrandTotalById(workOrder.Id);
        Assert.isTrue(WorkOrdersSelector.selectForModifierReference(null).isEmpty());
        List<WorkOrder> modifierRef =
            WorkOrdersSelector.selectForModifierReference(workOrder.Id);
        Assert.isTrue(WorkOrdersSelector.selectForCreateReturnOrderContext(null).isEmpty());
        List<WorkOrder> croContext =
            WorkOrdersSelector.selectForCreateReturnOrderContext(workOrder.Id);
        Test.stopTest();

        Assert.isNotNull(byId);
        Assert.areEqual(workOrder.Id, byId.Id);
        Assert.isNotNull(byNumber);
        Assert.isNotNull(shipped);
        Assert.isFalse(quoteTotals.isEmpty());
        Assert.isFalse(modifierRef.isEmpty());
        Assert.isNotNull(croContext);
    }
}