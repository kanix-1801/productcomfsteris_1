/**
 * @description Controller tests for Warranty Repair Evaluation (GW-3891).
 */
@IsTest
private class DeviceEvaluationControllerWreTest {
    @TestSetup
    static void setupData() {
        adb_Account accountBuilder = new adb_Account()
            .name('WRE Controller Test Account')
            .systemId('LEG-WRE-CTL-01')
            .sourceSystemId('TEST-ORACLE-WRE-CTL-001')
            .orgIds('82');

        adb_Product2 assetProduct = new adb_Product2()
            .name('WRE Controller Asset Product')
            .productCode('WRE-CTL-ASSET-001')
            .productType('Service Asset')
            .productLine('ENDOSCOPE')
            .manufacturer('Olympus')
            .model('CF-HQ190L');

        adb_Asset assetBuilder = new adb_Asset()
            .name('WRE Controller Asset')
            .account(accountBuilder)
            .product(assetProduct)
            .serialNumber('SN-WRE-CTL-001');

        Id standardPricebookId = Test.getStandardPricebookId();
        new adb_WorkOrder()
            .account(accountBuilder)
            .asset(assetBuilder)
            .status('Evaluate')
            .subject('WRE Controller WO')
            .setRecordType('RepairCenterDevices')
            .pricebook2Id(standardPricebookId);

        accountBuilder.persist();

        WorkOrder workOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'WRE Controller WO'
            LIMIT 1
        ];
        workOrder.Description = 'Controller test return reason';
        workOrder.QuantityReceived__c = 1;
        update workOrder;
    }

    private static WorkOrder getWorkOrder() {
        return [
            SELECT Id, WorkOrderNumber
            FROM WorkOrder
            WHERE Subject = 'WRE Controller WO'
            LIMIT 1
        ];
    }

    private static DeviceEvaluationController.WarrantyRepairEvaluationForm buildSavableForm(
        Id workOrderId
    ) {
        DeviceEvaluationController.WarrantyRepairEvaluationForm form =
            DeviceEvaluationController.getWarrantyRepairEvaluationForm(workOrderId, null);
        form.signsOfDamageWearFailure = 'Yes';
        form.disposition = 'Warranty';
        form.confirmedCustomerReportedIssue = 'Yes';
        form.issueRelatedToPreviousRepair = 'No';
        form.workPerformedAndRecommendation = 'Controller test work performed.';
        form.technicianPerformingWorkId = UserInfo.getUserId();
        form.technicianSignOffDate = Date.today();
        form.autoclaved = 'Autoclaved';
        form.correctiveActionTaken = 'No';
        form.componentNcrCreated = 'No';
        form.contributingFactor = 'Part Failure';
        return form;
    }

    @IsTest
    static void getWarrantyRepairEvaluations_emptyForNewWorkOrder() {
        WorkOrder workOrder = getWorkOrder();

        Test.startTest();
        List<DeviceEvaluationController.WarrantyRepairEvaluationRow> rows =
            DeviceEvaluationController.getWarrantyRepairEvaluations(workOrder.Id);
        Test.stopTest();

        Assert.isTrue(rows.isEmpty());
    }

    @IsTest
    static void getWarrantyRepairEvaluationForm_newRecordDefaults() {
        WorkOrder workOrder = getWorkOrder();

        Test.startTest();
        DeviceEvaluationController.WarrantyRepairEvaluationForm form =
            DeviceEvaluationController.getWarrantyRepairEvaluationForm(workOrder.Id, null);
        Test.stopTest();

        Assert.areEqual(workOrder.Id, form.workOrderId);
        Assert.areEqual(workOrder.WorkOrderNumber, form.workOrderNumber);
        Assert.areEqual('Controller test return reason', form.reasonForReturn);
        Assert.areEqual('ENDOSCOPE', form.deviceType);
        Assert.isFalse(form.signsOfDamageOptions.isEmpty());
        Assert.isFalse(form.dispositionOptions.isEmpty());
        Assert.isFalse(form.yesNoOptions.isEmpty());
    }

    @IsTest
    static void saveWarrantyRepairEvaluation_jsonPayloadCreatesRecord() {
        WorkOrder workOrder = getWorkOrder();
        DeviceEvaluationController.WarrantyRepairEvaluationForm form = buildSavableForm(workOrder.Id);
        String formJson = JSON.serialize(form);

        Test.startTest();
        List<DeviceEvaluationController.WarrantyRepairEvaluationRow> rows =
            DeviceEvaluationController.saveWarrantyRepairEvaluation(workOrder.Id, formJson);
        Test.stopTest();

        Assert.areEqual(1, rows.size());
        Assert.areEqual('Warranty', rows[0].disposition);
        Assert.areEqual(Date.today(), rows[0].evaluationDate);
        Assert.isNotNull(rows[0].name);
    }

    @IsTest
    static void saveWarrantyRepairEvaluation_blankFormJsonThrows() {
        WorkOrder workOrder = getWorkOrder();
        Boolean threw = false;

        Test.startTest();
        try {
            DeviceEvaluationController.saveWarrantyRepairEvaluation(workOrder.Id, ' ');
        } catch (AuraHandledException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('form data is required'));
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Expected blank form JSON validation.');
    }

    @IsTest
    static void saveWarrantyRepairEvaluation_validationSurfacesServiceMessage() {
        WorkOrder workOrder = getWorkOrder();
        DeviceEvaluationController.WarrantyRepairEvaluationForm form =
            DeviceEvaluationController.getWarrantyRepairEvaluationForm(workOrder.Id, null);
        form.signsOfDamageWearFailure = null;
        String formJson = JSON.serialize(form);
        Boolean threw = false;

        Test.startTest();
        try {
            DeviceEvaluationController.saveWarrantyRepairEvaluation(workOrder.Id, formJson);
        } catch (AuraHandledException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('required field'));
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Expected validation message from service layer.');
    }

    @IsTest
    static void getWarrantyRepairEvaluations_returnsSavedRow() {
        WorkOrder workOrder = getWorkOrder();
        DeviceEvaluationController.WarrantyRepairEvaluationForm form = buildSavableForm(workOrder.Id);
        DeviceEvaluationController.saveWarrantyRepairEvaluation(
            workOrder.Id,
            JSON.serialize(form)
        );

        Test.startTest();
        List<DeviceEvaluationController.WarrantyRepairEvaluationRow> rows =
            DeviceEvaluationController.getWarrantyRepairEvaluations(workOrder.Id);
        Test.stopTest();

        Assert.areEqual(1, rows.size());
        Assert.areEqual('Warranty', rows[0].disposition);
        Assert.areEqual(Date.today(), rows[0].evaluationDate);
    }

    @IsTest
    static void getWarrantyRepairEvaluationForm_workOrderNotFoundThrows() {
        Boolean threw = false;

        Test.startTest();
        try {
            DeviceEvaluationController.getWarrantyRepairEvaluationForm(UserInfo.getUserId(), null);
        } catch (AuraHandledException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('Work Order was not found'));
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Expected missing Work Order error.');
    }

    @IsTest
    static void getWarrantyRepairEvaluationForm_loadsExistingRecord() {
        WorkOrder workOrder = getWorkOrder();
        DeviceEvaluationController.WarrantyRepairEvaluationForm form = buildSavableForm(workOrder.Id);
        List<DeviceEvaluationController.WarrantyRepairEvaluationRow> createdRows =
            DeviceEvaluationController.saveWarrantyRepairEvaluation(
                workOrder.Id,
                JSON.serialize(form)
            );

        Test.startTest();
        DeviceEvaluationController.WarrantyRepairEvaluationForm loaded =
            DeviceEvaluationController.getWarrantyRepairEvaluationForm(
                workOrder.Id,
                createdRows[0].id
            );
        Test.stopTest();

        Assert.areEqual(createdRows[0].id, loaded.id);
        Assert.areEqual('Warranty', loaded.disposition);
        Assert.areEqual(workOrder.Id, loaded.workOrderId);
    }
}