/**
 * @description GC-2860 - Resolves contributing accounts for competitive installed base roll-up.
 *              Facility: this account only.
 *              Customer parent: this account + direct child facilities (ParentId, Oracle Address Id).
 *              IDN/GPO: affiliated customer parents via AAR + their direct child facilities.
 */
public with sharing class AccountHierarchyResolutionService {
    private static final String HEADING_FACILITY = 'All Competitive Assets on this Facility';
    private static final String HEADING_CUSTOMER_PARENT =
        'All Competitive Assets on this Customer and related Facilities';
    private static final String HEADING_IDN =
        'All Competitive Assets on this IDN\'s affiliated Customers and related Facilities';
    private static final String HEADING_GPO =
        'All Competitive Assets on this GPO\'s affiliated Customers and related Facilities';

    /**
     * @description Account Ids whose competitive assets should appear on the tab, plus UI heading context.
     */
    public class AccountScope {
        public Set<Id> accountIds;
        public String assetDetailHeading;
    }

    /**
     * @description Resolves contributing account Ids and the asset detail heading for the given account.
     * @param accountId Account context for the Competitive Installed Base tab.
     * @return Account scope with account Ids and heading label.
     */
    public static AccountScope resolveAccountScope(Id accountId) {
        AccountScope scope = new AccountScope();
        scope.accountIds = new Set<Id>();
        scope.assetDetailHeading = HEADING_FACILITY;

        if (accountId == null) {
            return scope;
        }

        List<Account> contextAccounts = AccountSelector.selectByIds(new Set<Id>{ accountId });
        if (contextAccounts.isEmpty()) {
            return scope;
        }

        Account contextAccount = contextAccounts[0];

        if (String.isNotBlank(contextAccount.OracleAddressId__c)) {
            scope.accountIds.add(accountId);
            scope.assetDetailHeading = HEADING_FACILITY;
            return scope;
        }

        if (contextAccount.Type == 'IDN') {
            scope.assetDetailHeading = HEADING_IDN;
            addAffiliatedCustomerParentScope(accountId, scope.accountIds);
            return scope;
        }

        if (contextAccount.Type == 'GPO') {
            scope.assetDetailHeading = HEADING_GPO;
            addAffiliatedCustomerParentScope(accountId, scope.accountIds);
            return scope;
        }

        scope.assetDetailHeading = HEADING_CUSTOMER_PARENT;
        scope.accountIds.add(accountId);
        for (Account facilityAccount : AccountSelector.selectFacilityAccountsByParentId(accountId)) {
            scope.accountIds.add(facilityAccount.Id);
        }

        return scope;
    }

    private static void addAffiliatedCustomerParentScope(Id idnOrGpoAccountId, Set<Id> accountIds) {
        Set<Id> relatedAccountIds = new Set<Id>();

        for (AccountAccountRelationship__c affiliationRecord :
            AccountAccountRelationshipSelector.selectAffiliationsByAccountIds(
                new Set<Id>{ idnOrGpoAccountId }
            )) {
            Id relatedAccountId = idnOrGpoAccountId == affiliationRecord.ParentAccount__c
                ? affiliationRecord.ChildAccount__c
                : affiliationRecord.ParentAccount__c;

            if (relatedAccountId != null) {
                relatedAccountIds.add(relatedAccountId);
            }
        }

        if (relatedAccountIds.isEmpty()) {
            return;
        }

        Set<Id> customerParentIds = new Set<Id>();
        for (Account relatedAccount : AccountSelector.selectByIds(relatedAccountIds)) {
            if (relatedAccount.Type != 'IDN' && relatedAccount.Type != 'GPO') {
                customerParentIds.add(relatedAccount.Id);
            }
        }

        accountIds.addAll(customerParentIds);

        for (Account facilityAccount : AccountSelector.selectFacilityAccountsByParentIds(customerParentIds)) {
            accountIds.add(facilityAccount.Id);
        }
    }
}