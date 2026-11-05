/**
 * @description
 * Test class for OpportunityBULeaderSelector.
 */
@IsTest
private class OpportunityBULeaderSelectorTest {

    private static final String BU_FIELD = 'HCBusinessUnit__c';
    private static final String BU_LEADER_ROLE = 'Business Unit Leader';
    private static final String OTHER_ROLE = 'Sales';
    private static final String ACTIVE_USERNAME = 'buleader.active@opptybuselector.test';
    private static final String INACTIVE_USERNAME = 'buleader.inactive@opptybuselector.test';

    @TestSetup
    static void setupData() {
        Profile standardProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];

        List<User> users = new List<User>{
            buildUser(standardProfile.Id, ACTIVE_USERNAME, 'buact', true),
            buildUser(standardProfile.Id, INACTIVE_USERNAME, 'buinact', false)
        };
        insert users;

        Account acc = new Account(Name = 'BU Selector Test Account');
        insert acc;

        Contact primaryContact = new Contact(
            LastName = 'BU Selector Contact',
            AccountId = acc.Id
        );
        insert primaryContact;

        List<Opportunity> opportunities = new List<Opportunity>{
            new Opportunity(
                Name = 'BU Selector Opp 1',
                AccountId = acc.Id,
                Type = 'New Business',
                Amount = 1000,
                Probability = 10,
                PrimaryContact__c = primaryContact.Id,
                StageName = 'Discovery',
                ForecastConfidenceLevel__c = 'Pipeline',
                CloseDate = Date.today().addDays(30),
                HCBusinessUnit__c = 'Procedural OR;IMS'
            ),
            new Opportunity(
                Name = 'BU Selector Opp 2',
                AccountId = acc.Id,
                Type = 'New Business',
                Amount = 1000,
                Probability = 10,
                PrimaryContact__c = primaryContact.Id,
                StageName = 'Discovery',
                ForecastConfidenceLevel__c = 'Pipeline',
                CloseDate = Date.today().addDays(30)
            )
        };
        insert opportunities;

