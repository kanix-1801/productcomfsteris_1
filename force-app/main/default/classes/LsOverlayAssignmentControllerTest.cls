/**
 * @author PWC Developer
 * @date 2026/11/04
 *
 * @group Life Sciences Overlay Assignment
 *
 * @description
 * GCL-79 - Unit tests for LsOverlayAssignmentController and LsOverlayAssignmentService.
 * Country values use the ISO code because CBMDEV has State and Country picklists on.
 */
@IsTest
private class LsOverlayAssignmentControllerTest {

    /**
     * @description GCL-79 - The confirmation label must come from the same constant submit writes.
     */
    @IsTest
    static void assignmentTypeLabelMatchesWhatSubmitWrites() {
        System.assertEquals(
            LsOverlayAssignmentService.ASSIGNMENT_TYPE_SALESFORCE_ASSIGNED,
            LsOverlayAssignmentController.getAssignmentTypeLabel()
        );
    }

    /**
     * @description GCL-79 - Territory search returns the Customer parent, drops GPO, IDN, and Address,
     *              and ignores a Healthcare territory.
     */
    @IsTest
    static void searchesLifeSciencesTerritoriesAndCustomerAccounts() {
        Account parentAccount = insertCustomer('LS Overlay Parent', 'LS-OV-P');
        insertAddress(parentAccount.Id, 'LS Overlay Address', 'LS-OV-A', 'LS-OV-ADDR-1');
        Database.insert(
            new Account(Name = 'LS Overlay IDN', AccountNumber = 'LS-OV-IDN', Type = 'IDN', CustomerClassCode__c = 'SC'),
            allowDuplicates()
        );

        Account gpoParent = new Account(Name = 'LS Overlay GPO Parent', AccountNumber = 'LS-OV-G', Type = 'GPO');
        Database.insert(gpoParent, allowDuplicates());
        insertAddress(gpoParent.Id, 'LS Overlay GPO Address', 'LS-OV-GA', 'LS-OV-ADDR-G');
        insertAddress(null, 'LS Overlay Orphan Address', 'LS-OV-OA', 'LS-OV-ADDR-O');

        insert new List<OrderLineContact__c>{
            lifeSciencesTerritory('LS-OV-ADDR-1', 'LS-TERR-100', 'Life Sciences East', '100'),
            lifeSciencesTerritory('LS-OV-ADDR-1B', 'LS-TERR-100', 'Life Sciences East Duplicate', '100'),
            lifeSciencesTerritory('LS-OV-ADDR-G', 'LS-TERR-GPO', 'GPO Territory', '101'),
            lifeSciencesTerritory('LS-OV-ADDR-O', 'LS-TERR-ORPHAN', 'Orphan Territory', '102'),
            new OrderLineContact__c(
                TASAddressId__c = 'HC-OV-ADDR-1',
                TerritoryID__c = 'HC-TERR-100',
                TerritoryDescription__c = 'Healthcare East',
                TerritoryNumber__c = '100',
                ClassCode__c = 'HC',
                BusinessUnit__c = 'Healthcare'
            )
        };

        Test.startTest();
        System.assertEquals(0, LsOverlayAssignmentController.searchTerritories(null).size());
        System.assertEquals(0, LsOverlayAssignmentController.searchTerritories('   ').size());
        List<LsOverlayAssignmentController.TerritoryWrapper> territories =
            LsOverlayAssignmentController.searchTerritories('LS-TERR-100');
        List<LsOverlayAssignmentController.AccountWrapper> accounts =
            LsOverlayAssignmentController.retrieveAccounts(
                new List<String>{ 'LS-TERR-100', '' },
                'does-not-match',
                'Customer',
                null
            );
        List<LsOverlayAssignmentController.AccountWrapper> namedAccounts =
            LsOverlayAssignmentController.retrieveAccounts(
                new List<String>{ 'LS-TERR-100' },
                'LS Overlay',
                null,
                new List<Id>{ parentAccount.Id }
            );
        System.assertEquals(0, LsOverlayAssignmentController.searchAccounts(null, null, null).size());
        System.assertEquals(0, LsOverlayAssignmentController.searchAccounts('LS Overlay', 'GPO', null).size());
        System.assertEquals(0, LsOverlayAssignmentController.searchAccounts('LS Overlay IDN', 'IDN', null).size());
        List<LsOverlayAssignmentController.AccountWrapper> customerSearch =
            LsOverlayAssignmentController.searchAccounts('LS Overlay Parent', 'Customer', null);
        List<LsOverlayAssignmentController.AccountWrapper> customersByType =
            LsOverlayAssignmentController.searchAccounts(null, 'Customer', null);
        List<LsOverlayAssignmentController.AccountWrapper> gpoTerritory =
            LsOverlayAssignmentController.retrieveAccounts(new List<String>{ 'LS-TERR-GPO' }, null, null, null);
        List<LsOverlayAssignmentController.AccountWrapper> orphanTerritory =
            LsOverlayAssignmentController.retrieveAccounts(new List<String>{ 'LS-TERR-ORPHAN' }, null, null, null);
        List<LsOverlayAssignmentController.AccountWrapper> selectedOnly =
            LsOverlayAssignmentController.retrieveAccounts(null, null, null, new List<Id>{ parentAccount.Id });
        Test.stopTest();

        System.assertEquals(1, territories.size());
        System.assertEquals('LS-TERR-100', territories[0].territoryId);
        System.assertEquals(0, accounts.size(), 'A non-matching name filter should drop the Customer row.');
        System.assertEquals(1, namedAccounts.size());
        System.assertEquals(parentAccount.Id, namedAccounts[0].accountId);
        System.assertEquals('Customer', namedAccounts[0].accountType);
        System.assertEquals('LS-TERR-100', namedAccounts[0].territoryId);
        System.assertEquals(1, customerSearch.size());
        System.assert(customersByType.size() > 0);
        System.assertEquals(0, gpoTerritory.size(), 'A GPO parent should not be shown.');
        System.assertEquals(0, orphanTerritory.size(), 'An Address Account with no parent should not be shown.');
        System.assertEquals(1, selectedOnly.size());
        System.assertEquals(parentAccount.Id, selectedOnly[0].accountId);
    }

