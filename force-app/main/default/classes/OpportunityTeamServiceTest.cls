/**
 * @description : Test class for OpportunityTeamService.
 *                Validates GC 2641 logic for adding active public group users
 *                to Opportunity Team Members when an Instrument Processing
 *                Opportunity Stage changes to Proposal and IP_Pillar__c is not Mobile.
 * @author      : Vinay
 * @date        : 2026-06-30
 * @story       : GC 2641
 */
@IsTest
private class OpportunityTeamServiceTest {

    private static final String TEAM_MEMBER_ROLE = 'Sales Ops / Contracting';
    private static final String TEST_GROUP_DEVELOPER_NAME = 'GC2641_Test_Group';

    /**
     * @description Verifies active public group user is added to Opportunity Team
     *              when StageName changes to Proposal.
     */
    @IsTest
    static void shouldAddActiveUserWhenStageChangesToProposal() {
        OpportunityTeamService.publicGroupDeveloperName = TEST_GROUP_DEVELOPER_NAME;
        OpportunityTeamService.sendNotifications = false;

        User adminUser = createSystemAdminUser('gcpos');
        insert adminUser;
        assignPermissionSetGroup(adminUser.Id);

        User teamUser = createSystemAdminUser('gcteam');
        insert teamUser;

        Group testGroup = createGroup(TEST_GROUP_DEVELOPER_NAME, 'GC2641 Test Group');
        insert testGroup;

        insert new GroupMember(
            GroupId = testGroup.Id,
            UserOrGroupId = teamUser.Id
        );

        System.runAs(adminUser) {
            Account accountRecord = createAccount();
            insert accountRecord;

            Opportunity opportunityRecord = createOpportunity(accountRecord.Id, 'Onsite');
            insert opportunityRecord;

            Opportunity oldOpportunity = opportunityRecord.clone(false, true, false, false);
            oldOpportunity.Id = opportunityRecord.Id;
            oldOpportunity.StageName = 'Prospecting';

            Test.startTest();
            opportunityRecord.StageName = 'Proposal';
            update opportunityRecord;
            OpportunityTeamService.addSalesOpsContractTeamMembers(
                new List<Opportunity>{ opportunityRecord },
                new Map<Id, Opportunity>{ opportunityRecord.Id => oldOpportunity }
            );
            Test.stopTest();

            List<OpportunityTeamMember> teamMembers = [
                SELECT Id, OpportunityId, UserId, TeamMemberRole, OpportunityAccessLevel
                FROM OpportunityTeamMember
                WHERE OpportunityId = :opportunityRecord.Id
                AND UserId = :teamUser.Id
            ];

            System.assertEquals(
                1,
                teamMembers.size(),
                'Active public group user should be added to Opportunity Team.'
            );

            System.assertEquals(
                TEAM_MEMBER_ROLE,
                teamMembers[0].TeamMemberRole,
                'Team Member Role should be Sales Ops / Contracting.'
            );

            System.assertEquals(
                'Edit',
                teamMembers[0].OpportunityAccessLevel,
                'Opportunity access should be Edit.'
            );
        }
    }

    /**
     * @description Verifies no Opportunity Team Member is added
     *              when IP_Pillar__c is Mobile.
     */
    
