/**
 * @description Covers the CSC blocked-date save used by the admin calendar.
 */
@IsTest(SeeAllData=false)
private class CscBlockedDateActionTest {
    private static final String LOCATION = 'Customer Solution Center (Mentor, OH)';

    @TestSetup
    static void setup() {
        insert new Automation_Setting_Validation_Rule__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            disableAll__c = true
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id salesProfileId = [
                SELECT Id
                FROM Profile
                WHERE Name = 'Healthcare Sales'
                LIMIT 1
            ].Id;
            Id roleId = [SELECT Id FROM UserRole WHERE PortalType = 'None' LIMIT 1].Id;
            User adminUser = new User(
                Alias = 'blkadm',
                Email = 'blkadm@csc.example.test',
                EmailEncodingKey = 'UTF-8',
                LastName = 'BlockAdmin',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = salesProfileId,
                UserRoleId = roleId,
                TimeZoneSidKey = 'America/New_York',
                Username = 'blkadm' + DateTime.now().getTime() + '@csc.example.test'
            );
            User salesUser = new User(
                Alias = 'blksal',
                Email = 'blksal@csc.example.test',
                EmailEncodingKey = 'UTF-8',
                LastName = 'BlockSales',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = salesProfileId,
                UserRoleId = roleId,
                TimeZoneSidKey = 'America/New_York',
                Username = 'blksal' + DateTime.now().getTime() + '@csc.example.test'
            );
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
    static void salesUserCannotBlockADate() {
        User salesUser = [SELECT Id FROM User WHERE LastName = 'BlockSales' LIMIT 1];
        Boolean threw = false;
        System.runAs(salesUser) {
            try {
                CscBlockedDateAction.save(new List<CscBlockedDateAction.Request>{
                    blockRequest(String.valueOf(Date.today().addDays(30)), null)
                });
            } catch (CscBlockedDateAction.BlockedDateException ex) {
                threw = true;
            }
        }
        System.assertEquals(true, threw, 'A user without the CSC admin permission cannot block a date');
    }

    @IsTest
    static void administratorCanBlockAndUnblockADate() {
        User adminUser = [SELECT Id FROM User WHERE LastName = 'BlockAdmin' LIMIT 1];
        String blockDay = String.valueOf(Date.today().addDays(40));
        String secondDay = String.valueOf(Date.today().addDays(41));

        System.runAs(adminUser) {
            List<CscBlockedDateAction.Result> blocked = CscBlockedDateAction.save(
                new List<CscBlockedDateAction.Request>{
                    blockRequest(blockDay + ';' + secondDay + '; ' + blockDay, null)
                }
            );
            System.assertEquals(2, blocked[0].blockedCount);
            System.assertEquals(0, blocked[0].removedCount);

            List<CscBlockedDateAction.Result> again = CscBlockedDateAction.save(
                new List<CscBlockedDateAction.Request>{ blockRequest(blockDay, null) }
            );
            System.assertEquals(0, again[0].blockedCount, 'An existing block is not inserted again');

            List<CscBlockedDateAction.Result> cleared = CscBlockedDateAction.save(
                new List<CscBlockedDateAction.Request>{ blockRequest(null, blockDay) }
            );
            System.assertEquals(1, cleared[0].removedCount);
        }

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM CSC_Visit_Request__c
                WHERE VisitLocation__c = :LOCATION
                  AND Blocked_Date__c = :Date.today().addDays(41)
            ]
        );
    }

    private static CscBlockedDateAction.Request blockRequest(String datesToBlock, String datesToUnblock) {
        CscBlockedDateAction.Request request = new CscBlockedDateAction.Request();
        request.visitLocation = LOCATION;
        request.blockedReason = 'Holiday';
        request.datesToBlock = datesToBlock;
        request.datesToUnblock = datesToUnblock;
        return request;
    }
}