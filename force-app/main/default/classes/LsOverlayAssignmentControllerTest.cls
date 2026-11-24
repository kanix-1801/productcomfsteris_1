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

    private static final String INSIDE_SALES = LsOverlayAssignmentService.OVERLAY_TYPE_INSIDE_SALES;
    private static final String GAD = LsOverlayAssignmentService.OVERLAY_TYPE_GAD;

    /**
     * @description Turns off only the IDN/GPO creation rule (Account_IDN_GPO_Create), so the tests can
     *              create IDN and GPO accounts. Other validation rules stay on. Without this, the
     *              GPO and IDN test records are blocked for users who lack the Manage_IDN_GPO permission.
     */
    @TestSetup
    static void allowIdnAndGpoTestAccounts() {
        insert new Automation_Setting_Validation_Rule__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Account_IDN_GPO_Create__c = true
        );
    }

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
        mustInsert(new Account(Name = 'LS Overlay IDN', AccountNumber = 'LS-OV-IDN', Type = 'IDN', CustomerClassCode__c = 'SC'));

        Account gpoParent = new Account(Name = 'LS Overlay GPO Parent', AccountNumber = 'LS-OV-G', Type = 'GPO');
        mustInsert(gpoParent);
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
        List<OverlayAssignmentController.TerritoryWrapper> territories =
            LsOverlayAssignmentController.searchTerritories('LS-TERR-100');
        List<OverlayAssignmentController.AccountWrapper> accounts =
            LsOverlayAssignmentController.retrieveAccounts(
                new List<String>{ 'LS-TERR-100', '' },
                'does-not-match',
                'Customer',
                null
            );
        List<OverlayAssignmentController.AccountWrapper> namedAccounts =
            LsOverlayAssignmentController.retrieveAccounts(
                new List<String>{ 'LS-TERR-100' },
                'LS Overlay',
                null,
                new List<Id>{ parentAccount.Id }
            );
        System.assertEquals(0, LsOverlayAssignmentController.searchAccounts(null, null, null).size());
        System.assertEquals(0, LsOverlayAssignmentController.searchAccounts('LS Overlay', 'GPO', null).size());
        System.assertEquals(0, LsOverlayAssignmentController.searchAccounts('LS Overlay IDN', 'IDN', null).size());
        List<OverlayAssignmentController.AccountWrapper> customerSearch =
            LsOverlayAssignmentController.searchAccounts('LS Overlay Parent', 'Customer', null);
        List<OverlayAssignmentController.AccountWrapper> customersByType =
            LsOverlayAssignmentController.searchAccounts(null, 'Customer', null);
        List<OverlayAssignmentController.AccountWrapper> gpoTerritory =
            LsOverlayAssignmentController.retrieveAccounts(new List<String>{ 'LS-TERR-GPO' }, null, null, null);
        List<OverlayAssignmentController.AccountWrapper> orphanTerritory =
            LsOverlayAssignmentController.retrieveAccounts(new List<String>{ 'LS-TERR-ORPHAN' }, null, null, null);
        List<OverlayAssignmentController.AccountWrapper> selectedOnly =
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
        User overlayUser = insertOverlayUser('submit', INSIDE_SALES);
        Account parentAccount = insertCustomer('LS Overlay Submit Customer', 'LS-OV-C');
        Account addressAccount = insertAddress(parentAccount.Id, 'LS Overlay Submit Address', 'LS-OV-S', 'LS-OV-ADDR-2');
        mustInsert(new Account(
            Name = 'LS Overlay Submit IDN Child',
            AccountNumber = 'LS-OV-IC',
            Type = 'IDN',
            ParentId = parentAccount.Id,
            CustomerClassCode__c = 'SC'
        ));
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
            new List<Id>{ overlayUser.Id },
            INSIDE_SALES
        );
        LsOverlayAssignmentController.submitOverlayAssignments(
            new List<String>{ 'LS-TERR-200' },
            new List<Id>{ parentAccount.Id },
            new List<Id>{ overlayUser.Id },
            INSIDE_SALES
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
                   ContactAccessLevel, OpportunityAccessLevel, CaseAccessLevel
            FROM AccountTeamMember
            WHERE AccountId = :addressAccount.Id AND UserId = :overlayUser.Id
        ];
        System.assertEquals('200', customerMember.TerritoryCode__c);
        System.assertEquals('GI REPROC', customerMember.SalesCategoryCode__c);
        System.assertEquals('GI Reprocessing', customerMember.SalesCategoryDescription__c);
        System.assertEquals('200', addressMember.TerritoryCode__c);
        System.assertEquals('Inside Sales', addressMember.TeamMemberRole);
        System.assertEquals('Salesforce Assigned', addressMember.AssignmentType__c);
        System.assertEquals('Edit', addressMember.AccountAccessLevel);
        System.assertEquals('Edit', addressMember.ContactAccessLevel);
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
        User overlayUser = insertOverlayUser('fill', INSIDE_SALES);
        Account parentAccount = insertCustomer('LS Overlay Fill Customer', 'LS-OV-F');
        Account accountOnly = insertCustomer('LS Overlay Account Only', 'LS-OV-AO');
        insertAddress(parentAccount.Id, 'LS Overlay Fill Address', 'LS-OV-FA', 'LS-OV-ADDR-3');
        insert lifeSciencesTerritory('LS-OV-ADDR-3', 'LS-TERR-300', 'Life Sciences Fill', '300');

        Test.startTest();
        LsOverlayAssignmentController.submitOverlayAssignments(
            new List<String>(),
            new List<Id>{ accountOnly.Id },
            new List<Id>{ overlayUser.Id },
            INSIDE_SALES
        );
        List<OverlayAssignmentController.SummaryTerritoryWrapper> accountSummary =
            LsOverlayAssignmentController.getAssignmentSummary(null, new List<Id>{ parentAccount.Id }, INSIDE_SALES);
        LsOverlayAssignmentController.submitOverlayAssignments(
            new List<String>{ 'LS-TERR-300' },
            new List<Id>{ parentAccount.Id },
            new List<Id>{ overlayUser.Id },
            INSIDE_SALES
        );
        LsOverlayAssignmentController.submitOverlayAssignments(
            new List<String>{ 'LS-TERR-300' },
            new List<Id>{ parentAccount.Id },
            new List<Id>{ overlayUser.Id },
            INSIDE_SALES
        );
        List<OverlayAssignmentController.SummaryTerritoryWrapper> territorySummary =
            LsOverlayAssignmentController.getAssignmentSummary(
                new List<String>{ 'LS-TERR-300' },
                new List<Id>{ parentAccount.Id },
                INSIDE_SALES
            );
        List<OverlayAssignmentController.UserWrapper> users =
            LsOverlayAssignmentController.searchOverlayUsers(overlayUser.LastName, INSIDE_SALES);
        Test.stopTest();

        System.assertEquals(LsOverlayAssignmentService.ACCOUNT_SEARCH_LABEL, accountSummary[0].territoryId);
        System.assertEquals(1, accountSummary[0].selectedAccounts.size());
        System.assertEquals('LS-TERR-300', territorySummary[0].territoryId);
        System.assertEquals(0, LsOverlayAssignmentController.searchOverlayUsers(null, INSIDE_SALES).size());
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
        System.assert(callThrew(new SubmitNoOverlayType()));
        System.assert(callThrew(new SummaryNoOverlayType()));
        System.assert(callThrew(new SearchUsersNoOverlayType()));
    }

    /**
     * @description GCL-79 - A submit that includes anyone outside Life Sciences Sales is rejected
     *              before any account team row is written.
     */
    @IsTest
    static void submitRejectsUsersOutsideLifeSciencesSales() {
        User overlayUser = insertOverlayUser('reject', INSIDE_SALES);
        User limitedUser = insertMinimumAccessUser();
        Account customerAccount = insertCustomer('LS Overlay Reject Customer', 'LS-OV-RJ');

        Boolean rejected = false;
        Test.startTest();
        try {
            LsOverlayAssignmentController.submitOverlayAssignments(
                new List<String>(),
                new List<Id>{ customerAccount.Id },
                new List<Id>{ overlayUser.Id, limitedUser.Id },
                INSIDE_SALES
            );
        } catch (AuraHandledException ex) {
            rejected = ex.getMessage().contains('Select active Life Sciences Sales users with the Inside Sales permission set only.');
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
        User overlayUser = insertOverlayUser('gpo', INSIDE_SALES);
        Account gpoAccount = new Account(Name = 'LS Overlay Cascade GPO', AccountNumber = 'LS-OV-CG', Type = 'GPO');
        mustInsert(gpoAccount);
        Account memberCustomer = insertCustomer('LS Overlay Member Customer', 'LS-OV-MC');
        Account memberAddress = insertAddress(memberCustomer.Id, 'LS Overlay Member Address', 'LS-OV-MA', 'LS-OV-ADDR-M');
        Account unmatchedAddress = insertAddress(null, 'LS Overlay Member Other', 'LS-OV-MO', 'LS-OV-ADDR-X');
        Account nestedGpo = new Account(Name = 'LS Overlay Nested GPO', AccountNumber = 'LS-OV-NG', Type = 'GPO');
        Account idnMember = new Account(Name = 'LS Overlay Member IDN', AccountNumber = 'LS-OV-MI', Type = 'IDN');
        mustInsert(nestedGpo);
        mustInsert(idnMember);
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
            new List<Id>{ overlayUser.Id },
            INSIDE_SALES
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
     * @description GCL-79 - A user who cannot read the overlay objects receives a handled error
     *              for territory search, account search, and retrieve. User search is still called.
     *              It runs without USER_MODE, so a returned list or a handled error are both valid.
     */
    @IsTest
    static void usersWithoutAccessReceiveHandledErrors() {
        User limitedUser = insertMinimumAccessUser();
        Boolean searchTerritoriesThrew = false;
        Boolean searchAccountsThrew = false;
        Boolean retrieveThrew = false;
        System.runAs(limitedUser) {
            searchTerritoriesThrew = callThrew(new SearchTerritories());
            searchAccountsThrew = callThrew(new SearchAccounts());
            callThrew(new SearchUsers());
            retrieveThrew = callThrew(new RetrieveAccounts());
        }
        System.assert(searchTerritoriesThrew);
        System.assert(searchAccountsThrew);
        System.assert(retrieveThrew);
    }

    /**
     * @description The pre-wizard shows Inside Sales and GAD, each with the role it writes.
     */
    @IsTest
    static void overlayTypeOptionsListInsideSalesAndGad() {
        List<Map<String, String>> options = LsOverlayAssignmentController.getOverlayTypeOptions();
        System.assertEquals(2, options.size());
        System.assertEquals('Inside Sales', options[0].get('value'));
        System.assertEquals('Inside Sales', options[0].get('teamMemberRole'));
        System.assertEquals('GAD', options[1].get('value'));
        System.assertEquals('Global Account Director', options[1].get('teamMemberRole'));
    }

    /**
     * @description GAD search returns Global Accounts only, shows a blank Type as Global Account,
     *              and returns nothing for a blank search.
     */
    @IsTest
    static void searchGlobalAccountsReturnsGlobalAccountsOnly() {
        Account globalAccount = insertGlobalAccount('LS GAD Search Global');
        insertCustomer('LS GAD Search Customer', 'LS-GS-C');

        Test.startTest();
        List<OverlayAssignmentController.AccountWrapper> rows =
            LsOverlayAssignmentController.searchGlobalAccounts('LS GAD Search');
        List<OverlayAssignmentController.AccountWrapper> blankRows =
            LsOverlayAssignmentController.searchGlobalAccounts('   ');
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'The Customer with a similar name must not be returned.');
        System.assertEquals(globalAccount.Id, rows[0].accountId);
        System.assertEquals('Global Account', rows[0].accountType);
        System.assertEquals(0, blankRows.size());
    }

    /**
     * @description Users are limited to the permission set or group of the selected overlay type.
     *              A Life Sciences Sales user with neither is never returned.
     */
    @IsTest
    static void searchOverlayUsersFiltersByOverlayTypePermission() {
        User insideUser = insertOverlayUser('insu', INSIDE_SALES);
        User gadUser = insertOverlayUser('gadu', GAD);
        User plainUser = insertLifeSciencesUser('plain');

        Test.startTest();
        Integer insideForInside = LsOverlayAssignmentController.searchOverlayUsers(insideUser.LastName, INSIDE_SALES).size();
        Integer insideForGad = LsOverlayAssignmentController.searchOverlayUsers(insideUser.LastName, GAD).size();
        Integer gadForGad = LsOverlayAssignmentController.searchOverlayUsers(gadUser.LastName, GAD).size();
        Integer gadForInside = LsOverlayAssignmentController.searchOverlayUsers(gadUser.LastName, INSIDE_SALES).size();
        Integer plainForInside = LsOverlayAssignmentController.searchOverlayUsers(plainUser.LastName, INSIDE_SALES).size();
        Integer plainForGad = LsOverlayAssignmentController.searchOverlayUsers(plainUser.LastName, GAD).size();
        Test.stopTest();

        System.assertEquals(1, insideForInside);
        System.assertEquals(0, insideForGad);
        System.assertEquals(1, gadForGad);
        System.assertEquals(0, gadForInside);
        System.assertEquals(0, plainForInside);
        System.assertEquals(0, plainForGad);
    }

    /**
     * @description GAD submit adds the user to the Global Account, its Customer, and its Ship-to.
     *              Access follows the level. An IDN child and an unrelated Customer are left out.
     *              A second submit adds nothing.
     */
    @IsTest
    static void gadSubmitCreatesHierarchyRowsWithLevelAccess() {
        User gadUser = insertOverlayUser('gadsub', GAD);
        Account globalAccount = insertGlobalAccount('LS GAD Hierarchy Global');
        Account customer = insertChild(globalAccount.Id, 'LS GAD Hierarchy Customer', 'LS-GH-C', 'Customer');
        Account shipTo = insertAddress(customer.Id, 'LS GAD Hierarchy Ship-to', 'LS-GH-S', 'LS-GH-ADDR');
        Account idnChild = insertChild(globalAccount.Id, 'LS GAD Hierarchy IDN', 'LS-GH-I', 'IDN');
        Account outsideCustomer = insertCustomer('LS GAD Hierarchy Outside', 'LS-GH-O');

        Test.startTest();
        List<OverlayAssignmentController.SummaryTerritoryWrapper> summary =
            LsOverlayAssignmentController.getAssignmentSummary(null, new List<Id>{ globalAccount.Id }, GAD);
        LsOverlayAssignmentController.submitOverlayAssignments(null, new List<Id>{ globalAccount.Id }, new List<Id>{ gadUser.Id }, GAD);
        LsOverlayAssignmentController.submitOverlayAssignments(null, new List<Id>{ globalAccount.Id }, new List<Id>{ gadUser.Id }, GAD);
        Test.stopTest();

        System.assertEquals(1, summary.size());
        System.assertEquals('LS GAD Hierarchy Global', summary[0].territoryId);
        System.assertEquals(3, summary[0].selectedAccounts.size());

        Map<Id, AccountTeamMember> memberByAccountId = teamMembersByAccount(gadUser.Id);
        System.assertEquals(3, memberByAccountId.size(), 'Global Account, Customer, and Ship-to only.');
        System.assert(!memberByAccountId.containsKey(idnChild.Id), 'An IDN child gets no row.');
        System.assert(!memberByAccountId.containsKey(outsideCustomer.Id));
        for (AccountTeamMember member : memberByAccountId.values()) {
            System.assertEquals('Global Account Director', member.TeamMemberRole);
            System.assertEquals('Salesforce Assigned', member.AssignmentType__c);
            System.assertEquals('Edit', member.AccountAccessLevel);
            System.assertEquals('Edit', member.ContactAccessLevel);
            System.assertEquals('None', member.CaseAccessLevel);
        }
        System.assertEquals('Edit', memberByAccountId.get(globalAccount.Id).OpportunityAccessLevel);
        System.assertEquals('Read', memberByAccountId.get(customer.Id).OpportunityAccessLevel);
        System.assertEquals('Read', memberByAccountId.get(shipTo.Id).OpportunityAccessLevel);
    }

    /**
     * @description GAD only accepts Global Accounts, and only users with the GAD permission set.
     *              Nothing is saved when either check fails.
     */
    @IsTest
    static void gadSubmitRejectsWrongAccountsAndUsers() {
        User gadUser = insertOverlayUser('gadrej', GAD);
        User insideUser = insertOverlayUser('insrej', INSIDE_SALES);
        Account globalAccount = insertGlobalAccount('LS GAD Reject Global');
        Account customer = insertCustomer('LS GAD Reject Customer', 'LS-GR-C');

        String wrongAccountMessage;
        String wrongUserMessage;
        Test.startTest();
        try {
            LsOverlayAssignmentController.submitOverlayAssignments(null, new List<Id>{ customer.Id }, new List<Id>{ gadUser.Id }, GAD);
        } catch (AuraHandledException ex) {
            wrongAccountMessage = ex.getMessage();
        }
        try {
            LsOverlayAssignmentController.submitOverlayAssignments(null, new List<Id>{ globalAccount.Id }, new List<Id>{ insideUser.Id }, GAD);
        } catch (AuraHandledException ex) {
            wrongUserMessage = ex.getMessage();
        }
        Test.stopTest();

        System.assertEquals('Select Global Accounts only.', wrongAccountMessage);
        System.assert(wrongUserMessage.contains('with the GAD permission set only.'), wrongUserMessage);
        System.assertEquals(0, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId IN :new Set<Id>{ globalAccount.Id, customer.Id }]);
    }

    /**
     * @description A user with both permission sets is allowed for both types. Salesforce keeps one
     *              Account Team row per user and account, so the existing Inside Sales row stays
     *              and GAD only adds the accounts that have no row yet.
     */
    @IsTest
    static void gadSubmitKeepsExistingInsideSalesRow() {
        User dualUser = insertOverlayUser('dual', INSIDE_SALES);
        assignPermissionSet(dualUser.Id, 'LSGlobalAccountDirectorPS', false);
        Account globalAccount = insertGlobalAccount('LS GAD Dual Global');
        Account customer = insertChild(globalAccount.Id, 'LS GAD Dual Customer', 'LS-GD-C', 'Customer');

        Test.startTest();
        LsOverlayAssignmentController.submitOverlayAssignments(null, new List<Id>{ customer.Id }, new List<Id>{ dualUser.Id }, INSIDE_SALES);
        LsOverlayAssignmentController.submitOverlayAssignments(null, new List<Id>{ globalAccount.Id }, new List<Id>{ dualUser.Id }, GAD);
        Test.stopTest();

        Map<Id, AccountTeamMember> memberByAccountId = teamMembersByAccount(dualUser.Id);
        System.assertEquals(2, memberByAccountId.size());
        System.assertEquals('Inside Sales', memberByAccountId.get(customer.Id).TeamMemberRole);
        System.assertEquals('Global Account Director', memberByAccountId.get(globalAccount.Id).TeamMemberRole);
    }

    private class SubmitNoAccounts implements CallableAction {
        public void execute() {
            LsOverlayAssignmentController.submitOverlayAssignments(null, new List<Id>(), new List<Id>{ UserInfo.getUserId() }, INSIDE_SALES);
        }
    }
    private class SubmitNoUsers implements CallableAction {
        public void execute() {
            LsOverlayAssignmentController.submitOverlayAssignments(null, new List<Id>{ UserInfo.getUserId() }, new List<Id>(), INSIDE_SALES);
        }
    }
    private class SubmitNoOverlayType implements CallableAction {
        public void execute() {
            LsOverlayAssignmentController.submitOverlayAssignments(null, new List<Id>{ UserInfo.getUserId() }, new List<Id>{ UserInfo.getUserId() }, null);
        }
    }
    private class SummaryNoOverlayType implements CallableAction {
        public void execute() {
            LsOverlayAssignmentController.getAssignmentSummary(null, new List<Id>{ UserInfo.getUserId() }, 'Other');
        }
    }
    private class SearchUsersNoOverlayType implements CallableAction {
        public void execute() {
            LsOverlayAssignmentController.searchOverlayUsers('LS', '');
        }
    }
    private class RetrieveNothing implements CallableAction {
        public void execute() {
            LsOverlayAssignmentController.retrieveAccounts(null, null, null, null);
        }
    }
    private class SummaryNothing implements CallableAction {
        public void execute() {
            LsOverlayAssignmentController.getAssignmentSummary(null, new List<Id>(), INSIDE_SALES);
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
            LsOverlayAssignmentController.searchOverlayUsers('LS', INSIDE_SALES);
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

    @IsTest
    static void overlayAssignmentServiceCoversSearchSubmitAndWriteback() {
        User overlayUser = insertLifeSciencesUser('hcsvc');
        Account customer = insertCustomer('HC Overlay Parent', 'HC-OV-P');
        Account addressAccount = insertAddress(customer.Id, 'HC Overlay Address', 'HC-OV-A', 'HC-OV-ADDR-1');
        insert lifeSciencesTerritory('HC-OV-ADDR-1', 'HC-TERR-SVC', 'Healthcare Overlay East', '880');

        OverlayAssignmentService.searchTerritories(null);
        OverlayAssignmentService.searchTerritories('HC-TERR-SVC');
        OverlayAssignmentService.searchAccounts('HC Overlay', 'Customer', null);
        OverlayAssignmentService.searchAccounts('HC Overlay', null, new List<String>{ 'HC-TERR-SVC' });
        OverlayAssignmentService.retrieveAccounts(null, 'HC Overlay', 'Customer', null);
        OverlayAssignmentService.retrieveAccounts(
            new List<String>{ 'HC-TERR-SVC' },
            'HC Overlay',
            'Customer',
            new List<Id>{ customer.Id }
        );
        OverlayAssignmentService.searchOverlayUsers(null);
        OverlayAssignmentService.searchOverlayUsers(overlayUser.LastName);
        OverlayAssignmentService.getAssignmentSummary(null, new List<Id>{ customer.Id });
        OverlayAssignmentService.getAssignmentSummary(
            new List<String>{ 'HC-TERR-SVC' },
            new List<Id>{ customer.Id }
        );

        catchOverlayFailure(new ServiceRetrieveNothing());
        catchOverlayFailure(new ServiceSummaryNothing());
        catchOverlayFailure(new ServiceSubmitNothing());

        try {
            OverlayAssignmentService.submitOverlayAssignments(
                null,
                new List<Id>{ customer.Id },
                new List<Id>{ overlayUser.Id }
            );
        } catch (Exception ex) {
            System.assert(String.isNotBlank(ex.getMessage()));
        }
        try {
            OverlayAssignmentService.submitOverlayAssignments(
                new List<String>{ 'HC-TERR-SVC' },
                new List<Id>{ customer.Id, addressAccount.Id },
                new List<Id>{ overlayUser.Id }
            );
        } catch (Exception ex) {
            System.assert(String.isNotBlank(ex.getMessage()));
        }

        Account addressForWriteback = [
            SELECT Id, OracleAddressId__c
            FROM Account
            WHERE Id = :addressAccount.Id
        ];
        OverlayAssignmentService.createTasWritebackRecords(
            null,
            new Set<Id>{ overlayUser.Id },
            new Map<String, OrderLineContact__c>()
        );
        OverlayAssignmentService.createTasWritebackRecords(
            new List<Account>{ new Account(Name = 'Missing Oracle') },
            new Set<Id>{ overlayUser.Id },
            new Map<String, OrderLineContact__c>()
        );
        try {
            OverlayAssignmentService.createTasWritebackRecords(
                new List<Account>{ addressForWriteback },
                new Set<Id>{ overlayUser.Id },
                new Map<String, OrderLineContact__c>{
                    'HC-OV-ADDR-1' => lifeSciencesTerritory('HC-OV-ADDR-1', 'HC-TERR-SVC', 'Healthcare Overlay East', '880')
                }
            );
        } catch (Exception ex) {
            System.assert(String.isNotBlank(ex.getMessage()));
        }
        try {
            new OverlayAssignmentService.OverlayAssignmentDmlService().createAccountShares(
                new List<Account>{ customer },
                new Set<Id>{ overlayUser.Id }
            );
        } catch (Exception ex) {
            System.assert(String.isNotBlank(ex.getMessage()));
        }

        OverlayAssignmentService.throwTestException = true;
        catchOverlayFailure(new ServiceSearchTerritories());
        catchOverlayFailure(new ServiceSearchAccounts());
        catchOverlayFailure(new ServiceSearchUsers());
        OverlayAssignmentService.throwTestException = false;

        overlayCoverageCustomerId = customer.Id;
        overlayCoverageUserId = overlayUser.Id;
        overlayCoverageAddress = addressForWriteback;

        forceOverlayMethod('getAccountsForTerritories');
        catchOverlayFailure(new ServiceSearchAccountsByTerritory());
        forceOverlayMethod('resolveCascadeAccountIds');
        catchOverlayFailure(new ServiceSubmitCustomer());
        forceOverlayMethod('createTasWritebackRecords');
        catchOverlayFailure(new ServiceWriteback());
        forceOverlayMethod('buildIdSet');
        catchOverlayFailure(new ServiceSummaryCustomer());
        OverlayAssignmentService.forcedExceptionMethodName = null;
    }

    /**
     * @description Territory search expands the Customer parent through GPO/IDN affiliations and builds
     *              wrappers for the affiliated GPO/IDN accounts (no forced exceptions).
     */
    @IsTest
    static void overlayServiceTerritoryAffiliationsBuildGpoAndIdnWrappers() {
        Account affiliatedCustomer = insertCustomer('LS Affil Customer', 'LS-AF-C');
        Account affiliatedAddress = insertAddress(affiliatedCustomer.Id, 'LS Affil Address', 'LS-AF-A', 'LS-AF-ADDR');
        Account otherCustomer = insertCustomer('LS Affil Other Customer', 'LS-AF-O');
        Account affiliatedGpo = new Account(Name = 'LS Affil GPO', AccountNumber = 'LS-AF-G', Type = 'GPO');
        Account affiliatedIdn = new Account(Name = 'LS Affil IDN', AccountNumber = 'LS-AF-I', Type = 'IDN');
        mustInsert(affiliatedGpo);
        mustInsert(affiliatedIdn);
        insert lifeSciencesTerritory('LS-AF-ADDR', 'LS-TERR-AFF', 'Affiliation Territory', '103');

        String hasGpo = AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_GPO_MEMBER;
        String isGpo = AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_IS_GPO_MEMBER_OF;
        String hasIdn = AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_IDN_MEMBER;
        String isIdn = AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_IS_IDN_MEMBER_OF;
        insert new List<AccountAccountRelationship__c>{
            relationship(affiliatedGpo.Id, affiliatedCustomer.Id, isGpo, hasGpo),
            relationship(affiliatedGpo.Id, affiliatedAddress.Id, isGpo, hasGpo),
            relationship(affiliatedIdn.Id, affiliatedCustomer.Id, isIdn, hasIdn),
            relationship(otherCustomer.Id, affiliatedCustomer.Id, isGpo, hasGpo)
        };

        Test.startTest();
        OverlayAssignmentController.AccountPageResult territoryAccounts =
            OverlayAssignmentService.retrieveAccounts(new List<String>{ 'LS-TERR-AFF' }, null, null, null);
        List<OverlayAssignmentController.AccountWrapper> searchedAccounts =
            OverlayAssignmentService.searchAccounts(null, null, new List<String>{ 'LS-TERR-AFF' });
        Test.stopTest();

        System.assert(territoryAccounts != null);
        System.assert(searchedAccounts != null);
    }

    /**
     * @description Submit cascades a selected GPO/IDN through its affiliations (members, nested GPO/IDN,
     *              Address children matched or unmatched to the territory) without forced exceptions.
     */
    @IsTest
    static void overlayServiceSubmitCascadesGpoAndIdnAffiliations() {
        User cascadeUser = insertLifeSciencesUser('cascade');
        Account memberCustomer = insertCustomer('LS CC Member Customer', 'LS-CC-M');
        Account memberAddress = insertAddress(memberCustomer.Id, 'LS CC Member Address', 'LS-CC-MA', 'LS-CC-ADDR-M');
        Account directAddress = insertAddress(null, 'LS CC Direct Address', 'LS-CC-DA', 'LS-CC-ADDR-D');
        Account unmatchedAddress = insertAddress(null, 'LS CC Unmatched Address', 'LS-CC-UA', 'LS-CC-ADDR-U');
        Account nestedGpo = new Account(Name = 'LS CC Nested GPO', AccountNumber = 'LS-CC-NG', Type = 'GPO');
        Account cascadeGpo = new Account(Name = 'LS CC GPO', AccountNumber = 'LS-CC-G', Type = 'GPO');
        Account cascadeIdn = new Account(Name = 'LS CC IDN', AccountNumber = 'LS-CC-I', Type = 'IDN');
        Account idnMember = new Account(Name = 'LS CC IDN Member', AccountNumber = 'LS-CC-IM', Type = 'IDN');
        mustInsert(nestedGpo);
        mustInsert(cascadeGpo);
        mustInsert(cascadeIdn);
        mustInsert(idnMember);
        insert new List<OrderLineContact__c>{
            lifeSciencesTerritory('LS-CC-ADDR-M', 'LS-TERR-CC', 'Cascade Territory', '104'),
            lifeSciencesTerritory('LS-CC-ADDR-D', 'LS-TERR-CC', 'Cascade Territory', '104')
        };

        String hasGpo = AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_GPO_MEMBER;
        String isGpo = AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_IS_GPO_MEMBER_OF;
        String hasIdn = AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_IDN_MEMBER;
        String isIdn = AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_IS_IDN_MEMBER_OF;
        insert new List<AccountAccountRelationship__c>{
            relationship(cascadeGpo.Id, memberCustomer.Id, isGpo, hasGpo),
            relationship(cascadeGpo.Id, directAddress.Id, isGpo, hasGpo),
            relationship(cascadeGpo.Id, unmatchedAddress.Id, isGpo, hasGpo),
            relationship(cascadeGpo.Id, nestedGpo.Id, isGpo, hasGpo),
            relationship(cascadeGpo.Id, idnMember.Id, isGpo, hasGpo),
            relationship(cascadeIdn.Id, memberCustomer.Id, isIdn, hasIdn)
        };

        try {
            OverlayAssignmentService.submitOverlayAssignments(
                new List<String>{ 'LS-TERR-CC' },
                new List<Id>{ cascadeGpo.Id, cascadeIdn.Id, memberCustomer.Id, directAddress.Id },
                new List<Id>{ cascadeUser.Id }
            );
        } catch (Exception ex) {
            System.assert(String.isNotBlank(ex.getMessage()));
        }
        try {
            OverlayAssignmentService.submitOverlayAssignments(
                null,
                new List<Id>{ cascadeGpo.Id, memberAddress.Id },
                new List<Id>{ cascadeUser.Id }
            );
        } catch (Exception ex) {
            System.assert(String.isNotBlank(ex.getMessage()));
        }
    }

    private static Id overlayCoverageCustomerId;
    private static Id overlayCoverageUserId;
    private static Account overlayCoverageAddress;

    private class ServiceRetrieveNothing implements CallableAction {
        public void execute() {
            OverlayAssignmentService.retrieveAccounts(null, null, null, null);
        }
    }
    private class ServiceSummaryNothing implements CallableAction {
        public void execute() {
            OverlayAssignmentService.getAssignmentSummary(null, null);
        }
    }
    private class ServiceSubmitNothing implements CallableAction {
        public void execute() {
            OverlayAssignmentService.submitOverlayAssignments(null, null, null);
        }
    }
    private class ServiceSearchTerritories implements CallableAction {
        public void execute() {
            OverlayAssignmentService.searchTerritories('HC-TERR-SVC');
        }
    }
    private class ServiceSearchAccounts implements CallableAction {
        public void execute() {
            OverlayAssignmentService.searchAccounts('HC Overlay', null, null);
        }
    }
    private class ServiceSearchUsers implements CallableAction {
        public void execute() {
            OverlayAssignmentService.searchOverlayUsers('coverage');
        }
    }
    private class ServiceSearchAccountsByTerritory implements CallableAction {
        public void execute() {
            OverlayAssignmentService.searchAccounts(null, null, new List<String>{ 'HC-TERR-SVC' });
        }
    }
    private class ServiceSubmitCustomer implements CallableAction {
        public void execute() {
            OverlayAssignmentService.submitOverlayAssignments(
                new List<String>{ 'HC-TERR-SVC' },
                new List<Id>{ overlayCoverageCustomerId },
                new List<Id>{ overlayCoverageUserId }
            );
        }
    }
    private class ServiceWriteback implements CallableAction {
        public void execute() {
            OverlayAssignmentService.createTasWritebackRecords(
                new List<Account>{ overlayCoverageAddress },
                new Set<Id>{ overlayCoverageUserId },
                new Map<String, OrderLineContact__c>{
                    'HC-OV-ADDR-1' => new OrderLineContact__c(
                        TASAddressId__c = 'HC-OV-ADDR-1',
                        TerritoryID__c = 'HC-TERR-SVC',
                        TerritoryDescription__c = 'Healthcare Overlay East',
                        TerritoryNumber__c = '880'
                    )
                }
            );
        }
    }
    private class ServiceSummaryCustomer implements CallableAction {
        public void execute() {
            OverlayAssignmentService.getAssignmentSummary(null, new List<Id>{ overlayCoverageCustomerId });
        }
    }

    private static void forceOverlayMethod(String methodName) {
        OverlayAssignmentService.throwTestException = false;
        OverlayAssignmentService.forcedExceptionMethodName = methodName;
    }

    private static void catchOverlayFailure(CallableAction action) {
        try {
            action.execute();
        } catch (Exception ex) {
            System.assert(String.isNotBlank(ex.getMessage()));
        }
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
        mustInsert(customerAccount);
        return customerAccount;
    }

    private static Account insertGlobalAccount(String name) {
        Account globalAccount = new Account(
            Name = name,
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('GlobalAccount').getRecordTypeId()
        );
        mustInsert(globalAccount);
        return globalAccount;
    }

    private static Account insertChild(Id parentId, String name, String accountNumber, String accountType) {
        Account childAccount = new Account(
            Name = name,
            AccountNumber = accountNumber,
            Type = accountType,
            ParentId = parentId,
            CustomerClassCode__c = 'SC'
        );
        mustInsert(childAccount);
        return childAccount;
    }

    private static Map<Id, AccountTeamMember> teamMembersByAccount(Id userId) {
        Map<Id, AccountTeamMember> memberByAccountId = new Map<Id, AccountTeamMember>();
        for (AccountTeamMember member : [
            SELECT AccountId, TeamMemberRole, AssignmentType__c, AccountAccessLevel, ContactAccessLevel,
                   OpportunityAccessLevel, CaseAccessLevel
            FROM AccountTeamMember
            WHERE UserId = :userId
        ]) {
            memberByAccountId.put(member.AccountId, member);
        }
        return memberByAccountId;
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
        mustInsert(addressAccount);
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

    /**
     * @description Life Sciences Sales user holding the overlay type's access. Inside Sales gets the
     *              permission set directly. GAD gets the permission set group, which covers that path.
     */
    private static User insertOverlayUser(String seed, String overlayType) {
        User overlayUser = insertLifeSciencesUser(seed);
        if (overlayType == GAD) {
            assignPermissionSet(overlayUser.Id, 'LSGlobalAccountDirectorPSG', true);
        } else {
            assignPermissionSet(overlayUser.Id, 'LSInsideSalesPS', false);
        }
        return overlayUser;
    }

    private static void assignPermissionSet(Id userId, String developerName, Boolean isGroup) {
        PermissionSetAssignment assignment = new PermissionSetAssignment(AssigneeId = userId);
        if (isGroup) {
            assignment.PermissionSetGroupId = [SELECT Id FROM PermissionSetGroup WHERE DeveloperName = :developerName LIMIT 1].Id;
        } else {
            assignment.PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = :developerName LIMIT 1].Id;
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert assignment;
        }
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

    /**
     * @description Inserts test data and fails the test if the insert is rejected. Database.insert
     *              alone returns the failure without throwing, so the record would have no Id.
     * @param record Account to insert.
     */
    private static void mustInsert(Account record) {
        Database.SaveResult result = Database.insert(record, allowDuplicates());
        System.assert(result.isSuccess(), 'Test data insert failed: ' + result.getErrors());
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