    @IsTest
    static void shouldNotAddUserWhenIpPillarIsMobile() {
        OpportunityTeamService.publicGroupDeveloperName = TEST_GROUP_DEVELOPER_NAME + '_Mobile';
        OpportunityTeamService.sendNotifications = false;

        User adminUser = createSystemAdminUser('gcmob');
        insert adminUser;
        assignPermissionSetGroup(adminUser.Id);

        User teamUser = createSystemAdminUser('gcmobt');
        insert teamUser;

        Group testGroup = createGroup(TEST_GROUP_DEVELOPER_NAME + '_Mobile', 'GC2641 Mobile Group');
        insert testGroup;

        insert new GroupMember(
            GroupId = testGroup.Id,
            UserOrGroupId = teamUser.Id
        );

        System.runAs(adminUser) {
            Account accountRecord = createAccount();
            insert accountRecord;

            Opportunity opportunityRecord = createOpportunity(accountRecord.Id, 'Mobile');
            insert opportunityRecord;

            Test.startTest();
            opportunityRecord.StageName = 'Proposal';
            update opportunityRecord;
            Test.stopTest();

            System.assertEquals(
                0,
                [
                    SELECT COUNT()
                    FROM OpportunityTeamMember
                    WHERE OpportunityId = :opportunityRecord.Id
                    AND UserId = :teamUser.Id
                ],
                'User should not be added when IP_Pillar__c is Mobile.'
            );
        }
    }
	
    /**
     * @description Verifies duplicate Opportunity Team Members are not created
     *              when the user is already present on the Opportunity Team.
     */
    @IsTest
    static void shouldNotCreateDuplicateTeamMember() {
        OpportunityTeamService.publicGroupDeveloperName = TEST_GROUP_DEVELOPER_NAME + '_Dup';
        OpportunityTeamService.sendNotifications = false;

        User adminUser = createSystemAdminUser('gcdup');
        insert adminUser;
        assignPermissionSetGroup(adminUser.Id);

        User teamUser = createSystemAdminUser('gcdupt');
        insert teamUser;

        Group testGroup = createGroup(TEST_GROUP_DEVELOPER_NAME + '_Dup', 'GC2641 Dup Group');
        insert testGroup;

        insert new GroupMember(
            GroupId = testGroup.Id,
            UserOrGroupId = teamUser.Id
        );

        System.runAs(adminUser) {
            Account accountRecord = createAccount();
            insert accountRecord;

            Opportunity opportunityRecord = createOpportunity(accountRecord.Id, 'Onsite');
            insert opportunityRecord;

            insert new OpportunityTeamMember(
                OpportunityId = opportunityRecord.Id,
                UserId = teamUser.Id,
                TeamMemberRole = TEAM_MEMBER_ROLE,
                OpportunityAccessLevel = 'Edit'
            );

            System.assertEquals(
                1,
                TeamMemberSelector.getOpportunityTeamMembersByOpportunityIdsAndUserIds(
                    new Set<Id>{ opportunityRecord.Id },
                    new Set<Id>{ teamUser.Id }
                ).size(),
                'Existing Opportunity Team Member should be selected.'
            );
            System.assertNotEquals(
                null,
                TeamMemberSelector.getPublicGroupByDeveloperName(TEST_GROUP_DEVELOPER_NAME + '_Dup'),
                'Public Group should be selected.'
            );
            System.assertEquals(
                1,
                TeamMemberSelector.getGroupMembersByGroupIds(new Set<Id>{ testGroup.Id }).size(),
                'Group Member should be selected.'
            );

            Test.startTest();
            opportunityRecord.StageName = 'Proposal';
            update opportunityRecord;
            Test.stopTest();

            System.assertEquals(
                1,
                [
                    SELECT COUNT()
                    FROM OpportunityTeamMember
                    WHERE OpportunityId = :opportunityRecord.Id
                    AND UserId = :teamUser.Id
                    AND TeamMemberRole = :TEAM_MEMBER_ROLE
                ],
                'Duplicate Opportunity Team Member should not be created.'
            );
        }
    }

