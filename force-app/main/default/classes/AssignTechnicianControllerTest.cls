/**
 * @description Aura-entry tests for AssignTechnicianController (GW-3816).
 *              Business scenarios are covered in WorkOrdersServiceTest /
 *              WOAssignmentHistoriesServiceTest.
 */
@IsTest
private class AssignTechnicianControllerTest {
    private static final String STATUS_RECEIVED = 'Received';
    private static final String STATUS_READY_FOR_REPAIR = 'Ready for Repair';
    private static final String READY_SUBJECT = 'Assign Tech Ready WO';
    private static final String BLOCKED_SUBJECT = 'Assign Tech Blocked WO';

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

            Id wahRecordTypeId = Schema.SObjectType.WOAssignmentHistory__c
                .getRecordTypeInfosByDeveloperName()
                .get('RepairCenter')
                ?.getRecordTypeId();
            WOAssignmentHistory__c openAssignment = new WOAssignmentHistory__c(
                WorkOrder__c = readyWo.Id,
                Type__c = 'Technician',
                Technician__c = UserInfo.getUserId(),
                StartDateTime__c = Datetime.now().addHours(-1)
            );
            if (wahRecordTypeId != null) {
                openAssignment.RecordTypeId = wahRecordTypeId;
            }
            insert openAssignment;
        }
    }

    @IsTest
    static void testAssignTechnician_WhenValidInputs_ReturnsMappedResult() {
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
            AssignTechnicianController.AssignResult result =
                AssignTechnicianController.assignTechnician(readyWo.WorkOrderNumber);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(readyWo.Id, result.workOrderId);
            Assert.areEqual(readyWo.WorkOrderNumber, result.workOrderNumber);
            Assert.isNotNull(result.assignmentHistoryId);

            WorkOrder updated = [
                SELECT OwnerId
                FROM WorkOrder
                WHERE Id = :readyWo.Id
            ];
            Assert.areEqual(UserInfo.getUserId(), updated.OwnerId);
        }
    }

    @IsTest
    static void testAssignTechnician_WhenBlockedStatus_ThrowsAuraHandledException() {
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
                AssignTechnicianController.assignTechnician(blockedWo.WorkOrderNumber);
                Test.stopTest();
            } catch (AuraHandledException e) {
                threw = true;
                Assert.areEqual(
                    WorkOrdersService.ASSIGN_TECHNICIAN_STATUS_BLOCKED_MESSAGE,
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
    static void testAssignTechnician_WhenBlankWorkOrder_ThrowsAuraHandledException() {
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
                AssignTechnicianController.assignTechnician('  ');
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
    static void testAssignTechnician_WhenWorkOrderMissing_ThrowsAuraHandledException() {
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
                AssignTechnicianController.assignTechnician('WO-DOES-NOT-EXIST-999');
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