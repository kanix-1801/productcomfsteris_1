/**
 * @description Test class for TeamMemberSelector.
 *              Covers Opportunity Team Member, Public Group, Group Member,
 *              Custom Notification Type, and Queue lookups.
 * @author      : Vinay
 * @date        : 2026-10-29
 */
@IsTest
private class TeamMemberSelectorTest {

    /**
     * @description Verifies team, group, and queue records are returned when they exist.
     */
    @IsTest
    static void returnsMatchingTeamGroupAndQueue() {
        User teamUser = createUser('tmsel');
        insert teamUser;

        String groupDeveloperName = 'TMSCov' + String.valueOf(DateTime.now().getTime());
        Group publicGroup = new Group(
            Name = 'Team Member Selector Group',
            DeveloperName = groupDeveloperName,
            Type = 'Regular'
        );
        insert publicGroup;

        insert new GroupMember(
            GroupId = publicGroup.Id,
            UserOrGroupId = teamUser.Id
        );

        String queueDeveloperName = 'TMSQueue' + String.valueOf(DateTime.now().getTime());
        Group queueGroup = new Group(
            Name = 'Team Member Selector Queue',
            DeveloperName = queueDeveloperName,
            Type = 'Queue'
        );
        insert queueGroup;

        System.runAs(teamUser) {
            Account accountRecord = new Account(
                Name = 'Team Member Selector Account',
                SourceSystemID__c = 'TMS' + String.valueOf(DateTime.now().getTime())
            );
            insert accountRecord;

            Contact contactRecord = new Contact(
                FirstName = 'Team',
                LastName = 'Selector',
                AccountId = accountRecord.Id,
                Email = 'teamselector' + String.valueOf(DateTime.now().getTime()) + '@test.com'
            );
            insert contactRecord;

            Opportunity opportunityRecord = new Opportunity(
                Name = 'Team Member Selector Opportunity',
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

            insert new OpportunityTeamMember(
                OpportunityId = opportunityRecord.Id,
                UserId = teamUser.Id,
                TeamMemberRole = 'Temporary Assignment',
                OpportunityAccessLevel = 'Edit'
            );

            Test.startTest();
            List<OpportunityTeamMember> teamMembers =
                TeamMemberSelector.getOpportunityTeamMembersByOpportunityIdsAndUserIds(
                    new Set<Id>{ opportunityRecord.Id },
                    new Set<Id>{ teamUser.Id }
                );
            Group selectedGroup = TeamMemberSelector.getPublicGroupByDeveloperName(groupDeveloperName);
            List<GroupMember> groupMembers =
                TeamMemberSelector.getGroupMembersByGroupIds(new Set<Id>{ publicGroup.Id });
            Id queueId = TeamMemberSelector.getQueueIdByDeveloperName(queueDeveloperName);
            Test.stopTest();

            System.assertEquals(1, teamMembers.size(), 'Opportunity Team Member should be returned.');
            System.assertEquals(
                opportunityRecord.Id,
                teamMembers[0].OpportunityId,
                'Opportunity Id should match.'
            );
            System.assertNotEquals(null, selectedGroup, 'Public Group should be returned.');
            System.assertEquals(groupDeveloperName, selectedGroup.DeveloperName, 'Public Group name should match.');
            System.assertEquals(1, groupMembers.size(), 'Group Member should be returned.');
            System.assertEquals(teamUser.Id, groupMembers[0].UserOrGroupId, 'Group Member user should match.');
            System.assertEquals(queueGroup.Id, queueId, 'Queue Id should match.');
        }
    }

    /**
     * @description Verifies blank and unknown filters return null or no rows.
     */
    @IsTest
    static void returnsEmptyWhenFiltersDoNotMatch() {
        Test.startTest();
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
            null,
            TeamMemberSelector.getCustomNotificationTypeByDeveloperName(''),
            'A blank notification type should return null.'
        );
        System.assertEquals(
            null,
            TeamMemberSelector.getCustomNotificationTypeByDeveloperName('TMS_Notification_Does_Not_Exist'),
            'An unknown notification type should return null.'
        );
        System.assertEquals(
            null,
            TeamMemberSelector.getQueueIdByDeveloperName(''),
            'A blank queue name should return null.'
        );
        System.assertEquals(
            null,
            TeamMemberSelector.getQueueIdByDeveloperName('TMS_Queue_Does_Not_Exist'),
            'An unknown queue should return null.'
        );
        Test.stopTest();
    }

    /**
     * @description Creates a System Administrator user for selector data setup.
     */
    private static User createUser(String aliasPrefix) {
        Profile adminProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];

        String uniqueValue = aliasPrefix + String.valueOf(DateTime.now().getTime());

        return new User(
            FirstName = 'Team',
            LastName = 'Selector',
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
}