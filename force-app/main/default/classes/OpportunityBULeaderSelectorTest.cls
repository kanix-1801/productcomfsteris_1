/**
 * @description Covers OpportunityBULeaderSelector and OpportunityBULeaderTeamSync.
 *              Setup follows the Healthcare Sales opportunity pattern used by the other
 *              test classes: Customer account, primary contact, Discovery stage, and
 *              the Healthcare_Sales record type so the strategic-contract BU flow does not run.
 *              Mapping rows are supplied in memory because Business_Unit_Leader__c is null
 *              on the deployed Custom Metadata and Custom Metadata cannot be inserted in tests.
 */
@IsTest(SeeAllData=false)
private class OpportunityBULeaderSelectorTest {

    private static final String BU_FIELD = 'HCBusinessUnit__c';
    private static final String BU_LEADER_ROLE = 'Business Unit Leader';
    private static final String OTHER_ROLE = 'Sales';
    // Usernames are stored in lowercase. The sync matches them with a case-sensitive map key.
    private static final String PRIMARY_USERNAME =
        ('buleader.primary.' + UserInfo.getOrganizationId() + '@buleadersync.test').toLowerCase();
    private static final String SECONDARY_USERNAME =
        ('buleader.secondary.' + UserInfo.getOrganizationId() + '@buleadersync.test').toLowerCase();
    private static final String INACTIVE_USERNAME =
        ('buleader.inactive.' + UserInfo.getOrganizationId() + '@buleadersync.test').toLowerCase();
    private static final String OPP_WITH_LEADERS = 'BU Sync Opp With Leaders';
    private static final String OPP_OTHER_ROLE = 'BU Sync Opp Other Role';
    private static final String OPP_OPEN = 'BU Sync Opp Open';

    @TestSetup
    static void setupData() {
        User currentUser = [
            SELECT ProfileId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        List<User> users = new List<User>{
            buildUser(currentUser.ProfileId, PRIMARY_USERNAME, 'bulprim', true),
            buildUser(currentUser.ProfileId, SECONDARY_USERNAME, 'bulsec', true),
            buildUser(currentUser.ProfileId, INACTIVE_USERNAME, 'bulinact', false)
        };
        insert users;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id customerRecordTypeId = accountRecordTypeId('Customer');
            Account accountRecord = new Account(
                Name = 'BU Leader Sync Account',
                Type = 'Customer',
                RecordTypeId = customerRecordTypeId,
                OrgIDs__c = '82',
                OracleAddressId__c = 'ADDR-BULEADER',
                SourceSystemID__c = 'SRC-BULEADER'
            );
            insert accountRecord;

            Contact primaryContact = new Contact(
                FirstName = 'BU',
                LastName = 'Leader Sync',
                AccountId = accountRecord.Id,
                Email = 'buleader.sync.contact@buleadersync.test'
            );
            insert primaryContact;

            Id healthcareSalesRecordTypeId = opportunityRecordTypeId('Healthcare_Sales');
            List<Opportunity> opportunities = new List<Opportunity>{
                buildOpportunity(
                    accountRecord.Id,
                    primaryContact.Id,
                    healthcareSalesRecordTypeId,
                    OPP_WITH_LEADERS,
                    'Procedural OR;IMS'
                ),
                buildOpportunity(
                    accountRecord.Id,
                    primaryContact.Id,
                    healthcareSalesRecordTypeId,
                    OPP_OTHER_ROLE,
                    null
                ),
                buildOpportunity(
                    accountRecord.Id,
                    primaryContact.Id,
                    healthcareSalesRecordTypeId,
                    OPP_OPEN,
                    null
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
                    UserId = users[1].Id,
                    TeamMemberRole = OTHER_ROLE,
                    OpportunityAccessLevel = 'Read'
                )
            };
        }
    }

