/**
 * @author PWC Developer
 * @date 2026/11/04
 *
 * @group Life Sciences Overlay Assignment
 *
 * @description
 * GCL-79 - Service layer for Life Sciences Overlay Assignment across Accounts, Users, and TAS territory records.
 * GCL-79 - Territory search stays scoped to Life Sciences class codes (SC / Life Science / Life Sciences).
 * Overlay users are limited to the Life Sciences Sales profile.
 * GCL-79 - Step 1 and Step 2 show Customer accounts. GPO, IDN, and Address are not searched or shown.
 * Submit adds the overlay user to the selected Customer and to that account's child accounts.
 * When a territory is selected, TerritoryCode__c is copied from the TAS territory number and a TAS row is inserted. IDN is skipped.
 * GCL-79 - Submit also calls the Healthcare share helper for each assigned account. No Opportunity Team row is created.
 * Account, Contact, Opportunity, and Case access are set on the Account Team row itself.
 * Overlay type - The pre-wizard chooses Inside Sales or GAD. Inside Sales keeps the territory and
 * account flow above with role Inside Sales. GAD assigns the selected Global Account and its
 * ParentId hierarchy (Customer, then Ship-to Address) with role Global Account Director.
 * Overlay users must have the Life Sciences Sales profile and the overlay type's permission set
 * or permission set group.
 */
