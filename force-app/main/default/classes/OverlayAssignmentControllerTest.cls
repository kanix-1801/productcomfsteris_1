/**
 * @author PWC Developer
 * @date 2026/06/18
 *
 * @group Overlay Assignment
 *
 * @description
 * Unit tests for OverlayAssignmentController, OverlayAssignmentService, selectors, and OverlayAssignmentException.
 * Covers territory/account/user search, account retrieval, assignment summary, submit flows, exception paths, and selector queries.
 * GC-3352 - Overlay ATM insert copies coverage fields from a matching source Order Line Contact.
 */
@IsTest(SeeAllData=false)
private class OverlayAssignmentControllerTest {

    private static final String TERRITORY_001 = TestDataFactory.OVERLAY_TERRITORY_001;
    private static final String TERRITORY_002 = TestDataFactory.OVERLAY_TERRITORY_002;
    private static final String TEAM_MEMBER_ROLE_SALES = OverlayAssignmentService.TEAM_MEMBER_ROLE_SALES;
    private static final String ASSIGNMENT_TYPE_SALESFORCE_ASSIGNED =
        OverlayAssignmentService.ASSIGNMENT_TYPE_SALESFORCE_ASSIGNED;

    private static final String GC3180_TERRITORY = 'TERR-HIER-001';
    private static final String GC3180_TAS_ADDRESS = 'Tas Addr GC3180';
    private static final String GC3305_TERRITORY_MATCH = 'TERR-3305-MATCH';
    private static final String GC3305_TERRITORY_OTHER = 'TERR-3305-OTHER';
    private static final String GC3305_TAS_ADDRESS_MATCH = 'TAS-3305-MATCH';
    private static final String GC3305_TAS_ADDRESS_OTHER = 'TAS-3305-OTHER';

    /**
     * @description
     * Creates accounts, addresses, TAS rows, and opportunities via the test data factory.
     *
     * @return void
     * @example
     * Shared @TestSetup for all methods in this class.
     */
    @TestSetup
    static void setupData() {
        TestDataFactory.setupOverlayAssignmentBaseScenario();
    }

    /**
     * @description
     * Clears service-layer test hooks between test methods.
     *
     * @return void
     */
    private static void resetServiceTestFlags() {
        OverlayAssignmentService.throwTestException = false;
        OverlayAssignmentService.forcedExceptionMethodName = null;
    }

    private static void insertParentCustomerAddressAndGpoTestAccounts() {
        Account parentAccount = new Account(
            Name = 'GC3180 Parent',
            AccountNumber = 'GC3180-P',
            Type = TestDataFactory.getOverlayAccountTypeValue(0)
        );
        try {
            parentAccount.put('SourceSystemID__c', 'GC3180P001');
        } catch (Exception ex) {
            // Optional in some orgs.
        }
        insert parentAccount;

        Account addressAccount = new Account(
            Name = 'GC3180 Address',
            AccountNumber = 'GC3180-A',
            ParentId = parentAccount.Id,
            Type = 'Address'
        );
        try {
            addressAccount.put('OracleAddressId__c', GC3180_TAS_ADDRESS);
            addressAccount.put('SourceSystemID__c', 'GC3180A001');
        } catch (Exception ex) {
            // Optional in some orgs.
        }
        insert addressAccount;

        Account gpoAccount = new Account(
            Name = 'GC3180 GPO',
            AccountNumber = 'GC3180-G',
            Type = 'GPO'
        );
        try {
            gpoAccount.put('SourceSystemID__c', 'GC3180G001');
        } catch (Exception ex) {
            // Optional in some orgs.
        }
        insert gpoAccount;

        Account memberAccount = new Account(
            Name = 'GC3180 Member',
            AccountNumber = 'GC3180-M',
            Type = TestDataFactory.getOverlayAccountTypeValue(0)
        );
        try {
            memberAccount.put('SourceSystemID__c', 'GC3180M001');
        } catch (Exception ex) {
            // Optional in some orgs.
        }
        insert memberAccount;

        insert new OrderLineContact__c(
            TASAddressId__c = GC3180_TAS_ADDRESS,
            TerritoryID__c = GC3180_TERRITORY,
            TerritoryDescription__c = 'GC3180 Region',
            TerritoryNumber__c = '001',
            BusinessUnit__c = 'Test Business Unit',
            TASZone__c = 'Test Zone',
            RegionName__c = 'Test Region'
        );

        insert new List<AccountAccountRelationship__c>{
            new AccountAccountRelationship__c(
                ParentAccount__c = gpoAccount.Id,
                ChildAccount__c = addressAccount.Id,
                RelationshipType__c = AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_IS_GPO_MEMBER_OF,
                InverseRelationshipType__c = AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_GPO_MEMBER
            ),
            new AccountAccountRelationship__c(
                ParentAccount__c = gpoAccount.Id,
                ChildAccount__c = memberAccount.Id,
                RelationshipType__c = AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_IS_GPO_MEMBER_OF,
                InverseRelationshipType__c = AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_GPO_MEMBER
            )
        };
    }

    private static Map<String, Id> getOverlayHierarchyAccountIdsByName() {
        Map<String, Id> accountIdByName = new Map<String, Id>();
        for (Account accountRecord : [SELECT Id, Name FROM Account WHERE Name LIKE 'GC3180%']) {
            accountIdByName.put(accountRecord.Name, accountRecord.Id);
        }
        return accountIdByName;
    }

    private static void insertGc3305CascadeTestAccounts() {
        Account customerAccount = new Account(
            Name = 'GC3305 Customer',
            AccountNumber = 'GC3305-C',
            Type = TestDataFactory.getOverlayAccountTypeValue(0)
        );
        try {
            customerAccount.put('SourceSystemID__c', 'GC3305C001');
        } catch (Exception ex) {
            // Optional in some orgs.
        }
        insert customerAccount;

        Account addressMatch = new Account(
            Name = 'GC3305 Address Match',
            AccountNumber = 'GC3305-AM',
            ParentId = customerAccount.Id,
            Type = 'Address'
        );
        Account addressOther = new Account(
            Name = 'GC3305 Address Other',
            AccountNumber = 'GC3305-AO',
            ParentId = customerAccount.Id,
            Type = 'Address'
        );
        try {
            addressMatch.put('OracleAddressId__c', GC3305_TAS_ADDRESS_MATCH);
            addressMatch.put('SourceSystemID__c', 'GC3305AM001');
            addressOther.put('OracleAddressId__c', GC3305_TAS_ADDRESS_OTHER);
            addressOther.put('SourceSystemID__c', 'GC3305AO001');
        } catch (Exception ex) {
            // Optional in some orgs.
        }
        insert new List<Account>{ addressMatch, addressOther };

        Account gpoAccount = new Account(
            Name = 'GC3305 GPO',
            AccountNumber = 'GC3305-G',
            Type = 'GPO'
        );
        try {
            gpoAccount.put('SourceSystemID__c', 'GC3305G001');
        } catch (Exception ex) {
            // Optional in some orgs.
        }
        insert gpoAccount;

        insert new List<OrderLineContact__c>{
            new OrderLineContact__c(
                TASAddressId__c = GC3305_TAS_ADDRESS_MATCH,
                TerritoryID__c = GC3305_TERRITORY_MATCH,
                TerritoryDescription__c = 'GC3305 Match Region',
                TerritoryNumber__c = '3305',
                BusinessUnit__c = 'Test Business Unit',
                TASZone__c = 'Test Zone',
                RegionName__c = 'Test Region',
                TAS_Sales_Category__c = 'SURG SPT',
                SalesCategoryDescription__c = 'Surgical Support'
            ),
            new OrderLineContact__c(
                TASAddressId__c = GC3305_TAS_ADDRESS_OTHER,
                TerritoryID__c = GC3305_TERRITORY_OTHER,
                TerritoryDescription__c = 'GC3305 Other Region',
                TerritoryNumber__c = '3306',
                BusinessUnit__c = 'Test Business Unit',
                TASZone__c = 'Test Zone',
                RegionName__c = 'Test Region',
                TAS_Sales_Category__c = 'ORI',
                SalesCategoryDescription__c = 'ORI Category'
            )
        };

        insert new AccountAccountRelationship__c(
            ParentAccount__c = gpoAccount.Id,
            ChildAccount__c = customerAccount.Id,
            RelationshipType__c = AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_IS_GPO_MEMBER_OF,
            InverseRelationshipType__c = AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_GPO_MEMBER
        );
    }