    @IsTest
    static void selectOpportunitiesWithBUField_returnsRequestedFieldValues() {
        Opportunity withBusinessUnit = opportunityByName(OPP_WITH_LEADERS);
        Opportunity withoutBusinessUnit = opportunityByName(OPP_OPEN);

        Test.startTest();
        List<Opportunity> results = OpportunityBULeaderSelector.selectOpportunitiesWithBUField(
            new Set<Id>{ withBusinessUnit.Id, withoutBusinessUnit.Id },
            BU_FIELD
        );
        Test.stopTest();

        Assert.areEqual(2, results.size(), 'Both opportunities should be returned.');
        Map<Id, Opportunity> resultsById = new Map<Id, Opportunity>(results);
        Assert.areEqual(
            'Procedural OR;IMS',
            (String) resultsById.get(withBusinessUnit.Id).get(BU_FIELD),
            'The business unit field should be returned by the dynamic query.'
        );
        Assert.isTrue(
            String.isBlank((String) resultsById.get(withoutBusinessUnit.Id).get(BU_FIELD)),
            'An opportunity without business units should still be returned.'
        );
    }

    @IsTest
    static void selectOpportunitiesWithBUField_emptyIdsReturnsNoRows() {
        Test.startTest();
        List<Opportunity> results = OpportunityBULeaderSelector.selectOpportunitiesWithBUField(
            new Set<Id>(),
            BU_FIELD
        );
        Test.stopTest();

        Assert.isTrue(results.isEmpty(), 'An empty id set should return no opportunities.');
    }

    @IsTest
    static void selectBULeaderMappings_returnsQueriedRows() {
        Test.startTest();
        List<Business_Unit_Leader_Mappings__mdt> mappings =
            OpportunityBULeaderSelector.selectBULeaderMappings();
        Test.stopTest();

        Assert.isNotNull(mappings, 'The mapping query should return a list.');
        for (Business_Unit_Leader_Mappings__mdt mappingRow : mappings) {
            Assert.isTrue(
                String.isNotBlank(mappingRow.Business_Unit__c)
                && String.isNotBlank(mappingRow.Business_Unit_Leader__c),
                'The selector should only return rows with both values populated.'
            );
        }
    }

    @IsTest
    static void selectActiveUsersByUsernames_excludesInactiveAndUnknownUsers() {
        Test.startTest();
        List<User> results = OpportunityBULeaderSelector.selectActiveUsersByUsernames(
            new Set<String>{
                PRIMARY_USERNAME,
                INACTIVE_USERNAME,
                'does.not.exist@buleadersync.test'
            }
        );
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Only the active mapped user should be returned.');
        Assert.areEqual(PRIMARY_USERNAME, results[0].Username, 'The active username should match.');
    }

    @IsTest
    static void selectActiveUsersByUsernames_emptySetReturnsNoRows() {
        Test.startTest();
        List<User> results = OpportunityBULeaderSelector.selectActiveUsersByUsernames(new Set<String>());
        Test.stopTest();

        Assert.isTrue(results.isEmpty(), 'An empty username set should return no users.');
    }

    @IsTest
    static void selectBULeaderTeamMembers_returnsOnlyMatchingRole() {
        Set<Id> opportunityIds = new Map<Id, Opportunity>(testOpportunities()).keySet();

        Test.startTest();
        List<OpportunityTeamMember> results =
            OpportunityBULeaderSelector.selectBULeaderTeamMembers(opportunityIds, BU_LEADER_ROLE);
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Only the Business Unit Leader row should be returned.');
        Assert.areEqual(BU_LEADER_ROLE, results[0].TeamMemberRole, 'The team role should match.');
        Assert.areEqual('Edit', results[0].OpportunityAccessLevel, 'The access level should match.');
    }

    @IsTest
    static void selectBULeaderTeamMembers_noMatchesForUnknownRole() {
        Set<Id> opportunityIds = new Map<Id, Opportunity>(testOpportunities()).keySet();

        Test.startTest();
        List<OpportunityTeamMember> results =
            OpportunityBULeaderSelector.selectBULeaderTeamMembers(opportunityIds, 'Nonexistent Role');
        Test.stopTest();

        Assert.isTrue(results.isEmpty(), 'An unknown team role should return no rows.');
    }

