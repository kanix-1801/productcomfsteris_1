/**
 * @author PWC Developer
 * @date 2026-11-25
 * @group Life Sciences
 * @description GCL-74 - End-to-end tests for LSUserService through the User trigger. Covers the Life Sciences
 *              removal, rows that must stay, non-Life Sciences users, updates that do not deactivate, and a
 *              Healthcare regression showing the Healthcare cleanup still behaves as before.
 *
 *              All team rows are created in @TestSetup. Test methods only update the User, so there is
 *              no mixed DML.
 */
@IsTest
private class LSUserServiceTest {

    private static final String TYPE_ORACLE = 'Oracle Assigned';
    private static final String TYPE_SALESFORCE = 'Salesforce Assigned';
    private static final String TYPE_TEMPORARY = 'Temporary Assignment';
    private static final String TYPE_MANUAL = 'Manually Assigned';
    private static final String ROLE_SALES = 'Sales';
    private static final String ROLE_HEALTHCARE_ORACLE = 'Oracle Assigned';

    private static final String LS_REMOVED_LAST_NAME = 'GCL74LsRemoved';
    private static final String LS_MIXED_LAST_NAME = 'GCL74LsMixed';
    private static final String LS_UNCHANGED_LAST_NAME = 'GCL74LsUnchanged';
    private static final String NON_LS_TYPE_LAST_NAME = 'GCL74NonLsType';
    private static final String NON_LS_ROLE_LAST_NAME = 'GCL74NonLsRole';

    /**
     * @description Creates the users, then the accounts, opportunity and team rows used by the tests.
     */
    @TestSetup
    static void setupTestData() {
        List<User> userList = new List<User>{
            buildUser(UserSelector.LIFESCIENCES_SALES_PROFILE_NAME, LS_REMOVED_LAST_NAME, 'lsu1'),
            buildUser(UserSelector.LIFESCIENCES_SALES_PROFILE_NAME, LS_MIXED_LAST_NAME, 'lsu2'),
            buildUser(UserSelector.LIFESCIENCES_SALES_PROFILE_NAME, LS_UNCHANGED_LAST_NAME, 'lsu3'),
            buildUser('System Administrator', NON_LS_TYPE_LAST_NAME, 'lsu4'),
            buildUser('System Administrator', NON_LS_ROLE_LAST_NAME, 'lsu5')
        };
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert userList;
        }

        List<Account> accountList = new List<Account>{
            new Account(Name = 'GCL74 Service Account One', SourceSystemID__c = 'GCL74SVC001'),
            new Account(Name = 'GCL74 Service Account Two', SourceSystemID__c = 'GCL74SVC002')
        };
        insert accountList;
        Opportunity opportunityRecord = createOpportunity(accountList[0].Id);

