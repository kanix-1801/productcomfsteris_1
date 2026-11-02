/**
 * @description GW-5231 tests for WorkOrderCoordinatorActionsService.
 */
@IsTest
private class WorkOrderCoordinatorActionsServiceTest {
    private static final String READY_SUBJECT = 'GW5231 Ready Work Order';
    private static final String SECOND_READY_SUBJECT = 'GW5231 Second Ready Work Order';
    private static final String BLOCKED_SUBJECT = 'GW5231 Blocked Work Order';
    private static final String OLD_RACK_NAME = 'GW5231 Old Rack';
    private static final String SHARED_NAME = 'GW5231 Shared';
    private static final String TEAM_ONLY_NAME = 'GW5231 Team Only';
    private static final String OTHER_CENTER_TEAM_NAME = 'GW5231 Other Center Team';

    /**
     * @description GW-5231 - Creates Work Orders, Racks, Teams, and open assignment history.
     */
    @TestSetup
    static void setupData() {
        Account account = new Account(
            Name = 'GW5231 Service Account',
            SystemID__c = 'GW5231-SVC',
            SourceSystemID__c = 'GW5231-SVC',
            OrgIDs__c = '82'
        );
        insert account;

        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW5231 Repair Center',
            LocationType = 'Repair Center'
        );
        Schema.Location otherRepairCenter = new Schema.Location(
            Name = 'GW5231 Other Repair Center',
            LocationType = 'Repair Center'
        );
        Schema.Location oldRack = new Schema.Location(
            Name = OLD_RACK_NAME,
            LocationType = 'Rack',
            TrackRackAssignmentHistory__c = true
        );
        Schema.Location sharedRack = new Schema.Location(
            Name = SHARED_NAME,
            LocationType = 'Rack',
            TrackRackAssignmentHistory__c = true
        );
        insert new List<Schema.Location>{
            repairCenter,
            otherRepairCenter,
            oldRack,
            sharedRack
        };

        ServiceTeam__c initialTeam = new ServiceTeam__c(
            Name = 'GW5231 Initial Team',
            Status__c = 'Active',
            Type__c = 'Repair Center',
            Location__c = repairCenter.Id
        );
        ServiceTeam__c sharedTeam = new ServiceTeam__c(
            Name = SHARED_NAME,
            Status__c = 'Active',
            Type__c = 'Repair Center',
            Location__c = repairCenter.Id
        );
        ServiceTeam__c teamOnly = new ServiceTeam__c(
            Name = TEAM_ONLY_NAME,
            Status__c = 'Active',
            Type__c = 'Repair Center',
            Location__c = repairCenter.Id
        );
        ServiceTeam__c sameNameOtherCenter = new ServiceTeam__c(
            Name = TEAM_ONLY_NAME,
            Status__c = 'Active',
            Type__c = 'Repair Center',
            Location__c = otherRepairCenter.Id
        );
        ServiceTeam__c otherCenterTeam = new ServiceTeam__c(
            Name = OTHER_CENTER_TEAM_NAME,
            Status__c = 'Active',
            Type__c = 'Repair Center',
            Location__c = otherRepairCenter.Id
        );
        insert new List<ServiceTeam__c>{
            initialTeam,
            sharedTeam,
            teamOnly,
            sameNameOtherCenter,
            otherCenterTeam
        };

        WorkOrder readyWorkOrder = new WorkOrder(
            Subject = READY_SUBJECT,
            Status = 'Received',
            AccountId = account.Id
        );
        WorkOrder secondReadyWorkOrder = new WorkOrder(
            Subject = SECOND_READY_SUBJECT,
            Status = 'Received',
            AccountId = account.Id
        );
        WorkOrder blockedWorkOrder = new WorkOrder(
            Subject = BLOCKED_SUBJECT,
            Status = 'Received',
            AccountId = account.Id
        );
        insert new List<WorkOrder>{ readyWorkOrder, secondReadyWorkOrder, blockedWorkOrder };