    /**
     * @description Covers TeamMemberSelector when the group, members, or notification type do not match.
     */
    @IsTest
    static void selectorReturnsNullForMissingGroupAndNotification() {
        System.assertEquals(
            null,
            TeamMemberSelector.getPublicGroupByDeveloperName(''),
            'A blank group name should return null.'
        );
        System.assertEquals(
            null,
            TeamMemberSelector.getPublicGroupByDeveloperName('TMS_Group_Does_Not_Exist'),
            'An unknown group should return null.'
        );
        System.assertEquals(
            0,
            TeamMemberSelector.getGroupMembersByGroupIds(new Set<Id>()).size(),
            'An empty group filter should return no members.'
        );
        System.assertEquals(
            0,
            TeamMemberSelector.getOpportunityTeamMembersByOpportunityIdsAndUserIds(
                new Set<Id>(),
                new Set<Id>()
            ).size(),
            'Empty filters should return no Opportunity Team Members.'
        );
        System.assertEquals(
            null,
            TeamMemberSelector.getCustomNotificationTypeByDeveloperName(''),
            'A blank notification type should return null.'
        );
        System.assertEquals(
            null,
            TeamMemberSelector.getCustomNotificationTypeByDeveloperName('TMS_Notification_Does_Not_Exist'),
            'An unknown notification type should return null.'
        );
    }


    /**
     * @description Verifies users from nested public groups are also added
     *              to Opportunity Team Members.
     */
    @IsTest
    static void shouldAddUserFromNestedPublicGroup() {
        OpportunityTeamService.publicGroupDeveloperName = TEST_GROUP_DEVELOPER_NAME + '_Parent';
        OpportunityTeamService.sendNotifications = false;

        User adminUser = createSystemAdminUser('gcnest');
        insert adminUser;
        assignPermissionSetGroup(adminUser.Id);

        User teamUser = createSystemAdminUser('gcnestu');
        insert teamUser;

        Group parentGroup = createGroup(TEST_GROUP_DEVELOPER_NAME + '_Parent', 'GC2641 Parent');
        insert parentGroup;

        Group childGroup = createGroup(TEST_GROUP_DEVELOPER_NAME + '_Child', 'GC2641 Child');
        insert childGroup;

        insert new GroupMember(
            GroupId = parentGroup.Id,
            UserOrGroupId = childGroup.Id
        );

        insert new GroupMember(
            GroupId = childGroup.Id,
            UserOrGroupId = teamUser.Id
        );

        System.runAs(adminUser) {
            Account accountRecord = createAccount();
            insert accountRecord;

            Opportunity opportunityRecord = createOpportunity(accountRecord.Id, 'Onsite');
            insert opportunityRecord;

            Opportunity oldOpportunity = opportunityRecord.clone(false, true, false, false);
            oldOpportunity.Id = opportunityRecord.Id;
            oldOpportunity.StageName = 'Prospecting';

            Test.startTest();
            opportunityRecord.StageName = 'Proposal';
            update opportunityRecord;
            OpportunityTeamService.addSalesOpsContractTeamMembers(
                new List<Opportunity>{ opportunityRecord },
                new Map<Id, Opportunity>{ opportunityRecord.Id => oldOpportunity }
            );
            Test.stopTest();

            System.assertEquals(
                1,
                [
                    SELECT COUNT()
                    FROM OpportunityTeamMember
                    WHERE OpportunityId = :opportunityRecord.Id
                    AND UserId = :teamUser.Id
                ],
                'User from nested public group should be added to Opportunity Team.'
            );
        }
    }

    /**
     * @description Creates a test public group.
     */
    private static Group createGroup(String developerName, String groupName) {
        return new Group(
            Name = groupName,
            DeveloperName = developerName,
            Type = 'Regular'
        );
    }

