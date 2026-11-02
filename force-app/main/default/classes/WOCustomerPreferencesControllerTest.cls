/**
 * @description Tests for WorkOrderCustomerPreferencesController (GW-2860).
 * @author Uptima
 */
@IsTest
private class WOCustomerPreferencesControllerTest {
    private static final String PRODUCT_LINE = 'FLEXIBLE SCOPE';

    private class ClientException extends Exception {
    }

    private class FakeWorkOrdersClient
        implements WorkOrderCustomerPreferencesController.ICustomerPreferencesWorkOrdersClient {
        private Boolean shouldThrow;

        FakeWorkOrdersClient(Boolean shouldThrow) {
            this.shouldThrow = shouldThrow;
        }

        public List<WorkOrder> getWorkOrdersForCustomerPreferences(Set<Id> workOrderIds) {
            if (shouldThrow) {
                throw new ClientException('customer preferences service failed');
            }
            return new List<WorkOrder>{
                new WorkOrder(Id = workOrderIds.iterator().next())
            };
        }
    }

    @TestSetup
    static void setupData() {
        adb_Account accountBuilder = new adb_Account()
            .name('WO Customer Preferences Account')
            .systemId('LEG-WO-CP-1001')
            .sourceSystemId('TEST-ORACLE-WO-CP-001')
            .orgIds('82');

        new adb_CustomerPreference()
            .account(accountBuilder)
            .setRecordType('IMSCustomerPreference')
            .preferenceType('Photos required')
            .productLine(null)
            .startDate(Date.today().addDays(-1))
            .endDate(Date.today().addDays(30));

        adb_Product2 assetProduct = new adb_Product2()
            .name('WO CP Asset Product')
            .productCode('WO-CP-ASSET-001')
            .productType('Service Asset')
            .productLine(PRODUCT_LINE);
        adb_Asset assetBuilder = new adb_Asset()
            .name('WO CP Asset')
            .account(accountBuilder)
            .product(assetProduct)
            .serialNumber('SN-WO-CP-001');

        // Persist Account/Asset first. ParentWorkOrder self-lookup can scramble UOW
        // insert order and leave Asset.AccountId null in a single graph persist.
        accountBuilder.persist();

        adb_Account persistedAccount = new adb_Account();
        persistedAccount.record.Id = accountBuilder.Id;
        adb_Asset persistedAsset = new adb_Asset();
        persistedAsset.record.Id = assetBuilder.Id;

        adb_WorkOrder parentWorkOrder = new adb_WorkOrder()
            .account(persistedAccount)
            .status('Received')
            .subject('WO CP Parent')
            .setRecordType('RepairCenterDevices');
        new adb_WorkOrder()
            .account(persistedAccount)
            .asset(persistedAsset)
            .parentWorkOrder(parentWorkOrder)
            .status('Received')
            .subject('WO CP Child')
            .setRecordType('RepairCenterDevices');
        new adb_WorkOrder()
            .account(persistedAccount)
            .asset(persistedAsset)
            .status('Received')
            .subject('WO CP Orphan')
            .setRecordType('RepairCenterDevices')
            .persist();
    }

    @IsTest
    static void testGetPreferencesForWorkOrderChildVisibleWithRows() {
        // Setup
        WorkOrder childWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'WO CP Child'
            LIMIT 1
        ];

        // Given / When
        Test.startTest();
        WorkOrderCustomerPreferencesController.PreferenceListResult result =
            WorkOrderCustomerPreferencesController.getPreferencesForWorkOrder(childWorkOrder.Id);
        Test.stopTest();