    /**
     * @description GCL-79 - Submit copies territory and sales category onto the Customer and Address
     *              team rows, creates shares, and does not duplicate them on a second submit.
     */
    @IsTest
    static void submitCreatesTeamShareAndTasRow() {
        User overlayUser = insertLifeSciencesUser('submit');
        Account parentAccount = insertCustomer('LS Overlay Submit Customer', 'LS-OV-C');
        Account addressAccount = insertAddress(parentAccount.Id, 'LS Overlay Submit Address', 'LS-OV-S', 'LS-OV-ADDR-2');
        Database.insert(
            new Account(
                Name = 'LS Overlay Submit IDN Child',
                AccountNumber = 'LS-OV-IC',
                Type = 'IDN',
                ParentId = parentAccount.Id,
                CustomerClassCode__c = 'SC'
            ),
            allowDuplicates()
        );
        insertAddress(parentAccount.Id, 'LS Overlay Unmatched Address', 'LS-OV-U', 'LS-OV-ADDR-UNMATCHED');
        insert new OrderLineContact__c(
            TASAddressId__c = 'LS-OV-ADDR-2',
            TerritoryID__c = 'LS-TERR-200',
            TerritoryDescription__c = 'Life Sciences West',
            TerritoryNumber__c = '200',
            TAS_Sales_Category__c = 'GI REPROC',
            SalesCategoryDescription__c = 'GI Reprocessing',
            ClassCode__c = 'SC',
            BusinessUnit__c = 'Life Sciences',
            TASZone__c = 'East',
            RegionName__c = 'Great Lakes'
        );
        Integer tasCountBefore = [SELECT COUNT() FROM OrderLineContact__c WHERE TerritoryID__c = 'LS-TERR-200'];

        Test.startTest();
        LsOverlayAssignmentController.submitOverlayAssignments(
            new List<String>{ 'LS-TERR-200' },
            new List<Id>{ parentAccount.Id },
            new List<Id>{ overlayUser.Id }
        );
        LsOverlayAssignmentController.submitOverlayAssignments(
            new List<String>{ 'LS-TERR-200' },
            new List<Id>{ parentAccount.Id },
            new List<Id>{ overlayUser.Id }
        );
        Test.stopTest();

        AccountTeamMember customerMember = [
            SELECT TerritoryCode__c, SalesCategoryCode__c, SalesCategoryDescription__c,
                   TeamMemberRole, AssignmentType__c, AccountAccessLevel, OpportunityAccessLevel, CaseAccessLevel
            FROM AccountTeamMember
            WHERE AccountId = :parentAccount.Id AND UserId = :overlayUser.Id
        ];
        AccountTeamMember addressMember = [
            SELECT TerritoryCode__c, TeamMemberRole, AssignmentType__c, AccountAccessLevel,
                   OpportunityAccessLevel, CaseAccessLevel
            FROM AccountTeamMember
            WHERE AccountId = :addressAccount.Id AND UserId = :overlayUser.Id
        ];
        System.assertEquals('200', customerMember.TerritoryCode__c);
        System.assertEquals('GI REPROC', customerMember.SalesCategoryCode__c);
        System.assertEquals('GI Reprocessing', customerMember.SalesCategoryDescription__c);
        System.assertEquals('200', addressMember.TerritoryCode__c);
        System.assertEquals('Sales', addressMember.TeamMemberRole);
        System.assertEquals('Salesforce Assigned', addressMember.AssignmentType__c);
        System.assertEquals('Edit', addressMember.AccountAccessLevel);
        System.assertEquals('None', addressMember.OpportunityAccessLevel);
        System.assertEquals('None', addressMember.CaseAccessLevel);
        System.assertEquals(1, [
            SELECT COUNT() FROM AccountTeamMember
            WHERE AccountId = :addressAccount.Id AND UserId = :overlayUser.Id
        ]);
        System.assertEquals(0, [
            SELECT COUNT() FROM AccountTeamMember
            WHERE Account.Name = 'LS Overlay Unmatched Address' AND UserId = :overlayUser.Id
        ]);
        System.assertEquals(tasCountBefore + 2, [
            SELECT COUNT() FROM OrderLineContact__c WHERE TerritoryID__c = 'LS-TERR-200'
        ]);
        List<AccountShare> shares = [
            SELECT AccountAccessLevel, RowCause
            FROM AccountShare
            WHERE UserOrGroupId = :overlayUser.Id
            AND AccountId IN :new Set<Id>{ parentAccount.Id, addressAccount.Id }
            AND AccountAccessLevel = 'Edit'
        ];
        System.assertEquals(2, shares.size(), 'Each assigned account should have an Edit share for the overlay user.');
    }

