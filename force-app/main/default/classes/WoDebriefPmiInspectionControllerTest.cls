/**
 * @description Tests for CRSS PMI inspection measurements and the P1 outcome.
 * @see WoDebriefPmiInspectionController
 */
@IsTest
private class WoDebriefPmiInspectionControllerTest {
    /**
     * @description A reading that matches the default passes when the standard has no bounds.
     */
    @IsTest
    static void evaluateStatus_noBounds_matchingValuePasses() {
        System.assertEquals(
            'Pass',
            WoDebriefPmiInspectionController.evaluateStatus('10', '10', null, null)
        );
        System.assertEquals(
            'Pass',
            WoDebriefPmiInspectionController.evaluateStatus('10.0', '10', null, null)
        );
    }

    /**
     * @description Anything other than the default fails when the standard has no bounds.
     */
    @IsTest
    static void evaluateStatus_noBounds_otherValueFails() {
        System.assertEquals(
            'Failed',
            WoDebriefPmiInspectionController.evaluateStatus('11', '10', null, null)
        );
    }

    /**
     * @description A reading inside minimum and maximum passes. A reading outside fails.
     */
    @IsTest
    static void evaluateStatus_bounds_checksRange() {
        System.assertEquals(
            'Pass',
            WoDebriefPmiInspectionController.evaluateStatus('15', '10', '10', '20')
        );
        System.assertEquals(
            'Failed',
            WoDebriefPmiInspectionController.evaluateStatus('9', '10', '10', '20')
        );
        System.assertEquals(
            'Failed',
            WoDebriefPmiInspectionController.evaluateStatus('21', '10', '10', '20')
        );
        System.assertEquals(
            'Pass',
            WoDebriefPmiInspectionController.evaluateStatus('20', '10', null, '20')
        );
    }

    /**
     * @description A blank reading is not scored.
     */
    @IsTest
    static void evaluateStatus_blankValue_returnsNull() {
        System.assertEquals(
            null,
            WoDebriefPmiInspectionController.evaluateStatus('  ', '10', null, null)
        );
    }

    /**
     * @description A product with no Device Standards does not require measurements.
     */
    @IsTest
    static void listSatisfiedLineIds_noStandards_includesLine() {
        LineContext context = createLine(null);

        Test.startTest();
        List<Id> satisfied = WoDebriefPmiInspectionController.listSatisfiedLineIds(context.workOrderId);
        Test.stopTest();

        System.assertEquals(1, satisfied.size());
        System.assertEquals(context.lineId, satisfied[0]);
    }

    /**
     * @description The popup explains that a product with no Device Standards has nothing to fill.
     */
    @IsTest
    static void loadInspection_noStandards_returnsMessage() {
        LineContext context = createLine(null);

        Test.startTest();
        WoDebriefPmiInspectionController.InspectionContext inspection =
            WoDebriefPmiInspectionController.loadInspection(context.lineId);
        Test.stopTest();

        System.assertEquals(false, inspection.hasStandards);
        System.assertEquals('There is nothing to fill for this asset.', inspection.emptyMessage);
        System.assertEquals(0, inspection.rows.size());
        System.assertEquals(false, inspection.workOrderClosed);
    }

