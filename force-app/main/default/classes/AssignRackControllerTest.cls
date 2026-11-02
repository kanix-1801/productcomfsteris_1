/**
 * @description Aura-entry tests for AssignRackController (GW-3816).
 *              Business scenarios are covered in WorkOrdersServiceTest /
 *              WOAssignmentHistoriesServiceTest / LocationsServiceTest.
 */
@IsTest
private class AssignRackControllerTest {
    private static final String STATUS_RECEIVED = 'Received';
    private static final String STATUS_READY_FOR_REPAIR = 'Ready for Repair';
    private static final String RACK_NAME = 'RACK-AT-001';
    private static final String READY_SUBJECT = 'Assign Rack Ready WO';
    private static final String BLOCKED_SUBJECT = 'Assign Rack Blocked WO';

    private static void assignRequiredPermissionSets() {
        Set<String> permissionSetNames = new Set<String>{
            'RepairCenterOperations',
            'ManageWorkOrders',
            'BaseUser',
            'System_Administrator'
        };
        List<PermissionSet> permissionSets = [
            SELECT Id
            FROM PermissionSet
            WHERE Name IN :permissionSetNames
        ];
        if (permissionSets.isEmpty()) {
            return;
        }

        Id userId = UserInfo.getUserId();
        Set<Id> alreadyAssigned = new Set<Id>();
        for (PermissionSetAssignment existing : [
            SELECT PermissionSetId
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId
                AND PermissionSetId IN :permissionSets
        ]) {
            alreadyAssigned.add(existing.PermissionSetId);
        }

        List<PermissionSetAssignment> toInsert = new List<PermissionSetAssignment>();
        for (PermissionSet ps : permissionSets) {
            if (!alreadyAssigned.contains(ps.Id)) {
                toInsert.add(
                    new PermissionSetAssignment(
                        AssigneeId = userId,
                        PermissionSetId = ps.Id
                    )
                );
            }
        }
        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, false);
        }
    }

    @TestSetup
    static void setupData() {
        /********************************************
         * SETUP
         ********************************************/
        assignRequiredPermissionSets();

        // Separate setup-object DML (PermissionSetAssignment) from non-setup DML via runAs.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            adb_Account account = new adb_Account();
            account.persist();

            adb_Location rackBuilder = new adb_Location()
                .name(RACK_NAME)
                .locationType('Rack');
            Schema.Location rack = (Schema.Location) rackBuilder.record;
            rack.TrackRackAssignmentHistory__c = true;
            rackBuilder.persist();

            adb_WorkOrder readyBuilder = new adb_WorkOrder()
                .subject(READY_SUBJECT)
                .status(STATUS_RECEIVED)
                .account(account)
                .setRecordType('RepairCenterDevices');
            readyBuilder.persist();

            adb_WorkOrder blockedBuilder = new adb_WorkOrder()
                .subject(BLOCKED_SUBJECT)
                .status(STATUS_RECEIVED)
                .account(account)
                .setRecordType('RepairCenterDevices');
            blockedBuilder.persist();

            WorkOrder readyWo = (WorkOrder) readyBuilder.record;
            readyWo.Status = STATUS_READY_FOR_REPAIR;
            Database.update(readyWo, AccessLevel.SYSTEM_MODE);
        }
    }

    @IsTest
    static void testAssignRack_WhenValidInputs_ReturnsMappedResult() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        WorkOrder readyWo = [
            SELECT Id, WorkOrderNumber
            FROM WorkOrder
            WHERE Subject = :READY_SUBJECT
            LIMIT 1
        ];

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            AssignRackController.AssignResult result = AssignRackController.assignRack(
                String.valueOf(readyWo.Id),
                RACK_NAME
            );
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(readyWo.Id, result.workOrderId);
            Assert.areEqual(readyWo.WorkOrderNumber, result.workOrderNumber);
            Assert.areEqual(RACK_NAME, result.rackName);
            Assert.isNotNull(result.rackId);

            WorkOrder updated = [
                SELECT Rack__c
                FROM WorkOrder
                WHERE Id = :readyWo.Id
            ];
            Assert.areEqual(result.rackId, updated.Rack__c);
        }
    }

    @IsTest
    static void testAssignRack_WhenBlockedStatus_ThrowsAuraHandledException() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        WorkOrder blockedWo = [
            SELECT WorkOrderNumber
            FROM WorkOrder
            WHERE Subject = :BLOCKED_SUBJECT
            LIMIT 1
        ];
        Boolean threw = false;

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            try {
                Test.startTest();
                AssignRackController.assignRack(String.valueOf(blockedWo.Id), RACK_NAME);
                Test.stopTest();
            } catch (AuraHandledException e) {
                threw = true;
                Assert.areEqual(
                    WorkOrdersService.ASSIGN_RACK_STATUS_BLOCKED_MESSAGE,
                    e.getMessage()
                );
            }

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(threw, 'Blocked status should throw AuraHandledException');
        }
    }

    @IsTest
    static void testAssignRack_WhenBlankWorkOrder_ThrowsAuraHandledException() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        Boolean threw = false;

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            try {
                AssignRackController.assignRack('  ', RACK_NAME);
            } catch (AuraHandledException e) {
                threw = true;
            }

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(threw, 'Blank Work Order should throw AuraHandledException');
        }
    }

    @IsTest
    static void testAssignRack_WhenBlankRack_ThrowsAuraHandledException() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        WorkOrder readyWo = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :READY_SUBJECT
            LIMIT 1
        ];
        Boolean threw = false;

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            try {
                AssignRackController.assignRack(String.valueOf(readyWo.Id), '  ');
            } catch (AuraHandledException e) {
                threw = true;
            }

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(threw, 'Blank Rack should throw AuraHandledException');
        }
    }

    @IsTest
    static void testAssignRack_WhenWorkOrderMissing_ThrowsAuraHandledException() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        Boolean threw = false;

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            try {
                Test.startTest();
                AssignRackController.assignRack('WO-DOES-NOT-EXIST-999', RACK_NAME);
                Test.stopTest();
            } catch (AuraHandledException e) {
                threw = true;
                Assert.isTrue(e.getMessage().contains('Work Order'));
            }

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(threw, 'Missing Work Order should throw AuraHandledException');
        }
    }
}