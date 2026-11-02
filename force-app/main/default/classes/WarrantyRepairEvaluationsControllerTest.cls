/**
 * @description Tests for WarrantyRepairEvaluationsController (GW-3891 / GW-3400).
 */
@IsTest
private class WarrantyRepairEvaluationsControllerTest {
    private static Id fakeWorkOrderId() {
        // Use a checksum-valid org Id so form JSON deserialize does not throw "malformed id".
        return UserInfo.getUserId();
    }

    private static WarrantyRepairEvaluation__c wreWithName(String name) {
        return (WarrantyRepairEvaluation__c) JSON.deserialize(
            '{"attributes":{"type":"WarrantyRepairEvaluation__c"},"Name":"' +
                name +
                '","Disposition__c":"Repair"}',
            WarrantyRepairEvaluation__c.class
        );
    }

    private static WorkOrder workOrderWithNumber(Id workOrderId, String workOrderNumber) {
        return (WorkOrder) JSON.deserialize(
            '{"attributes":{"type":"WorkOrder"},"Id":"' +
                String.valueOf(workOrderId) +
                '","WorkOrderNumber":"' +
                workOrderNumber +
                '"}',
            WorkOrder.class
        );
    }

    private class StubClient implements WarrantyRepairEvaluationsController.IWarrantyRepairEvaluationsClient {
        public List<WarrantyRepairEvaluation__c> getEvaluationsByWorkOrderId(
            Id workOrderId,
            Id workOrderLineItemId
        ) {
            WarrantyRepairEvaluation__c row = wreWithName('WRE-1');
            row.Date__c = Date.today();
            row.WorkOrderLineItem__c = workOrderLineItemId;
            return new List<WarrantyRepairEvaluation__c>{ row };
        }

        public WarrantyRepairEvaluation__c buildEvaluationForForm(
            Id workOrderId,
            Id recordId,
            Id workOrderLineItemId
        ) {
            WarrantyRepairEvaluation__c evaluation = wreWithName('WRE-Form');
            evaluation.WorkOrder__c = workOrderId;
            evaluation.WorkOrderLineItem__c = workOrderLineItemId;
            evaluation.ReasonForReturn__c = 'Damaged';
            return evaluation;
        }

        public List<WarrantyRepairEvaluation__c> saveEvaluation(
            WarrantyRepairEvaluation__c evaluation
        ) {
            Assert.isNotNull(evaluation);
            Assert.isNotNull(evaluation.WorkOrder__c);
            return new List<WarrantyRepairEvaluation__c>{ wreWithName('WRE-Saved') };
        }

        public WorkOrder getWorkOrderForForm(Id workOrderId) {
            return workOrderWithNumber(workOrderId, 'WO-1001');
        }

        public WorkOrderLineItem getLineItemForForm(Id workOrderLineItemId) {
            return new WorkOrderLineItem(Id = workOrderLineItemId, Quantity = 3);
        }
    }

    private class MissingWorkOrderClient implements WarrantyRepairEvaluationsController.IWarrantyRepairEvaluationsClient {
        public List<WarrantyRepairEvaluation__c> getEvaluationsByWorkOrderId(
            Id workOrderId,
            Id workOrderLineItemId
        ) {
            return new List<WarrantyRepairEvaluation__c>();
        }

        public WarrantyRepairEvaluation__c buildEvaluationForForm(
            Id workOrderId,
            Id recordId,
            Id workOrderLineItemId
        ) {
            return null;
        }

        public List<WarrantyRepairEvaluation__c> saveEvaluation(
            WarrantyRepairEvaluation__c evaluation
        ) {
            return new List<WarrantyRepairEvaluation__c>();
        }

        public WorkOrder getWorkOrderForForm(Id workOrderId) {
            return null;
        }

        public WorkOrderLineItem getLineItemForForm(Id workOrderLineItemId) {
            return null;
        }
    }

    private class ThrowingClient implements WarrantyRepairEvaluationsController.IWarrantyRepairEvaluationsClient {
        public List<WarrantyRepairEvaluation__c> getEvaluationsByWorkOrderId(
            Id workOrderId,
            Id workOrderLineItemId
        ) {
            throw new WarrantyRepairEvaluationsService.WarrantyRepairEvaluationsServiceException(
                'Unable to load Warranty Repair Evaluations.'
            );
        }

        public WarrantyRepairEvaluation__c buildEvaluationForForm(
            Id workOrderId,
            Id recordId,
            Id workOrderLineItemId
        ) {
            throw new WarrantyRepairEvaluationsService.WarrantyRepairEvaluationsServiceException(
                'Unable to build form.'
            );
        }

        public List<WarrantyRepairEvaluation__c> saveEvaluation(
            WarrantyRepairEvaluation__c evaluation
        ) {
            throw new WarrantyRepairEvaluationsService.WarrantyRepairEvaluationsServiceException(
                'Unable to save evaluation.'
            );
        }

