/**
* @author PWC Developer
* @date 2026/06/09
*
* @group Overlay Assignment
*
* @description
* GC-3088 - Service layer for Overlay Assignment orchestration across Accounts, Opportunities, Users, and TAS records.
* GC-3352 - Overlay ATM insert stamps TerritoryCode__c, SalesCategoryCode__c, and SalesCategoryDescription__c
* from a source OrderLineContact__c when one exists for the Account Oracle address.
* GC-3345 - Overlay ATM insert sets OpportunityAccessLevel to Edit.
*/
public without sharing class OverlayAssignmentService {
    /**
* @description
* Constants used in the class.
*/
    public static final String SCENARIO = 'Overlay Assignment';
    public static final String LOGGER_TAG = 'OverlayAssignment';
    public static final String ACCOUNT_ACCESS_LEVEL_EDIT = 'Edit';
    public static final String OPPORTUNITY_ACCESS_LEVEL_READ = 'Read'; 
    public static final String OPPORTUNITY_ACCESS_LEVEL_EDIT = 'Edit'; 
    public static final String CASE_ACCESS_LEVEL_READ = 'Read';
    public static final String ACCOUNT_SEARCH_SUMMARY_ID = 'ACCOUNT_SEARCH';
    public static final String ACCOUNT_SEARCH_SUMMARY_LABEL = 'Account Search';
    public static final String TEAM_MEMBER_ROLE_SALES = 'Sales';
    public static final String ASSIGNMENT_TYPE_SALESFORCE_ASSIGNED = 'Salesforce Assigned';
    public static final Integer USER_SEARCH_LIMIT = 50;
    @TestVisible
    private static Boolean throwTestException = false;
    @TestVisible
    private static String forcedExceptionMethodName;

    public without sharing class OverlayAssignmentDmlService {
         /**
* @description
* Private helper method for createAccountTeamMembers.
* Creates account share records
* 
* @param accountList List of selected Accounts.
* @param userIdSet List of selected Overlay User Ids.
* @return Void.
* 
* @example
* OverlayAssignmentService.createAccountShares(accountIdSet, userIdSet);
*/
public void createAccountShares(List<Account> accountList, Set<Id> userIdSet) {
    Set<Id> accountIdSet = new Map<Id, Account>(accountList).keySet();
    Set<String> existingShareKeySet = new Set<String>();

    for (AccountShare accountShare : [
        SELECT AccountId, UserOrGroupId
        FROM AccountShare
        WHERE AccountId IN :accountIdSet
        AND UserOrGroupId IN :userIdSet
    ]) {
        existingShareKeySet.add(accountShare.AccountId + '-' + accountShare.UserOrGroupId);
    }

    List<AccountShare> accountShareList = new List<AccountShare>();

    for (Id accountId : accountIdSet) {
        for (Id userId : userIdSet) {
            String key = accountId + '-' + userId;

            if (!existingShareKeySet.contains(key)) {
                accountShareList.add(new AccountShare(
                    AccountId = accountId,
                    UserOrGroupId = userId,
                    AccountAccessLevel = 'Edit',
                    OpportunityAccessLevel = 'Read',
                    CaseAccessLevel = 'Read',
                    RowCause = Schema.AccountShare.RowCause.Manual
                ));
            }
        }
    }

    if (!accountShareList.isEmpty()) {
        insert accountShareList;
    }
}
    }

    /**
* @description
* GC-3088 - Helper method for searchTerritories.
* Searches TAS territory records for matching Territory ID, Description, or Number.
* 
* @param searchKey User-entered search text.
* @return List<OverlayAssignmentController.TerritoryWrapper> Matching territories for selection.
* 
* @example
* OverlayAssignmentService.searchTerritories(searchKey);
*/
    public static List<OverlayAssignmentController.TerritoryWrapper> searchTerritories(String searchKey) {
        try{
            if (Test.isRunningTest() && throwTestException) {
                throw new QueryException('Forced test exception');
            }
            List<OrderLineContact__c> orderLineContactList = TASSelector.selectByTerritorySearch(searchKey);
            Map<String, OverlayAssignmentController.TerritoryWrapper> territoryByIdMap =
                new Map<String, OverlayAssignmentController.TerritoryWrapper>();
            
            for (OrderLineContact__c orderLineContact : orderLineContactList) {
                if (String.isBlank(orderLineContact.TerritoryID__c)) {
                    continue;
                }
                
                if (!territoryByIdMap.containsKey(orderLineContact.TerritoryID__c)) {
                    OverlayAssignmentController.TerritoryWrapper territoryWrapper =
                        new OverlayAssignmentController.TerritoryWrapper();
                    territoryWrapper.territoryId = orderLineContact.TerritoryID__c;
                    territoryWrapper.territoryDescription = orderLineContact.TerritoryDescription__c;
                    territoryWrapper.tasAddressId = orderLineContact.TASAddressId__c;
                    territoryWrapper.tasZone = orderLineContact.TASZone__c;
                    territoryWrapper.regionName = orderLineContact.RegionName__c;
                    territoryByIdMap.put(orderLineContact.TerritoryID__c, territoryWrapper);
                }
            }
            
            return territoryByIdMap.values();
        }catch (Exception ex) {
            Logger.error('Error searching territories', ex);
            throw new OverlayAssignmentException('Unable to search territories.');
        } finally {
            Logger.saveLog();
        }
    }
    
    /**
* @description
* GC-3088 -  Searches TAS territory records for matching Territory ID, Description, or Number.
* 
* @param accountSearchKey account name/number search key
* @param accountType account type selected if any
* @param territoryIds Territory ids selected if any
* @return Matching accounts based on search account section.
* 
* @example
* OverlayAssignmentService.searchAccounts(accountSearchKey, accountType, territoryIds);
*/
    public static List<OverlayAssignmentController.AccountWrapper> searchAccounts(
        String accountSearchKey,
        String accountType,
        List<String> territoryIds
    ) {
        try{
            if (throwTestException) {
                throw new QueryException('Forced test exception');
            }
            
            Boolean hasTerritoryFilter = territoryIds != null && !territoryIds.isEmpty();
            
            if (hasTerritoryFilter) {
                List<OverlayAssignmentController.AccountWrapper> territoryAccountWrapperList = getAccountsForTerritories(territoryIds);
                return filterAccountWrappers(
                    territoryAccountWrapperList,
                    accountSearchKey,
                    accountType,
                    new Set<Id>()
                );
            }
            
            List<Account> accountList = AccountSelector.selectBySearchCriteria(accountSearchKey, accountType);
            return buildAccountWrappersFromAccounts(accountList, null, null);
        }catch (Exception ex) {
            Logger.error('Error searching accounts', ex);
            throw new OverlayAssignmentException('Unable to search accounts.');
        } finally {
            Logger.saveLog();
        }
    }
    
    /**
* @description
* GC-3088 - Helper method for retrieveAccounts.
* Retrieves Accounts by flexible Territory, Account Name/Number, Account Type, and selected Account filters.
* 
* @param territoryIds Selected Territory IDs.
* @param accountSearchKey Account Name or Account Number entered by the user.
* @param accountType Account Type selected by the user.
* @param selectedSearchAccountIds Account IDs selected from Step 1 Account search results.
* @return Account result used by LWC client-side pagination.* 
* @example
* OverlayAssignmentService.retrieveAccounts(territoryIds, accountSearchKey, accountType, selectedSearchAccountIds);
*/
    public static OverlayAssignmentController.AccountPageResult retrieveAccounts(
        List<String> territoryIds,
        String accountSearchKey,
        String accountType,
        List<Id> selectedSearchAccountIds
    ) {
        try{
            validateAtLeastOneSearchCriterion(territoryIds, accountSearchKey, accountType, selectedSearchAccountIds);
            List<OverlayAssignmentController.AccountWrapper> accountWrapperList = getAccountsForSearch(
                territoryIds,
                accountSearchKey,
                accountType,
                selectedSearchAccountIds
            );
            
            OverlayAssignmentController.AccountPageResult result = new OverlayAssignmentController.AccountPageResult();
            result.accounts = accountWrapperList;
            result.totalRecords = accountWrapperList.size();
            result.pageNumber = 1;
            result.pageSize = accountWrapperList.size();
            result.totalPages = 1;
            return result;
        }catch (Exception ex) {
            Logger.error('Error retrieving accounts', ex);
            throw new OverlayAssignmentException('Unable to Retrieve Accounts.');
        } finally {
            Logger.saveLog();
        }
    }
    
    /**
* @description
* GC-3088 - Helper method for searchOverlayUsers.
* Searches active users for overlay assignment.
* 
* @param searchKey User-entered search text.
* @return List<OverlayAssignmentController.UserWrapper>  Matching overlay users.
* 
* @example
* OverlayAssignmentService.searchOverlayUsers(searchKey);
*/
    public static List<OverlayAssignmentController.UserWrapper> searchOverlayUsers(String searchKey) {
        try {
            if (throwTestException) {
                throw new QueryException('Forced test exception');
            }
            List<User> userList = UserSelector.selectActiveUsersBySearch(searchKey);
            
            List<OverlayAssignmentController.UserWrapper> userWrapperList = new List<OverlayAssignmentController.UserWrapper>();
            
            if(userList == null || userlist.isEmpty()){
                Logger.warn('OverlayAssignmentService.searchOverlayUsers: userlist is null or empty');
                return null;
            }
            
            for (User userRecord : userList) {
                OverlayAssignmentController.UserWrapper userWrapper = new OverlayAssignmentController.UserWrapper();
                userWrapper.userId = userRecord.Id;
                userWrapper.userName = userRecord.Name;
                userWrapper.email = userRecord.Email;
                userWrapper.phone = userRecord.Phone;
                userWrapper.role = userRecord.UserRole == null ? null : userRecord.UserRole.Name;
                userWrapper.title = userRecord.Title;
                userWrapper.country = userRecord.Country;
                userWrapper.managerName = userRecord.Manager == null ? null : userRecord.Manager.Name;
                userWrapperList.add(userWrapper);
            }
            
            return userWrapperList;
        }catch (Exception ex) {
            Logger.error('Error searching overlay users', ex);
            throw new OverlayAssignmentException('Unable to search overlay users.');
        } finally {
            Logger.saveLog();
        }
    }
    
    /**
* @description
* GC-3088 - Helper method for getAssignmentSummary.
* Builds selected account summary grouped by Territory or Account Search.
* 
* @param territoryIds Selected Territory IDs.
* @param selectedAccountIds Account IDs selected on the Account confirmation step.
* @return Territory/account-search summary DTOs.* 
* @example
* OverlayAssignmentService.getAssignmentSummary(territoryIds, selectedAccountIds);
*/
    public static List<OverlayAssignmentController.SummaryTerritoryWrapper> getAssignmentSummary(
        List<String> territoryIds,
        List<Id> selectedAccountIds
    ) {
        try{
            Set<Id> selectedAccountIdSet = buildIdSet(selectedAccountIds);
            
            if (selectedAccountIdSet.isEmpty()) {
                throw new AuraHandledException('No accounts selected for overlay assignment.');
            }
            
            List<OverlayAssignmentController.AccountWrapper> accountWrapperList = buildSummaryAccountWrappers(
                territoryIds,
                selectedAccountIdSet
            );
            
            Map<String, OverlayAssignmentController.SummaryTerritoryWrapper> summaryByKeyMap =
                new Map<String, OverlayAssignmentController.SummaryTerritoryWrapper>();
            
            for (OverlayAssignmentController.AccountWrapper accountWrapper : accountWrapperList) {
                String summaryKey = String.isBlank(accountWrapper.territoryId)
                    ? ACCOUNT_SEARCH_SUMMARY_ID
                    : accountWrapper.territoryId;
                
                if (!summaryByKeyMap.containsKey(summaryKey)) {
                    OverlayAssignmentController.SummaryTerritoryWrapper summaryWrapper =
                        new OverlayAssignmentController.SummaryTerritoryWrapper();
                    summaryWrapper.territoryId = String.isBlank(accountWrapper.territoryId)
                        ? ACCOUNT_SEARCH_SUMMARY_LABEL
                        : accountWrapper.territoryId;
                    summaryWrapper.territoryDescription = String.isBlank(accountWrapper.territoryDescription)
                        ? ACCOUNT_SEARCH_SUMMARY_LABEL
                        : accountWrapper.territoryDescription;
                    summaryWrapper.selectedAccounts = new List<OverlayAssignmentController.AccountWrapper>();
                    summaryByKeyMap.put(summaryKey, summaryWrapper);
                }
                
                summaryByKeyMap.get(summaryKey).selectedAccounts.add(accountWrapper);
            }
            
            return summaryByKeyMap.values();
        }catch (Exception ex) {
            Logger.error('Error getting assignment summary', ex);
            throw new OverlayAssignmentException('Error getting assignment summary');
        } finally {
            Logger.saveLog();
        }
    }
    
    /**
* @description
* Helper method for submitOverlayAssignments.
* GC-3088 - Creates overlay Account Team and territory-based TAS writeback records.
* GC-3180 - Cascades Account Team access to child and affiliated accounts.
* GC-3180 - Opportunity Team creation removed.
* GC-3352 - Loads source Order Line Contacts once and reuses them for ATM coverage fields and TAS writeback.
* 
* @param territoryIds Selected Territory IDs.
* @param selectedAccountIds Selected Account IDs from Step 2.
* @param userIds Selected overlay User IDs.
* @return Void.
* 
* @example
* OverlayAssignmentService.submitOverlayAssignments(territoryIds, selectedAccountIds, userIds);
*/
    public static void submitOverlayAssignments(
        List<String> territoryIds,
        List<Id> selectedAccountIds,
        List<Id> userIds
    ) {
        Savepoint savepointValue = Database.setSavepoint();
        
        try {
            validateUserIds(userIds);
            Set<Id> selectedAccountIdSet = buildIdSet(selectedAccountIds);
            Set<Id> userIdSet = buildIdSet(userIds);
            
            if (selectedAccountIdSet.isEmpty()) {
                throw new AuraHandledException('No accounts selected for overlay assignment.');
            }
            
            // List<Account> accountList = AccountSelector.selectByIds(selectedAccountIdSet);
            // Set<Id> accountIdSet = new Map<Id, Account>(accountList).keySet();
            //GC-3180 / GC-3305 - START
            List<Account> selectedAccountList = AccountSelector.selectByIds(selectedAccountIdSet);
            Set<Id> expandedAccountIdSet = resolveCascadeAccountIds(selectedAccountList, territoryIds);
            List<Account> accountList = AccountSelector.selectByIds(expandedAccountIdSet);
			//GC-3180 / GC-3305 - END
            // GC-3352 - One source-OLC query for ATM coverage fields and TAS writeback.
            Map<String, OrderLineContact__c> sourceOlcByTasAddressIdMap =
                loadSourceOlcByTasAddressIdMap(accountList, territoryIds);

            createAccountTeamMembers(accountList, userIdSet, sourceOlcByTasAddressIdMap);

            // GC-3180 - Opportunity Team creation removed per story:
            // createOpportunityTeamMembers(accountIdSet, userIdSet);

            if (territoryIds != null && !territoryIds.isEmpty()) {
                createTerritoryTasWritebackRecords(accountList, userIdSet, sourceOlcByTasAddressIdMap);
            } else {
                Logger.setScenario(SCENARIO);
                Logger.info('Skipped TAS writeback because no territory was selected for this overlay assignment.')
                    .addTag(LOGGER_TAG);
            }
        } catch (Exception exceptionValue) {
            Database.rollback(savepointValue);
            Logger.setScenario(SCENARIO);
            Logger.error('Overlay assignment submit failed. ' + exceptionValue.getMessage()).addTag(LOGGER_TAG);
            throw exceptionValue;
        }
    }
    
    /**
* @description
* GC-3088 - Searches and fetches accounts based on selected search criteria on Account search screen.
* 
* @param territoryIds Selected Territory IDs.
* @param accountSearchKey account search key.
* @param accountType account type if selected.
* @param selectedSearchAccountIds selected account ids from step 1
* @return List<OverlayAssignmentController.AccountWrapper> - Queries and fetches accounts.
* 
* @example
* OverlayAssignmentService.getAccountsForSearch(territoryIds, accountSearchKey, accountType, selectedSearchAccountIds);
*/
    private static List<OverlayAssignmentController.AccountWrapper> getAccountsForSearch(
        List<String> territoryIds,
        String accountSearchKey,
        String accountType,
        List<Id> selectedSearchAccountIds
    ) {
        try{
            throwForcedTestExceptionIfRequested('getAccountsForSearch');
            Boolean hasTerritoryFilter = territoryIds != null && !territoryIds.isEmpty();
            Set<Id> selectedSearchAccountIdSet = buildIdSet(selectedSearchAccountIds);
            List<OverlayAssignmentController.AccountWrapper> accountWrapperList;
            
            if (hasTerritoryFilter) {
                accountWrapperList = getAccountsForTerritories(territoryIds);
                accountWrapperList = filterAccountWrappers(accountWrapperList, accountSearchKey, accountType, selectedSearchAccountIdSet);
            } else {
                List<Account> accountList = selectedSearchAccountIdSet.isEmpty()
                    ? AccountSelector.selectBySearchCriteria(accountSearchKey, accountType)
                    : AccountSelector.selectByIds(selectedSearchAccountIdSet);
                accountWrapperList = buildAccountWrappersFromAccounts(accountList, accountSearchKey, accountType);
            }
            
            accountWrapperList.sort();
            return accountWrapperList;
        }catch (Exception ex) {
            Logger.error('Fetching account failed ', ex);
            throw new OverlayAssignmentException('Fetching account failed');
        } finally {
            Logger.saveLog();
        }
    }
    
    /**
    * @description
    * GC-3088 - Private helper method for retrieveAccounts.
    * Fetches Accounts for selected territories
    *
    * GC-3112 - Resolves Accounts via Account.OracleAddressId__c instead of Address object.
    * GC-3180 - Resolves child Address accounts internally and returns Parent plus affiliated IDN/GPO accounts.
    *
    * @param territoryIds Selected Territory IDs.
    * @return List<OverlayAssignmentController.AccountWrapper> - Queries and fetches accounts related to the selected territories.
    *
    * @example
    * OverlayAssignmentService.getAccountsForTerritories(territoryIds);
    */
    private static List<OverlayAssignmentController.AccountWrapper> getAccountsForTerritories(List<String> territoryIds) {
        try{
            throwForcedTestExceptionIfRequested('getAccountsForTerritories');
            //GC-3180-START
            Set<String> territoryIdSet = buildStringSet(territoryIds);
            List<OrderLineContact__c> orderLineContactList = TASSelector.selectByTerritoryIds(territoryIdSet);

            if (orderLineContactList.isEmpty()) {
                return new List<OverlayAssignmentController.AccountWrapper>();
            }

            Set<String> oracleAddressKeySet = new Set<String>();

            for (OrderLineContact__c orderLineContact : orderLineContactList) {
                if (String.isNotBlank(orderLineContact.TASAddressId__c)) {
                    oracleAddressKeySet.add(orderLineContact.TASAddressId__c.trim());
                }
            }

            Map<String, Account> accountByOracleAddressIdMap =
                AccountSelector.selectAccountsByOracleAddressId(oracleAddressKeySet);
            Map<Id, OrderLineContact__c> orderLineContactByChildAccountId = new Map<Id, OrderLineContact__c>();
            Map<Id, Account> childAccountByIdMap = new Map<Id, Account>();
            Set<Id> parentAccountIdSet = new Set<Id>();

            for (OrderLineContact__c orderLineContact : orderLineContactList) {
                if (String.isBlank(orderLineContact.TASAddressId__c)) {
                    continue;
                }

                Account childAccount = accountByOracleAddressIdMap.get(orderLineContact.TASAddressId__c.trim());

                if (childAccount == null || orderLineContactByChildAccountId.containsKey(childAccount.Id)) {
                    continue;
                }

                childAccountByIdMap.put(childAccount.Id, childAccount);
                orderLineContactByChildAccountId.put(childAccount.Id, orderLineContact);

                if (childAccount.ParentId != null) {
                    parentAccountIdSet.add(childAccount.ParentId);
                }
            }

            Map<Id, OrderLineContact__c> orderLineContactByParentAccountId = new Map<Id, OrderLineContact__c>();

            for (Id childAccountId : orderLineContactByChildAccountId.keySet()) {
                Account childAccount = childAccountByIdMap.get(childAccountId);

                if (childAccount == null || childAccount.ParentId == null
                    || !parentAccountIdSet.contains(childAccount.ParentId)
                    || orderLineContactByParentAccountId.containsKey(childAccount.ParentId)) {
                    continue;
                }

                orderLineContactByParentAccountId.put(
                    childAccount.ParentId,
                    orderLineContactByChildAccountId.get(childAccountId)
                );
            }

            Map<Id, OverlayAssignmentController.AccountWrapper> accountWrapperByAccountIdMap =
                new Map<Id, OverlayAssignmentController.AccountWrapper>();

            for (Account accountRecord : AccountSelector.selectByIds(parentAccountIdSet)) {
                if (accountWrapperByAccountIdMap.containsKey(accountRecord.Id)) {
                    continue;
                }

                OrderLineContact__c orderLineContact = orderLineContactByParentAccountId.get(accountRecord.Id);
                OverlayAssignmentController.AccountWrapper accountWrapper = new OverlayAssignmentController.AccountWrapper();
                accountWrapper.accountId = accountRecord.Id;
                accountWrapper.accountName = accountRecord.Name;
                accountWrapper.accountNumber = accountRecord.AccountNumber;
                accountWrapper.accountType = accountRecord.Type;

                if (orderLineContact != null) {
                    accountWrapper.territoryId = orderLineContact.TerritoryID__c;
                    accountWrapper.territoryDescription = orderLineContact.TerritoryDescription__c;
                }

                accountWrapperByAccountIdMap.put(accountRecord.Id, accountWrapper);
            }

            Set<Id> accountIdsForAffiliationLookup = new Set<Id>();
            accountIdsForAffiliationLookup.addAll(orderLineContactByChildAccountId.keySet());
            accountIdsForAffiliationLookup.addAll(parentAccountIdSet);
            Set<Id> gpoIdnAccountIdSet = new Set<Id>();
            Map<Id, OrderLineContact__c> orderLineContactByGpoIdnAccountId = new Map<Id, OrderLineContact__c>();

            for (AccountAccountRelationship__c affiliationRecord :
                AccountAccountRelationshipSelector.selectGpoIdnAffiliationsByAccountIds(accountIdsForAffiliationLookup)) {
                Id gpoIdnAccountId = affiliationRecord.ParentAccount__c;
                String parentAccountType = affiliationRecord.ParentAccount__r.Type;

                if (gpoIdnAccountId == null || (parentAccountType != 'GPO' && parentAccountType != 'IDN')) {
                    continue;
                }

                gpoIdnAccountIdSet.add(gpoIdnAccountId);

                if (orderLineContactByGpoIdnAccountId.containsKey(gpoIdnAccountId)) {
                    continue;
                }

                OrderLineContact__c orderLineContact =
                    orderLineContactByChildAccountId.get(affiliationRecord.ChildAccount__c);

                if (orderLineContact == null) {
                    orderLineContact = orderLineContactByParentAccountId.get(affiliationRecord.ChildAccount__c);
                }

                if (orderLineContact != null) {
                    orderLineContactByGpoIdnAccountId.put(gpoIdnAccountId, orderLineContact);
                }
            }

            for (Account accountRecord : AccountSelector.selectByIds(gpoIdnAccountIdSet)) {
                if (accountRecord.Type != 'GPO' && accountRecord.Type != 'IDN') {
                    continue;
                }

                if (accountWrapperByAccountIdMap.containsKey(accountRecord.Id)) {
                    continue;
                }

                OrderLineContact__c orderLineContact = orderLineContactByGpoIdnAccountId.get(accountRecord.Id);
                OverlayAssignmentController.AccountWrapper accountWrapper = new OverlayAssignmentController.AccountWrapper();
                accountWrapper.accountId = accountRecord.Id;
                accountWrapper.accountName = accountRecord.Name;
                accountWrapper.accountNumber = accountRecord.AccountNumber;
                accountWrapper.accountType = accountRecord.Type;

                if (orderLineContact != null) {
                    accountWrapper.territoryId = orderLineContact.TerritoryID__c;
                    accountWrapper.territoryDescription = orderLineContact.TerritoryDescription__c;
                }

                accountWrapperByAccountIdMap.put(accountRecord.Id, accountWrapper);
            }
			//GC-3180-START
            List<OverlayAssignmentController.AccountWrapper> accountWrapperList = accountWrapperByAccountIdMap.values();
            accountWrapperList.sort();
            return accountWrapperList;
        }catch (Exception ex) {
            Logger.error('Fetching account territories failed ', ex);
            throw new OverlayAssignmentException('Fetching account territories failed');
        } finally {
            Logger.saveLog();
        }
    }

   /**
    * @description
    * GC-3180 / GC-3305 - Expands selected accounts for Account Team cascade.
    * GC-3305 - Territory search: child Address accounts must match selected Territory Ids (via OLC).
    * GC-3305 - Account search: all child Address accounts; IDN/GPO also expand AAR Customers to Addresses.
    *
    * @param selectedAccountList Accounts selected in the Overlay Assignment UI.
    * @param territoryIds Territory Ids from territory search; empty/null means account-search path (AC2).
    * @return Deduped Account Ids including cascade targets.
    */
    private static Set<Id> resolveCascadeAccountIds(
        List<Account> selectedAccountList,
        List<String> territoryIds
    ) {
        try {
            throwForcedTestExceptionIfRequested('resolveCascadeAccountIds');
            Set<Id> expandedAccountIdSet = new Set<Id>();
            Set<Id> customerAccountIdSet = new Set<Id>();
            Set<Id> gpoIdnAccountIdSet = new Set<Id>();

            if (selectedAccountList == null || selectedAccountList.isEmpty()) {
                return expandedAccountIdSet;
            }

            Boolean filterByTerritory = territoryIds != null && !territoryIds.isEmpty();
            Set<String> territoryMatchedOracleAddressIds = filterByTerritory
                ? collectOracleAddressIdsForTerritories(territoryIds)
                : null;

            for (Account accountRecord : selectedAccountList) {
                expandedAccountIdSet.add(accountRecord.Id);

                if (accountRecord.Type == 'GPO' || accountRecord.Type == 'IDN') {
                    gpoIdnAccountIdSet.add(accountRecord.Id);
                } else if (accountRecord.Type != 'Address') {
                    // GC-3305 - Customer (and other non-Address) selections cascade ParentId children.
                    customerAccountIdSet.add(accountRecord.Id);
                }
            }

            addCascadedChildAccountIds(
                expandedAccountIdSet,
                customerAccountIdSet,
                territoryMatchedOracleAddressIds
            );

            Set<Id> affiliationChildAccountIdSet = new Set<Id>();
            for (AccountAccountRelationship__c affiliationRecord :
                AccountAccountRelationshipSelector.selectMembersByParentIds(gpoIdnAccountIdSet)) {
                if (affiliationRecord.ChildAccount__c != null) {
                    affiliationChildAccountIdSet.add(affiliationRecord.ChildAccount__c);
                }
            }

            if (!affiliationChildAccountIdSet.isEmpty()) {
                Map<Id, Account> affiliationAccountById = new Map<Id, Account>(
                    AccountSelector.selectByIds(affiliationChildAccountIdSet)
                );
                Set<Id> affiliatedCustomerAccountIdSet = new Set<Id>();

                for (Id affiliationChildAccountId : affiliationChildAccountIdSet) {
                    Account affiliationAccount = affiliationAccountById.get(affiliationChildAccountId);
                    if (affiliationAccount == null) {
                        continue;
                    }

                    if (affiliationAccount.Type == 'Address') {
                        if (
                            !filterByTerritory ||
                            isTerritoryMatchedAddress(affiliationAccount, territoryMatchedOracleAddressIds)
                        ) {
                            expandedAccountIdSet.add(affiliationAccount.Id);
                        }
                    } else if (
                        affiliationAccount.Type != 'GPO' &&
                        affiliationAccount.Type != 'IDN'
                    ) {
                        expandedAccountIdSet.add(affiliationAccount.Id);
                        affiliatedCustomerAccountIdSet.add(affiliationAccount.Id);
                    } else {
                        expandedAccountIdSet.add(affiliationAccount.Id);
                    }
                }

                // GC-3305 - Address children under affiliated Customer accounts.
                addCascadedChildAccountIds(
                    expandedAccountIdSet,
                    affiliatedCustomerAccountIdSet,
                    territoryMatchedOracleAddressIds
                );
            }

            return expandedAccountIdSet;
        } catch (Exception ex) {
            Logger.error('Resolving cascade account Ids failed', ex);
            throw new OverlayAssignmentException('Resolving cascade account Ids failed');
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description
     * GC-3305 - Collects Oracle / TAS address keys for OrderLineContact rows on the given territories.
     *
     * @param territoryIds Selected Territory Ids.
     * @return Trimmed TASAddressId__c values for territory matching.
     */
    private static Set<String> collectOracleAddressIdsForTerritories(List<String> territoryIds) {
        Set<String> oracleAddressIdSet = new Set<String>();
        Set<String> territoryIdSet = buildStringSet(territoryIds);

        for (OrderLineContact__c orderLineContact : TASSelector.selectByTerritoryIds(territoryIdSet)) {
            if (String.isNotBlank(orderLineContact.TASAddressId__c)) {
                oracleAddressIdSet.add(orderLineContact.TASAddressId__c.trim());
            }
        }

        return oracleAddressIdSet;
    }

    /**
     * @description
     * GC-3305 - Adds ParentId child accounts; when territoryMatchedOracleAddressIds is set,
     *              only children whose OracleAddressId__c matches a territory OLC are included.
     *
     * @param expandedAccountIdSet Output set of cascade Account Ids.
     * @param parentAccountIdSet Parent Customer Account Ids.
     * @param territoryMatchedOracleAddressIds Null for AC2 (all children); non-null for AC1 filter.
     */
    private static void addCascadedChildAccountIds(
        Set<Id> expandedAccountIdSet,
        Set<Id> parentAccountIdSet,
        Set<String> territoryMatchedOracleAddressIds
    ) {
        if (parentAccountIdSet == null || parentAccountIdSet.isEmpty()) {
            return;
        }

        for (Account childAccount : AccountSelector.selectChildAccountsByParentIds(parentAccountIdSet)) {
            if (
                territoryMatchedOracleAddressIds != null &&
                !isTerritoryMatchedAddress(childAccount, territoryMatchedOracleAddressIds)
            ) {
                continue;
            }

            expandedAccountIdSet.add(childAccount.Id);
        }
    }

    /**
     * @description
     * GC-3305 - True when the Account OracleAddressId__c is present in the territory OLC key set.
     *
     * @param accountRecord Child / Address Account.
     * @param territoryMatchedOracleAddressIds Oracle address keys for selected territories.
     * @return True when the account matches a selected territory.
     */
    private static Boolean isTerritoryMatchedAddress(
        Account accountRecord,
        Set<String> territoryMatchedOracleAddressIds
    ) {
        if (
            accountRecord == null ||
            territoryMatchedOracleAddressIds == null ||
            territoryMatchedOracleAddressIds.isEmpty() ||
            String.isBlank(accountRecord.OracleAddressId__c)
        ) {
            return false;
        }

        return territoryMatchedOracleAddressIds.contains(accountRecord.OracleAddressId__c.trim());
    }

    /**
* @description
* GC-3088 - Filters AccountWrapper records based on selected accounts, account type, and search criteria.
*
* @param accountWrapperList List of AccountWrapper records to be filtered.
* @param accountSearchKey Search keyword used to match Account Name or Account Number.
* @param accountType Selected Account Type used as a filter criterion.
* @param selectedSearchAccountIdSet Set of Account IDs selected from account search results.
* @return List<OverlayAssignmentController.AccountWrapper> - Filtered list of AccountWrapper records matching the provided criteria.
*
* @example
* List<OverlayAssignmentController.AccountWrapper> filteredAccounts =
*     filterAccountWrappers(accountWrapperList, accountSearchKey, accountType, selectedSearchAccountIdSet);
*/
    private static List<OverlayAssignmentController.AccountWrapper> filterAccountWrappers(
        List<OverlayAssignmentController.AccountWrapper> accountWrapperList,
        String accountSearchKey,
        String accountType,
        Set<Id> selectedSearchAccountIdSet
    ) {
        try{
            throwForcedTestExceptionIfRequested('filterAccountWrappers');
            List<OverlayAssignmentController.AccountWrapper> filteredAccountWrapperList =
                new List<OverlayAssignmentController.AccountWrapper>();
            String normalizedSearchKey = String.isBlank(accountSearchKey) ? null : accountSearchKey.trim().toLowerCase();
            
            for (OverlayAssignmentController.AccountWrapper accountWrapper : accountWrapperList) {
                if (!selectedSearchAccountIdSet.isEmpty() && !selectedSearchAccountIdSet.contains(accountWrapper.accountId)) {
                    continue;
                }
                
                if (String.isNotBlank(accountType) && accountWrapper.accountType != accountType) {
                    continue;
                }
                
                if (String.isNotBlank(normalizedSearchKey)
                    && !containsIgnoreCase(accountWrapper.accountName, normalizedSearchKey)
                    && !containsIgnoreCase(accountWrapper.accountNumber, normalizedSearchKey)) {
                        continue;
                    }
                
                filteredAccountWrapperList.add(accountWrapper);
            }
            
            return filteredAccountWrapperList;
        }catch (Exception ex) {
            Logger.error('Filtering accounts failed', ex);
            throw new OverlayAssignmentException('Filtering accounts failed');
        } finally {
            Logger.saveLog();
        }
    }
    
    /**
* @description
* GC-3088 - Performs a case-insensitive check to determine whether the source string contains the specified search keyword.
*
* @param sourceValue Source string to be evaluated.
* @param normalizedSearchKey Lowercase search keyword used for comparison.
* @return Boolean - Returns true if the source string contains the search keyword; otherwise, returns false.
*
* @example
* Boolean isMatch = containsIgnoreCase(accountWrapper.accountName, normalizedSearchKey);
*/
    private static Boolean containsIgnoreCase(String sourceValue, String normalizedSearchKey) {
        return sourceValue != null && sourceValue.toLowerCase().contains(normalizedSearchKey);
    }
    
    /**
* @description
* GC-3088 - Builds AccountWrapper records from Account records and prepares the data for display in the overlay assignment UI.
*
* @param accountList List of Account records used to construct AccountWrapper records.
* @param accountSearchKey Search keyword used during account retrieval.
* @param accountType Selected Account Type used during account retrieval.
* @return List<OverlayAssignmentController.AccountWrapper> - Sorted list of AccountWrapper records created from the provided Account records.
*
* @example
* List<OverlayAssignmentController.AccountWrapper> accountWrappers =
*     buildAccountWrappersFromAccounts(accountList, accountSearchKey, accountType);
*/
    private static List<OverlayAssignmentController.AccountWrapper> buildAccountWrappersFromAccounts(
        List<Account> accountList,
        String accountSearchKey,
        String accountType
    ) {
        try{
            throwForcedTestExceptionIfRequested('buildAccountWrappersFromAccounts');
            List<OverlayAssignmentController.AccountWrapper> accountWrapperList =
                new List<OverlayAssignmentController.AccountWrapper>();
            
            for (Account accountRecord : accountList) {
                OverlayAssignmentController.AccountWrapper accountWrapper = new OverlayAssignmentController.AccountWrapper();
                accountWrapper.accountId = accountRecord.Id;
                accountWrapper.accountName = accountRecord.Name;
                accountWrapper.accountNumber = accountRecord.AccountNumber;
                accountWrapper.accountType = accountRecord.Type;
                accountWrapper.territoryId = null;
                accountWrapper.territoryDescription = null;
                accountWrapperList.add(accountWrapper);
            }
            
            accountWrapperList.sort();
            return accountWrapperList;
        }catch (Exception ex) {
            Logger.error('Building account wrapper failed', ex);
            throw new OverlayAssignmentException('Building account wrapper failed');
        } finally {
            Logger.saveLog();
        }
    }
    
    /**
* @description
* GC-3088 - Builds the summary list of AccountWrapper records for selected accounts by combining
* territory-based accounts and account search selections that are not associated with the selected territories.
*
* @param territoryIds List of selected Territory IDs.
* @param selectedAccountIdSet Set of Account IDs selected by the user.
* @return List<OverlayAssignmentController.AccountWrapper> - Sorted list of AccountWrapper records representing the selected accounts.
*
* @example
* List<OverlayAssignmentController.AccountWrapper> summaryAccounts =
*     buildSummaryAccountWrappers(territoryIds, selectedAccountIdSet);
*/
    private static List<OverlayAssignmentController.AccountWrapper> buildSummaryAccountWrappers(
        List<String> territoryIds,
        Set<Id> selectedAccountIdSet
    ) {
        try{
            throwForcedTestExceptionIfRequested('buildSummaryAccountWrappers');
            List<OverlayAssignmentController.AccountWrapper> summaryAccountWrapperList = new List<OverlayAssignmentController.AccountWrapper>();
            
            if (territoryIds != null && !territoryIds.isEmpty()) {
                for (OverlayAssignmentController.AccountWrapper accountWrapper : getAccountsForTerritories(territoryIds)) {
                    if (selectedAccountIdSet.contains(accountWrapper.accountId)) {
                        summaryAccountWrapperList.add(accountWrapper);
                    }
                }
            }
            
            Set<Id> alreadyAddedAccountIdSet = new Set<Id>();
            
            for (OverlayAssignmentController.AccountWrapper accountWrapper : summaryAccountWrapperList) {
                alreadyAddedAccountIdSet.add(accountWrapper.accountId);
            }
            
            Set<Id> accountSearchOnlyIdSet = new Set<Id>();
            
            for (Id accountId : selectedAccountIdSet) {
                if (!alreadyAddedAccountIdSet.contains(accountId)) {
                    accountSearchOnlyIdSet.add(accountId);
                }
            }
            
            if (!accountSearchOnlyIdSet.isEmpty()) {
                summaryAccountWrapperList.addAll(
                    buildAccountWrappersFromAccounts(AccountSelector.selectByIds(accountSearchOnlyIdSet), null, null)
                );
            }
            
            summaryAccountWrapperList.sort();
            return summaryAccountWrapperList;
        }catch (Exception ex) {
            Logger.error('Building account summary wrapper failed', ex);
            throw new OverlayAssignmentException('Building account summary wrapper failed');
        } finally {
            Logger.saveLog();
        }
    }
    
    /**
* @description
* GC-3088 - Creates TAS Writeback records for the provided accounts by matching
* assignment source data from Order Line Contacts.
* GC-3112 - Uses Account.OracleAddressId__c instead of Address records for TAS address resolution.
* GC-3352 - Uses the source OLC map already loaded in submitOverlayAssignments (no second query).
*
* @param accountList List of Account records for which TAS Writeback records will be created.
* @param userIdSet Set of User IDs associated with the assignment process.
* @param orderLineContactByTasAddressIdMap Map of TAS Address Id to source Order Line Contact.
* @return void
*
* @example
* createTerritoryTasWritebackRecords(accountList, userIdSet, orderLineContactByTasAddressIdMap);
*/
    private static void createTerritoryTasWritebackRecords(
        List<Account> accountList,
        Set<Id> userIdSet,
        Map<String, OrderLineContact__c> orderLineContactByTasAddressIdMap
    ) {
        try{
            throwForcedTestExceptionIfRequested('createTerritoryTasWritebackRecords');
            createTasWritebackRecords(accountList, userIdSet, orderLineContactByTasAddressIdMap);
        } catch (Exception ex) {
            Logger.error('Tas write back data failed ', ex);
            throw new OverlayAssignmentException('Tas write back data failed');
        } finally {
            Logger.saveLog();
        }
    }

    /**
* @description
* GC-3352 - Loads source Order Line Contacts for selected territories and Account Oracle addresses.
* Empty when no territory is selected. First OLC per TAS Address Id wins.
*
* @param accountList Expanded overlay Account list
* @param territoryIds Selected Territory IDs
* @return Map of TASAddressId__c to source OrderLineContact__c
*/
    private static Map<String, OrderLineContact__c> loadSourceOlcByTasAddressIdMap(
        List<Account> accountList,
        List<String> territoryIds
    ) {
        Map<String, OrderLineContact__c> sourceOlcByTasAddressIdMap = new Map<String, OrderLineContact__c>();

        if (territoryIds == null || territoryIds.isEmpty() || accountList == null || accountList.isEmpty()) {
            return sourceOlcByTasAddressIdMap;
        }

        Set<String> territoryIdSet = buildStringSet(territoryIds);
        Set<String> tasAddressIdSet = getTasAddressIdsFromAccounts(accountList);
        List<OrderLineContact__c> sourceOrderLineContactList = TASSelector.selectAssignmentSources(
            territoryIdSet,
            tasAddressIdSet
        );

        sourceOlcByTasAddressIdMap = buildOrderLineContactByTasAddressIdMap(sourceOrderLineContactList);
        return sourceOlcByTasAddressIdMap;
    }
    
    /**
* @description
* Private helper method for submitOverlayAssignments.
* Creates overlay Account Team Member records.
* Duplicate key remains AccountId-UserId.
* GC-3352 - When a source OLC exists for Account.OracleAddressId__c, copy
* TerritoryNumber__c, TAS_Sales_Category__c, and SalesCategoryDescription__c
* onto TerritoryCode__c, SalesCategoryCode__c, and SalesCategoryDescription__c.
* GC-3345 - Sets OpportunityAccessLevel to Edit.
* 
* @param accountList List of selected Accounts.
* @param userIdSet Set of selected Overlay User Ids.
* @param sourceOlcByTasAddressIdMap Source OLC by TAS Address Id; empty when no territory selected.
* @return Void.
* 
* @example
* OverlayAssignmentService.createAccountTeamMembers(accountList, userIdSet, sourceOlcByTasAddressIdMap);
*/
    private static void createAccountTeamMembers(
        List<Account> accountList,
        Set<Id> userIdSet,
        Map<String, OrderLineContact__c> sourceOlcByTasAddressIdMap
    ) {
        try{
            throwForcedTestExceptionIfRequested('createAccountTeamMembers');
            if (accountList == null || accountList.isEmpty() || userIdSet == null || userIdSet.isEmpty()) {
                Logger.warn('OverlayAssignmentService.createAccountTeamMembers: accountList, userIdSet is null or empty');
                return;
            }

            if (sourceOlcByTasAddressIdMap == null) {
                sourceOlcByTasAddressIdMap = new Map<String, OrderLineContact__c>();
            }
            
            OverlayAssignmentDmlService dmlService = new OverlayAssignmentDmlService();
            dmlService.createAccountShares(accountList, userIdSet);

            if (!Schema.sObjectType.AccountTeamMember.isCreateable()) {
                throw new OverlayAssignmentException('Current user cannot create Account Team Member records.');
            }
            
            Set<Id> accountIdSet = new Map<Id, Account>(accountList).keySet();
            Set<String> existingKeySet = new Set<String>();
            
            for (AccountTeamMember accountTeamMember : AccountTeamMemberSelector.selectByAccountsAndUsers(
                accountIdSet,
                userIdSet
            )) {
                existingKeySet.add(accountTeamMember.AccountId + '-' + accountTeamMember.UserId);
            }
            
            List<AccountTeamMember> accountTeamMemberList = new List<AccountTeamMember>();
            
            for (Account accountRecord : accountList) {
                OrderLineContact__c sourceOrderLineContact;
                if (String.isNotBlank(accountRecord.OracleAddressId__c)) {
                    sourceOrderLineContact =
                        sourceOlcByTasAddressIdMap.get(accountRecord.OracleAddressId__c.trim());
                }

                for (Id userId : userIdSet) {
                    String key = accountRecord.Id + '-' + userId;
                    
                    if (!existingKeySet.contains(key)) {
                        AccountTeamMember accountTeamMember = new AccountTeamMember();
                        accountTeamMember.AccountId = accountRecord.Id;
                        accountTeamMember.UserId = userId;
                        accountTeamMember.TeamMemberRole = TEAM_MEMBER_ROLE_SALES;
                        accountTeamMember.AssignmentType__c = ASSIGNMENT_TYPE_SALESFORCE_ASSIGNED;
                        accountTeamMember.AccountAccessLevel = ACCOUNT_ACCESS_LEVEL_EDIT;
                        accountTeamMember.OpportunityAccessLevel = OPPORTUNITY_ACCESS_LEVEL_EDIT; // GC-3345
                        accountTeamMember.CaseAccessLevel = CASE_ACCESS_LEVEL_READ;

                        if (sourceOrderLineContact != null) {
                            accountTeamMember.TerritoryCode__c = sourceOrderLineContact.TerritoryNumber__c;
                           // accountTeamMember.SalesCategoryCode__c = sourceOrderLineContact.TAS_Sales_Category__c;
                          //  accountTeamMember.SalesCategoryDescription__c =
                              //  sourceOrderLineContact.SalesCategoryDescription__c;
                        }

                        accountTeamMemberList.add(accountTeamMember);
                    }
                }
            }
            
            List<SObject> accountTeamMemberSObjectList = new List<SObject>();
            
            for (AccountTeamMember accountTeamMember : accountTeamMemberList) {
                accountTeamMemberSObjectList.add(accountTeamMember);
            }
            
            insertCreatableRecords(accountTeamMemberSObjectList, 'AccountTeamMember');
        } catch (Exception ex) {
            Logger.error('Account Team member creation failed ', ex);
            throw new OverlayAssignmentException('Account team member creation failed');
        } finally {
            Logger.saveLog();
        }
    }

    /*
    // GC-3180 - Opportunity Team creation removed per story. Previous implementation retained for reference:
    private static void createOpportunityTeamMembers(Set<Id> accountIdSet, Set<Id> userIdSet) {
        try{
            throwForcedTestExceptionIfRequested('createOpportunityTeamMembers');
            if (accountIdSet == null || accountIdSet.isEmpty() || userIdSet == null || userIdSet.isEmpty()) {
                Logger.warn('OverlayAssignmentService.createOpportunityTeamMembers: accountIdSet, userIdSet is null or empty');
                return;
            }

            if (!Schema.sObjectType.OpportunityTeamMember.isCreateable()) {
                throw new OverlayAssignmentException('Current user cannot create Opportunity Team Member records.');
            }

            List<Opportunity> opportunityList = OpportunitySelector.selectByAccountIds(accountIdSet);

            if (opportunityList.isEmpty()) {
                return;
            }

            Set<Id> opportunityIdSet = new Set<Id>();

            for (Opportunity opportunityRecord : opportunityList) {
                opportunityIdSet.add(opportunityRecord.Id);
            }

            Set<String> existingKeySet = new Set<String>();

            for (OpportunityTeamMember opportunityTeamMember : OpportunityTeamMemberSelector.selectByOpportunitiesAndUsers(
                opportunityIdSet,
                userIdSet
            )) {
                existingKeySet.add(opportunityTeamMember.OpportunityId + '-' + opportunityTeamMember.UserId);
            }

            List<OpportunityTeamMember> opportunityTeamMemberList = new List<OpportunityTeamMember>();

            for (Opportunity opportunityRecord : opportunityList) {
                for (Id userId : userIdSet) {
                    String key = opportunityRecord.Id + '-' + userId;

                    if (!existingKeySet.contains(key)) {
                        OpportunityTeamMember opportunityTeamMember = new OpportunityTeamMember();
                        opportunityTeamMember.OpportunityId = opportunityRecord.Id;
                        opportunityTeamMember.UserId = userId;
                        opportunityTeamMember.TeamMemberRole = TEAM_MEMBER_ROLE_SALES;
                        opportunityTeamMember.AssignmentType__c = ASSIGNMENT_TYPE_SALESFORCE_ASSIGNED;
                        opportunityTeamMember.OpportunityAccessLevel = OPPORTUNITY_ACCESS_LEVEL_EDIT;
                        opportunityTeamMemberList.add(opportunityTeamMember);
                    }
                }
            }

            List<SObject> opportunityTeamMemberSObjectList = new List<SObject>();

            for (OpportunityTeamMember opportunityTeamMember : opportunityTeamMemberList) {
                opportunityTeamMemberSObjectList.add(opportunityTeamMember);
            }

            insertCreatableRecords(opportunityTeamMemberSObjectList, 'OpportunityTeamMember');
        } catch (Exception ex) {
            Logger.error('Opportunity team member creation failed ', ex);
            throw new OverlayAssignmentException('Opportunity team member creation failed');
        } finally {
            Logger.saveLog();
        }
    }
    */
    
    /**
* @description
* Private helper method for submitOverlayAssignments.
* Creates overlay Order Line Contact records
* 
* @param accountList List of selected Accounts.
* @param userIdSet Set of selected Overlay User Ids.
* @param orderLineContactByTasAddressIdMap Map of TAS Address Id to source Order Line Contact.
* @return Void.
*
* @example
* OverlayAssignmentService.createTasWritebackRecords(accountList, userIdSet, orderLineContactByTasAddressIdMap);
*
* @modified By Pwc Developer
* GC-3108 - Updated to remove ZoneName__c field and add TasZone__c.
* GC-3112 - Iterates selected Accounts by OracleAddressId__c instead of Address records.
*/
    private static void createTasWritebackRecords(
        List<Account> accountList,
        Set<Id> userIdSet,
        Map<String, OrderLineContact__c> orderLineContactByTasAddressIdMap
    ) {
        try{
            throwForcedTestExceptionIfRequested('createTasWritebackRecords');
            if (accountList == null || accountList.isEmpty()) {
                Logger.warn('OverlayAssignmentService.createTasWritebackRecords: accountList is null or empty');
                return;
            }

            if (!Schema.sObjectType.OrderLineContact__c.isCreateable()) {
                throw new OverlayAssignmentException('Current user cannot create Order Line Contact records.');
            }

            Map<Id, User> userByIdMap = new Map<Id, User>(UserSelector.selectByIds(userIdSet));
            List<OrderLineContact__c> orderLineContactToInsertList = new List<OrderLineContact__c>();

            // GC-3112 - One writeback per Account OracleAddressId__c matched to source OLC TASAddressId__c.
            for (Account accountRecord : accountList) {
                if (String.isBlank(accountRecord.OracleAddressId__c)) {
                    continue;
                }

                String tasAddressId = accountRecord.OracleAddressId__c.trim();
                OrderLineContact__c sourceOrderLineContact = orderLineContactByTasAddressIdMap.get(tasAddressId);

                if (sourceOrderLineContact == null) {
                    Logger.warn('OverlayAssignmentService.createTasWritebackRecords: sourceOrderLineContact is null or empty');
                    continue;
                }

                for (Id userId : userIdSet) {
                    User overlayUser = userByIdMap.get(userId);

                    if (overlayUser == null) {
                        Logger.warn('OverlayAssignmentService.createTasWritebackRecords: overlayUser is null or empty');
                        continue;
                    }

                    OrderLineContact__c orderLineContact = new OrderLineContact__c();
                    orderLineContact.TerritoryID__c = sourceOrderLineContact.TerritoryID__c;
                    orderLineContact.TerritoryDescription__c = sourceOrderLineContact.TerritoryDescription__c;
                    orderLineContact.TerritoryNumber__c = sourceOrderLineContact.TerritoryNumber__c;
                    orderLineContact.TASAddressId__c = sourceOrderLineContact.TASAddressId__c;
                    orderLineContact.BusinessUnit__c = sourceOrderLineContact.BusinessUnit__c;
                    orderLineContact.TASZone__c = sourceOrderLineContact.TASZone__c;
                    orderLineContact.RegionName__c = sourceOrderLineContact.RegionName__c;
                    orderLineContact.HRISSalesRepId__c = overlayUser.EmployeeNumber__c;
                    orderLineContactToInsertList.add(orderLineContact);
                }
            }
            
            List<SObject> orderLineContactSObjectList = new List<SObject>();
            
            for (OrderLineContact__c orderLineContact : orderLineContactToInsertList) {
                orderLineContactSObjectList.add(orderLineContact);
            }
            
            insertCreatableRecords(orderLineContactSObjectList, 'OrderLineContact__c');
        } catch (Exception ex) {
            Logger.error('Tas write back data failed ', ex);
            throw new OverlayAssignmentException('Tas write back data failed');
        } finally {
            Logger.saveLog();
        }
    }
    
    
    /**
* @description
* Private helper method to insert records.
* Creates Account Team, Opportunity Team, and TAS writeback records for overlay assignments.
* 
* @param sObjectList List of object records to be inserted.
* @param objectName Name of object data to be inserted.
* @return Void.
* 
* @example
* OverlayAssignmentService.insertCreatableRecords(sObjectList, objectName);
*/
    private static void insertCreatableRecords(List<SObject> sObjectList, String objectName) {
        try{
            throwForcedTestExceptionIfRequested('insertCreatableRecords');
            if (sObjectList == null || sObjectList.isEmpty()) {
                Logger.warn('OverlayAssignmentService.insertCreatableRecords: sObjectList is null or empty');
                Logger.setScenario(SCENARIO);
                Logger.debug('No ' + objectName + ' records were created because the input list was empty.')
                    .addTag(LOGGER_TAG);
                return;
            }
            
            SObjectAccessDecision accessDecision = Security.stripInaccessible(AccessType.CREATABLE, sObjectList);
            insert accessDecision.getRecords();
            
            Logger.setScenario(SCENARIO);
            Logger.info('Created ' + accessDecision.getRecords().size() + ' ' + objectName + ' records.')
                .addTag(LOGGER_TAG);
        } catch (Exception ex) {
            Logger.error('Data insertion failed', ex);
            throw new OverlayAssignmentException('Data insertion failed');
        } finally {
            Logger.saveLog();
        } 
    }
    
    /**
* @description
* Private helper method for submitOverlayAssignments.
* GC-3112 - Collects TAS Address Ids from Account.OracleAddressId__c on selected accounts
*              (replaces Address.AddressId__c lookup).
*
* @param accountList Selected Account records.
* @return Set<String> TAS Address Id set
*
* @example
* OverlayAssignmentService.getTasAddressIdsFromAccounts(accountList);
*/
    private static Set<String> getTasAddressIdsFromAccounts(List<Account> accountList) {
        try{
            throwForcedTestExceptionIfRequested('getTasAddressIdsFromAccounts');
            Set<String> tasAddressIdSet = new Set<String>();

            if (accountList == null || accountList.isEmpty()) {
                return tasAddressIdSet;
            }

            for (Account accountRecord : accountList) {
                if (String.isNotBlank(accountRecord.OracleAddressId__c)) {
                    tasAddressIdSet.add(accountRecord.OracleAddressId__c.trim());
                }
            }

            return tasAddressIdSet;
        } catch (Exception ex) {
            Logger.error('Getting tas address Ids from accounts failed', ex);
            throw new OverlayAssignmentException('Getting tas address Ids from accounts failed');
        } finally {
            Logger.saveLog();
        }
    }
    
    /**
* @description
* Private helper method for submitOverlayAssignments.
* Forms the MAP of TasAddress Id versus OrderLineContact__c record
* 
* @param orderLineContactList Order Line Contact list.
* @return Map<String, OrderLineContact__c> TasAddress Id versus OrderLineContact__c record.
* 
* @example
* OverlayAssignmentService.buildOrderLineContactByTasAddressIdMap(orderLineContactList);
*/
    private static Map<String, OrderLineContact__c> buildOrderLineContactByTasAddressIdMap(
        List<OrderLineContact__c> orderLineContactList
    ) {
        try{
            throwForcedTestExceptionIfRequested('buildOrderLineContactByTasAddressIdMap');
            Map<String, OrderLineContact__c> orderLineContactByTasAddressIdMap = new Map<String, OrderLineContact__c>();
            
            for (OrderLineContact__c orderLineContact : orderLineContactList) {
                if (!orderLineContactByTasAddressIdMap.containsKey(orderLineContact.TASAddressId__c)) {
                    orderLineContactByTasAddressIdMap.put(orderLineContact.TASAddressId__c, orderLineContact);
                }
            }
            
            return orderLineContactByTasAddressIdMap;
        } catch (Exception ex) {
            Logger.error('Building order line contact vs address map failed', ex);
            throw new OverlayAssignmentException('Building order line contact vs address map failed');
        } finally {
            Logger.saveLog();
        } 
    }
    
    /**
* @description
* GC-3088 - Validates that at least one search criterion is provided before executing the account retrieval process.
* Throws an exception when no Territory, Account, Account Type, or selected Account has been specified.
*
* @param territoryIds List of selected Territory IDs.
* @param accountSearchKey Search keyword entered for Account Name or Account Number.
* @param accountType Selected Account Type filter.
* @param selectedSearchAccountIds List of Account IDs selected from account search results.
* @return void
*
* @example
* validateAtLeastOneSearchCriterion(
*     territoryIds,
*     accountSearchKey,
*     accountType,
*     selectedSearchAccountIds
* );
*/
    private static void validateAtLeastOneSearchCriterion(
        List<String> territoryIds,
        String accountSearchKey,
        String accountType,
        List<Id> selectedSearchAccountIds
    ) {
        try{
            throwForcedTestExceptionIfRequested('validateAtLeastOneSearchCriterion');
            Boolean hasTerritory = territoryIds != null && !territoryIds.isEmpty();
            Boolean hasAccountSearch = String.isNotBlank(accountSearchKey);
            Boolean hasAccountType = String.isNotBlank(accountType);
            Boolean hasSelectedAccounts = selectedSearchAccountIds != null && !selectedSearchAccountIds.isEmpty();
            
            if (!hasTerritory && !hasAccountSearch && !hasAccountType && !hasSelectedAccounts) {
                throw new AuraHandledException('Please search or select at least one Territory, Account, or Account Type.');
            }
        } catch (Exception ex) {
            Logger.error('Validation of search criteria failed', ex);
            throw new OverlayAssignmentException('Validation of search criteria failed');
        } finally {
            Logger.saveLog();
        } 
    }
    
    /**
* @description
* GC-3088 - Validates that at least one overlay user has been selected before proceeding with the assignment process.
* Throws an exception when no user IDs are provided.
*
* @param userIds List of selected User IDs.
* @return void
*
* @example
* validateUserIds(userIds);
*/
    private static void validateUserIds(List<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            Logger.warn('OverlayAssignmentService.insertCreatableRecords: sObjectList is null or empty');
            throw new AuraHandledException('Please select at least one overlay user.');
        }
    }
    
    /**
* @description
* Reusable private helper method used to build Id set.
* 
* @param idList List of Ids.
* @return Set<Id> Set of Ids.
* 
* @example
* OverlayAssignmentService.buildIdSet(idList);
*/
    private static Set<Id> buildIdSet(List<Id> idList) {
        try{
            throwForcedTestExceptionIfRequested('buildIdSet');
            Set<Id> idSet = new Set<Id>();
            
            if (idList != null) {
                idSet.addAll(idList);
            }
            
            return idSet;
        } catch (Exception ex) {
            Logger.error('Building ID set failed', ex);
            throw new OverlayAssignmentException('Building ID set failed');
        } finally {
            Logger.saveLog();
        }
    }
    
    /**
* @description
* Reusable private helper method used to build String set.
* 
* @param stringList List of Strings.
* @return Set<String> Set of Strings.
* 
* @example
* OverlayAssignmentService.buildStringSet(stringList);
*/
    private static Set<String> buildStringSet(List<String> stringList) {
        try{
            throwForcedTestExceptionIfRequested('buildStringSet');
            Set<String> stringSet = new Set<String>();
            
            if (stringList != null) {
                stringSet.addAll(stringList);
            }
            
            return stringSet;
        } catch (Exception ex) {
            Logger.error('Building String set failed', ex);
            throw new OverlayAssignmentException('Building String set failed');
        } finally {
            Logger.saveLog();
        }
    }

    private static void throwForcedTestExceptionIfRequested(String methodName) {
        if (Test.isRunningTest() && forcedExceptionMethodName == methodName) {
            throw new QueryException('Script-thrown exception');
        }
    }
}