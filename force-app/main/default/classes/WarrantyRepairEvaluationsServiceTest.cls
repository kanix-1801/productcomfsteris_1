/**
 * @description Tests for WarrantyRepairEvaluationsService (GW-3891).
 */
@IsTest
private class WarrantyRepairEvaluationsServiceTest {
    @TestSetup
    static void setupData() {
        adb_Account accountBuilder = new adb_Account()
            .name('WRE Service Test Account')
            .systemId('LEG-WRE-SVC-01')
            .sourceSystemId('TEST-ORACLE-WRE-SVC-001')
            .orgIds('82');

        adb_Product2 assetProduct = new adb_Product2()
            .name('WRE Service Asset Product')
            .productCode('WRE-SVC-ASSET-001')
            .productType('Service Asset')
            .productLine('ENDOSCOPE')
            .manufacturer('Olympus')
            .model('CF-HQ190L');

        adb_Asset assetBuilder = new adb_Asset()
            .name('WRE Service Asset')
            .account(accountBuilder)
            .product(assetProduct)
            .serialNumber('SN-WRE-SVC-001');

        Id standardPricebookId = Test.getStandardPricebookId();

        adb_WorkOrder priorWorkOrderBuilder = new adb_WorkOrder()
            .account(accountBuilder)
            .asset(assetBuilder)
            .status('Closed')
            .subject('WRE Service Prior Repair WO')
            .setRecordType('RepairCenterDevices')
            .actualShipDate(Date.today().addDays(-30))
            .pricebook2Id(standardPricebookId);
        priorWorkOrderBuilder.persist();

        WorkOrder priorWorkOrder = (WorkOrder) priorWorkOrderBuilder.record;

        Id wahRecordTypeId = Schema.SObjectType.WOAssignmentHistory__c.getRecordTypeInfosByDeveloperName()
            .get('RepairCenter')
            ?.getRecordTypeId();
        WOAssignmentHistory__c closedAssignment = new WOAssignmentHistory__c(
            WorkOrder__c = priorWorkOrder.Id,
            Type__c = 'Technician',
            Technician__c = UserInfo.getUserId(),
            StartDateTime__c = Datetime.now().addDays(-31),
            EndDateTime__c = Datetime.now().addDays(-30)
        );
        if (wahRecordTypeId != null) {
            closedAssignment.RecordTypeId = wahRecordTypeId;
        }
        insert closedAssignment;

        new adb_WorkOrder()
            .account(accountBuilder)
            .asset(assetBuilder)
            .status('Evaluate')
            .subject('WRE Service Current WO')
            .setRecordType('RepairCenterDevices')
            .pricebook2Id(standardPricebookId);

        accountBuilder.persist();

        WorkOrder currentWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'WRE Service Current WO'
            LIMIT 1
        ];
        currentWorkOrder.Description = 'Customer reported leak';
        currentWorkOrder.QuantityReceived__c = 2;
        update currentWorkOrder;
    }

    private static WorkOrder getCurrentWorkOrder() {
        return [
            SELECT Id, AssetId, Description, QuantityReceived__c
            FROM WorkOrder
            WHERE Subject = 'WRE Service Current WO'
            LIMIT 1
        ];
    }

    private static WarrantyRepairEvaluation__c buildValidEvaluation(Id workOrderId) {
        Id recordTypeId = Schema.SObjectType.WarrantyRepairEvaluation__c.getRecordTypeInfosByDeveloperName()
            .get('RepairCenter')
            ?.getRecordTypeId();

        WarrantyRepairEvaluation__c evaluation = new WarrantyRepairEvaluation__c(
            WorkOrder__c = workOrderId,
            ReasonForReturn__c = 'Customer reported leak',
            SignsOfDamageWearFailure__c = 'Yes',
            OriginalReturnOrder__c = 'RO-12345',
            PreviousRepairQCTechnician__c = UserInfo.getUserId(),
            PreviousRepairDate__c = Date.today().addDays(-30),
            DeviceType__c = 'ENDOSCOPE',
            ManufacturerOfTheDeviceInstrument__c = 'Olympus',
            ModelNumberOfTheDeviceInstrument__c = 'CF-HQ190L',
            SerialNumberOfTheDeviceInstrument__c = 'SN-WRE-SVC-001',
            Disposition__c = 'Warranty',
            ConfirmedCustomerReportedIssue__c = 'Yes',
            IssueRelatedToPreviousRepair__c = 'No',
            PreviousWorkPerformed__c = 'Prior category and service work',
            WorkPerformedAndRecommendation__c = 'Inspected and tested device.',
            TechnicianPerformingWork__c = UserInfo.getUserId(),
            Date__c = Date.today(),
            Autoclaved__c = 'Autoclaved',
            CorrectiveActionTaken__c = 'No',
            ComponentNCRCreated__c = 'No',
            ContributingFactor__c = 'Part Failure'
        );
        if (recordTypeId != null) {
            evaluation.RecordTypeId = recordTypeId;
        }
        return evaluation;
    }

    private static WarrantyRepairEvaluation__c buildValidEvaluationWithoutAssetPreviousRepairFields(
        Id workOrderId
    ) {
        WarrantyRepairEvaluation__c evaluation = buildValidEvaluation(workOrderId);
        evaluation.OriginalReturnOrder__c = null;
        evaluation.PreviousRepairQCTechnician__c = null;
        evaluation.PreviousRepairDate__c = null;
        evaluation.PreviousWorkPerformed__c = null;
        evaluation.SerialNumberOfTheDeviceInstrument__c = null;
        return evaluation;
    }

    @IsTest
    static void getEvaluationsByWorkOrderId_nullReturnsEmpty() {
        Test.startTest();
        List<WarrantyRepairEvaluation__c> rows =
            WarrantyRepairEvaluationsService.getEvaluationsByWorkOrderId(null);
        Test.stopTest();

        Assert.isTrue(rows.isEmpty());
    }

    @IsTest
    static void buildEvaluationForForm_nullWorkOrderThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            WarrantyRepairEvaluationsService.buildEvaluationForForm(null, null);
        } catch (WarrantyRepairEvaluationsService.WarrantyRepairEvaluationsServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('Work Order is required'));
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Expected Work Order is required.');
    }

    @IsTest
    static void buildEvaluationForForm_newRecordAutoPopulates() {
        WorkOrder workOrder = getCurrentWorkOrder();

        Test.startTest();
        WarrantyRepairEvaluation__c shell = WarrantyRepairEvaluationsService.buildEvaluationForForm(
            workOrder.Id,
            null
        );
        Test.stopTest();

        Assert.areEqual(workOrder.Id, shell.WorkOrder__c);
        Assert.areEqual('Customer reported leak', shell.ReasonForReturn__c);
        Assert.areEqual(2, shell.ItemCount__c);
        Assert.areEqual('ENDOSCOPE', shell.DeviceType__c);
        Assert.areEqual('Olympus', shell.ManufacturerOfTheDeviceInstrument__c);
        Assert.areEqual('CF-HQ190L', shell.ModelNumberOfTheDeviceInstrument__c);
        Assert.areEqual('SN-WRE-SVC-001', shell.SerialNumberOfTheDeviceInstrument__c);
        Assert.areEqual(UserInfo.getUserId(), shell.TechnicianPerformingWork__c);
        Assert.areEqual(Date.today(), shell.Date__c);
        Assert.areEqual(Date.today().addDays(-30), shell.PreviousRepairDate__c);
        Assert.areEqual(UserInfo.getUserId(), shell.PreviousRepairQCTechnician__c);
    }

    @IsTest
    static void buildEvaluationForForm_existingRecord() {
        WorkOrder workOrder = getCurrentWorkOrder();
        WarrantyRepairEvaluation__c saved = buildValidEvaluation(workOrder.Id);
        insert saved;

        Test.startTest();
        WarrantyRepairEvaluation__c loaded = WarrantyRepairEvaluationsService.buildEvaluationForForm(
            workOrder.Id,
            saved.Id
        );
        Test.stopTest();

        Assert.areEqual(saved.Id, loaded.Id);
        Assert.areEqual('Warranty', loaded.Disposition__c);
    }

    @IsTest
    static void buildEvaluationForForm_recordNotForWorkOrderThrows() {
        WorkOrder workOrder = getCurrentWorkOrder();
        WarrantyRepairEvaluation__c saved = buildValidEvaluation(workOrder.Id);
        insert saved;

        WorkOrder otherWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'WRE Service Prior Repair WO'
            LIMIT 1
        ];

        Boolean threw = false;
        Test.startTest();
        try {
            WarrantyRepairEvaluationsService.buildEvaluationForForm(otherWorkOrder.Id, saved.Id);
        } catch (WarrantyRepairEvaluationsService.WarrantyRepairEvaluationsServiceException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('Warranty Repair Evaluation was not found for this Work Order')
            );
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Expected not found for mismatched Work Order.');
    }

    @IsTest
    static void saveEvaluation_nullEvaluationThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            WarrantyRepairEvaluationsService.saveEvaluation(null);
        } catch (WarrantyRepairEvaluationsService.WarrantyRepairEvaluationsServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('Work Order is required'));
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Expected Work Order is required.');
    }

    @IsTest
    static void saveEvaluation_validationMissingRequiredFields() {
        WorkOrder workOrder = getCurrentWorkOrder();
        WarrantyRepairEvaluation__c evaluation = new WarrantyRepairEvaluation__c(
            WorkOrder__c = workOrder.Id
        );

        Boolean threw = false;
        Test.startTest();
        try {
            WarrantyRepairEvaluationsService.saveEvaluation(evaluation);
        } catch (WarrantyRepairEvaluationsService.WarrantyRepairEvaluationsServiceException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('Please complete the following required fields')
            );
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Expected validation failure.');
    }

    @IsTest
    static void saveEvaluation_validationSingleMissingFieldMessage() {
        WorkOrder workOrder = getCurrentWorkOrder();
        WarrantyRepairEvaluation__c evaluation = buildValidEvaluation(workOrder.Id);
        evaluation.ReasonForReturn__c = null;

        Boolean threw = false;
        Test.startTest();
        try {
            WarrantyRepairEvaluationsService.saveEvaluation(evaluation);
        } catch (WarrantyRepairEvaluationsService.WarrantyRepairEvaluationsServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('Please complete the required field:'));
            Assert.isTrue(e.getMessage().contains('Describe Reason for Return'));
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Expected singular validation message.');
    }

    @IsTest
    static void saveEvaluation_validationCorrectiveActionDetailsRequired() {
        WorkOrder workOrder = getCurrentWorkOrder();
        WarrantyRepairEvaluation__c evaluation = buildValidEvaluation(workOrder.Id);
        evaluation.CorrectiveActionTaken__c = 'Yes';

        Boolean threw = false;
        Test.startTest();
        try {
            WarrantyRepairEvaluationsService.saveEvaluation(evaluation);
        } catch (WarrantyRepairEvaluationsService.WarrantyRepairEvaluationsServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('additional detail'));
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Expected corrective action detail validation.');
    }

    @IsTest
    static void saveEvaluation_validationNcrFieldsRequired() {
        WorkOrder workOrder = getCurrentWorkOrder();
        WarrantyRepairEvaluation__c evaluation = buildValidEvaluation(workOrder.Id);
        evaluation.ComponentNCRCreated__c = 'Yes';

        Boolean threw = false;
        Test.startTest();
        try {
            WarrantyRepairEvaluationsService.saveEvaluation(evaluation);
        } catch (WarrantyRepairEvaluationsService.WarrantyRepairEvaluationsServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('NCR Number'));
            Assert.isTrue(e.getMessage().contains('Part Number'));
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Expected NCR field validation.');
    }

    @IsTest
    static void saveEvaluation_insertSuccess() {
        WorkOrder workOrder = getCurrentWorkOrder();
        WarrantyRepairEvaluation__c evaluation = buildValidEvaluation(workOrder.Id);

        Test.startTest();
        List<WarrantyRepairEvaluation__c> insertedRows =
            WarrantyRepairEvaluationsService.saveEvaluation(evaluation);
        Test.stopTest();

        Assert.areEqual(1, insertedRows.size());
        Assert.areEqual('Warranty', insertedRows[0].Disposition__c);

        List<WarrantyRepairEvaluation__c> queried =
            WarrantyRepairEvaluationsService.getEvaluationsByWorkOrderId(workOrder.Id);
        Assert.areEqual(1, queried.size());
    }

    @IsTest
    static void saveEvaluation_updateSuccess() {
        WorkOrder workOrder = getCurrentWorkOrder();
        WarrantyRepairEvaluation__c evaluation = buildValidEvaluation(workOrder.Id);
        insert evaluation;

        evaluation = [
            SELECT
                Id,
                WorkOrder__c,
                WorkOrderLineItem__c,
                ParentWorkOrder__c,
                RelatedReturnOrder__c,
                CustomerNumber__c,
                DateReceived__c,
                ItemCount__c,
                ReasonForReturn__c,
                SignsOfDamageWearFailure__c,
                OriginalReturnOrder__c,
                PreviousRepairQCTechnician__c,
                PreviousRepairDate__c,
                DeviceType__c,
                ManufacturerOfTheDeviceInstrument__c,
                ModelNumberOfTheDeviceInstrument__c,
                SerialNumberOfTheDeviceInstrument__c,
                Disposition__c,
                ConfirmedCustomerReportedIssue__c,
                IssueRelatedToPreviousRepair__c,
                PreviousWorkPerformed__c,
                WorkPerformedAndRecommendation__c,
                TechnicianPerformingWork__c,
                Date__c,
                TeamLeader__c,
                TeamLeaderSignOff__c,
                Autoclaved__c,
                CorrectiveActionTaken__c,
                CorrectiveActionAdditionalDetails__c,
                ContributingFactor__c,
                ComponentNCRCreated__c,
                NCRNumber__c,
                PartNumber__c,
                LotNumber__c
            FROM WarrantyRepairEvaluation__c
            WHERE Id = :evaluation.Id
        ];
        evaluation.Disposition__c = 'No Problem Found';

        Test.startTest();
        List<WarrantyRepairEvaluation__c> updatedRows =
            WarrantyRepairEvaluationsService.saveEvaluation(evaluation);
        Test.stopTest();

        Assert.areEqual(1, updatedRows.size());
        Assert.areEqual('No Problem Found', updatedRows[0].Disposition__c);
    }

    @IsTest
    static void buildUpdatePayload_omitsMasterDetailWorkOrder() {
        WorkOrder workOrder = getCurrentWorkOrder();
        WarrantyRepairEvaluation__c evaluation = buildValidEvaluation(workOrder.Id);
        insert evaluation;

        Test.startTest();
        WarrantyRepairEvaluation__c payload =
            WarrantyRepairEvaluationsService.buildUpdatePayload(evaluation);
        Test.stopTest();

        Assert.areEqual(evaluation.Id, payload.Id);
        Assert.isNull(payload.WorkOrder__c);
        Assert.areEqual('Warranty', payload.Disposition__c);
    }

    @IsTest
    static void saveEvaluation_updateWithoutWorkOrderOnStub() {
        WorkOrder workOrder = getCurrentWorkOrder();
        WarrantyRepairEvaluation__c evaluation = buildValidEvaluation(workOrder.Id);
        insert evaluation;

        evaluation = [
            SELECT
                Id,
                WorkOrderLineItem__c,
                ReasonForReturn__c,
                SignsOfDamageWearFailure__c,
                OriginalReturnOrder__c,
                PreviousRepairQCTechnician__c,
                PreviousRepairDate__c,
                DeviceType__c,
                ManufacturerOfTheDeviceInstrument__c,
                ModelNumberOfTheDeviceInstrument__c,
                SerialNumberOfTheDeviceInstrument__c,
                Disposition__c,
                ConfirmedCustomerReportedIssue__c,
                IssueRelatedToPreviousRepair__c,
                PreviousWorkPerformed__c,
                WorkPerformedAndRecommendation__c,
                TechnicianPerformingWork__c,
                Date__c,
                Autoclaved__c,
                CorrectiveActionTaken__c,
                CorrectiveActionAdditionalDetails__c,
                ContributingFactor__c,
                ComponentNCRCreated__c
            FROM WarrantyRepairEvaluation__c
            WHERE Id = :evaluation.Id
        ];

        WarrantyRepairEvaluation__c updateStub = new WarrantyRepairEvaluation__c(
            Id = evaluation.Id,
            WorkOrderLineItem__c = evaluation.WorkOrderLineItem__c,
            ReasonForReturn__c = evaluation.ReasonForReturn__c,
            SignsOfDamageWearFailure__c = evaluation.SignsOfDamageWearFailure__c,
            OriginalReturnOrder__c = 'Updated without WorkOrder on stub',
            PreviousRepairQCTechnician__c = evaluation.PreviousRepairQCTechnician__c,
            PreviousRepairDate__c = evaluation.PreviousRepairDate__c,
            DeviceType__c = evaluation.DeviceType__c,
            ManufacturerOfTheDeviceInstrument__c = evaluation.ManufacturerOfTheDeviceInstrument__c,
            ModelNumberOfTheDeviceInstrument__c = evaluation.ModelNumberOfTheDeviceInstrument__c,
            SerialNumberOfTheDeviceInstrument__c = evaluation.SerialNumberOfTheDeviceInstrument__c,
            Disposition__c = evaluation.Disposition__c,
            ConfirmedCustomerReportedIssue__c = evaluation.ConfirmedCustomerReportedIssue__c,
            IssueRelatedToPreviousRepair__c = evaluation.IssueRelatedToPreviousRepair__c,
            PreviousWorkPerformed__c = evaluation.PreviousWorkPerformed__c,
            WorkPerformedAndRecommendation__c = evaluation.WorkPerformedAndRecommendation__c,
            TechnicianPerformingWork__c = evaluation.TechnicianPerformingWork__c,
            Date__c = evaluation.Date__c,
            Autoclaved__c = evaluation.Autoclaved__c,
            CorrectiveActionTaken__c = evaluation.CorrectiveActionTaken__c,
            CorrectiveActionAdditionalDetails__c = evaluation.CorrectiveActionAdditionalDetails__c,
            ContributingFactor__c = evaluation.ContributingFactor__c,
            ComponentNCRCreated__c = evaluation.ComponentNCRCreated__c
        );

        Test.startTest();
        List<WarrantyRepairEvaluation__c> updatedRows =
            WarrantyRepairEvaluationsService.saveEvaluation(updateStub);
        Test.stopTest();

        Assert.areEqual(1, updatedRows.size());
        WarrantyRepairEvaluation__c persisted = [
            SELECT OriginalReturnOrder__c
            FROM WarrantyRepairEvaluation__c
            WHERE Id = :evaluation.Id
        ];
        Assert.areEqual('Updated without WorkOrder on stub', persisted.OriginalReturnOrder__c);
    }

    @IsTest
    static void resolveFieldHelpers_coverAssetFallbacks() {
        WorkOrder workOrder = WorkOrdersSelector.selectForWarrantyRepairEvaluationById(
            getCurrentWorkOrder().Id
        );

        Test.startTest();
        Assert.areEqual('ENDOSCOPE', WarrantyRepairEvaluationsService.resolveDeviceType(workOrder));
        Assert.areEqual('Olympus', WarrantyRepairEvaluationsService.resolveManufacturer(workOrder));
        Assert.areEqual('CF-HQ190L', WarrantyRepairEvaluationsService.resolveModel(workOrder));
        Assert.areEqual('SN-WRE-SVC-001', WarrantyRepairEvaluationsService.resolveSerialNumber(workOrder));
        Assert.isNull(WarrantyRepairEvaluationsService.resolveDeviceType(null));
        Assert.isNull(WarrantyRepairEvaluationsService.resolveManufacturer(null));
        Assert.isNull(WarrantyRepairEvaluationsService.resolveModel(null));
        Assert.isNull(WarrantyRepairEvaluationsService.resolveSerialNumber(null));
        Test.stopTest();
    }

    @IsTest
    static void resolvePreviousRepairContext_nullWorkOrderReturnsEmptyContext() {
        Test.startTest();
        WarrantyRepairEvaluationsService.PreviousRepairContext context =
            WarrantyRepairEvaluationsService.resolvePreviousRepairContext(null);
        Test.stopTest();

        Assert.isNull(context.technicianId);
        Assert.isNull(context.repairDate);
    }

    @IsTest
    static void buildPreviousWorkPerformedDescription_usesProductDescription() {
        WorkOrder priorWorkOrder = [
            SELECT Id, Pricebook2Id
            FROM WorkOrder
            WHERE Subject = 'WRE Service Prior Repair WO'
            LIMIT 1
        ];
        Id repairCodeRtId = WorkOrderLineItemsService.getRepairCodeRecordTypeId();
        Assert.isNotNull(repairCodeRtId, 'Repair Code record type is required.');

        Product2 categoryProduct = new Product2(
            Name = 'CAT-NAME-SHOULD-NOT-APPEAR',
            ProductCode = 'WRE-CAT-DESC-001',
            Description = 'Category description line',
            ProductType__c = 'Category Code',
            IsActive = true
        );
        Product2 serviceProduct = new Product2(
            Name = 'SRV-NAME-SHOULD-NOT-APPEAR',
            ProductCode = 'WRE-SRV-DESC-001',
            Description = 'Service description line',
            ProductType__c = 'Service Code',
            IsActive = true
        );
        insert new List<Product2>{ categoryProduct, serviceProduct };

        insert new List<PricebookEntry>{
            new PricebookEntry(
                Pricebook2Id = priorWorkOrder.Pricebook2Id,
                Product2Id = categoryProduct.Id,
                UnitPrice = 1,
                IsActive = true
            ),
            new PricebookEntry(
                Pricebook2Id = priorWorkOrder.Pricebook2Id,
                Product2Id = serviceProduct.Id,
                UnitPrice = 1,
                IsActive = true
            )
        };
        Map<Id, Id> productToPricebookEntryId = new Map<Id, Id>();
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id
            FROM PricebookEntry
            WHERE
                Pricebook2Id = :priorWorkOrder.Pricebook2Id
                AND Product2Id IN :new Set<Id>{ categoryProduct.Id, serviceProduct.Id }
        ]) {
            productToPricebookEntryId.put(pbe.Product2Id, pbe.Id);
        }

        insert new List<WorkOrderLineItem>{
            new WorkOrderLineItem(
                WorkOrderId = priorWorkOrder.Id,
                RecordTypeId = repairCodeRtId,
                PricebookEntryId = productToPricebookEntryId.get(categoryProduct.Id),
                ProductDescription__c = categoryProduct.Description,
                Quantity = 1,
                Status = 'Approved'
            ),
            new WorkOrderLineItem(
                WorkOrderId = priorWorkOrder.Id,
                RecordTypeId = repairCodeRtId,
                PricebookEntryId = productToPricebookEntryId.get(serviceProduct.Id),
                ProductDescription__c = serviceProduct.Description,
                Quantity = 1,
                Status = 'Approved'
            )
        };

        Test.startTest();
        String result = WarrantyRepairEvaluationsService.buildPreviousWorkPerformedDescription(
            priorWorkOrder.Id
        );
        Test.stopTest();

        Assert.areEqual(
            'Category description line\nService description line',
            result,
            'Previous work performed should concatenate Product descriptions, not names.'
        );
    }

    @IsTest
    static void resolvePreviousRepairContext_usesInstrumentsPriorWorkOrderForIeAsset() {
        adb_Account accountBuilder = new adb_Account()
            .name('WRE IE Asset Prior Account')
            .systemId('LEG-WRE-IE-01')
            .sourceSystemId('TEST-ORACLE-WRE-IE-001')
            .orgIds('82');

        adb_Product2 assetProduct = new adb_Product2()
            .name('WRE IE Asset Product')
            .productCode('WRE-IE-ASSET-001')
            .productType('Service Asset')
            .productLine('INSTRUMENTS')
            .manufacturer('STERIS')
            .model('STIRRUP-TEST');

        adb_Asset assetBuilder = new adb_Asset()
            .name('WRE IE Asset')
            .account(accountBuilder)
            .product(assetProduct)
            .serialNumber('SN-WRE-IE-001');

        Date priorShipDate = Date.today().addDays(-12);

        adb_WorkOrder priorWorkOrderBuilder = new adb_WorkOrder()
            .account(accountBuilder)
            .asset(assetBuilder)
            .status('Closed')
            .subject('WRE IE Prior Instruments WO')
            .setRecordType('RepairCenterInstruments')
            .actualShipDate(priorShipDate);
        priorWorkOrderBuilder.persist();

        WorkOrder priorWorkOrder = (WorkOrder) priorWorkOrderBuilder.record;
        update new WorkOrder(
            Id = priorWorkOrder.Id,
            PreviousReturnOrder__c = 'RO-PRIOR-IE-001'
        );

        Id wahRecordTypeId = Schema.SObjectType.WOAssignmentHistory__c.getRecordTypeInfosByDeveloperName()
            .get('RepairCenter')
            ?.getRecordTypeId();
        WOAssignmentHistory__c closedAssignment = new WOAssignmentHistory__c(
            WorkOrder__c = priorWorkOrder.Id,
            Type__c = 'Technician',
            Technician__c = UserInfo.getUserId(),
            StartDateTime__c = Datetime.now().addDays(-13),
            EndDateTime__c = Datetime.now().addDays(-12)
        );
        if (wahRecordTypeId != null) {
            closedAssignment.RecordTypeId = wahRecordTypeId;
        }
        insert closedAssignment;

        adb_WorkOrder currentWorkOrderBuilder = new adb_WorkOrder()
            .account(accountBuilder)
            .asset(assetBuilder)
            .status('Repair')
            .subject('WRE IE Current Instruments WO')
            .setRecordType('RepairCenterInstruments');
        currentWorkOrderBuilder.persist();

        WorkOrder currentWorkOrder = WorkOrdersSelector.selectForWarrantyRepairEvaluationById(
            ((WorkOrder) currentWorkOrderBuilder.record).Id
        );

        Test.startTest();
        WarrantyRepairEvaluationsService.PreviousRepairContext context =
            WarrantyRepairEvaluationsService.resolvePreviousRepairContext(currentWorkOrder);
        Test.stopTest();

        Assert.areEqual(priorShipDate, context.repairDate, 'IE asset should use prior Instruments ship date.');
        Assert.areEqual(
            UserInfo.getUserId(),
            context.technicianId,
            'IE asset should use closed Technician assignment on prior Instruments WO.'
        );
        Assert.areEqual(
            'RO-PRIOR-IE-001',
            context.originalReturnOrder,
            'IE asset should use prior Instruments original return order.'
        );
    }

    @IsTest
    static void saveEvaluation_allowsMissingPreviousRepairFieldsForInstrumentNonAsset() {
        adb_Account accountBuilder = new adb_Account()
            .name('WRE IE Non-Asset Account')
            .systemId('LEG-WRE-NA-01')
            .sourceSystemId('TEST-ORACLE-WRE-NA-001')
            .orgIds('82');

        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .account(accountBuilder)
            .status('Evaluate & Quote')
            .subject('WRE IE Non-Asset WO')
            .setRecordType('RepairCenterInstruments');
        workOrderBuilder.persist();

        WorkOrder workOrder = (WorkOrder) workOrderBuilder.record;
        update new WorkOrder(
            Id = workOrder.Id,
            Description = 'Tray item return',
            QuantityReceived__c = 2
        );

        WarrantyRepairEvaluation__c evaluation =
            buildValidEvaluationWithoutAssetPreviousRepairFields(workOrder.Id);

        Test.startTest();
        List<WarrantyRepairEvaluation__c> insertedRows =
            WarrantyRepairEvaluationsService.saveEvaluation(evaluation);
        Test.stopTest();

        Assert.areEqual(1, insertedRows.size());
        WarrantyRepairEvaluation__c persisted = [
            SELECT
                OriginalReturnOrder__c,
                PreviousRepairQCTechnician__c,
                PreviousRepairDate__c,
                PreviousWorkPerformed__c
            FROM WarrantyRepairEvaluation__c
            WHERE Id = :insertedRows[0].Id
        ];
        Assert.isNull(persisted.OriginalReturnOrder__c);
        Assert.isNull(persisted.PreviousRepairQCTechnician__c);
        Assert.isNull(persisted.PreviousRepairDate__c);
        Assert.isNull(persisted.PreviousWorkPerformed__c);
    }

    @IsTest
    static void saveEvaluation_requiresPreviousRepairFieldsForInstrumentAsset() {
        adb_Account accountBuilder = new adb_Account()
            .name('WRE IE Asset Required Account')
            .systemId('LEG-WRE-AR-01')
            .sourceSystemId('TEST-ORACLE-WRE-AR-001')
            .orgIds('82');

        adb_Product2 assetProduct = new adb_Product2()
            .name('WRE IE Asset Required Product')
            .productCode('WRE-IE-AR-001')
            .productType('Service Asset')
            .productLine('INSTRUMENTS')
            .manufacturer('STERIS')
            .model('TRAY-TEST');

        adb_Asset assetBuilder = new adb_Asset()
            .name('WRE IE Asset Required Asset')
            .account(accountBuilder)
            .product(assetProduct)
            .serialNumber('SN-WRE-IE-AR-001');

        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .account(accountBuilder)
            .asset(assetBuilder)
            .status('Repair')
            .subject('WRE IE Asset Required WO')
            .setRecordType('RepairCenterInstruments');
        workOrderBuilder.persist();

        WorkOrder workOrder = (WorkOrder) workOrderBuilder.record;
        WarrantyRepairEvaluation__c evaluation = buildValidEvaluation(workOrder.Id);
        evaluation.OriginalReturnOrder__c = null;

        Boolean threw = false;
        Test.startTest();
        try {
            WarrantyRepairEvaluationsService.saveEvaluation(evaluation);
        } catch (WarrantyRepairEvaluationsService.WarrantyRepairEvaluationsServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('Original Return Order'), e.getMessage());
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Expected Original Return Order validation for asset Instrument WO.');
    }

    @IsTest
    static void assertNoEvaluationsLinkedToWorkOrderLineItems_emptyAndBlocked() {
        WarrantyRepairEvaluationsService.assertNoEvaluationsLinkedToWorkOrderLineItems(null);
        WarrantyRepairEvaluationsService.assertNoEvaluationsLinkedToWorkOrderLineItems(new Set<Id>());

        WorkOrder workOrder = getCurrentWorkOrder();
        Id productServicedRtId = Schema.SObjectType.WorkOrderLineItem.getRecordTypeInfosByDeveloperName()
            .get('ProductServiced')
            ?.getRecordTypeId();
        Assert.isNotNull(productServicedRtId);

        Product2 product = new Product2(
            Name = 'WRE Assert Product',
            ProductCode = 'WRE-ASSERT-1',
            IsActive = true,
            DeviceType__c = 'ENDOSCOPE',
            Manufacturer__c = 'Olympus',
            Model__c = 'CF-TEST'
        );
        insert product;
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );
        insert pbe;
        WorkOrderLineItem psLine = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            RecordTypeId = productServicedRtId,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            SerialNumber__c = 'SN-ASSERT-1'
        );
        insert psLine;

        WarrantyRepairEvaluation__c evaluation = buildValidEvaluation(workOrder.Id);
        evaluation.WorkOrderLineItem__c = psLine.Id;
        insert evaluation;

        Boolean threw = false;
        try {
            WarrantyRepairEvaluationsService.assertNoEvaluationsLinkedToWorkOrderLineItems(
                new Set<Id>{ psLine.Id }
            );
        } catch (WarrantyRepairEvaluationsService.WarrantyRepairEvaluationsServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('cannot be deleted'));
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void deleteByWorkOrderLineItemIds_deletesLinkedEvaluations() {
        WarrantyRepairEvaluationsService.deleteByWorkOrderLineItemIds(null);
        WarrantyRepairEvaluationsService.deleteByWorkOrderLineItemIds(new Set<Id>());

        WorkOrder workOrder = getCurrentWorkOrder();
        Id productServicedRtId = Schema.SObjectType.WorkOrderLineItem.getRecordTypeInfosByDeveloperName()
            .get('ProductServiced')
            ?.getRecordTypeId();
        Product2 product = new Product2(
            Name = 'WRE Delete Product',
            ProductCode = 'WRE-DEL-1',
            IsActive = true
        );
        insert product;
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );
        insert pbe;
        WorkOrderLineItem psLine = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            RecordTypeId = productServicedRtId,
            PricebookEntryId = pbe.Id,
            Quantity = 1
        );
        insert psLine;

        WarrantyRepairEvaluation__c evaluation = buildValidEvaluation(workOrder.Id);
        evaluation.WorkOrderLineItem__c = psLine.Id;
        insert evaluation;

        Test.startTest();
        WarrantyRepairEvaluationsService.deleteByWorkOrderLineItemIds(new Set<Id>{ psLine.Id });
        Test.stopTest();

        Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM WarrantyRepairEvaluation__c
                WHERE Id = :evaluation.Id
            ]
        );
    }

    @IsTest
    static void applyProductServicedDefaults_andResolveHelpers() {
        WorkOrder workOrder = getCurrentWorkOrder();
        Id productServicedRtId = Schema.SObjectType.WorkOrderLineItem.getRecordTypeInfosByDeveloperName()
            .get('ProductServiced')
            ?.getRecordTypeId();
        Product2 product = new Product2(
            Name = 'WRE Defaults Product',
            ProductCode = 'WRE-DEF-1',
            IsActive = true,
            ProductLine__c = 'INSTRUMENTS',
            Manufacturer__c = 'STERIS',
            Model__c = 'Model-X'
        );
        insert product;
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );
        insert pbe;
        WorkOrderLineItem psLine = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            RecordTypeId = productServicedRtId,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            SerialNumber__c = 'SN-DEF-9',
            ProductDescription__c = 'Desc fallback'
        );
        insert psLine;

        WarrantyRepairEvaluation__c evaluation = new WarrantyRepairEvaluation__c(
            WorkOrder__c = workOrder.Id
        );
        WarrantyRepairEvaluationsService.applyProductServicedDefaults(evaluation, null);
        WarrantyRepairEvaluationsService.applyProductServicedDefaults(evaluation, psLine.Id);

        Assert.areEqual(psLine.Id, evaluation.WorkOrderLineItem__c);
        Assert.areEqual(1, evaluation.ItemCount__c);
        Assert.areEqual('INSTRUMENTS', evaluation.DeviceType__c);
        Assert.areEqual('STERIS', evaluation.ManufacturerOfTheDeviceInstrument__c);
        Assert.areEqual('Model-X', evaluation.ModelNumberOfTheDeviceInstrument__c);
        Assert.areEqual('SN-DEF-9', evaluation.SerialNumberOfTheDeviceInstrument__c);

        Assert.isNull(WarrantyRepairEvaluationsService.resolveDeviceType(null));
        Assert.isNull(WarrantyRepairEvaluationsService.resolveManufacturer(null));
        Assert.isNull(WarrantyRepairEvaluationsService.resolveModel(null));
        Assert.isNull(WarrantyRepairEvaluationsService.resolveSerialNumber(null));
        Assert.isNull(WarrantyRepairEvaluationsService.resolveOriginalReturnOrderFromWorkOrder(null));
        Assert.isNull(WarrantyRepairEvaluationsService.buildPreviousWorkPerformedDescription(null));
        Assert.isNull(WarrantyRepairEvaluationsService.resolveRepairCodeLineDescription(null));
        Assert.isNull(WarrantyRepairEvaluationsService.resolvePriorRepairWorkOrderRecordTypeId(null));
        Assert.isNull(WarrantyRepairEvaluationsService.resolveWorkOrderIdForSave(null));

        String label = WarrantyRepairEvaluationsService.resolveDeviceTypeFieldLabel(
            new WarrantyRepairEvaluation__c(WorkOrderLineItem__c = psLine.Id),
            new WorkOrder(AssetId = null)
        );
        Assert.areEqual('Instrument Type', label);
    }

    @IsTest
    static void buildEvaluationForForm_withProductServicedLineSeedsDefaults() {
        WorkOrder workOrder = getCurrentWorkOrder();
        Id productServicedRtId = Schema.SObjectType.WorkOrderLineItem.getRecordTypeInfosByDeveloperName()
            .get('ProductServiced')
            ?.getRecordTypeId();
        Product2 product = new Product2(
            Name = 'WRE Form Seed Product',
            ProductCode = 'WRE-SEED-1',
            IsActive = true,
            DeviceType__c = 'PROBE',
            Manufacturer__c = 'Acme',
            Model__c = 'P-100'
        );
        insert product;
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );
        insert pbe;
        WorkOrderLineItem psLine = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            RecordTypeId = productServicedRtId,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            SerialNumber__c = 'SN-SEED-1'
        );
        insert psLine;

        Test.startTest();
        WarrantyRepairEvaluation__c shell =
            WarrantyRepairEvaluationsService.buildEvaluationForForm(
                workOrder.Id,
                null,
                psLine.Id
            );
        Test.stopTest();

        Assert.areEqual(psLine.Id, shell.WorkOrderLineItem__c);
        Assert.isTrue(
            shell.SerialNumberOfTheDeviceInstrument__c == 'SN-SEED-1' ||
                shell.SerialNumberOfTheDeviceInstrument__c == 'SN-WRE-SVC-001',
            'Expected serial from WOLI or WO asset, got: ' +
                shell.SerialNumberOfTheDeviceInstrument__c
        );
    }

    @IsTest
    static void resolveDeviceType_fallbacksAndProductDescriptionDefaults() {
        Product2 productWithDeviceType = new Product2(DeviceType__c = 'DEVICE-TYPE-A');
        Asset assetWithDeviceType = new Asset();
        assetWithDeviceType.Product2 = productWithDeviceType;
        WorkOrder woDeviceType = new WorkOrder();
        woDeviceType.Asset = assetWithDeviceType;
        Assert.areEqual(
            'DEVICE-TYPE-A',
            WarrantyRepairEvaluationsService.resolveDeviceType(woDeviceType)
        );

        WorkOrder woProductLineF = (WorkOrder) JSON.deserialize(
            '{"ProductLine_f__c":"PRODUCT-LINE-F"}',
            WorkOrder.class
        );
        Assert.areEqual(
            'PRODUCT-LINE-F',
            WarrantyRepairEvaluationsService.resolveDeviceType(woProductLineF)
        );

        Asset assetCalculated = (Asset) JSON.deserialize(
            '{"ProductLineCalculated__c":"CALC-LINE"}',
            Asset.class
        );
        WorkOrder woCalculated = new WorkOrder();
        woCalculated.Asset = assetCalculated;
        Assert.areEqual(
            'CALC-LINE',
            WarrantyRepairEvaluationsService.resolveDeviceType(woCalculated)
        );

        Product2 productLineOnly = new Product2(ProductLine__c = 'PROD-LINE');
        Asset assetProductLine = new Asset();
        assetProductLine.Product2 = productLineOnly;
        WorkOrder woProductLine = new WorkOrder();
        woProductLine.Asset = assetProductLine;
        Assert.areEqual(
            'PROD-LINE',
            WarrantyRepairEvaluationsService.resolveDeviceType(woProductLine)
        );

        Assert.areEqual(
            'Device Type',
            WarrantyRepairEvaluationsService.resolveDeviceTypeFieldLabel(
                new WarrantyRepairEvaluation__c(),
                new WorkOrder(AssetId = UserInfo.getUserId())
            )
        );

        WorkOrderLineItem descLine = new WorkOrderLineItem();
        descLine.ProductDescription__c = 'Desc only model';
        Assert.areEqual(
            'Desc only model',
            WarrantyRepairEvaluationsService.resolveRepairCodeLineDescription(descLine)
        );

        WorkOrderLineItem product2DescLine = new WorkOrderLineItem();
        product2DescLine.Product2 = new Product2(Description = 'P2 description');
        Assert.areEqual(
            'P2 description',
            WarrantyRepairEvaluationsService.resolveRepairCodeLineDescription(product2DescLine)
        );

        WorkOrder workOrder = getCurrentWorkOrder();
        Id productServicedRtId = Schema.SObjectType.WorkOrderLineItem.getRecordTypeInfosByDeveloperName()
            .get('ProductServiced')
            ?.getRecordTypeId();
        Product2 product = new Product2(
            Name = 'WRE Desc Model Product',
            ProductCode = 'WRE-DESC-1',
            IsActive = true,
            DeviceType__c = 'CAMERA',
            Manufacturer__c = 'Acme'
        );
        insert product;
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );
        insert pbe;
        WorkOrderLineItem psLine = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            RecordTypeId = productServicedRtId,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            ProductDescription__c = 'Fallback model text'
        );
        insert psLine;

        WarrantyRepairEvaluation__c evaluation = new WarrantyRepairEvaluation__c(
            WorkOrder__c = workOrder.Id
        );
        WarrantyRepairEvaluationsService.applyProductServicedDefaults(evaluation, psLine.Id);
        Assert.areEqual('CAMERA', evaluation.DeviceType__c);
        Assert.areEqual('Fallback model text', evaluation.ModelNumberOfTheDeviceInstrument__c);
    }

    @IsTest
    static void saveEvaluation_dmlFailureWrapsException() {
        WorkOrder workOrder = getCurrentWorkOrder();
        WarrantyRepairEvaluation__c evaluation = buildValidEvaluation(workOrder.Id);
        insert evaluation;

        // Force DML failure via a deleted Id so validation still passes pre-DML.
        WarrantyRepairEvaluation__c payload = buildValidEvaluation(workOrder.Id);
        payload.Id = evaluation.Id;
        delete evaluation;

        Boolean threw = false;
        Test.startTest();
        try {
            WarrantyRepairEvaluationsService.saveEvaluation(payload);
        } catch (WarrantyRepairEvaluationsService.WarrantyRepairEvaluationsServiceException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('Unable to save') ||
                    e.getMessage().contains('Work Order is required'),
                e.getMessage()
            );
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Expected exception when updating deleted evaluation.');
    }
}