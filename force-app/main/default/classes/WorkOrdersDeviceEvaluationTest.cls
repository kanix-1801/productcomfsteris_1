/**
 * @description GW-3913 / GW-3096 - Direct WorkOrdersService tests for Device Evaluation.
 */
@IsTest
private class WorkOrdersDeviceEvaluationTest {
    private static final String SUBJECT_STAGE_1 = 'WO DE Service Stage 1';
    private static final String SUBJECT_EMPTY_BOM = 'WO DE Service Empty BOM';
    private static final String SUBJECT_NO_ASSET = 'WO DE Service No Asset';
    private static final String PRODUCT_CODE_CATEGORY = 'CT.WODE001';

    /**
     * @description GW-3913 / GW-3096 - Creates Devices Work Orders with eval-display BOM codes.
     */
    @TestSetup
    static void setupData() {
        adb_Account accountBuilder = new adb_Account()
            .name('WO DE Service Account')
            .systemId('LEG-WODE-1001')
            .sourceSystemId('TEST-ORACLE-WODE')
            .orgIds('82');

        adb_Product2 assetProduct = new adb_Product2()
            .name('WO DE Asset Product')
            .productCode('WODE-ASSET-001')
            .productType('Service Asset')
            .productLine('ENDOSCOPE')
            .manufacturer('Olympus')
            .model('CF-HQ190L');
        adb_Product2 categoryCode = new adb_Product2()
            .name('WO DE Category Code')
            .productCode(PRODUCT_CODE_CATEGORY)
            .productType('Category Code')
            .evalDisplayScreen('Y')
            .evalRank('10')
            .evalCategory('ANY');
        adb_Product2 observationCode = new adb_Product2()
            .name('WO DE Observation Code')
            .productCode('OC.WODE001')
            .productType('Observation Code')
            .evalDisplayScreen('Y')
            .evalRank('20')
            .evalCategory('DISTAL TIP')
            .condition('Ok');
        adb_Product2 emptyAssetProduct = new adb_Product2()
            .name('WO DE Empty BOM Product')
            .productCode('WODE-ASSET-EMPTY')
            .productType('Service Asset');

        for (adb_Product2 productBuilder : new List<adb_Product2>{
            assetProduct,
            categoryCode,
            observationCode,
            emptyAssetProduct
        }) {
            new adb_PricebookEntry().product(productBuilder);
        }

        new adb_ProductRelatedMaterial()
            .name('WODE-BOM-CT')
            .product(assetProduct)
            .productComponent(categoryCode)
            .quantityPerProductUnit(1)
            .componentSequence(10);
        new adb_ProductRelatedMaterial()
            .name('WODE-BOM-OC')
            .product(assetProduct)
            .productComponent(observationCode)
            .quantityPerProductUnit(1)
            .componentSequence(20);

        adb_Asset assetBuilder = new adb_Asset()
            .name('WO DE Asset')
            .account(accountBuilder)
            .product(assetProduct)
            .serialNumber('SN-WODE-001');
        adb_Asset emptyBomAssetBuilder = new adb_Asset()
            .name('WO DE Empty BOM Asset')
            .account(accountBuilder)
            .product(emptyAssetProduct)
            .serialNumber('SN-WODE-EMPTY');

        Id standardPricebookId = Test.getStandardPricebookId();
        new adb_WorkOrder()
            .account(accountBuilder)
            .asset(assetBuilder)
            .status('Received')
            .subject(SUBJECT_STAGE_1)
            .setRecordType('RepairCenterDevices')
            .pricebook2Id(standardPricebookId);
        new adb_WorkOrder()
            .account(accountBuilder)
            .asset(emptyBomAssetBuilder)
            .status('Received')
            .subject(SUBJECT_EMPTY_BOM)
            .setRecordType('RepairCenterDevices')
            .pricebook2Id(standardPricebookId);
        new adb_WorkOrder()
            .account(accountBuilder)
            .status('Received')
            .subject(SUBJECT_NO_ASSET)
            .setRecordType('RepairCenterDevices')
            .pricebook2Id(standardPricebookId);

        accountBuilder.persist();
    }