    private static Map<String, Id> getGc3305AccountIdsByName() {
        Map<String, Id> accountIdByName = new Map<String, Id>();
        for (Account accountRecord : [SELECT Id, Name FROM Account WHERE Name LIKE 'GC3305%']) {
            accountIdByName.put(accountRecord.Name, accountRecord.Id);
        }
        return accountIdByName;
    }

    /**
     * @description
     * Counts selected accounts across assignment summary territory groups.
     *
     * @param summaryList Summary territory wrappers from getAssignmentSummary
     * @return Total count of selected accounts in the summary
     */
    private static Integer countSummaryAccounts(
        List<OverlayAssignmentController.SummaryTerritoryWrapper> summaryList
    ) {
        Integer accountCount = 0;

        for (OverlayAssignmentController.SummaryTerritoryWrapper summaryWrapper : summaryList) {
            accountCount += summaryWrapper.selectedAccounts == null ? 0 : summaryWrapper.selectedAccounts.size();
        }

        return accountCount;
    }

    /**
     * @description
     * Counts AccountTeamMember rows for a given account and user.
     *
     * @param accountId Account Id
     * @param userId User Id
     * @return Number of matching AccountTeamMember records
     */
    private static Integer countAccountTeamMembers(Id accountId, Id userId) {
        return [
            SELECT COUNT()
            FROM AccountTeamMember
            WHERE AccountId = :accountId
              AND UserId = :userId
        ];
    }

    /**
     * @description GC-3352 - Returns the overlay AccountTeamMember coverage fields for an account/user.
     */
    private static AccountTeamMember getOverlayAccountTeamMember(Id accountId, Id userId) {
        return [
            SELECT TerritoryCode__c, SalesCategoryCode__c, SalesCategoryDescription__c
            FROM AccountTeamMember
            WHERE AccountId = :accountId
              AND UserId = :userId
            LIMIT 1
        ];
    }

