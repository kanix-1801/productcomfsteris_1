/**
 * @author Suraj Thapliyal
 * @date 2026/10/29
 *
 * @group Overlay Assignment
 *
 * @description
 * Tests for OpportunityTeamMemberSelector.
 * @TestSetup inserts every Account, Contact, Opportunity, User, and Opportunity Team Member.
 * Selector calls run as the inserted team user, who is assigned the permission set that can read
 * OpportunityTeamMember.AssignmentType__c under WITH USER_MODE.
 */
@IsTest(SeeAllData=false)
private class OpportunityTeamMemberSelectorTest {

    private static final String PERMISSION_SET_NAME = 'SalesCustomerOpsSalesSupportSalesAdmin';
    private static final String TEAM_USERNAME = 'otm.selector.team@otmselectortest.example.com';
    private static final String OTHER_USERNAME = 'otm.selector.other@otmselectortest.example.com';
    private static final String ACCOUNT_NAME = 'OTM Selector Account';
    private static final String OPP_NAME = 'OTM Selector Opportunity';
    private static final String OTHER_OPP_NAME = 'OTM Selector Other Opportunity';
    private static final String PREFERRED_ROLE = 'Sales';
    private static final String PREFERRED_ASSIGNMENT_TYPE = 'Temporary Assignment';
    private static final String PREFERRED_ACCESS_LEVEL = 'Edit';
    private static final String PREFERRED_STAGE = 'Discovery';
    private static final String PREFERRED_TYPE = 'New Business';
    private static final String PREFERRED_FORECAST = 'Pipeline';
    private static final Set<String> TEST_USERNAMES = new Set<String>{ TEAM_USERNAME, OTHER_USERNAME };
    private static final Set<String> TEST_OPPORTUNITY_NAMES = new Set<String>{ OPP_NAME, OTHER_OPP_NAME };

    /**
     * @description
     * Ids and picklist values for the Opportunity Team Member inserted in @TestSetup.
     */
    private class TeamMemberFixture {
        public Id opportunityId;
        public Id otherOpportunityId;
        public Id userId;
        public Id otherUserId;
        public String teamMemberRole;
        public String assignmentType;
        public String otherRole;
        public String otherAssignmentType;
        public String accessLevel;
    }