    /**
     * @description GCL-79 - Account-only summary uses the Account Search label. A territory submit
     *              copies the territory number onto the new team row. A second submit does not edit it.
     */
    @IsTest
    static void accountSearchSummaryAndTerritorySubmit() {
        User overlayUser = insertLifeSciencesUser('fill');
        Account parentAccount = insertCustomer('LS Overlay Fill Customer', 'LS-OV-F');
        Account accountOnly = insertCustomer('LS Overlay Account Only', 'LS-OV-AO');
        insertAddress(parentAccount.Id, 'LS Overlay Fill Address', 'LS-OV-FA', 'LS-OV-ADDR-3');
        insert lifeSciencesTerritory('LS-OV-ADDR-3', 'LS-TERR-300', 'Life Sciences Fill', '300');

        Test.startTest();
        LsOverlayAssignmentController.submitOverlayAssignments(
            new List<String>(),
            new List<Id>{ accountOnly.Id },
            new List<Id>{ overlayUser.Id }
        );
        List<LsOverlayAssignmentController.SummaryTerritoryWrapper> accountSummary =
            LsOverlayAssignmentController.getAssignmentSummary(null, new List<Id>{ parentAccount.Id });
        LsOverlayAssignmentController.submitOverlayAssignments(
            new List<String>{ 'LS-TERR-300' },
            new List<Id>{ parentAccount.Id },
            new List<Id>{ overlayUser.Id }
        );
        LsOverlayAssignmentController.submitOverlayAssignments(
            new List<String>{ 'LS-TERR-300' },
            new List<Id>{ parentAccount.Id },
            new List<Id>{ overlayUser.Id }
        );
        List<LsOverlayAssignmentController.SummaryTerritoryWrapper> territorySummary =
            LsOverlayAssignmentController.getAssignmentSummary(
                new List<String>{ 'LS-TERR-300' },
                new List<Id>{ parentAccount.Id }
            );
        List<LsOverlayAssignmentController.UserWrapper> users =
            LsOverlayAssignmentController.searchOverlayUsers(overlayUser.LastName);
        Test.stopTest();

        System.assertEquals(LsOverlayAssignmentService.ACCOUNT_SEARCH_LABEL, accountSummary[0].territoryId);
        System.assertEquals(1, accountSummary[0].selectedAccounts.size());
        System.assertEquals('LS-TERR-300', territorySummary[0].territoryId);
        System.assertEquals(0, LsOverlayAssignmentController.searchOverlayUsers(null).size());
        System.assertEquals(1, users.size());
        System.assertEquals(overlayUser.Id, users[0].userId);
        System.assertEquals('300', [
            SELECT TerritoryCode__c FROM AccountTeamMember
            WHERE AccountId = :parentAccount.Id AND UserId = :overlayUser.Id
        ].TerritoryCode__c);
    }