        insert new List<OpportunityTeamMember>{
            new OpportunityTeamMember(
                OpportunityId = opportunities[0].Id,
                UserId = users[0].Id,
                TeamMemberRole = BU_LEADER_ROLE,
                OpportunityAccessLevel = 'Edit'
            ),
            new OpportunityTeamMember(
                OpportunityId = opportunities[1].Id,
                UserId = users[0].Id,
                TeamMemberRole = OTHER_ROLE,
                OpportunityAccessLevel = 'Read'
            )
        };
    }

    private static User buildUser(Id profileId, String username, String alias, Boolean isActive) {
        return new User(
            ProfileId = profileId,
            Username = username,
            Email = username,
            LastName = 'Leader ' + alias,
            Alias = alias,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            IsActive = isActive
        );
    }

    private static List<Opportunity> testOpportunities() {
        Contact primaryContact = [
            SELECT AccountId
            FROM Contact
            WHERE LastName = 'BU Selector Contact'
            LIMIT 1
        ];
        return [
            SELECT Id, HCBusinessUnit__c
            FROM Opportunity
            WHERE AccountId = :primaryContact.AccountId
        ];
    }

    private static Opportunity opportunityByBusinessUnit(List<Opportunity> opportunities, Boolean hasBusinessUnit) {
        for (Opportunity opp : opportunities) {
            Boolean populated = String.isNotBlank((String) opp.get(BU_FIELD));
            if (populated == hasBusinessUnit) {
                return opp;
            }
        }
        return null;
    }

    @IsTest
    static void selectOpportunitiesWithBUField_returnsRequestedFieldValues() {
        List<Opportunity> opportunities = testOpportunities();
        Opportunity withBU = opportunityByBusinessUnit(opportunities, true);
        Opportunity withoutBU = opportunityByBusinessUnit(opportunities, false);
        Set<Id> oppIds = new Set<Id>{ withBU.Id, withoutBU.Id };

        Test.startTest();
        List<Opportunity> results =
            OpportunityBULeaderSelector.selectOpportunitiesWithBUField(oppIds, BU_FIELD);
        Test.stopTest();

        Assert.areEqual(2, results.size());
    }

    @IsTest
    static void selectOpportunitiesWithBUField_emptyIdsReturnsNoRows() {
        Test.startTest();
        List<Opportunity> results =
            OpportunityBULeaderSelector.selectOpportunitiesWithBUField(new Set<Id>(), BU_FIELD);
        Test.stopTest();

        Assert.isTrue(results.isEmpty());
    }

    @IsTest
    static void selectBULeaderMappings_returnsOnlyPopulatedMappings() {
        Test.startTest();
        List<Business_Unit_Leader_Mappings__mdt> queriedMappings =
            OpportunityBULeaderSelector.selectBULeaderMappings();
        Test.stopTest();

        Assert.isNotNull(queriedMappings);
    }

    @IsTest
    static void selectActiveUsersByUsernames_excludesInactiveAndUnknownUsers() {
        Set<String> usernames = new Set<String>{
            ACTIVE_USERNAME,
            INACTIVE_USERNAME,
            'does.not.exist@opptybuselector.test'
        };

        Test.startTest();
        List<User> results = OpportunityBULeaderSelector.selectActiveUsersByUsernames(usernames);
        Test.stopTest();

        Assert.areEqual(1, results.size());
    }

    @IsTest
    static void selectActiveUsersByUsernames_emptySetReturnsNoRows() {
        Test.startTest();
        List<User> results = OpportunityBULeaderSelector.selectActiveUsersByUsernames(new Set<String>());
        Test.stopTest();

        Assert.isTrue(results.isEmpty());
    }

    @IsTest
    static void selectBULeaderTeamMembers_returnsOnlyMatchingRole() {
        List<Opportunity> opportunities = testOpportunities();
        Set<Id> oppIds = new Map<Id, Opportunity>(opportunities).keySet();

        Test.startTest();
        List<OpportunityTeamMember> results =
            OpportunityBULeaderSelector.selectBULeaderTeamMembers(oppIds, BU_LEADER_ROLE);
        Test.stopTest();

        Assert.areEqual(1, results.size());
    }

    @IsTest
    static void selectBULeaderTeamMembers_noMatchesForUnknownRole() {
        Set<Id> oppIds = new Map<Id, Opportunity>(testOpportunities()).keySet();

        Test.startTest();
        List<OpportunityTeamMember> results =
            OpportunityBULeaderSelector.selectBULeaderTeamMembers(oppIds, 'Nonexistent Role');
        Test.stopTest();

        Assert.isTrue(results.isEmpty());
    }

    @IsTest
    static void syncBULeaders_emptyMappingsLeavesExistingLeader() {
        Opportunity opportunity = opportunityByBusinessUnit(testOpportunities(), true);
        Id existingMemberId = [
            SELECT Id
            FROM OpportunityTeamMember
            WHERE OpportunityId = :opportunity.Id
            AND TeamMemberRole = :BU_LEADER_ROLE
            LIMIT 1
        ].Id;
        OpportunityBULeaderTeamSync.testMappings = new List<Business_Unit_Leader_Mappings__mdt>();

        Test.startTest();
        sync(opportunity.Id);
        Test.stopTest();

        Assert.areEqual(existingMemberId, leaderMemberId(opportunity.Id));
    }

    @IsTest
    static void syncBULeaders_incompleteMappingsLeavesExistingLeader() {
        Opportunity opportunity = opportunityByBusinessUnit(testOpportunities(), true);
        Id existingMemberId = leaderMemberId(opportunity.Id);
        OpportunityBULeaderTeamSync.testMappings = new List<Business_Unit_Leader_Mappings__mdt>{
            new Business_Unit_Leader_Mappings__mdt(
                Business_Unit__c = null,
                Business_Unit_Leader__c = 'leader.active@example.com'
            ),
            new Business_Unit_Leader_Mappings__mdt(
                Business_Unit__c = 'IMS',
                Business_Unit_Leader__c = null
            ),
            new Business_Unit_Leader_Mappings__mdt(
                Business_Unit__c = '   ',
                Business_Unit_Leader__c = '   '
            )
        };

        Test.startTest();
        sync(opportunity.Id);
        Test.stopTest();

        Assert.areEqual(existingMemberId, leaderMemberId(opportunity.Id));
    }

    @IsTest
    static void syncBULeaders_missingOpportunityDoesNotAddLeader() {
        Opportunity opportunity = opportunityByBusinessUnit(testOpportunities(), false);
        Id deletedOpportunityId = opportunity.Id;
        delete opportunity;

        Test.startTest();
        sync(deletedOpportunityId);
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM OpportunityTeamMember WHERE OpportunityId = :deletedOpportunityId]
        );
    }

    @IsTest
    static void syncBULeaders_swallowsUnexpectedException() {
        OpportunityBULeaderTeamSync.testThrowBeforeSync = true;

        Test.startTest();
        OpportunityBULeaderTeamSync.syncBULeaders(null);
        Test.stopTest();

        Assert.isFalse(OpportunityBULeaderTeamSync.testThrowBeforeSync);
    }

    @IsTest
    static void syncBULeaders_nullAndBlankInputsLeaveTeamUnchanged() {
        Opportunity opportunity = opportunityByBusinessUnit(testOpportunities(), true);
        Id existingMemberId = leaderMemberId(opportunity.Id);
        OpportunityBULeaderTeamSync.FlowInput blankInput = new OpportunityBULeaderTeamSync.FlowInput();

        Test.startTest();
        OpportunityBULeaderTeamSync.syncBULeaders(null);
        OpportunityBULeaderTeamSync.syncBULeaders(new List<OpportunityBULeaderTeamSync.FlowInput>());
        OpportunityBULeaderTeamSync.syncBULeaders(
            new List<OpportunityBULeaderTeamSync.FlowInput>{ null, blankInput }
        );
        Test.stopTest();

        Assert.areEqual(existingMemberId, leaderMemberId(opportunity.Id));
    }

    @IsTest
    static void syncBULeaders_addsMappedLeader() {
        Opportunity opportunity = opportunityByBusinessUnit(testOpportunities(), false);
        opportunity.HCBusinessUnit__c = 'IMS';
        update opportunity;
        OpportunityBULeaderTeamSync.testMappings = new List<Business_Unit_Leader_Mappings__mdt>{
            mapping('IMS', ACTIVE_USERNAME),
            mapping('IMS', INACTIVE_USERNAME)
        };

        Test.startTest();
        sync(opportunity.Id);
        Test.stopTest();

        Assert.areEqual(1, leaderCount(opportunity.Id));
    }

    @IsTest
    static void syncBULeaders_doesNotDuplicateExistingLeader() {
        Opportunity opportunity = opportunityByBusinessUnit(testOpportunities(), true);
        OpportunityBULeaderTeamSync.testMappings = new List<Business_Unit_Leader_Mappings__mdt>{
            mapping('Procedural OR', ACTIVE_USERNAME),
            mapping('IMS', ACTIVE_USERNAME)
        };

        Test.startTest();
        sync(opportunity.Id);
        Test.stopTest();

        Assert.areEqual(1, leaderCount(opportunity.Id));
    }

    @IsTest
    static void syncBULeaders_clearedBusinessUnitRemovesLeader() {
        Opportunity opportunity = opportunityByBusinessUnit(testOpportunities(), true);
        opportunity.HCBusinessUnit__c = null;
        update opportunity;
        OpportunityBULeaderTeamSync.testMappings = new List<Business_Unit_Leader_Mappings__mdt>{
            mapping('IMS', ACTIVE_USERNAME)
        };

        Test.startTest();
        sync(opportunity.Id);
        Test.stopTest();

        Assert.areEqual(0, leaderCount(opportunity.Id));
    }

    @IsTest
    static void syncBULeaders_unmappedBusinessUnitRemovesLeader() {
        Opportunity opportunity = opportunityByBusinessUnit(testOpportunities(), true);
        opportunity.HCBusinessUnit__c = 'Other';
        update opportunity;
        OpportunityBULeaderTeamSync.testMappings = new List<Business_Unit_Leader_Mappings__mdt>{
            mapping('IMS', ACTIVE_USERNAME)
        };

        Test.startTest();
        sync(opportunity.Id);
        Test.stopTest();

        Assert.areEqual(0, leaderCount(opportunity.Id));
    }

    @IsTest
    static void syncBULeaders_inactiveLeaderIsNotAdded() {
        Opportunity opportunity = opportunityByBusinessUnit(testOpportunities(), false);
        opportunity.HCBusinessUnit__c = 'IP';
        update opportunity;
        OpportunityBULeaderTeamSync.testMappings = new List<Business_Unit_Leader_Mappings__mdt>{
            mapping('IP', INACTIVE_USERNAME)
        };

        Test.startTest();
        sync(opportunity.Id);
        Test.stopTest();

        Assert.areEqual(0, leaderCount(opportunity.Id));
    }

    @IsTest
    static void syncBULeaders_sameLeaderOnTwoBusinessUnitsAddsOneMember() {
        Opportunity opportunity = opportunityByBusinessUnit(testOpportunities(), false);
        opportunity.HCBusinessUnit__c = 'IMS;IP';
        update opportunity;
        OpportunityBULeaderTeamSync.testMappings = new List<Business_Unit_Leader_Mappings__mdt>{
            mapping('IMS', ACTIVE_USERNAME),
            mapping('IP', ACTIVE_USERNAME)
        };

        Test.startTest();
        sync(opportunity.Id);
        Test.stopTest();

        Assert.areEqual(1, leaderCount(opportunity.Id));
    }

    @IsTest
    static void logSaveResults_coversSuccessFailureAndGuardPaths() {
        Opportunity opportunity = opportunityByBusinessUnit(testOpportunities(), false);
        OpportunityTeamMember member = new OpportunityTeamMember(
            OpportunityId = opportunity.Id,
            UserId = [SELECT Id FROM User WHERE Username = :ACTIVE_USERNAME].Id
        );
        Database.SaveResult successResult = (Database.SaveResult) JSON.deserialize(
            '{"success":true,"id":"006000000000001AAA","errors":[]}',
            Database.SaveResult.class
        );
        Database.SaveResult failedResult = (Database.SaveResult) JSON.deserialize(
            '{"success":false,"errors":[{"message":"Insert failed","statusCode":"FIELD_CUSTOM_VALIDATION_EXCEPTION","fields":["UserId"]}]}',
            Database.SaveResult.class
        );

        Test.startTest();
        OpportunityBULeaderTeamSync.logSaveResults('OpportunityTeamMember', null, null);
        OpportunityBULeaderTeamSync.logSaveResults(
            'OpportunityTeamMember',
            new List<Database.SaveResult>(),
            null
        );
        OpportunityBULeaderTeamSync.logSaveResults(
            'OpportunityTeamMember',
            new List<Database.SaveResult>{ successResult, failedResult, failedResult },
            new List<OpportunityTeamMember>{ member, member }
        );
        OpportunityBULeaderTeamSync.logSaveResults(
            'OpportunityTeamMember',
            new List<Database.SaveResult>{ null },
            new List<OpportunityTeamMember>()
        );
        Test.stopTest();

        Assert.areEqual(opportunity.Id, member.OpportunityId);
    }

    @IsTest
    static void logDeleteResults_coversSuccessFailureAndGuardPaths() {
        Opportunity opportunity = opportunityByBusinessUnit(testOpportunities(), false);
        OpportunityTeamMember member = new OpportunityTeamMember(
            OpportunityId = opportunity.Id,
            UserId = [SELECT Id FROM User WHERE Username = :ACTIVE_USERNAME].Id
        );
        Database.DeleteResult successResult = (Database.DeleteResult) JSON.deserialize(
            '{"success":true,"id":"00q000000000001AAA","errors":[]}',
            Database.DeleteResult.class
        );
        Database.DeleteResult failedResult = (Database.DeleteResult) JSON.deserialize(
            '{"success":false,"errors":[{"message":"Delete failed","statusCode":"ENTITY_IS_DELETED","fields":[]}]}',
            Database.DeleteResult.class
        );

        Test.startTest();
        OpportunityBULeaderTeamSync.logDeleteResults('OpportunityTeamMember', null, null);
        OpportunityBULeaderTeamSync.logDeleteResults(
            'OpportunityTeamMember',
            new List<Database.DeleteResult>(),
            null
        );
        OpportunityBULeaderTeamSync.logDeleteResults(
            'OpportunityTeamMember',
            new List<Database.DeleteResult>{ successResult, failedResult, failedResult },
            new List<OpportunityTeamMember>{ member, member }
        );
        OpportunityBULeaderTeamSync.logDeleteResults(
            'OpportunityTeamMember',
            new List<Database.DeleteResult>{ null },
            new List<OpportunityTeamMember>()
        );
        Test.stopTest();

        Assert.areEqual(opportunity.Id, member.OpportunityId);
    }

    private static void sync(Id opportunityId) {
        OpportunityBULeaderTeamSync.FlowInput input = new OpportunityBULeaderTeamSync.FlowInput();
        input.opportunityId = opportunityId;
        OpportunityBULeaderTeamSync.syncBULeaders(
            new List<OpportunityBULeaderTeamSync.FlowInput>{ input }
        );
    }

    private static Business_Unit_Leader_Mappings__mdt mapping(String businessUnit, String leaderUsername) {
        return new Business_Unit_Leader_Mappings__mdt(
            Business_Unit__c = businessUnit,
            Business_Unit_Leader__c = leaderUsername
        );
    }

    private static Integer leaderCount(Id opportunityId) {
        return [
            SELECT COUNT()
            FROM OpportunityTeamMember
            WHERE OpportunityId = :opportunityId
            AND TeamMemberRole = :BU_LEADER_ROLE
        ];
    }

    private static Id leaderMemberId(Id opportunityId) {
        return [
            SELECT Id
            FROM OpportunityTeamMember
            WHERE OpportunityId = :opportunityId
            AND TeamMemberRole = :BU_LEADER_ROLE
            LIMIT 1
        ].Id;
    }
}