/**
 * @author Abhishek Mishra
 * @date 14-10-2026
 * @description #GC-3435 Tests sales-rep cancel and CSC admin postpone without a pending approval.
 */
@IsTest(SeeAllData=false)
private class CscVisitStatusActionTest {
    private static final String LOCATION = 'Customer Solution Center (Mentor, OH)';

    @TestSetup
    static void setupData() {
        insert new Automation_Setting_Validation_Rule__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            disableAll__c = true
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id roleId = [SELECT Id FROM UserRole WHERE PortalType = 'None' LIMIT 1].Id;
            User adminUser = buildUser('cscadm', 'CSC Admin', 'Healthcare Sales');
            User salesUser = buildUser('cscsal', 'CSC Sales', 'Healthcare Sales');
            adminUser.UserRoleId = roleId;
            salesUser.UserRoleId = roleId;
            insert new List<User>{ adminUser, salesUser };
            assignPermissionSetGroup(salesUser.Id, 'SalesFieldRepAccountManagerPSG');
            assignPermissionSetGroup(adminUser.Id, 'SalesCustomerOpsSalesSupportSalesAdminPSG');
            assignPermissionSetGroup(adminUser.Id, 'CSCVisitAdministratorPSG');
        }
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

    @IsTest
    static void confirmRejectsVisitThatIsNotApproved() {
        System.runAs(salesUser()) {
            CSC_Visit_Request__c visit = insertVisit(CscVisitRequestSelector.STATUS_DRAFT);
            Boolean threw = false;

            try {
                CscVisitStatusAction.confirmVisit(visit.Id);
            } catch (AuraHandledException ex) {
                threw = true;
                System.assert(ex.getMessage().contains('approved'));
            }

            System.assertEquals(true, threw, 'Only an approved visit can be confirmed');
        }
    }

    @IsTest
    static void cancelRequiresAVisit() {
        System.runAs(salesUser()) {
            Boolean threw = false;

            try {
                CscVisitStatusAction.cancelVisit(null);
            } catch (AuraHandledException ex) {
                threw = true;
                System.assert(ex.getMessage().contains('required'));
            }

            System.assertEquals(true, threw, 'Cancel needs a visit record');
        }
    }

    @IsTest
    static void onlyTheOwnerCanCancel() {
        CSC_Visit_Request__c visit;
        System.runAs(adminUser()) {
            visit = insertVisit(CscVisitRequestSelector.STATUS_DRAFT);
        }
        if (sharingModel('CSC_Visit_Request__c') == 'Private') {
            insert new CSC_Visit_Request__Share(
                ParentId = visit.Id,
                UserOrGroupId = salesUser().Id,
                AccessLevel = 'Read',
                RowCause = Schema.CSC_Visit_Request__Share.RowCause.Manual
            );
        }
        Boolean threw = false;

        System.runAs(salesUser()) {
            try {
                CscVisitStatusAction.cancelVisit(visit.Id);
            } catch (AuraHandledException ex) {
                threw = true;
                System.assert(ex.getMessage().contains('owner'));
            }
        }

        System.assertEquals(true, threw, 'Another user cannot cancel the visit');
    }

    @IsTest
    static void ownerCanCancelDraft() {
        System.runAs(salesUser()) {
            CSC_Visit_Request__c visit = insertVisit(CscVisitRequestSelector.STATUS_DRAFT);

            Test.startTest();
            CscVisitStatusAction.cancelVisit(visit.Id);
            Test.stopTest();

            visit = [SELECT Status__c FROM CSC_Visit_Request__c WHERE Id = :visit.Id];
            System.assertEquals(CscVisitRequestSelector.STATUS_CANCELLED, visit.Status__c);
        }
    }

    @IsTest
    static void ownerCanCancelApprovedVisit() {
        System.runAs(salesUser()) {
            CSC_Visit_Request__c visit = insertVisit(CscVisitRequestSelector.STATUS_APPROVED);

            CscVisitStatusAction.cancelVisit(visit.Id);

            visit = [SELECT Status__c FROM CSC_Visit_Request__c WHERE Id = :visit.Id];
            System.assertEquals(CscVisitRequestSelector.STATUS_CANCELLED, visit.Status__c);
        }
    }

    @IsTest
    static void ownerCanCancelConfirmedVisit() {
        System.runAs(salesUser()) {
            CSC_Visit_Request__c visit = insertVisit(CscVisitRequestSelector.STATUS_CONFIRMED);

            CscVisitStatusAction.cancelVisit(visit.Id);

            visit = [SELECT Status__c FROM CSC_Visit_Request__c WHERE Id = :visit.Id];
            System.assertEquals(CscVisitRequestSelector.STATUS_CANCELLED, visit.Status__c);
        }
    }

    @IsTest
    static void ownerCanConfirmApprovedVisitWithDate() {
        System.runAs(salesUser()) {
            CSC_Visit_Request__c visit = insertVisit(CscVisitRequestSelector.STATUS_APPROVED);
            visit.Confirmed_Date__c = Date.today().addDays(10);
            update visit;

            CscVisitStatusAction.confirmVisit(visit.Id);

            visit = [SELECT Status__c FROM CSC_Visit_Request__c WHERE Id = :visit.Id];
            System.assertEquals(CscVisitRequestSelector.STATUS_CONFIRMED, visit.Status__c);
        }
    }

