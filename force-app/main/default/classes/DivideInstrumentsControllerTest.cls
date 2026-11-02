/**
 * @description Tests for DivideInstrumentsController (GW-2891).
 */
@IsTest
private class DivideInstrumentsControllerTest {
    /**
     * @description GW-2891 - Stub service client that returns canned workspace context.
     */
    private class StubClient implements DivideInstrumentsController.IDivideInstrumentsClient {
        /**
         * @description GW-2891 - Returns a canned initialize context for the given Work Order Id.
         * @param workOrderId Work Order Id from the scan
         * @return Divide Instruments context
         */
        public WorkOrdersService.DivideInstrumentsContext initializeDivideInstruments(Id workOrderId) {
            WorkOrdersService.DivideInstrumentsContext context =
                new WorkOrdersService.DivideInstrumentsContext();
            context.workOrder = new WorkOrder(
                Id = workOrderId,
                Status = 'Divide',
                QuantityReceived__c = 5
            );
            context.existingBins = new List<WorkOrdersService.DivideInstrumentsBin>();
            return context;
        }

        /**
         * @description GW-2891 - Returns a canned complete context with Quantity Received and labels warning.
         * @param workOrderId Parent Work Order Id
         * @param quantityReceived Quantity Received from the UI
         * @param bins Bin rows
         * @return Divide Instruments context
         */
        public WorkOrdersService.DivideInstrumentsContext completeDivideInstruments(
            Id workOrderId,
            Decimal quantityReceived,
            List<WorkOrdersService.DivideInstrumentsBin> bins
        ) {
            WorkOrdersService.DivideInstrumentsContext context =
                initializeDivideInstruments(workOrderId);
            context.workOrder.QuantityReceived__c = quantityReceived;
            context.labelsWarning = 'Child Work Orders were created. Bin labels are not wired yet.';
            return context;
        }
    }

    /**
     * @description GW-2891 - Stub service client that throws WorkOrdersServiceException.
     */
    private class ThrowingClient implements DivideInstrumentsController.IDivideInstrumentsClient {
        /**
         * @description GW-2891 - Throws not-found to exercise initialize error wrapping.
         * @param workOrderId Work Order Id from the scan
         * @return Never returns
         */
        public WorkOrdersService.DivideInstrumentsContext initializeDivideInstruments(Id workOrderId) {
            throw new WorkOrdersService.WorkOrdersServiceException('Work Order was not found.');
        }

        /**
         * @description GW-2891 - Throws a bins-required error to exercise complete error wrapping.
         * @param workOrderId Parent Work Order Id
         * @param quantityReceived Quantity Received from the UI
         * @param bins Bin rows
         * @return Never returns
         */
        public WorkOrdersService.DivideInstrumentsContext completeDivideInstruments(
            Id workOrderId,
            Decimal quantityReceived,
            List<WorkOrdersService.DivideInstrumentsBin> bins
        ) {
            throw new WorkOrdersService.WorkOrdersServiceException('Add at least one bin before completing.');
        }
    }

    /**
     * @description GW-2891 - Stub that returns null existing bins so mapping skips empty input.
     */
    private class StubClientWithNullExistingBins implements DivideInstrumentsController.IDivideInstrumentsClient {
        /**
         * @description GW-2891 - Returns context with a null existing-bins list.
         * @param workOrderId Work Order Id from the scan
         * @return Divide Instruments context
         */
        public WorkOrdersService.DivideInstrumentsContext initializeDivideInstruments(Id workOrderId) {
            WorkOrdersService.DivideInstrumentsContext context =
                new WorkOrdersService.DivideInstrumentsContext();
            context.workOrder = new WorkOrder(Id = workOrderId, Status = 'Divide');
            context.existingBins = null;
            return context;
        }

        /**
         * @description GW-2891 - Returns context including a null bin row.
         * @param workOrderId Parent Work Order Id
         * @param quantityReceived Quantity Received from the UI
         * @param bins Bin rows
         * @return Divide Instruments context
         */
        public WorkOrdersService.DivideInstrumentsContext completeDivideInstruments(
            Id workOrderId,
            Decimal quantityReceived,
            List<WorkOrdersService.DivideInstrumentsBin> bins
        ) {
            WorkOrdersService.DivideInstrumentsContext context =
                initializeDivideInstruments(workOrderId);
            WorkOrdersService.DivideInstrumentsBin existingBin =
                new WorkOrdersService.DivideInstrumentsBin();
            existingBin.repairCategory = 'Stainless';
            existingBin.quantity = quantityReceived;
            existingBin.turnTime = 1;
            context.existingBins = new List<WorkOrdersService.DivideInstrumentsBin>{
                null,
                existingBin
            };
            context.workOrder.QuantityReceived__c = quantityReceived;
            return context;
        }
    }

