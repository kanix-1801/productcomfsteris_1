/**
* @author PWC Developer
* @date 2026/06/10
*
* @group Generate Quote
*
* @description
* GC-2642 Controller class for Generate and Refresh Quote Button on Opportunity.
*/
public with sharing class GenerateQuoteController {
    public static final String SCENARIO = 'Generate Quote';
    public static final String LOGGER_TAG = 'GenerateQuote';

    /**
     * @description Quote line detail used in the product subgroup accordion.
     */
    public class QuoteLineDetailWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String quoteLineId;
        @AuraEnabled public String productCode;
        @AuraEnabled public String productName;
        @AuraEnabled public String uom;
        @AuraEnabled public String productFAMCode;
        @AuraEnabled public String productSubgroupDetailName;
        @AuraEnabled public String tasSalesCategory;
        @AuraEnabled public String salesCategoryDescription;
        @AuraEnabled public String territoryId;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal lineTotal;
    }

    /**
     * @description Product subgroup summary row for the Generate Quote LWC.
     */
    public class ProductSubgroupSummaryWrapper {
        @AuraEnabled public String productSubgroupDetailName;
        @AuraEnabled public Decimal totalUnitPrice;
        @AuraEnabled public List<QuoteLineDetailWrapper> quoteLines;
    }

    /**
     * @description Quote returned to the Generate Quote LWC.
     */
    public class QuoteWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String quoteNumber;
        @AuraEnabled public String salesConnectionViewQuoteNumber;
        @AuraEnabled public String salesConnectionQuoteId;
        @AuraEnabled public String quoteName;
        @AuraEnabled public Date expirationDate;
        @AuraEnabled public String salesConnectionUrl;
        @AuraEnabled public String description;
        @AuraEnabled public String status;
        @AuraEnabled public String approvalStatus;
        @AuraEnabled public Decimal quoteTotalWithoutFreight;
        @AuraEnabled public String currencyIsoCode;
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public Boolean isForecastIneligible;
        @AuraEnabled public String quoteType;
        @AuraEnabled public String quoteForecastConfidence;
        @AuraEnabled public String opportunityForecastConfidence;
        @AuraEnabled public List<ProductSubgroupSummaryWrapper> productSubgroupSummary;
        @AuraEnabled public List<ProductSubgroupSummaryWrapper> salesCategorySummary;
    }

    /**
     * @description Response returned after quote creation.
     */
    public class CreateQuoteResponse {
        @AuraEnabled public Id quoteId;
        @AuraEnabled public String quoteNumber;
        @AuraEnabled public String quoteName;
        @AuraEnabled public String salesConnectionUrl;
    }

    /**
     * @description Retrieves quotes for an Opportunity with optional filters.
     * @param opportunityId Opportunity Id.
     * @param quoteTypeFilter Optional QuoteType__c value to filter results.
     * @param excludeForecastIneligible When true, omit forecast-ineligible quotes.
     * @param trialIdFilter Optional Trial__c Id to limit results to one Trial record.
     * @param sampleIdFilter Optional Sample__c Id to limit results to one Sample record.
     * @return Quote DTOs for the LWC.
     */
    public static List<QuoteWrapper> getQuotes(
        Id opportunityId,
        String quoteTypeFilter,
        Boolean excludeForecastIneligible,
        Id trialIdFilter,
        Id sampleIdFilter
    ) {
        return getQuotes(
            opportunityId,
            quoteTypeFilter,
            excludeForecastIneligible,
            trialIdFilter,
            sampleIdFilter,
            false
        );
    }

    /**
     * @description Retrieves quotes for an Opportunity. Portal calls omit prices until the quote is Approved.
     * @param opportunityId Opportunity Id.
     * @param quoteTypeFilter Optional QuoteType__c value to filter results.
     * @param excludeForecastIneligible When true, omit forecast-ineligible quotes.
     * @param trialIdFilter Optional Trial__c Id to limit results to one Trial record.
     * @param sampleIdFilter Optional Sample__c Id to limit results to one Sample record.
     * @param forDealerPortal When true, pricing is returned only for Approved quotes.
     * @return Quote DTOs for the LWC.
     */
    @AuraEnabled
    public static List<QuoteWrapper> getQuotes(
        Id opportunityId,
        String quoteTypeFilter,
        Boolean excludeForecastIneligible,
        Id trialIdFilter,
        Id sampleIdFilter,
        Boolean forDealerPortal
    ) {
        try {
            return GenerateQuoteService.getQuotes(
                opportunityId,
                quoteTypeFilter,
                excludeForecastIneligible == true,
                trialIdFilter,
                sampleIdFilter,
                forDealerPortal == true
            );
        } catch (Exception exceptionValue) {
            handleException('Unable to retrieve quotes.', exceptionValue);
            return new List<QuoteWrapper>();
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Creates a Quote for an Opportunity.
     * @param opportunityId Opportunity Id.
     * @param quoteType Quote Type picklist value to assign on create.
     * @param trialId Optional Trial record Id for Trial Quote creation.
     * @param sampleId Optional Sample record Id for Sample Quote creation.
     * @return Create quote response DTO.
     */
    @AuraEnabled
    public static CreateQuoteResponse createQuote(
        Id opportunityId,
        String quoteType,
        Id trialId,
        Id sampleId
    ) {
        try {
            return GenerateQuoteService.createQuote(
                opportunityId,
                String.isBlank(quoteType) ? GenerateQuoteService.QUOTE_TYPE_NORMAL : quoteType,
                trialId,
                sampleId
            );
        } catch (Exception exceptionValue) {
            handleException('Unable to create quote.', exceptionValue);
            return null;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Creates a shell Quote and opens Sales Connection for copy quote.
     * @param opportunityId Opportunity Id.
     * @return Create quote response DTO with encrypted Sales Connection URL.
     */
    @AuraEnabled
    public static CreateQuoteResponse copyQuote(Id opportunityId) {
        try {
            return GenerateQuoteService.createShellQuoteForSalesConnectionRequest(
                opportunityId,
                SalesConnectionUrlService.SF_REQUEST_COPY
            );
        } catch (Exception exceptionValue) {
            handleException('Unable to copy quote.', exceptionValue);
            return null;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Creates a shell Quote and opens Sales Connection for merge quote.
     * @param opportunityId Opportunity Id.
     * @return Create quote response DTO with encrypted Sales Connection URL.
     */
    @AuraEnabled
    public static CreateQuoteResponse mergeQuote(Id opportunityId) {
        try {
            return GenerateQuoteService.createShellQuoteForSalesConnectionRequest(
                opportunityId,
                SalesConnectionUrlService.SF_REQUEST_MERGE
            );
        } catch (Exception exceptionValue) {
            handleException('Unable to merge quote.', exceptionValue);
            return null;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Refreshes quotes for an Opportunity from Sales Connection.
     * @param opportunityId Opportunity Id.
     * @return Quote DTOs for the LWC.
     */
    @AuraEnabled
    public static List<QuoteWrapper> refreshQuotes(Id opportunityId) {
        try {
            return GenerateQuoteService.refreshQuotes(opportunityId);
        } catch (Exception exceptionValue) {
            handleException('Unable to refresh quotes.', exceptionValue);
            return new List<QuoteWrapper>();
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Validates that the current user has edit access to the Opportunity (UserRecordAccess).
     * @param opportunityId Opportunity Id.
     */
    @AuraEnabled
    public static void validateQuoteAccess(Id opportunityId) {
        try {
            GenerateQuoteService.validateQuoteAccess(opportunityId);
        } catch (Exception exceptionValue) {
            handleException('Unable to validate quote access.', exceptionValue);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Builds a Sales Connection view-quote URL from the stored Quote Id.
     * @param salesConnectionQuoteId SalesConnectionQuoteID__c value for the view URL.
     * @return Sales Connection view-quote URL.
     */
    /**
     * @description Syncs Quote Forecast Confidence to Sales Connection (GC-3457); updates SF only after Boomi success.
     * @param opportunityId Opportunity Id.
     * @param quoteId Quote Id.
     * @param quoteForecastConfidence Selected Quote Forecast Confidence value.
     * @param syncFromOpportunity When true, copies the Opportunity Forecast Confidence first.
     * @return Updated quote values for the UI.
     */
    @AuraEnabled
    public static QuoteWrapper syncQuoteForecastConfidence(
        Id opportunityId,
        Id quoteId,
        String quoteForecastConfidence,
        Boolean syncFromOpportunity
    ) {
        try {
            return GenerateQuoteService.syncQuoteForecastConfidence(
                opportunityId,
                quoteId,
                quoteForecastConfidence,
                syncFromOpportunity == true
            );
        } catch (Exception exceptionValue) {
            handleException('Unable to sync quote forecast confidence.', exceptionValue);
            return null;
        } finally {
            Logger.saveLog();
        }
    }

    @AuraEnabled
    public static String getSalesConnectionQuoteUrl(String salesConnectionQuoteId) {
        try {
            if (String.isBlank(salesConnectionQuoteId)) {
                throw new AuraHandledException('Sales Connection Quote Id is required.');
            }

            return SalesConnectionUrlService.buildExistingQuoteUrl(
                GenerateQuoteService.normalizeSalesConnectionQuoteIdForStorage(salesConnectionQuoteId)
            );
        } catch (Exception exceptionValue) {
            handleException('Unable to build Sales Connection URL.', exceptionValue);
            return null;
        } finally {
            Logger.saveLog();
        }
    }

    private static void handleException(String message, Exception exceptionValue) {
        Logger.setScenario(SCENARIO);
        Logger.error(message + ' ' + exceptionValue.getMessage()).addTag(LOGGER_TAG);

        if (exceptionValue instanceof AuraHandledException) {
            throw exceptionValue;
        }

        if (exceptionValue instanceof GenerateQuoteException) {
            throw new AuraHandledException(exceptionValue.getMessage());
        }

        throw new AuraHandledException(message);
    }
}