    /**
     * @description GW-3913 / GW-3096 - Verifies initialize sets Evaluate / Eval and builds context.
     */
    @IsTest
    static void testInitializeDeviceEvaluation_WhenValidNumber_SetsEvaluate() {
        WorkOrder workOrder = queryWorkOrder(SUBJECT_STAGE_1);

        Test.startTest();
        WorkOrdersService.DeviceEvaluationContext context =
            WorkOrdersService.initializeDeviceEvaluation('  ' + workOrder.WorkOrderNumber + '  ');
        Test.stopTest();

        Assert.areEqual(workOrder.Id, context.workOrder.Id);
        Assert.areEqual('Evaluate', context.workOrder.Status);
        Assert.areEqual('Eval', context.workOrder.SubStatus__c);
        Assert.areEqual(UserInfo.getUserId(), context.workOrder.OwnerId);
        Assert.areEqual(UserInfo.getUserId(), context.workOrder.Evaluator__c);
        Assert.isTrue(context.selectableCardCount >= 1, 'Expected selectable eval codes');
        Assert.isTrue(
            String.isNotBlank(context.deviceIdentityLine) &&
            context.deviceIdentityLine.contains('SN-WODE-001'),
            'Identity line should include the asset serial'
        );
        Assert.areEqual(false, context.photosRequired);
    }

    /**
     * @description GW-3913 / GW-3096 - Verifies unknown Work Order Number is rejected.
     */
    @IsTest
    static void testInitializeDeviceEvaluation_WhenMissingNumber_Throws() {
        Boolean threw = false;
        Test.startTest();
        try {
            WorkOrdersService.initializeDeviceEvaluation('WO-DOES-NOT-EXIST-3096');
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('not found'));
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Unknown Work Order Number should throw');
    }

    /**
     * @description GW-3913 / GW-3096 - Verifies Work Orders without an Asset cannot start evaluation.
     */
    @IsTest
    static void testInitializeDeviceEvaluation_WhenMissingAsset_Throws() {
        WorkOrder workOrder = queryWorkOrder(SUBJECT_NO_ASSET);
        Boolean threw = false;
        Test.startTest();
        try {
            WorkOrdersService.initializeDeviceEvaluation(workOrder.WorkOrderNumber);
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('Asset'));
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Missing Asset should throw');
    }

    /**
     * @description GW-3913 / GW-3096 - Verifies products with no eval-display codes cannot start evaluation.
     */
    @IsTest
    static void testInitializeDeviceEvaluation_WhenNoSelectableCodes_Throws() {
        WorkOrder workOrder = queryWorkOrder(SUBJECT_EMPTY_BOM);
        Boolean threw = false;
        Test.startTest();
        try {
            WorkOrdersService.initializeDeviceEvaluation(workOrder.WorkOrderNumber);
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('No evaluation codes'));
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Empty BOM should throw');
    }

    /**
     * @description GW-3913 / GW-3096 - Verifies save persists header fields and usage-count date.
     */
    @IsTest
    static void testSaveDeviceEvaluationWorkOrderFields_WhenValidId_PersistsNotes() {
        WorkOrder workOrder = queryWorkOrder(SUBJECT_STAGE_1);
        WorkOrdersService.initializeDeviceEvaluation(workOrder.WorkOrderNumber);

        Test.startTest();
        WorkOrdersService.DeviceEvaluationContext saved =
            WorkOrdersService.saveDeviceEvaluationWorkOrderFields(
                workOrder.Id,
                'Eval',
                true,
                12,
                '100',
                'Customer facing note',
                'Internal note',
                'Specialist note'
            );
        WorkOrdersService.DeviceEvaluationContext cleared =
            WorkOrdersService.saveDeviceEvaluationWorkOrderFields(
                workOrder.Id,
                'Eval',
                false,
                8,
                null,
                'Customer facing note',
                'Internal note',
                'Specialist note'
            );
        Test.stopTest();

        Assert.areEqual(true, saved.workOrder.UnableToTakePhoto__c);
        Assert.areEqual(12, saved.workOrder.TurnTime__c);
        Assert.areEqual('100', saved.workOrder.UsageCount__c);
        Assert.areEqual(Date.today(), saved.workOrder.UsageCountDate__c);
        Assert.areEqual('Customer facing note', saved.workOrder.EvaluationNotes__c);
        Assert.isNull(cleared.workOrder.UsageCountDate__c, 'Blank usage count should clear the date');
        Assert.areEqual(false, cleared.workOrder.UnableToTakePhoto__c);
    }

    /**
     * @description GW-3913 / GW-3096 - Verifies save rejects an unknown Work Order Id.
     */
    @IsTest
    static void testSaveDeviceEvaluationWorkOrderFields_WhenUnknownId_Throws() {
        Boolean threw = false;
        Test.startTest();
        try {
            WorkOrdersService.saveDeviceEvaluationWorkOrderFields(
                UserInfo.getUserId(),
                'Eval',
                false,
                1,
                null,
                null,
                null,
                null
            );
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('not found'));
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Unknown Work Order Id should throw');
    }