    /**
     * @description GW-2891 - Stub that throws an unexpected exception for error wrapping.
     */
    private class UnexpectedExceptionClient implements DivideInstrumentsController.IDivideInstrumentsClient {
        /**
         * @description GW-2891 - Throws a non-service exception on initialize.
         * @param workOrderId Work Order Id from the scan
         * @return Never returns
         */
        public WorkOrdersService.DivideInstrumentsContext initializeDivideInstruments(Id workOrderId) {
            throw new IllegalArgumentException('Unexpected initialize failure');
        }

        /**
         * @description GW-2891 - Throws a non-service exception on complete.
         * @param workOrderId Parent Work Order Id
         * @param quantityReceived Quantity Received from the UI
         * @param bins Bin rows
         * @return Never returns
         */
        public WorkOrdersService.DivideInstrumentsContext completeDivideInstruments(
            Id workOrderId,
            Decimal quantityReceived,
            List<WorkOrdersService.DivideInstrumentsBin> bins
        ) {
            throw new IllegalArgumentException('Unexpected complete failure');
        }
    }

    /**
     * @description GW-2891 - Verifies unknown Work Order Id/Number throws AuraHandledException.
     */
    @IsTest
    static void testInitializeDivide_WhenInvalidId_Throws() {
        Boolean threw = false;
        Test.startTest();
        try {
            DivideInstrumentsController.initializeDivide('not-an-id');
        } catch (AuraHandledException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('was not found'),
                'Unknown Id/Number should use the shared not-found message'
            );
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Unknown Work Order input should throw AuraHandledException');
    }

    /**
     * @description GW-2891 - Verifies blank scan input requires a Work Order.
     */
    @IsTest
    static void testInitializeDivide_WhenBlankInput_Throws() {
        Boolean threw = false;
        Test.startTest();
        try {
            DivideInstrumentsController.initializeDivide('  ');
        } catch (AuraHandledException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('required'),
                'Blank input should require a Work Order'
            );
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Blank Work Order input should throw AuraHandledException');
    }

    /**
     * @description GW-2891 - Verifies initialize by Id or Number and complete return workspace DTOs.
     */
    @IsTest
    static void testInitializeAndComplete_WhenStubClient_ReturnsWorkspace() {
        DivideInstrumentsController.clientOverride = new StubClient();
        adb_WorkOrder builder = new adb_WorkOrder();
        builder.persist();
        WorkOrder created = (WorkOrder) builder.record;

        DivideInstrumentsController.BinDraft draft = new DivideInstrumentsController.BinDraft();
        draft.repairCategory = 'Stainless';
        draft.quantity = 5;
        draft.turnTime = 2;

        WorkOrder createdWithNumber = [
            SELECT Id, WorkOrderNumber
            FROM WorkOrder
            WHERE Id = :created.Id
        ];

        Test.startTest();
        DivideInstrumentsController.Workspace startedById =
            DivideInstrumentsController.initializeDivide(createdWithNumber.Id);
        DivideInstrumentsController.Workspace startedByNumber =
            DivideInstrumentsController.initializeDivide(createdWithNumber.WorkOrderNumber);
        DivideInstrumentsController.Workspace completed =
            DivideInstrumentsController.completeDivide(
                created.Id,
                5,
                new List<DivideInstrumentsController.BinDraft>{ draft }
            );
        Test.stopTest();

        Assert.areEqual(created.Id, startedById.workOrderId);
        Assert.areEqual(created.Id, startedByNumber.workOrderId);
        Assert.areEqual(5, completed.quantityReceived);
        Assert.isTrue(String.isNotBlank(completed.labelsWarning));
    }

    /**
     * @description GW-2891 - Verifies the default client calls WorkOrdersService.
     */
    @IsTest
    static void testInitializeAndComplete_WhenDefaultClient_UsesService() {
        DivideInstrumentsController.clientOverride = null;
        WorkOrder created = createDivideInstrumentsParentWorkOrder();
        created.EstimateRequired__c = 'Estimate Required';
        created.CustomerPORequired__c = false;
        created.RepairWarranty__c = 'No';
        created.ContinuousImprovementOpportunity__c = false;
        update created;

        DivideInstrumentsController.BinDraft draft = new DivideInstrumentsController.BinDraft();
        draft.repairCategory = 'Stainless';
        draft.quantity = 1;
        draft.turnTime = 1;

        Test.startTest();
        DivideInstrumentsController.Workspace started =
            DivideInstrumentsController.initializeDivide(created.Id);
        DivideInstrumentsController.Workspace completed =
            DivideInstrumentsController.completeDivide(
                created.Id,
                1,
                new List<DivideInstrumentsController.BinDraft>{ draft }
            );
        Test.stopTest();

        Assert.areEqual(created.Id, started.workOrderId);
        Assert.areEqual(1, completed.quantityReceived);
    }