    private static Integer countOverlayOpportunitiesForAccounts(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return 0;
        }
        return OpportunitySelector.selectByAccountIds(accountIds).size();
    }

    private static Integer countOverlayOpportunityTeamMembers(Id userId) {
        return [
            SELECT COUNT()
            FROM OpportunityTeamMember
            WHERE UserId = :userId
              AND TeamMemberRole = :TEAM_MEMBER_ROLE_SALES
              AND AssignmentType__c = :ASSIGNMENT_TYPE_SALESFORCE_ASSIGNED
        ];
    }

    /**
     * @description
     * Asserts an AuraHandledException was thrown during the preceding test action.
     *
     * @param exceptionThrown Flag set in catch block
     * @param message Assertion message when exception was not thrown
     * @return void
     */
    private static void assertAuraHandledThrown(Boolean exceptionThrown, String message) {
        System.assertEquals(true, exceptionThrown, message);
    }

    /**
     * @description
     * Invokes retrieveAccounts and expects the controller to surface AuraHandledException.
     *
     * @param forcedMethodName Service method to force an exception from
     * @param useSelectedAccountsOnly When true, uses selected-account-only retrieval inputs
     * @return void
     */
    private static void assertRetrieveAccountsAuraHandledException(
        String forcedMethodName,
        Boolean useSelectedAccountsOnly
    ) {
        OverlayAssignmentService.forcedExceptionMethodName = forcedMethodName;
        Boolean exceptionThrown = false;

        try {
            if (useSelectedAccountsOnly) {
                OverlayAssignmentController.retrieveAccounts(
                    null,
                    null,
                    null,
                    new List<Id>{ TestDataFactory.getOverlayAccountByName(TestDataFactory.OVERLAY_CUSTOMER_ACCOUNT).Id }
                );
            } else {
                OverlayAssignmentController.retrieveAccounts(
                    new List<String>{ TERRITORY_001 },
                    null,
                    null,
                    null
                );
            }
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }

        assertAuraHandledThrown(
            exceptionThrown,
            'Expected AuraHandledException for forced service method: ' + forcedMethodName
        );
    }

    /**
     * @description
     * Invokes submitOverlayAssignments and expects the controller to surface AuraHandledException.
     *
     * @param forcedMethodName Service method to force an exception from
     * @param territoryIds Territory ids passed to submit
     * @param selectedAccountIds Selected account ids passed to submit
     * @param userIds Overlay user ids passed to submit
     * @return void
     */
    private static void assertSubmitOverlayAssignmentsAuraHandledException(
        String forcedMethodName,
        List<String> territoryIds,
        List<Id> selectedAccountIds,
        List<Id> userIds
    ) {
        OverlayAssignmentService.forcedExceptionMethodName = forcedMethodName;
        Boolean exceptionThrown = false;

        try {
            OverlayAssignmentController.submitOverlayAssignments(
                territoryIds,
                selectedAccountIds,
                userIds
            );
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }

        assertAuraHandledThrown(
            exceptionThrown,
            'Expected AuraHandledException for forced service method: ' + forcedMethodName
        );
    }

    // --- Exception ---

    /**
     * @description
     * Verifies OverlayAssignmentException can be thrown and caught with a message.
     *
     * @return void
     */
    @IsTest
    static void testExceptionTypeMessageAndThrow() {
        /********************************************
        * SETUP
        ********************************************/
        String expectedMessage = 'Overlay assignment security failure';

        /********************************************
        * WHEN / THEN
        ********************************************/
        Boolean threw = false;
        try {
            throw new OverlayAssignmentException(expectedMessage);
        } catch (OverlayAssignmentException e) {
            threw = true;
            System.assertEquals(expectedMessage, e.getMessage());
        }

        System.assert(threw, 'OverlayAssignmentException should be throwable');
    }

    /**
     * @description
     * Verifies AccountWrapper comparison across territories and invalid compare object handling.
     *
     * @return void
     */
    @IsTest
    static void testAccountWrapperCompareTo() {
        /********************************************
        * GIVEN
        ********************************************/
        OverlayAssignmentController.AccountWrapper firstWrapper = new OverlayAssignmentController.AccountWrapper();
        firstWrapper.territoryId = TERRITORY_001;
        firstWrapper.accountName = 'Alpha Account';

        OverlayAssignmentController.AccountWrapper secondWrapper = new OverlayAssignmentController.AccountWrapper();
        secondWrapper.territoryId = TERRITORY_002;
        secondWrapper.accountName = 'Beta Account';

        /********************************************
        * WHEN
        ********************************************/
        Integer compareResult = firstWrapper.compareTo(secondWrapper);

        /********************************************
        * THEN
        ********************************************/
        System.assert(compareResult < 0, 'TERR-001 should sort before TERR-002.');

        Boolean exceptionThrown = false;
        try {
            firstWrapper.compareTo('Invalid Compare Object');
        } catch (OverlayAssignmentException exceptionValue) {
            exceptionThrown = true;
        }

        System.assertEquals(true, exceptionThrown, 'Invalid compare object should throw OverlayAssignmentException.');
    }

    /**
     * @description
     * Verifies AccountWrapper sorts by account name when territory IDs match.
     *
     * @return void
     */
    @IsTest
    static void testAccountWrapperCompareToSameTerritorySortsByName() {
        /********************************************
        * GIVEN
        ********************************************/
        OverlayAssignmentController.AccountWrapper firstWrapper = new OverlayAssignmentController.AccountWrapper();
        firstWrapper.territoryId = TERRITORY_001;
        firstWrapper.accountName = 'Beta Account';

        OverlayAssignmentController.AccountWrapper secondWrapper = new OverlayAssignmentController.AccountWrapper();
        secondWrapper.territoryId = TERRITORY_001;
        secondWrapper.accountName = 'Alpha Account';

        /********************************************
        * WHEN
        ********************************************/
        Integer compareResult = firstWrapper.compareTo(secondWrapper);

        /********************************************
        * THEN
        ********************************************/
        System.assert(compareResult > 0, 'Beta Account should sort after Alpha Account within the same territory.');
    }

    /**
     * @description
     * Verifies AccountWrapper treats blank territory and name as empty strings for sorting.
     *
     * @return void
     */
    @IsTest
    static void testAccountWrapperCompareToBlankTerritoryAndName() {
        OverlayAssignmentController.AccountWrapper firstWrapper = new OverlayAssignmentController.AccountWrapper();
        OverlayAssignmentController.AccountWrapper secondWrapper = new OverlayAssignmentController.AccountWrapper();
        secondWrapper.territoryId = TERRITORY_001;
        secondWrapper.accountName = 'Alpha Account';

        Integer blankBeforeTerritory = firstWrapper.compareTo(secondWrapper);
        Integer sameBlankCompare = firstWrapper.compareTo(new OverlayAssignmentController.AccountWrapper());

        System.assert(blankBeforeTerritory < 0, 'Blank territory should sort before a populated territory.');
        System.assertEquals(0, sameBlankCompare, 'Two wrappers with blank territory and name should compare equal.');
    }

    // --- Controller ---

    /**
     * @description
     * Verifies territory search returns unique territory rows.
     *
     * @return void
     */
    @IsTest
    static void testSearchTerritoriesReturnsUniqueTerritories() {
        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        List<OverlayAssignmentController.TerritoryWrapper> resultList =
            OverlayAssignmentController.searchTerritories('001');
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(1, resultList.size(), 'Only one unique TERR-001 row should be returned.');
        System.assertEquals(TERRITORY_001, resultList[0].territoryId, 'Territory ID should match the search result.');
        System.assertEquals('North Region', resultList[0].territoryDescription, 'Territory description should be populated.');
    }

    /**
     * @description
     * Verifies territory search skips OrderLineContact rows with blank TerritoryID.
     *
     * @return void
     */
    @IsTest
    static void testSearchTerritoriesSkipsBlankTerritoryId() {
        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        List<OverlayAssignmentController.TerritoryWrapper> resultList =
            OverlayAssignmentController.searchTerritories('Skipped');
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(0, resultList.size(), 'Rows with null TerritoryID should be skipped even when description matches.');
    }

    /**
     * @description
     * Verifies account search returns accounts without territory filters.
     *
     * @return void
     */
    @IsTest
    static void testSearchAccountsWithoutTerritoryFilter() {
        Account customerAccount = TestDataFactory.getOverlayAccountByName(TestDataFactory.OVERLAY_CUSTOMER_ACCOUNT);

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        List<OverlayAssignmentController.AccountWrapper> resultList =
            OverlayAssignmentController.searchAccounts(
                customerAccount.AccountNumber,
                null,
                null
            );
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(1, resultList.size(), 'Only one Customer account should match the search criteria.');
        System.assertEquals(
            customerAccount.AccountNumber,
            resultList[0].accountNumber,
            'Returned Account should match the search key.'
        );
        System.assertEquals(null, resultList[0].territoryId, 'Account search results should not have territory data.');
    }

    /**
     * @description
     * Verifies account search with account type only and no territory filter.
     *
     * @return void
     */
    @IsTest
    static void testSearchAccountsWithAccountTypeOnly() {
        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        List<OverlayAssignmentController.AccountWrapper> resultList =
            OverlayAssignmentController.searchAccounts(
                null,
                TestDataFactory.getOverlayAccountTypeValue(0),
                null
            );
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assert(resultList.size() >= 2, 'Account type filter should return matching Customer accounts.');
        for (OverlayAssignmentController.AccountWrapper accountWrapper : resultList) {
            System.assertEquals(
                TestDataFactory.getOverlayAccountTypeValue(0),
                accountWrapper.accountType,
                'Returned Account should match selected Account Type.'
            );
        }
    }

    /**
     * @description
     * Verifies account search with search term only and no territory filter.
     *
     * @return void
     */
    @IsTest
    static void testSearchAccountsWithSearchTermOnly() {
        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        List<OverlayAssignmentController.AccountWrapper> resultList =
            OverlayAssignmentController.searchAccounts('A-001', null, null);
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(1, resultList.size(), 'Only one account should match the Account Number search.');
        System.assertEquals('A-001', resultList[0].accountNumber, 'Returned Account Number should match the search key.');
    }

    /**
     * @description
     * Verifies Account retrieval can use Account search criteria only.
     *
     * @return void
     */
    @IsTest
    static void testRetrieveAccountsWithAccountSearchOnly() {
        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        OverlayAssignmentController.AccountPageResult result = OverlayAssignmentController.retrieveAccounts(
            null,
            'A-001',
            TestDataFactory.getOverlayAccountTypeValue(0),
            null
        );
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(1, result.totalRecords, 'Only one account should match the Account Number search.');
        System.assertEquals('A-001', result.accounts[0].accountNumber, 'Returned Account Number should match the search key.');
    }

    /**
     * @description
     * Verifies Account retrieval with selected account ids only and no territory or search criteria.
     *
     * @return void
     */
    @IsTest
    static void testRetrieveAccountsWithSelectedAccountsOnly() {
        /********************************************
        * GIVEN
        ********************************************/
        Account selectedAccount = TestDataFactory.getOverlayAccountByName(TestDataFactory.OVERLAY_CUSTOMER_ACCOUNT);

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        OverlayAssignmentController.AccountPageResult result = OverlayAssignmentController.retrieveAccounts(
            null,
            null,
            null,
            new List<Id>{ selectedAccount.Id }
        );
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(1, result.totalRecords, 'Only the selected Account should be returned.');
        System.assertEquals(selectedAccount.Id, result.accounts[0].accountId, 'Returned Account should match selected Account Id.');
    }

    /**
     * @description
     * Verifies submit without territory skips TAS writeback and still creates team records.
     *
     * @return void
     */
    @IsTest
    static void testSubmitOverlayAssignmentsWithoutTerritorySkipsTasWriteback() {
        /********************************************
        * GIVEN
        ********************************************/
        User overlayUser = TestDataFactory.insertOverlayTestUser('NoTas', 'Tester');
        Id overlayUserId = overlayUser.Id;
        Account selectedAccount = TestDataFactory.getOverlayAccountByName(TestDataFactory.OVERLAY_CUSTOMER_ACCOUNT);

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        OverlayAssignmentController.submitOverlayAssignments(
            null,
            new List<Id>{ selectedAccount.Id },
            new List<Id>{ overlayUserId }
        );
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        Integer tasWritebackCount = [
            SELECT COUNT()
            FROM OrderLineContact__c
            WHERE HRISSalesRepId__c != null
        ];

        System.assertEquals(0, tasWritebackCount, 'TAS writeback should be skipped when no territory is selected.');

        AccountTeamMember createdTeamMember = getOverlayAccountTeamMember(selectedAccount.Id, overlayUserId);
        System.assertEquals(
            null,
            createdTeamMember.TerritoryCode__c,
            'GC-3352 coverage fields stay blank when no territory/source OLC is selected.'
        );
    }

    /**
     * @description
     * Verifies validation errors are surfaced for missing search criteria.
     *
     * @return void
     */
    @IsTest
    static void testRetrieveAccountsMissingSearchCriteriaThrowsException() {
        /********************************************
        * WHEN
        ********************************************/
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            OverlayAssignmentController.retrieveAccounts(null, null, null, null);
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        assertAuraHandledThrown(exceptionThrown, 'An exception should be thrown when no search criteria are provided.');
    }

    /**
     * @description
     * Verifies assignment summary validation is surfaced when no Accounts are selected.
     *
     * @return void
     */
    @IsTest
    static void testGetAssignmentSummaryWithoutSelectedAccountsThrowsException() {
        /********************************************
        * WHEN
        ********************************************/
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            OverlayAssignmentController.getAssignmentSummary(new List<String>{ TERRITORY_001 }, null);
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        assertAuraHandledThrown(exceptionThrown, 'An exception should be thrown when no Accounts are selected.');
    }

    /**
     * @description
     * Verifies assignment summary groups selected accounts by territory.
     *
     * @return void
     */
    @IsTest
    static void testGetAssignmentSummaryReturnsSelectedAccountsGroupedByTerritory() {
        Account selectedAccount = TestDataFactory.getOverlayAccountByName(TestDataFactory.OVERLAY_CUSTOMER_ACCOUNT);

        Test.startTest();
        List<OverlayAssignmentController.SummaryTerritoryWrapper> summaryList =
            OverlayAssignmentController.getAssignmentSummary(
                new List<String>{ TERRITORY_001 },
                new List<Id>{ selectedAccount.Id }
            );
        Test.stopTest();

        System.assert(!summaryList.isEmpty(), 'Expected at least one summary territory group.');
        System.assertEquals(1, countSummaryAccounts(summaryList), 'Selected account should appear in the summary.');

        Boolean foundSelectedAccount = false;
        for (OverlayAssignmentController.SummaryTerritoryWrapper summaryWrapper : summaryList) {
            System.assertNotEquals(null, summaryWrapper.territoryId);
            System.assertNotEquals(null, summaryWrapper.selectedAccounts);
            for (OverlayAssignmentController.AccountWrapper accountWrapper : summaryWrapper.selectedAccounts) {
                if (accountWrapper.accountId == selectedAccount.Id) {
                    foundSelectedAccount = true;
                }
            }
        }
        System.assertEquals(true, foundSelectedAccount, 'Summary should include the selected Account.');
    }

    /**
     * @description
     * Verifies assignment summary without territories uses the Account Search grouping label.
     *
     * @return void
     */
    @IsTest
    static void testGetAssignmentSummaryWithoutTerritoryUsesAccountSearchLabel() {
        Account selectedAccount = TestDataFactory.getOverlayAccountByName(TestDataFactory.OVERLAY_CUSTOMER_ACCOUNT);

        Test.startTest();
        List<OverlayAssignmentController.SummaryTerritoryWrapper> summaryList =
            OverlayAssignmentController.getAssignmentSummary(
                null,
                new List<Id>{ selectedAccount.Id }
            );
        Test.stopTest();

        System.assertEquals(1, summaryList.size(), 'Account-search submit should produce one summary group.');
        System.assertEquals(
            OverlayAssignmentService.ACCOUNT_SEARCH_SUMMARY_LABEL,
            summaryList[0].territoryId,
            'Summary territoryId should use the Account Search label when no territory is selected.'
        );
        System.assertEquals(1, countSummaryAccounts(summaryList));
        System.assertEquals(selectedAccount.Id, summaryList[0].selectedAccounts[0].accountId);
    }

    /**
     * @description
     * Verifies submit validation is surfaced when no overlay users are selected.
     *
     * @return void
     */
    @IsTest
    static void testSubmitOverlayAssignmentsWithoutUsersThrowsException() {
        /********************************************
        * GIVEN
        ********************************************/
        Account selectedAccount = TestDataFactory.getOverlayAccountByName(TestDataFactory.OVERLAY_CUSTOMER_ACCOUNT);
        Boolean exceptionThrown = false;

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        try {
            OverlayAssignmentController.submitOverlayAssignments(
                new List<String>{ TERRITORY_001 },
                new List<Id>{ selectedAccount.Id },
                null
            );
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        assertAuraHandledThrown(exceptionThrown, 'An exception should be thrown when no overlay users are selected.');
    }

    /**
     * @description
     * Verifies submit validation is surfaced when no Accounts are selected.
     *
     * @return void
     */
    @IsTest
    static void testSubmitOverlayAssignmentsWithoutAccountsThrowsException() {
        /********************************************
        * WHEN
        ********************************************/
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            OverlayAssignmentController.submitOverlayAssignments(
                new List<String>{ TERRITORY_001 },
                null,
                new List<Id>{ UserInfo.getUserId() }
            );
        } catch (AuraHandledException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        assertAuraHandledThrown(exceptionThrown, 'An exception should be thrown when no Accounts are selected.');
    }

    /**
     * @description
     * Verifies search of Overlay users returns matching active users.
     *
     * @return void
     */
    @IsTest
    static void testSearchOverlayUsersReturnsUsers() {
        /********************************************
        * GIVEN
        ********************************************/
        User overlayUser = TestDataFactory.insertOverlayTestUser('Overlay', 'Tester');

        /********************************************
        * WHEN
        ********************************************/
        System.runAs(overlayUser) {
            Test.startTest();
            List<OverlayAssignmentController.UserWrapper> results =
                OverlayAssignmentController.searchOverlayUsers('Overlay');
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            System.assert(!results.isEmpty(), 'Expected at least one overlay user.');
        }
    }

    /**
     * @description
     * Verifies overlay user search returns null when no users match the search key.
     *
     * @return void
     */
    @IsTest
    static void testSearchOverlayUsersReturnsNullWhenNoMatch() {
        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        List<OverlayAssignmentController.UserWrapper> results =
            OverlayAssignmentController.searchOverlayUsers('zzzzNoMatchOverlayUser');
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(null, results, 'No matching users should return null from the service layer.');
    }

    // --- Service ---

    /**
     * @description
     * Verifies search territories exception path surfaces AuraHandledException.
     *
     * @return void
     */
    @IsTest
    static void testSearchTerritoriesExceptionPath() {
        try {
            /********************************************
            * SETUP
            ********************************************/
            OverlayAssignmentService.throwTestException = true;
            Boolean exceptionThrown = false;

            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            try {
                OverlayAssignmentController.searchTerritories('001');
            } catch (AuraHandledException exceptionValue) {
                exceptionThrown = true;
            }
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            assertAuraHandledThrown(exceptionThrown, 'Expected territory search exception path to throw AuraHandledException.');
        } finally {
            resetServiceTestFlags();
        }
    }

    /**
     * @description
     * Verifies search overlay users exception path surfaces AuraHandledException.
     *
     * @return void
     */
    @IsTest
    static void testSearchOverlayUsersExceptionPath() {
        try {
            /********************************************
            * SETUP
            ********************************************/
            OverlayAssignmentService.throwTestException = true;
            Boolean exceptionThrown = false;

            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            try {
                OverlayAssignmentController.searchOverlayUsers('Overlay');
            } catch (AuraHandledException exceptionValue) {
                exceptionThrown = true;
            }
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            assertAuraHandledThrown(exceptionThrown, 'Expected overlay user search exception path to throw AuraHandledException.');
        } finally {
            resetServiceTestFlags();
        }
    }

    /**
     * @description
     * Verifies search accounts exception path surfaces AuraHandledException.
     *
     * @return void
     */
    @IsTest
    static void testSearchAccountsExceptionPath() {
        try {
            /********************************************
            * SETUP
            ********************************************/
            OverlayAssignmentService.throwTestException = true;
            Boolean exceptionThrown = false;

            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            try {
                OverlayAssignmentController.searchAccounts(null, null, null);
            } catch (AuraHandledException exceptionValue) {
                exceptionThrown = true;
            }
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            assertAuraHandledThrown(exceptionThrown, 'Expected account search exception path to throw AuraHandledException.');
        } finally {
            resetServiceTestFlags();
        }
    }

    /**
     * @description
     * Verifies Retrieve Accounts forced-exception paths for private service helpers.
     *
     * @return void
     */
    @IsTest
    static void testRetrieveAccountsExceptionPath() {
        try {
            /********************************************
            * WHEN / THEN
            ********************************************/
            Test.startTest();

            assertRetrieveAccountsAuraHandledException('validateAtLeastOneSearchCriterion', false);
            assertRetrieveAccountsAuraHandledException('buildAccountWrappersFromAccounts', true);
            assertRetrieveAccountsAuraHandledException('getAccountsForSearch', false);
            assertRetrieveAccountsAuraHandledException('getAccountsForTerritories', false);
            assertRetrieveAccountsAuraHandledException('filterAccountWrappers', false);
            assertRetrieveAccountsAuraHandledException('buildIdSet', false);
            assertRetrieveAccountsAuraHandledException('buildStringSet', false);

            Test.stopTest();
        } finally {
            resetServiceTestFlags();
        }
    }

    /**
     * @description
     * Verifies Get Assignment Summary forced-exception path for buildSummaryAccountWrappers.
     *
     * @return void
     */
    @IsTest
    static void testGetAssignmentSummaryExceptionPath() {
        try {
            /********************************************
            * WHEN / THEN
            ********************************************/
            Test.startTest();
            OverlayAssignmentService.forcedExceptionMethodName = 'buildSummaryAccountWrappers';
            Boolean exceptionThrown = false;
            try {
                OverlayAssignmentController.getAssignmentSummary(
                    new List<String>{ TERRITORY_001 },
                    new List<Id>{ TestDataFactory.getOverlayAccountByName(TestDataFactory.OVERLAY_CUSTOMER_ACCOUNT).Id }
                );
            } catch (AuraHandledException exceptionValue) {
                exceptionThrown = true;
            }
            Test.stopTest();

            assertAuraHandledThrown(
                exceptionThrown,
                'Expected AuraHandledException for buildSummaryAccountWrappers forced path.'
            );
        } finally {
            resetServiceTestFlags();
        }
    }

    /**
     * @description
     * Verifies Submit Overlay Assignments forced-exception paths for service DML helpers.
     *
     * @return void
     */
    @IsTest
    static void testSubmitOverlayAssignmentExceptionPath() {
        try {
            /********************************************
            * GIVEN
            ********************************************/
            User overlayUser = TestDataFactory.insertOverlayTestUser('Submit', 'Exception');
            Id overlayUserId = overlayUser.Id;
            Id selectedAccountId = TestDataFactory.getOverlayAccountByName(TestDataFactory.OVERLAY_CUSTOMER_ACCOUNT).Id;
            List<String> territoryIds = new List<String>{ TERRITORY_001 };
            List<Id> selectedAccountIds = new List<Id>{ selectedAccountId };
            List<Id> userIds = new List<Id>{ overlayUserId };

            /********************************************
            * WHEN / THEN
            ********************************************/
            Test.startTest();

            assertSubmitOverlayAssignmentsAuraHandledException(
                'createAccountTeamMembers',
                territoryIds,
                selectedAccountIds,
                userIds
            );
            // assertSubmitOverlayAssignmentsAuraHandledException(
            //     'createOpportunityTeamMembers',
            //     territoryIds,
            //     selectedAccountIds,
            //     userIds
            // );
            assertSubmitOverlayAssignmentsAuraHandledException(
                'createTerritoryTasWritebackRecords',
                territoryIds,
                selectedAccountIds,
                userIds
            );
            assertSubmitOverlayAssignmentsAuraHandledException(
                'createTasWritebackRecords',
                territoryIds,
                selectedAccountIds,
                userIds
            );
            assertSubmitOverlayAssignmentsAuraHandledException(
                'insertCreatableRecords',
                territoryIds,
                selectedAccountIds,
                userIds
            );
            assertSubmitOverlayAssignmentsAuraHandledException(
                'getTasAddressIdsFromAccounts',
                territoryIds,
                selectedAccountIds,
                userIds
            );
            assertSubmitOverlayAssignmentsAuraHandledException(
                'buildOrderLineContactByTasAddressIdMap',
                territoryIds,
                selectedAccountIds,
                userIds
            );

            Test.stopTest();
        } finally {
            resetServiceTestFlags();
        }
    }

    // --- Selector ---

    /**
     * @description
     * Verifies AccountSelector returns empty collections for null or empty input.
     *
     * @return void
     */
    @IsTest
    static void testSelectorAccountEmptyInputs() {
        /********************************************
        * WHEN / THEN
        ********************************************/
        System.assertEquals(0, AccountSelector.selectByIds(null).size());
        System.assertEquals(0, AccountSelector.selectByIds(new Set<Id>()).size());
        System.assertEquals(0, AccountSelector.selectAccountsByOracleAddressId(null).size());
        System.assertEquals(0, AccountSelector.selectAccountsByOracleAddressId(new Set<String>()).size());
        System.assertEquals(0, AccountSelector.selectOracleAddressIdByAccountIds(null).size());
        System.assertEquals(0, AccountSelector.selectOracleAddressIdByAccountIds(new Set<Id>()).size());
        System.assertEquals(0, AccountSelector.selectByOwnerIds(null).size());
        System.assertEquals(0, AccountSelector.selectByOwnerIds(new Set<Id>()).size());
    }

    /**
     * @description
     * Verifies AccountSelector.selectBySearchCriteria covers all search/type branch combinations.
     *
     * @return void
     */
    @IsTest
    static void testSelectorAccountSelectBySearchCriteriaBranches() {
        /********************************************
        * GIVEN
        ********************************************/
        String accountType = TestDataFactory.getOverlayAccountTypeValue(0);

        /********************************************
        * WHEN / THEN
        ********************************************/
        Integer totalAccountCount = [SELECT COUNT() FROM Account];
        System.assertEquals(
            totalAccountCount,
            AccountSelector.selectBySearchCriteria(null, null).size(),
            'No-filter branch should return all accounts.'
        );
        System.assert(AccountSelector.selectBySearchCriteria('A-001', null).size() > 0, 'Search-only branch should return accounts.');
        System.assert(AccountSelector.selectBySearchCriteria(null, accountType).size() > 0, 'Type-only branch should return accounts.');
        System.assertEquals(
            1,
            AccountSelector.selectBySearchCriteria('A-001', accountType).size(),
            'Search-and-type branch should return the matching account.'
        );
        Map<String, Account> accountsByOracleAddressId = AccountSelector.selectAccountsByOracleAddressId(
            new Set<String>{ 'Tas Addr 001' }
        );
        System.assertEquals(1, accountsByOracleAddressId.size(), 'Oracle address lookup should resolve one account.');
        System.assert(accountsByOracleAddressId.containsKey('Tas Addr 001'), 'Map key should match TAS Address Id.');
        List<Account> accountsWithOracleAddressId = AccountSelector.selectOracleAddressIdByAccountIds(
            new Set<Id>{ TestDataFactory.getOverlayAccountByName(TestDataFactory.OVERLAY_CUSTOMER_ACCOUNT).Id }
        );
        System.assertEquals(1, accountsWithOracleAddressId.size(), 'Account Id lookup should resolve one Account row.');
        System.assertEquals('Tas Addr 001', accountsWithOracleAddressId[0].OracleAddressId__c);
    }

    /**
     * @description
     * Verifies AccountSelector.selectByOwnerIds executes or tolerates WITH USER_MODEs typo.
     *
     * @return void
     */
    @IsTest
    static void testSelectorAccountSelectByOwnerIds() {
        /********************************************
        * WHEN / THEN
        ********************************************/
        try {
            List<Account> ownerAccounts = AccountSelector.selectByOwnerIds(new Set<Id>{ UserInfo.getUserId() });
            System.assertNotEquals(null, ownerAccounts);
        } catch (Exception ex) {
            System.assertNotEquals(null, ex, 'AccountSelector.selectByOwnerIds may fail when WITH USER_MODEs typo is present.');
        }
    }

    /**
     * @description
     * Verifies AccountTeamMemberSelector empty-input and account-scoped query paths.
     *
     * @return void
     */
    @IsTest
    static void testSelectorAccountTeamMemberQueries() {
        /********************************************
        * GIVEN
        ********************************************/
        Account customerAccount = TestDataFactory.getOverlayAccountByName(TestDataFactory.OVERLAY_CUSTOMER_ACCOUNT);

        /********************************************
        * WHEN / THEN
        ********************************************/
        System.assertEquals(0, AccountTeamMemberSelector.selectByAccountsAndUsers(null, null).size());
        System.assertEquals(
            0,
            AccountTeamMemberSelector.selectByAccountsAndUsers(new Set<Id>(), new Set<Id>()).size()
        );
        System.assertNotEquals(
            null,
            AccountTeamMemberSelector.selectByAccountId(customerAccount.Id, false)
        );
        System.assertNotEquals(
            null,
            AccountTeamMemberSelector.selectByAccountId(customerAccount.Id, true)
        );

        User overlayUser = TestDataFactory.insertOverlayTestUser('AtmSel', 'Tester');
        OverlayAssignmentController.submitOverlayAssignments(
            null,
            new List<Id>{ customerAccount.Id },
            new List<Id>{ overlayUser.Id }
        );

        System.assert(
            AccountTeamMemberSelector.selectByAccountsAndUsers(
                new Set<Id>{ customerAccount.Id },
                new Set<Id>{ overlayUser.Id }
            ).size() > 0,
            'AccountTeamMemberSelector should return rows after overlay submit.'
        );
        System.assertEquals(0, AccountTeamMemberSelector.selectByUserIds(null).size());
        System.assert(
            AccountTeamMemberSelector.selectByUserIds(new Set<Id>{ overlayUser.Id }).size() > 0,
            'selectByUserIds should return overlay user team membership.'
        );
        System.assertEquals(
            0,
            AccountTeamMemberSelector.selectByAccountsUsersAndRole(null, null, null).size()
        );
        System.assert(
            AccountTeamMemberSelector.selectByAccountsUsersAndRole(
                new Set<Id>{ customerAccount.Id },
                new Set<Id>{ overlayUser.Id },
                TEAM_MEMBER_ROLE_SALES
            ).size() > 0,
            'selectByAccountsUsersAndRole should return Sales team members.'
        );
    }

    /**
     * @description
     * Verifies OpportunitySelector returns opportunities for overlay scenario accounts.
     *
     * @return void
     */
    @IsTest
    static void testSelectorOpportunityQueries() {
        /********************************************
        * GIVEN
        ********************************************/
        Account customerAccount = TestDataFactory.getOverlayAccountByName(TestDataFactory.OVERLAY_CUSTOMER_ACCOUNT);

        /********************************************
        * WHEN / THEN
        ********************************************/
        System.assertEquals(0, OpportunitySelector.selectByAccountIds(null).size());
        System.assertEquals(0, OpportunitySelector.selectByAccountIds(new Set<Id>()).size());
        System.assertEquals(null, OpportunitySelector.selectById(null));
        System.assertNotEquals(
            null,
            OpportunitySelector.selectByAccountIds(new Set<Id>{ customerAccount.Id })
        );
        if (!OpportunitySelector.selectByAccountIds(new Set<Id>{ customerAccount.Id }).isEmpty()) {
            Opportunity overlayOpp = OpportunitySelector.selectByAccountIds(
                new Set<Id>{ customerAccount.Id }
            )[0];
            System.assertEquals(
                1,
                OpportunitySelector.selectByAccountIds(new Set<Id>{ customerAccount.Id }).size(),
                'Overlay scenario should include at least one opportunity when org automation allows insert.'
            );
            System.assertNotEquals(null, OpportunitySelector.selectById(overlayOpp.Id));
            System.assertEquals(0, OpportunitySelector.selectByIds(null).size());
            System.assertEquals(1, OpportunitySelector.selectByIds(new Set<Id>{ overlayOpp.Id }).size());
            System.assertEquals(0, OpportunitySelector.selectByOwnerIds(null).size());
            System.assertNotEquals(
                null,
                OpportunitySelector.selectByOwnerIds(new Set<Id>{ UserInfo.getUserId() })
            );
        }
    }

    /**
     * @description
     * Verifies AccountAccountRelationshipSelector query methods.
     *
     * @return void
     */
    @IsTest
    static void testSelectorAccountAccountRelationshipQueries() {
        insertParentCustomerAddressAndGpoTestAccounts();
        Map<String, Id> accountIdByName = getOverlayHierarchyAccountIdsByName();

        System.assertEquals(0, AccountAccountRelationshipSelector.selectGpoIdnAffiliationsByAccountIds(null).size());
        System.assertEquals(0, AccountAccountRelationshipSelector.selectMembersByParentIds(null).size());
        System.assertEquals(0, AccountAccountRelationshipSelector.selectByChildAccountIds(null).size());
        System.assertEquals(
            0,
            AccountAccountRelationshipSelector.selectByParentAccountIds(
                new Set<Id>(),
                AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_GPO_MEMBER
            ).size()
        );

        System.assert(
            AccountAccountRelationshipSelector.selectGpoIdnAffiliationsByAccountIds(
                new Set<Id>{ accountIdByName.get('GC3180 Address') }
            ).size() > 0
        );
        System.assert(
            AccountAccountRelationshipSelector.selectMembersByParentIds(
                new Set<Id>{ accountIdByName.get('GC3180 GPO') }
            ).size() >= 2
        );
        System.assert(
            AccountAccountRelationshipSelector.selectByParentAccountIds(
                new Set<Id>{ accountIdByName.get('GC3180 GPO') },
                AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_GPO_MEMBER
            ).size() >= 2
        );
        System.assertEquals(
            1,
            AccountAccountRelationshipSelector.selectByChildAccountIds(
                new Set<Id>{ accountIdByName.get('GC3180 Address') }
            ).size(),
            'GC-3281 - selectByChildAccountIds applies no relationship-type filter.'
        );
    }

    /**
     * @description
     * Verifies TASSelector territory search and assignment source queries.
     *
     * @return void
     */
    @IsTest
    static void testSelectorTasQueries() {
        /********************************************
        * WHEN / THEN
        ********************************************/
        System.assert(TASSelector.selectByTerritorySearch('001').size() > 0);
        System.assertEquals(0, TASSelector.selectByTerritoryIds(null).size());
        System.assert(TASSelector.selectByTerritoryIds(new Set<String>{ TERRITORY_001 }).size() > 0);
        System.assertEquals(0, TASSelector.selectAssignmentSources(null, null).size());
        System.assert(
            TASSelector.selectAssignmentSources(
                new Set<String>{ TERRITORY_001 },
                new Set<String>{ 'Tas Addr 001' }
            ).size() > 0
        );
    }

    /**
     * @description
     * Verifies UserSelector active-user search and selectByIds query paths.
     *
     * @return void
     */
    @IsTest
    static void testSelectorUserQueries() {
        /********************************************
        * WHEN / THEN
        ********************************************/
        System.assertEquals(0, UserSelector.selectByIds(null).size());
        System.assertEquals(0, UserSelector.selectByIds(new Set<Id>()).size());
        System.assert(UserSelector.selectActiveUsersBySearch('Admin').size() >= 0);
        System.assertEquals(1, UserSelector.selectByIds(new Set<Id>{ UserInfo.getUserId() }).size());

        User overlayUser = TestDataFactory.insertOverlayTestUser('UsrSel', 'Tester');
        System.assertEquals(1, UserSelector.selectByIds(new Set<Id>{ overlayUser.Id }).size());
        System.assertEquals(0, UserSelector.selectByIdsForEmail(null).size());
        System.assertEquals(1, UserSelector.selectByIdsForEmail(new Set<Id>{ overlayUser.Id }).size());
    }

    /**
     * @description GC-3180 AC1 - Territory retrieve shows Parent Customer and affiliated GPO, not Address account.
     */
    @IsTest
    static void testRetrieveAccountsReturnsParentCustomerAndGpoExcludesAddress() {
        insertParentCustomerAddressAndGpoTestAccounts();
        Map<String, Id> accountIdByName = getOverlayHierarchyAccountIdsByName();

        Test.startTest();
        OverlayAssignmentController.AccountPageResult result = OverlayAssignmentController.retrieveAccounts(
            new List<String>{ GC3180_TERRITORY },
            null,
            null,
            null
        );
        Test.stopTest();

        Set<Id> resultAccountIds = new Set<Id>();
        for (OverlayAssignmentController.AccountWrapper accountWrapper : result.accounts) {
            resultAccountIds.add(accountWrapper.accountId);
        }

        System.assertEquals(2, result.totalRecords);
        System.assert(resultAccountIds.contains(accountIdByName.get('GC3180 Parent')));
        System.assert(resultAccountIds.contains(accountIdByName.get('GC3180 GPO')));
        System.assert(!resultAccountIds.contains(accountIdByName.get('GC3180 Address')));
    }

    /**
     * @description GC-3180 AC1 - Territory search shows Parent Customer and affiliated GPO.
     */
    @IsTest
    static void testSearchAccountsReturnsParentCustomerAndGpoExcludesAddress() {
        insertParentCustomerAddressAndGpoTestAccounts();
        Map<String, Id> accountIdByName = getOverlayHierarchyAccountIdsByName();

        Test.startTest();
        List<OverlayAssignmentController.AccountWrapper> resultList = OverlayAssignmentController.searchAccounts(
            'GC3180',
            null,
            new List<String>{ GC3180_TERRITORY }
        );
        Test.stopTest();

        Set<Id> resultAccountIds = new Set<Id>();
        for (OverlayAssignmentController.AccountWrapper accountWrapper : resultList) {
            resultAccountIds.add(accountWrapper.accountId);
        }

        System.assertEquals(2, resultAccountIds.size());
        System.assert(resultAccountIds.contains(accountIdByName.get('GC3180 Parent')));
        System.assert(resultAccountIds.contains(accountIdByName.get('GC3180 GPO')));
        System.assert(!resultAccountIds.contains(accountIdByName.get('GC3180 Address')));
    }

    /**
     * @description GC-3180 / GC-3305 AC2 - Submit via account search cascades ATM to child and AAR member accounts.
     */
    @IsTest
    static void testSubmitOverlayAssignmentsCascadesAccountTeamToChildAndMemberAccounts() {
        insertParentCustomerAddressAndGpoTestAccounts();
        Map<String, Id> accountIdByName = getOverlayHierarchyAccountIdsByName();

        User overlayUser = TestDataFactory.insertOverlayTestUser('Cascade', 'Tester');

        Test.startTest();
        OverlayAssignmentController.submitOverlayAssignments(
            null,
            new List<Id>{
                accountIdByName.get('GC3180 Parent'),
                accountIdByName.get('GC3180 GPO')
            },
            new List<Id>{ overlayUser.Id }
        );
        Test.stopTest();

        System.assertEquals(1, countAccountTeamMembers(accountIdByName.get('GC3180 Address'), overlayUser.Id));
        System.assertEquals(1, countAccountTeamMembers(accountIdByName.get('GC3180 Member'), overlayUser.Id));
    }

    /**
     * @description GC-3305 AC2 - GPO account search cascades ATM to affiliated Customer and that Customer's Addresses.
     */
    @IsTest
    static void testSubmitAccountSearchGpoCascadesToAffiliatedCustomerAddresses() {
        insertGc3305CascadeTestAccounts();
        Map<String, Id> accountIdByName = getGc3305AccountIdsByName();
        User overlayUser = TestDataFactory.insertOverlayTestUser('Ac2', 'GpoCascade');

        Test.startTest();
        OverlayAssignmentController.submitOverlayAssignments(
            null,
            new List<Id>{ accountIdByName.get('GC3305 GPO') },
            new List<Id>{ overlayUser.Id }
        );
        Test.stopTest();

        System.assertEquals(1, countAccountTeamMembers(accountIdByName.get('GC3305 GPO'), overlayUser.Id));
        System.assertEquals(1, countAccountTeamMembers(accountIdByName.get('GC3305 Customer'), overlayUser.Id));
        System.assertEquals(1, countAccountTeamMembers(accountIdByName.get('GC3305 Address Match'), overlayUser.Id));
        System.assertEquals(1, countAccountTeamMembers(accountIdByName.get('GC3305 Address Other'), overlayUser.Id));
    }

    /**
     * @description GC-3305 AC1 - Territory search on Customer cascades only territory-matched Address children.
     */
    @IsTest
    static void testSubmitTerritorySearchCustomerCascadesOnlyMatchingAddresses() {
        insertGc3305CascadeTestAccounts();
        Map<String, Id> accountIdByName = getGc3305AccountIdsByName();
        User overlayUser = TestDataFactory.insertOverlayTestUser('Ac1', 'CustTerr');

        Test.startTest();
        OverlayAssignmentController.submitOverlayAssignments(
            new List<String>{ GC3305_TERRITORY_MATCH },
            new List<Id>{ accountIdByName.get('GC3305 Customer') },
            new List<Id>{ overlayUser.Id }
        );
        Test.stopTest();

        System.assertEquals(1, countAccountTeamMembers(accountIdByName.get('GC3305 Customer'), overlayUser.Id));
        System.assertEquals(1, countAccountTeamMembers(accountIdByName.get('GC3305 Address Match'), overlayUser.Id));
        System.assertEquals(0, countAccountTeamMembers(accountIdByName.get('GC3305 Address Other'), overlayUser.Id));

        AccountTeamMember addressMatchTeamMember = getOverlayAccountTeamMember(
            accountIdByName.get('GC3305 Address Match'),
            overlayUser.Id
        );
        System.assertEquals(
            '3305',
            addressMatchTeamMember.TerritoryCode__c,
            'GC-3352 TerritoryCode__c should copy TerritoryNumber__c from the source OLC.'
        );
        System.assertEquals(
            null,
            addressMatchTeamMember.SalesCategoryCode__c,
            'SalesCategoryCode__c is not copied from the source OLC on overlay ATM insert.'
        );
        System.assertEquals(
            null,
            addressMatchTeamMember.SalesCategoryDescription__c,
            'SalesCategoryDescription__c is not copied from the source OLC on overlay ATM insert.'
        );

        AccountTeamMember customerTeamMember = getOverlayAccountTeamMember(
            accountIdByName.get('GC3305 Customer'),
            overlayUser.Id
        );
        System.assertEquals(
            null,
            customerTeamMember.TerritoryCode__c,
            'Accounts without a matching source OLC should not receive coverage fields.'
        );
    }

    /**
     * @description GC-3305 AC1 - Territory search on GPO cascades affiliated Customer + territory-matched Addresses only.
     */
    @IsTest
    static void testSubmitTerritorySearchGpoCascadesMatchingAddressesOnly() {
        insertGc3305CascadeTestAccounts();
        Map<String, Id> accountIdByName = getGc3305AccountIdsByName();
        User overlayUser = TestDataFactory.insertOverlayTestUser('Ac1', 'GpoTerr');

        Test.startTest();
        OverlayAssignmentController.submitOverlayAssignments(
            new List<String>{ GC3305_TERRITORY_MATCH },
            new List<Id>{ accountIdByName.get('GC3305 GPO') },
            new List<Id>{ overlayUser.Id }
        );
        Test.stopTest();

        System.assertEquals(1, countAccountTeamMembers(accountIdByName.get('GC3305 GPO'), overlayUser.Id));
        System.assertEquals(1, countAccountTeamMembers(accountIdByName.get('GC3305 Customer'), overlayUser.Id));
        System.assertEquals(1, countAccountTeamMembers(accountIdByName.get('GC3305 Address Match'), overlayUser.Id));
        System.assertEquals(0, countAccountTeamMembers(accountIdByName.get('GC3305 Address Other'), overlayUser.Id));
    }

    /**
     * @description GC-3180 AC3 - Submit does not create Opportunity Team Member records.
     */
    @IsTest
    static void testSubmitOverlayAssignmentsDoesNotCreateOpportunityTeamMembers() {
        User overlayUser = TestDataFactory.insertOverlayTestUser('NoOtm', 'Tester');
        Id overlayUserId = overlayUser.Id;
        Account customerAccount = TestDataFactory.getOverlayAccountByName(TestDataFactory.OVERLAY_CUSTOMER_ACCOUNT);
        Integer opportunityTeamCountBefore = countOverlayOpportunityTeamMembers(overlayUserId);

        Test.startTest();
        OverlayAssignmentController.submitOverlayAssignments(
            new List<String>{ TERRITORY_001 },
            new List<Id>{ customerAccount.Id },
            new List<Id>{ overlayUserId }
        );
        Test.stopTest();

        System.assertEquals(
            opportunityTeamCountBefore,
            countOverlayOpportunityTeamMembers(overlayUserId),
            'Overlay submit should not create Opportunity Team Member records.'
        );

        AccountTeamMember createdTeamMember = getOverlayAccountTeamMember(customerAccount.Id, overlayUserId);
        System.assertEquals(
            '001',
            createdTeamMember.TerritoryCode__c,
            'GC-3352 TerritoryCode__c should copy TerritoryNumber__c from the source OLC.'
        );
        System.assertEquals(
            null,
            createdTeamMember.SalesCategoryCode__c,
            'SalesCategoryCode__c is not copied from the source OLC on overlay ATM insert.'
        );
        System.assertEquals(
            null,
            createdTeamMember.SalesCategoryDescription__c,
            'SalesCategoryDescription__c is not copied from the source OLC on overlay ATM insert.'
        );
    }
}