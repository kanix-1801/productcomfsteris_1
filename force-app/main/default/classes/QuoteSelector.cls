/**
* @author PWC Developer
* @date 2026/06/10
*
* @group Generate Quote
*
* @description
* GC-2642 Selector class for Querying Quote Records.
* Uses SYSTEM_MODE so quote line PSAM/FAM fields remain readable for grouping display.
*/
public with sharing class QuoteSelector extends SoqlQueryBuilder {
    /**
     * @description GW-3600 - Binds this selector to Quote for SoqlQueryBuilder queries.
     */
    public QuoteSelector() {
        this.objectName = 'Quote';
    }

    public static final String CLOSED_STATUS_VALUE = 'Closed';
    public static final String OPEN_STATUS_VALUE = 'Open';

    /**
     * @description Selects Quotes and related line items for an Opportunity.
     * @param opportunityId Opportunity Id.
     * @return Matching Quote records with child Quote Line Items.
     */
    public static List<Quote> selectByOpportunityIdWithLineItems(Id opportunityId) {
        return selectByOpportunityIdWithLineItems(opportunityId, null);
    }

    /**
     * @description Selects Quotes and related line items for an Opportunity.
     * @param opportunityId Opportunity Id.
     * @param quoteTypeFilter Optional QuoteType__c value to filter results.
     * @return Matching Quote records with child Quote Line Items.
     */
    public static List<Quote> selectByOpportunityIdWithLineItems(Id opportunityId, String quoteTypeFilter) {
        return selectByOpportunityIdWithLineItems(opportunityId, quoteTypeFilter, false);
    }

    /**
     * @description Selects Quotes and related line items for an Opportunity.
     * @param opportunityId Opportunity Id.
     * @param quoteTypeFilter Optional QuoteType__c value to filter results.
     * @param excludeForecastIneligible When true, omit forecast-ineligible quotes.
     * @return Matching Quote records with child Quote Line Items.
     */
    public static List<Quote> selectByOpportunityIdWithLineItems(
        Id opportunityId,
        String quoteTypeFilter,
        Boolean excludeForecastIneligible
    ) {
        return selectByOpportunityIdWithLineItems(
            opportunityId,
            quoteTypeFilter,
            excludeForecastIneligible,
            null
        );
    }

    /**
     * @description Selects Quotes and related line items for an Opportunity.
     * @param opportunityId Opportunity Id.
     * @param quoteTypeFilter Optional QuoteType__c value to filter results.
     * @param excludeForecastIneligible When true, omit forecast-ineligible quotes.
     * @param trialIdFilter Optional Trial__c Id to limit results to one Trial record.
     * @return Matching Quote records with child Quote Line Items.
     */
    public static List<Quote> selectByOpportunityIdWithLineItems(
        Id opportunityId,
        String quoteTypeFilter,
        Boolean excludeForecastIneligible,
        Id trialIdFilter
    ) {
        return selectByOpportunityIdWithLineItems(
            opportunityId,
            quoteTypeFilter,
            excludeForecastIneligible,
            trialIdFilter,
            null
        );
    }

    /**
     * @description Selects Quotes and related line items for an Opportunity.
     * @param opportunityId Opportunity Id.
     * @param quoteTypeFilter Optional QuoteType__c value to filter results.
     * @param excludeForecastIneligible When true, omit forecast-ineligible quotes.
     * @param trialIdFilter Optional Trial__c Id to limit results to one Trial record.
     * @param sampleIdFilter Optional Sample__c Id to limit results to one Sample record.
     * @return Matching Quote records with child Quote Line Items.
     */
    public static List<Quote> selectByOpportunityIdWithLineItems(
        Id opportunityId,
        String quoteTypeFilter,
        Boolean excludeForecastIneligible,
        Id trialIdFilter,
        Id sampleIdFilter
    ) {
        if (opportunityId == null) {
            return new List<Quote>();
        }

        if (trialIdFilter != null) {
            if (String.isNotBlank(quoteTypeFilter)) {
                return [
                    SELECT Id,
                        Name,
                        CurrencyIsoCode,
                        QuoteNumber,
                        QuoteNumber__c,
                        ExpirationDate,
                        Description,
                        Status,
                        Approval_Status__c,
                        Quote_Total_Without_Freight__c,
                        TotalPrice,
                        LastModifiedDate,
                        LastModifiedDate__c,
                        IsForecastIneligible__c,
                        Forecast_Eligible__c,
                        QuoteForecastConfidence__c,
                        RecordTypeId,
                        QuoteType__c,
                        Trial__c,
                        IsSyncing,
                        SalesConnectionQuoteID__c,
                        SalesConnectionCreateQuoteURL__c,
                        Source_System_ID__c,
                        (
                            SELECT Id,
                                Description,
                                Quantity,
                                UnitPrice,
                                TotalPrice,
                                Product_FAM_Code__c,
                                Product_Subgroup_Detail_Name__c,
                                SalesCategory__c,
                                TerritoryID__c,
                                UOM__c,
                                SalesConnectionQuoteLineID__c,
                                Total_Unit_Price__c,
                                PricebookEntry.Product2Id,
                                PricebookEntry.Product2.ProductCode,
                                PricebookEntry.Product2.Name
                            FROM QuoteLineItems
                            ORDER BY CreatedDate ASC
                        )
                    FROM Quote
                    WHERE OpportunityId = :opportunityId
                      AND QuoteType__c = :quoteTypeFilter
                      AND Trial__c = :trialIdFilter
                    WITH SYSTEM_MODE
                    ORDER BY CreatedDate DESC
                ];
            }

            if (excludeForecastIneligible == true) {
                return [
                    SELECT Id,
                        Name,
                        CurrencyIsoCode,
                        QuoteNumber,
                        QuoteNumber__c,
                        ExpirationDate,
                        Description,
                        Status,
                        Approval_Status__c,
                        Quote_Total_Without_Freight__c,
                        TotalPrice,
                        LastModifiedDate,
                        LastModifiedDate__c,
                        IsForecastIneligible__c,
                        Forecast_Eligible__c,
                        QuoteForecastConfidence__c,
                        RecordTypeId,
                        QuoteType__c,
                        Trial__c,
                        IsSyncing,
                        SalesConnectionQuoteID__c,
                        SalesConnectionCreateQuoteURL__c,
                        Source_System_ID__c,
                        (
                            SELECT Id,
                                Description,
                                Quantity,
                                UnitPrice,
                                TotalPrice,
                                Product_FAM_Code__c,
                                Product_Subgroup_Detail_Name__c,
                                SalesCategory__c,
                                TerritoryID__c,
                                UOM__c,
                                SalesConnectionQuoteLineID__c,
                                Total_Unit_Price__c,
                                PricebookEntry.Product2Id,
                                PricebookEntry.Product2.ProductCode,
                                PricebookEntry.Product2.Name
                            FROM QuoteLineItems
                            ORDER BY CreatedDate ASC
                        )
                    FROM Quote
                    WHERE OpportunityId = :opportunityId
                      AND Trial__c = :trialIdFilter
                      AND IsForecastIneligible__c != true
                    WITH SYSTEM_MODE
                    ORDER BY CreatedDate DESC
                ];
            }

            return [
                SELECT Id,
                    Name,
                    CurrencyIsoCode,
                    QuoteNumber,
                    QuoteNumber__c,
                    ExpirationDate,
                    Description,
                    Status,
                    Approval_Status__c,
                    Quote_Total_Without_Freight__c,
                    TotalPrice,
                    LastModifiedDate,
                    LastModifiedDate__c,
                    IsForecastIneligible__c,
                    Forecast_Eligible__c,
                    QuoteForecastConfidence__c,
                    RecordTypeId,
                    QuoteType__c,
                    Trial__c,
                    IsSyncing,
                    SalesConnectionQuoteID__c,
                    SalesConnectionCreateQuoteURL__c,
                    Source_System_ID__c,
                    (
                        SELECT Id,
                            Description,
                            Quantity,
                            UnitPrice,
                            TotalPrice,
                            Product_FAM_Code__c,
                            Product_Subgroup_Detail_Name__c,
                            SalesCategory__c,
                            TerritoryID__c,
                            UOM__c,
                            SalesConnectionQuoteLineID__c,
                            Total_Unit_Price__c,
                            PricebookEntry.Product2Id,
                            PricebookEntry.Product2.ProductCode,
                            PricebookEntry.Product2.Name
                        FROM QuoteLineItems
                        ORDER BY CreatedDate ASC
                    )
                FROM Quote
                WHERE OpportunityId = :opportunityId
                  AND Trial__c = :trialIdFilter
                WITH SYSTEM_MODE
                ORDER BY CreatedDate DESC
            ];
        }

        if (sampleIdFilter != null) {
            if (String.isNotBlank(quoteTypeFilter)) {
                return [
                    SELECT Id,
                        Name,
                        CurrencyIsoCode,
                        QuoteNumber,
                        QuoteNumber__c,
                        ExpirationDate,
                        Description,
                        Status,
                        Approval_Status__c,
                        Quote_Total_Without_Freight__c,
                        TotalPrice,
                        LastModifiedDate,
                        LastModifiedDate__c,
                        IsForecastIneligible__c,
                        Forecast_Eligible__c,
                        QuoteForecastConfidence__c,
                        RecordTypeId,
                        QuoteType__c,
                        Sample__c,
                        IsSyncing,
                        SalesConnectionQuoteID__c,
                        SalesConnectionCreateQuoteURL__c,
                        Source_System_ID__c,
                        (
                            SELECT Id,
                                Description,
                                Quantity,
                                UnitPrice,
                                TotalPrice,
                                Product_FAM_Code__c,
                                Product_Subgroup_Detail_Name__c,
                                SalesCategory__c,
                                TerritoryID__c,
                                UOM__c,
                                SalesConnectionQuoteLineID__c,
                                Total_Unit_Price__c,
                                PricebookEntry.Product2Id,
                                PricebookEntry.Product2.ProductCode,
                                PricebookEntry.Product2.Name
                            FROM QuoteLineItems
                            ORDER BY CreatedDate ASC
                        )
                    FROM Quote
                    WHERE OpportunityId = :opportunityId
                      AND QuoteType__c = :quoteTypeFilter
                      AND Sample__c = :sampleIdFilter
                    WITH SYSTEM_MODE
                    ORDER BY CreatedDate DESC
                ];
            }

            if (excludeForecastIneligible == true) {
                return [
                    SELECT Id,
                        Name,
                        CurrencyIsoCode,
                        QuoteNumber,
                        QuoteNumber__c,
                        ExpirationDate,
                        Description,
                        Status,
                        Approval_Status__c,
                        Quote_Total_Without_Freight__c,
                        TotalPrice,
                        LastModifiedDate,
                        LastModifiedDate__c,
                        IsForecastIneligible__c,
                        Forecast_Eligible__c,
                        QuoteForecastConfidence__c,
                        RecordTypeId,
                        QuoteType__c,
                        Sample__c,
                        IsSyncing,
                        SalesConnectionQuoteID__c,
                        SalesConnectionCreateQuoteURL__c,
                        Source_System_ID__c,
                        (
                            SELECT Id,
                                Description,
                                Quantity,
                                UnitPrice,
                                TotalPrice,
                                Product_FAM_Code__c,
                                Product_Subgroup_Detail_Name__c,
                                SalesCategory__c,
                                TerritoryID__c,
                                UOM__c,
                                SalesConnectionQuoteLineID__c,
                                Total_Unit_Price__c,
                                PricebookEntry.Product2Id,
                                PricebookEntry.Product2.ProductCode,
                                PricebookEntry.Product2.Name
                            FROM QuoteLineItems
                            ORDER BY CreatedDate ASC
                        )
                    FROM Quote
                    WHERE OpportunityId = :opportunityId
                      AND Sample__c = :sampleIdFilter
                      AND IsForecastIneligible__c != true
                    WITH SYSTEM_MODE
                    ORDER BY CreatedDate DESC
                ];
            }

            return [
                SELECT Id,
                    Name,
                    CurrencyIsoCode,
                    QuoteNumber,
                    QuoteNumber__c,
                    ExpirationDate,
                    Description,
                    Status,
                    Approval_Status__c,
                    Quote_Total_Without_Freight__c,
                    TotalPrice,
                    LastModifiedDate,
                    LastModifiedDate__c,
                    IsForecastIneligible__c,
                    Forecast_Eligible__c,
                    QuoteForecastConfidence__c,
                    RecordTypeId,
                    QuoteType__c,
                    Sample__c,
                    IsSyncing,
                    SalesConnectionQuoteID__c,
                    SalesConnectionCreateQuoteURL__c,
                    Source_System_ID__c,
                    (
                        SELECT Id,
                            Description,
                            Quantity,
                            UnitPrice,
                            TotalPrice,
                            Product_FAM_Code__c,
                            Product_Subgroup_Detail_Name__c,
                            SalesCategory__c,
                            TerritoryID__c,
                            UOM__c,
                            SalesConnectionQuoteLineID__c,
                            Total_Unit_Price__c,
                            PricebookEntry.Product2Id,
                            PricebookEntry.Product2.ProductCode,
                            PricebookEntry.Product2.Name
                        FROM QuoteLineItems
                        ORDER BY CreatedDate ASC
                    )
                FROM Quote
                WHERE OpportunityId = :opportunityId
                  AND Sample__c = :sampleIdFilter
                WITH SYSTEM_MODE
                ORDER BY CreatedDate DESC
            ];
        }

        if (String.isNotBlank(quoteTypeFilter)) {
            return [
                SELECT Id,
                    Name,
                    CurrencyIsoCode,
                    QuoteNumber,
                    QuoteNumber__c,
                    ExpirationDate,
                    Description,
                    Status,
                    Approval_Status__c,
                    Quote_Total_Without_Freight__c,
                    TotalPrice,
                    LastModifiedDate,
                    LastModifiedDate__c,
                    IsForecastIneligible__c,
                    Forecast_Eligible__c,
                    QuoteForecastConfidence__c,
                    RecordTypeId,
                    QuoteType__c,
                    IsSyncing,
                    SalesConnectionQuoteID__c,
                    SalesConnectionCreateQuoteURL__c,
                    Source_System_ID__c,
                    (
                        SELECT Id,
                            Description,
                            Quantity,
                            UnitPrice,
                            TotalPrice,
                            Product_FAM_Code__c,
                            Product_Subgroup_Detail_Name__c,
                            SalesCategory__c,
                            TerritoryID__c,
                            UOM__c,
                            SalesConnectionQuoteLineID__c,
                            Total_Unit_Price__c,
                            PricebookEntry.Product2Id,
                            PricebookEntry.Product2.ProductCode,
                            PricebookEntry.Product2.Name
                        FROM QuoteLineItems
                        ORDER BY CreatedDate ASC
                    )
                FROM Quote
                WHERE OpportunityId = :opportunityId
                  AND QuoteType__c = :quoteTypeFilter
                WITH SYSTEM_MODE
                ORDER BY CreatedDate DESC
            ];
        }

        if (excludeForecastIneligible == true) {
            return [
                SELECT Id,
                    Name,
                    CurrencyIsoCode,
                    QuoteNumber,
                    QuoteNumber__c,
                    ExpirationDate,
                    Description,
                    Status,
                    Approval_Status__c,
                    Quote_Total_Without_Freight__c,
                    TotalPrice,
                    LastModifiedDate,
                    LastModifiedDate__c,
                    IsForecastIneligible__c,
                    Forecast_Eligible__c,
                    QuoteForecastConfidence__c,
                    RecordTypeId,
                    QuoteType__c,
                    IsSyncing,
                    SalesConnectionQuoteID__c,
                    SalesConnectionCreateQuoteURL__c,
                    Source_System_ID__c,
                    (
                        SELECT Id,
                            Description,
                            Quantity,
                            UnitPrice,
                            TotalPrice,
                            Product_FAM_Code__c,
                            Product_Subgroup_Detail_Name__c,
                            SalesCategory__c,
                            TerritoryID__c,
                            UOM__c,
                            SalesConnectionQuoteLineID__c,
                            Total_Unit_Price__c,
                            PricebookEntry.Product2Id,
                            PricebookEntry.Product2.ProductCode,
                            PricebookEntry.Product2.Name
                        FROM QuoteLineItems
                        ORDER BY CreatedDate ASC
                    )
                FROM Quote
                WHERE OpportunityId = :opportunityId
                  AND IsForecastIneligible__c != true
                WITH SYSTEM_MODE
                ORDER BY CreatedDate DESC
            ];
        }

        return [
            SELECT Id,
                Name,
                CurrencyIsoCode,
                QuoteNumber,
                QuoteNumber__c,
                ExpirationDate,
                Description,
                Status,
                Approval_Status__c,
                Quote_Total_Without_Freight__c,
                TotalPrice,
                LastModifiedDate,
                LastModifiedDate__c,
                IsForecastIneligible__c,
                Forecast_Eligible__c,
                QuoteForecastConfidence__c,
                RecordTypeId,
                QuoteType__c,
                IsSyncing,
                SalesConnectionQuoteID__c,
                SalesConnectionCreateQuoteURL__c,
                Source_System_ID__c,
                (
                    SELECT Id,
                        Description,
                        Quantity,
                        UnitPrice,
                        TotalPrice,
                        Product_FAM_Code__c,
                        Product_Subgroup_Detail_Name__c,
                        SalesCategory__c,
                        TerritoryID__c,
                        UOM__c,
                        SalesConnectionQuoteLineID__c,
                        Total_Unit_Price__c,
                        PricebookEntry.Product2Id,
                        PricebookEntry.Product2.ProductCode,
                        PricebookEntry.Product2.Name
                    FROM QuoteLineItems
                    ORDER BY CreatedDate ASC
                )
            FROM Quote
            WHERE OpportunityId = :opportunityId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ];
    }

    /**
     * @description Counts Quotes for an Opportunity.
     * @param opportunityId Opportunity Id.
     * @return Number of existing quotes.
     */
    public static Integer countByOpportunityId(Id opportunityId) {
        return countByOpportunityId(opportunityId, null);
    }

    /**
     * @description Counts Quotes for an Opportunity.
     * @param opportunityId Opportunity Id.
     * @param quoteTypeFilter Optional QuoteType__c value to filter results.
     * @return Number of existing quotes.
     */
    public static Integer countByOpportunityId(Id opportunityId, String quoteTypeFilter) {
        return countByOpportunityId(opportunityId, quoteTypeFilter, false);
    }

    /**
     * @description Counts Quotes for an Opportunity.
     * @param opportunityId Opportunity Id.
     * @param quoteTypeFilter Optional QuoteType__c value to filter results.
     * @param excludeForecastIneligible When true, omit forecast-ineligible quotes.
     * @return Number of existing quotes.
     */
    public static Integer countByOpportunityId(
        Id opportunityId,
        String quoteTypeFilter,
        Boolean excludeForecastIneligible
    ) {
        return countByOpportunityId(
            opportunityId,
            quoteTypeFilter,
            excludeForecastIneligible,
            null
        );
    }

    /**
     * @description Counts Quotes for an Opportunity.
     * @param opportunityId Opportunity Id.
     * @param quoteTypeFilter Optional QuoteType__c value to filter results.
     * @param excludeForecastIneligible When true, omit forecast-ineligible quotes.
     * @param trialIdFilter Optional Trial__c Id to limit results to one Trial record.
     * @return Number of existing quotes.
     */
    public static Integer countByOpportunityId(
        Id opportunityId,
        String quoteTypeFilter,
        Boolean excludeForecastIneligible,
        Id trialIdFilter
    ) {
        return countByOpportunityId(
            opportunityId,
            quoteTypeFilter,
            excludeForecastIneligible,
            trialIdFilter,
            null
        );
    }

    /**
     * @description Counts Quotes for an Opportunity.
     * @param opportunityId Opportunity Id.
     * @param quoteTypeFilter Optional QuoteType__c value to filter results.
     * @param excludeForecastIneligible When true, omit forecast-ineligible quotes.
     * @param trialIdFilter Optional Trial__c Id to limit results to one Trial record.
     * @param sampleIdFilter Optional Sample__c Id to limit results to one Sample record.
     * @return Number of existing quotes.
     */
    public static Integer countByOpportunityId(
        Id opportunityId,
        String quoteTypeFilter,
        Boolean excludeForecastIneligible,
        Id trialIdFilter,
        Id sampleIdFilter
    ) {
        if (opportunityId == null) {
            return 0;
        }

        if (trialIdFilter != null) {
            if (String.isNotBlank(quoteTypeFilter)) {
                return [
                    SELECT COUNT()
                    FROM Quote
                    WHERE OpportunityId = :opportunityId
                      AND QuoteType__c = :quoteTypeFilter
                      AND Trial__c = :trialIdFilter
                    WITH SYSTEM_MODE
                ];
            }

            if (excludeForecastIneligible == true) {
                return [
                    SELECT COUNT()
                    FROM Quote
                    WHERE OpportunityId = :opportunityId
                      AND Trial__c = :trialIdFilter
                      AND IsForecastIneligible__c != true
                    WITH SYSTEM_MODE
                ];
            }

            return [
                SELECT COUNT()
                FROM Quote
                WHERE OpportunityId = :opportunityId
                  AND Trial__c = :trialIdFilter
                WITH SYSTEM_MODE
            ];
        }

        if (sampleIdFilter != null) {
            if (String.isNotBlank(quoteTypeFilter)) {
                return [
                    SELECT COUNT()
                    FROM Quote
                    WHERE OpportunityId = :opportunityId
                      AND QuoteType__c = :quoteTypeFilter
                      AND Sample__c = :sampleIdFilter
                    WITH SYSTEM_MODE
                ];
            }

            if (excludeForecastIneligible == true) {
                return [
                    SELECT COUNT()
                    FROM Quote
                    WHERE OpportunityId = :opportunityId
                      AND Sample__c = :sampleIdFilter
                      AND IsForecastIneligible__c != true
                    WITH SYSTEM_MODE
                ];
            }

            return [
                SELECT COUNT()
                FROM Quote
                WHERE OpportunityId = :opportunityId
                  AND Sample__c = :sampleIdFilter
                WITH SYSTEM_MODE
            ];
        }

        if (String.isNotBlank(quoteTypeFilter)) {
            return [
                SELECT COUNT()
                FROM Quote
                WHERE OpportunityId = :opportunityId
                  AND QuoteType__c = :quoteTypeFilter
                WITH SYSTEM_MODE
            ];
        }

        if (excludeForecastIneligible == true) {
            return [
                SELECT COUNT()
                FROM Quote
                WHERE OpportunityId = :opportunityId
                  AND IsForecastIneligible__c != true
                WITH SYSTEM_MODE
            ];
        }

        return [
            SELECT COUNT()
            FROM Quote
            WHERE OpportunityId = :opportunityId
            WITH SYSTEM_MODE
        ];
    }

    /**
     * @description Selects a Quote by Id.
     * @param quoteId Quote Id.
     * @return Matching Quote record, or null when not found.
     */
    public static Quote selectById(Id quoteId) {
        if (quoteId == null) {
            return null;
        }

        List<Quote> quoteList = [
            SELECT Id,
                Name,
                CurrencyIsoCode,
                QuoteNumber,
                QuoteNumber__c,
                SalesConnectionQuoteID__c,
                SalesConnectionCreateQuoteURL__c,
                Source_System_ID__c
            FROM Quote
            WHERE Id = :quoteId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        return quoteList.isEmpty() ? null : quoteList[0];
    }

    /**
     * @description Selects Quotes and related line items by Id set.
     * @param quoteIds Quote Id set.
     * @return Matching Quote records with child Quote Line Items.
     */
    public static List<Quote> selectByIdsWithLineItems(Set<Id> quoteIds) {
        if (quoteIds == null || quoteIds.isEmpty()) {
            return new List<Quote>();
        }

        return [
            SELECT Id,
                Name,
                CurrencyIsoCode,
                QuoteNumber,
                QuoteNumber__c,
                ExpirationDate,
                Description,
                Status,
                Approval_Status__c,
                Quote_Total_Without_Freight__c,
                TotalPrice,
                LastModifiedDate,
                LastModifiedDate__c,
                IsForecastIneligible__c,
                QuoteForecastConfidence__c,
                IsSyncing,
                SalesConnectionQuoteID__c,
                SalesConnectionCreateQuoteURL__c,
                Source_System_ID__c,
                OpportunityId,
                (
                    SELECT Id,
                        Description,
                        Quantity,
                        UnitPrice,
                        TotalPrice,
                        Product_FAM_Code__c,
                        Product_Subgroup_Detail_Name__c,
                        SalesCategory__c,
                        TerritoryID__c,
                        UOM__c,
                        SalesConnectionQuoteLineID__c,
                        Total_Unit_Price__c,
                        PricebookEntry.Product2Id,
                        PricebookEntry.Product2.ProductCode,
                        PricebookEntry.Product2.Name
                    FROM QuoteLineItems
                    ORDER BY CreatedDate ASC
                )
            FROM Quote
            WHERE Id IN :quoteIds
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ];
    }
    
    /**
     * Retrieves open (non-Closed) Forecast Eligible Quotes for the given Opportunities.
     * Used to block Opportunity closure while forecast-driving quotes remain unresolved. GC 3188
     * @param opportunityIds Opportunity Ids to check.
     * @return Quotes that are Forecast Eligible and not in Closed status, for the given Opportunities.
     */
    public static List<Quote> selectOpenForecastEligibleQuotesByOpportunityIds(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return new List<Quote>();
        }
        Id hcSalesRtId = resolveHcSalesRecordTypeId();
        if (hcSalesRtId == null) {
            return new List<Quote>();
        }
    
        return [
            SELECT Id, OpportunityId, Status, Forecast_Eligible__c
            FROM Quote
            WHERE OpportunityId IN :opportunityIds
              AND Forecast_Eligible__c = true
              AND RecordTypeId = :hcSalesRtId
              AND Status != :CLOSED_STATUS_VALUE
            WITH USER_MODE
        ];
    }

    /**
     * @description Returns Opportunity Ids that already have an open Forecast Eligible HC_Sales quote.
     * @param opportunityIds Opportunity Ids to evaluate.
     * @return Opportunity Ids with at least one open Forecast Eligible quote.
     */
    public static Set<Id> selectOpportunityIdsWithOpenForecastEligibleQuotes(Set<Id> opportunityIds) {
        Set<Id> opportunityIdsWithForecastEligible = new Set<Id>();

        for (Quote quoteRecord : selectOpenForecastEligibleQuotesByOpportunityIds(opportunityIds)) {
            if (quoteRecord.OpportunityId != null) {
                opportunityIdsWithForecastEligible.add(quoteRecord.OpportunityId);
            }
        }

        return opportunityIdsWithForecastEligible;
    }

    /**
     * @description Returns Open quotes eligible for Forecast Eligible management on an Opportunity. GC-3185
     * @param opportunityId Opportunity Id.
     * @return Manageable Quote records.
     */
    public static List<Quote> selectForecastManagementQuotesByOpportunityId(Id opportunityId) {
        if (opportunityId == null) {
            return new List<Quote>();
        }

        return [
            SELECT Id,
                Name,
                CurrencyIsoCode,
                QuoteNumber,
                QuoteNumber__c,
                Status,
                Approval_Status__c,
                Quote_Total_Without_Freight__c,
                TotalPrice,
                Forecast_Eligible__c,
                LastModifiedDate,
                LastModifiedDate__c,
                (
                    SELECT Id,
                        Quantity,
                        UnitPrice,
                        TotalPrice,
                        Total_Unit_Price__c
                    FROM QuoteLineItems
                )
            FROM Quote
            WHERE OpportunityId = :opportunityId
              AND Status NOT IN ('Draft', 'Budget', 'Test', :CLOSED_STATUS_VALUE)
              AND IsForecastIneligible__c != true
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ];
    }

    /**
     * @description Returns Sales Connection quotes used for Forecast Eligible automation. GC-3185
     * @param opportunityIds Opportunity Id set.
     * @return HCSales Quote records for the given Opportunities.
     */
    public static List<Quote> selectSalesConnectionQuotesForForecastEligibleByOpportunityIds(
        Set<Id> opportunityIds
    ) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return new List<Quote>();
        }

        Id hcSalesRecordTypeId = resolveHcSalesRecordTypeId();
        if (hcSalesRecordTypeId == null) {
            return new List<Quote>();
        }

        return [
            SELECT Id,
                OpportunityId,
                QuoteNumber,
                QuoteNumber__c,
                Status,
                Forecast_Eligible__c,
                IsForecastIneligible__c,
                LastModifiedDate,
                LastModifiedDate__c,
                RecordTypeId
            FROM Quote
            WHERE OpportunityId IN :opportunityIds
              AND RecordTypeId = :hcSalesRecordTypeId
            WITH SYSTEM_MODE
        ];
    }

    /**
     * @description Resolves the HCSales Quote record type Id used by forecast automation queries.
     * @return HCSales record type Id, or null when unavailable in the org.
     */
    private static Id resolveHcSalesRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypesByDeveloperName =
            Schema.SObjectType.Quote.getRecordTypeInfosByDeveloperName();

        if (!recordTypesByDeveloperName.containsKey(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME)) {
            return null;
        }

        Schema.RecordTypeInfo recordTypeInfo =
            recordTypesByDeveloperName.get(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME);
        return recordTypeInfo.isAvailable() ? recordTypeInfo.getRecordTypeId() : null;
    }

    /**
     * @description Returns counts of quotes eligible for Opportunity forecast confidence propagation.
     * @param opportunityIds Opportunity Id set.
     * @return Quote counts keyed by Opportunity Id.
     */
    public static Map<Id, Integer> countPropagatableForecastConfidenceQuotesByOpportunityIds(
        Set<Id> opportunityIds
    ) {
        Map<Id, Integer> quoteCountsByOpportunityId = new Map<Id, Integer>();

        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return quoteCountsByOpportunityId;
        }

        Id salesConnectionRecordTypeId = resolveHcSalesRecordTypeId();
        Set<String> includedQuoteTypes = forecastPropagateIncludedQuoteTypes();

        for (AggregateResult aggregateResult : [
            SELECT OpportunityId opportunityId, COUNT(Id) quoteCount
            FROM Quote
            WHERE OpportunityId IN :opportunityIds
              AND (
                    (
                        RecordTypeId = :salesConnectionRecordTypeId
                        AND IsForecastIneligible__c != TRUE
                    )
                    OR QuoteType__c IN :includedQuoteTypes
                )
            WITH SYSTEM_MODE
            GROUP BY OpportunityId
        ]) {
            quoteCountsByOpportunityId.put(
                (Id) aggregateResult.get('opportunityId'),
                (Integer) aggregateResult.get('quoteCount')
            );
        }

        return quoteCountsByOpportunityId;
    }

    /**
     * @description Returns quotes eligible for Opportunity forecast confidence propagation.
     * @param opportunityId Opportunity Id.
     * @return Applicable Quote records.
     */
    public static List<Quote> selectPropagatableForecastConfidenceQuotesByOpportunityId(Id opportunityId) {
        if (opportunityId == null) {
            return new List<Quote>();
        }

        Id salesConnectionRecordTypeId = resolveHcSalesRecordTypeId();
        Set<String> includedQuoteTypes = forecastPropagateIncludedQuoteTypes();

        return [
            SELECT Id,
                Name,
                CurrencyIsoCode,
                QuoteNumber,
                QuoteNumber__c,
                Status,
                QuoteForecastConfidence__c,
                QuoteType__c
            FROM Quote
            WHERE OpportunityId = :opportunityId
              AND (
                    (
                        RecordTypeId = :salesConnectionRecordTypeId
                        AND IsForecastIneligible__c != TRUE
                    )
                    OR QuoteType__c IN :includedQuoteTypes
                )
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC, CreatedDate DESC
        ];
    }

    /**
     * @description Returns open Sales Connection quotes for an Opportunity.
     * @param opportunityId Opportunity Id.
     * @return Open HC Sales Quote records plus Trial, Sample, and Goodwill quotes.
     */
    public static List<Quote> selectOpenSalesConnectionQuotesByOpportunityId(Id opportunityId) {
        if (opportunityId == null) {
            return new List<Quote>();
        }

        Id salesConnectionRecordTypeId = resolveHcSalesRecordTypeId();
        Set<String> includedQuoteTypes = salesConnectionSpecialQuoteTypes();

        if (salesConnectionRecordTypeId == null) {
            return [
                SELECT Id,
                    Name,
                    CurrencyIsoCode,
                    QuoteNumber,
                    QuoteNumber__c,
                    Status,
                    Forecast_Eligible__c,
                    Approval_Status__c,
                    QuoteType__c
                FROM Quote
                WHERE OpportunityId = :opportunityId
                  AND QuoteType__c IN :includedQuoteTypes
                  AND Status != :CLOSED_STATUS_VALUE
                WITH SYSTEM_MODE
                ORDER BY LastModifiedDate DESC, CreatedDate DESC
            ];
        }

        return [
            SELECT Id,
                Name,
                CurrencyIsoCode,
                QuoteNumber,
                QuoteNumber__c,
                Status,
                Forecast_Eligible__c,
                Approval_Status__c,
                QuoteType__c
            FROM Quote
            WHERE OpportunityId = :opportunityId
              AND Status != :CLOSED_STATUS_VALUE
              AND (
                    RecordTypeId = :salesConnectionRecordTypeId
                    OR QuoteType__c IN :includedQuoteTypes
                )
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC, CreatedDate DESC
        ];
    }

    /**
     * @description Returns counts of open Sales Connection quotes by Opportunity.
     * @param opportunityIds Opportunity Id set.
     * @return Open quote counts keyed by Opportunity Id.
     */
    public static Map<Id, Integer> countOpenSalesConnectionQuotesByOpportunityIds(Set<Id> opportunityIds) {
        Map<Id, Integer> quoteCountsByOpportunityId = new Map<Id, Integer>();

        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return quoteCountsByOpportunityId;
        }

        Id salesConnectionRecordTypeId = resolveHcSalesRecordTypeId();
        Set<String> includedQuoteTypes = salesConnectionSpecialQuoteTypes();

        if (salesConnectionRecordTypeId == null) {
            for (AggregateResult aggregateResult : [
                SELECT OpportunityId opportunityId, COUNT(Id) quoteCount
                FROM Quote
                WHERE OpportunityId IN :opportunityIds
                  AND QuoteType__c IN :includedQuoteTypes
                  AND Status != :CLOSED_STATUS_VALUE
                WITH SYSTEM_MODE
                GROUP BY OpportunityId
            ]) {
                quoteCountsByOpportunityId.put(
                    (Id) aggregateResult.get('opportunityId'),
                    (Integer) aggregateResult.get('quoteCount')
                );
            }

            return quoteCountsByOpportunityId;
        }

        for (AggregateResult aggregateResult : [
            SELECT OpportunityId opportunityId, COUNT(Id) quoteCount
            FROM Quote
            WHERE OpportunityId IN :opportunityIds
              AND Status != :CLOSED_STATUS_VALUE
              AND (
                    RecordTypeId = :salesConnectionRecordTypeId
                    OR QuoteType__c IN :includedQuoteTypes
                )
            WITH SYSTEM_MODE
            GROUP BY OpportunityId
        ]) {
            quoteCountsByOpportunityId.put(
                (Id) aggregateResult.get('opportunityId'),
                (Integer) aggregateResult.get('quoteCount')
            );
        }

        return quoteCountsByOpportunityId;
    }

    private static Set<String> forecastPropagateIncludedQuoteTypes() {
        return salesConnectionSpecialQuoteTypes();
    }

    private static Set<String> salesConnectionSpecialQuoteTypes() {
        return new Set<String>{
            GenerateQuoteService.QUOTE_TYPE_TRIAL,
            GenerateQuoteService.QUOTE_TYPE_SAMPLE,
            GenerateQuoteService.QUOTE_TYPE_GOODWILL
        };
    }

    /**
     * @description GW-5102 - Quote header used when processing Repair Center quote email replies.
     * @param quoteId Quote Id
     * @return Matching Quote, or null
     */
    public static Quote selectForQuoteEmailReplyById(Id quoteId) {
        if (quoteId == null) {
            return null;
        }

        List<Quote> quotes = [
            SELECT
                Id,
                Name,
                CurrencyIsoCode,
                QuoteNumber,
                Status,
                Pricebook2Id,
                WorkOrder__c
            FROM Quote
            WHERE Id = :quoteId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return quotes.isEmpty() ? null : quotes[0];
    }

    /**
     * @description GW-5333 - Loads a Quote header for Approve/Reject Quote.
     * @param quoteId Quote Id
     * @return Matching Quote, or null
     */
    public static Quote selectForApproveRejectById(Id quoteId) {
        if (quoteId == null) {
            return null;
        }

        List<Quote> quotes = [
            SELECT
                Id,
                Status,
                Version__c,
                Pricebook2Id,
                CurrencyIsoCode,
                WorkOrder__c
            FROM Quote
            WHERE Id = :quoteId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return quotes.isEmpty() ? null : quotes[0];
    }
}