    /**
     * @description GCL-79 - Missing accounts, users, or retrieve criteria are returned to the screen.
     */
    @IsTest
    static void validationErrorsAreReturnedToTheScreen() {
        System.assert(callThrew(new SubmitNoAccounts()));
        System.assert(callThrew(new SubmitNoUsers()));
        System.assert(callThrew(new RetrieveNothing()));
        System.assert(callThrew(new SummaryNothing()));
    }

    /**
     * @description GCL-79 - A submit that includes anyone outside Life Sciences Sales is rejected
     *              before any account team row is written.
     */
    @IsTest
    static void submitRejectsUsersOutsideLifeSciencesSales() {
        User overlayUser = insertLifeSciencesUser('reject');
        User limitedUser = insertMinimumAccessUser();
        Account customerAccount = insertCustomer('LS Overlay Reject Customer', 'LS-OV-RJ');

        Boolean rejected = false;
        Test.startTest();
        try {
            LsOverlayAssignmentController.submitOverlayAssignments(
                new List<String>(),
                new List<Id>{ customerAccount.Id },
                new List<Id>{ overlayUser.Id, limitedUser.Id }
            );
        } catch (AuraHandledException ex) {
            rejected = ex.getMessage().contains('Select active Life Sciences Sales users only.');
        }
        Test.stopTest();

        System.assert(rejected, 'A user outside Life Sciences Sales should be rejected.');
        System.assertEquals(0, [
            SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :customerAccount.Id
        ]);
    }

