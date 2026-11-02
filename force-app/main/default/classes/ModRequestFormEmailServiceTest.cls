/**
 * @description Tests for ModRequestFormEmailService.
 */
@IsTest(isParallel=false)
private class ModRequestFormEmailServiceTest {
    private static adb_WorkOrder buildInstrumentsWorkOrder(
        adb_Account accountBuilder,
        Boolean isModRequest,
        String modRequestContactEmail
    ) {
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .setRecordType('RepairCenterInstruments')
            .status('Received')
            .account(accountBuilder);
        workOrderBuilder.set(WorkOrder.ModRequest__c, isModRequest);
        workOrderBuilder.set(WorkOrder.SubStatus__c, 'Mod Hold');
        if (String.isNotBlank(modRequestContactEmail)) {
            workOrderBuilder.set(WorkOrder.ModRequestContactEmail__c, modRequestContactEmail);
        }
        return workOrderBuilder;
    }

    @IsTest
    static void testPreviewRequiresEligibleModHoldWorkOrder() {
        // Setup
        // Given
        adb_Account accountBuilder = new adb_Account().name('Mod Request Email Account');
        adb_WorkOrder workOrderBuilder = buildInstrumentsWorkOrder(accountBuilder, false, null);
        workOrderBuilder.persist();

        ModRequestFormEmailService.Request request = new ModRequestFormEmailService.Request();
        request.workOrderId = workOrderBuilder.id;
        request.operation = 'Preview';

        // When
        ModRequestFormEmailService.Response response = ModRequestFormEmailService.process(
            new List<ModRequestFormEmailService.Request>{ request }
        )[0];

        // Then
        System.assertEquals(false, response.eligible, 'Expected ineligible work order.');
        System.assertEquals(false, response.success, 'Expected preview failure for ineligible work order.');
        System.assertNotEquals(null, response.errorMessage, 'Expected an error message.');
    }

    @IsTest
    static void testPreviewBulkRequestsUseConstantQueries() {
        // Setup
        // Given
        adb_Account accountBuilder = new adb_Account().name('Bulk Mod Request Email Account');
        adb_WorkOrder lastWorkOrderBuilder;
        for (Integer recordIndex = 0; recordIndex < 200; recordIndex++) {
            lastWorkOrderBuilder = buildInstrumentsWorkOrder(accountBuilder, false, null);
        }
        lastWorkOrderBuilder.persist();

        List<WorkOrder> workOrders = [
            SELECT Id
            FROM WorkOrder
            WHERE AccountId = :accountBuilder.id
        ];

        List<ModRequestFormEmailService.Request> requests =
            new List<ModRequestFormEmailService.Request>();
        for (WorkOrder workOrder : workOrders) {
            ModRequestFormEmailService.Request request =
                new ModRequestFormEmailService.Request();
            request.workOrderId = workOrder.Id;
            request.operation = 'Preview';
            requests.add(request);
        }

        // When
        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        List<ModRequestFormEmailService.Response> responses =
            ModRequestFormEmailService.process(requests);
        Integer queryCount = Limits.getQueries() - queriesBefore;
        Test.stopTest();

        // Then
        Assert.areEqual(200, responses.size(), 'Expected one response per Work Order.');
        Assert.isTrue(queryCount <= 2, 'Expected bulk processing to use at most two SOQL queries.');
        for (ModRequestFormEmailService.Response response : responses) {
            Assert.isFalse(response.eligible, 'Expected each non-Mod Request Work Order to be ineligible.');
        }
    }

