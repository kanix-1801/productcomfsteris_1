/**
 * @description Tests for WorkOrderRepairHistoryController (GW-1295).
 */
@IsTest
private class WorkOrderRepairHistoryControllerTest {
    private class ClientException extends Exception {
    }

    private class ThrowingRepairHistoryClient
        implements WorkOrderRepairHistoryController.IRepairHistoryClient {
        public List<WorkOrder> getWorkOrdersForRepairHistory(Set<Id> workOrderIds) {
            throw new ClientException('repair history service failed');
        }

        public List<WorkOrder> getRepairHistoryByAsset(
            Id assetId,
            Id excludedWorkOrderId
        ) {
            throw new ClientException('repair history service failed');
        }
    }

    @TestSetup
    static void setupData() {
        adb_Account accountBuilder = new adb_Account()
            .name('Repair History Controller Account')
            .systemId('LEG-RH-CTRL-001')
            .sourceSystemId('TEST-ORACLE-RH-CTRL-001')
            .orgIds('82');

        adb_Asset assetBuilder = new adb_Asset()
            .name('Repair History Asset')
            .account(accountBuilder)
            .serialNumber('SN-RH-001');

        new adb_WorkOrder()
            .account(accountBuilder)
            .asset(assetBuilder)
            .status('Received')
            .subject('RH Current With Asset')
            .setRecordType('RepairCenterDevices');
        new adb_WorkOrder()
            .account(accountBuilder)
            .asset(assetBuilder)
            .status('Closed')
            .subject('RH Prior Shipped')
            .setRecordType('RepairCenterDevices')
            .actualShipDate(Date.today().addDays(-10))
            .evaluator(UserInfo.getUserId());
        new adb_WorkOrder()
            .account(accountBuilder)
            .status('Received')
            .subject('RH Current No Asset')
            .setRecordType('RepairCenterDevices');
        new adb_WorkOrder()
            .account(accountBuilder)
            .asset(assetBuilder)
            .status('Closed')
            .subject('RH Prior No Evaluator')
            .setRecordType('RepairCenterDevices')
            .actualShipDate(Date.today().addDays(-20));

        accountBuilder.persist();
    }

    @IsTest
    static void testGetRepairHistoryForWorkOrderVisibleWithHistory() {
        // Setup
        WorkOrder currentWo = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'RH Current With Asset'
            LIMIT 1
        ];

        // Given / When
        Test.startTest();
        WorkOrderRepairHistoryController.HistoryListResult result =
            WorkOrderRepairHistoryController.getRepairHistoryForWorkOrder(currentWo.Id);
        Test.stopTest();