public without sharing class LsOverlayAssignmentService {
    /** @description GCL-79 - Account Team Member.AssignmentType__c value for this wizard. */
    public static final String ASSIGNMENT_TYPE_SALESFORCE_ASSIGNED = 'Salesforce Assigned';

    /** @description GCL-79 - Edit access level on the Account Team row. */
    public static final String ACCOUNT_ACCESS_EDIT = 'Edit';

    /** @description GCL-79 - No access on the Account Team row. */
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
        'SC'
    };

    /** @description Overlay type values sent by the pre-wizard. */
    public static final String OVERLAY_TYPE_INSIDE_SALES = 'Inside Sales';
    public static final String OVERLAY_TYPE_GAD = 'GAD';

    /** @description Account Team roles written for each overlay type. */
    public static final String TEAM_MEMBER_ROLE_INSIDE_SALES = 'Inside Sales';
    public static final String TEAM_MEMBER_ROLE_GAD = 'Global Account Director';

    /** @description Read access level used for GAD Customer and Ship-to opportunities. */
    public static final String ACCESS_READ = 'Read';

    /** @description Summary row description for a GAD Global Account hierarchy. */
    public static final String GLOBAL_ACCOUNT_SUMMARY_LABEL = 'Global Account hierarchy';

    /** @description Account Type shown for a Global Account with a blank Type. */
    private static final String GLOBAL_ACCOUNT_DISPLAY_TYPE = 'Global Account';

    private static final Map<String, String> TEAM_MEMBER_ROLE_BY_OVERLAY_TYPE = new Map<String, String>{
        OVERLAY_TYPE_INSIDE_SALES => TEAM_MEMBER_ROLE_INSIDE_SALES,
        OVERLAY_TYPE_GAD => TEAM_MEMBER_ROLE_GAD
    };

    private static final Map<String, Set<String>> PERMISSION_SETS_BY_OVERLAY_TYPE = new Map<String, Set<String>>{
        OVERLAY_TYPE_INSIDE_SALES => new Set<String>{ 'LSInsideSalesPS' },
        OVERLAY_TYPE_GAD => new Set<String>{ 'LSGlobalAccountDirectorPS' }
    };

    private static final Map<String, Set<String>> PERMISSION_SET_GROUPS_BY_OVERLAY_TYPE = new Map<String, Set<String>>{
        OVERLAY_TYPE_INSIDE_SALES => new Set<String>{ 'LSInsideSalesPSG' },
        OVERLAY_TYPE_GAD => new Set<String>{ 'LSGlobalAccountDirectorPSG' }
    };

    /** @description Inside Sales: Account and Contact Edit, no Opportunity or Case access. */
    private static final AccessLevels INSIDE_SALES_ACCESS = new AccessLevels(ACCOUNT_ACCESS_EDIT, ACCOUNT_ACCESS_EDIT, NO_ACCESS, NO_ACCESS);

    /** @description GAD on the Global Account: Account, Contact, and direct Opportunity Edit. */
    private static final AccessLevels GAD_GLOBAL_ACCOUNT_ACCESS = new AccessLevels(ACCOUNT_ACCESS_EDIT, ACCOUNT_ACCESS_EDIT, ACCOUNT_ACCESS_EDIT, NO_ACCESS);

    /** @description GAD on Customer and Ship-to: Account and Contact Edit, Opportunity Read. */
    private static final AccessLevels GAD_HIERARCHY_ACCESS = new AccessLevels(ACCOUNT_ACCESS_EDIT, ACCOUNT_ACCESS_EDIT, ACCESS_READ, NO_ACCESS);

    /**
     * @description Account Team Member access levels for one assigned account.
     */
    private class AccessLevels {
        public final String accountAccess;
        public final String contactAccess;
        public final String opportunityAccess;
        public final String caseAccess;

        public AccessLevels(String accountAccess, String contactAccess, String opportunityAccess, String caseAccess) {
            this.accountAccess = accountAccess;
            this.contactAccess = contactAccess;
            this.opportunityAccess = opportunityAccess;
            this.caseAccess = caseAccess;
        }
    }

    /**
     * @description Searches Global Accounts by Account Name or Account Number for the GAD overlay.
     *              Every GlobalAccount record type account is searchable. Class code is not filtered.
     * @param searchKey User-entered search text. Returns an empty list when blank.
     * @return Matching Global Account rows.
     */
    public static List<OverlayAssignmentController.AccountWrapper> searchGlobalAccounts(String searchKey) {
        try {
            if (String.isBlank(searchKey)) {
                return new List<OverlayAssignmentController.AccountWrapper>();
            }
            List<OverlayAssignmentController.AccountWrapper> rows = new List<OverlayAssignmentController.AccountWrapper>();
            for (Account globalAccount : AccountSelector.selectGlobalAccountsBySearch(
                '%' + searchKey.trim() + '%',
                SEARCH_LIMIT
            )) {
                rows.add(toGlobalAccountWrapper(globalAccount));
            }
            return rows;
        } catch (Exception ex) {
            throw logAndWrap('Unable to search Global Accounts.', ex);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Searches overlay users for the selected overlay type. Reuses the Healthcare
     *              user search, then keeps only active Life Sciences Sales users who hold the
     *              overlay type's permission set or permission set group.
     * @param searchKey User-entered search text. Returns an empty list when blank.
     * @param overlayType Inside Sales or GAD.
     * @return Eligible overlay users.
     */
    public static List<OverlayAssignmentController.UserWrapper> searchOverlayUsers(String searchKey, String overlayType) {
        try {
            String resolvedType = requireOverlayType(overlayType);
            List<OverlayAssignmentController.UserWrapper> eligibleUsers = new List<OverlayAssignmentController.UserWrapper>();
            if (String.isBlank(searchKey)) {
                return eligibleUsers;
            }

            List<OverlayAssignmentController.UserWrapper> candidates = OverlayAssignmentService.searchOverlayUsers(searchKey);
            if (candidates == null || candidates.isEmpty()) {
                return eligibleUsers;
            }

            Set<Id> candidateIds = new Set<Id>();
            for (OverlayAssignmentController.UserWrapper candidate : candidates) {
                candidateIds.add(candidate.userId);
            }
            Set<Id> eligibleIds = selectEligibleOverlayUserIds(candidateIds, resolvedType);
            for (OverlayAssignmentController.UserWrapper candidate : candidates) {
                if (eligibleIds.contains(candidate.userId)) {
                    eligibleUsers.add(candidate);
                }
            }
            return eligibleUsers;
        } catch (OverlayAssignmentException ex) {
            throw ex;
        } catch (Exception ex) {
            throw logAndWrap('Unable to search Life Sciences overlay users.', ex);
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
    public static List<OverlayAssignmentController.AccountWrapper> searchAccounts(
        String accountSearchKey,
        String accountType,
        List<String> territoryIds
    ) {
        try {
            Boolean hasAnyCriteria = String.isNotBlank(accountSearchKey)
                || String.isNotBlank(accountType)
                || (territoryIds != null && !territoryIds.isEmpty());

            if (!hasAnyCriteria) {
                return new List<OverlayAssignmentController.AccountWrapper>();
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
    public static List<OverlayAssignmentController.AccountWrapper> retrieveAccounts(
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
                throw new OverlayAssignmentException('Enter a territory or account before retrieving accounts.');
            }

            return findAccountRows(accountSearchKey, accountType, territoryIds, selectedSearchAccountIds);
        } catch (OverlayAssignmentException ex) {
            throw ex;
        } catch (Exception ex) {
            throw logAndWrap('Unable to retrieve Life Sciences accounts.', ex);
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
     * @param overlayType Inside Sales or GAD. GAD returns one row per Global Account hierarchy.
     * @return One summary row per territory (or Account Search) with its selected accounts.
     */
    public static List<OverlayAssignmentController.SummaryTerritoryWrapper> getAssignmentSummary(
        List<String> territoryIds,
        List<Id> selectedAccountIds,
        String overlayType
    ) {
        try {
            String resolvedType = requireOverlayType(overlayType);
            Set<Id> selectedAccountIdSet = toIdSet(selectedAccountIds);
            if (selectedAccountIdSet.isEmpty()) {
                throw new OverlayAssignmentException('No accounts selected for overlay assignment.');
            }
            if (resolvedType == OVERLAY_TYPE_GAD) {
                return buildGlobalAccountSummary(selectedAccountIdSet);
            }

            List<OverlayAssignmentController.AccountWrapper> selectedRows = selectSummaryAccountRows(
                territoryIds,
                selectedAccountIdSet
            );
            return groupAccountRowsByTerritory(selectedRows);
        } catch (OverlayAssignmentException ex) {
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
     * Inside Sales: TeamMemberRole is Inside Sales, Account and Contact access are Edit, and
     * Opportunity / Case access are None. GAD: TeamMemberRole is Global Account Director,
     * Account and Contact access are Edit, Opportunity access is Edit on the Global Account and
     * Read on its Customer and Ship-to accounts, and Case access is None.
     * AssignmentType__c defaults to Salesforce Assigned. The Healthcare share helper then runs
     * for each assigned account. When a territory is selected, a TAS OrderLineContact__c row
     * is inserted for each Address Account that matches that territory.
     *
     * @param territoryIds Selected Territory IDs. When present, child accounts must match a
     *                     territory TAS address, and TerritoryCode__c is copied from that territory.
     * @param selectedAccountIds Customer accounts still selected after Step 2 deselection.
     *                           For GAD, the Global Accounts selected on Step 1.
     * @param userIds Overlay users selected on Step 3.
     * @param overlayType Inside Sales or GAD.
     */
    public static void submitOverlayAssignments(
        List<String> territoryIds,
        List<Id> selectedAccountIds,
        List<Id> userIds,
        String overlayType
    ) {
        String resolvedType = requireOverlayType(overlayType);
        Set<Id> accountIdSet = toIdSet(selectedAccountIds);
        Set<Id> userIdSet = toIdSet(userIds);

        if (accountIdSet.isEmpty()) {
            throw new OverlayAssignmentException('No accounts selected for overlay assignment.');
        }
        if (userIdSet.isEmpty()) {
            throw new OverlayAssignmentException('Select at least one overlay user.');
        }
        requireEligibleOverlayUsers(userIdSet, resolvedType);

        Savepoint savepointValue = Database.setSavepoint();
        try {
            if (resolvedType == OVERLAY_TYPE_GAD) {
                submitGlobalAccountAssignments(accountIdSet, userIdSet);
                return;
            }

            Set<String> territoryIdSet = toStringSet(territoryIds);
            Map<String, OrderLineContact__c> territoryByAddressId = loadLifeSciencesTerritories(territoryIdSet);
            Set<Id> cascadeAccountIds = resolveCascadeAccountIds(
                accountIdSet,
                territoryIdSet,
                territoryByAddressId.keySet()
            );
            List<Account> cascadeAccounts = queryAccountsByIds(cascadeAccountIds);
            Map<Id, AccessLevels> accessByAccountId = new Map<Id, AccessLevels>();
            for (Account cascadeAccount : cascadeAccounts) {
                accessByAccountId.put(cascadeAccount.Id, INSIDE_SALES_ACCESS);
            }
            insertAccountTeamMembers(buildNewAccountTeamMembers(
                cascadeAccounts,
                userIdSet,
                territoryIdSet.isEmpty() ? new Map<String, OrderLineContact__c>() : territoryByAddressId,
                TEAM_MEMBER_ROLE_INSIDE_SALES,
                accessByAccountId
            ));
            createAccountShares(cascadeAccounts, userIdSet);
            if (!territoryIdSet.isEmpty()) {
                //GCL-390 : Tech Story - Hc x LS code dependency resolution
                OverlayAssignmentService.createTasWritebackRecords(
                    cascadeAccounts,
                    userIdSet,
                    territoryByAddressId
                );
            }
        } catch (OverlayAssignmentException ex) {
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
     * @description GAD submit. Adds the GAD to each selected Global Account and to its ParentId
     *              hierarchy. No territory fields are copied and no TAS row is written.
     * @param globalAccountIds Global Accounts selected on Step 1.
     * @param userIdSet GAD users selected on Step 3.
     */
    private static void submitGlobalAccountAssignments(Set<Id> globalAccountIds, Set<Id> userIdSet) {
        requireGlobalAccounts(globalAccountIds);
        Map<Id, AccessLevels> accessByAccountId = new Map<Id, AccessLevels>();
        for (Set<Id> hierarchyIds : resolveGlobalAccountHierarchy(globalAccountIds).values()) {
            for (Id accountId : hierarchyIds) {
                accessByAccountId.put(
                    accountId,
                    globalAccountIds.contains(accountId) ? GAD_GLOBAL_ACCOUNT_ACCESS : GAD_HIERARCHY_ACCESS
                );
            }
        }

        List<Account> hierarchyAccounts = queryAccountsByIds(accessByAccountId.keySet());
        insertAccountTeamMembers(buildNewAccountTeamMembers(
            hierarchyAccounts,
            userIdSet,
            new Map<String, OrderLineContact__c>(),
            TEAM_MEMBER_ROLE_GAD,
            accessByAccountId
        ));
        createAccountShares(hierarchyAccounts, userIdSet);
    }

    /**
     * @description Global Account hierarchy through ParentId: Global Account, its Customer children,
     *              and the Ship-to (Address) children of those Customers. IDN children are skipped.
     * @param globalAccountIds Selected Global Account Ids.
     * @return Account Ids in each hierarchy, keyed by Global Account Id. Each set includes the Global Account.
     */
    private static Map<Id, Set<Id>> resolveGlobalAccountHierarchy(Set<Id> globalAccountIds) {
        Map<Id, Set<Id>> hierarchyByGlobalAccountId = new Map<Id, Set<Id>>();
        for (Id globalAccountId : globalAccountIds) {
            hierarchyByGlobalAccountId.put(globalAccountId, new Set<Id>{ globalAccountId });
        }

        Map<Id, Id> globalAccountIdByCustomerId = new Map<Id, Id>();
        for (Account childAccount : AccountSelector.selectLifeSciencesChildAccounts(globalAccountIds)) {
            if (childAccount.Type == ACCOUNT_TYPE_IDN) {
                continue;
            }
            hierarchyByGlobalAccountId.get(childAccount.ParentId).add(childAccount.Id);
            if (childAccount.Type != ACCOUNT_TYPE_ADDRESS) {
                globalAccountIdByCustomerId.put(childAccount.Id, childAccount.ParentId);
            }
        }

        for (Account shipToAccount : AccountSelector.selectLifeSciencesChildAccounts(globalAccountIdByCustomerId.keySet())) {
            if (shipToAccount.Type == ACCOUNT_TYPE_IDN) {
                continue;
            }
            hierarchyByGlobalAccountId.get(globalAccountIdByCustomerId.get(shipToAccount.ParentId)).add(shipToAccount.Id);
        }
        return hierarchyByGlobalAccountId;
    }

    /**
     * @description GAD summary. One row per selected Global Account listing every account in its hierarchy.
     * @param globalAccountIds Global Accounts selected on Step 1.
     * @return Summary rows for the confirmation step.
     */
    private static List<OverlayAssignmentController.SummaryTerritoryWrapper> buildGlobalAccountSummary(Set<Id> globalAccountIds) {
        List<Account> globalAccounts = requireGlobalAccounts(globalAccountIds);
        Map<Id, Set<Id>> hierarchyByGlobalAccountId = resolveGlobalAccountHierarchy(globalAccountIds);
        Set<Id> hierarchyAccountIds = new Set<Id>();
        for (Set<Id> hierarchyIds : hierarchyByGlobalAccountId.values()) {
            hierarchyAccountIds.addAll(hierarchyIds);
        }
        Map<Id, Account> accountById = new Map<Id, Account>(queryAccountsByIds(hierarchyAccountIds));

        List<OverlayAssignmentController.SummaryTerritoryWrapper> summaryRows =
            new List<OverlayAssignmentController.SummaryTerritoryWrapper>();
        for (Account globalAccount : globalAccounts) {
            OverlayAssignmentController.SummaryTerritoryWrapper summaryRow =
                new OverlayAssignmentController.SummaryTerritoryWrapper();
            summaryRow.territoryId = globalAccount.Name;
            summaryRow.territoryDescription = GLOBAL_ACCOUNT_SUMMARY_LABEL;
            summaryRow.selectedAccounts = new List<OverlayAssignmentController.AccountWrapper>();
            for (Id accountId : hierarchyByGlobalAccountId.get(globalAccount.Id)) {
                Account hierarchyAccount = accountById.get(accountId);
                if (hierarchyAccount == null) {
                    continue;
                }
                summaryRow.selectedAccounts.add(
                    accountId == globalAccount.Id
                        ? toGlobalAccountWrapper(globalAccount)
                        : toAccountWrapper(hierarchyAccount, null)
                );
            }
            summaryRows.add(summaryRow);
        }
        return summaryRows;
    }

    /**
     * @description Loads the selected Global Accounts and rejects any Id that is not a Global Account.
     * @param globalAccountIds Account Ids selected on the GAD search.
     * @return Selected Global Accounts.
     */
    private static List<Account> requireGlobalAccounts(Set<Id> globalAccountIds) {
        List<Account> globalAccounts = AccountSelector.selectGlobalAccountsByIds(globalAccountIds);
        if (globalAccounts.size() != globalAccountIds.size()) {
            throw new OverlayAssignmentException('Select Global Accounts only.');
        }
        return globalAccounts;
    }

    /**
     * @description Maps a Global Account into the LWC row. A blank Type shows as Global Account.
     * @param globalAccount Global Account record.
     * @return Populated AccountWrapper row.
     */
    private static OverlayAssignmentController.AccountWrapper toGlobalAccountWrapper(Account globalAccount) {
        OverlayAssignmentController.AccountWrapper row = toAccountWrapper(globalAccount, null);
        if (String.isBlank(row.accountType)) {
            row.accountType = GLOBAL_ACCOUNT_DISPLAY_TYPE;
        }
        return row;
    }

    /**
     * @description Inserts new Account Team rows. Fields the running user cannot create are stripped.
     * @param membersToInsert New Account Team rows.
     */
    private static void insertAccountTeamMembers(List<AccountTeamMember> membersToInsert) {
        if (membersToInsert.isEmpty()) {
            return;
        }
        SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, membersToInsert);
        insert decision.getRecords();
    }

    /**
     * @description Reuses the Healthcare share helper. It only adds a manual AccountShare when no share
     *              exists yet. The Account Team row inserted just before already creates the Team share
     *              with the access levels on that row, so the access comes from the row, not from here.
     * @param accountList Accounts receiving the overlay assignment.
     * @param userIdSet Overlay users.
     */
    private static void createAccountShares(List<Account> accountList, Set<Id> userIdSet) {
        //GCL-390 : Tech Story - Hc x LS code dependency resolution
        OverlayAssignmentService.OverlayAssignmentDmlService dmlService = new OverlayAssignmentService.OverlayAssignmentDmlService();
        dmlService.createAccountShares(accountList, userIdSet); // GCL-390 : End
    }

    /**
     * @description Validates the overlay type sent by the pre-wizard.
     * @param overlayType Inside Sales or GAD.
     * @return The trimmed overlay type.
     */
    private static String requireOverlayType(String overlayType) {
        String resolvedType = overlayType == null ? null : overlayType.trim();
        if (String.isBlank(resolvedType) || !TEAM_MEMBER_ROLE_BY_OVERLAY_TYPE.containsKey(resolvedType)) {
            throw new OverlayAssignmentException('Select an overlay type: Inside Sales or GAD.');
        }
        return resolvedType;
    }

    /**
     * @description Active Life Sciences Sales users who hold the overlay type's permission set or group.
     * @param userIds Candidate user Ids.
     * @param overlayType Inside Sales or GAD.
     * @return Eligible user Ids.
     */
    private static Set<Id> selectEligibleOverlayUserIds(Set<Id> userIds, String overlayType) {
        if (UserSelector.getLifeSciencesSalesProfileIdForOverlay() == null) {
            throw new OverlayAssignmentException('Life Sciences Sales profile was not found.');
        }
        return UserSelector.selectActiveLifeSciencesUserIdsWithPermissionSets(
            userIds,
            PERMISSION_SETS_BY_OVERLAY_TYPE.get(overlayType),
            PERMISSION_SET_GROUPS_BY_OVERLAY_TYPE.get(overlayType)
        );
    }

    /**
     * @description Rejects the submit when any selected user is not eligible for the overlay type.
     * @param userIdSet User Ids submitted from the screen.
     * @param overlayType Inside Sales or GAD.
     */
    private static void requireEligibleOverlayUsers(Set<Id> userIdSet, String overlayType) {
        if (selectEligibleOverlayUserIds(userIdSet, overlayType).size() != userIdSet.size()) {
            throw new OverlayAssignmentException(
                'Select active Life Sciences Sales users with the ' + overlayType + ' permission set only.'
            );
        }
    }

    /**
     * @description GCL-79 - Logs an unexpected exception and returns a sanitized exception to throw to the caller.
     * @param userMessage User-safe message to log and surface to the LWC.
     * @param ex The exception caught by the calling method.
     * @return OverlayAssignmentException carrying the sanitized message.
     */
    private static OverlayAssignmentException logAndWrap(String userMessage, Exception ex) {
        Logger.setScenario(SCENARIO);
        Logger.error(userMessage + ' ' + ex.getMessage(), ex).addTag(LOGGER_TAG);
        return new OverlayAssignmentException(userMessage);
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
    private static List<OverlayAssignmentController.AccountWrapper> findAccountRows(
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

        List<OverlayAssignmentController.AccountWrapper> rows =
            new List<OverlayAssignmentController.AccountWrapper>();

        for (Account accountRecord : matchedAccounts) {
            if (!isSearchableAccountType(accountRecord.Type)) {
                continue;
            }

            OverlayAssignmentController.AccountWrapper row = toAccountWrapper(
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

        for (OrderLineContact__c orderLineContact : TASSelector.selectLifeSciencesTerritoriesByIds(
            territoryIds,
            LIFE_SCIENCES_CLASS_CODES
        )) {
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
        return AccountSelector.selectLifeSciencesAccountsByOracleAddress(oracleAddressIds, SEARCH_LIMIT);
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
        return AccountSelector.selectLifeSciencesCustomersByName(
            searchTerm,
            LIFE_SCIENCES_CLASS_CODES,
            SEARCH_LIMIT
        );
    }

    /**
     * @description GCL-79 - Customer accounts with a Life Sciences class code.
     * @return Customer accounts.
     */
    private static List<Account> queryCustomers() {
        return AccountSelector.selectLifeSciencesCustomers(LIFE_SCIENCES_CLASS_CODES, SEARCH_LIMIT);
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
        return AccountSelector.selectLifeSciencesAccountsByIds(accountIds);
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
        for (Account childAccount : AccountSelector.selectLifeSciencesChildAccounts(customerIds)) {
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
        OverlayAssignmentController.AccountWrapper row,
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
        return nameValue.contains(key) || numberValue.contains(key);
    }

    /**
     * @description GCL-79 - Maps an Account record, and its matching territory when one exists, into the LWC-facing row.
     * @param accountRecord Address-level or standalone Account record.
     * @param territory Matching Life Sciences territory row, or null when not resolved through a territory search.
     * @return Populated AccountWrapper row.
     */
    private static OverlayAssignmentController.AccountWrapper toAccountWrapper(
        Account accountRecord,
        OrderLineContact__c territory
    ) {
        OverlayAssignmentController.AccountWrapper row = new OverlayAssignmentController.AccountWrapper();
        row.accountId = accountRecord.Id;
        row.accountName = accountRecord.Name;
        row.accountNumber = accountRecord.AccountNumber;
        row.accountType = accountRecord.Type;

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
    private static List<OverlayAssignmentController.AccountWrapper> selectSummaryAccountRows(
        List<String> territoryIds,
        Set<Id> selectedAccountIdSet
    ) {
        List<OverlayAssignmentController.AccountWrapper> selectedRows =
            new List<OverlayAssignmentController.AccountWrapper>();

        for (OverlayAssignmentController.AccountWrapper accountRow : findAccountRows(null, null, territoryIds, null)) {
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
    private static List<OverlayAssignmentController.SummaryTerritoryWrapper> groupAccountRowsByTerritory(
        List<OverlayAssignmentController.AccountWrapper> selectedRows
    ) {
        Map<String, OverlayAssignmentController.SummaryTerritoryWrapper> summaryByKey =
            new Map<String, OverlayAssignmentController.SummaryTerritoryWrapper>();

        for (OverlayAssignmentController.AccountWrapper accountRow : selectedRows) {
            String summaryKey = String.isBlank(accountRow.territoryId) ? ACCOUNT_SEARCH_LABEL : accountRow.territoryId;

            if (!summaryByKey.containsKey(summaryKey)) {
                OverlayAssignmentController.SummaryTerritoryWrapper summaryRow =
                    new OverlayAssignmentController.SummaryTerritoryWrapper();
                summaryRow.territoryId = summaryKey;
                summaryRow.territoryDescription = String.isBlank(accountRow.territoryDescription)
                    ? summaryKey
                    : accountRow.territoryDescription;
                summaryRow.selectedAccounts = new List<OverlayAssignmentController.AccountWrapper>();
                summaryByKey.put(summaryKey, summaryRow);
            }
            summaryByKey.get(summaryKey).selectedAccounts.add(accountRow);
        }
        return summaryByKey.values();
    }

    /**
     * @description
     * GCL-79 - Builds the new Account Team Member records for submit, skipping any
     * Account-plus-User combination that already exists. Role and access levels come
     * from the overlay type.
     *
     * @param accountList Selected Customer or GPO accounts plus their cascaded child accounts.
     * @param userIdSet Overlay users selected on Step 3.
     * @param territoryByAddressId Life Sciences territories keyed by TAS Address Id. Empty when no territory is selected.
     * @param teamMemberRole Inside Sales or Global Account Director.
     * @param accessByAccountId Account, Contact, Opportunity, and Case access for each account.
     * @return New AccountTeamMember records to insert. Empty when every combination already exists.
     */
    private static List<AccountTeamMember> buildNewAccountTeamMembers(
        List<Account> accountList,
        Set<Id> userIdSet,
        Map<String, OrderLineContact__c> territoryByAddressId,
        String teamMemberRole,
        Map<Id, AccessLevels> accessByAccountId
    ) {
        Set<Id> accountIdSet = new Map<Id, Account>(accountList).keySet();
        if (accountIdSet.isEmpty() || userIdSet.isEmpty()) {
            return new List<AccountTeamMember>();
        }

        Set<String> existingKeys = new Set<String>();
        for (AccountTeamMember existingMember : AccountTeamMemberSelector.selectLifeSciencesByAccountsAndUsers(
            accountIdSet,
            userIdSet
        )) {
            existingKeys.add(existingMember.AccountId + '-' + existingMember.UserId);
        }

        Map<Id, OrderLineContact__c> territoryByParentId = territoryByParentAccountId(accountList, territoryByAddressId);
        List<AccountTeamMember> membersToInsert = new List<AccountTeamMember>();
        for (Account accountRecord : accountList) {
            OrderLineContact__c sourceTerritory = territoryForAccount(accountRecord, territoryByAddressId);
            if (sourceTerritory == null) {
                sourceTerritory = territoryByParentId.get(accountRecord.Id);
            }
            AccessLevels access = accessByAccountId.get(accountRecord.Id);
            for (Id userId : userIdSet) {
                if (existingKeys.contains(accountRecord.Id + '-' + userId)) {
                    continue;
                }
                AccountTeamMember member = new AccountTeamMember(
                    AccountId = accountRecord.Id,
                    UserId = userId,
                    TeamMemberRole = teamMemberRole,
                    AssignmentType__c = ASSIGNMENT_TYPE_SALESFORCE_ASSIGNED,
                    AccountAccessLevel = access.accountAccess,
                    ContactAccessLevel = access.contactAccess,
                    OpportunityAccessLevel = access.opportunityAccess,
                    CaseAccessLevel = access.caseAccess
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