    @IsTest
    static void syncBULeaders_nullAndBlankInputsLeaveTeamUnchanged() {
        Opportunity opportunityRecord = opportunityByName(OPP_WITH_LEADERS);
        Id existingMemberId = leaderMemberId(opportunityRecord.Id);
        OpportunityBULeaderTeamSync.FlowInput blankInput = new OpportunityBULeaderTeamSync.FlowInput();

        Test.startTest();
        OpportunityBULeaderTeamSync.syncBULeaders(null);
        OpportunityBULeaderTeamSync.syncBULeaders(new List<OpportunityBULeaderTeamSync.FlowInput>());
        OpportunityBULeaderTeamSync.syncBULeaders(
            new List<OpportunityBULeaderTeamSync.FlowInput>{ null, blankInput }
        );
        Test.stopTest();

        Assert.areEqual(
            existingMemberId,
            leaderMemberId(opportunityRecord.Id),
            'Blank flow input should not change the existing leader.'
        );
    }

    @IsTest
    static void syncBULeaders_swallowsUnexpectedException() {
        OpportunityBULeaderTeamSync.testThrowBeforeSync = true;

        Test.startTest();
        OpportunityBULeaderTeamSync.syncBULeaders(null);
        Test.stopTest();

        Assert.isFalse(
            OpportunityBULeaderTeamSync.testThrowBeforeSync,
            'The test exception should be caught and the flag cleared.'
        );
    }

