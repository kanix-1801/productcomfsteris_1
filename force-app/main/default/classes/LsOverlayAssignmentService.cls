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
 * GCL-79 - Submit creates additive Account Team rows only. It does not insert or update OrderLineContact__c
 * and does not create Opportunity Team rows. Only Account access is extended; OpportunityAccessLevel
 * and CaseAccessLevel are explicitly None.
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

            String key = '%' + String.escapeSingleQuotes(searchKey.trim()) + '%';
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
     * GCL-79 - Searches Life Sciences accounts on Step 1 by Account Name/Number and/or
     * Account Type, optionally scoped to already-selected territories. Any single
     * field, or any combination of the supported fields, is a valid search.
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
     * GCL-79 - Retrieves every address-level account tied to the selected territories
     * and/or account search criteria, for display and default selection on Step 2.
     *
     * @param territoryIds Selected Territory IDs, or empty for an account-only search.
     * @param accountSearchKey Account Name or Account Number text from Step 1.
     * @param accountType Selected Account Type from Step 1.
     * @param selectedSearchAccountIds Account Ids explicitly selected on Step 1's account search results.
     * @return Address-level account rows with territory and address detail.
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
     * in addition to Email and Role.
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

            String key = '%' + String.escapeSingleQuotes(searchKey.trim()) + '%';
            List<LsOverlayAssignmentController.UserWrapper> users = new List<LsOverlayAssignmentController.UserWrapper>();

            for (User userRecord : [
                SELECT Id, Name, Email, Country, UserRole.Name, Manager.Name
                FROM User
                WHERE IsActive = true
                AND ProfileId = :lifeSciencesProfileId
                AND (Name LIKE :key OR Email LIKE :key)
                WITH USER_MODE
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
     * Only Account access is extended: AccountAccessLevel is Edit, and
     * OpportunityAccessLevel / CaseAccessLevel are explicitly None. No
     * OrderLineContact__c (TAS/Oracle) row is inserted or updated by this method.
     *
     * @param territoryIds Selected Territory IDs. Not used for Account Team creation;
     *                      accepted for interface parity with the search/summary steps.
     * @param selectedAccountIds Accounts still selected after Step 2 deselection.
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

        Savepoint savepointValue = Database.setSavepoint();
        try {
            List<AccountTeamMember> membersToInsert = buildNewAccountTeamMembers(accountIdSet, userIdSet);

            if (!membersToInsert.isEmpty()) {
                SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, membersToInsert);
                insert decision.getRecords();
            }
        } catch (Exception ex) {
            Database.rollback(savepointValue);
            throw logAndWrap('Unable to submit Life Sciences overlay assignments.', ex);
        } finally {
            Logger.saveLog();
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
     * more territories are selected, accounts are resolved through the matching
     * Life Sciences OrderLineContact__c rows (TAS Address Id). Otherwise accounts are
     * resolved directly from Account Name/Number/Type. Results are always expanded to
     * address-level rows so street/city/state/postal/country can be displayed.
     *
     * @param accountSearchKey Account Name or Account Number text.
     * @param accountType Selected Account Type, or blank for any type.
     * @param territoryIds Selected Territory IDs, or empty for an account-only search.
     * @param selectedSearchAccountIds Account Ids explicitly selected on Step 1's account search results.
     * @return Address-level account rows matching the combined search criteria.
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

        List<Account> matchedAccounts = territoryByAddressId.isEmpty()
            ? queryLifeSciencesAccounts(accountSearchKey, accountType, selectedAccountIds)
            : queryAccountsByOracleAddress(territoryByAddressId.keySet());

        if (!territoryByAddressId.isEmpty() && !selectedAccountIds.isEmpty()) {
            matchedAccounts = restrictToSelectedAccounts(matchedAccounts, selectedAccountIds);
        }

        List<LsOverlayAssignmentController.AccountWrapper> rows =
            new List<LsOverlayAssignmentController.AccountWrapper>();

        for (Account accountRecord : expandToAddressAccounts(matchedAccounts)) {
            OrderLineContact__c territory = territoryForAccount(accountRecord, territoryByAddressId);
            if (!territoryIdSet.isEmpty() && territory == null) {
                continue;
            }

            LsOverlayAssignmentController.AccountWrapper row = toAccountWrapper(accountRecord, territory);
            if (matchesSearch(row, accountSearchKey, accountType)) {
                rows.add(row);
            }
        }
        return rows;
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
            SELECT TerritoryID__c, TerritoryDescription__c, TASAddressId__c
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
     * GCL-79 - Resolves Life Sciences Accounts for an account-only search (no territory selected),
     * branching on which of Account Name/Number and Account Type were provided. Explicit
     * account Ids from a prior Step 1 selection take priority over a fresh search.
     *
     * @param accountSearchKey Account Name or Account Number text.
     * @param accountType Selected Account Type, or blank for any type.
     * @param selectedAccountIds Account Ids explicitly selected on Step 1's account search results.
     * @return Matching Life Sciences Accounts (class code SC, Life Science, or Life Sciences).
     */
    private static List<Account> queryLifeSciencesAccounts(
        String accountSearchKey,
        String accountType,
        Set<Id> selectedAccountIds
    ) {
        if (!selectedAccountIds.isEmpty()) {
            return queryAccountsByIds(selectedAccountIds);
        }

        String searchTerm = String.isBlank(accountSearchKey)
            ? null
            : '%' + String.escapeSingleQuotes(accountSearchKey.trim()) + '%';
        Boolean hasSearchTerm = String.isNotBlank(accountSearchKey);
        Boolean hasType = String.isNotBlank(accountType);

        if (hasSearchTerm && hasType) {
            return [
                SELECT Id, Name, AccountNumber, Type, ParentId, Parent.Name, OracleAddressId__c,
                       BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry
                FROM Account
                WHERE CustomerClassCode__c IN :LIFE_SCIENCES_CLASS_CODES
                AND Type = :accountType
                AND (Name LIKE :searchTerm OR AccountNumber LIKE :searchTerm)
                WITH USER_MODE
                ORDER BY Name
                LIMIT :SEARCH_LIMIT
            ];
        }
        if (hasSearchTerm) {
            return [
                SELECT Id, Name, AccountNumber, Type, ParentId, Parent.Name, OracleAddressId__c,
                       BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry
                FROM Account
                WHERE CustomerClassCode__c IN :LIFE_SCIENCES_CLASS_CODES
                AND (Name LIKE :searchTerm OR AccountNumber LIKE :searchTerm)
                WITH USER_MODE
                ORDER BY Name
                LIMIT :SEARCH_LIMIT
            ];
        }
        if (hasType) {
            return [
                SELECT Id, Name, AccountNumber, Type, ParentId, Parent.Name, OracleAddressId__c,
                       BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry
                FROM Account
                WHERE CustomerClassCode__c IN :LIFE_SCIENCES_CLASS_CODES
                AND Type = :accountType
                WITH USER_MODE
                ORDER BY Name
                LIMIT :SEARCH_LIMIT
            ];
        }
        return new List<Account>();
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
     * @description GCL-79 - Keeps only the accounts (or their parent) that the user explicitly selected
     *              on Step 1's account search results, when combined with a territory search.
     * @param accounts Accounts matched by the territory search.
     * @param selectedAccountIds Account Ids explicitly selected on Step 1.
     * @return Filtered account list.
     */
    private static List<Account> restrictToSelectedAccounts(List<Account> accounts, Set<Id> selectedAccountIds) {
        List<Account> restricted = new List<Account>();
        for (Account accountRecord : accounts) {
            if (selectedAccountIds.contains(accountRecord.Id) || selectedAccountIds.contains(accountRecord.ParentId)) {
                restricted.add(accountRecord);
            }
        }
        return restricted;
    }

    /**
     * @description
     * GCL-79 - Expands non-Address accounts (Customer, IDN, GPO) to their child Address
     * accounts so the wizard always displays address-level rows. Accounts that are
     * already Address type, or that have no Address children, pass through unchanged.
     *
     * @param accounts Accounts resolved by territory or account search.
     * @return Address-level account rows where available, otherwise the original rows.
     */
    private static List<Account> expandToAddressAccounts(List<Account> accounts) {
        Map<Id, Account> addressById = new Map<Id, Account>();
        Set<Id> parentIds = new Set<Id>();

        for (Account accountRecord : accounts) {
            if (accountRecord.Type == 'Address') {
                addressById.put(accountRecord.Id, accountRecord);
            } else {
                parentIds.add(accountRecord.Id);
            }
        }

        if (!parentIds.isEmpty()) {
            for (Account childAccount : [
                SELECT Id, Name, AccountNumber, Type, ParentId, Parent.Name, OracleAddressId__c,
                       BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry
                FROM Account
                WHERE ParentId IN :parentIds
                AND Type = 'Address'
                WITH USER_MODE
                LIMIT :SEARCH_LIMIT
            ]) {
                addressById.put(childAccount.Id, childAccount);
            }
        }

        if (addressById.isEmpty()) {
            for (Account accountRecord : accounts) {
                addressById.put(accountRecord.Id, accountRecord);
            }
        }
        return addressById.values();
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
     * @param accountIdSet Accounts still selected after Step 2 deselection.
     * @param userIdSet Overlay users selected on Step 3.
     * @return New AccountTeamMember records to insert. Empty when every combination already exists.
     */
    private static List<AccountTeamMember> buildNewAccountTeamMembers(Set<Id> accountIdSet, Set<Id> userIdSet) {
        Set<String> existingKeys = new Set<String>();
        for (AccountTeamMember existingMember : [
            SELECT AccountId, UserId
            FROM AccountTeamMember
            WHERE AccountId IN :accountIdSet
            AND UserId IN :userIdSet
        ]) {
            existingKeys.add(existingMember.AccountId + '-' + existingMember.UserId);
        }

        List<AccountTeamMember> membersToInsert = new List<AccountTeamMember>();
        for (Id accountId : accountIdSet) {
            for (Id userId : userIdSet) {
                if (existingKeys.contains(accountId + '-' + userId)) {
                    continue;
                }
                membersToInsert.add(new AccountTeamMember(
                    AccountId = accountId,
                    UserId = userId,
                    TeamMemberRole = TEAM_MEMBER_ROLE_SALES,
                    AssignmentType__c = ASSIGNMENT_TYPE_SALESFORCE_ASSIGNED,
                    AccountAccessLevel = ACCOUNT_ACCESS_EDIT,
                    // Only Account access is extended for overlay users for this story.
                    OpportunityAccessLevel = NO_ACCESS,
                    CaseAccessLevel = NO_ACCESS
                ));
            }
        }
        return membersToInsert;
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