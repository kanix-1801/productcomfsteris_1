/**
 * @description Tests for WOAssignmentHistoriesService (GW-3816).
 */
@IsTest
private class WOAssignmentHistoriesServiceTest {
    private static final String READY_SUBJECT = 'WAH Service Ready WO';
    private static final String RACK_NAME = 'RACK-WAH-SVC-001';

    @TestSetup
    static void setupData() {
        /********************************************
         * SETUP
         ********************************************/
        adb_Account account = new adb_Account();
        account.persist();

        adb_Location rackBuilder = new adb_Location()
            .name(RACK_NAME)
            .locationType('Rack');
        Schema.Location rack = (Schema.Location) rackBuilder.record;
        rack.TrackRackAssignmentHistory__c = true;
        rackBuilder.persist();

        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .subject(READY_SUBJECT)
            .status('Received')
            .account(account)
            .setRecordType('RepairCenterDevices');
        workOrderBuilder.persist();

        WorkOrder workOrder = (WorkOrder) workOrderBuilder.record;
        workOrder.Status = 'Ready for Repair';
        Database.update(workOrder, AccessLevel.SYSTEM_MODE);

        // WAH has no adb_ builder yet — create Technician row directly.
        Id wahRecordTypeId = Schema.SObjectType.WOAssignmentHistory__c
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCenter')
            ?.getRecordTypeId();
        WOAssignmentHistory__c openTech = new WOAssignmentHistory__c(
            WorkOrder__c = workOrder.Id,
            Type__c = 'Technician',
            Technician__c = UserInfo.getUserId(),
            StartDateTime__c = Datetime.now().addHours(-1)
        );
        if (wahRecordTypeId != null) {
            openTech.RecordTypeId = wahRecordTypeId;
        }
        insert openTech;
    }