    /**
     * @description Creates a test Account.
     */
    private static Account createAccount() {
        return new Account(
            Name = 'GC 2641 Test Account',
            SourceSystemID__c = 'GC2641TEST'
        );
    }

    
      /**
     * @description Creates an Instrument Processing test Opportunity with all
     *              fields required for Proposal stage validation.
     */
    private static Opportunity createOpportunity(Id accountId, String ipPillar) {
        Id recordTypeId = Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get('InstrumentProcessing')
            .getRecordTypeId();
    
        String pillarCategory;
        String solutionServiceLine;
    
        if (ipPillar == 'Mobile') {
            pillarCategory = 'Offsite';
            solutionServiceLine = 'Offsite-ORC';
        } else if (ipPillar == 'Onsite') {
            pillarCategory = 'Education';
            solutionServiceLine = 'Education Program';
        }
    
        return new Opportunity(
            Name = 'GC 2641 Test Opportunity',
            AccountId = accountId,
            RecordTypeId = recordTypeId,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
    
            Opportunity_Summary__c = 'Test opportunity summary for GC 2641',
            NextStep = 'Test next step',
            TotalOpportunityQuantity = 1,
            Term__c = 12,
            Unit_of_Measure__c = 'Monthly',
            IP_Pillar__c = ipPillar,
            Pillar_Category__c = pillarCategory,
            IP_Solution_Service_Line__c = solutionServiceLine
        );
    }
    /**
     * @description Creates a System Administrator test User.
     */
    private static User createSystemAdminUser(String aliasPrefix) {
        Profile adminProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];

        String uniqueValue = aliasPrefix + String.valueOf(DateTime.now().getTime());

        return new User(
            FirstName = 'GC',
            LastName = '2641 Admin',
            Alias = aliasPrefix.left(8),
            Email = uniqueValue + '@test.com',
            Username = uniqueValue + '@test.com',
            CommunityNickname = uniqueValue.left(40),
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

   /**
     * @description Assigns SalesFieldRepAccountManagerPSG permission set group
     *              to the runAs user and recalculates the PSG for test execution.
     */
    private static void assignPermissionSetGroup(Id userId) {
        PermissionSetGroup permissionSetGroupRecord = [
            SELECT Id
            FROM PermissionSetGroup
            WHERE DeveloperName = 'SalesFieldRepAccountManagerPSG'
            LIMIT 1
        ];
    
        insert new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetGroupId = permissionSetGroupRecord.Id
        );
    
        Test.calculatePermissionSetGroup(permissionSetGroupRecord.Id);
    }
    @IsTest
    static void shouldExecuteNotificationLogicWhenEnabled() {
        OpportunityTeamService.publicGroupDeveloperName = TEST_GROUP_DEVELOPER_NAME + '_Notify';
        OpportunityTeamService.sendNotifications = true;
    
        User adminUser = createSystemAdminUser('gcnotif');
        insert adminUser;
        assignPermissionSetGroup(adminUser.Id);
    
        User teamUser = createSystemAdminUser('gcnotifu');
        insert teamUser;
    
        Group testGroup = createGroup(TEST_GROUP_DEVELOPER_NAME + '_Notify', 'GC2641 Notify');
        insert testGroup;
    
        insert new GroupMember(
            GroupId = testGroup.Id,
            UserOrGroupId = teamUser.Id
        );
    
        System.runAs(adminUser) {
            Account accountRecord = createAccount();
            insert accountRecord;
    
            Opportunity opportunityRecord = createOpportunity(accountRecord.Id, 'Onsite');
            insert opportunityRecord;
    
            Opportunity oldOpportunity = opportunityRecord.clone(false, true, false, false);
            oldOpportunity.Id = opportunityRecord.Id;
            oldOpportunity.StageName = 'Prospecting';
    
            Test.startTest();
    
            opportunityRecord.StageName = 'Proposal';
            update opportunityRecord;
    
            OpportunityTeamService.addSalesOpsContractTeamMembers(
                new List<Opportunity>{ opportunityRecord },
                new Map<Id, Opportunity>{ opportunityRecord.Id => oldOpportunity }
            );
    
            Test.stopTest();
    
            System.assertEquals(
                1,
                [
                    SELECT COUNT()
                    FROM OpportunityTeamMember
                    WHERE OpportunityId = :opportunityRecord.Id
                    AND UserId = :teamUser.Id
                ],
                'Team member should be added and notification path should execute.'
            );
        }
    }
}