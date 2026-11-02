/**
 * @description GC-3431 LWC controller for separate EPP capital-equipment and consumable product selection.
 */
public with sharing class EPPProductController {

    public class ProductWrapper {
        @AuraEnabled public Id pricebookEntryId;
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productCode;
        @AuraEnabled public String productFamily;
        @AuraEnabled public String businessUnit;
        @AuraEnabled public String productDescription;
        @AuraEnabled public Decimal listPrice;
    }

    public class ProductInput {
        @AuraEnabled public String pricebookEntryId;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Date placementStartDate;
        @AuraEnabled public Date placementEndDate;
        @AuraEnabled public String consumptionFrequency;
        @AuraEnabled public Boolean elevatedEPPPricingApplicable;
        @AuraEnabled public Decimal eppPrice;
        @AuraEnabled public Date commitmentStartDate;
        @AuraEnabled public Date commitmentEndDate;
    }

    public class OpportunityProductWrapper {
        @AuraEnabled public Id opportunityLineItemId;
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productCode;
        @AuraEnabled public String productFamily;
        @AuraEnabled public String businessUnit;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal totalPrice;
        @AuraEnabled public Date placementStartDate;
        @AuraEnabled public Date placementEndDate;
        @AuraEnabled public String consumptionFrequency;
        @AuraEnabled public Boolean elevatedEPPPricingApplicable;
        @AuraEnabled public Decimal eppPrice;
        @AuraEnabled public Date commitmentStartDate;
        @AuraEnabled public Date commitmentEndDate;
        @AuraEnabled public Decimal annualCommittedRevenue;
        @AuraEnabled public Decimal contractTermRevenue;
    }

    @AuraEnabled
    public static List<ProductWrapper> searchProducts(
        Id opportunityId,
        Boolean isConsumable,
        String searchKey
    ) {
        try {
            return EPPProductService.searchProducts(opportunityId, isConsumable, searchKey);
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to search EPP products.', exceptionValue);
        }
    }

    @AuraEnabled
    public static List<OpportunityProductWrapper> getOpportunityProducts(
        Id opportunityId,
        Boolean isConsumable
    ) {
        try {
            return EPPProductService.getOpportunityProducts(opportunityId, isConsumable);
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to load EPP Opportunity Products.', exceptionValue);
        }
    }

    @AuraEnabled
    public static Integer createOpportunityProducts(
        Id opportunityId,
        Boolean isConsumable,
        String productInputsJson
    ) {
        try {
            return EPPProductService.createOpportunityProducts(
                opportunityId,
                isConsumable,
                productInputsJson
            );
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to add EPP Opportunity Products.', exceptionValue);
        }
    }

    private static AuraHandledException buildHandledException(String fallbackMessage, Exception exceptionValue) {
        String message = exceptionValue instanceof EPPProductException
            ? exceptionValue.getMessage()
            : fallbackMessage;
        AuraHandledException handledException = new AuraHandledException(message);
        handledException.setMessage(message);
        return handledException;
    }
}