    @IsTest
    static void testPreviewAndSendForEligibleWorkOrder() {
        // Setup
        List<EmailTemplate> templates = [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName = 'Mod_Request_Form_Request'
            LIMIT 1
        ];
        if (templates.isEmpty()) {
            return;
        }

        // Given
        adb_Account accountBuilder = new adb_Account().name('Mod Request Email Account');
        adb_Contact contactBuilder = new adb_Contact()
            .lastName('Mod Request Contact')
            .email('modrequest@test.example')
            .account(accountBuilder);
        adb_WorkOrder workOrderBuilder = buildInstrumentsWorkOrder(
            accountBuilder,
            true,
            'modrequest@test.example'
        );
        workOrderBuilder.setParent(WorkOrder.ModRequestContact__c, contactBuilder);
        workOrderBuilder.persist();

        ModRequestFormEmailService.Request previewRequest = new ModRequestFormEmailService.Request();
        previewRequest.workOrderId = workOrderBuilder.id;
        previewRequest.operation = 'Preview';

        // When
        ModRequestFormEmailService.Response previewResponse = ModRequestFormEmailService.process(
            new List<ModRequestFormEmailService.Request>{ previewRequest }
        )[0];

        // Then
        System.assertEquals(true, previewResponse.eligible, 'Expected eligible work order.');
        System.assertEquals(true, previewResponse.success, 'Expected preview success.');
        System.assertEquals(
            'modrequest@test.example',
            previewResponse.toAddress,
            'Expected mod contact email.'
        );
        System.assertNotEquals(null, previewResponse.subject, 'Expected rendered subject.');
        System.assertNotEquals(null, previewResponse.htmlBody, 'Expected rendered HTML body.');
        System.assert(
            previewResponse.htmlBody.contains('Dear Mod Request Contact'),
            'Expected contact salutation in email body.'
        );

        ModRequestFormEmailService.Request sendRequest = new ModRequestFormEmailService.Request();
        sendRequest.workOrderId = workOrderBuilder.id;
        sendRequest.operation = 'Send';
        sendRequest.toAddress = previewResponse.toAddress;
        sendRequest.subject = previewResponse.subject;
        sendRequest.htmlBody = previewResponse.htmlBody;

        Test.startTest();
        ModRequestFormEmailService.Response sendResponse = ModRequestFormEmailService.process(
            new List<ModRequestFormEmailService.Request>{ sendRequest }
        )[0];
        Test.stopTest();

        System.assertEquals(true, sendResponse.success, 'Expected send success.');
    }

    @IsTest
    static void testPreviewRequiresWorkOrderId() {
        // Setup
        // Given
        ModRequestFormEmailService.Request request = new ModRequestFormEmailService.Request();
        request.operation = 'Preview';

        // When
        ModRequestFormEmailService.Response response = ModRequestFormEmailService.process(
            new List<ModRequestFormEmailService.Request>{ request }
        )[0];

        // Then
        System.assertEquals(false, response.success, 'Expected failure without work order id.');
        System.assertEquals('Work Order Id is required.', response.errorMessage);
    }

    @IsTest
    static void testUnsupportedOperationReturnsError() {
        // Setup
        // Given
        adb_Account accountBuilder = new adb_Account().name('Mod Request Email Account');
        adb_WorkOrder workOrderBuilder = buildInstrumentsWorkOrder(
            accountBuilder,
            true,
            'modrequest@test.example'
        );
        workOrderBuilder.persist();

        ModRequestFormEmailService.Request request = new ModRequestFormEmailService.Request();
        request.workOrderId = workOrderBuilder.id;
        request.operation = 'Archive';

        // When
        ModRequestFormEmailService.Response response = ModRequestFormEmailService.process(
            new List<ModRequestFormEmailService.Request>{ request }
        )[0];

        // Then
        System.assertEquals(true, response.eligible, 'Expected eligible work order.');
        System.assertEquals(false, response.success, 'Expected unsupported operation failure.');
        System.assertEquals(
            'Unsupported operation. Use Preview or Send.',
            response.errorMessage
        );
    }

    @IsTest
    static void testApplyContactSalutationReplacesEmptyDearLine() {
        // Setup
        // Given
        // When
        String body = WorkOrdersService.applyContactSalutation(
            'Dear ,\n\nWe have received your request.',
            'Jane Smith'
        );

        // Then
        System.assertEquals(
            'Dear Jane Smith,\n\nWe have received your request.',
            body,
            'Expected empty Dear salutation to be replaced with contact name.'
        );
    }
}