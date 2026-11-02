/**
 * @author Divya Sree
 * @date 2026/07/20
 *
 * @group AccountAccountRelationship
 *
 * @description
 * Orchestrates retrieval of Account-Account Relationship records for the
 * Customer 360 "Account Account Relationship" tab. Related story: GC-3126.
 * GC-3213 - Also stamps Account/Opportunity IDN_Account__c and GPO_Account__c
 *           from IDN/GPO AAR rows (latest wins) and syncs open Opportunities.
 */
public with sharing class AccountAccountRelationshipService {

    @TestVisible
    private static final String ACCOUNT_TYPE_CUSTOMER = 'Customer';
    @TestVisible
    private static final String ACCOUNT_TYPE_ADDRESS = 'Address';
    @TestVisible
    private static final String ACCOUNT_TYPE_IDN = 'IDN';
    @TestVisible
    private static final String ACCOUNT_TYPE_GPO = 'GPO';

    // GC-3213 - START
    private static final String CLASS_NAME = 'AccountAccountRelationshipService';
    // GC-3213 - END

    /**
     * @description
     * Test-only override to force getRelationshipsForAccount to throw,
     * so callers can verify their exception handling behavior.
     */
    @TestVisible
    private static Boolean forceExceptionForTest = false;

    /**
     * @description
     * Returns the relationships relevant to the given Account, branching on
     * whether the Account is a Customer (Child side) or an IDN/GPO (Parent side).
     *
     * @param accountId Id of the Account currently being viewed
     * @return List of AccountAccountRelationship__c records relevant to that Account
     * @example
     * AccountAccountRelationshipService.getRelationshipsForAccount(accId);
     */
    public static List<AccountAccountRelationship__c> getRelationshipsForAccount(Id accountId) {
        if (Test.isRunningTest() && forceExceptionForTest) {
            throw new AccountAccountRelationshipException('Forced exception for test coverage.');
        }

        Set<Id> accountIdSet = new Set<Id>{ accountId };
        String accountType = resolveAccountType(accountIdSet);

        if (accountType == ACCOUNT_TYPE_CUSTOMER || accountType == ACCOUNT_TYPE_ADDRESS) {
            return AccountAccountRelationshipSelector.selectByChildAccountIds(accountIdSet);
        } 
        
        // else if (accountType == ACCOUNT_TYPE_IDN || accountType == ACCOUNT_TYPE_GPO) {
        //     return AccountAccountRelationshipSelector.selectByParentAccountIds(accountIdSet);
        // }
        else if (accountType == ACCOUNT_TYPE_IDN) {
            return AccountAccountRelationshipSelector.selectByParentAccountIds(
                accountIdSet,
                AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_IDN_MEMBER
            );
        } else if (accountType == ACCOUNT_TYPE_GPO) {
            return AccountAccountRelationshipSelector.selectByParentAccountIds(
                accountIdSet,
                AccountAccountRelationshipSelector.RELATIONSHIP_TYPE_HAS_GPO_MEMBER
            );
        }
        return new List<AccountAccountRelationship__c>();
    }

    /**
     * @description
     * Returns the Type value of the given Account, used by the LWC to decide
     * which lookup field (ParentAccount__c vs ChildAccount__c) to pre-fill
     * when creating a new relationship.
     *
     * @param accountId Id of the Account currently being viewed
     * @return The Account.Type value
     * @example
     * AccountAccountRelationshipService.getAccountType(accId);
     */
    public static String getAccountType(Id accountId) {
        return resolveAccountType(new Set<Id>{ accountId });
    }

    /**
     * @description
     * Resolves the Type of a single Account using the existing shared
     * AccountSelector.selectByIds method, rather than a new query method.
     *
     * @param accountIdSet Set containing the single Account Id to resolve
     * @return The Account.Type value, or null if not found
     */
    private static String resolveAccountType(Set<Id> accountIdSet) {
        List<Account> accountList = AccountSelector.selectByIds(accountIdSet);
        return accountList.isEmpty() ? null : accountList[0].Type;
    }

    /**
     * @description
     * Returns whether the current user's Profile is System Administrator.
     * Used to restrict the "New" relationship creation button to admins only.
     *
     * @return True if the running user's Profile Name is 'System Administrator'
     * @example
     * AccountAccountRelationshipService.isSystemAdministrator();
     */
    public static Boolean isSystemAdministrator() {
        return [SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1]
            .Profile.Name == 'System Administrator';
            
    }

    // GC-3213 - START

    /**
     * @description Collects affected child Accounts from AAR trigger rows and
     *              stamps IDN/GPO plus open Opportunity sync.
     *              Pass oldMap as null for insert/delete; pass Trigger.oldMap for update.
     * @param relationships AAR records from Trigger.new or Trigger.old.
     * @param oldMap Trigger.oldMap on update; null on insert/delete.
     */
    public static void processRelationships(
        List<AccountAccountRelationship__c> relationships,
        Map<Id, AccountAccountRelationship__c> oldMap
    ) {
        Set<Id> childAccountIds = oldMap == null
            ? collectChildIds(relationships)
            : collectChangedChildIds(relationships, oldMap);
        stampAccounts(childAccountIds);
    }

    /**
     * @description Before insert/update: copies Account IDN/GPO onto open Opportunities.
     * @param opportunities Trigger.new Opportunity records.
     * @param oldMap Trigger.oldMap; null on insert.
     */
    public static void stampOpportunitiesFromAccount(
        List<Opportunity> opportunities,
        Map<Id, Opportunity> oldMap
    ) {
        try {
            if (opportunities != null && !opportunities.isEmpty()) {
                Set<Id> accountIds = new Set<Id>();
                List<Opportunity> opportunitiesToStamp = new List<Opportunity>();

                for (Opportunity opportunityRecord : opportunities) {
                    if (opportunityRecord.AccountId == null) {
                        continue;
                    }

                    if (oldMap == null) {
                        opportunitiesToStamp.add(opportunityRecord);
                        accountIds.add(opportunityRecord.AccountId);
                    } else {
                        Opportunity oldOpportunity = oldMap.get(opportunityRecord.Id);
                        if (
                            oldOpportunity != null &&
                            opportunityRecord.IsClosed != true &&
                            opportunityRecord.AccountId != oldOpportunity.AccountId
                        ) {
                            opportunitiesToStamp.add(opportunityRecord);
                            accountIds.add(opportunityRecord.AccountId);
                        }
                    }
                }

                if (!opportunitiesToStamp.isEmpty()) {
                    Map<Id, Account> accountsById = new Map<Id, Account>([
                        SELECT Id, IDN_Account__c, GPO_Account__c
                        FROM Account
                        WHERE Id IN :accountIds
                    ]);

                    for (Opportunity opportunityRecord : opportunitiesToStamp) {
                        Account parentAccount = accountsById.get(opportunityRecord.AccountId);
                        if (parentAccount != null) {
                            opportunityRecord.IDN_Account__c = parentAccount.IDN_Account__c;
                            opportunityRecord.GPO_Account__c = parentAccount.GPO_Account__c;
                        }
                    }
                }
            }
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.stampOpportunitiesFromAccount', e);
        }
    }

    /**
     * @description Stamps IDN/GPO on child Accounts from remaining AARs, then
     *              syncs open Opportunities for those Accounts.
     * @param childAccountIds Customer/Address Account Ids to stamp.
     */
    private static void stampAccounts(Set<Id> childAccountIds) {
        try {
            if (childAccountIds != null && !childAccountIds.isEmpty()) {
                childAccountIds.remove(null);

                if (!childAccountIds.isEmpty()) {
                    Map<Id, Id> childToIdn = new Map<Id, Id>();
                    Map<Id, Id> childToGpo = new Map<Id, Id>();
                    buildLatestAffiliationMaps(childAccountIds, childToIdn, childToGpo);

                    List<Account> accountsToUpdate = buildAccountUpdates(
                        childAccountIds,
                        childToIdn,
                        childToGpo
                    );

                    if (!accountsToUpdate.isEmpty()) {
                        logSaveResults(Database.update(accountsToUpdate, false), 'Account');
                    }

                    syncOpenOpportunities(childAccountIds);
                }
            }
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.stampAccounts', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Collects child Account Ids from IDN/GPO AAR rows.
     * @param relationships AAR records from Trigger.new / Trigger.old.
     * @return Child Account Ids requiring stamp.
     */
    private static Set<Id> collectChildIds(
        List<AccountAccountRelationship__c> relationships
    ) {
        Set<Id> childAccountIds = new Set<Id>();

        if (relationships != null && !relationships.isEmpty()) {
            for (AccountAccountRelationship__c relationship : relationships) {
                // GC-3213 - START
                if (
                    relationship != null &&
                    relationship.ChildAccount__c != null &&
                    AccountAccountRelationshipSelector.isIdnOrGpoRelationshipType(relationship)
                ) {
                    childAccountIds.add(relationship.ChildAccount__c);
                }
                // GC-3213 - END
            }
        }

        return childAccountIds;
    }

    /**
     * @description Collects old and new child Account Ids when AAR type/parent/child
     *              changes for IDN/GPO-relevant rows.
     * @param newRelationships Trigger.new AAR records.
     * @param oldMap Trigger.oldMap AAR records.
     * @return Child Account Ids requiring stamp.
     */
    private static Set<Id> collectChangedChildIds(
        List<AccountAccountRelationship__c> newRelationships,
        Map<Id, AccountAccountRelationship__c> oldMap
    ) {
        Set<Id> childAccountIds = new Set<Id>();

        if (newRelationships != null && !newRelationships.isEmpty() && oldMap != null) {
            for (AccountAccountRelationship__c newRelationship : newRelationships) {
                AccountAccountRelationship__c oldRelationship = oldMap.get(newRelationship.Id);
                if (oldRelationship == null) {
                    continue;
                }

                // GC-3213 - START
                Boolean relevantChanged =
                    newRelationship.RelationshipType__c != oldRelationship.RelationshipType__c ||
                    newRelationship.InverseRelationshipType__c != oldRelationship.InverseRelationshipType__c ||
                    newRelationship.ParentAccount__c != oldRelationship.ParentAccount__c ||
                    newRelationship.ChildAccount__c != oldRelationship.ChildAccount__c;

                if (!relevantChanged) {
                    continue;
                }

                Boolean wasRelevant =
                    AccountAccountRelationshipSelector.isIdnOrGpoRelationshipType(oldRelationship);
                Boolean isRelevant =
                    AccountAccountRelationshipSelector.isIdnOrGpoRelationshipType(newRelationship);
                // GC-3213 - END

                if (wasRelevant || isRelevant) {
                    if (oldRelationship.ChildAccount__c != null) {
                        childAccountIds.add(oldRelationship.ChildAccount__c);
                    }
                    if (newRelationship.ChildAccount__c != null) {
                        childAccountIds.add(newRelationship.ChildAccount__c);
                    }
                }
            }
        }

        return childAccountIds;
    }

    /**
     * @description Syncs Account IDN/GPO onto open Opportunities (bulk query + one DML).
     * @param accountIds Account Ids whose open Opportunities should refresh.
     */
    private static void syncOpenOpportunities(Set<Id> accountIds) {
        try {
            if (accountIds != null && !accountIds.isEmpty()) {
                accountIds.remove(null);

                if (!accountIds.isEmpty()) {
                    Map<Id, Account> accountsById = new Map<Id, Account>([
                        SELECT Id, IDN_Account__c, GPO_Account__c
                        FROM Account
                        WHERE Id IN :accountIds
                    ]);

                    if (!accountsById.isEmpty()) {
                        List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();

                        for (Opportunity opportunityRecord : [
                            SELECT Id, AccountId, IDN_Account__c, GPO_Account__c
                            FROM Opportunity
                            WHERE AccountId IN :accountsById.keySet()
                              AND IsClosed = false
                        ]) {
                            Account parentAccount = accountsById.get(opportunityRecord.AccountId);
                            if (
                                parentAccount != null &&
                                (opportunityRecord.IDN_Account__c != parentAccount.IDN_Account__c ||
                                 opportunityRecord.GPO_Account__c != parentAccount.GPO_Account__c)
                            ) {
                                Opportunity opportunityForUpdate = new Opportunity();
                                opportunityForUpdate.Id = opportunityRecord.Id;
                                opportunityForUpdate.IDN_Account__c = parentAccount.IDN_Account__c;
                                opportunityForUpdate.GPO_Account__c = parentAccount.GPO_Account__c;
                                opportunitiesToUpdate.add(opportunityForUpdate);
                            }
                        }

                        if (!opportunitiesToUpdate.isEmpty()) {
                            logSaveResults(
                                Database.update(opportunitiesToUpdate, false),
                                'Opportunity'
                            );
                        }
                    }
                }
            }
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.syncOpenOpportunities', e);
        }
    }

    /**
     * @description Builds latest IDN/GPO parent maps from AARs (CreatedDate DESC).
     * @param childAccountIds Child Account Ids.
     * @param childToIdn Output map of child Id to IDN Account Id.
     * @param childToGpo Output map of child Id to GPO Account Id.
     */
    private static void buildLatestAffiliationMaps(
        Set<Id> childAccountIds,
        Map<Id, Id> childToIdn,
        Map<Id, Id> childToGpo
    ) {
        for (AccountAccountRelationship__c affiliation :
            AccountAccountRelationshipSelector.selectGpoIdnAffiliationsByAccountIds(
                childAccountIds
            )
        ) {
            if (affiliation.ChildAccount__c == null || affiliation.ParentAccount__c == null) {
                continue;
            }

            // GC-3213 - START
            if (
                AccountAccountRelationshipSelector.isIdnRelationshipType(affiliation) &&
                !childToIdn.containsKey(affiliation.ChildAccount__c)
            ) {
                childToIdn.put(affiliation.ChildAccount__c, affiliation.ParentAccount__c);
            }

            if (
                AccountAccountRelationshipSelector.isGpoRelationshipType(affiliation) &&
                !childToGpo.containsKey(affiliation.ChildAccount__c)
            ) {
                childToGpo.put(affiliation.ChildAccount__c, affiliation.ParentAccount__c);
            }
            // GC-3213 - END
        }
    }

    /**
     * @description Builds Account updates only when IDN/GPO values differ.
     * @param childAccountIds Child Account Ids.
     * @param childToIdn Latest IDN parent by child.
     * @param childToGpo Latest GPO parent by child.
     * @return Accounts that need an IDN/GPO update.
     */
    private static List<Account> buildAccountUpdates(
        Set<Id> childAccountIds,
        Map<Id, Id> childToIdn,
        Map<Id, Id> childToGpo
    ) {
        List<Account> accountsToUpdate = new List<Account>();
        Map<Id, Account> existingAccounts = new Map<Id, Account>([
            SELECT Id, IDN_Account__c, GPO_Account__c
            FROM Account
            WHERE Id IN :childAccountIds
        ]);

        for (Id childAccountId : childAccountIds) {
            Account existingAccount = existingAccounts.get(childAccountId);
            if (existingAccount == null) {
                continue;
            }

            Id targetIdn = childToIdn.get(childAccountId);
            Id targetGpo = childToGpo.get(childAccountId);

            if (
                existingAccount.IDN_Account__c != targetIdn ||
                existingAccount.GPO_Account__c != targetGpo
            ) {
                Account accountForUpdate = new Account();
                accountForUpdate.Id = childAccountId;
                accountForUpdate.IDN_Account__c = targetIdn;
                accountForUpdate.GPO_Account__c = targetGpo;
                accountsToUpdate.add(accountForUpdate);
            }
        }

        return accountsToUpdate;
    }

    /**
     * @description Logs partial DML success and failure counts.
     * @param saveResults DML save results.
     * @param objectName Object label for the log message.
     */
    @TestVisible
    private static void logSaveResults(
        List<Database.SaveResult> saveResults,
        String objectName
    ) {
        if (saveResults != null && !saveResults.isEmpty()) {
            Integer successCount = 0;
            Integer failureCount = 0;

            for (Integer index = 0; index < saveResults.size(); index++) {
                Database.SaveResult saveResult = saveResults[index];
                if (saveResult.isSuccess()) {
                    successCount++;
                } else {
                    failureCount++;
                    for (Database.Error error : saveResult.getErrors()) {
                        Logger.error(
                            CLASS_NAME + '.logSaveResults: failed ' +
                            objectName +
                            ' index=' +
                            index +
                            ' statusCode=' +
                            error.getStatusCode() +
                            ' message=' +
                            error.getMessage()
                        );
                    }
                }
            }

            Logger.info(
                CLASS_NAME + '.logSaveResults: objectName=' +
                objectName +
                ' successCount=' +
                successCount +
                ' failureCount=' +
                failureCount
            );
        }
    }

    // GC-3213 - END
}