    /**
     * @description
     * Inserts the users, account, contact, opportunities, and Opportunity Team Member once.
     *
     * @return void
     */
    @TestSetup
    static void setupData() {
        User teamUser = buildUser(TEAM_USERNAME, 'otmteam');
        User otherUser = buildUser(OTHER_USERNAME, 'otmother');
        insert new List<User>{ teamUser, otherUser };

        List<PermissionSet> permissionSets = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :PERMISSION_SET_NAME
            LIMIT 1
        ];
        Assert.areEqual(
            1,
            permissionSets.size(),
            'Required permission set ' + PERMISSION_SET_NAME + ' was not found.'
        );

        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(
                AssigneeId = teamUser.Id,
                PermissionSetId = permissionSets[0].Id
            );
        }

        System.runAs(teamUser) {
            Account accountRecord = new Account(
                Name = ACCOUNT_NAME,
                SourceSystemID__c = 'OTMSELECTOR'
            );
            insert accountRecord;

            Contact contactRecord = new Contact(
                FirstName = 'OTM',
                LastName = 'Selector',
                AccountId = accountRecord.Id,
                Email = 'otm.selector.contact@otmselectortest.example.com'
            );
            insert contactRecord;

            Opportunity opportunityRecord = buildOpportunity(accountRecord.Id, contactRecord.Id, OPP_NAME);
            Opportunity otherOpportunity = buildOpportunity(accountRecord.Id, contactRecord.Id, OTHER_OPP_NAME);
            insert new List<Opportunity>{ opportunityRecord, otherOpportunity };

            insert new OpportunityTeamMember(
                OpportunityId = opportunityRecord.Id,
                UserId = teamUser.Id,
                TeamMemberRole = teamMemberRole(),
                AssignmentType__c = assignmentType(),
                OpportunityAccessLevel = accessLevel()
            );
        }
    }

    /**
     * @description
     * Verifies selectByOpportunitiesAndUsers returns the inserted row and ignores other ids.
     *
     * @return void
     */
    @IsTest
    static void testSelectByOpportunitiesAndUsers() {
        TeamMemberFixture fixture = loadFixture();
        List<OpportunityTeamMember> matches;
        List<OpportunityTeamMember> otherUser;
        List<OpportunityTeamMember> otherOpportunity;

        System.runAs(new User(Id = fixture.userId)) {
            Test.startTest();
            matches = OpportunityTeamMemberSelector.selectByOpportunitiesAndUsers(
                new Set<Id>{ fixture.opportunityId },
                new Set<Id>{ fixture.userId }
            );
            otherUser = OpportunityTeamMemberSelector.selectByOpportunitiesAndUsers(
                new Set<Id>{ fixture.opportunityId },
                new Set<Id>{ fixture.otherUserId }
            );
            otherOpportunity = OpportunityTeamMemberSelector.selectByOpportunitiesAndUsers(
                new Set<Id>{ fixture.otherOpportunityId },
                new Set<Id>{ fixture.userId }
            );
            Test.stopTest();
        }

        Assert.areEqual(1, matches.size(), 'Expected the inserted Opportunity Team Member');
        Assert.areEqual(fixture.opportunityId, matches[0].OpportunityId, 'OpportunityId should match the inserted row');
        Assert.areEqual(fixture.userId, matches[0].UserId, 'UserId should match the inserted row');
        Assert.areEqual(
            fixture.accessLevel,
            matches[0].OpportunityAccessLevel,
            'OpportunityAccessLevel should match the inserted row'
        );
        Assert.areEqual(0, otherUser.size(), 'A different user should not match');
        Assert.areEqual(0, otherOpportunity.size(), 'A different opportunity should not match');
    }

    /**
     * @description
     * Verifies null and empty id sets return an empty list before querying.
     *
     * @return void
     */
    @IsTest
    static void testSelectByOpportunitiesAndUsersBlankInput() {
        TeamMemberFixture fixture = loadFixture();
        Set<Id> opportunityIds = new Set<Id>{ fixture.opportunityId };
        Set<Id> userIds = new Set<Id>{ fixture.userId };
        List<OpportunityTeamMember> nullOpportunities;
        List<OpportunityTeamMember> emptyOpportunities;
        List<OpportunityTeamMember> nullUsers;
        List<OpportunityTeamMember> emptyUsers;

        System.runAs(new User(Id = fixture.userId)) {
            Test.startTest();
            nullOpportunities = OpportunityTeamMemberSelector.selectByOpportunitiesAndUsers(null, userIds);
            emptyOpportunities = OpportunityTeamMemberSelector.selectByOpportunitiesAndUsers(new Set<Id>(), userIds);
            nullUsers = OpportunityTeamMemberSelector.selectByOpportunitiesAndUsers(opportunityIds, null);
            emptyUsers = OpportunityTeamMemberSelector.selectByOpportunitiesAndUsers(opportunityIds, new Set<Id>());
            Test.stopTest();
        }

        Assert.areEqual(0, nullOpportunities.size(), 'Null opportunity ids should return an empty list');
        Assert.areEqual(0, emptyOpportunities.size(), 'Empty opportunity ids should return an empty list');
        Assert.areEqual(0, nullUsers.size(), 'Null user ids should return an empty list');
        Assert.areEqual(0, emptyUsers.size(), 'Empty user ids should return an empty list');
    }

    /**
     * @description
     * Verifies selectByUserIds returns the inserted row and ignores another user.
     *
     * @return void
     */
    @IsTest
    static void testSelectByUserIds() {
        TeamMemberFixture fixture = loadFixture();
        List<OpportunityTeamMember> matches;
        List<OpportunityTeamMember> otherUser;

        System.runAs(new User(Id = fixture.userId)) {
            Test.startTest();
            matches = OpportunityTeamMemberSelector.selectByUserIds(new Set<Id>{ fixture.userId });
            otherUser = OpportunityTeamMemberSelector.selectByUserIds(new Set<Id>{ fixture.otherUserId });
            Test.stopTest();
        }

        Assert.areEqual(1, matches.size(), 'Expected the inserted Opportunity Team Member');
        Assert.areEqual(fixture.opportunityId, matches[0].OpportunityId, 'OpportunityId should match');
        Assert.areEqual(fixture.userId, matches[0].UserId, 'UserId should match');
        Assert.areEqual(fixture.teamMemberRole, matches[0].TeamMemberRole, 'TeamMemberRole should match');
        Assert.areEqual(fixture.accessLevel, matches[0].OpportunityAccessLevel, 'OpportunityAccessLevel should match');
        Assert.areEqual(0, otherUser.size(), 'A different user should not match');
    }

    /**
     * @description
     * Verifies null and empty user id sets return an empty list before querying.
     *
     * @return void
     */
    @IsTest
    static void testSelectByUserIdsBlankInput() {
        TeamMemberFixture fixture = loadFixture();
        List<OpportunityTeamMember> nullUsers;
        List<OpportunityTeamMember> emptyUsers;

        System.runAs(new User(Id = fixture.userId)) {
            Test.startTest();
            nullUsers = OpportunityTeamMemberSelector.selectByUserIds(null);
            emptyUsers = OpportunityTeamMemberSelector.selectByUserIds(new Set<Id>());
            Test.stopTest();
        }

        Assert.areEqual(0, nullUsers.size(), 'Null user ids should return an empty list');
        Assert.areEqual(0, emptyUsers.size(), 'Empty user ids should return an empty list');
    }

    /**
     * @description
     * Verifies selectByOpportunitiesUsersAndRole matches opportunity, user, and role together.
     *
     * @return void
     */
    @IsTest
    static void testSelectByOpportunitiesUsersAndRole() {
        TeamMemberFixture fixture = loadFixture();
        List<OpportunityTeamMember> matches;
        List<OpportunityTeamMember> otherRole;

        System.runAs(new User(Id = fixture.userId)) {
            Test.startTest();
            matches = OpportunityTeamMemberSelector.selectByOpportunitiesUsersAndRole(
                new Set<Id>{ fixture.opportunityId },
                new Set<Id>{ fixture.userId },
                fixture.teamMemberRole
            );
            otherRole = OpportunityTeamMemberSelector.selectByOpportunitiesUsersAndRole(
                new Set<Id>{ fixture.opportunityId },
                new Set<Id>{ fixture.userId },
                fixture.otherRole
            );
            Test.stopTest();
        }

        Assert.areEqual(1, matches.size(), 'Expected the inserted Opportunity Team Member');
        Assert.areEqual(fixture.opportunityId, matches[0].OpportunityId, 'OpportunityId should match');
        Assert.areEqual(fixture.userId, matches[0].UserId, 'UserId should match');
        Assert.areEqual(0, otherRole.size(), 'A different role should not match');
    }

    /**
     * @description
     * Verifies null, empty, and blank inputs return an empty list before querying.
     *
     * @return void
     */
    @IsTest
    static void testSelectByOpportunitiesUsersAndRoleBlankInput() {
        TeamMemberFixture fixture = loadFixture();
        Set<Id> opportunityIds = new Set<Id>{ fixture.opportunityId };
        Set<Id> userIds = new Set<Id>{ fixture.userId };
        List<OpportunityTeamMember> nullOpportunities;
        List<OpportunityTeamMember> emptyUsers;
        List<OpportunityTeamMember> blankRole;

        System.runAs(new User(Id = fixture.userId)) {
            Test.startTest();
            nullOpportunities = OpportunityTeamMemberSelector.selectByOpportunitiesUsersAndRole(
                null,
                userIds,
                PREFERRED_ROLE
            );
            emptyUsers = OpportunityTeamMemberSelector.selectByOpportunitiesUsersAndRole(
                opportunityIds,
                new Set<Id>(),
                PREFERRED_ROLE
            );
            blankRole = OpportunityTeamMemberSelector.selectByOpportunitiesUsersAndRole(
                opportunityIds,
                userIds,
                '   '
            );
            Test.stopTest();
        }

        Assert.areEqual(0, nullOpportunities.size(), 'Null opportunity ids should return an empty list');
        Assert.areEqual(0, emptyUsers.size(), 'Empty user ids should return an empty list');
        Assert.areEqual(0, blankRole.size(), 'A blank role should return an empty list');
    }

    /**
     * @description
     * Verifies selectByOpportunitiesUsersRoleAssignmentType matches role and assignment type.
     *
     * @return void
     */
    @IsTest
    static void testSelectByOpportunitiesUsersRoleAssignmentType() {
        TeamMemberFixture fixture = loadFixture();
        List<OpportunityTeamMember> matches;
        List<OpportunityTeamMember> otherAssignment;

        System.runAs(new User(Id = fixture.userId)) {
            Test.startTest();
            matches = OpportunityTeamMemberSelector.selectByOpportunitiesUsersRoleAssignmentType(
                new Set<Id>{ fixture.opportunityId },
                new Set<Id>{ fixture.userId },
                fixture.teamMemberRole,
                fixture.assignmentType
            );
            otherAssignment = OpportunityTeamMemberSelector.selectByOpportunitiesUsersRoleAssignmentType(
                new Set<Id>{ fixture.opportunityId },
                new Set<Id>{ fixture.userId },
                fixture.teamMemberRole,
                fixture.otherAssignmentType
            );
            Test.stopTest();
        }

        Assert.areEqual(1, matches.size(), 'Expected the inserted Opportunity Team Member');
        Assert.areEqual(fixture.opportunityId, matches[0].OpportunityId, 'OpportunityId should match');
        Assert.areEqual(fixture.userId, matches[0].UserId, 'UserId should match');
        Assert.areEqual(fixture.teamMemberRole, matches[0].TeamMemberRole, 'TeamMemberRole should match');
        Assert.areEqual(fixture.assignmentType, matches[0].AssignmentType__c, 'AssignmentType__c should match');
        Assert.areEqual(0, otherAssignment.size(), 'A different assignment type should not match');
    }

    /**
     * @description
     * Verifies null, empty, and blank inputs return an empty list before querying.
     *
     * @return void
     */
    @IsTest
    static void testSelectByOpportunitiesUsersRoleAssignmentTypeBlankInput() {
        TeamMemberFixture fixture = loadFixture();
        Set<Id> opportunityIds = new Set<Id>{ fixture.opportunityId };
        Set<Id> userIds = new Set<Id>{ fixture.userId };
        List<OpportunityTeamMember> nullUsers;
        List<OpportunityTeamMember> emptyOpportunities;
        List<OpportunityTeamMember> blankRole;
        List<OpportunityTeamMember> blankAssignmentType;

        System.runAs(new User(Id = fixture.userId)) {
            Test.startTest();
            nullUsers = OpportunityTeamMemberSelector.selectByOpportunitiesUsersRoleAssignmentType(
                opportunityIds,
                null,
                PREFERRED_ROLE,
                PREFERRED_ASSIGNMENT_TYPE
            );
            emptyOpportunities = OpportunityTeamMemberSelector.selectByOpportunitiesUsersRoleAssignmentType(
                new Set<Id>(),
                userIds,
                PREFERRED_ROLE,
                PREFERRED_ASSIGNMENT_TYPE
            );
            blankRole = OpportunityTeamMemberSelector.selectByOpportunitiesUsersRoleAssignmentType(
                opportunityIds,
                userIds,
                null,
                PREFERRED_ASSIGNMENT_TYPE
            );
            blankAssignmentType = OpportunityTeamMemberSelector.selectByOpportunitiesUsersRoleAssignmentType(
                opportunityIds,
                userIds,
                PREFERRED_ROLE,
                ''
            );
            Test.stopTest();
        }

        Assert.areEqual(0, nullUsers.size(), 'Null user ids should return an empty list');
        Assert.areEqual(0, emptyOpportunities.size(), 'Empty opportunity ids should return an empty list');
        Assert.areEqual(0, blankRole.size(), 'A blank role should return an empty list');
        Assert.areEqual(0, blankAssignmentType.size(), 'A blank assignment type should return an empty list');
    }

    /**
     * @description
     * Loads the rows inserted by setupData. User queries are limited to the usernames this test inserts.
     *
     * @return TeamMemberFixture with the inserted ids and picklist values
     */
    private static TeamMemberFixture loadFixture() {
        Map<String, User> usersByUsername = new Map<String, User>();
        for (User userRecord : [
            SELECT Id, Username
            FROM User
            WHERE Username IN :TEST_USERNAMES
        ]) {
            usersByUsername.put(userRecord.Username, userRecord);
        }

        Map<String, Opportunity> opportunitiesByName = new Map<String, Opportunity>();
        for (Opportunity opportunityRecord : [
            SELECT Id, Name
            FROM Opportunity
            WHERE Name IN :TEST_OPPORTUNITY_NAMES
        ]) {
            opportunitiesByName.put(opportunityRecord.Name, opportunityRecord);
        }

        TeamMemberFixture fixture = new TeamMemberFixture();
        fixture.userId = usersByUsername.get(TEAM_USERNAME).Id;
        fixture.otherUserId = usersByUsername.get(OTHER_USERNAME).Id;
        fixture.opportunityId = opportunitiesByName.get(OPP_NAME).Id;
        fixture.otherOpportunityId = opportunitiesByName.get(OTHER_OPP_NAME).Id;
        fixture.teamMemberRole = teamMemberRole();
        fixture.assignmentType = assignmentType();
        fixture.otherRole = otherPicklistValue(OpportunityTeamMember.TeamMemberRole, fixture.teamMemberRole);
        fixture.otherAssignmentType = otherPicklistValue(
            OpportunityTeamMember.AssignmentType__c,
            fixture.assignmentType
        );
        fixture.accessLevel = accessLevel();
        return fixture;
    }

    /**
     * @description
     * Builds an Opportunity that satisfies Instrument Processing Discovery requirements.
     *
     * @param accountId Account created in this test
     * @param contactId Contact created in this test
     * @param opportunityName Opportunity name
     * @return Opportunity ready to insert
     */
    private static Opportunity buildOpportunity(Id accountId, Id contactId, String opportunityName) {
        Opportunity opportunityRecord = new Opportunity(
            Name = opportunityName,
            AccountId = accountId,
            CloseDate = Date.today().addDays(30),
            Amount = 100,
            StageName = activePicklistValue(Opportunity.StageName, PREFERRED_STAGE),
            ForecastConfidenceLevel__c = activePicklistValue(
                Opportunity.ForecastConfidenceLevel__c,
                PREFERRED_FORECAST
            ),
            Probability = 10,
            Type = activePicklistValue(Opportunity.Type, PREFERRED_TYPE),
            PrimaryContact__c = contactId
        );
        Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get('InstrumentProcessing');
        if (recordTypeInfo != null) {
            opportunityRecord.RecordTypeId = recordTypeInfo.getRecordTypeId();
        }
        return opportunityRecord;
    }

    /**
     * @description
     * Builds an active user on the running user's profile.
     *
     * @param username Unique username inserted by this test
     * @param aliasPrefix Short prefix within the alias length limit
     * @return User ready to insert
     */
    private static User buildUser(String username, String aliasPrefix) {
        return new User(
            FirstName = 'OTM',
            LastName = 'Selector',
            Alias = aliasPrefix.left(8),
            Email = username,
            Username = username,
            CommunityNickname = username.replace('@', '').replace('.', '').left(40),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = UserInfo.getProfileId(),
            IsActive = true
        );
    }

    /**
     * @description
     * Returns the team member role inserted on the Opportunity Team Member.
     *
     * @return Active TeamMemberRole value
     */
    private static String teamMemberRole() {
        return activePicklistValue(OpportunityTeamMember.TeamMemberRole, PREFERRED_ROLE);
    }

    /**
     * @description
     * Returns the assignment type inserted on the Opportunity Team Member.
     *
     * @return Active AssignmentType__c value
     */
    private static String assignmentType() {
        return activePicklistValue(OpportunityTeamMember.AssignmentType__c, PREFERRED_ASSIGNMENT_TYPE);
    }

    /**
     * @description
     * Returns the opportunity access level inserted on the Opportunity Team Member.
     *
     * @return Active OpportunityAccessLevel value
     */
    private static String accessLevel() {
        return activePicklistValue(OpportunityTeamMember.OpportunityAccessLevel, PREFERRED_ACCESS_LEVEL);
    }

    /**
     * @description
     * Returns the preferred active picklist value, or the first active value.
     *
     * @param fieldToken Picklist field
     * @param preferredValue Value to use when it is active
     * @return Active picklist value
     */
    private static String activePicklistValue(Schema.SObjectField fieldToken, String preferredValue) {
        String fallback;
        for (Schema.PicklistEntry picklistEntry : fieldToken.getDescribe().getPicklistValues()) {
            if (!picklistEntry.isActive()) {
                continue;
            }
            if (picklistEntry.getValue() == preferredValue) {
                return preferredValue;
            }
            if (fallback == null) {
                fallback = picklistEntry.getValue();
            }
        }
        return String.isBlank(fallback) ? preferredValue : fallback;
    }

    /**
     * @description
     * Returns an active picklist value other than the excluded value.
     *
     * @param fieldToken Picklist field
     * @param excludedValue Value already used on the inserted row
     * @return A non-matching picklist value
     */
    private static String otherPicklistValue(Schema.SObjectField fieldToken, String excludedValue) {
        for (Schema.PicklistEntry picklistEntry : fieldToken.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive() && picklistEntry.getValue() != excludedValue) {
                return picklistEntry.getValue();
            }
        }
        return excludedValue + ' Other';
    }
}