    @IsTest
    static void testCreateRackAssignment_WhenValid_CreatesOpenRackHistory() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        WorkOrder workOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :READY_SUBJECT
            LIMIT 1
        ];
        Schema.Location rack = [
            SELECT Id
            FROM Location
            WHERE Name = :RACK_NAME
            LIMIT 1
        ];
        Datetime startAt = Datetime.now();

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            Id historyId = WOAssignmentHistoriesService.createRackAssignment(
                workOrder.Id,
                rack.Id,
                startAt
            );
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(historyId);
            WOAssignmentHistory__c history = [
                SELECT WorkOrder__c, Type__c, Rack__c, EndDateTime__c
                FROM WOAssignmentHistory__c
                WHERE Id = :historyId
            ];
            Assert.areEqual(workOrder.Id, history.WorkOrder__c);
            Assert.areEqual('Rack', history.Type__c);
            Assert.areEqual(rack.Id, history.Rack__c);
            Assert.isNull(history.EndDateTime__c);
        }
    }

    @IsTest
    static void testCreateRackAssignment_WhenMissingInputs_Throws() {
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
                WOAssignmentHistoriesService.createRackAssignment(null, null, null);
                Test.stopTest();
            } catch (WOAssignmentHistoriesService.WOAssignmentHistoriesServiceException e) {
                threw = true;
            }

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(threw, 'Missing inputs should throw');
        }
    }

    @IsTest
    static void testEndOpenTechnicianAssignments_WhenOpenRowsExist_EndsThem() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        WorkOrder workOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :READY_SUBJECT
            LIMIT 1
        ];
        Datetime endAt = Datetime.now();

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            WOAssignmentHistoriesService.endOpenTechnicianAssignments(workOrder.Id, endAt);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer openCount = [
                SELECT COUNT()
                FROM WOAssignmentHistory__c
                WHERE WorkOrder__c = :workOrder.Id
                    AND Type__c = 'Technician'
                    AND EndDateTime__c = NULL
            ];
            Assert.areEqual(0, openCount);

            Integer closedCount = [
                SELECT COUNT()
                FROM WOAssignmentHistory__c
                WHERE WorkOrder__c = :workOrder.Id
                    AND Type__c = 'Technician'
                    AND EndDateTime__c != NULL
            ];
            Assert.areEqual(1, closedCount);
        }
    }

    @IsTest
    static void testEndOpenTechnicianAssignments_WhenNullInputs_DoesNothing() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        WorkOrder workOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :READY_SUBJECT
            LIMIT 1
        ];

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            WOAssignmentHistoriesService.endOpenTechnicianAssignments(null, Datetime.now());
            WOAssignmentHistoriesService.endOpenAssignmentsByType(null, 'Technician', Datetime.now());
            WOAssignmentHistoriesService.endOpenAssignmentsByType(workOrder.Id, '', Datetime.now());
            WOAssignmentHistoriesService.endOpenAssignmentsByType(workOrder.Id, 'Technician', null);
            WOAssignmentHistoriesService.endOpenAssignments(null, Datetime.now());
            WOAssignmentHistoriesService.endOpenAssignments(workOrder.Id, null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(true, 'Null guards should no-op without throwing');
        }
    }

    @IsTest
    static void testEndOpenAssignmentsByType_WhenOpenRackExists_EndsRackRows() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        WorkOrder workOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :READY_SUBJECT
            LIMIT 1
        ];
        Schema.Location rack = [
            SELECT Id
            FROM Location
            WHERE Name = :RACK_NAME
            LIMIT 1
        ];
        Id wahRecordTypeId = Schema.SObjectType.WOAssignmentHistory__c
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCenter')
            ?.getRecordTypeId();
        WOAssignmentHistory__c openRack = new WOAssignmentHistory__c(
            WorkOrder__c = workOrder.Id,
            Type__c = 'Rack',
            Rack__c = rack.Id,
            StartDateTime__c = Datetime.now().addHours(-2)
        );
        if (wahRecordTypeId != null) {
            openRack.RecordTypeId = wahRecordTypeId;
        }
        insert openRack;
        Datetime endAt = Datetime.now();

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            WOAssignmentHistoriesService.endOpenAssignmentsByType(workOrder.Id, 'Rack', endAt);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer openRackCount = [
                SELECT COUNT()
                FROM WOAssignmentHistory__c
                WHERE WorkOrder__c = :workOrder.Id
                    AND Type__c = 'Rack'
                    AND EndDateTime__c = NULL
            ];
            Assert.areEqual(0, openRackCount);
        }
    }

    @IsTest
    static void testCreateTechnicianAssignment_WhenValid_CreatesOpenTechnicianHistory() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        WorkOrder workOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :READY_SUBJECT
            LIMIT 1
        ];
        Datetime startAt = Datetime.now();

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            Id historyId = WOAssignmentHistoriesService.createTechnicianAssignment(
                workOrder.Id,
                UserInfo.getUserId(),
                startAt
            );
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(historyId);
            WOAssignmentHistory__c history = [
                SELECT WorkOrder__c, Type__c, Technician__c, EndDateTime__c
                FROM WOAssignmentHistory__c
                WHERE Id = :historyId
            ];
            Assert.areEqual(workOrder.Id, history.WorkOrder__c);
            Assert.areEqual('Technician', history.Type__c);
            Assert.areEqual(UserInfo.getUserId(), history.Technician__c);
            Assert.isNull(history.EndDateTime__c);
        }
    }

    @IsTest
    static void testCreateTechnicianAssignment_WhenMissingInputs_Throws() {
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
                WOAssignmentHistoriesService.createTechnicianAssignment(null, null, null);
                Test.stopTest();
            } catch (WOAssignmentHistoriesService.WOAssignmentHistoriesServiceException e) {
                threw = true;
            }

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(threw, 'Missing inputs should throw');
        }
    }

    @IsTest
    static void testEndOpenAssignments_WhenOpenRowsExist_EndsAllTypes() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        WorkOrder workOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :READY_SUBJECT
            LIMIT 1
        ];
        Schema.Location rack = [
            SELECT Id
            FROM Location
            WHERE Name = :RACK_NAME
            LIMIT 1
        ];
        Id wahRecordTypeId = Schema.SObjectType.WOAssignmentHistory__c
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCenter')
            ?.getRecordTypeId();
        WOAssignmentHistory__c openRack = new WOAssignmentHistory__c(
            WorkOrder__c = workOrder.Id,
            Type__c = 'Rack',
            Rack__c = rack.Id,
            StartDateTime__c = Datetime.now().addHours(-1)
        );
        if (wahRecordTypeId != null) {
            openRack.RecordTypeId = wahRecordTypeId;
        }
        insert openRack;

        Datetime endAt = Datetime.now();

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            WOAssignmentHistoriesService.endOpenAssignments(workOrder.Id, endAt);
            // Second call covers empty open-list early return.
            WOAssignmentHistoriesService.endOpenAssignments(workOrder.Id, endAt);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer openCount = [
                SELECT COUNT()
                FROM WOAssignmentHistory__c
                WHERE WorkOrder__c = :workOrder.Id
                    AND EndDateTime__c = NULL
            ];
            Assert.areEqual(0, openCount);
        }
    }

    @IsTest
    static void testCreateRackAssignment_WhenInvalidWorkOrder_Throws() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        Schema.Location rack = [
            SELECT Id
            FROM Location
            WHERE Name = :RACK_NAME
            LIMIT 1
        ];
        adb_Account account = new adb_Account();
        account.persist();
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .subject('WAH Disposable WO')
            .status('Received')
            .account(account)
            .setRecordType('RepairCenterDevices');
        workOrderBuilder.persist();
        Id deletedWorkOrderId = workOrderBuilder.id;
        delete [SELECT Id FROM WorkOrder WHERE Id = :deletedWorkOrderId];
        Boolean threw = false;

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            try {
                Test.startTest();
                WOAssignmentHistoriesService.createRackAssignment(
                    deletedWorkOrderId,
                    rack.Id,
                    Datetime.now()
                );
                Test.stopTest();
            } catch (WOAssignmentHistoriesService.WOAssignmentHistoriesServiceException e) {
                threw = true;
            }

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(threw, 'Deleted Work Order should throw service exception');
        }
    }

    @IsTest
    static void testAssignCurrentUserAsTechnician_WhenSameUserOpen_LeavesRow() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        WorkOrder workOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :READY_SUBJECT
            LIMIT 1
        ];
        WOAssignmentHistory__c existing = [
            SELECT Id
            FROM WOAssignmentHistory__c
            WHERE WorkOrder__c = :workOrder.Id
                AND Type__c = 'Technician'
                AND EndDateTime__c = NULL
            LIMIT 1
        ];

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            Id historyId = WOAssignmentHistoriesService.assignCurrentUserAsTechnician(workOrder.Id);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(existing.Id, historyId);
            Integer closedCount = [
                SELECT COUNT()
                FROM WOAssignmentHistory__c
                WHERE WorkOrder__c = :workOrder.Id
                    AND EndDateTime__c != NULL
            ];
            Assert.areEqual(0, closedCount);
        }
    }

    @IsTest
    static void testAssignCurrentUserAsTechnician_WhenOtherTechAndRack_EndsAndCreates() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        User otherUser = [
            SELECT Id
            FROM User
            WHERE Id != :UserInfo.getUserId()
                AND IsActive = TRUE
            LIMIT 1
        ];
        adb_Account account = new adb_Account();
        account.persist();
        adb_Location rackBuilder = new adb_Location()
            .name('RACK-WAH-SVC-TECH')
            .locationType('Rack');
        Schema.Location rack = (Schema.Location) rackBuilder.record;
        rack.TrackRackAssignmentHistory__c = true;
        rackBuilder.persist();
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .subject('WAH Assign Current User WO')
            .status('Received')
            .account(account)
            .setRecordType('RepairCenterDevices');
        workOrderBuilder.persist();
        WorkOrder workOrder = (WorkOrder) workOrderBuilder.record;
        workOrder.Status = 'Ready for Repair';
        Database.update(workOrder, AccessLevel.SYSTEM_MODE);

        Id wahRecordTypeId = Schema.SObjectType.WOAssignmentHistory__c
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCenter')
            ?.getRecordTypeId();
        WOAssignmentHistory__c openRack = new WOAssignmentHistory__c(
            WorkOrder__c = workOrder.Id,
            Type__c = 'Rack',
            Rack__c = rack.Id,
            StartDateTime__c = Datetime.now().addHours(-2)
        );
        WOAssignmentHistory__c openOther = new WOAssignmentHistory__c(
            WorkOrder__c = workOrder.Id,
            Type__c = 'Technician',
            Technician__c = otherUser.Id,
            StartDateTime__c = Datetime.now().addHours(-1)
        );
        if (wahRecordTypeId != null) {
            openRack.RecordTypeId = wahRecordTypeId;
            openOther.RecordTypeId = wahRecordTypeId;
        }
        insert new List<WOAssignmentHistory__c>{ openRack, openOther };

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            Id historyId = WOAssignmentHistoriesService.assignCurrentUserAsTechnician(workOrder.Id);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(historyId);
            Assert.areNotEqual(openOther.Id, historyId);
            WOAssignmentHistory__c closedRack = [
                SELECT EndDateTime__c
                FROM WOAssignmentHistory__c
                WHERE Id = :openRack.Id
            ];
            Assert.isNotNull(closedRack.EndDateTime__c);
            WOAssignmentHistory__c closedOther = [
                SELECT EndDateTime__c
                FROM WOAssignmentHistory__c
                WHERE Id = :openOther.Id
            ];
            Assert.isNotNull(closedOther.EndDateTime__c);
        }
    }

    @IsTest
    static void testAssignCurrentUserAsTechnician_WhenWorkOrderNull_Throws() {
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
                WOAssignmentHistoriesService.assignCurrentUserAsTechnician(null);
            } catch (WOAssignmentHistoriesService.WOAssignmentHistoriesServiceException e) {
                threw = true;
                Assert.isTrue(e.getMessage().contains('Work Order'));
            }

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(threw);
        }
    }

    @IsTest
    static void testCreateTechnicianAssignment_WhenInvalidWorkOrder_Throws() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        adb_Account account = new adb_Account();
        account.persist();
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .subject('WAH Disposable Tech WO')
            .status('Received')
            .account(account)
            .setRecordType('RepairCenterDevices');
        workOrderBuilder.persist();
        Id deletedWorkOrderId = workOrderBuilder.id;
        delete [SELECT Id FROM WorkOrder WHERE Id = :deletedWorkOrderId];
        Boolean threw = false;

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            try {
                Test.startTest();
                WOAssignmentHistoriesService.createTechnicianAssignment(
                    deletedWorkOrderId,
                    UserInfo.getUserId(),
                    Datetime.now()
                );
                Test.stopTest();
            } catch (WOAssignmentHistoriesService.WOAssignmentHistoriesServiceException e) {
                threw = true;
            }

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(threw, 'Deleted Work Order should throw service exception');
        }
    }
}