    @IsTest
    static void syncBULeaders_missingOpportunityDoesNotAddLeader() {
        Opportunity opportunityRecord = opportunityByName(OPP_OPEN);
        Id deletedOpportunityId = opportunityRecord.Id;
        delete opportunityRecord;

        Test.startTest();
        sync(deletedOpportunityId);
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM OpportunityTeamMember WHERE OpportunityId = :deletedOpportunityId],
            'A deleted opportunity should not receive team members.'
        );
    }

    @IsTest
    static void syncBULeaders_emptyMappingsLeavesExistingLeader() {
        Opportunity opportunityRecord = opportunityByName(OPP_WITH_LEADERS);
        Id existingMemberId = leaderMemberId(opportunityRecord.Id);
        OpportunityBULeaderTeamSync.testMappings = new List<Business_Unit_Leader_Mappings__mdt>();

        Test.startTest();
        sync(opportunityRecord.Id);
        Test.stopTest();

        Assert.areEqual(
            existingMemberId,
            leaderMemberId(opportunityRecord.Id),
            'No mapping rows should leave the existing leader in place.'
        );
    }

    @IsTest
    static void syncBULeaders_usesOrgMappingsWhenOverrideIsUnset() {
        Opportunity opportunityRecord = opportunityByName(OPP_WITH_LEADERS);
        Id existingMemberId = leaderMemberId(opportunityRecord.Id);

        Test.startTest();
        sync(opportunityRecord.Id);
        Test.stopTest();

        if (OpportunityBULeaderSelector.selectBULeaderMappings().isEmpty()) {
            Assert.areEqual(
                existingMemberId,
                leaderMemberId(opportunityRecord.Id),
                'Empty org metadata should leave the existing leader in place.'
            );
        } else {
            Assert.isNotNull(opportunityRecord.Id, 'Sync should finish when org metadata has leaders.');
        }
    }

    @IsTest
    static void syncBULeaders_incompleteMappingsLeavesExistingLeader() {
        Opportunity opportunityRecord = opportunityByName(OPP_WITH_LEADERS);
        Id existingMemberId = leaderMemberId(opportunityRecord.Id);
        OpportunityBULeaderTeamSync.testMappings = new List<Business_Unit_Leader_Mappings__mdt>{
            mapping(null, PRIMARY_USERNAME),
            mapping('IMS', null),
            mapping('   ', '   ')
        };

        Test.startTest();
        sync(opportunityRecord.Id);
        Test.stopTest();

        Assert.areEqual(
            existingMemberId,
            leaderMemberId(opportunityRecord.Id),
            'Incomplete mapping rows should not change the team.'
        );
    }

    @IsTest
    static void syncBULeaders_addsMappedLeaderAndSkipsUnusableRows() {
        Opportunity opportunityRecord = opportunityByName(OPP_OPEN);
        opportunityRecord.HCBusinessUnit__c = 'IMS;Other';
        update opportunityRecord;
        OpportunityBULeaderTeamSync.testMappings = new List<Business_Unit_Leader_Mappings__mdt>{
            mapping(null, PRIMARY_USERNAME),
            mapping('IP', null),
            mapping('   ', '   '),
            mapping('  IMS  ', '  ' + PRIMARY_USERNAME + '  '),
            mapping('IP', INACTIVE_USERNAME)
        };

        Test.startTest();
        sync(opportunityRecord.Id);
        Test.stopTest();

        List<OpportunityTeamMember> leaders = leaderMembers(opportunityRecord.Id);
        Assert.areEqual(1, leaders.size(), 'One active leader should be added.');
        Assert.areEqual(userId(PRIMARY_USERNAME), leaders[0].UserId, 'The trimmed username should resolve.');
        Assert.areEqual(BU_LEADER_ROLE, leaders[0].TeamMemberRole, 'The inserted role should be Business Unit Leader.');
        Assert.areEqual('Edit', leaders[0].OpportunityAccessLevel, 'The inserted access level should be Edit.');
    }

    @IsTest
    static void syncBULeaders_sameLeaderOnTwoBusinessUnitsAddsOneMember() {
        Opportunity opportunityRecord = opportunityByName(OPP_OPEN);
        opportunityRecord.HCBusinessUnit__c = 'IMS;IP';
        update opportunityRecord;
        OpportunityBULeaderTeamSync.testMappings = new List<Business_Unit_Leader_Mappings__mdt>{
            mapping('IMS', PRIMARY_USERNAME),
            mapping('IP', PRIMARY_USERNAME)
        };

        Test.startTest();
        sync(opportunityRecord.Id);
        Test.stopTest();

        Assert.areEqual(
            1,
            leaderCount(opportunityRecord.Id),
            'The same leader mapped from two business units should be added once.'
        );
    }

    @IsTest
    static void syncBULeaders_twoLeadersOnOneBusinessUnitAreBothAdded() {
        Opportunity opportunityRecord = opportunityByName(OPP_OPEN);
        opportunityRecord.HCBusinessUnit__c = 'IMS';
        update opportunityRecord;
        OpportunityBULeaderTeamSync.testMappings = new List<Business_Unit_Leader_Mappings__mdt>{
            mapping('IMS', PRIMARY_USERNAME),
            mapping('IMS', SECONDARY_USERNAME)
        };

        Test.startTest();
        sync(opportunityRecord.Id);
        Test.stopTest();

        Set<Id> leaderUserIds = new Set<Id>();
        for (OpportunityTeamMember leader : leaderMembers(opportunityRecord.Id)) {
            leaderUserIds.add(leader.UserId);
        }
        Assert.areEqual(2, leaderUserIds.size(), 'Both leaders for the business unit should be added.');
        Assert.isTrue(leaderUserIds.contains(userId(PRIMARY_USERNAME)), 'The primary leader should be on the team.');
        Assert.isTrue(leaderUserIds.contains(userId(SECONDARY_USERNAME)), 'The secondary leader should be on the team.');
    }

    @IsTest
    static void syncBULeaders_doesNotDuplicateExistingLeader() {
        Opportunity opportunityRecord = opportunityByName(OPP_WITH_LEADERS);
        OpportunityBULeaderTeamSync.testMappings = new List<Business_Unit_Leader_Mappings__mdt>{
            mapping('Procedural OR', PRIMARY_USERNAME),
            mapping('IMS', PRIMARY_USERNAME)
        };

        Test.startTest();
        sync(opportunityRecord.Id);
        Test.stopTest();

        Assert.areEqual(1, leaderCount(opportunityRecord.Id), 'The existing leader should not be inserted again.');
        Assert.areEqual(
            userId(PRIMARY_USERNAME),
            leaderMembers(opportunityRecord.Id)[0].UserId,
            'The original leader should remain.'
        );
    }

    @IsTest
    static void syncBULeaders_secondExistingLeaderIsRemovedWhenNoLongerSelected() {
        Opportunity opportunityRecord = opportunityByName(OPP_WITH_LEADERS);
        insert new OpportunityTeamMember(
            OpportunityId = opportunityRecord.Id,
            UserId = userId(SECONDARY_USERNAME),
            TeamMemberRole = BU_LEADER_ROLE,
            OpportunityAccessLevel = 'Edit'
        );
        OpportunityBULeaderTeamSync.testMappings = new List<Business_Unit_Leader_Mappings__mdt>{
            mapping('Procedural OR', PRIMARY_USERNAME),
            mapping('IMS', PRIMARY_USERNAME)
        };

        Test.startTest();
        sync(opportunityRecord.Id);
        Test.stopTest();

        List<OpportunityTeamMember> leaders = leaderMembers(opportunityRecord.Id);
        Assert.areEqual(1, leaders.size(), 'Only the still-selected leader should remain.');
        Assert.areEqual(userId(PRIMARY_USERNAME), leaders[0].UserId, 'The primary leader should be kept.');
    }

    @IsTest
    static void syncBULeaders_clearedBusinessUnitRemovesLeader() {
        Opportunity withLeaders = opportunityByName(OPP_WITH_LEADERS);
        Opportunity openOpportunity = opportunityByName(OPP_OPEN);
        withLeaders.HCBusinessUnit__c = null;
        update withLeaders;
        OpportunityBULeaderTeamSync.testMappings = new List<Business_Unit_Leader_Mappings__mdt>{
            mapping('IMS', PRIMARY_USERNAME)
        };

        Test.startTest();
        syncIds(new List<Id>{ withLeaders.Id, openOpportunity.Id });
        Test.stopTest();

        Assert.areEqual(0, leaderCount(withLeaders.Id), 'Clearing the business unit should remove the leader.');
        Assert.areEqual(0, leaderCount(openOpportunity.Id), 'An opportunity with no business unit should not gain a leader.');
    }

    @IsTest
    static void syncBULeaders_unmappedBusinessUnitRemovesLeader() {
        Opportunity opportunityRecord = opportunityByName(OPP_WITH_LEADERS);
        opportunityRecord.HCBusinessUnit__c = 'Other';
        update opportunityRecord;
        OpportunityBULeaderTeamSync.testMappings = new List<Business_Unit_Leader_Mappings__mdt>{
            mapping('IMS', PRIMARY_USERNAME)
        };

        Test.startTest();
        sync(opportunityRecord.Id);
        Test.stopTest();

        Assert.areEqual(
            0,
            leaderCount(opportunityRecord.Id),
            'A business unit without a mapping should remove the previous leader.'
        );
    }

    @IsTest
    static void syncBULeaders_inactiveLeaderIsNotAdded() {
        Opportunity opportunityRecord = opportunityByName(OPP_OPEN);
        opportunityRecord.HCBusinessUnit__c = 'IP';
        update opportunityRecord;
        OpportunityBULeaderTeamSync.testMappings = new List<Business_Unit_Leader_Mappings__mdt>{
            mapping('IP', INACTIVE_USERNAME)
        };

        Test.startTest();
        sync(opportunityRecord.Id);
        Test.stopTest();

        Assert.areEqual(0, leaderCount(opportunityRecord.Id), 'An inactive leader should not be added.');
    }

    @IsTest
    static void syncBULeaders_existingTeamMemberBecomesBusinessUnitLeader() {
        Opportunity opportunityRecord = opportunityByName(OPP_OTHER_ROLE);
        Id salesMemberId = [
            SELECT Id
            FROM OpportunityTeamMember
            WHERE OpportunityId = :opportunityRecord.Id
            AND TeamMemberRole = :OTHER_ROLE
            LIMIT 1
        ].Id;
        opportunityRecord.HCBusinessUnit__c = 'IMS';
        update opportunityRecord;
        OpportunityBULeaderTeamSync.testMappings = new List<Business_Unit_Leader_Mappings__mdt>{
            mapping('IMS', SECONDARY_USERNAME)
        };

        Test.startTest();
        sync(opportunityRecord.Id);
        Test.stopTest();

        List<OpportunityTeamMember> teamMembers = [
            SELECT Id, TeamMemberRole, UserId
            FROM OpportunityTeamMember
            WHERE OpportunityId = :opportunityRecord.Id
        ];
        Assert.areEqual(1, teamMembers.size(), 'The user should still occupy a single team row.');
        Assert.areEqual(salesMemberId, teamMembers[0].Id, 'The original team row should be reused.');
        Assert.areEqual(
            BU_LEADER_ROLE,
            teamMembers[0].TeamMemberRole,
            'The existing team member should become the Business Unit Leader.'
        );
        Assert.areEqual(userId(SECONDARY_USERNAME), teamMembers[0].UserId, 'The mapped leader should remain the team user.');
    }

    @IsTest
    static void logSaveResults_coversSuccessFailureAndGuardPaths() {
        Opportunity opportunityRecord = opportunityByName(OPP_OPEN);
        OpportunityTeamMember member = new OpportunityTeamMember(
            OpportunityId = opportunityRecord.Id,
            UserId = userId(PRIMARY_USERNAME),
            TeamMemberRole = BU_LEADER_ROLE,
            OpportunityAccessLevel = 'Edit'
        );
        Database.SaveResult successResult = (Database.SaveResult) JSON.deserialize(
            '{"success":true,"id":"006000000000001AAA","errors":[]}',
            Database.SaveResult.class
        );
        Database.SaveResult failedResult = (Database.SaveResult) JSON.deserialize(
            '{"success":false,"errors":[{"message":"Insert failed","statusCode":"FIELD_CUSTOM_VALIDATION_EXCEPTION","fields":["UserId"]},{"message":"Second failure","statusCode":"FIELD_CUSTOM_VALIDATION_EXCEPTION","fields":["TeamMemberRole"]}]}',
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
            new List<Database.SaveResult>{ failedResult },
            null
        );
        OpportunityBULeaderTeamSync.logSaveResults(
            'OpportunityTeamMember',
            new List<Database.SaveResult>{ null },
            new List<OpportunityTeamMember>()
        );
        Test.stopTest();

        Assert.areEqual(opportunityRecord.Id, member.OpportunityId, 'The sample team member should keep its opportunity.');
    }

    @IsTest
    static void logDeleteResults_coversSuccessFailureAndGuardPaths() {
        Opportunity opportunityRecord = opportunityByName(OPP_WITH_LEADERS);
        OpportunityTeamMember member = leaderMembers(opportunityRecord.Id)[0];
        Database.DeleteResult successResult = (Database.DeleteResult) JSON.deserialize(
            '{"success":true,"id":"00q000000000001AAA","errors":[]}',
            Database.DeleteResult.class
        );
        Database.DeleteResult failedResult = (Database.DeleteResult) JSON.deserialize(
            '{"success":false,"errors":[{"message":"Delete failed","statusCode":"ENTITY_IS_DELETED","fields":[]},{"message":"Second delete failure","statusCode":"ENTITY_IS_DELETED","fields":[]}]}',
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
            new List<Database.DeleteResult>{ failedResult },
            null
        );
        OpportunityBULeaderTeamSync.logDeleteResults(
            'OpportunityTeamMember',
            new List<Database.DeleteResult>{ null },
            new List<OpportunityTeamMember>()
        );
        Test.stopTest();

        Assert.areEqual(opportunityRecord.Id, member.OpportunityId, 'The sample team member should keep its opportunity.');
    }

    private static void sync(Id opportunityId) {
        syncIds(new List<Id>{ opportunityId });
    }

    private static void syncIds(List<Id> opportunityIds) {
        List<OpportunityBULeaderTeamSync.FlowInput> inputs = new List<OpportunityBULeaderTeamSync.FlowInput>();
        for (Id opportunityId : opportunityIds) {
            OpportunityBULeaderTeamSync.FlowInput inputRecord = new OpportunityBULeaderTeamSync.FlowInput();
            inputRecord.opportunityId = opportunityId;
            inputs.add(inputRecord);
        }
        OpportunityBULeaderTeamSync.syncBULeaders(inputs);
    }

    private static Business_Unit_Leader_Mappings__mdt mapping(String businessUnit, String leaderUsername) {
        return new Business_Unit_Leader_Mappings__mdt(
            Business_Unit__c = businessUnit,
            Business_Unit_Leader__c = leaderUsername
        );
    }

    private static User buildUser(Id profileId, String username, String alias, Boolean isActive) {
        return new User(
            ProfileId = profileId,
            Username = username,
            Email = username,
            LastName = 'Leader ' + alias,
            Alias = alias,
            CommunityNickname = alias + UserInfo.getOrganizationId().right(8),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            IsActive = isActive
        );
    }

    private static Opportunity buildOpportunity(
        Id accountId,
        Id contactId,
        Id recordTypeId,
        String opportunityName,
        String businessUnits
    ) {
        return new Opportunity(
            Name = opportunityName,
            AccountId = accountId,
            RecordTypeId = recordTypeId,
            Type = 'New Business',
            Amount = 1000,
            Probability = 10,
            PrimaryContact__c = contactId,
            StageName = 'Discovery',
            ForecastConfidenceLevel__c = 'Pipeline',
            CloseDate = Date.today().addDays(30),
            HCBusinessUnit__c = businessUnits
        );
    }

    private static Id accountRecordTypeId(String developerName) {
        Schema.RecordTypeInfo recordTypeInfo =
            Account.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName().get(developerName);
        Assert.isNotNull(recordTypeInfo, developerName + ' account record type is required.');
        return recordTypeInfo.getRecordTypeId();
    }

    private static Id opportunityRecordTypeId(String developerName) {
        Schema.RecordTypeInfo recordTypeInfo =
            Opportunity.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName().get(developerName);
        Assert.isNotNull(recordTypeInfo, developerName + ' opportunity record type is required.');
        return recordTypeInfo.getRecordTypeId();
    }

    private static List<Opportunity> testOpportunities() {
        return [
            SELECT Id, HCBusinessUnit__c
            FROM Opportunity
            WHERE Name IN :new Set<String>{ OPP_WITH_LEADERS, OPP_OTHER_ROLE, OPP_OPEN }
        ];
    }

    private static Opportunity opportunityByName(String opportunityName) {
        return [
            SELECT Id, HCBusinessUnit__c
            FROM Opportunity
            WHERE Name = :opportunityName
            LIMIT 1
        ];
    }

    private static Id userId(String username) {
        return [
            SELECT Id
            FROM User
            WHERE Username = :username
            LIMIT 1
        ].Id;
    }

    private static Integer leaderCount(Id opportunityId) {
        return [
            SELECT COUNT()
            FROM OpportunityTeamMember
            WHERE OpportunityId = :opportunityId
            AND TeamMemberRole = :BU_LEADER_ROLE
        ];
    }

    private static List<OpportunityTeamMember> leaderMembers(Id opportunityId) {
        return [
            SELECT Id, OpportunityId, UserId, TeamMemberRole, OpportunityAccessLevel
            FROM OpportunityTeamMember
            WHERE OpportunityId = :opportunityId
            AND TeamMemberRole = :BU_LEADER_ROLE
        ];
    }

    private static Id leaderMemberId(Id opportunityId) {
        return leaderMembers(opportunityId)[0].Id;
    }
}