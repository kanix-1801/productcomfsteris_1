/**
 * @description Tests for WOAssignmentHistoriesSelector (GW-3816 / GW-3891).
 */
@IsTest
private class WOAssignmentHistoriesSelectorTest {
    private static final String WO_SUBJECT = 'WAH Selector WO';

    @TestSetup
    static void setupData() {
        /********************************************
         * SETUP
         ********************************************/
        adb_Account account = new adb_Account();
        account.persist();

        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .subject(WO_SUBJECT)
            .status('Received')
            .account(account)
            .setRecordType('RepairCenterDevices');
        workOrderBuilder.persist();
        WorkOrder workOrder = (WorkOrder) workOrderBuilder.record;

        // WAH has no adb_ builder yet — create rows directly.
        Id wahRecordTypeId = Schema.SObjectType.WOAssignmentHistory__c
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCenter')
            ?.getRecordTypeId();

        WOAssignmentHistory__c openAssignment = new WOAssignmentHistory__c(
            WorkOrder__c = workOrder.Id,
            Type__c = 'Technician',
            Technician__c = UserInfo.getUserId(),
            StartDateTime__c = Datetime.now().addHours(-2)
        );
        WOAssignmentHistory__c closedAssignment = new WOAssignmentHistory__c(
            WorkOrder__c = workOrder.Id,
            Type__c = 'Technician',
            Technician__c = UserInfo.getUserId(),
            StartDateTime__c = Datetime.now().addDays(-2),
            EndDateTime__c = Datetime.now().addDays(-1)
        );
        if (wahRecordTypeId != null) {
            openAssignment.RecordTypeId = wahRecordTypeId;
            closedAssignment.RecordTypeId = wahRecordTypeId;
        }
        insert new List<WOAssignmentHistory__c>{ openAssignment, closedAssignment };
    }

    @IsTest
    static void testSelectOpenByWorkOrderIdAndType_WhenNullGuards_ReturnsEmpty() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        WorkOrder workOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :WO_SUBJECT
            LIMIT 1
        ];

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            List<WOAssignmentHistory__c> nullWo =
                WOAssignmentHistoriesSelector.selectOpenByWorkOrderIdAndType(null, 'Technician');
            List<WOAssignmentHistory__c> nullType =
                WOAssignmentHistoriesSelector.selectOpenByWorkOrderIdAndType(workOrder.Id, null);
            List<WOAssignmentHistory__c> blankType =
                WOAssignmentHistoriesSelector.selectOpenByWorkOrderIdAndType(workOrder.Id, ' ');
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(nullWo.isEmpty());
            Assert.isTrue(nullType.isEmpty());
            Assert.isTrue(blankType.isEmpty());
        }
    }

    @IsTest
    static void testSelectOpenByWorkOrderIdAndType_WhenOpenRowsExist_ReturnsOpenRows() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        WorkOrder workOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :WO_SUBJECT
            LIMIT 1
        ];

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            List<WOAssignmentHistory__c> openRows =
                WOAssignmentHistoriesSelector.selectOpenByWorkOrderIdAndType(
                    workOrder.Id,
                    'Technician'
                );
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(1, openRows.size());
            Assert.isNull(openRows[0].EndDateTime__c);
        }
    }

    @IsTest
    static void testSelectMostRecentClosedByWorkOrderIdAndType_WhenNullGuards_ReturnsEmpty() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        WorkOrder workOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :WO_SUBJECT
            LIMIT 1
        ];

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            List<WOAssignmentHistory__c> nullWo =
                WOAssignmentHistoriesSelector.selectMostRecentClosedByWorkOrderIdAndType(
                    null,
                    'Technician'
                );
            List<WOAssignmentHistory__c> nullType =
                WOAssignmentHistoriesSelector.selectMostRecentClosedByWorkOrderIdAndType(
                    workOrder.Id,
                    null
                );
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(nullWo.isEmpty());
            Assert.isTrue(nullType.isEmpty());
        }
    }

    @IsTest
    static void testSelectMostRecentClosedByWorkOrderIdAndType_WhenClosedExists_ReturnsLatest() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        WorkOrder workOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :WO_SUBJECT
            LIMIT 1
        ];

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            List<WOAssignmentHistory__c> closedRows =
                WOAssignmentHistoriesSelector.selectMostRecentClosedByWorkOrderIdAndType(
                    workOrder.Id,
                    'Technician'
                );
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(1, closedRows.size());
            Assert.isNotNull(closedRows[0].EndDateTime__c);
            Assert.areEqual(UserInfo.getUserId(), closedRows[0].Technician__c);
        }
    }
}