        public WorkOrder getWorkOrderForForm(Id workOrderId) {
            return workOrderWithNumber(workOrderId, 'WO-ERR');
        }

        public WorkOrderLineItem getLineItemForForm(Id workOrderLineItemId) {
            return null;
        }
    }

    @IsTest
    private static void testGetWarrantyRepairEvaluationsPositive() {
        // Setup
        Id workOrderId = fakeWorkOrderId();
        WarrantyRepairEvaluationsController.clientOverride = new StubClient();

        // Given / When
        Test.startTest();
        List<WarrantyRepairEvaluationsController.WarrantyRepairEvaluationRow> rows =
            WarrantyRepairEvaluationsController.getWarrantyRepairEvaluations(workOrderId, null);
        Test.stopTest();

        // Then
        Assert.areEqual(1, rows.size());
        Assert.areEqual('WRE-1', rows[0].name);
        Assert.areEqual('Repair', rows[0].disposition);
    }

    @IsTest
    private static void testGetWarrantyRepairEvaluationFormPositive() {
        // Setup
        Id workOrderId = fakeWorkOrderId();
        WarrantyRepairEvaluationsController.clientOverride = new StubClient();

        // Given / When
        Test.startTest();
        WarrantyRepairEvaluationsController.WarrantyRepairEvaluationForm form =
            WarrantyRepairEvaluationsController.getWarrantyRepairEvaluationForm(
                workOrderId,
                null,
                null
            );
        Test.stopTest();

        // Then
        Assert.areEqual(workOrderId, form.workOrderId);
        Assert.areEqual('WO-1001', form.workOrderNumber);
        Assert.areEqual('Damaged', form.reasonForReturn);
        Assert.areEqual(1, form.maxEvaluationCount);
        Assert.isFalse(form.serialNumberRequired);
        Assert.isNotNull(form.yesNoOptions);
        Assert.isTrue(form.yesNoOptions.size() >= 2);
    }

    @IsTest
    private static void testGetWarrantyRepairEvaluationFormWorkOrderMissing() {
        // Setup
        Id workOrderId = fakeWorkOrderId();
        WarrantyRepairEvaluationsController.clientOverride = new MissingWorkOrderClient();
        Boolean threw = false;

        // Given / When
        Test.startTest();
        try {
            WarrantyRepairEvaluationsController.getWarrantyRepairEvaluationForm(
                workOrderId,
                null,
                null
            );
        } catch (AuraHandledException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('Work Order was not found.'));
        }
        Test.stopTest();

        // Then
        Assert.isTrue(threw);
    }

    @IsTest
    private static void testSaveWarrantyRepairEvaluationPositive() {
        // Setup
        Id workOrderId = fakeWorkOrderId();
        WarrantyRepairEvaluationsController.clientOverride = new StubClient();
        WarrantyRepairEvaluationsController.WarrantyRepairEvaluationForm form =
            new WarrantyRepairEvaluationsController.WarrantyRepairEvaluationForm();
        form.workOrderId = workOrderId;
        form.reasonForReturn = 'Damaged';
        form.disposition = 'Repair';
        String formJson = JSON.serialize(form);

        // Given / When
        Test.startTest();
        List<WarrantyRepairEvaluationsController.WarrantyRepairEvaluationRow> rows =
            WarrantyRepairEvaluationsController.saveWarrantyRepairEvaluation(workOrderId, formJson);
        Test.stopTest();

        // Then
        Assert.areEqual(1, rows.size());
        Assert.areEqual('WRE-Saved', rows[0].name);
    }

    @IsTest
    private static void testSaveWarrantyRepairEvaluationBlankForm() {
        // Setup
        Id workOrderId = fakeWorkOrderId();
        WarrantyRepairEvaluationsController.clientOverride = new StubClient();
        Boolean threw = false;

        // Given / When
        Test.startTest();
        try {
            WarrantyRepairEvaluationsController.saveWarrantyRepairEvaluation(workOrderId, '');
        } catch (AuraHandledException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('form data is required'));
        }
        Test.stopTest();

        // Then
        Assert.isTrue(threw);
    }

    @IsTest
    private static void testGetWarrantyRepairEvaluationsServiceException() {
        // Setup
        Id workOrderId = fakeWorkOrderId();
        WarrantyRepairEvaluationsController.clientOverride = new ThrowingClient();
        Boolean threw = false;

        // Given / When
        Test.startTest();
        try {
            WarrantyRepairEvaluationsController.getWarrantyRepairEvaluations(workOrderId, null);
        } catch (AuraHandledException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('Unable to load'));
        }
        Test.stopTest();

        // Then
        Assert.isTrue(threw);
    }
}