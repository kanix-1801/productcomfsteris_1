/**
 * @description GW-5231 tests for RepairCoordinatorActionsController.
 */
@IsTest
private class RepairCoordinatorActionsControllerTest {
    private static final String SUBJECT = 'GW5231 Controller Work Order';

    /**
     * @description GW-5231 - Creates an eligible Work Order for controller tests.
     */
    @TestSetup
    static void setupData() {
        Account account = new Account(
            Name = 'GW5231 Controller Account',
            SystemID__c = 'GW5231-CTRL',
            SourceSystemID__c = 'GW5231-CTRL',
            OrgIDs__c = '82'
        );
        insert account;
        WorkOrder workOrder = new WorkOrder(
            Subject = SUBJECT,
            Status = 'Received',
            AccountId = account.Id
        );
        insert workOrder;
        workOrder.Status = 'Ready for Repair';
        update workOrder;
    }

    /**
     * @description GW-5231 - Controller delegates valid Work Order scans.
     */
    @IsTest
    static void testProcessScanValidWorkOrderReturnsState() {
        WorkOrder workOrder = [
            SELECT Id, WorkOrderNumber
            FROM WorkOrder
            WHERE Subject = :SUBJECT
            LIMIT 1
        ];

        Test.startTest();
        WorkOrderCoordinatorActionsService.ScanResult result =
            RepairCoordinatorActionsController.processScan(
                null,
                workOrder.WorkOrderNumber
            );
        Test.stopTest();

        Assert.areEqual(workOrder.Id, result.workOrderId, 'Controller should return service state');
    }

    /**
     * @description GW-5231 - Controller translates service validation into AuraHandledException.
     */
    @IsTest
    static void testProcessScanInvalidWorkOrderThrowsAuraHandledException() {
        String errorMessage;

        Test.startTest();
        try {
            RepairCoordinatorActionsController.processScan(null, 'INVALID-WO');
            Assert.fail('Invalid scan should throw');
        } catch (AuraHandledException e) {
            errorMessage = e.getMessage();
        }
        Test.stopTest();

        Assert.areEqual(
            'You must first scan in a valid Work Order before you can proceed with assignments.',
            errorMessage,
            'Controller should preserve the business error'
        );
    }

    /**
     * @description GW-5231 - Controller delegates Service Team assignment and removal.
     */
    @IsTest
    static void testAssignCandidateAndRemoveServiceTeamUpdateState() {
        WorkOrder workOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :SUBJECT
            LIMIT 1
        ];
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW5231 Controller Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;
        workOrder.RepairCenter__c = repairCenter.Id;
        update workOrder;
        ServiceTeam__c serviceTeam = new ServiceTeam__c(
            Name = 'GW5231 Controller Team',
            Status__c = 'Active',
            Type__c = 'Repair Center',
            Location__c = repairCenter.Id
        );
        insert serviceTeam;

        Test.startTest();
        WorkOrderCoordinatorActionsService.ScanResult assignedResult =
            RepairCoordinatorActionsController.assignCandidate(
                workOrder.Id,
                'SERVICE_TEAM',
                serviceTeam.Id
            );
        WorkOrderCoordinatorActionsService.ScanResult removedResult =
            RepairCoordinatorActionsController.removeServiceTeam(workOrder.Id);
        Test.stopTest();

        Assert.areEqual(serviceTeam.Id, assignedResult.serviceTeamId, 'Team should be assigned');
        Assert.isNull(removedResult.serviceTeamId, 'Team should be removed');
    }

    /**
     * @description GW-5231 - Controller delegates Rack removal.
     */
    @IsTest
    static void testRemoveRackClearsExistingRack() {
        Schema.Location rack = new Schema.Location(
            Name = 'GW5231 Controller Rack',
            LocationType = 'Rack',
            TrackRackAssignmentHistory__c = false
        );
        insert rack;
        WorkOrder workOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :SUBJECT
            LIMIT 1
        ];
        workOrder.Rack__c = rack.Id;
        update workOrder;

        Test.startTest();
        WorkOrderCoordinatorActionsService.ScanResult result =
            RepairCoordinatorActionsController.removeRack(workOrder.Id);
        Test.stopTest();

        Assert.isNull(result.rackId, 'Rack should be removed');
    }

    /**
     * @description GW-5231 - Controller translates assignment and removal validation errors.
     */
    @IsTest
    static void testAssignmentActionsInvalidInputsThrowAuraHandledExceptions() {
        WorkOrder workOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :SUBJECT
            LIMIT 1
        ];
        Integer auraErrorCount = 0;

        Test.startTest();
        try {
            RepairCoordinatorActionsController.assignCandidate(
                workOrder.Id,
                'INVALID',
                UserInfo.getUserId()
            );
            Assert.fail('Invalid assignment type should throw');
        } catch (AuraHandledException e) {
            auraErrorCount++;
        }
        try {
            RepairCoordinatorActionsController.removeRack(null);
            Assert.fail('Missing Work Order should throw for Rack removal');
        } catch (AuraHandledException e) {
            auraErrorCount++;
        }
        try {
            RepairCoordinatorActionsController.removeServiceTeam(null);
            Assert.fail('Missing Work Order should throw for Service Team removal');
        } catch (AuraHandledException e) {
            auraErrorCount++;
        }
        Test.stopTest();

        Assert.areEqual(3, auraErrorCount, 'All validation errors should be Aura handled');
    }
}