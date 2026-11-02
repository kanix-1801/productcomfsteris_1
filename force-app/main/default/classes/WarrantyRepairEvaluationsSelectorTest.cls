/**
 * @description Tests for WarrantyRepairEvaluationsSelector (GW-3891).
 */
@IsTest
private class WarrantyRepairEvaluationsSelectorTest {
    @TestSetup
    static void setupData() {
        adb_Account accountBuilder = new adb_Account()
            .name('WRE Selector Test Account')
            .systemId('LEG-WRE-SEL-01')
            .sourceSystemId('TEST-ORACLE-WRE-SEL-001')
            .orgIds('82');

        adb_Product2 assetProduct = new adb_Product2()
            .name('WRE Selector Asset Product')
            .productCode('WRE-SEL-ASSET-001')
            .productType('Service Asset')
            .productLine('ENDOSCOPE')
            .manufacturer('Olympus')
            .model('CF-HQ190L');

        adb_Asset assetBuilder = new adb_Asset()
            .name('WRE Selector Asset')
            .account(accountBuilder)
            .product(assetProduct)
            .serialNumber('SN-WRE-SEL-001');

        Id standardPricebookId = Test.getStandardPricebookId();
        new adb_WorkOrder()
            .account(accountBuilder)
            .asset(assetBuilder)
            .status('Evaluate')
            .subject('WRE Selector WO')
            .setRecordType('RepairCenterDevices')
            .pricebook2Id(standardPricebookId);

        accountBuilder.persist();
    }

    private static WarrantyRepairEvaluation__c buildSavedEvaluation(Id workOrderId) {
        Id recordTypeId = Schema.SObjectType.WarrantyRepairEvaluation__c.getRecordTypeInfosByDeveloperName()
            .get('RepairCenter')
            ?.getRecordTypeId();

        WarrantyRepairEvaluation__c evaluation = new WarrantyRepairEvaluation__c(
            WorkOrder__c = workOrderId,
            ReasonForReturn__c = 'Selector test reason',
            SignsOfDamageWearFailure__c = 'No',
            DeviceType__c = 'ENDOSCOPE',
            ManufacturerOfTheDeviceInstrument__c = 'Olympus',
            ModelNumberOfTheDeviceInstrument__c = 'CF-HQ190L',
            SerialNumberOfTheDeviceInstrument__c = 'SN-WRE-SEL-001',
            Disposition__c = 'Warranty',
            ConfirmedCustomerReportedIssue__c = 'Yes',
            IssueRelatedToPreviousRepair__c = 'No',
            WorkPerformedAndRecommendation__c = 'Selector test work performed.',
            TechnicianPerformingWork__c = UserInfo.getUserId(),
            Date__c = Date.today(),
            Autoclaved__c = 'Autoclaved',
            CorrectiveActionTaken__c = 'No',
            ComponentNCRCreated__c = 'No',
            ContributingFactor__c = 'Other'
        );
        if (recordTypeId != null) {
            evaluation.RecordTypeId = recordTypeId;
        }
        insert evaluation;
        return evaluation;
    }

    @IsTest
    static void selectByWorkOrderId_nullReturnsEmpty() {
        Test.startTest();
        List<WarrantyRepairEvaluation__c> rows =
            WarrantyRepairEvaluationsSelector.selectByWorkOrderId(null);
        Test.stopTest();

        Assert.isTrue(rows.isEmpty());
    }

    @IsTest
    static void selectByWorkOrderId_returnsRelatedRows() {
        WorkOrder workOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'WRE Selector WO'
            LIMIT 1
        ];
        WarrantyRepairEvaluation__c saved = buildSavedEvaluation(workOrder.Id);

        Test.startTest();
        List<WarrantyRepairEvaluation__c> rows =
            WarrantyRepairEvaluationsSelector.selectByWorkOrderId(workOrder.Id);
        Test.stopTest();

        Assert.areEqual(1, rows.size());
        Assert.areEqual(saved.Id, rows[0].Id);
        Assert.areEqual('Warranty', rows[0].Disposition__c);
    }

    @IsTest
    static void selectByIdForWorkOrder_nullGuardsReturnNull() {
        WorkOrder workOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'WRE Selector WO'
            LIMIT 1
        ];

        Test.startTest();
        Assert.isNull(WarrantyRepairEvaluationsSelector.selectByIdForWorkOrder(null, workOrder.Id));
        Assert.isNull(WarrantyRepairEvaluationsSelector.selectByIdForWorkOrder(workOrder.Id, null));
        Test.stopTest();
    }

    @IsTest
    static void selectByIdForWorkOrder_returnsDetailRow() {
        WorkOrder workOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'WRE Selector WO'
            LIMIT 1
        ];
        WarrantyRepairEvaluation__c saved = buildSavedEvaluation(workOrder.Id);

        Test.startTest();
        WarrantyRepairEvaluation__c loaded = WarrantyRepairEvaluationsSelector.selectByIdForWorkOrder(
            saved.Id,
            workOrder.Id
        );
        Test.stopTest();

        Assert.isNotNull(loaded);
        Assert.areEqual(saved.Id, loaded.Id);
        Assert.areEqual('Selector test reason', loaded.ReasonForReturn__c);
    }

    @IsTest
    static void selectByIdForWorkOrder_wrongWorkOrderReturnsNull() {
        WorkOrder workOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'WRE Selector WO'
            LIMIT 1
        ];
        WarrantyRepairEvaluation__c saved = buildSavedEvaluation(workOrder.Id);

        Test.startTest();
        WarrantyRepairEvaluation__c loaded = WarrantyRepairEvaluationsSelector.selectByIdForWorkOrder(
            saved.Id,
            UserInfo.getUserId()
        );
        Test.stopTest();

        Assert.isNull(loaded);
    }
}