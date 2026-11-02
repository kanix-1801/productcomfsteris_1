/**
 * @author Sahithi PWC
 * @date 07-24-2026
 *
 * @group Enterprise Pipeline
 *
 * @description
 * Builds consolidated enterprise pipeline data for Customer, IDN, and GPO Accounts.
 * Customer Accounts use the standard Account.ParentId hierarchy; IDN and GPO Accounts
 * use AccountAccountRelationship__c child Accounts.
 */
public with sharing class EnterprisePipelineService {

    @TestVisible
    private static final String ACCOUNT_TYPE_CUSTOMER = 'Customer';
    @TestVisible
    private static final String ACCOUNT_TYPE_IDN = 'IDN';
    @TestVisible
    private static final String ACCOUNT_TYPE_GPO = 'GPO';

    @TestVisible
    private static Boolean forceExceptionForTest = false;

    public class PipelineSummary {
        @AuraEnabled public Boolean isEligible;
        @AuraEnabled public String accountType;
        @AuraEnabled public Integer childAccountCount;
        @AuraEnabled public Integer opportunityCount;
        @AuraEnabled public Decimal totalPipelineAmount;
        @AuraEnabled public List<PipelineOpportunity> opportunities;
        @AuraEnabled public List<StageSummary> stageSummaries;
    }

    public class PipelineOpportunity {
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String stageName;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Date closeDate;
        @AuraEnabled public String ownerName;
    }

    public class StageSummary {
        @AuraEnabled public String stageName;
        @AuraEnabled public Integer opportunityCount;
        @AuraEnabled public Decimal totalAmount;
    }

    /**
     * @description Returns consolidated pipeline data for a Customer, IDN, or GPO Account.
     * @param accountId Account record Id from the Account record page.
     * @return PipelineSummary containing child location and opportunity roll-up data.
     */
    public static PipelineSummary getPipelineRollup(Id accountId) {
        if (Test.isRunningTest() && forceExceptionForTest) {
            throw new EnterprisePipelineException('Forced exception for test coverage.');
        }

        PipelineSummary summary = new PipelineSummary();
        summary.isEligible = false;
        summary.childAccountCount = 0;
        summary.opportunityCount = 0;
        summary.totalPipelineAmount = 0;
        summary.opportunities = new List<PipelineOpportunity>();
        summary.stageSummaries = new List<StageSummary>();

        if (accountId == null) {
            return summary;
        }

        String accountType = AccountAccountRelationshipService.getAccountType(accountId);
        summary.accountType = accountType;

        if (!isEligibleAccountType(accountType)) {
            return summary;
        }

        summary.isEligible = true;

        Set<Id> childAccountIds = resolveChildAccountIds(accountId, accountType);
        summary.childAccountCount = childAccountIds.size();

        if (childAccountIds.isEmpty()) {
            return summary;
        }

        List<Opportunity> opportunities =
            OpportunitySelector.selectOpenPipelineByAccountIds(childAccountIds);

        Map<String, StageSummary> stageSummaryByName = new Map<String, StageSummary>();

        for (Opportunity opportunity : opportunities) {
            PipelineOpportunity pipelineOpportunity = new PipelineOpportunity();
            pipelineOpportunity.opportunityId = opportunity.Id;
            pipelineOpportunity.opportunityName = opportunity.Name;
            pipelineOpportunity.accountId = opportunity.AccountId;
            pipelineOpportunity.accountName = opportunity.Account.Name;
            pipelineOpportunity.stageName = opportunity.StageName;
            pipelineOpportunity.amount = opportunity.Amount;
            pipelineOpportunity.closeDate = opportunity.CloseDate;
            pipelineOpportunity.ownerName = opportunity.Owner.Name;
            summary.opportunities.add(pipelineOpportunity);

            Decimal opportunityAmount = opportunity.Amount == null ? 0 : opportunity.Amount;
            summary.totalPipelineAmount += opportunityAmount;

            StageSummary stageSummary = stageSummaryByName.get(opportunity.StageName);
            if (stageSummary == null) {
                stageSummary = new StageSummary();
                stageSummary.stageName = opportunity.StageName;
                stageSummary.opportunityCount = 0;
                stageSummary.totalAmount = 0;
                stageSummaryByName.put(opportunity.StageName, stageSummary);
            }

            stageSummary.opportunityCount++;
            stageSummary.totalAmount += opportunityAmount;
        }

        summary.opportunityCount = summary.opportunities.size();
        summary.stageSummaries = new List<StageSummary>(stageSummaryByName.values());
        summary.stageSummaries.sort(new StageSummaryComparator());

        return summary;
    }

    @TestVisible
    private static Boolean isEligibleAccountType(String accountType) {
        return accountType == ACCOUNT_TYPE_CUSTOMER
            || accountType == ACCOUNT_TYPE_IDN
            || accountType == ACCOUNT_TYPE_GPO;
    }

    @TestVisible
    private static Set<Id> resolveChildAccountIds(Id accountId, String accountType) {
        if (accountId == null || String.isBlank(accountType)) {
            return new Set<Id>();
        }

        if (accountType == ACCOUNT_TYPE_CUSTOMER) {
            return extractAccountIds(
                AccountSelector.selectChildAccountsByParentId(new Set<Id>{ accountId })
            );
        }

        if (accountType == ACCOUNT_TYPE_IDN || accountType == ACCOUNT_TYPE_GPO) {
            return extractChildAccountIds(
                AccountAccountRelationshipSelector.selectByParentAccountIds(new Set<Id>{ accountId })
            );
        }

        return new Set<Id>();
    }

    @TestVisible
    private static Set<Id> extractChildAccountIds(List<AccountAccountRelationship__c> relationships) {
        Set<Id> childAccountIds = new Set<Id>();

        if (relationships == null) {
            return childAccountIds;
        }

        for (AccountAccountRelationship__c relationship : relationships) {
            if (relationship.ChildAccount__c != null) {
                childAccountIds.add(relationship.ChildAccount__c);
            }
        }

        return childAccountIds;
    }

    @TestVisible
    private static Set<Id> extractAccountIds(List<Account> accounts) {
        Set<Id> accountIds = new Set<Id>();

        if (accounts == null) {
            return accountIds;
        }

        for (Account accountRecord : accounts) {
            if (accountRecord.Id != null) {
                accountIds.add(accountRecord.Id);
            }
        }

        return accountIds;
    }

    private class StageSummaryComparator implements Comparator<StageSummary> {
        public Integer compare(StageSummary first, StageSummary second) {
            String firstStage = first.stageName == null ? '' : first.stageName;
            String secondStage = second.stageName == null ? '' : second.stageName;
            return firstStage.compareTo(secondStage);
        }
    }
}