        Map<String, Id> userIdByLastNameMap = new Map<String, Id>();
        for (User userRecord : [SELECT Id, LastName FROM User WHERE LastName LIKE 'GCL74%']) {
            userIdByLastNameMap.put(userRecord.LastName, userRecord.Id);
        }
        insert new List<AccountTeamMember>{
            buildAccountTeamMember(
                accountList[0].Id, userIdByLastNameMap.get(LS_REMOVED_LAST_NAME), ROLE_SALES, TYPE_ORACLE
            ),
            buildAccountTeamMember(
                accountList[0].Id, userIdByLastNameMap.get(LS_MIXED_LAST_NAME), ROLE_SALES, TYPE_MANUAL
            ),
            buildAccountTeamMember(
                accountList[1].Id, userIdByLastNameMap.get(LS_MIXED_LAST_NAME), ROLE_SALES, TYPE_SALESFORCE
            ),
            buildAccountTeamMember(
                accountList[1].Id, userIdByLastNameMap.get(LS_UNCHANGED_LAST_NAME), ROLE_SALES, TYPE_ORACLE
            ),
            buildAccountTeamMember(
                accountList[0].Id, userIdByLastNameMap.get(NON_LS_TYPE_LAST_NAME), ROLE_SALES, TYPE_ORACLE
            ),
            buildAccountTeamMember(
                accountList[1].Id, userIdByLastNameMap.get(NON_LS_ROLE_LAST_NAME), ROLE_HEALTHCARE_ORACLE, null
            )
        };
        insert new OpportunityTeamMember(
            OpportunityId = opportunityRecord.Id,
            UserId = userIdByLastNameMap.get(LS_REMOVED_LAST_NAME),
            TeamMemberRole = ROLE_SALES,
            OpportunityAccessLevel = 'Edit',
            AssignmentType__c = TYPE_TEMPORARY
        );
    }

    /**
     * @description Deactivating a Life Sciences user removes the Account Team and Opportunity Team rows,
     *              writes one history row each, and leaves record owners unchanged.
     */
    @IsTest
    static void testProcessInactiveLifeSciencesUsersRemovesRowsAndWritesHistory() {
        // SETUP
        User lsUser = getUser(LS_REMOVED_LAST_NAME);
        Map<Id, Id> ownerIdByRecordIdMap = getOwnerIdByRecordIdMap();

        // GIVEN
        System.assertEquals(1, countAccountTeamRows(lsUser.Id), 'One Account Team row should exist.');
        System.assertEquals(1, countOpportunityTeamRows(lsUser.Id), 'One Opportunity Team row should exist.');

        // WHEN
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            update new User(Id = lsUser.Id, IsActive = false);
            Test.stopTest();
        }

        // THEN
        System.assertEquals(0, countAccountTeamRows(lsUser.Id), 'The Account Team row should be removed.');
        System.assertEquals(0, countOpportunityTeamRows(lsUser.Id), 'The Opportunity Team row should be removed.');
        List<InactiveUserAssignmentHistory__c> historyList = getHistoryList(lsUser.Id);
        System.assertEquals(2, historyList.size(), 'Two history rows should be written.');
        Map<String, InactiveUserAssignmentHistory__c> historyByObjectMap =
            new Map<String, InactiveUserAssignmentHistory__c>();
        for (InactiveUserAssignmentHistory__c history : historyList) {
            historyByObjectMap.put(history.AssignmentObject__c, history);
            System.assertEquals(true, history.IsLifeSciences__c, 'History should be flagged Life Sciences.');
            System.assertEquals(Date.today(), history.UserInactivationDate__c, 'History should use today.');
        }
        System.assertEquals(TYPE_ORACLE, historyByObjectMap.get('Account').Assignment_Type__c, 'Account history type.');
        System.assertEquals(
            TYPE_TEMPORARY, historyByObjectMap.get('Opportunity').Assignment_Type__c, 'Opportunity history type.'
        );
        System.assertEquals(ownerIdByRecordIdMap, getOwnerIdByRecordIdMap(), 'Record owners should not change.');
    }

    /**
     * @description A Manually Assigned row stays, while the Salesforce Assigned row of the same user is removed.
     */
    @IsTest
    static void testProcessInactiveLifeSciencesUsersKeepsManuallyAssignedRow() {
        // SETUP
        User lsUser = getUser(LS_MIXED_LAST_NAME);

        // GIVEN
        System.assertEquals(2, countAccountTeamRows(lsUser.Id), 'Two Account Team rows should exist.');

        // WHEN
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            update new User(Id = lsUser.Id, IsActive = false);
            Test.stopTest();
        }

        // THEN
        List<AccountTeamMember> remainingList = [
            SELECT AssignmentType__c FROM AccountTeamMember WHERE UserId = :lsUser.Id
        ];
        System.assertEquals(1, remainingList.size(), 'Only the Manually Assigned row should remain.');
        System.assertEquals(
            TYPE_MANUAL, remainingList[0].AssignmentType__c, 'The Manually Assigned row should remain.'
        );
        List<InactiveUserAssignmentHistory__c> historyList = getHistoryList(lsUser.Id);
        System.assertEquals(1, historyList.size(), 'Only the removed row should have a history row.');
        System.assertEquals(
            TYPE_SALESFORCE, historyList[0].Assignment_Type__c, 'History should record the removed type.'
        );
    }

    /**
     * @description Updating a Life Sciences user without deactivating them removes nothing.
     */
    @IsTest
    static void testProcessInactiveLifeSciencesUsersIgnoresUpdateWithoutDeactivation() {
        // SETUP
        User lsUser = getUser(LS_UNCHANGED_LAST_NAME);

        // WHEN
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            update new User(Id = lsUser.Id, Title = 'GCL74 Updated Title');
            Test.stopTest();
        }

        // THEN
        System.assertEquals(1, countAccountTeamRows(lsUser.Id), 'The row should remain.');
        System.assertEquals(0, getHistoryList(lsUser.Id).size(), 'No history row should be written.');
    }

    /**
     * @description A non Life Sciences user is ignored by the Life Sciences path, even when the row carries
     *              a configured AssignmentType__c. Healthcare matches on role only, so the row also stays.
     */
    @IsTest
    static void testProcessInactiveLifeSciencesUsersIgnoresNonLifeSciencesUser() {
        // SETUP
        User otherUser = getUser(NON_LS_TYPE_LAST_NAME);

        // WHEN
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            update new User(Id = otherUser.Id, IsActive = false);
            Test.stopTest();
        }

        // THEN
        System.assertEquals(1, countAccountTeamRows(otherUser.Id), 'The non Life Sciences row should remain.');
        System.assertEquals(0, getHistoryList(otherUser.Id).size(), 'No history row should be written.');
    }

    /**
     * @description Healthcare regression. A non Life Sciences user with a role based row is still cleaned up by
     *              the Healthcare path, with one history row that is not flagged Life Sciences.
     */
    @IsTest
    static void testProcessInactiveLifeSciencesUsersHealthcareRoleRowStillRemoved() {
        // SETUP
        User healthcareUser = getUser(NON_LS_ROLE_LAST_NAME);

        // GIVEN
        System.assertEquals(1, countAccountTeamRows(healthcareUser.Id), 'One role based row should exist.');

        // WHEN
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            update new User(Id = healthcareUser.Id, IsActive = false);
            Test.stopTest();
        }

        // THEN
        System.assertEquals(0, countAccountTeamRows(healthcareUser.Id), 'Healthcare should still remove the row.');
        List<InactiveUserAssignmentHistory__c> historyList = getHistoryList(healthcareUser.Id);
        System.assertEquals(1, historyList.size(), 'Exactly one history row should be written.');
        System.assertEquals(
            false, historyList[0].IsLifeSciences__c, 'Healthcare history should not be flagged Life Sciences.'
        );
        System.assertEquals(
            ROLE_HEALTHCARE_ORACLE, historyList[0].Assignment_Type__c, 'Healthcare history keeps the role.'
        );
    }

    /**
     * @description Automation bypass (Standards Section 8.1). With this automation's bypass checkbox set for the
     *              running user, deactivating a Life Sciences user removes nothing and writes no history.
     */
    @IsTest
    static void testProcessInactiveLifeSciencesUsersSkippedWhenBypassChecked() {
        // SETUP
        User lsUser = getUser(LS_REMOVED_LAST_NAME);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new Automation_Setting_Trigger__c(
                SetupOwnerId = UserInfo.getUserId(),
                IsLSInactiveUserCleanupBypassed__c = true
            );
        }

        // GIVEN
        System.assertEquals(1, countAccountTeamRows(lsUser.Id), 'One Account Team row should exist.');

        // WHEN
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            update new User(Id = lsUser.Id, IsActive = false);
            Test.stopTest();
        }

        // THEN
        System.assertEquals(
            1, countAccountTeamRows(lsUser.Id), 'The row should remain while the bypass is checked.'
        );
        System.assertEquals(0, getHistoryList(lsUser.Id).size(), 'No history row should be written.');
    }

    private static User buildUser(String profileName, String lastName, String aliasPrefix) {
        Profile profileRecord = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
        String uniqueValue = aliasPrefix + String.valueOf(DateTime.now().getTime())
            + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        return new User(
            FirstName = 'GCL74',
            LastName = lastName,
            Alias = aliasPrefix.left(8),
            Email = uniqueValue + '@test.com',
            Username = uniqueValue + '@test.com',
            CommunityNickname = uniqueValue.left(40),
            ProfileId = profileRecord.Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    private static User getUser(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName LIMIT 1];
    }

    private static Opportunity createOpportunity(Id accountId) {
        Contact contactRecord = new Contact(
            FirstName = 'GCL74',
            LastName = 'Service Contact',
            AccountId = accountId,
            Email = 'gcl74service@test.com'
        );
        insert contactRecord;
        Opportunity opportunityRecord = new Opportunity(
            Name = 'GCL74 Service Opportunity',
            AccountId = accountId,
            CloseDate = Date.today().addDays(30),
            Amount = 100,
            StageName = 'Discovery',
            ForecastConfidenceLevel__c = 'Pipeline',
            Probability = 20,
            Type = 'New Business',
            PrimaryContact__c = contactRecord.Id
        );
        insert opportunityRecord;
        return opportunityRecord;
    }

    private static AccountTeamMember buildAccountTeamMember(
        Id accountId,
        Id userId,
        String teamMemberRole,
        String assignmentType
    ) {
        return new AccountTeamMember(
            AccountId = accountId,
            UserId = userId,
            TeamMemberRole = teamMemberRole,
            AccountAccessLevel = 'Edit',
            OpportunityAccessLevel = 'Edit',
            AssignmentType__c = assignmentType
        );
    }

    private static Map<Id, Id> getOwnerIdByRecordIdMap() {
        Map<Id, Id> ownerIdByRecordIdMap = new Map<Id, Id>();
        for (Account accountRecord : [SELECT Id, OwnerId FROM Account WHERE Name LIKE 'GCL74 Service%']) {
            ownerIdByRecordIdMap.put(accountRecord.Id, accountRecord.OwnerId);
        }
        for (Opportunity opportunityRecord :
            [SELECT Id, OwnerId FROM Opportunity WHERE Name = 'GCL74 Service Opportunity']
        ) {
            ownerIdByRecordIdMap.put(opportunityRecord.Id, opportunityRecord.OwnerId);
        }
        return ownerIdByRecordIdMap;
    }

    private static Integer countAccountTeamRows(Id userId) {
        return [SELECT COUNT() FROM AccountTeamMember WHERE UserId = :userId];
    }

    private static Integer countOpportunityTeamRows(Id userId) {
        return [SELECT COUNT() FROM OpportunityTeamMember WHERE UserId = :userId];
    }

    private static List<InactiveUserAssignmentHistory__c> getHistoryList(Id userId) {
        return [
            SELECT Assignment_Type__c, AssignmentObject__c, UserInactivationDate__c, IsLifeSciences__c
            FROM InactiveUserAssignmentHistory__c
            WHERE User__c = :userId
        ];
    }
}