        readyWorkOrder.Status = 'Ready for Repair';
        readyWorkOrder.Rack__c = oldRack.Id;
        readyWorkOrder.ServiceTeam__c = initialTeam.Id;
        readyWorkOrder.RepairCenter__c = repairCenter.Id;
        secondReadyWorkOrder.Status = 'Ready for Repair';
        secondReadyWorkOrder.RepairCenter__c = repairCenter.Id;
        update new List<WorkOrder>{ readyWorkOrder, secondReadyWorkOrder };

        Id historyRecordTypeId = Schema.SObjectType.WOAssignmentHistory__c
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCenter')
            ?.getRecordTypeId();
        WOAssignmentHistory__c openRackHistory = new WOAssignmentHistory__c(
            WorkOrder__c = readyWorkOrder.Id,
            Type__c = 'Rack',
            Rack__c = oldRack.Id,
            StartDateTime__c = Datetime.now().addHours(-2)
        );
        WOAssignmentHistory__c openTechnicianHistory = new WOAssignmentHistory__c(
            WorkOrder__c = readyWorkOrder.Id,
            Type__c = 'Technician',
            Technician__c = UserInfo.getUserId(),
            StartDateTime__c = Datetime.now().addHours(-1)
        );
        if (historyRecordTypeId != null) {
            openRackHistory.RecordTypeId = historyRecordTypeId;
            openTechnicianHistory.RecordTypeId = historyRecordTypeId;
        }
        insert new List<WOAssignmentHistory__c>{
            openRackHistory,
            openTechnicianHistory
        };
    }

    /**
     * @description GW-5231 - First Work Order scan loads existing Rack and Service Team.
     */
    @IsTest
    static void testProcessScanFirstWorkOrderReturnsExistingAssignments() {
        WorkOrder workOrder = getWorkOrder(READY_SUBJECT);

        Test.startTest();
        WorkOrderCoordinatorActionsService.ScanResult result =
            WorkOrderCoordinatorActionsService.processScan(
                null,
                workOrder.WorkOrderNumber
            );
        Test.stopTest();

        Assert.areEqual(workOrder.Id, result.workOrderId, 'Scanned Work Order should load');
        Assert.areEqual(OLD_RACK_NAME, result.rackName, 'Existing Rack should display');
        Assert.areEqual('GW5231 Initial Team', result.serviceTeamName, 'Existing team should display');
    }

    /**
     * @description GW-5231 - A Name shared by a Rack and Service Team requires user selection.
     */
    @IsTest
    static void testProcessScanSharedNameReturnsCandidateChoices() {
        WorkOrder workOrder = getWorkOrder(READY_SUBJECT);

        Test.startTest();
        WorkOrderCoordinatorActionsService.ScanResult result =
            WorkOrderCoordinatorActionsService.processScan(workOrder.Id, SHARED_NAME);
        Test.stopTest();

        Assert.areEqual(2, result.candidates.size(), 'Rack and Service Team choices should display');
    }

    /**
     * @description GW-5231 / GW-5783 - Replacing a Rack closes all open history and opens new Rack history.
     */
    @IsTest
    static void testAssignCandidateRackReplacesRackAndHistory() {
        WorkOrder workOrder = getWorkOrder(READY_SUBJECT);
        Schema.Location sharedRack = [
            SELECT Id
            FROM Location
            WHERE Name = :SHARED_NAME
            LIMIT 1
        ];
        Schema.Location oldRack = [
            SELECT Id
            FROM Location
            WHERE Name = :OLD_RACK_NAME
            LIMIT 1
        ];
        Id sharedRackId = sharedRack.Id;
        Id oldRackId = oldRack.Id;

        Test.startTest();
        WorkOrderCoordinatorActionsService.ScanResult result =
            WorkOrderCoordinatorActionsService.assignCandidate(
                workOrder.Id,
                'RACK',
                sharedRackId
            );
        Test.stopTest();

        Assert.areEqual(sharedRackId, result.rackId, 'New Rack should be assigned');
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM WOAssignmentHistory__c
                WHERE WorkOrder__c = :workOrder.Id
                    AND Type__c = 'Rack'
                    AND Rack__c = :sharedRackId
                    AND EndDateTime__c = NULL
            ],
            'New Rack history should be open'
        );
        Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM WOAssignmentHistory__c
                WHERE WorkOrder__c = :workOrder.Id
                    AND EndDateTime__c = NULL
                    AND Type__c = 'Rack'
                    AND Rack__c = :oldRackId
            ],
            'Prior Rack history should be closed'
        );
        Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM WOAssignmentHistory__c
                WHERE WorkOrder__c = :workOrder.Id
                    AND EndDateTime__c = NULL
                    AND Type__c = 'Technician'
            ],
            'Prior Technician history should be closed'
        );
    }

    /**
     * @description GW-5783 - Re-assigning the same Rack does not create another history row.
     */
    @IsTest
    static void testAssignCandidateSameRackDoesNotCreateDuplicateHistory() {
        WorkOrder workOrder = getWorkOrder(READY_SUBJECT);
        Schema.Location oldRack = [
            SELECT Id
            FROM Location
            WHERE Name = :OLD_RACK_NAME
            LIMIT 1
        ];
        Integer openRackBefore = [
            SELECT COUNT()
            FROM WOAssignmentHistory__c
            WHERE WorkOrder__c = :workOrder.Id
                AND Type__c = 'Rack'
                AND EndDateTime__c = NULL
        ];
        Integer openTechnicianBefore = [
            SELECT COUNT()
            FROM WOAssignmentHistory__c
            WHERE WorkOrder__c = :workOrder.Id
                AND Type__c = 'Technician'
                AND EndDateTime__c = NULL
        ];

        Test.startTest();
        WorkOrderCoordinatorActionsService.ScanResult result =
            WorkOrderCoordinatorActionsService.assignCandidate(
                workOrder.Id,
                'RACK',
                oldRack.Id
            );
        Test.stopTest();

        Assert.areEqual(oldRack.Id, result.rackId, 'Existing Rack should remain assigned');
        Assert.areEqual(
            openRackBefore,
            [
                SELECT COUNT()
                FROM WOAssignmentHistory__c
                WHERE WorkOrder__c = :workOrder.Id
                    AND Type__c = 'Rack'
                    AND EndDateTime__c = NULL
            ],
            'Same Rack should not create another open history row'
        );
        Assert.areEqual(
            openTechnicianBefore,
            [
                SELECT COUNT()
                FROM WOAssignmentHistory__c
                WHERE WorkOrder__c = :workOrder.Id
                    AND Type__c = 'Technician'
                    AND EndDateTime__c = NULL
            ],
            'Same Rack should not close Technician history'
        );
    }

    /**
     * @description GW-5231 - Service Team scan assigns the team and remove clears it.
     */
    @IsTest
    static void testProcessScanAndRemoveServiceTeamUpdatesWorkOrder() {
        WorkOrder workOrder = getWorkOrder(READY_SUBJECT);

        Test.startTest();
        WorkOrderCoordinatorActionsService.ScanResult assignedResult =
            WorkOrderCoordinatorActionsService.processScan(workOrder.Id, TEAM_ONLY_NAME);
        WorkOrderCoordinatorActionsService.ScanResult removedResult =
            WorkOrderCoordinatorActionsService.removeServiceTeam(workOrder.Id);
        Test.stopTest();

        Assert.areEqual(TEAM_ONLY_NAME, assignedResult.serviceTeamName, 'Team should be assigned');
        Assert.isNull(removedResult.serviceTeamId, 'Team should be cleared');
        WorkOrder refreshedWorkOrder = [
            SELECT ServiceTeam__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];
        Assert.isNull(refreshedWorkOrder.ServiceTeam__c, 'Work Order field should be cleared');
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM ServiceTeam__c
                WHERE Name = :TEAM_ONLY_NAME
                    AND Id != :assignedResult.serviceTeamId
            ],
            'A same-name team at another Repair Center should remain unselected'
        );
    }

    /**
     * @description GW-5231 - A Service Team at another Repair Center cannot be assigned.
     */
    @IsTest
    static void testProcessScanServiceTeamOutsideRepairCenterThrows() {
        WorkOrder workOrder = getWorkOrder(READY_SUBJECT);
        ServiceTeam__c otherCenterTeam = [
            SELECT Id
            FROM ServiceTeam__c
            WHERE Name = :OTHER_CENTER_TEAM_NAME
            LIMIT 1
        ];
        String scanMessage;
        String assignMessage;

        Test.startTest();
        try {
            WorkOrderCoordinatorActionsService.processScan(
                workOrder.Id,
                OTHER_CENTER_TEAM_NAME
            );
            Assert.fail('A team at another Repair Center should be rejected');
        } catch (WorkOrderCoordinatorActionsService.CoordinatorActionsException e) {
            scanMessage = e.getMessage();
        }
        try {
            WorkOrderCoordinatorActionsService.assignCandidate(
                workOrder.Id,
                'SERVICE_TEAM',
                otherCenterTeam.Id
            );
            Assert.fail('Assigning a team at another Repair Center should be rejected');
        } catch (WorkOrderCoordinatorActionsService.CoordinatorActionsException e) {
            assignMessage = e.getMessage();
        }
        Test.stopTest();

        Assert.areEqual(
            'The Service Team is not tied to this Work Order\'s Repair Center.',
            scanMessage,
            'Name search should reject a team from another Repair Center'
        );
        Assert.areEqual(
            scanMessage,
            assignMessage,
            'Candidate assignment should reject a team from another Repair Center'
        );
        WorkOrder refreshedWorkOrder = [
            SELECT ServiceTeam__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];
        Assert.areNotEqual(
            otherCenterTeam.Id,
            refreshedWorkOrder.ServiceTeam__c,
            'The other Repair Center team should not be assigned'
        );
    }

    /**
     * @description GW-5231 - Removing a Rack retains Repair Category and closes Rack history.
     */
    @IsTest
    static void testRemoveRackClearsRackRetainsCategoryAndClosesHistory() {
        WorkOrder workOrder = [
            SELECT Id, RepairCategory__c
            FROM WorkOrder
            WHERE Subject = :READY_SUBJECT
            LIMIT 1
        ];
        String priorRepairCategory = workOrder.RepairCategory__c;

        Test.startTest();
        WorkOrderCoordinatorActionsService.ScanResult result =
            WorkOrderCoordinatorActionsService.removeRack(workOrder.Id);
        Test.stopTest();

        Assert.isNull(result.rackId, 'Rack should be cleared');
        WorkOrder refreshedWorkOrder = [
            SELECT Rack__c, RepairCategory__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];
        Assert.isNull(refreshedWorkOrder.Rack__c, 'Rack__c should be blank');
        Assert.areEqual(
            priorRepairCategory,
            refreshedWorkOrder.RepairCategory__c,
            'Repair Category should remain unchanged'
        );
        Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM WOAssignmentHistory__c
                WHERE WorkOrder__c = :workOrder.Id
                    AND Type__c = 'Rack'
                    AND EndDateTime__c = NULL
            ],
            'Open Rack history should be closed'
        );
    }

    /**
     * @description GW-5231 - Scanning another eligible Work Order switches the current context.
     */
    @IsTest
    static void testProcessScanAnotherWorkOrderSwitchesContext() {
        WorkOrder firstWorkOrder = getWorkOrder(READY_SUBJECT);
        WorkOrder secondWorkOrder = getWorkOrder(SECOND_READY_SUBJECT);

        Test.startTest();
        WorkOrderCoordinatorActionsService.ScanResult result =
            WorkOrderCoordinatorActionsService.processScan(
                firstWorkOrder.Id,
                secondWorkOrder.WorkOrderNumber
            );
        Test.stopTest();

        Assert.areEqual(secondWorkOrder.Id, result.workOrderId, 'Current Work Order should switch');
    }

    /**
     * @description GW-5231 - Invalid first scans and blocked Work Orders return business errors.
     */
    @IsTest
    static void testProcessScanInvalidAndBlockedInputsThrowBusinessErrors() {
        WorkOrder blockedWorkOrder = getWorkOrder(BLOCKED_SUBJECT);
        String invalidMessage;
        String blockedMessage;

        Test.startTest();
        try {
            WorkOrderCoordinatorActionsService.processScan(null, 'NOT-A-WORK-ORDER');
            Assert.fail('Invalid first scan should throw');
        } catch (WorkOrderCoordinatorActionsService.CoordinatorActionsException e) {
            invalidMessage = e.getMessage();
        }
        try {
            WorkOrderCoordinatorActionsService.processScan(
                null,
                blockedWorkOrder.WorkOrderNumber
            );
            Assert.fail('Blocked Work Order should throw');
        } catch (WorkOrderCoordinatorActionsService.CoordinatorActionsException e) {
            blockedMessage = e.getMessage();
        }
        Test.stopTest();

        Assert.areEqual(
            'You must first scan in a valid Work Order before you can proceed with assignments.',
            invalidMessage,
            'Invalid first scan message should match the story'
        );
        Assert.areEqual(
            'The selected Work Order is not Ready for Repair and cannot be assigned.',
            blockedMessage,
            'Blocked status message should match the story'
        );
    }

    /**
     * @description GW-5692 - Assigning a Rack copies Status and Sub Status only when Status Assignment is set.
     */
    @IsTest
    static void testAssignCandidateRackAppliesStatusAssignment() {
        WorkOrder workOrder = getWorkOrder(SECOND_READY_SUBJECT);
        Id devicesRecordTypeId = Schema.SObjectType.WorkOrder
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCenterDevices')
            ?.getRecordTypeId();
        if (devicesRecordTypeId != null) {
            workOrder.RecordTypeId = devicesRecordTypeId;
            update workOrder;
        }
        Schema.Location rack = new Schema.Location(
            Name = 'GW6074 Status Rack',
            LocationType = 'Rack',
            StatusAssignment__c = 'Repair',
            SubStatusAssignment__c = 'Ready for QC',
            TrackRackAssignmentHistory__c = true
        );
        insert rack;

        Test.startTest();
        WorkOrderCoordinatorActionsService.ScanResult result =
            WorkOrderCoordinatorActionsService.assignCandidate(
                workOrder.Id,
                'RACK',
                rack.Id
            );
        Test.stopTest();

        Assert.areEqual(rack.Id, result.rackId, 'New Rack should be assigned');
        WorkOrder refreshedWorkOrder = [
            SELECT Status, SubStatus__c, Rack__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];
        Assert.areEqual(rack.Id, refreshedWorkOrder.Rack__c, 'Rack__c should match the assigned Rack');
        Assert.areEqual('Repair', refreshedWorkOrder.Status, 'Status should copy from the Rack');
        Assert.areEqual(
            'Ready for QC',
            refreshedWorkOrder.SubStatus__c,
            'Sub Status should copy from the Rack'
        );
    }

    /**
     * @description GW-5231 - Gets one test Work Order by Subject.
     * @param subject Test Work Order Subject
     * @return Matching test Work Order
     */
    private static WorkOrder getWorkOrder(String subject) {
        return [
            SELECT Id, WorkOrderNumber
            FROM WorkOrder
            WHERE Subject = :subject
            LIMIT 1
        ];
    }
}