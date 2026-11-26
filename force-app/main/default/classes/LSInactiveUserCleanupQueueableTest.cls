/**
 * @author PWC Developer
 * @date 2026-11-25
 * @group Life Sciences
 * @description GCL-74 - Tests for LSInactiveUserCleanupQueueable: removal of Account Team and Opportunity Team
 *              rows matched on AssignmentType__c, the history rows written for them, ownership, paging,
 *              bulk volume and failure handling.
 */
@IsTest
private class LSInactiveUserCleanupQueueableTest {

    private static final String TYPE_ORACLE = 'Oracle Assigned';
    private static final String TYPE_SALESFORCE = 'Salesforce Assigned';
    private static final String TYPE_TEMPORARY = 'Temporary Assignment';
    private static final String TYPE_MANUAL = 'Manually Assigned';
    private static final String ROLE_SALES = 'Sales';
    private static final String LS_USER_LAST_NAME = 'GCL74QueueableLs';
    private static final String OTHER_USER_LAST_NAME = 'GCL74QueueableOther';

    /**
     * @description Creates one Life Sciences user and one other user. User inserts are kept in the
     *              setup method so the test methods never mix User and non-setup DML.
     */
    @TestSetup
    static void setupTestData() {
        List<User> userList = new List<User>{
            buildUser(UserSelector.LIFESCIENCES_SALES_PROFILE_NAME, LS_USER_LAST_NAME, 'lsq1'),
            buildUser('System Administrator', OTHER_USER_LAST_NAME, 'lsq2')
        };
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert userList;
        }
    }

    /**
     * @description Account Team rows of each configured type are removed and one history row is written
     *              per row. The Account owner does not change.
     */
    @IsTest
    static void testExecuteAccountTeamRowsRemovedWithHistory() {
        // SETUP
        User lsUser = getUser(LS_USER_LAST_NAME);
        List<Account> accountList = createAccountList(3, 'T1');
        insert new List<AccountTeamMember>{
            buildAccountTeamMember(accountList[0].Id, lsUser.Id, TYPE_ORACLE),
            buildAccountTeamMember(accountList[1].Id, lsUser.Id, TYPE_SALESFORCE),
            buildAccountTeamMember(accountList[2].Id, lsUser.Id, TYPE_TEMPORARY)
        };
        Map<Id, Id> ownerIdByAccountIdMap = getOwnerIdByAccountIdMap(accountList);
        Date inactiveDate = Date.today().addDays(-1);

        // GIVEN
        System.assertEquals(3, countAccountTeamRows(lsUser.Id), 'Three Account Team rows should exist before cleanup.');

        // WHEN
        Test.startTest();
        new LSInactiveUserCleanupQueueable(new Map<Id, Date>{ lsUser.Id => inactiveDate }, getAssignmentTypeSet())
            .execute(null);
        Test.stopTest();

        // THEN
        System.assertEquals(0, countAccountTeamRows(lsUser.Id), 'All three Account Team rows should be removed.');
        List<InactiveUserAssignmentHistory__c> historyList = getHistoryList(lsUser.Id);
        System.assertEquals(3, historyList.size(), 'One history row should exist per removed row.');
        Set<String> historyTypeSet = new Set<String>();
        for (InactiveUserAssignmentHistory__c history : historyList) {
            historyTypeSet.add(history.Assignment_Type__c);
            System.assertEquals('Account', history.AssignmentObject__c, 'History should record the Account object.');
            System.assertEquals(inactiveDate, history.UserInactivationDate__c, 'History should use the inactive date.');
            System.assertEquals(true, history.IsLifeSciences__c, 'History should be flagged Life Sciences.');
        }
        System.assertEquals(
            new Set<String>{ TYPE_ORACLE, TYPE_SALESFORCE, TYPE_TEMPORARY },
            historyTypeSet,
            'History should keep the original assignment types.'
        );
        System.assertEquals(
            ownerIdByAccountIdMap,
            getOwnerIdByAccountIdMap(accountList),
            'Account owners should not change.'
        );
    }

    /**
     * @description Opportunity Team rows are removed and one history row is written with the Opportunity,
     *              a blank Account, and an unchanged Opportunity owner.
     */
    @IsTest
    static void testExecuteOpportunityTeamRowsRemovedWithHistory() {
        // SETUP
        User lsUser = getUser(LS_USER_LAST_NAME);
        Account accountRecord = createAccountList(1, 'T2')[0];
        Opportunity opportunityRecord = createOpportunity(accountRecord.Id, 'T2');
        insert new OpportunityTeamMember(
            OpportunityId = opportunityRecord.Id,
            UserId = lsUser.Id,
            TeamMemberRole = ROLE_SALES,
            OpportunityAccessLevel = 'Edit',
            AssignmentType__c = TYPE_TEMPORARY
        );
        Id ownerBeforeId = [SELECT OwnerId FROM Opportunity WHERE Id = :opportunityRecord.Id].OwnerId;

        // GIVEN
        System.assertEquals(1, countOpportunityTeamRows(lsUser.Id), 'One Opportunity Team row should exist.');

        // WHEN
        Test.startTest();
        new LSInactiveUserCleanupQueueable(new Map<Id, Date>{ lsUser.Id => Date.today() }, getAssignmentTypeSet())
            .execute(null);
        Test.stopTest();

        // THEN
        System.assertEquals(0, countOpportunityTeamRows(lsUser.Id), 'The Opportunity Team row should be removed.');
        List<InactiveUserAssignmentHistory__c> historyList = getHistoryList(lsUser.Id);
        System.assertEquals(1, historyList.size(), 'One history row should be written.');
        System.assertEquals(opportunityRecord.Id, historyList[0].Opportunity__c, 'History should point to the Opportunity.');
        System.assertEquals(null, historyList[0].Account__c, 'History Account should be blank for an Opportunity row.');
        System.assertEquals('Opportunity', historyList[0].AssignmentObject__c, 'History should record the Opportunity object.');
        System.assertEquals(TYPE_TEMPORARY, historyList[0].Assignment_Type__c, 'History should keep the assignment type.');
        System.assertEquals(
            ownerBeforeId,
            [SELECT OwnerId FROM Opportunity WHERE Id = :opportunityRecord.Id].OwnerId,
            'The Opportunity owner should not change.'
        );
    }

    /**
     * @description A Manually Assigned row is not in the configured types, so it stays and gets no history row.
     */
    @IsTest
    static void testExecuteManuallyAssignedRowKept() {
        // SETUP
        User lsUser = getUser(LS_USER_LAST_NAME);
        List<Account> accountList = createAccountList(2, 'T3');
        insert new List<AccountTeamMember>{
            buildAccountTeamMember(accountList[0].Id, lsUser.Id, TYPE_ORACLE),
            buildAccountTeamMember(accountList[1].Id, lsUser.Id, TYPE_MANUAL)
        };

        // WHEN
        Test.startTest();
        new LSInactiveUserCleanupQueueable(new Map<Id, Date>{ lsUser.Id => Date.today() }, getAssignmentTypeSet())
            .execute(null);
        Test.stopTest();

        // THEN
        List<AccountTeamMember> remainingList = [
            SELECT AccountId, AssignmentType__c FROM AccountTeamMember WHERE UserId = :lsUser.Id
        ];
        System.assertEquals(1, remainingList.size(), 'Only the Manually Assigned row should remain.');
        System.assertEquals(TYPE_MANUAL, remainingList[0].AssignmentType__c, 'The remaining row should be Manually Assigned.');
        System.assertEquals(1, getHistoryList(lsUser.Id).size(), 'Only the removed row should have a history row.');
    }

    /**
     * @description Rows that belong to a user who was not deactivated are never touched.
     */
    @IsTest
    static void testExecuteOtherUserRowKept() {
        // SETUP
        User lsUser = getUser(LS_USER_LAST_NAME);
        User otherUser = getUser(OTHER_USER_LAST_NAME);
        List<Account> accountList = createAccountList(1, 'T4');
        insert new List<AccountTeamMember>{
            buildAccountTeamMember(accountList[0].Id, lsUser.Id, TYPE_ORACLE),
            buildAccountTeamMember(accountList[0].Id, otherUser.Id, TYPE_ORACLE)
        };

        // WHEN
        Test.startTest();
        new LSInactiveUserCleanupQueueable(new Map<Id, Date>{ lsUser.Id => Date.today() }, getAssignmentTypeSet())
            .execute(null);
        Test.stopTest();

        // THEN
        System.assertEquals(0, countAccountTeamRows(lsUser.Id), 'The deactivated user row should be removed.');
        System.assertEquals(1, countAccountTeamRows(otherUser.Id), 'The other user row should remain.');
        System.assertEquals(0, getHistoryList(otherUser.Id).size(), 'The other user should have no history rows.');
    }

    /**
     * @description With no matching rows the job does nothing and writes no history.
     */
    @IsTest
    static void testExecuteNoMatchingRowsDoesNothing() {
        // SETUP
        User lsUser = getUser(LS_USER_LAST_NAME);

        // WHEN
        Test.startTest();
        new LSInactiveUserCleanupQueueable(new Map<Id, Date>{ lsUser.Id => Date.today() }, getAssignmentTypeSet())
            .execute(null);
        Test.stopTest();

        // THEN
        System.assertEquals(0, getHistoryList(lsUser.Id).size(), 'No history rows should be written.');
        System.assertEquals(false, LSInactiveUserCleanupQueueable.isChainRequested, 'No further run should be requested.');
    }

    /**
     * @description A full page requests another run, and only one page is processed per run.
     */
    @IsTest
    static void testExecuteChainRequestedWhenPageIsFull() {
        // SETUP
        User lsUser = getUser(LS_USER_LAST_NAME);
        List<Account> accountList = createAccountList(3, 'T5');
        List<AccountTeamMember> teamMemberList = new List<AccountTeamMember>();
        for (Account accountRecord : accountList) {
            teamMemberList.add(buildAccountTeamMember(accountRecord.Id, lsUser.Id, TYPE_ORACLE));
        }
        insert teamMemberList;
        LSInactiveUserCleanupQueueable.rowLimit = 2;

        // WHEN
        Test.startTest();
        new LSInactiveUserCleanupQueueable(new Map<Id, Date>{ lsUser.Id => Date.today() }, getAssignmentTypeSet())
            .execute(null);
        Test.stopTest();

        // THEN
        System.assertEquals(true, LSInactiveUserCleanupQueueable.isChainRequested, 'A full page should request another run.');
        System.assertEquals(2, getHistoryList(lsUser.Id).size(), 'Only one page of history rows should be written.');
        System.assertEquals(1, countAccountTeamRows(lsUser.Id), 'One row should be left for the next run.');
    }

    /**
     * @description More than 200 rows are removed and recorded in one run.
     */
    @IsTest
    static void testExecuteBulkOver200RowsRemovedWithHistory() {
        // SETUP
        User lsUser = getUser(LS_USER_LAST_NAME);
        insert new Automation_Setting_Trigger__c(SetupOwnerId = UserInfo.getUserId(), AccountTriggerByPass__c = true);
        List<Account> accountList = createAccountList(201, 'BULK');
        List<AccountTeamMember> teamMemberList = new List<AccountTeamMember>();
        for (Account accountRecord : accountList) {
            teamMemberList.add(buildAccountTeamMember(accountRecord.Id, lsUser.Id, TYPE_ORACLE));
        }
        insert teamMemberList;

        // GIVEN
        System.assertEquals(201, countAccountTeamRows(lsUser.Id), '201 Account Team rows should exist before cleanup.');

        // WHEN
        Test.startTest();
        new LSInactiveUserCleanupQueueable(new Map<Id, Date>{ lsUser.Id => Date.today() }, getAssignmentTypeSet())
            .execute(null);
        Test.stopTest();

        // THEN
        System.assertEquals(0, countAccountTeamRows(lsUser.Id), 'All 201 rows should be removed.');
        System.assertEquals(201, getHistoryList(lsUser.Id).size(), 'One history row should exist per removed row.');
    }

    /**
     * @description A history failure is wrapped in LSInactiveUserCleanupException and no team row is deleted.
     *              Manually Assigned is a valid team row type but not a valid history type.
     */
    @IsTest
    static void testExecuteHistoryFailureThrowsWrappedExceptionAndKeepsRows() {
        // SETUP
        User lsUser = getUser(LS_USER_LAST_NAME);
        List<Account> accountList = createAccountList(1, 'T6');
        insert buildAccountTeamMember(accountList[0].Id, lsUser.Id, TYPE_MANUAL);
        String caughtExceptionType;

        // WHEN
        Test.startTest();
        try {
            new LSInactiveUserCleanupQueueable(
                new Map<Id, Date>{ lsUser.Id => Date.today() },
                new Set<String>{ TYPE_MANUAL }
            ).execute(null);
        } catch (LSInactiveUserCleanupException cleanupError) {
            caughtExceptionType = 'LSInactiveUserCleanupException';
        }
        Test.stopTest();

        // THEN
        System.assertEquals('LSInactiveUserCleanupException', caughtExceptionType, 'The failure should be wrapped.');
        System.assertEquals(1, countAccountTeamRows(lsUser.Id), 'The team row should not be deleted when history fails.');
        System.assertEquals(0, getHistoryList(lsUser.Id).size(), 'No history row should be saved.');
    }

    /**
     * @description The job also works when it is enqueued as a real Queueable.
     */
    @IsTest
    static void testExecuteEnqueuedJobRemovesRows() {
        // SETUP
        User lsUser = getUser(LS_USER_LAST_NAME);
        List<Account> accountList = createAccountList(1, 'T7');
        insert buildAccountTeamMember(accountList[0].Id, lsUser.Id, TYPE_ORACLE);

        // WHEN
        Test.startTest();
        System.enqueueJob(
            new LSInactiveUserCleanupQueueable(new Map<Id, Date>{ lsUser.Id => Date.today() }, getAssignmentTypeSet())
        );
        Test.stopTest();

        // THEN
        System.assertEquals(0, countAccountTeamRows(lsUser.Id), 'The enqueued job should remove the row.');
        System.assertEquals(1, getHistoryList(lsUser.Id).size(), 'The enqueued job should write one history row.');
    }

    private static Set<String> getAssignmentTypeSet() {
        return new Set<String>{ TYPE_ORACLE, TYPE_SALESFORCE, TYPE_TEMPORARY };
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

    private static List<Account> createAccountList(Integer accountCount, String keyPrefix) {
        List<Account> accountList = new List<Account>();
        for (Integer index = 0; index < accountCount; index++) {
            accountList.add(new Account(
                Name = 'GCL74 Account ' + keyPrefix + ' ' + index,
                SourceSystemID__c = 'GCL74' + keyPrefix + index
            ));
        }
        insert accountList;
        return accountList;
    }

    private static Opportunity createOpportunity(Id accountId, String keySuffix) {
        Contact contactRecord = new Contact(
            FirstName = 'GCL74',
            LastName = 'Contact ' + keySuffix,
            AccountId = accountId,
            Email = 'gcl74' + keySuffix + '@test.com'
        );
        insert contactRecord;
        Opportunity opportunityRecord = new Opportunity(
            Name = 'GCL74 Opportunity ' + keySuffix,
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

    private static AccountTeamMember buildAccountTeamMember(Id accountId, Id userId, String assignmentType) {
        return new AccountTeamMember(
            AccountId = accountId,
            UserId = userId,
            TeamMemberRole = ROLE_SALES,
            AccountAccessLevel = 'Edit',
            OpportunityAccessLevel = 'Edit',
            AssignmentType__c = assignmentType
        );
    }

    private static Map<Id, Id> getOwnerIdByAccountIdMap(List<Account> accountList) {
        Map<Id, Id> ownerIdByAccountIdMap = new Map<Id, Id>();
        for (Account accountRecord : [SELECT Id, OwnerId FROM Account WHERE Id IN :accountList]) {
            ownerIdByAccountIdMap.put(accountRecord.Id, accountRecord.OwnerId);
        }
        return ownerIdByAccountIdMap;
    }

    private static Integer countAccountTeamRows(Id userId) {
        return [SELECT COUNT() FROM AccountTeamMember WHERE UserId = :userId];
    }

    private static Integer countOpportunityTeamRows(Id userId) {
        return [SELECT COUNT() FROM OpportunityTeamMember WHERE UserId = :userId];
    }

    private static List<InactiveUserAssignmentHistory__c> getHistoryList(Id userId) {
        return [
            SELECT Account__c, Opportunity__c, Assignment_Type__c, AssignmentObject__c,
                UserInactivationDate__c, IsLifeSciences__c
            FROM InactiveUserAssignmentHistory__c
            WHERE User__c = :userId
        ];
    }
}