    /**
     * @description GW-3913 / GW-3096 - Verifies Save (not Complete) keeps Evaluate status.
     */
    @IsTest
    static void testPersistDeviceEvaluationDraft_WhenSave_KeepsEvaluate() {
        WorkOrder workOrder = queryWorkOrder(SUBJECT_STAGE_1);
        WorkOrdersService.initializeDeviceEvaluation(workOrder.WorkOrderNumber);

        Test.startTest();
        WorkOrdersService.DeviceEvaluationContext context =
            WorkOrdersService.persistDeviceEvaluationDraft(
                workOrder.Id,
                'Eval',
                false,
                3,
                '50',
                'Save notes',
                'Internal save',
                'Specialist save',
                new List<Id>(),
                new List<ContentDocumentLinksService.StagedPhotoAssignment>(),
                false
            );
        Test.stopTest();

        Assert.areEqual('Evaluate', context.workOrder.Status);
        Assert.areEqual('Eval', context.workOrder.SubStatus__c);
        Assert.areEqual('Save notes', context.workOrder.EvaluationNotes__c);
        Assert.areEqual('50', context.workOrder.UsageCount__c);
        Assert.areEqual(Date.today(), context.workOrder.UsageCountDate__c);
    }

    /**
     * @description GW-3913 / GW-3096 - Verifies Complete without Estimate Required sets Ready for Repair.
     */
    @IsTest
    static void testPersistDeviceEvaluationDraft_WhenCompletePreApproved_SetsReadyForRepair() {
        WorkOrder workOrder = queryWorkOrder(SUBJECT_STAGE_1);
        workOrder.EstimateRequired__c = 'Pre-Approved';
        workOrder.CustomerPORequired__c = false;
        update workOrder;
        WorkOrdersService.initializeDeviceEvaluation(workOrder.WorkOrderNumber);
        Id categoryProductId = [
            SELECT Id
            FROM Product2
            WHERE ProductCode = :PRODUCT_CODE_CATEGORY
            LIMIT 1
        ]
        .Id;

        Test.startTest();
        WorkOrdersService.DeviceEvaluationContext completed =
            WorkOrdersService.persistDeviceEvaluationDraft(
                workOrder.Id,
                'Eval',
                true,
                4,
                null,
                'Complete notes',
                'Internal complete',
                'Specialist complete',
                new List<Id>{ categoryProductId, null },
                null,
                true
            );
        Test.stopTest();

        Assert.areEqual('Ready for Repair', completed.workOrder.Status);
        Assert.isNull(completed.workOrder.SubStatus__c);
        Assert.isTrue(
            completed.selectedProductIds.contains(categoryProductId),
            'Selected category code should remain on the Work Order'
        );
    }

    /**
     * @description GW-3913 / GW-3096 - Verifies Complete with Estimate Required sets Quote.
     */
    @IsTest
    static void testPersistDeviceEvaluationDraft_WhenCompleteEstimateRequired_SetsQuote() {
        WorkOrder workOrder = queryWorkOrder(SUBJECT_STAGE_1);
        workOrder.EstimateRequired__c = 'Estimate Required';
        workOrder.CustomerPORequired__c = false;
        update workOrder;
        WorkOrdersService.initializeDeviceEvaluation(workOrder.WorkOrderNumber);

        Test.startTest();
        WorkOrdersService.DeviceEvaluationContext completed =
            WorkOrdersService.persistDeviceEvaluationDraft(
                workOrder.Id,
                'Eval',
                true,
                2,
                null,
                'Quote notes',
                null,
                null,
                new List<Id>(),
                null,
                true
            );
        Test.stopTest();

        Assert.areEqual('Quote', completed.workOrder.Status);
        Assert.areEqual('Waiting for Approval', completed.workOrder.SubStatus__c);
    }

    /**
     * @description GW-3913 / GW-3096 - Verifies Complete with missing Customer PO sets Quote.
     */
    @IsTest
    static void testPersistDeviceEvaluationDraft_WhenCompleteMissingPo_SetsQuote() {
        WorkOrder workOrder = queryWorkOrder(SUBJECT_STAGE_1);
        workOrder.EstimateRequired__c = 'Pre-Approved';
        workOrder.CustomerPORequired__c = true;
        workOrder.CustomerPO__c = null;
        update workOrder;
        WorkOrdersService.initializeDeviceEvaluation(workOrder.WorkOrderNumber);

        Test.startTest();
        WorkOrdersService.DeviceEvaluationContext completed =
            WorkOrdersService.persistDeviceEvaluationDraft(
                workOrder.Id,
                'Eval',
                true,
                2,
                null,
                null,
                null,
                null,
                new List<Id>(),
                null,
                true
            );
        Test.stopTest();

        Assert.areEqual('Quote', completed.workOrder.Status);
        Assert.areEqual('Waiting for Approval', completed.workOrder.SubStatus__c);
    }

