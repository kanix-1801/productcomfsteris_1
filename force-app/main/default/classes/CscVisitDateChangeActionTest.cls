/**
 * @author Abhishek Mishra
 * @date 02-11-2026
 * @description #GC-3579 Tests the Change Date save and the postpone date release.
 */
@IsTest(SeeAllData=false)
private class CscVisitDateChangeActionTest {
    private static final String LOCATION = 'Customer Solution Center (Mentor, OH)';

    @TestSetup
    static void setupData() {
        insert new Automation_Setting_Validation_Rule__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            disableAll__c = true
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id roleId = [SELECT Id FROM UserRole WHERE PortalType = 'None' LIMIT 1].Id;
            User adminUser = buildUser('dateadm', 'Date Admin', 'Healthcare Sales');
            adminUser.UserRoleId = roleId;
            insert adminUser;
            assignPermissionSetGroup(adminUser.Id, 'SalesCustomerOpsSalesSupportSalesAdminPSG');
            assignPermissionSetGroup(adminUser.Id, 'CSCVisitAdministratorPSG');
        }
    }

    @IsTest
    static void changeDateSavesConfirmedDateAndApproves() {
        Date selectedDate = weekdayAhead(12);
        CSC_Visit_Request__c visit = insertVisit(CscVisitRequestSelector.STATUS_REQUESTED, selectedDate.addDays(7));
        List<CscVisitRequestService.UnavailableDate> openDates =
            CscAvailabilityController.getUnavailableDatesForVisit(
                CscVisitRequestSelector.REQUEST_CSC,
                LOCATION,
                selectedDate,
                selectedDate,
                visit.Id
            );
        System.assertNotEquals(null, openDates);

        System.runAs(adminUser()) {
            CscVisitDateChangeAction.changeDates(null);
            CscVisitDateChangeAction.changeDates(new List<CscVisitDateChangeAction.Request>{ null });
            CscVisitDateChangeAction.Request request = new CscVisitDateChangeAction.Request();
            request.recordId = visit.Id;
            request.confirmedDate = selectedDate;
            CscVisitDateChangeAction.changeDates(new List<CscVisitDateChangeAction.Request>{ request });
        }

        visit = [
            SELECT Status__c, Confirmed_Date__c, Primary_Requested_Date__c, Backup_Requested_Date__c
            FROM CSC_Visit_Request__c
            WHERE Id = :visit.Id
        ];
        System.assertEquals(CscVisitRequestSelector.STATUS_APPROVED, visit.Status__c);
        System.assertEquals(selectedDate, visit.Confirmed_Date__c);
        System.assertEquals(null, visit.Primary_Requested_Date__c);
        System.assertEquals(null, visit.Backup_Requested_Date__c);
    }

    @IsTest
    static void changeDateRejectsAnOccupiedDate() {
        Date occupiedDate = weekdayAhead(20);
        insertVisit(CscVisitRequestSelector.STATUS_CONFIRMED, occupiedDate);
        CSC_Visit_Request__c visit = insertVisit(CscVisitRequestSelector.STATUS_POSTPONED, null);
        Boolean threw = false;

        System.runAs(adminUser()) {
            try {
                CscVisitStatusAction.changeVisitDate(visit.Id, occupiedDate);
            } catch (AuraHandledException ex) {
                threw = true;
                System.assert(ex.getMessage().contains('no longer available'));
            }
        }

        visit = [
            SELECT Status__c, Confirmed_Date__c
            FROM CSC_Visit_Request__c
            WHERE Id = :visit.Id
        ];
        System.assertEquals(true, threw, 'An occupied date is not saved');
        System.assertEquals(CscVisitRequestSelector.STATUS_POSTPONED, visit.Status__c);
        System.assertEquals(null, visit.Confirmed_Date__c);
    }

    @IsTest
    static void postponeClearsTheActiveDate() {
        Date confirmedDate = weekdayAhead(8);
        CSC_Visit_Request__c visit = insertVisit(CscVisitRequestSelector.STATUS_CONFIRMED, confirmedDate);

        System.runAs(adminUser()) {
            CscVisitStatusAction.postponeVisit(visit.Id);
        }

        visit = [
            SELECT Status__c, Confirmed_Date__c, Primary_Requested_Date__c, Backup_Requested_Date__c
            FROM CSC_Visit_Request__c
            WHERE Id = :visit.Id
        ];
        System.assertEquals(CscVisitRequestSelector.STATUS_POSTPONED, visit.Status__c);
        System.assertEquals(null, visit.Confirmed_Date__c);
        System.assertEquals(null, visit.Primary_Requested_Date__c);
        System.assertEquals(null, visit.Backup_Requested_Date__c);
    }

    private static CSC_Visit_Request__c insertVisit(String statusValue, Date confirmedDate) {
        CSC_Visit_Request__c visit = new CSC_Visit_Request__c(
            RecordTypeId = visitRecordTypeId(),
            VisitType__c = CscVisitRequestSelector.REQUEST_CSC,
            VisitLocation__c = LOCATION,
            Status__c = statusValue,
            Confirmed_Date__c = confirmedDate,
            Primary_Requested_Date__c = confirmedDate,
            Backup_Requested_Date__c = confirmedDate == null ? null : confirmedDate.addDays(1)
        );
        insert visit;
        return visit;
    }

    private static Id visitRecordTypeId() {
        return Schema.SObjectType.CSC_Visit_Request__c
            .getRecordTypeInfosByDeveloperName()
            .get(CscVisitRequestSelector.RECORD_TYPE_VISIT)
            .getRecordTypeId();
    }

    private static Date weekdayAhead(Integer daysAhead) {
        Date value = Date.today().addDays(daysAhead);
        while (CscVisitRequestService.isWeekend(value)) {
            value = value.addDays(1);
        }
        return value;
    }

    private static User adminUser() {
        return [SELECT Id FROM User WHERE Alias = 'dateadm' LIMIT 1];
    }

    private static void assignPermissionSetGroup(Id userId, String developerName) {
        PermissionSetGroup permissionSetGroupRecord = [
            SELECT Id, Status
            FROM PermissionSetGroup
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];
        if (permissionSetGroupRecord.Status != 'Updated') {
            Test.calculatePermissionSetGroup(permissionSetGroupRecord.Id);
        }
        insert new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetGroupId = permissionSetGroupRecord.Id
        );
    }

    private static User buildUser(String alias, String lastName, String profileName) {
        Profile profileRow = [
            SELECT Id
            FROM Profile
            WHERE Name = :profileName
            LIMIT 1
        ];
        String uniqueName = alias + DateTime.now().getTime();
        return new User(
            Alias = alias,
            Email = uniqueName + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = lastName,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profileRow.Id,
            TimeZoneSidKey = 'America/New_York',
            Username = uniqueName + '@example.com'
        );
    }
}