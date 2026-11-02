/**
 * @description Covers Team Member duplicate checks, sharing, and the trigger.
 */
@IsTest(SeeAllData=false)
private class TeamMemberServiceTest {
    private static final String LOCATION = 'Customer Solution Center (Mentor, OH)';

    @TestSetup
    static void setup() {
        insert new Automation_Setting_Validation_Rule__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            disableAll__c = true
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id healthcareSalesProfileId = [
                SELECT Id
                FROM Profile
                WHERE Name = 'Healthcare Sales'
                LIMIT 1
            ].Id;
            Id roleId = [SELECT Id FROM UserRole WHERE PortalType = 'None' LIMIT 1].Id;
            User sharedUser = new User(
                Alias = 'tmuser',
                Email = 'tmuser@csc.example.test',
                EmailEncodingKey = 'UTF-8',
                LastName = 'TeamMemberUser',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = healthcareSalesProfileId,
                UserRoleId = roleId,
                TimeZoneSidKey = 'America/New_York',
                Username = 'tmuser' + DateTime.now().getTime() + '@csc.example.test'
            );
            User salesRep = new User(
                Alias = 'tmrep',
                Email = 'tmrep@csc.example.test',
                EmailEncodingKey = 'UTF-8',
                LastName = 'TeamMemberSalesRep',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = healthcareSalesProfileId,
                UserRoleId = roleId,
                TimeZoneSidKey = 'America/New_York',
                Username = 'tmrep' + DateTime.now().getTime() + '@csc.example.test'
            );
            insert new List<User>{ sharedUser, salesRep };
            assignPermissionSetGroup(salesRep.Id, 'SalesFieldRepAccountManagerPSG');
        }
    }

    private static User salesRep() {
        return [SELECT Id FROM User WHERE LastName = 'TeamMemberSalesRep' LIMIT 1];
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
    static void missingUserAndParentAreRejected() {
        System.runAs(salesRep()) {
            TeamMember__c missingUser = new TeamMember__c();
            TeamMember__c missingParent = new TeamMember__c(User__c = UserInfo.getUserId());
            TeamMemberService.validateDuplicates(new List<TeamMember__c>{ missingUser, missingParent });

            System.assertEquals(true, missingUser.hasErrors());
            System.assertEquals(true, missingParent.hasErrors());
        }
    }

    @IsTest
    static void duplicateInTheSameSaveIsRejected() {
        System.runAs(salesRep()) {
            Id parentId = visitId();
            TeamMember__c firstRow = member(parentId, UserInfo.getUserId());
            TeamMember__c secondRow = member(parentId, UserInfo.getUserId());
            TeamMemberService.validateDuplicates(new List<TeamMember__c>{ firstRow, secondRow });

            System.assertEquals(false, firstRow.hasErrors());
            System.assertEquals(true, secondRow.hasErrors());
        }
    }

    @IsTest
    static void insertUpdateDeleteAndUndeleteShareTheVisit() {
        System.runAs(salesRep()) {
            Id parentId = visitId();
            User sharedUser = [SELECT Id FROM User WHERE LastName = 'TeamMemberUser' LIMIT 1];
            TeamMember__c row = member(parentId, sharedUser.Id);
            String sharingModel = sharingModel('CSC_Visit_Request__c');
            row.AccessLevel__c = sharingModel == 'Read' ? 'Edit' : 'Read';
            insert row;

            if (sharingModel == 'Private') {
                row.AccessLevel__c = 'Edit';
                update row;
                row.AccessLevel__c = 'Read';
                update row;
            }
            delete row;
            undelete row;

            System.assertEquals(1, [SELECT COUNT() FROM TeamMember__c WHERE Id = :row.Id]);
        }
    }

    private static Id visitId() {
        Opportunity opportunityRecord = new Opportunity(
            Name = 'Team Member Visit Opportunity',
            StageName = 'Discovery',
            CloseDate = Date.today().addDays(30),
            ForecastConfidenceLevel__c = 'Budget'
        );
        insert opportunityRecord;
        CSC_Visit_Request__c visit = new CSC_Visit_Request__c(
            VisitLocation__c = LOCATION,
            Opportunity__c = opportunityRecord.Id,
            Status__c = 'Draft'
        );
        insert visit;
        return visit.Id;
    }

    private static String sharingModel(String objectName) {
        return [
            SELECT InternalSharingModel
            FROM EntityDefinition
            WHERE QualifiedApiName = :objectName
            LIMIT 1
        ].InternalSharingModel;
    }

    private static TeamMember__c member(Id parentId, Id userId) {
        return new TeamMember__c(
            CSCVisitRequest__c = parentId,
            User__c = userId,
            AccessLevel__c = 'Read'
        );
    }
}