    /**
     * @description GCL-79 - A passed GPO still expands its members. IDN members are skipped.
     *              An IDN or Address selected on its own does not pull in other accounts.
     */
    @IsTest
    static void gpoAndIdnSelectionsFollowTheCascadeRules() {
        User overlayUser = insertLifeSciencesUser('gpo');
        Account gpoAccount = new Account(Name = 'LS Overlay Cascade GPO', AccountNumber = 'LS-OV-CG', Type = 'GPO');
        Database.insert(gpoAccount, allowDuplicates());
        Account memberCustomer = insertCustomer('LS Overlay Member Customer', 'LS-OV-MC');
        Account memberAddress = insertAddress(memberCustomer.Id, 'LS Overlay Member Address', 'LS-OV-MA', 'LS-OV-ADDR-M');
        Account unmatchedAddress = insertAddress(null, 'LS Overlay Member Other', 'LS-OV-MO', 'LS-OV-ADDR-X');
        Account nestedGpo = new Account(Name = 'LS Overlay Nested GPO', AccountNumber = 'LS-OV-NG', Type = 'GPO');
        Account idnMember = new Account(Name = 'LS Overlay Member IDN', AccountNumber = 'LS-OV-MI', Type = 'IDN');
        Database.insert(new List<Account>{ nestedGpo, idnMember }, allowDuplicates());
        insert lifeSciencesTerritory('LS-OV-ADDR-M', 'LS-TERR-400', 'Member Territory', '400');

        String hasMember = AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_GPO_MEMBER;
        String isMember = AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_IS_GPO_MEMBER_OF;
        insert new List<AccountAccountRelationship__c>{
            relationship(gpoAccount.Id, memberCustomer.Id, isMember, hasMember),
            relationship(gpoAccount.Id, memberAddress.Id, isMember, hasMember),
            relationship(gpoAccount.Id, unmatchedAddress.Id, isMember, hasMember),
            relationship(gpoAccount.Id, nestedGpo.Id, isMember, hasMember),
            relationship(gpoAccount.Id, idnMember.Id, isMember, hasMember),
            relationship(
                gpoAccount.Id,
                memberCustomer.Id,
                AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_IS_IDN_MEMBER_OF,
                AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_IDN_MEMBER
            )
        };

        Test.startTest();
        LsOverlayAssignmentController.submitOverlayAssignments(
            new List<String>{ 'LS-TERR-400' },
            new List<Id>{ gpoAccount.Id, idnMember.Id, unmatchedAddress.Id },
            new List<Id>{ overlayUser.Id }
        );
        Test.stopTest();

        Set<Id> teamAccountIds = new Set<Id>();
        for (AccountTeamMember teamMember : [
            SELECT AccountId FROM AccountTeamMember WHERE UserId = :overlayUser.Id
        ]) {
            teamAccountIds.add(teamMember.AccountId);
        }
        System.assert(teamAccountIds.contains(gpoAccount.Id));
        System.assert(teamAccountIds.contains(memberCustomer.Id));
        System.assert(teamAccountIds.contains(memberAddress.Id));
        System.assert(teamAccountIds.contains(nestedGpo.Id));
        System.assert(teamAccountIds.contains(unmatchedAddress.Id), 'The selected Address is included even when it is not a territory match.');
        System.assert(!teamAccountIds.contains(idnMember.Id), 'An IDN should not receive a team row.');
    }

    /**
     * @description GCL-79 - A user who cannot read the overlay objects receives a handled error.
     *              User search is the exception: it cannot use USER_MODE, so it returns a list.
     */
    @IsTest
    static void usersWithoutAccessReceiveHandledErrors() {
        User limitedUser = insertMinimumAccessUser();
        Boolean searchTerritoriesThrew = false;
        Boolean searchAccountsThrew = false;
        Boolean searchUsersThrew = false;
        Boolean retrieveThrew = false;
        System.runAs(limitedUser) {
            searchTerritoriesThrew = callThrew(new SearchTerritories());
            searchAccountsThrew = callThrew(new SearchAccounts());
            searchUsersThrew = callThrew(new SearchUsers());
            retrieveThrew = callThrew(new RetrieveAccounts());
        }
        System.assert(searchTerritoriesThrew);
        System.assert(searchAccountsThrew);
        System.assert(!searchUsersThrew, 'User search returns a list without User field access.');
        System.assert(retrieveThrew);
    }

    private class SubmitNoAccounts implements CallableAction {
        public void execute() {
            LsOverlayAssignmentController.submitOverlayAssignments(null, new List<Id>(), new List<Id>{ UserInfo.getUserId() });
        }
    }
    private class SubmitNoUsers implements CallableAction {
        public void execute() {
            LsOverlayAssignmentController.submitOverlayAssignments(null, new List<Id>{ UserInfo.getUserId() }, new List<Id>());
        }
    }
    private class RetrieveNothing implements CallableAction {
        public void execute() {
            LsOverlayAssignmentController.retrieveAccounts(null, null, null, null);
        }
    }
    private class SummaryNothing implements CallableAction {
        public void execute() {
            LsOverlayAssignmentController.getAssignmentSummary(null, new List<Id>());
        }
    }
    private class SearchTerritories implements CallableAction {
        public void execute() {
            LsOverlayAssignmentController.searchTerritories('LS');
        }
    }
    private class SearchAccounts implements CallableAction {
        public void execute() {
            LsOverlayAssignmentController.searchAccounts('LS', 'Customer', null);
        }
    }
    private class SearchUsers implements CallableAction {
        public void execute() {
            LsOverlayAssignmentController.searchOverlayUsers('LS');
        }
    }
    private class RetrieveAccounts implements CallableAction {
        public void execute() {
            LsOverlayAssignmentController.retrieveAccounts(new List<String>{ 'LS' }, null, null, null);
        }
    }