    /**
     * @description A failed reading sets the line outcome to Performance Standard Not Met (P1).
     */
    @IsTest
    static void saveInspection_failedReading_setsP1() {
        LineContext context = createLine('Passed');
        useStandard(context.productId, 'Field of View', '10', null, null);
        WoDebriefPmiInspectionController.MeasurementInput input = standardInput('11', 'Checked');

        Test.startTest();
        WoDebriefPmiInspectionController.SaveResult result =
            WoDebriefPmiInspectionController.saveInspection(
                context.lineId,
                new List<WoDebriefPmiInspectionController.MeasurementInput>{ input }
            );
        Test.stopTest();

        System.assertEquals(true, result.hasFailure);
        System.assertEquals(WoDebriefPmiInspectionController.OUTCOME_P1, result.inspectionOutcome);
        System.assertEquals(true, result.outcomeUpdated);
        System.assertEquals(true, result.checklistComplete);
        Measurement__c saved = [
            SELECT Name, MeasurementType__c, ReferenceValue__c, MeasurementValue__c,
                Comments__c, Status__c, Asset__c, WorkOrder__c, WorkOrderLineItem__c, MeasurementDate__c
            FROM Measurement__c
            WHERE WorkOrderLineItem__c = :context.lineId
        ];
        System.assertEquals('Field of View', saved.Name);
        System.assertEquals('PMI', saved.MeasurementType__c);
        System.assertEquals('10', saved.ReferenceValue__c);
        System.assertEquals('11', saved.MeasurementValue__c);
        System.assertEquals('Checked', saved.Comments__c);
        System.assertEquals('Failed', saved.Status__c);
        System.assertEquals(context.assetId, saved.Asset__c);
        System.assertEquals(context.workOrderId, saved.WorkOrder__c);
        System.assertEquals(Date.today(), saved.MeasurementDate__c);
        WorkOrderLineItem line = [
            SELECT InspectionOutcome__c
            FROM WorkOrderLineItem
            WHERE Id = :context.lineId
        ];
        System.assertEquals(WoDebriefPmiInspectionController.OUTCOME_P1, line.InspectionOutcome__c);
    }

    /**
     * @description An all-pass save clears a P1 outcome back to Passed and leaves any other outcome unchanged.
     */
    @IsTest
    static void saveInspection_allPass_clearsP1Only() {
        LineContext failedLine = createLine(WoDebriefPmiInspectionController.OUTCOME_P1);
        useStandard(failedLine.productId, 'Field of View', '10', null, null);

        Test.startTest();
        WoDebriefPmiInspectionController.SaveResult cleared =
            WoDebriefPmiInspectionController.saveInspection(
                failedLine.lineId,
                new List<WoDebriefPmiInspectionController.MeasurementInput>{ standardInput('10', null) }
            );
        Test.stopTest();

        System.assertEquals(false, cleared.hasFailure);
        System.assertEquals('Passed', cleared.inspectionOutcome);

        WoDebriefPmiInspectionController.testStandardsById = null;
        LineContext otherLine = createLine('Recommended for Repair');
        useStandard(otherLine.productId, 'Field of View', '10', null, null);
        WoDebriefPmiInspectionController.SaveResult unchanged =
            WoDebriefPmiInspectionController.saveInspection(
                otherLine.lineId,
                new List<WoDebriefPmiInspectionController.MeasurementInput>{ standardInput('10', null) }
            );
        System.assertEquals('Recommended for Repair', unchanged.inspectionOutcome);
        System.assertEquals(false, unchanged.outcomeUpdated);
    }

