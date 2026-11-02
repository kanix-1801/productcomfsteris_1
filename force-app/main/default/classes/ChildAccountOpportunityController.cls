/**
 * Author: Akash Dahinde
 * Story: GC-2868
 * @description Retrieves Opportunities from child Accounts related through Account.ParentId and AAR.
 *
 * IDN      -> ParentId + AAR
 * GPO      -> ParentId + AAR
 * Customer -> ParentId + AAR
 */
public with sharing class ChildAccountOpportunityController {

    /**
     * @description Returns Opportunities from all related child Accounts.
     * @param accountId Current IDN, GPO, or Customer Account ID.
     * @return ChildOpportunityResponse.
     */
    @AuraEnabled(cacheable=true)
    public static ChildOpportunityResponse getChildAccountOpportunities(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }

        ChildOpportunityResponse response = initializeResponse();
        Set<Id> currentAccountIds = new Set<Id>{ accountId };
        List<Account> currentAccounts = AccountSelector.selectByIds(currentAccountIds);

        if (currentAccounts.isEmpty()) {
            throw new AuraHandledException('The Account does not exist or you do not have access.');
        }

        Account currentAccount = currentAccounts[0];
        response.enterpriseAccountId = currentAccount.Id;
        response.enterpriseAccountName = currentAccount.Name;
        response.enterpriseAccountType = currentAccount.Type;

        if (!EnterpriseAccountEligibilityService.isSupportedAccount(currentAccount)) {
            return response;
        }

        response.displayComponent = true;
        Set<Id> childAccountIds = resolveChildAccountIds(currentAccountIds);
        response.childAccountCount = childAccountIds.size();

        if (childAccountIds.isEmpty()) {
            return response;
        }

        for (Opportunity opportunityRecord : OpportunitySelector.selectByAccountIds(childAccountIds)) {
            response.opportunities.add(createOpportunityRow(opportunityRecord));
        }

        response.totalOpportunityCount = response.opportunities.size();
        return response;
    }

    /**
     * @description Resolves unique child Account IDs through ParentId and AAR.
     * @param parentAccountIds Parent Account IDs.
     * @return Unique child Account IDs.
     */
    private static Set<Id> resolveChildAccountIds(Set<Id> parentAccountIds) {
        Set<Id> childAccountIds = new Set<Id>();

        for (Account childAccount : AccountSelector.selectByParentIds(parentAccountIds)) {
            childAccountIds.add(childAccount.Id);
        }

        List<AccountAccountRelationship__c> relationships =
            AccountAccountRelationshipSelector.selectMembersByParentIds(parentAccountIds);

        for (AccountAccountRelationship__c relationship : relationships) {
            if (relationship.ChildAccount__c != null) {
                childAccountIds.add(relationship.ChildAccount__c);
            }
        }

        return childAccountIds;
    }

    private static OpportunityRow createOpportunityRow(Opportunity opportunityRecord) {
        OpportunityRow row = new OpportunityRow();
        row.opportunityId = opportunityRecord.Id;
        row.opportunityName = opportunityRecord.Name;
        row.accountId = opportunityRecord.AccountId;
        row.accountName = opportunityRecord.Account != null ? opportunityRecord.Account.Name : null;
        row.accountType = opportunityRecord.Account != null ? opportunityRecord.Account.Type : null;
        row.stageName = opportunityRecord.StageName;
        row.amount = opportunityRecord.Amount;
        row.closeDate = opportunityRecord.CloseDate;
        row.ownerId = opportunityRecord.OwnerId;
        row.ownerName = opportunityRecord.Owner != null ? opportunityRecord.Owner.Name : null;
        row.isClosed = opportunityRecord.IsClosed;
        row.isWon = opportunityRecord.IsWon;
        row.probability = opportunityRecord.Probability;
        row.forecastCategory = opportunityRecord.ForecastCategoryName;
        row.lastModifiedDate = opportunityRecord.LastModifiedDate;
        return row;
    }

    private static ChildOpportunityResponse initializeResponse() {
        ChildOpportunityResponse response = new ChildOpportunityResponse();
        response.displayComponent = false;
        response.resultLimitReached = false;
        response.childAccountCount = 0;
        response.totalOpportunityCount = 0;
        response.opportunities = new List<OpportunityRow>();
        return response;
    }

    public class ChildOpportunityResponse {
        @AuraEnabled public Boolean displayComponent;
        @AuraEnabled public Boolean resultLimitReached;
        @AuraEnabled public Id enterpriseAccountId;
        @AuraEnabled public String enterpriseAccountName;
        @AuraEnabled public String enterpriseAccountType;
        @AuraEnabled public Integer childAccountCount;
        @AuraEnabled public Integer totalOpportunityCount;
        @AuraEnabled public List<OpportunityRow> opportunities;
    }

    public class OpportunityRow {
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String accountType;
        @AuraEnabled public String stageName;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Date closeDate;
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Boolean isClosed;
        @AuraEnabled public Boolean isWon;
        @AuraEnabled public Decimal probability;
        @AuraEnabled public String forecastCategory;
        @AuraEnabled public Datetime lastModifiedDate;
    }
}