        // Then
        WorkOrder shipped = [SELECT Id FROM WorkOrder WHERE Subject = 'RH Prior Shipped' LIMIT 1];
        Assert.isTrue(result.isVisible, 'Should be visible when Asset is populated');
        Assert.isTrue(result.history.size() >= 1, 'Should return prior shipped Work Orders');
        Set<Id> historyIds = new Set<Id>();
        for (WorkOrderRepairHistoryController.HistoryRow row : result.history) {
            historyIds.add(row.workOrderId);
        }
        Assert.isTrue(historyIds.contains(shipped.Id));
        Assert.isNotNull(result.history[0].workOrderNumber);
        Assert.isNotNull(result.history[0].actualShipDate);
        Assert.isTrue(
            result.history[0].recordUrl.startsWith('/'),
            'Record URL should be a relative path'
        );
    }

    @IsTest
    static void testGetRepairHistoryForWorkOrderHiddenWithoutAsset() {
        WorkOrder noAssetWo = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'RH Current No Asset'
            LIMIT 1
        ];

        Test.startTest();
        WorkOrderRepairHistoryController.HistoryListResult result =
            WorkOrderRepairHistoryController.getRepairHistoryForWorkOrder(noAssetWo.Id);
        Test.stopTest();

        Assert.isFalse(result.isVisible, 'Should hide when Asset is blank');
        Assert.areEqual(0, result.history.size());
    }

    @IsTest
    static void testGetRepairHistoryForWorkOrderNullId() {
        WorkOrderRepairHistoryController.HistoryListResult result =
            WorkOrderRepairHistoryController.getRepairHistoryForWorkOrder(null);

        Assert.isFalse(result.isVisible);
        Assert.areEqual(0, result.history.size());
    }

    @IsTest
    static void testGetRepairHistoryForWorkOrderUnknownWorkOrderId() {
        String prefix = WorkOrder.SObjectType.getDescribe().getKeyPrefix();
        Id unknownId = (Id)(prefix + '000000000001');

        Test.startTest();
        WorkOrderRepairHistoryController.HistoryListResult result =
            WorkOrderRepairHistoryController.getRepairHistoryForWorkOrder(unknownId);
        Test.stopTest();

        Assert.isFalse(result.isVisible);
        Assert.areEqual(0, result.history.size());
    }

    @IsTest
    static void testGetRepairHistoryForWorkOrderVisibleEmptyHistory() {
        // Use a separate asset so prior shipped rows on the shared asset do not appear.
        Account account = [SELECT Id FROM Account LIMIT 1];
        adb_Account accountBuilder = new adb_Account();
        accountBuilder.record.Id = account.Id;
        adb_Asset emptyHistoryAsset = new adb_Asset()
            .name('Repair History Empty Asset')
            .account(accountBuilder)
            .serialNumber('SN-RH-EMPTY');
        new adb_WorkOrder()
            .account(accountBuilder)
            .asset(emptyHistoryAsset)
            .status('Received')
            .subject('RH Empty History Runtime')
            .setRecordType('RepairCenterDevices')
            .persist();

        WorkOrder emptyHistoryWo = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'RH Empty History Runtime'
            LIMIT 1
        ];

        Test.startTest();
        WorkOrderRepairHistoryController.HistoryListResult result =
            WorkOrderRepairHistoryController.getRepairHistoryForWorkOrder(emptyHistoryWo.Id);
        Test.stopTest();

        Assert.isTrue(result.isVisible, 'Should be visible with Asset even when history is empty');
        Assert.areEqual(0, result.history.size());
    }

    @IsTest
    static void testGetRepairHistoryForWorkOrderNoEvaluatorMapped() {
        WorkOrder currentWo = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'RH Current With Asset'
            LIMIT 1
        ];
        WorkOrder noEvaluator = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'RH Prior No Evaluator'
            LIMIT 1
        ];

        Test.startTest();
        WorkOrderRepairHistoryController.HistoryListResult result =
            WorkOrderRepairHistoryController.getRepairHistoryForWorkOrder(currentWo.Id);
        Test.stopTest();

        WorkOrderRepairHistoryController.HistoryRow matched;
        for (WorkOrderRepairHistoryController.HistoryRow row : result.history) {
            if (row.workOrderId == noEvaluator.Id) {
                matched = row;
                break;
            }
        }
        Assert.isNotNull(matched, 'No-evaluator history row should be returned');
        Assert.isNull(matched.evaluatorName, 'Evaluator name should be null when lookup blank');
    }

    @IsTest
    static void testGetRepairHistoryForWorkOrder_serviceThrows() {
        WorkOrder workOrder = [SELECT Id FROM WorkOrder LIMIT 1];
        WorkOrderRepairHistoryController.facadeOverride = new ThrowingRepairHistoryClient();
        try {
            Boolean threw = false;
            try {
                WorkOrderRepairHistoryController.getRepairHistoryForWorkOrder(workOrder.Id);
            } catch (AuraHandledException e) {
                threw = true;
                Assert.isTrue(
                    e.getMessage().contains('Unable to load Repair Order History'),
                    'Controller should return a user-facing error'
                );
            }
            Assert.isTrue(threw, 'Service failure should become AuraHandledException');
        } finally {
            WorkOrderRepairHistoryController.facadeOverride = null;
        }
    }
}