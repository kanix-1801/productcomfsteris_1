/**
 * @description GC-3441 / GC-3500 - Queries used to evaluate Prospect Account SC
 *              sync eligibility and to load payload fields after commit.
 */
public with sharing class ProspectAccountScSyncSelector {
    public static final String ACCOUNT_RECORD_TYPE_PROSPECT = 'Prospect';
    public static final String OPPORTUNITY_RECORD_TYPE_HC_SALES = 'Healthcare_Sales';
    public static final String OPPORTUNITY_RECORD_TYPE_EPP = 'EquipmentPlacementProgram';
    public static final String OPPORTUNITY_RECORD_TYPE_IP = 'InstrumentProcessing';
    public static final String QUOTE_RECORD_TYPE_HC_SALES = 'HCSales';

    /**
     * @description Returns Account Ids that have at least one HC Sales Opportunity
     * with at least one HC Sales Quote. Quote status is ignored.
     * GC-3441 - Include all Healthcare Sales record types, not Capital-only.
     * Life Sciences / other sales families stay excluded.
     */
    public static Set<Id> selectAccountIdsWithHcSalesQuote(Set<Id> accountIds) {
        Set<Id> eligibleAccountIds = new Set<Id>();

        if (accountIds == null || accountIds.isEmpty()) {
            return eligibleAccountIds;
        }

        for (Opportunity opportunityRecord : [
            SELECT AccountId,
                   RecordType.DeveloperName,
                   (
                       SELECT Id, RecordType.DeveloperName
                       FROM Quotes
                       WHERE RecordType.DeveloperName LIKE 'HCSales%'
                       LIMIT 1
                   )
            FROM Opportunity
            WHERE AccountId IN :accountIds
              AND (
                    RecordType.DeveloperName = :OPPORTUNITY_RECORD_TYPE_HC_SALES
                    OR RecordType.DeveloperName = :OPPORTUNITY_RECORD_TYPE_EPP
                    OR RecordType.DeveloperName = :OPPORTUNITY_RECORD_TYPE_IP
                    OR RecordType.DeveloperName LIKE 'HCSales%'
                    OR RecordType.DeveloperName LIKE 'HC_Sales_%'
              )
            WITH SYSTEM_MODE
        ]) {
            if (!isHealthcareSalesOpportunity(opportunityRecord.RecordType?.DeveloperName)) {
                continue;
            }

            if (hasHealthcareSalesQuote(opportunityRecord.Quotes)) {
                eligibleAccountIds.add(opportunityRecord.AccountId);
            }
        }

        return eligibleAccountIds;
    }

    /**
     * @description GC-3441 - Healthcare_Sales, HCSales*, HC_Sales_*, EPP, and IP Opportunity types.
     */
    @TestVisible
    static Boolean isHealthcareSalesOpportunity(String developerName) {
        return String.isNotBlank(developerName) &&
            (
                developerName == OPPORTUNITY_RECORD_TYPE_HC_SALES ||
                developerName == OPPORTUNITY_RECORD_TYPE_EPP ||
                developerName == OPPORTUNITY_RECORD_TYPE_IP ||
                developerName.startsWith('HCSales') ||
                developerName.startsWith('HC_Sales_')
            );
    }

    /**
     * @description GC-3441 - HCSales and other HCSales* Quote types. Status is ignored.
     */
    @TestVisible
    static Boolean hasHealthcareSalesQuote(List<Quote> quotes) {
        if (quotes == null || quotes.isEmpty()) {
            return false;
        }

        for (Quote quoteRecord : quotes) {
            String developerName = quoteRecord.RecordType?.DeveloperName;
            if (
                developerName == QUOTE_RECORD_TYPE_HC_SALES ||
                (String.isNotBlank(developerName) && developerName.startsWith('HCSales'))
            ) {
                return true;
            }
        }

        return false;
    }

    /**
     * @description Loads payload fields for queued Account Ids.
     */
    public static List<Account> selectAccountsForSync(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<Account>();
        }

        return [
            SELECT Id,
                   Name,
                   OrgIDs__c,
                   CustomerClassCode__c,
                   BillingStreet,
                   BillingCity,
                   BillingState,
                   BillingPostalCode,
                   BillingCountry,
                   CreatedDate,
                   LastModifiedDate,
                   Price_List__c,
                   Price_List__r.Price_List_ID__c,
                   CreatedBy.EmployeeNumber__c,
                   CreatedBy.EmployeeNumber,
                   LastModifiedBy.EmployeeNumber__c,
                   LastModifiedBy.EmployeeNumber
            FROM Account
            WHERE Id IN :accountIds
              AND RecordType.DeveloperName = :ACCOUNT_RECORD_TYPE_PROSPECT
            WITH SYSTEM_MODE
            ORDER BY Id
        ];
    }
}