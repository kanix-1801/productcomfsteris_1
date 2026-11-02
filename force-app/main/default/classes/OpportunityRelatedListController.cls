/**
 * Author: Akash Dahinde
 * Story: GC-2868
 * @description Retrieves Opportunities directly related to the current Account.
 */
public with sharing class OpportunityRelatedListController {
 /**
     * @description Returns Opportunities directly related to the current Account.
     * @param accountId Current Account ID.
     * @return DirectOpportunityResponse.
     */
    @AuraEnabled(cacheable=true)
    public static DirectOpportunityResponse getDirectOpportunities(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }

        DirectOpportunityResponse response = initializeResponse();
        Set<Id> accountIds = new Set<Id>{ accountId };
        List<Account> accounts = AccountSelector.selectByIds(accountIds);

        if (accounts.isEmpty()) {
            throw new AuraHandledException(
                'The Account does not exist or you do not have access.'
            );
        }

        Account currentAccount = accounts[0];
        response.accountId = currentAccount.Id;
        response.accountName = currentAccount.Name;

        List<Opportunity> opportunities =
            OpportunitySelector.selectByAccountIds(accountIds);

        for (Opportunity opportunityRecord : opportunities) {
            response.opportunities.add(
                createOpportunityRow(opportunityRecord)
            );
        }

        response.totalOpportunityCount = response.opportunities.size();
        return response;
    }

    private static OpportunityRow createOpportunityRow(
        Opportunity opportunityRecord
    ) {
        OpportunityRow row = new OpportunityRow();
        row.opportunityId = opportunityRecord.Id;
        row.opportunityName = opportunityRecord.Name;
        row.accountId = opportunityRecord.AccountId;
        row.accountName = opportunityRecord.Account != null
            ? opportunityRecord.Account.Name
            : null;
        row.stageName = opportunityRecord.StageName;
        row.amount = opportunityRecord.Amount;
        row.closeDate = opportunityRecord.CloseDate;
        row.ownerId = opportunityRecord.OwnerId;
        row.ownerName = opportunityRecord.Owner != null
            ? opportunityRecord.Owner.Name
            : null;
        row.isClosed = opportunityRecord.IsClosed;
        row.isWon = opportunityRecord.IsWon;
        row.probability = opportunityRecord.Probability;
        row.forecastCategory = opportunityRecord.ForecastCategoryName;
        row.lastModifiedDate = opportunityRecord.LastModifiedDate;
        return row;
    }

    private static DirectOpportunityResponse initializeResponse() {
        DirectOpportunityResponse response =
            new DirectOpportunityResponse();

        response.totalOpportunityCount = 0;
        response.opportunities = new List<OpportunityRow>();
        return response;
    }

    public class DirectOpportunityResponse {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Integer totalOpportunityCount;
        @AuraEnabled public List<OpportunityRow> opportunities;
    }

    public class OpportunityRow {
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
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