    private interface CallableAction {
        void execute();
    }

    private static Boolean callThrew(CallableAction action) {
        try {
            action.execute();
            return false;
        } catch (AuraHandledException ex) {
            return true;
        }
    }

    private static Account insertCustomer(String name, String accountNumber) {
        Account customerAccount = new Account(
            Name = name,
            AccountNumber = accountNumber,
            Type = 'Customer',
            CustomerClassCode__c = 'SC'
        );
        Database.insert(customerAccount, allowDuplicates());
        return customerAccount;
    }

    private static Account insertAddress(Id parentId, String name, String accountNumber, String oracleAddressId) {
        Account addressAccount = new Account(
            Name = name,
            AccountNumber = accountNumber,
            Type = 'Address',
            ParentId = parentId,
            CustomerClassCode__c = 'SC',
            OracleAddressId__c = oracleAddressId,
            BillingStreet = '1 Science Way',
            BillingCity = 'Mentor',
            BillingPostalCode = '44060',
            BillingCountryCode = 'US'
        );
        Database.insert(addressAccount, allowDuplicates());
        return addressAccount;
    }

    private static OrderLineContact__c lifeSciencesTerritory(
        String tasAddressId,
        String territoryId,
        String description,
        String territoryNumber
    ) {
        return new OrderLineContact__c(
            TASAddressId__c = tasAddressId,
            TerritoryID__c = territoryId,
            TerritoryDescription__c = description,
            TerritoryNumber__c = territoryNumber,
            ClassCode__c = 'SC',
            BusinessUnit__c = 'Life Sciences'
        );
    }

    private static AccountAccountRelationship__c relationship(
        Id parentId,
        Id childId,
        String relationshipType,
        String inverseType
    ) {
        return new AccountAccountRelationship__c(
            ParentAccount__c = parentId,
            ChildAccount__c = childId,
            RelationshipType__c = relationshipType,
            InverseRelationshipType__c = inverseType
        );
    }

    private static User insertLifeSciencesUser(String seed) {
        Profile lifeSciencesProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = :UserSelector.LIFESCIENCES_SALES_PROFILE_NAME
            LIMIT 1
        ];
        return insertUser(lifeSciencesProfile.Id, seed, true);
    }

    private static User insertMinimumAccessUser() {
        Profile minimumAccess = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Minimum Access - Salesforce'
            LIMIT 1
        ];
        return insertUser(minimumAccess.Id, 'limited', false);
    }

    private static Database.DMLOptions allowDuplicates() {
        Database.DMLOptions options = new Database.DMLOptions();
        options.DuplicateRuleHeader.allowSave = true;
        return options;
    }

    private static User insertUser(Id profileId, String seed, Boolean setEmployeeNumber) {
        String uniqueSeed = seed + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User overlayUser = new User(
            FirstName = 'LS',
            LastName = 'Overlay' + uniqueSeed.right(5),
            Alias = ('l' + uniqueSeed).left(8),
            Email = 'ls.overlay.' + uniqueSeed + '@example.com',
            Username = 'ls.overlay.' + uniqueSeed + '@example.com',
            CommunityNickname = ('lsov' + uniqueSeed).left(40),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileId,
            IsActive = true
        );
        if (setEmployeeNumber) {
            overlayUser.EmployeeNumber__c = ('LS' + uniqueSeed).left(20);
            overlayUser.UserRoleId = [SELECT Id FROM UserRole LIMIT 1].Id;
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert overlayUser;
        }
        return overlayUser;
    }
}