    /**
     * @description A closed work order cannot be changed.
     */
    @IsTest
    static void saveInspection_closedWorkOrder_throws() {
        LineContext context = createLine(null);
        update new WorkOrder(Id = context.workOrderId, Status = 'Closed');

        try {
            WoDebriefPmiInspectionController.saveInspection(
                context.lineId,
                new List<WoDebriefPmiInspectionController.MeasurementInput>()
            );
            System.assert(false, 'Expected a closed work order to reject the save.');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage().contains('closed'));
        }
    }

    /**
     * @description Non-numeric text matches only when it is the same text. A non-numeric reading fails a numeric range.
     */
    @IsTest
    static void evaluateStatus_textAndNonNumericRange() {
        System.assertEquals(
            'Pass',
            WoDebriefPmiInspectionController.evaluateStatus('OK', 'OK', null, null)
        );
        System.assertEquals(
            'Failed',
            WoDebriefPmiInspectionController.evaluateStatus('OK', 'OK', '1', '5')
        );
        System.assertEquals(
            new List<Id>(),
            WoDebriefPmiInspectionController.listSatisfiedLineIds(null)
        );
    }

    /**
     * @description A product with a Device Standard is not satisfied until that reading is saved.
     *              Saving inside the range stores Pass and a second save updates the same measurement.
     */
    @IsTest
    static void saveInspection_rangeAndReload_updatesSameMeasurement() {
        LineContext context = createLine(null);
        useStandard(context.productId, 'Field of View', '10', '8', '12');

        Test.startTest();
        List<Id> before = WoDebriefPmiInspectionController.listSatisfiedLineIds(context.workOrderId);
        WoDebriefPmiInspectionController.SaveResult saved =
            WoDebriefPmiInspectionController.saveInspection(
                context.lineId,
                new List<WoDebriefPmiInspectionController.MeasurementInput>{ standardInput('9', null) }
            );
        WoDebriefPmiInspectionController.InspectionContext loaded =
            WoDebriefPmiInspectionController.loadInspection(context.lineId);
        List<Id> after = WoDebriefPmiInspectionController.listSatisfiedLineIds(context.workOrderId);

        WoDebriefPmiInspectionController.MeasurementInput updateInput = standardInput('12', 'Updated');
        updateInput.measurementId = loaded.rows[0].measurementId;
        WoDebriefPmiInspectionController.saveInspection(
            context.lineId,
            new List<WoDebriefPmiInspectionController.MeasurementInput>{ updateInput }
        );
        Test.stopTest();

        System.assertEquals(0, before.size());
        System.assertEquals(false, saved.hasFailure);
        System.assertEquals(true, saved.checklistComplete);
        System.assertEquals(null, saved.inspectionOutcome);
        System.assertEquals(1, loaded.rows.size());
        System.assertEquals('Field of View', loaded.rows[0].measurementName);
        System.assertEquals('9', loaded.rows[0].measurementValue);
        System.assertEquals('8', loaded.rows[0].minimumValue);
        System.assertEquals(false, loaded.rows[0].manual);
        System.assertEquals(1, after.size());

        List<Measurement__c> measurements = [
            SELECT MeasurementValue__c, Status__c, Comments__c
            FROM Measurement__c
            WHERE WorkOrderLineItem__c = :context.lineId
        ];
        System.assertEquals(1, measurements.size());
        System.assertEquals('12', measurements[0].MeasurementValue__c);
        System.assertEquals('Pass', measurements[0].Status__c);
        System.assertEquals('Updated', measurements[0].Comments__c);
    }

    /**
     * @description Omitting a Device Standard is rejected.
     */
    @IsTest
    static void saveInspection_missingStandard_throws() {
        LineContext context = createLine(null);
        useStandard(context.productId, 'Field of View', '10', null, null);

        try {
            WoDebriefPmiInspectionController.saveInspection(
                context.lineId,
                new List<WoDebriefPmiInspectionController.MeasurementInput>()
            );
            System.assert(false, 'Expected a missing Device Standard to be rejected.');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage().contains('Field of View'));
        }
    }

    /**
     * @description A blank line id is rejected.
     */
    @IsTest
    static void loadInspection_nullLine_throws() {
        try {
            WoDebriefPmiInspectionController.loadInspection(null);
            System.assert(false, 'Expected a missing line to be rejected.');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage().contains('Save the Product Serviced line'));
        }
    }
    /**
     * @description A manual row requires a name, reference, and value.
     */
    @IsTest
    static void saveInspection_manualRowMissingReference_throws() {
        LineContext context = createLine(null);
        WoDebriefPmiInspectionController.MeasurementInput input =
            new WoDebriefPmiInspectionController.MeasurementInput();
        input.measurementName = 'Extra reading';
        input.measurementValue = '5';

        try {
            WoDebriefPmiInspectionController.saveInspection(
                context.lineId,
                new List<WoDebriefPmiInspectionController.MeasurementInput>{ input }
            );
            System.assert(false, 'Expected a manual row without a reference to be rejected.');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage().contains('required'));
        }
    }

    /**
     * @description A manual reading is stored and shown again as a manual row.
     */
    @IsTest
    static void saveInspection_manualRow_savesAndReloads() {
        LineContext context = createLine(null);
        WoDebriefPmiInspectionController.MeasurementInput input =
            new WoDebriefPmiInspectionController.MeasurementInput();
        input.measurementName = 'Extra reading';
        input.referenceValue = '5';
        input.minimumValue = '4';
        input.maximumValue = '6';
        input.measurementValue = '5';
        input.comments = 'Manual';

        Test.startTest();
        WoDebriefPmiInspectionController.SaveResult result =
            WoDebriefPmiInspectionController.saveInspection(
                context.lineId,
                new List<WoDebriefPmiInspectionController.MeasurementInput>{ input }
            );
        WoDebriefPmiInspectionController.InspectionContext loaded =
            WoDebriefPmiInspectionController.loadInspection(context.lineId);
        Test.stopTest();

        System.assertEquals(false, result.hasFailure);
        System.assertEquals(true, result.checklistComplete);
        System.assertEquals(1, loaded.rows.size());
        System.assertEquals(true, loaded.rows[0].manual);
        System.assertEquals('Extra reading', loaded.rows[0].measurementName);
        System.assertEquals('Pass', loaded.rows[0].status);
    }

    /**
     * @description Creates a CRSS product serviced line. The product has no Device Standards in the org.
     * @param inspectionOutcome Starting Inspection Outcome
     * @return Ids for the new records
     */
    private static LineContext createLine(String inspectionOutcome) {
        String token = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        Account account = new Account(Name = 'PMI ' + token, SourceSystemID__c = 'ORACLE-PMI-' + token);
        insert account;
        Product2 product = new Product2(Name = 'PMI Product ' + token, IsActive = true);
        insert product;
        Asset asset = new Asset(
            Name = 'PMI Asset ' + token,
            AccountId = account.Id,
            Product2Id = product.Id,
            SerialNumber = 'PMI-' + token
        );
        insert asset;
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'PMI ' + token,
            Status = 'New',
            RecordTypeId = Schema.SObjectType.WorkOrder
                .getRecordTypeInfosByDeveloperName()
                .get('CRSSFieldRepair')
                .getRecordTypeId()
        );
        insert workOrder;
        WorkOrderLineItem line = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            AssetId = asset.Id,
            RecordTypeId = Schema.SObjectType.WorkOrderLineItem
                .getRecordTypeInfosByDeveloperName()
                .get('ProductServiced')
                .getRecordTypeId(),
            LineType__c = 'Product Serviced',
            InspectionOutcome__c = inspectionOutcome
        );
        insert line;
        LineContext context = new LineContext();
        context.workOrderId = workOrder.Id;
        context.lineId = line.Id;
        context.assetId = asset.Id;
        context.productId = product.Id;
        return context;
    }

    /**
     * @description Injects one Device Standard for the product.
     * @param productId Asset product
     * @param name Device Standard name
     * @param referenceValue Default value
     * @param minimumValue Minimum, or null
     * @param maximumValue Maximum, or null
     */
    private static void useStandard(
        Id productId,
        String name,
        String referenceValue,
        String minimumValue,
        String maximumValue
    ) {
        WoDebriefPmiInspectionController.DeviceStandard standard =
            new WoDebriefPmiInspectionController.DeviceStandard();
        standard.standardId = (Id) (
            ProductAttributeDefinition.SObjectType.getDescribe().getKeyPrefix() + '000000000001'
        );
        standard.product2Id = productId;
        standard.name = name;
        standard.referenceValue = referenceValue;
        standard.minimumValue = minimumValue;
        standard.maximumValue = maximumValue;
        WoDebriefPmiInspectionController.testStandardsById =
            new Map<Id, WoDebriefPmiInspectionController.DeviceStandard>{
                standard.standardId => standard
            };
    }

    /**
     * @description Submitted Device Standard row using the injected standard Id.
     * @param measurementValue Value entered by the user
     * @param comments Comment
     * @return Save input
     */
    private static WoDebriefPmiInspectionController.MeasurementInput standardInput(
        String measurementValue,
        String comments
    ) {
        WoDebriefPmiInspectionController.MeasurementInput input =
            new WoDebriefPmiInspectionController.MeasurementInput();
        input.standardId = (Id) (
            ProductAttributeDefinition.SObjectType.getDescribe().getKeyPrefix() + '000000000001'
        );
        input.measurementValue = measurementValue;
        input.comments = comments;
        return input;
    }

    /**
     * @description Ids created for one checklist test.
     */
    private class LineContext {
        public Id workOrderId;
        public Id lineId;
        public Id assetId;
        public Id productId;
    }
}