/*****************************************************************************
 * Class Name       : LSQuoteSelector
 * Test Class       : LSQuoteSelectorTest
 * Author           : Sarthak Pani
 * Date of Dev      : 19th November 2026
 * Last Modified Date   : 19th November 2026
*****************************************************************************/
public with sharing class LSQuoteSelector extends SoqlQueryBuilder {
    public LSQuoteSelector() {
        this.objectName = 'Quote';
    }

    /*****************************************************************************
     * Method Name       : lsSelectByOpportunityIdWithLineItems
     * Author           : Sarthak Pani
     * Date of Dev      : 19th November 2026
     * Last Modified Date   : 19th November 2026
     * Description          : select quotes by opportunity id with line items for LS
    *****************************************************************************/
    
    public static List<Quote> lsSelectByOpportunityIdWithLineItems(
        Id opportunityId,
        String quoteTypeFilter,
        Boolean excludeForecastIneligible,
        Id trialIdFilter,
        Id sampleIdFilter
    ) {
        if (opportunityId == null) {
            return new List<Quote>();
        }

        List<String> whereClauses = new List<String>{ 'OpportunityId = :opportunityId' };
        if (trialIdFilter != null) {
            whereClauses.add('Trial__c = :trialIdFilter');
        } else if (sampleIdFilter != null) {
            whereClauses.add('Sample__c = :sampleIdFilter');
        }
        if (String.isNotBlank(quoteTypeFilter)) {
            whereClauses.add('QuoteType__c = :quoteTypeFilter');
        } else if (excludeForecastIneligible == true) {
            whereClauses.add('IsForecastIneligible__c != true');
        }

        String soql =
            'SELECT Id, Name, QuoteNumber, QuoteNumber__c, ExpirationDate, Description, Status, ' +
            'Approval_Status__c, Quote_Total_Without_Freight__c, TotalPrice, CurrencyIsoCode, ' +
            'LastModifiedDate, LastModifiedDate__c, IsForecastIneligible__c, Forecast_Eligible__c, ' +
            'QuoteForecastConfidence__c, RecordTypeId, QuoteType__c, Trial__c, Sample__c, IsSyncing, ' +
            'SalesConnectionQuoteID__c, SalesConnectionCreateQuoteURL__c, Source_System_ID__c, ' +
            'LSSCDateCreated__c, LSTotalRevenue__c, ' +
            '(SELECT Id, Description, Quantity, UnitPrice, LS_ExtendedPrice__c, ProductCode__c, ' +
            'LS_Status__c, LS_ExpectedOrderDate__c, LS_ExpectedShipDate__c, TotalPrice, ' +
            'Product_FAM_Code__c, Product_Subgroup_Detail_Name__c, SalesCategory__c, TerritoryID__c, ' +
            'UOM__c, SalesConnectionQuoteLineID__c, Total_Unit_Price__c, PricebookEntry.Product2Id, ' +
            'PricebookEntry.Product2.ProductCode, PricebookEntry.Product2.Name ' +
            'FROM QuoteLineItems ORDER BY CreatedDate ASC) ' +
            'FROM Quote WHERE ' + String.join(whereClauses, ' AND ') + ' ' +
            'WITH SYSTEM_MODE ORDER BY CreatedDate DESC';

        return (List<Quote>) Database.query(soql);
    }
    
}