    /**
     * @description GW-3913 / GW-3096 - Verifies Complete requires photos when the preference is on.
     */
    @IsTest
    static void testPersistDeviceEvaluationDraft_WhenPhotosRequired_Throws() {
        Account account = [SELECT Id FROM Account WHERE Name = 'WO DE Service Account' LIMIT 1];
        adb_Account accountBuilder = new adb_Account();
        accountBuilder.record.Id = account.Id;
        new adb_CustomerPreference()
            .account(accountBuilder)
            .name('WO DE Photos Required')
            .setRecordType('IMSCustomerPreference')
            .preferenceType('Photos required')
            .startDate(Date.today().addDays(-1))
            .endDate(Date.today().addDays(30))
            .persist();

        WorkOrder workOrder = queryWorkOrder(SUBJECT_STAGE_1);
        WorkOrdersService.initializeDeviceEvaluation(workOrder.WorkOrderNumber);

        ContentDocumentLinksService.StagedPhotoAssignment incomplete =
            new ContentDocumentLinksService.StagedPhotoAssignment();
        incomplete.contentDocumentId = null;
        incomplete.productId = null;

        Boolean threw = false;
        Test.startTest();
        try {
            WorkOrdersService.persistDeviceEvaluationDraft(
                workOrder.Id,
                'Eval',
                false,
                1,
                null,
                null,
                null,
                null,
                new List<Id>(),
                new List<ContentDocumentLinksService.StagedPhotoAssignment>{ incomplete },
                true
            );
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('Photos are required'));
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Photos required without files should throw');
    }

    /**
     * @description GW-3913 / GW-3096 - Verifies selected repair codes must belong to the catalog.
     */
    @IsTest
    static void testPersistDeviceEvaluationDraft_WhenInvalidSelectedProduct_Throws() {
        WorkOrder workOrder = queryWorkOrder(SUBJECT_STAGE_1);
        WorkOrdersService.initializeDeviceEvaluation(workOrder.WorkOrderNumber);

        Boolean threw = false;
        Test.startTest();
        try {
            WorkOrdersService.persistDeviceEvaluationDraft(
                workOrder.Id,
                'Eval',
                true,
                1,
                null,
                null,
                null,
                null,
                new List<Id>{ UserInfo.getUserId() },
                null,
                false
            );
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('not valid'));
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Unknown selected product should throw');
    }

    /**
     * @description GW-3913 / GW-3096 - Verifies Complete status helper for Estimate / PO rules.
     */
    @IsTest
    static void testApplyCompletionStatus_WhenEstimateOrPoMissing_SetsQuote() {
        WorkOrder estimateRequired = new WorkOrder(EstimateRequired__c = 'Estimate Required');
        WorkOrder missingPo = new WorkOrder(
            EstimateRequired__c = 'Pre-Approved',
            CustomerPORequired__c = true,
            CustomerPO__c = null
        );
        WorkOrder ready = new WorkOrder(
            EstimateRequired__c = 'Pre-Approved',
            CustomerPORequired__c = false
        );

        WorkOrdersService.applyCompletionStatus(estimateRequired);
        WorkOrdersService.applyCompletionStatus(missingPo);
        WorkOrdersService.applyCompletionStatus(ready);

        Assert.areEqual('Quote', estimateRequired.Status);
        Assert.areEqual('Waiting for Approval', estimateRequired.SubStatus__c);
        Assert.areEqual('Quote', missingPo.Status);
        Assert.areEqual('Waiting for Approval', missingPo.SubStatus__c);
        Assert.areEqual('Ready for Repair', ready.Status);
        Assert.isNull(ready.SubStatus__c);
    }

    /**
     * @description GW-3913 / GW-3096 - Work Order used by Device Evaluation service tests.
     * @param subject Work Order Subject created in @TestSetup
     * @return Matching Work Order
     */
    private static WorkOrder queryWorkOrder(String subject) {
        return [
            SELECT Id, WorkOrderNumber
            FROM WorkOrder
            WHERE Subject = :subject
            LIMIT 1
        ];
    }
}