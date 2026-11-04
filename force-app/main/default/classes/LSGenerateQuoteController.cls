/**
* @author Sarthak Pani
* @date 2026/10/28
*
* @group Generate Quote
*
* @description
* GCL-66 Controller class for Generate and Refresh Quote Button on Opportunity for LS.
*/
public with sharing class LSGenerateQuoteController {
    public static final String SCENARIO = 'LS Generate Quote';
    public static final String LOGGER_TAG = 'LSGenerateQuote';

    /**
     * @description Quote line detail used in the product subgroup accordion.
     */
    public class QuoteLineDetailWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String quoteLineId;
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
     * @description Validates that the current user has edit access to the Opportunity (UserRecordAccess).
     * @param opportunityId Opportunity Id.
     */
    @AuraEnabled
    public static void validateQuoteAccess(Id opportunityId) {
        try {
            LSGenerateQuoteService.validateQuoteAccess(opportunityId);
        } catch (Exception exceptionValue) {
            handleException(exceptionValue.getMessage(), exceptionValue);   //GCL-66
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
    public static GenerateQuoteController.CreateQuoteResponse createQuote(
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
    public static GenerateQuoteController.CreateQuoteResponse copyQuote(Id opportunityId) {
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
    public static GenerateQuoteController.CreateQuoteResponse mergeQuote(Id opportunityId) {
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
     * @description Validates that the current user has edit access to the Opportunity (UserRecordAccess).
     * @param opportunityId Opportunity Id.
     */
    @AuraEnabled
    public static Boolean isOpportunityOnHold(Id opportunityId) {
        Opportunity opportunityRecord = OpportunitySelector.selectById(opportunityId);

        if (opportunityRecord == null) {
            return false;
        }

        return opportunityRecord.OnHold__c;
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