    /**
     * @description GW-2891 - Verifies service exceptions are wrapped as AuraHandledException.
     */
    @IsTest
    static void testCompleteDivide_WhenServiceThrows_WrapsAuraException() {
        DivideInstrumentsController.clientOverride = new ThrowingClient();
        Boolean threw = false;
        Test.startTest();
        try {
            DivideInstrumentsController.completeDivide(
                UserInfo.getUserId(),
                1,
                new List<DivideInstrumentsController.BinDraft>()
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Service exception should become AuraHandledException');
    }

    /**
     * @description GW-2891 - Verifies initialize wraps WorkOrdersServiceException as AuraHandledException.
     */
    @IsTest
    static void testInitializeDivide_WhenServiceThrows_WrapsAuraException() {
        DivideInstrumentsController.clientOverride = new ThrowingClient();
        adb_WorkOrder builder = new adb_WorkOrder();
        builder.persist();
        WorkOrder created = (WorkOrder) builder.record;

        Boolean threw = false;
        Test.startTest();
        try {
            DivideInstrumentsController.initializeDivide(created.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Initialize service exception should become AuraHandledException');
    }

    /**
     * @description GW-2891 - Verifies unexpected errors are wrapped as AuraHandledException.
     */
    @IsTest
    static void testInitializeAndComplete_WhenUnexpectedException_WrapsAuraException() {
        DivideInstrumentsController.clientOverride = new UnexpectedExceptionClient();
        adb_WorkOrder builder = new adb_WorkOrder();
        builder.persist();
        WorkOrder created = (WorkOrder) builder.record;

        Boolean initThrew = false;
        Boolean completeThrew = false;
        Test.startTest();
        try {
            DivideInstrumentsController.initializeDivide(created.Id);
        } catch (AuraHandledException e) {
            initThrew = true;
        }
        try {
            DivideInstrumentsController.completeDivide(
                created.Id,
                1,
                new List<DivideInstrumentsController.BinDraft>()
            );
        } catch (AuraHandledException e) {
            completeThrew = true;
        }
        Test.stopTest();
        Assert.isTrue(initThrew, 'Unexpected initialize error should become AuraHandledException');
        Assert.isTrue(completeThrew, 'Unexpected complete error should become AuraHandledException');
    }

    /**
     * @description GW-2891 - Verifies complete maps null bin lists and null bin drafts.
     */
    @IsTest
    static void testCompleteDivide_WhenNullBins_MapsEmptyWorkspace() {
        DivideInstrumentsController.clientOverride = new StubClientWithNullExistingBins();
        adb_WorkOrder builder = new adb_WorkOrder();
        builder.persist();
        WorkOrder created = (WorkOrder) builder.record;

        Test.startTest();
        DivideInstrumentsController.Workspace started =
            DivideInstrumentsController.initializeDivide(created.Id);
        DivideInstrumentsController.Workspace completedNullList =
            DivideInstrumentsController.completeDivide(created.Id, 5, null);
        DivideInstrumentsController.Workspace completedNullDraft =
            DivideInstrumentsController.completeDivide(
                created.Id,
                5,
                new List<DivideInstrumentsController.BinDraft>{ null }
            );
        Test.stopTest();

        Assert.areEqual(created.Id, started.workOrderId);
        Assert.areEqual(0, started.existingBins.size(), 'Null existing bins should map to empty');
        Assert.areEqual(5, completedNullList.quantityReceived);
        Assert.areEqual(1, completedNullList.existingBins.size(), 'Null mapped bin should be skipped');
        Assert.areEqual('Stainless', completedNullList.existingBins[0].repairCategory);
        Assert.areEqual(5, completedNullDraft.quantityReceived);
    }

    /**
     * @description GW-2891 - Parent Instruments Work Order for Divide Instruments controller tests.
     * @return Persisted parent Work Order
     */
    private static WorkOrder createDivideInstrumentsParentWorkOrder() {
        adb_WorkOrder builder = new adb_WorkOrder().setRecordType('RepairCenterInstruments');
        builder.persist();
        return (WorkOrder) builder.record;
    }
}