    @IsTest
    static void confirmRequiresConfirmedDate() {
        System.runAs(salesUser()) {
            CSC_Visit_Request__c visit = insertVisit(CscVisitRequestSelector.STATUS_APPROVED);
            Boolean threw = false;

            try {
                CscVisitStatusAction.confirmVisit(visit.Id);
            } catch (AuraHandledException ex) {
                threw = true;
                System.assert(ex.getMessage().contains('Confirmed Date'));
            }

            System.assertEquals(true, threw, 'An approved visit without a date cannot be confirmed');
        }
    }

    @IsTest
    static void postponeRequiresAdministrator() {
        CSC_Visit_Request__c visit;
        System.runAs(salesUser()) {
            visit = insertVisit(CscVisitRequestSelector.STATUS_REQUESTED);
        }
        Boolean threw = false;

        System.runAs(salesUser()) {
            try {
                CscVisitStatusAction.postponeVisit(visit.Id);
            } catch (AuraHandledException ex) {
                threw = true;
                System.assert(ex.getMessage().contains('CSC Administrator'));
            }
        }

        System.assertEquals(true, threw, 'A sales user cannot postpone a visit');
    }

    @IsTest
    static void administratorCanPostponeApprovedVisit() {
        CSC_Visit_Request__c visit;
        System.runAs(salesUser()) {
            visit = insertVisit(CscVisitRequestSelector.STATUS_APPROVED);
        }

        System.runAs(adminUser()) {
            CscVisitStatusAction.postponeVisit(visit.Id);
        }

        visit = [SELECT Status__c FROM CSC_Visit_Request__c WHERE Id = :visit.Id];
        System.assertEquals(CscVisitRequestSelector.STATUS_POSTPONED, visit.Status__c);
    }

    @IsTest
    static void approvalRequiresConfirmedDate() {
        CSC_Visit_Request__c visit;
        System.runAs(salesUser()) {
            visit = insertVisit(CscVisitRequestSelector.STATUS_REQUESTED);
        }

        Database.SaveResult result;
        System.runAs(adminUser()) {
            visit.Status__c = CscVisitRequestSelector.STATUS_APPROVED;
            result = Database.update(visit, false);
        }

        System.assertEquals(false, result.isSuccess(), 'Approval without Confirmed Date is blocked');
        System.assert(
            result.getErrors()[0].getMessage().contains('Confirmed Date'),
            result.getErrors()[0].getMessage()
        );
    }

    @IsTest
    static void approvalSucceedsAfterConfirmedDateIsEntered() {
        CSC_Visit_Request__c visit;
        System.runAs(salesUser()) {
            visit = insertVisit(CscVisitRequestSelector.STATUS_REQUESTED);
        }

        System.runAs(adminUser()) {
            visit.Confirmed_Date__c = Date.today().addDays(10);
            visit.Status__c = CscVisitRequestSelector.STATUS_APPROVED;
            update visit;
        }

        visit = [SELECT Status__c FROM CSC_Visit_Request__c WHERE Id = :visit.Id];
        System.assertEquals(CscVisitRequestSelector.STATUS_APPROVED, visit.Status__c);
    }

    @IsTest
    static void administratorCanCancelAnotherUsersVisit() {
        CSC_Visit_Request__c visit;
        System.runAs(salesUser()) {
            visit = insertVisit(CscVisitRequestSelector.STATUS_DRAFT);
        }

        System.runAs(adminUser()) {
            CscVisitStatusAction.cancelVisit(visit.Id);
        }

        visit = [SELECT Status__c FROM CSC_Visit_Request__c WHERE Id = :visit.Id];
        System.assertEquals(CscVisitRequestSelector.STATUS_CANCELLED, visit.Status__c);
    }

    @IsTest
    static void salesUserCannotConfirmAnotherUsersVisit() {
        CSC_Visit_Request__c visit;
        System.runAs(adminUser()) {
            visit = insertVisit(CscVisitRequestSelector.STATUS_APPROVED);
            visit.Confirmed_Date__c = Date.today().addDays(3);
            update visit;
        }
        Boolean threw = false;

        System.runAs(salesUser()) {
            try {
                CscVisitStatusAction.confirmVisit(visit.Id);
            } catch (AuraHandledException ex) {
                threw = true;
            }
        }

        System.assertEquals(true, threw, 'Only the owner or a CSC administrator can confirm');
    }

    @IsTest
    static void missingVisitCannotBeCancelled() {
        System.runAs(salesUser()) {
            CSC_Visit_Request__c visit = insertVisit(CscVisitRequestSelector.STATUS_DRAFT);
            Id deletedId = visit.Id;
            delete visit;
            Boolean threw = false;

            try {
                CscVisitStatusAction.cancelVisit(deletedId);
            } catch (AuraHandledException ex) {
                threw = true;
            }

            System.assertEquals(true, threw, 'A deleted visit cannot be cancelled');
        }
    }

    private static CSC_Visit_Request__c insertVisit(String statusValue) {
        CSC_Visit_Request__c visit = new CSC_Visit_Request__c(
            VisitLocation__c = LOCATION,
            Status__c = statusValue
        );
        insert visit;
        return visit;
    }

    private static String sharingModel(String objectName) {
        return [
            SELECT InternalSharingModel
            FROM EntityDefinition
            WHERE QualifiedApiName = :objectName
            LIMIT 1
        ].InternalSharingModel;
    }

    private static User adminUser() {
        return [SELECT Id FROM User WHERE Alias = 'cscadm' LIMIT 1];
    }

    private static User salesUser() {
        return [SELECT Id FROM User WHERE Alias = 'cscsal' LIMIT 1];
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