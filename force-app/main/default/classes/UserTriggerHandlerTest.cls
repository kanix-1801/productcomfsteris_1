/**
 * @description : Test class for UserTriggerHandler, UserService, TeamMemberSelector and InactiveUserTeamCleanup.
 * 				  Validates inactive Sales User assignment cleanup processing.
 * @author 		: Vinay
 * @date 		: 2026-06-12
 */

@IsTest
private class UserTriggerHandlerTest {
	 /**
     * @description Verifies assignment history creation and cleanup
     * of Account Team Member and Opportunity Team Member records
     * when a Sales User becomes inactive.
     */
    @IsTest
    static void testInactiveSalesUserCreatesHistoryAndDeletesTeamMembers() {

        User systemAdminUser = createSystemAdminUser();
		
        System.runAs(systemAdminUser) {

            Profile profileRecord = [
                SELECT Id, Name
                FROM Profile
                WHERE Id = :UserInfo.getProfileId()
                LIMIT 1
            ];

            UserService.salesProfileName = profileRecord.Name;

            User salesUser = createTestUser(profileRecord.Id, 'salesusr');
            insert salesUser;
            

            Account accountRecord = new Account(
                Name = 'STERIS Test Account',
                SourceSystemID__c = 'TEST12345'
            );
            insert accountRecord;

            Contact contactRecord = new Contact(
                FirstName = 'STERIS',
                LastName = 'Test Contact',
                AccountId = accountRecord.Id,
                Email = 'steristestcontact@test.com'
            );
            insert contactRecord;
            
            Opportunity opportunityRecord = new Opportunity(
                Name = 'STERIS Test Opportunity',
                AccountId = accountRecord.Id,
                CloseDate = Date.today().addDays(30),
                Amount = 100,
                StageName = 'Discovery',
                ForecastConfidenceLevel__c = 'Pipeline',
                Probability = 20,
                Type = 'New Business',
                PrimaryContact__c = contactRecord.Id
            );
            insert opportunityRecord;

            insert new AccountTeamMember(
                AccountId = accountRecord.Id,
                UserId = salesUser.Id,
                TeamMemberRole = 'Oracle Assigned',
                AccountAccessLevel = 'Edit',
                OpportunityAccessLevel = 'Edit'
            );

            insert new OpportunityTeamMember(
                OpportunityId = opportunityRecord.Id,
                UserId = salesUser.Id,
                TeamMemberRole = 'Temporary Assignment',
                OpportunityAccessLevel = 'Edit'
            );

            Test.startTest();

            salesUser.IsActive = false;
            update salesUser;

            Test.stopTest();

            System.assertEquals(
                0,
                [
                    SELECT COUNT()
                    FROM AccountTeamMember
                    WHERE UserId = :salesUser.Id
                ],
                'Account Team Member should be deleted.'
            );

            System.assertEquals(
                0,
                [
                    SELECT COUNT()
                    FROM OpportunityTeamMember
                    WHERE UserId = :salesUser.Id
                ],
                'Opportunity Team Member should be deleted.'
            );

            List<InactiveUserAssignmentHistory__c> historyRecords = [
                SELECT Id,
                       User__c,
                       AssignmentObject__c,
                       UserInactivationDate__c
                FROM InactiveUserAssignmentHistory__c
                WHERE User__c = :salesUser.Id
            ];

            System.assertEquals(
                2,
                historyRecords.size(),
                'Two history records should be created.'
            );
        }
    }
	 /**
     * @description Verifies assignments with roles not configured
     * in the custom label are not removed.
     */
    @IsTest
    static void testInactiveSalesUserDoesNotDeleteRoleNotInCustomLabel() {

        User systemAdminUser = createSystemAdminUser();

        System.runAs(systemAdminUser) {

            Profile profileRecord = [
                SELECT Id, Name
                FROM Profile
                WHERE Id = :UserInfo.getProfileId()
                LIMIT 1
            ];

            UserService.salesProfileName = profileRecord.Name;

            User salesUser = createTestUser(profileRecord.Id, 'salesusr2');
            insert salesUser;

            Account accountRecord = new Account(
                Name = 'STERIS Test Account',
                SourceSystemID__c = 'TEST12345'
            );
            insert accountRecord;

            insert new AccountTeamMember(
                AccountId = accountRecord.Id,
                UserId = salesUser.Id,
                TeamMemberRole = 'Account Manager',
                AccountAccessLevel = 'Edit',
                OpportunityAccessLevel = 'Edit'
            );

            Test.startTest();

            salesUser.IsActive = false;
            update salesUser;

            Test.stopTest();

            System.assertEquals(
                1,
                [
                    SELECT COUNT()
                    FROM AccountTeamMember
                    WHERE UserId = :salesUser.Id
                ],
                'Team member role not in custom label should not be deleted.'
            );
        }
    }

	/**
     * @description Creates a System Administrator test User.
     */
    private static User createSystemAdminUser() {

        Profile systemAdminProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];

        String uniqueValue = String.valueOf(DateTime.now().getTime());

        return new User(
            FirstName = 'System',
            LastName = 'testInactiveSalesUserCreates',
            Alias = 'sysadmin',
            Email = 'sysadmin' + uniqueValue + '@test.com',
            Username = 'sysadmin' + uniqueValue + '@test.com',
            CommunityNickname = 'sysadmin' + uniqueValue,
            ProfileId = systemAdminProfile.Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }
	/**
     * @description Creates a generic test User.
     */
    private static User createTestUser(Id profileId, String aliasPrefix) {

        String uniqueValue = aliasPrefix + String.valueOf(DateTime.now().getTime());

        return new User(
            FirstName = 'STERIS',
            LastName = 'testInactiveSalesUserCreatesgeneric',
            Alias = aliasPrefix.left(8),
            Email = uniqueValue + '@test.com',
            Username = uniqueValue + '@test.com',
            CommunityNickname = uniqueValue.left(40),
            ProfileId = profileId,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }
    private static void assignPermissionSetGroup(Id userId) {
        PermissionSetGroup psg = [
            SELECT Id
            FROM PermissionSetGroup
            WHERE DeveloperName = 'SalesFieldRepAccountManagerPSG'
            LIMIT 1
        ];
    
        insert new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetGroupId = psg.Id
        );
    }
}