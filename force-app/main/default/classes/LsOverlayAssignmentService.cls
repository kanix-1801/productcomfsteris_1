/**
 * @author PWC Developer
 * @date 2026/11/04
 *
 * @group Life Sciences Overlay Assignment
 *
 * @description
 * GCL-79 - Service layer for Life Sciences Overlay Assignment across Accounts, Users, and TAS territory records.
 * GCL-79 - Territory and account search stay scoped to Life Sciences (BusinessUnit__c = Life Sciences
 * or ClassCode__c in SC / Life Science / Life Sciences). Overlay users are limited to the Life Sciences Sales profile.
 * GCL-79 - Step 1 and Step 2 show Customer accounts. GPO, IDN, and Address are not searched or shown.
 * Submit adds the overlay user to the selected Customer and to that account's child accounts.
 * When a territory is selected, TerritoryCode__c is copied from the TAS territory number and a TAS row is inserted. IDN is skipped.
 * GCL-79 - Submit also creates an AccountShare for each assigned account. Opportunity and Case
 * access on the Account Team row stay None. No Opportunity Team row is created.
 */
public without sharing class LsOverlayAssignmentService {
    /** @description GCL-79 - Account Team Member.AssignmentType__c value for this wizard. */
    public static final String ASSIGNMENT_TYPE_SALESFORCE_ASSIGNED = 'Salesforce Assigned';

    /** @description GCL-79 - Account Team Member.TeamMemberRole value created by this wizard. */
    public static final String TEAM_MEMBER_ROLE_SALES = 'Sales';

    /** @description GCL-79 - OrderLineContact__c.BusinessUnit__c value used to scope territory search. */
    public static final String BUSINESS_UNIT_LIFE_SCIENCES = 'Life Sciences';

    /** @description GCL-79 - Account access level granted to overlay users. Only Account access is extended. */
    public static final String ACCOUNT_ACCESS_EDIT = 'Edit';

    /** @description GCL-79 - Opportunity/Case access level for overlay rows. No access beyond Account is granted. */
    public static final String NO_ACCESS = 'None';

    /** @description GCL-79 - Account type the Life Sciences wizard searches and displays. GPO, IDN, and Address are excluded. */
    private static final String ACCOUNT_TYPE_CUSTOMER = 'Customer';
    private static final String ACCOUNT_TYPE_GPO = 'GPO';
    private static final String ACCOUNT_TYPE_ADDRESS = 'Address';
    private static final String ACCOUNT_TYPE_IDN = 'IDN';
    private static final Set<String> SEARCHABLE_ACCOUNT_TYPES = new Set<String>{
        ACCOUNT_TYPE_CUSTOMER
    };

    /** @description GCL-79 - Summary row label used when selected accounts came from Account Search, not a Territory. */
    public static final String ACCOUNT_SEARCH_LABEL = 'Account Search';

    /** @description GCL-79 - Row cap applied to search and retrieval queries. */
    private static final Integer SEARCH_LIMIT = 200;

    /** @description GCL-79 - Row cap applied to the overlay user search query. */
    private static final Integer USER_SEARCH_LIMIT = 50;

    /** @description GCL-79 - Logger scenario used for every error/warning raised by this class. */
    private static final String SCENARIO = 'Life Sciences Overlay Assignment';

    /** @description GCL-79 - Logger tag used for every error/warning raised by this class. */
    private static final String LOGGER_TAG = 'LsOverlayAssignment';

    /**
     * @description GCL-79 - OrderLineContact__c.ClassCode__c and Account.CustomerClassCode__c values that
     *              identify Life Sciences data. SOQL string comparisons are case-insensitive, so
     *              this single Set is safe to reuse as a bind variable for both fields.
     */
    private static final Set<String> LIFE_SCIENCES_CLASS_CODES = new Set<String>{
        'SC',
        'LIFE SCIENCE',
        'LIFE SCIENCES'
    };

    /**
     * @description
     * GCL-79 - Searches Life Sciences OrderLineContact__c territory rows by Territory ID,
     * Territory Description, or Territory Number.
     *
     * @param searchKey User-entered search text. Returns an empty list when blank.
     * @return Distinct Life Sciences territories matching the search key.
     */
    public static List<LsOverlayAssignmentController.TerritoryWrapper> searchTerritories(String searchKey) {
        try {
            if (String.isBlank(searchKey)) {
                return new List<LsOverlayAssignmentController.TerritoryWrapper>();
            }

            String key = '%' + searchKey.trim() + '%';
            Map<String, LsOverlayAssignmentController.TerritoryWrapper> territoryById =
                new Map<String, LsOverlayAssignmentController.TerritoryWrapper>();

            for (OrderLineContact__c orderLineContact : [
                SELECT TerritoryID__c, TerritoryDescription__c
                FROM OrderLineContact__c
                WHERE TerritoryID__c != null
                AND (
                    TerritoryID__c LIKE :key
                    OR TerritoryDescription__c LIKE :key
                    OR TerritoryNumber__c LIKE :key
                )
                AND (
                    BusinessUnit__c = :BUSINESS_UNIT_LIFE_SCIENCES
                    OR ClassCode__c IN :LIFE_SCIENCES_CLASS_CODES
                )
                WITH USER_MODE
                LIMIT :SEARCH_LIMIT
            ]) {
                if (territoryById.containsKey(orderLineContact.TerritoryID__c)) {
                    continue;
                }
                LsOverlayAssignmentController.TerritoryWrapper territory =
                    new LsOverlayAssignmentController.TerritoryWrapper();
                territory.territoryId = orderLineContact.TerritoryID__c;
                territory.territoryDescription = orderLineContact.TerritoryDescription__c;
                territoryById.put(territory.territoryId, territory);
            }
            return territoryById.values();
        } catch (Exception ex) {
            throw logAndWrap('Unable to search Life Sciences territories.', ex);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description
     * GCL-79 - Searches Life Sciences Customer accounts on Step 1 by Account Name/Number
     * and/or Account Type, optionally scoped to already-selected territories. GPO, IDN, and Address
     * are not searched. Any single field, or any combination of the supported fields, is a valid search.
     *
     * @param accountSearchKey Account Name or Account Number text.
     * @param accountType Selected Account Type, or blank for any type.
     * @param territoryIds Territory IDs already selected on Step 1, or empty for none.
     * @return Matching Life Sciences account rows. Empty when no search criteria is provided.
     */
    public static List<LsOverlayAssignmentController.AccountWrapper> searchAccounts(
        String accountSearchKey,
        String accountType,
        List<String> territoryIds
    ) {
        try {
            Boolean hasAnyCriteria = String.isNotBlank(accountSearchKey)
                || String.isNotBlank(accountType)
                || (territoryIds != null && !territoryIds.isEmpty());

            if (!hasAnyCriteria) {
                return new List<LsOverlayAssignmentController.AccountWrapper>();
            }
            return findAccountRows(accountSearchKey, accountType, territoryIds, null);
        } catch (Exception ex) {
            throw logAndWrap('Unable to search Life Sciences accounts.', ex);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description
     * GCL-79 - Retrieves the Customer accounts tied to the selected territories
     * and/or account search criteria, for display and default selection on Step 2.
     * GPO, IDN, and Address accounts stay off this screen.
     *
     * @param territoryIds Selected Territory IDs, or empty for an account-only search.
     * @param accountSearchKey Account Name or Account Number text from Step 1.
     * @param accountType Selected Account Type from Step 1.
     * @param selectedSearchAccountIds Account Ids explicitly selected on Step 1's account search results.
     * @return Customer account rows for Step 2.
     */
    public static List<LsOverlayAssignmentController.AccountWrapper> retrieveAccounts(
        List<String> territoryIds,
        String accountSearchKey,
        String accountType,
        List<Id> selectedSearchAccountIds
    ) {
        try {
            Boolean hasTerritory = territoryIds != null && !territoryIds.isEmpty();
            Boolean hasAccountFilter = String.isNotBlank(accountSearchKey)
                || String.isNotBlank(accountType)
                || (selectedSearchAccountIds != null && !selectedSearchAccountIds.isEmpty());

            if (!hasTerritory && !hasAccountFilter) {
                throw new LsOverlayAssignmentException('Enter a territory or account before retrieving accounts.');
            }

            return findAccountRows(accountSearchKey, accountType, territoryIds, selectedSearchAccountIds);
        } catch (LsOverlayAssignmentException ex) {
            throw ex;
        } catch (Exception ex) {
            throw logAndWrap('Unable to retrieve Life Sciences accounts.', ex);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description
     * GCL-79 - Searches active Life Sciences Sales profile users by name or email
     * for the overlay user selection step. Returns Name, Country, and Manager
     * in addition to Email and Role. This query does not use USER_MODE: the BSA
     * persona cannot read User.ProfileId, and stripping that field breaks the bind variables.
     *
     * @param searchKey User-entered search text. Returns an empty list when blank.
     * @return Matching active Life Sciences Sales users.
     */
    public static List<LsOverlayAssignmentController.UserWrapper> searchOverlayUsers(String searchKey) {
        try {
            if (String.isBlank(searchKey)) {
                return new List<LsOverlayAssignmentController.UserWrapper>();
            }

            Id lifeSciencesProfileId = UserSelector.getLifeSciencesSalesProfileId();
            if (lifeSciencesProfileId == null) {
                throw new LsOverlayAssignmentException('Life Sciences Sales profile was not found.');
            }

            String key = '%' + searchKey.trim() + '%';
            List<LsOverlayAssignmentController.UserWrapper> users = new List<LsOverlayAssignmentController.UserWrapper>();

            for (User userRecord : [
                SELECT Id, Name, Email, Country, UserRole.Name, Manager.Name
                FROM User
                WHERE IsActive = true
                AND ProfileId = :lifeSciencesProfileId
                AND (Name LIKE :key OR Email LIKE :key)
                LIMIT :USER_SEARCH_LIMIT
            ]) {
                LsOverlayAssignmentController.UserWrapper userWrapper = new LsOverlayAssignmentController.UserWrapper();
                userWrapper.userId = userRecord.Id;
                userWrapper.userName = userRecord.Name;
                userWrapper.email = userRecord.Email;
                userWrapper.country = userRecord.Country;
                userWrapper.role = userRecord.UserRole == null ? null : userRecord.UserRole.Name;
                userWrapper.managerName = userRecord.Manager == null ? null : userRecord.Manager.Name;
                users.add(userWrapper);
            }
            return users;
        } catch (LsOverlayAssignmentException ex) {
            throw ex;
        } catch (Exception ex) {
            throw logAndWrap('Unable to search Life Sciences overlay users.', ex);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description
     * GCL-79 - Builds the confirmation summary grouped by Territory (or by Account
     * Search when no territory was used), for the final review step.
     *
     * @param territoryIds Selected Territory IDs.
     * @param selectedAccountIds Accounts still selected after Step 2 deselection.
     * @return One summary row per territory (or Account Search) with its selected accounts.
     */
    public static List<LsOverlayAssignmentController.SummaryTerritoryWrapper> getAssignmentSummary(
        List<String> territoryIds,
        List<Id> selectedAccountIds
    ) {
        try {
            Set<Id> selectedAccountIdSet = toIdSet(selectedAccountIds);
            if (selectedAccountIdSet.isEmpty()) {
                throw new LsOverlayAssignmentException('No accounts selected for overlay assignment.');
            }

            List<LsOverlayAssignmentController.AccountWrapper> selectedRows = selectSummaryAccountRows(
                territoryIds,
                selectedAccountIdSet
            );
            return groupAccountRowsByTerritory(selectedRows);
        } catch (LsOverlayAssignmentException ex) {
            throw ex;
        } catch (Exception ex) {
            throw logAndWrap('Unable to build the Life Sciences overlay assignment summary.', ex);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description
     * GCL-79 - Creates additive Account Team Member rows for every selected
     * account and overlay user combination that does not already exist.
     * TeamMemberRole is Sales and AssignmentType__c defaults to Salesforce Assigned.
     * Only Account access is extended on the Account Team row: AccountAccessLevel is Edit, and
     * OpportunityAccessLevel / CaseAccessLevel are explicitly None. An AccountShare is created
     * for each assigned account. When a territory is selected, a TAS OrderLineContact__c row
     * is inserted for each Address Account that matches that territory.
     *
     * @param territoryIds Selected Territory IDs. When present, child accounts must match a
     *                     territory TAS address, and TerritoryCode__c is copied from that territory.
     * @param selectedAccountIds Customer accounts still selected after Step 2 deselection.
     * @param userIds Overlay users selected on Step 3.
     */
    public static void submitOverlayAssignments(
        List<String> territoryIds,
        List<Id> selectedAccountIds,
        List<Id> userIds
    ) {
        Set<Id> accountIdSet = toIdSet(selectedAccountIds);
        Set<Id> userIdSet = toIdSet(userIds);

        if (accountIdSet.isEmpty()) {
            throw new LsOverlayAssignmentException('No accounts selected for overlay assignment.');
        }
        if (userIdSet.isEmpty()) {
            throw new LsOverlayAssignmentException('Select at least one overlay user.');
        }
        requireActiveLifeSciencesUsers(userIdSet);

        Savepoint savepointValue = Database.setSavepoint();
        try {
            Set<String> territoryIdSet = toStringSet(territoryIds);
            Map<String, OrderLineContact__c> territoryByAddressId = loadLifeSciencesTerritories(territoryIdSet);
            Set<Id> cascadeAccountIds = resolveCascadeAccountIds(
                accountIdSet,
                territoryIdSet,
                territoryByAddressId.keySet()
            );
            List<Account> cascadeAccounts = queryAccountsByIds(cascadeAccountIds);
            List<AccountTeamMember> membersToInsert = buildNewAccountTeamMembers(
                cascadeAccounts,
                userIdSet,
                territoryIdSet.isEmpty() ? new Map<String, OrderLineContact__c>() : territoryByAddressId
            );

            if (!membersToInsert.isEmpty()) {
                SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, membersToInsert);
                insert decision.getRecords();
            }
            createAccountShares(cascadeAccounts, userIdSet);
            if (!territoryIdSet.isEmpty()) {
                createTasWritebackRecords(cascadeAccounts, userIdSet, territoryByAddressId);
            }
        } catch (LsOverlayAssignmentException ex) {
            Database.rollback(savepointValue);
            throw ex;
        } catch (Exception ex) {
            Database.rollback(savepointValue);
            throw logAndWrap('Unable to submit Life Sciences overlay assignments.', ex);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description
     * GCL-79 - Creates a manual AccountShare for each assigned account and overlay user that
     * does not already have one. Access matches Healthcare: Account Edit, Opportunity Read, Case Read.
     *
     * @param accountList Accounts receiving the overlay assignment.
     * @param userIdSet Overlay users selected on Step 3.
     */
    private static void createAccountShares(List<Account> accountList, Set<Id> userIdSet) {
        Set<Id> accountIdSet = new Map<Id, Account>(accountList).keySet();
        if (accountIdSet.isEmpty() || userIdSet.isEmpty()) {
            return;
        }

        Set<String> existingShareKeys = new Set<String>();
        for (AccountShare accountShare : [
            SELECT AccountId, UserOrGroupId
            FROM AccountShare
            WHERE AccountId IN :accountIdSet
            AND UserOrGroupId IN :userIdSet
        ]) {
            existingShareKeys.add(accountShare.AccountId + '-' + accountShare.UserOrGroupId);
        }

        List<AccountShare> sharesToInsert = new List<AccountShare>();
        for (Id accountId : accountIdSet) {
            for (Id userId : userIdSet) {
                if (existingShareKeys.contains(accountId + '-' + userId)) {
                    continue;
                }
                sharesToInsert.add(new AccountShare(
                    AccountId = accountId,
                    UserOrGroupId = userId,
                    AccountAccessLevel = ACCOUNT_ACCESS_EDIT,
                    OpportunityAccessLevel = 'Read',
                    CaseAccessLevel = 'Read',
                    RowCause = Schema.AccountShare.RowCause.Manual
                ));
            }
        }
        if (!sharesToInsert.isEmpty()) {
            if (!Schema.sObjectType.AccountShare.isCreateable()) {
                throw new LsOverlayAssignmentException('You do not have permission to share these accounts.');
            }
            insert sharesToInsert;
        }
    }

    /**
     * @description
     * GCL-79 - Inserts one OrderLineContact__c TAS row per overlay user for each assigned
     * account whose Oracle address matches a selected Life Sciences territory. Called only
     * when a territory was selected.
     *
     * @param accountList Accounts receiving the overlay assignment.
     * @param userIdSet Overlay users selected on Step 3.
     * @param territoryByAddressId Life Sciences source rows keyed by TAS Address Id.
     */
    private static void createTasWritebackRecords(
        List<Account> accountList,
        Set<Id> userIdSet,
        Map<String, OrderLineContact__c> territoryByAddressId
    ) {
        if (accountList.isEmpty() || userIdSet.isEmpty() || territoryByAddressId.isEmpty()) {
            return;
        }

        Map<Id, User> userById = new Map<Id, User>(UserSelector.selectByIds(userIdSet));
        List<OrderLineContact__c> rowsToInsert = new List<OrderLineContact__c>();
        for (Account accountRecord : accountList) {
            OrderLineContact__c sourceTerritory = territoryForAccount(accountRecord, territoryByAddressId);
            if (sourceTerritory == null) {
                continue;
            }
            for (Id userId : userIdSet) {
                User overlayUser = userById.get(userId);
                if (overlayUser == null) {
                    continue;
                }
                rowsToInsert.add(new OrderLineContact__c(
                    TerritoryID__c = sourceTerritory.TerritoryID__c,
                    TerritoryDescription__c = sourceTerritory.TerritoryDescription__c,
                    TerritoryNumber__c = sourceTerritory.TerritoryNumber__c,
                    TASAddressId__c = sourceTerritory.TASAddressId__c,
                    BusinessUnit__c = sourceTerritory.BusinessUnit__c,
                    TASZone__c = sourceTerritory.TASZone__c,
                    RegionName__c = sourceTerritory.RegionName__c,
                    HRISSalesRepId__c = overlayUser.EmployeeNumber__c
                ));
            }
        }
        if (!rowsToInsert.isEmpty()) {
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, rowsToInsert);
            insert decision.getRecords();
        }
    }

    /**
     * @description GCL-79 - Logs an unexpected exception and returns a sanitized exception to throw to the caller.
     * @param userMessage User-safe message to log and surface to the LWC.
     * @param ex The exception caught by the calling method.
     * @return LsOverlayAssignmentException carrying the sanitized message.
     */
    private static LsOverlayAssignmentException logAndWrap(String userMessage, Exception ex) {
        Logger.setScenario(SCENARIO);
        Logger.error(userMessage + ' ' + ex.getMessage(), ex).addTag(LOGGER_TAG);
        return new LsOverlayAssignmentException(userMessage);
    }

    /**
     * @description
     * GCL-79 - Shared account lookup used by searchAccounts and retrieveAccounts. When one or
     * more territories are selected, Address accounts are resolved through the matching
     * Life Sciences OrderLineContact__c rows, and the screen shows the Customer parent.
     * An account-only search queries Customer accounts directly. GPO, IDN, and Address are never returned.
     *
     * @param accountSearchKey Account Name or Account Number text.
     * @param accountType Selected Account Type, or blank for Customer.
     * @param territoryIds Selected Territory IDs, or empty for an account-only search.
     * @param selectedSearchAccountIds Account Ids explicitly selected on Step 1's account search results.
     * @return Customer account rows matching the combined search criteria.
     */
    private static List<LsOverlayAssignmentController.AccountWrapper> findAccountRows(
        String accountSearchKey,
        String accountType,
        List<String> territoryIds,
        List<Id> selectedSearchAccountIds
    ) {
        Set<String> territoryIdSet = toStringSet(territoryIds);
        Map<String, OrderLineContact__c> territoryByAddressId = loadLifeSciencesTerritories(territoryIdSet);
        Set<Id> selectedAccountIds = toIdSet(selectedSearchAccountIds);
        Map<Id, OrderLineContact__c> territoryByDisplayAccountId = new Map<Id, OrderLineContact__c>();

        List<Account> matchedAccounts = territoryByAddressId.isEmpty()
            ? queryLifeSciencesAccounts(accountSearchKey, accountType, selectedAccountIds)
            : queryDisplayAccountsForTerritories(territoryByAddressId, territoryByDisplayAccountId);

        if (!territoryByAddressId.isEmpty() && !selectedAccountIds.isEmpty()) {
            matchedAccounts = keepSelectedAccounts(matchedAccounts, selectedAccountIds);
        }

        List<LsOverlayAssignmentController.AccountWrapper> rows =
            new List<LsOverlayAssignmentController.AccountWrapper>();

        for (Account accountRecord : matchedAccounts) {
            if (!isSearchableAccountType(accountRecord.Type)) {
                continue;
            }

            LsOverlayAssignmentController.AccountWrapper row = toAccountWrapper(
                accountRecord,
                territoryByDisplayAccountId.get(accountRecord.Id)
            );
            if (matchesSearch(row, accountSearchKey, accountType)) {
                rows.add(row);
            }
        }
        return rows;
    }

    /**
     * @description GCL-79 - True for Customer. GPO, IDN, and Address are not searchable in this wizard.
     * @param accountType Account.Type value.
     * @return True when the type can be shown on Step 1 and Step 2.
     */
    private static Boolean isSearchableAccountType(String accountType) {
        return SEARCHABLE_ACCOUNT_TYPES.contains(accountType);
    }

    /**
     * @description GCL-79 - Loads Life Sciences OrderLineContact__c rows for the given territories,
     *              keyed by TAS Address Id. First row per address wins when duplicates exist.
     * @param territoryIds Territory IDs to resolve.
     * @return Map of TAS Address Id to its Life Sciences source territory row.
     */
    private static Map<String, OrderLineContact__c> loadLifeSciencesTerritories(Set<String> territoryIds) {
        Map<String, OrderLineContact__c> territoryByAddressId = new Map<String, OrderLineContact__c>();
        if (territoryIds.isEmpty()) {
            return territoryByAddressId;
        }

        for (OrderLineContact__c orderLineContact : [
            SELECT TerritoryID__c, TerritoryDescription__c, TerritoryNumber__c, TASAddressId__c,
                   TAS_Sales_Category__c, SalesCategoryDescription__c,
                   BusinessUnit__c, TASZone__c, RegionName__c
            FROM OrderLineContact__c
            WHERE TerritoryID__c IN :territoryIds
            AND TASAddressId__c != null
            AND (
                BusinessUnit__c = :BUSINESS_UNIT_LIFE_SCIENCES
                OR ClassCode__c IN :LIFE_SCIENCES_CLASS_CODES
            )
            WITH USER_MODE
        ]) {
            String addressKey = orderLineContact.TASAddressId__c.trim();
            if (!territoryByAddressId.containsKey(addressKey)) {
                territoryByAddressId.put(addressKey, orderLineContact);
            }
        }
        return territoryByAddressId;
    }

    /**
     * @description GCL-79 - Loads Accounts whose OracleAddressId__c matches a selected territory's TAS Address Id.
     * @param oracleAddressIds TAS Address Ids collected from the selected territories.
     * @return Accounts matching one of the given Oracle Address Ids.
     */
    private static List<Account> queryAccountsByOracleAddress(Set<String> oracleAddressIds) {
        if (oracleAddressIds.isEmpty()) {
            return new List<Account>();
        }
        return [
            SELECT Id, Name, AccountNumber, Type, ParentId, Parent.Name, OracleAddressId__c,
                   BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry
            FROM Account
            WHERE OracleAddressId__c IN :oracleAddressIds
            WITH USER_MODE
            LIMIT :SEARCH_LIMIT
        ];
    }

    /**
     * @description
     * GCL-79 - Resolves Customer accounts for an account-only search. Customer rows
     * must carry a Life Sciences class code. GPO, IDN, and Address are not returned.
     * Explicit Step 1 selections take priority.
     *
     * @param accountSearchKey Account Name or Account Number text.
     * @param accountType Selected Account Type. Only Customer is searched.
     * @param selectedAccountIds Account Ids explicitly selected on Step 1's account search results.
     * @return Matching Customer accounts.
     */
    private static List<Account> queryLifeSciencesAccounts(
        String accountSearchKey,
        String accountType,
        Set<Id> selectedAccountIds
    ) {
        if (!selectedAccountIds.isEmpty()) {
            return keepSearchableAccounts(queryAccountsByIds(selectedAccountIds));
        }
        if (String.isNotBlank(accountType) && !isSearchableAccountType(accountType)) {
            return new List<Account>();
        }

        String searchTerm = String.isBlank(accountSearchKey)
            ? null
            : '%' + accountSearchKey.trim() + '%';
        Boolean hasSearchTerm = String.isNotBlank(accountSearchKey);
        Boolean hasType = String.isNotBlank(accountType);
        if (!hasSearchTerm && !hasType) {
            return new List<Account>();
        }

        if (hasType && accountType != ACCOUNT_TYPE_CUSTOMER) {
            return new List<Account>();
        }
        return hasSearchTerm
            ? queryCustomersByName(searchTerm)
            : queryCustomers();
    }

    /**
     * @description GCL-79 - Customer accounts with a Life Sciences class code whose name or number matches.
     * @param searchTerm Bound LIKE term.
     * @return Matching Customer accounts.
     */
    private static List<Account> queryCustomersByName(String searchTerm) {
        return [
            SELECT Id, Name, AccountNumber, Type, ParentId, Parent.Name, OracleAddressId__c,
                   BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry
            FROM Account
            WHERE Type = :ACCOUNT_TYPE_CUSTOMER
            AND CustomerClassCode__c IN :LIFE_SCIENCES_CLASS_CODES
            AND (Name LIKE :searchTerm OR AccountNumber LIKE :searchTerm)
            WITH USER_MODE
            ORDER BY Name
            LIMIT :SEARCH_LIMIT
        ];
    }

    /**
     * @description GCL-79 - Customer accounts with a Life Sciences class code.
     * @return Customer accounts.
     */
    private static List<Account> queryCustomers() {
        return [
            SELECT Id, Name, AccountNumber, Type, ParentId, Parent.Name, OracleAddressId__c,
                   BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry
            FROM Account
            WHERE Type = :ACCOUNT_TYPE_CUSTOMER
            AND CustomerClassCode__c IN :LIFE_SCIENCES_CLASS_CODES
            WITH USER_MODE
            ORDER BY Name
            LIMIT :SEARCH_LIMIT
        ];
    }

    /**
     * @description GCL-79 - Loads Accounts by Id, used when the caller already has specific account selections.
     * @param accountIds Account Ids to load.
     * @return Accounts matching the given Ids.
     */
    private static List<Account> queryAccountsByIds(Set<Id> accountIds) {
        if (accountIds.isEmpty()) {
            return new List<Account>();
        }
        return [
            SELECT Id, Name, AccountNumber, Type, ParentId, Parent.Name, OracleAddressId__c,
                   BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry
            FROM Account
            WHERE Id IN :accountIds
            WITH USER_MODE
        ];
    }

    /**
     * @description GCL-79 - Drops GPO, IDN, Address, and any other type that this wizard does not search.
     * @param accounts Accounts to filter.
     * @return Customer accounts only.
     */
    private static List<Account> keepSearchableAccounts(List<Account> accounts) {
        List<Account> searchable = new List<Account>();
        for (Account accountRecord : accounts) {
            if (isSearchableAccountType(accountRecord.Type)) {
                searchable.add(accountRecord);
            }
        }
        return searchable;
    }

    /**
     * @description GCL-79 - Keeps display accounts the user explicitly selected on Step 1.
     * @param accounts Customer accounts matched by the territory search.
     * @param selectedAccountIds Account Ids explicitly selected on Step 1.
     * @return Filtered account list.
     */
    private static List<Account> keepSelectedAccounts(List<Account> accounts, Set<Id> selectedAccountIds) {
        List<Account> restricted = new List<Account>();
        for (Account accountRecord : accounts) {
            if (selectedAccountIds.contains(accountRecord.Id)) {
                restricted.add(accountRecord);
            }
        }
        return restricted;
    }

    /**
     * @description
     * GCL-79 - Finds the Address Account behind each territory TAS address and returns the
     * Customer parent for the screen. GPO, IDN, and the Address account itself are not returned.
     *
     * @param territoryByAddressId Life Sciences territories keyed by TAS Address Id.
     * @param territoryByDisplayAccountId Output map of displayed Account Id to its territory row.
     * @return Customer accounts to show for the selected territories.
     */
    private static List<Account> queryDisplayAccountsForTerritories(
        Map<String, OrderLineContact__c> territoryByAddressId,
        Map<Id, OrderLineContact__c> territoryByDisplayAccountId
    ) {
        List<Account> addressAccounts = queryAccountsByOracleAddress(territoryByAddressId.keySet());
        Set<Id> parentIds = new Set<Id>();
        for (Account addressAccount : addressAccounts) {
            if (addressAccount.ParentId != null) {
                parentIds.add(addressAccount.ParentId);
            }
        }

        Map<Id, Account> displayById = new Map<Id, Account>();
        for (Account parentAccount : queryAccountsByIds(parentIds)) {
            if (!isSearchableAccountType(parentAccount.Type)) {
                continue;
            }
            displayById.put(parentAccount.Id, parentAccount);
            if (territoryByDisplayAccountId.containsKey(parentAccount.Id)) {
                continue;
            }
            for (Account addressAccount : addressAccounts) {
                if (addressAccount.ParentId != parentAccount.Id) {
                    continue;
                }
                OrderLineContact__c territory = territoryForAccount(addressAccount, territoryByAddressId);
                if (territory != null) {
                    territoryByDisplayAccountId.put(parentAccount.Id, territory);
                    break;
                }
            }
        }

        return displayById.values();
    }

    /**
     * @description GCL-79 - True when the relationship is a GPO membership. IDN relationships are excluded.
     * @param affiliation Account-to-account relationship to test.
     * @return True for a GPO member relationship.
     */
    private static Boolean isGpoRelationship(AccountAccountRelationship__c affiliation) {
        return isGpoRelationshipLabel(affiliation.RelationshipType__c);
    }

    /**
     * @description GCL-79 - True for a GPO membership label. IDN labels return false.
     * @param relationshipType Relationship label from either side of the affiliation.
     * @return True when the label is a GPO member label.
     */
    private static Boolean isGpoRelationshipLabel(String relationshipType) {
        return relationshipType == AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_GPO_MEMBER
            || relationshipType == AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_IS_GPO_MEMBER_OF;
    }

    /**
     * @description
     * GCL-79 - Accounts that receive the overlay user. The selected Customer or GPO is included.
     * A Customer also contributes its child accounts. A GPO also contributes its member accounts,
     * and those member Customers contribute their children. IDN is never included. When a
     * territory is selected, a child or GPO member Address is included only when its Oracle
     * address matches that territory.
     *
     * @param selectedAccountIds Customer or GPO accounts selected on Step 2.
     * @param territoryIdSet Selected Territory IDs. Empty for an account-only assignment.
     * @param territoryAddressIds TAS address ids for the selected territories.
     * @return Account Ids that receive an Account Team row.
     */
    private static Set<Id> resolveCascadeAccountIds(
        Set<Id> selectedAccountIds,
        Set<String> territoryIdSet,
        Set<String> territoryAddressIds
    ) {
        Boolean filterByTerritory = !territoryIdSet.isEmpty();
        Set<Id> expandedAccountIds = new Set<Id>();
        Set<Id> customerIds = new Set<Id>();
        Set<Id> gpoIds = new Set<Id>();

        for (Account selectedAccount : queryAccountsByIds(selectedAccountIds)) {
            if (selectedAccount.Type == ACCOUNT_TYPE_IDN) {
                continue;
            }
            expandedAccountIds.add(selectedAccount.Id);
            if (selectedAccount.Type == ACCOUNT_TYPE_GPO) {
                gpoIds.add(selectedAccount.Id);
            } else if (selectedAccount.Type != ACCOUNT_TYPE_ADDRESS) {
                customerIds.add(selectedAccount.Id);
            }
        }

        addGpoMemberAccounts(gpoIds, customerIds, expandedAccountIds, filterByTerritory, territoryAddressIds);
        expandedAccountIds.addAll(queryChildAccountIds(customerIds, filterByTerritory, territoryAddressIds));
        return expandedAccountIds;
    }

    /**
     * @description
     * GCL-79 - Adds GPO member accounts to the assignment set. A member Customer is also collected
     * so its child accounts can be added. IDN members are skipped.
     *
     * @param gpoIds Selected GPO Account Ids.
     * @param customerIds Output set of Customer Account Ids whose children should be included.
     * @param expandedAccountIds Output set of Account Ids that receive an Account Team row.
     * @param filterByTerritory True when a territory was selected.
     * @param territoryAddressIds TAS address ids for the selected territories.
     */
    private static void addGpoMemberAccounts(
        Set<Id> gpoIds,
        Set<Id> customerIds,
        Set<Id> expandedAccountIds,
        Boolean filterByTerritory,
        Set<String> territoryAddressIds
    ) {
        if (gpoIds.isEmpty()) {
            return;
        }

        Set<Id> memberIds = new Set<Id>();
        for (AccountAccountRelationship__c affiliation :
            AccountAccountRelationshipSelector.selectMembersByParentIds(gpoIds)) {
            if (affiliation.ChildAccount__c != null && isGpoRelationship(affiliation)) {
                memberIds.add(affiliation.ChildAccount__c);
            }
        }

        for (Account memberAccount : queryAccountsByIds(memberIds)) {
            if (memberAccount.Type == ACCOUNT_TYPE_IDN) {
                continue;
            }
            if (memberAccount.Type == ACCOUNT_TYPE_ADDRESS) {
                if (!filterByTerritory || isTerritoryMatchedAddress(memberAccount, territoryAddressIds)) {
                    expandedAccountIds.add(memberAccount.Id);
                }
            } else if (memberAccount.Type == ACCOUNT_TYPE_GPO) {
                expandedAccountIds.add(memberAccount.Id);
            } else {
                expandedAccountIds.add(memberAccount.Id);
                customerIds.add(memberAccount.Id);
            }
        }
    }

    /**
     * @description
     * GCL-79 - Child Account Ids under the given Customer accounts. When a territory is selected,
     * only children whose Oracle address matches that territory are returned.
     *
     * @param customerIds Customer Account Ids.
     * @param filterByTerritory True when a territory was selected.
     * @param territoryAddressIds TAS address ids for the selected territories.
     * @return Child Account Ids.
     */
    private static Set<Id> queryChildAccountIds(
        Set<Id> customerIds,
        Boolean filterByTerritory,
        Set<String> territoryAddressIds
    ) {
        Set<Id> childIds = new Set<Id>();
        if (customerIds.isEmpty()) {
            return childIds;
        }
        for (Account childAccount : [
            SELECT Id, Type, OracleAddressId__c
            FROM Account
            WHERE ParentId IN :customerIds
            WITH USER_MODE
        ]) {
            if (childAccount.Type == ACCOUNT_TYPE_IDN) {
                continue;
            }
            if (filterByTerritory && !isTerritoryMatchedAddress(childAccount, territoryAddressIds)) {
                continue;
            }
            childIds.add(childAccount.Id);
        }
        return childIds;
    }

    /**
     * @description GCL-79 - True when the Address Account's Oracle address is on the selected territory.
     * @param accountRecord Address Account to test.
     * @param territoryAddressIds TAS address ids for the selected territories.
     * @return True when the account belongs to one of those territories.
     */
    private static Boolean isTerritoryMatchedAddress(Account accountRecord, Set<String> territoryAddressIds) {
        return accountRecord != null
            && String.isNotBlank(accountRecord.OracleAddressId__c)
            && territoryAddressIds != null
            && territoryAddressIds.contains(accountRecord.OracleAddressId__c.trim());
    }

    /**
     * @description GCL-79 - Looks up the Life Sciences territory row matching an Account's Oracle Address Id.
     * @param accountRecord Address-level Account to match.
     * @param territoryByAddressId Territories keyed by TAS Address Id.
     * @return Matching territory row, or null when there is no match.
     */
    private static OrderLineContact__c territoryForAccount(
        Account accountRecord,
        Map<String, OrderLineContact__c> territoryByAddressId
    ) {
        if (accountRecord == null || String.isBlank(accountRecord.OracleAddressId__c) || territoryByAddressId.isEmpty()) {
            return null;
        }
        return territoryByAddressId.get(accountRecord.OracleAddressId__c.trim());
    }

    /**
     * @description GCL-79 - Applies the Account Type and Account Name/Number filters to an already-resolved row.
     * @param row Account row to test.
     * @param accountSearchKey Account Name or Account Number text.
     * @param accountType Selected Account Type, or blank for any type.
     * @return True when the row matches every provided filter.
     */
    private static Boolean matchesSearch(
        LsOverlayAssignmentController.AccountWrapper row,
        String accountSearchKey,
        String accountType
    ) {
        if (String.isNotBlank(accountType) && row.accountType != accountType) {
            return false;
        }
        if (String.isBlank(accountSearchKey)) {
            return true;
        }

        String key = accountSearchKey.trim().toLowerCase();
        String nameValue = row.accountName == null ? '' : row.accountName.toLowerCase();
        String numberValue = row.accountNumber == null ? '' : row.accountNumber.toLowerCase();
        String associatedName = row.associatedAccountName == null ? '' : row.associatedAccountName.toLowerCase();
        return nameValue.contains(key) || numberValue.contains(key) || associatedName.contains(key);
    }

    /**
     * @description GCL-79 - Maps an Account record, and its matching territory when one exists, into the LWC-facing row.
     * @param accountRecord Address-level or standalone Account record.
     * @param territory Matching Life Sciences territory row, or null when not resolved through a territory search.
     * @return Populated AccountWrapper row.
     */
    private static LsOverlayAssignmentController.AccountWrapper toAccountWrapper(
        Account accountRecord,
        OrderLineContact__c territory
    ) {
        LsOverlayAssignmentController.AccountWrapper row = new LsOverlayAssignmentController.AccountWrapper();
        row.accountId = accountRecord.Id;
        row.accountName = accountRecord.Name;
        row.accountNumber = accountRecord.AccountNumber;
        row.accountType = accountRecord.Type;
        row.street = accountRecord.BillingStreet;
        row.city = accountRecord.BillingCity;
        row.state = accountRecord.BillingState;
        row.postalCode = accountRecord.BillingPostalCode;
        row.country = accountRecord.BillingCountry;
        row.associatedAccountId = accountRecord.ParentId == null ? accountRecord.Id : accountRecord.ParentId;
        row.associatedAccountName = accountRecord.ParentId == null ? accountRecord.Name : accountRecord.Parent.Name;

        if (territory != null) {
            row.territoryId = territory.TerritoryID__c;
            row.territoryDescription = territory.TerritoryDescription__c;
        }
        return row;
    }

    /**
     * @description GCL-79 - Resolves the account rows selected for submission/summary, preferring the
     *              territory-scoped search results and falling back to a direct Id lookup for
     *              an account-only selection that would not otherwise be re-derivable.
     * @param territoryIds Selected Territory IDs.
     * @param selectedAccountIdSet Accounts still selected after Step 2 deselection.
     * @return AccountWrapper rows for every selected account.
     */
    private static List<LsOverlayAssignmentController.AccountWrapper> selectSummaryAccountRows(
        List<String> territoryIds,
        Set<Id> selectedAccountIdSet
    ) {
        List<LsOverlayAssignmentController.AccountWrapper> selectedRows =
            new List<LsOverlayAssignmentController.AccountWrapper>();

        for (LsOverlayAssignmentController.AccountWrapper accountRow : findAccountRows(null, null, territoryIds, null)) {
            if (selectedAccountIdSet.contains(accountRow.accountId)) {
                selectedRows.add(accountRow);
            }
        }

        if (selectedRows.isEmpty()) {
            for (Account accountRecord : queryAccountsByIds(selectedAccountIdSet)) {
                selectedRows.add(toAccountWrapper(accountRecord, null));
            }
        }
        return selectedRows;
    }

    /**
     * @description GCL-79 - Groups selected account rows into one summary row per Territory, or a single
     *              Account Search row when no territory applies.
     * @param selectedRows Account rows selected for submission.
     * @return One summary row per Territory ID (or Account Search).
     */
    private static List<LsOverlayAssignmentController.SummaryTerritoryWrapper> groupAccountRowsByTerritory(
        List<LsOverlayAssignmentController.AccountWrapper> selectedRows
    ) {
        Map<String, LsOverlayAssignmentController.SummaryTerritoryWrapper> summaryByKey =
            new Map<String, LsOverlayAssignmentController.SummaryTerritoryWrapper>();

        for (LsOverlayAssignmentController.AccountWrapper accountRow : selectedRows) {
            String summaryKey = String.isBlank(accountRow.territoryId) ? ACCOUNT_SEARCH_LABEL : accountRow.territoryId;

            if (!summaryByKey.containsKey(summaryKey)) {
                LsOverlayAssignmentController.SummaryTerritoryWrapper summaryRow =
                    new LsOverlayAssignmentController.SummaryTerritoryWrapper();
                summaryRow.territoryId = summaryKey;
                summaryRow.territoryDescription = String.isBlank(accountRow.territoryDescription)
                    ? summaryKey
                    : accountRow.territoryDescription;
                summaryRow.selectedAccounts = new List<LsOverlayAssignmentController.AccountWrapper>();
                summaryByKey.put(summaryKey, summaryRow);
            }
            summaryByKey.get(summaryKey).selectedAccounts.add(accountRow);
        }
        return summaryByKey.values();
    }

    /**
     * @description
     * GCL-79 - Builds the new Account Team Member records for submit, skipping any
     * Account-plus-User combination that already exists. Only Account access is
     * extended: OpportunityAccessLevel and CaseAccessLevel are explicitly None.
     *
     * @param accountList Selected Customer or GPO accounts plus their cascaded child accounts.
     * @param userIdSet Overlay users selected on Step 3.
     * @param territoryByAddressId Life Sciences territories keyed by TAS Address Id. Empty when no territory is selected.
     * @return New AccountTeamMember records to insert. Empty when every combination already exists.
     */
    private static List<AccountTeamMember> buildNewAccountTeamMembers(
        List<Account> accountList,
        Set<Id> userIdSet,
        Map<String, OrderLineContact__c> territoryByAddressId
    ) {
        Set<Id> accountIdSet = new Map<Id, Account>(accountList).keySet();
        if (accountIdSet.isEmpty() || userIdSet.isEmpty()) {
            return new List<AccountTeamMember>();
        }

        Set<String> existingKeys = new Set<String>();
        for (AccountTeamMember existingMember : [
            SELECT AccountId, UserId
            FROM AccountTeamMember
            WHERE AccountId IN :accountIdSet
            AND UserId IN :userIdSet
        ]) {
            existingKeys.add(existingMember.AccountId + '-' + existingMember.UserId);
        }

        Map<Id, OrderLineContact__c> territoryByParentId = territoryByParentAccountId(accountList, territoryByAddressId);
        List<AccountTeamMember> membersToInsert = new List<AccountTeamMember>();
        for (Account accountRecord : accountList) {
            OrderLineContact__c sourceTerritory = territoryForAccount(accountRecord, territoryByAddressId);
            if (sourceTerritory == null) {
                sourceTerritory = territoryByParentId.get(accountRecord.Id);
            }
            for (Id userId : userIdSet) {
                if (existingKeys.contains(accountRecord.Id + '-' + userId)) {
                    continue;
                }
                AccountTeamMember member = new AccountTeamMember(
                    AccountId = accountRecord.Id,
                    UserId = userId,
                    TeamMemberRole = TEAM_MEMBER_ROLE_SALES,
                    AssignmentType__c = ASSIGNMENT_TYPE_SALESFORCE_ASSIGNED,
                    AccountAccessLevel = ACCOUNT_ACCESS_EDIT,
                    OpportunityAccessLevel = NO_ACCESS,
                    CaseAccessLevel = NO_ACCESS
                );
                copyTerritoryFields(member, sourceTerritory);
                membersToInsert.add(member);
            }
        }
        return membersToInsert;
    }

    /**
     * @description GCL-79 - Territory source for a Customer that has no Oracle address of its own.
     *              Uses the first child Address Account in this assignment whose Oracle address matches a selected territory.
     * @param accountList Accounts receiving the overlay assignment.
     * @param territoryByAddressId Life Sciences territories keyed by TAS Address Id.
     * @return Parent Account Id to the matching territory row.
     */
    private static Map<Id, OrderLineContact__c> territoryByParentAccountId(
        List<Account> accountList,
        Map<String, OrderLineContact__c> territoryByAddressId
    ) {
        Map<Id, OrderLineContact__c> territoryByParentId = new Map<Id, OrderLineContact__c>();
        for (Account accountRecord : accountList) {
            if (accountRecord.ParentId == null || territoryByParentId.containsKey(accountRecord.ParentId)) {
                continue;
            }
            OrderLineContact__c sourceTerritory = territoryForAccount(accountRecord, territoryByAddressId);
            if (sourceTerritory != null) {
                territoryByParentId.put(accountRecord.ParentId, sourceTerritory);
            }
        }
        return territoryByParentId;
    }

    /**
     * @description GCL-79 - Copies Territory Number and sales category from the source Order Line Contact
     *              onto a new Account Team Member. Existing rows are left unchanged because TAS territory
     *              fields cannot be edited after insert.
     * @param member Account Team Member to populate.
     * @param sourceTerritory Life Sciences Order Line Contact for the selected territory.
     */
    private static void copyTerritoryFields(AccountTeamMember member, OrderLineContact__c sourceTerritory) {
        if (member == null || sourceTerritory == null) {
            return;
        }
        member.TerritoryCode__c = sourceTerritory.TerritoryNumber__c;
        member.SalesCategoryCode__c = sourceTerritory.TAS_Sales_Category__c;
        member.SalesCategoryDescription__c = sourceTerritory.SalesCategoryDescription__c;
    }

    /**
     * @description
     * GCL-79 - Rejects the submit when any selected user is inactive or outside the
     * Life Sciences Sales profile. This query does not use USER_MODE: the BSA persona
     * cannot read User.ProfileId, and stripping that field breaks the bind variables.
     *
     * @param userIdSet User Ids submitted from the screen.
     */
    private static void requireActiveLifeSciencesUsers(Set<Id> userIdSet) {
        Id lifeSciencesProfileId = UserSelector.getLifeSciencesSalesProfileId();
        if (lifeSciencesProfileId == null) {
            throw new LsOverlayAssignmentException('Life Sciences Sales profile was not found.');
        }

        Set<Id> matchingUserIds = new Map<Id, User>([
            SELECT Id
            FROM User
            WHERE Id IN :userIdSet
            AND IsActive = true
            AND ProfileId = :lifeSciencesProfileId
        ]).keySet();

        if (matchingUserIds.size() != userIdSet.size()) {
            throw new LsOverlayAssignmentException('Select active Life Sciences Sales users only.');
        }
    }

    /**
     * @description GCL-79 - Converts a List of Ids into a null-safe Set.
     * @param ids Ids to convert, may be null.
     * @return Non-null Set with every null entry removed.
     */
    private static Set<Id> toIdSet(List<Id> ids) {
        Set<Id> idSet = new Set<Id>();
        if (ids != null) {
            idSet.addAll(ids);
        }
        idSet.remove(null);
        return idSet;
    }

    /**
     * @description GCL-79 - Converts a List of Strings into a null-safe, blank-free Set.
     * @param values Strings to convert, may be null.
     * @return Non-null Set with every blank entry removed.
     */
    private static Set<String> toStringSet(List<String> values) {
        Set<String> valueSet = new Set<String>();
        if (values == null) {
            return valueSet;
        }
        for (String value : values) {
            if (String.isNotBlank(value)) {
                valueSet.add(value);
            }
        }
        return valueSet;
    }
}