        // Then
        Assert.isTrue(result.isVisible, 'Child WO should be visible');
        Assert.areEqual(1, result.preferences.size(), 'Should return active IMS preference');
        Assert.areEqual('Photos required', result.preferences[0].preferenceType);
        Assert.isNotNull(result.preferences[0].preferenceId);
    }

    @IsTest
    static void testGetPreferencesForWorkOrderParentVisibleBlankProductLineOnly() {
        // Setup — parent WO has no Asset / Product Line
        WorkOrder parentWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'WO CP Parent'
            LIMIT 1
        ];

        // Given / When
        Test.startTest();
        WorkOrderCustomerPreferencesController.PreferenceListResult result =
            WorkOrderCustomerPreferencesController.getPreferencesForWorkOrder(parentWorkOrder.Id);
        Test.stopTest();

        // Then — visible and returns preferences where Product Line is blank
        Assert.isTrue(result.isVisible, 'Parent WO without Asset should be visible');
        Assert.areEqual(1, result.preferences.size(), 'Should return blank Product Line preference');
        Assert.isNull(result.preferences[0].productLine, 'Preference Product Line should be blank');
    }

    @IsTest
    static void testGetPreferencesForWorkOrderOrphanVisibleWithRows() {
        // Setup — WO without Parent but with Asset Product Line
        WorkOrder orphanWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'WO CP Orphan'
            LIMIT 1
        ];

        // Given / When
        Test.startTest();
        WorkOrderCustomerPreferencesController.PreferenceListResult result =
            WorkOrderCustomerPreferencesController.getPreferencesForWorkOrder(orphanWorkOrder.Id);
        Test.stopTest();

        // Then
        Assert.isTrue(result.isVisible, 'WO without Parent should still be visible');
        Assert.areEqual(1, result.preferences.size(), 'Should return matching preference rows');
    }

    @IsTest
    static void testGetPreferencesForWorkOrderNullId() {
        // When / Then
        WorkOrderCustomerPreferencesController.PreferenceListResult result =
            WorkOrderCustomerPreferencesController.getPreferencesForWorkOrder(null);
        Assert.isFalse(result.isVisible, 'Null Id should not be visible');
        Assert.areEqual(0, result.preferences.size());
    }

    @IsTest
    static void testGetPreferencesForWorkOrderUnknownId() {
        Id unknownId = WorkOrder.SObjectType.getDescribe().getKeyPrefix() + '000000000000AAA';
        WorkOrderCustomerPreferencesController.PreferenceListResult result =
            WorkOrderCustomerPreferencesController.getPreferencesForWorkOrder(unknownId);
        Assert.isFalse(result.isVisible, 'Unknown WO should not be visible');
        Assert.areEqual(0, result.preferences.size());
    }

    @IsTest
    static void testGetPreferencesForWorkOrder_accountIdNullReturnsVisibleEmpty() {
        WorkOrder workOrder = [SELECT Id FROM WorkOrder LIMIT 1];
        WorkOrderCustomerPreferencesController.facadeOverride =
            new FakeWorkOrdersClient(false);
        try {
            WorkOrderCustomerPreferencesController.PreferenceListResult result =
                WorkOrderCustomerPreferencesController.getPreferencesForWorkOrder(workOrder.Id);

            Assert.isTrue(result.isVisible, 'Loaded Work Order should make the component visible');
            Assert.isTrue(result.preferences.isEmpty(), 'Accountless Work Order has no preferences');
        } finally {
            WorkOrderCustomerPreferencesController.facadeOverride = null;
        }
    }

    @IsTest
    static void testGetPreferencesForWorkOrder_serviceThrows() {
        WorkOrder workOrder = [SELECT Id FROM WorkOrder LIMIT 1];
        WorkOrderCustomerPreferencesController.facadeOverride =
            new FakeWorkOrdersClient(true);
        try {
            Boolean threw = false;
            try {
                WorkOrderCustomerPreferencesController.getPreferencesForWorkOrder(workOrder.Id);
            } catch (AuraHandledException e) {
                threw = true;
                Assert.isTrue(
                    e.getMessage().contains('Unable to load Customer Preferences'),
                    'Controller should return a user-facing error'
                );
            }
            Assert.isTrue(threw, 'Service failure should become AuraHandledException');
        } finally {
            WorkOrderCustomerPreferencesController.facadeOverride = null;
        }
    }
}