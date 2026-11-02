/**
 * @author PWC Developer
 * @date 2026/10/30
 *
 * @group Lost Business Products
 *
 * @description
 * GC-3574 - LWC controller for the Lost Business product selection screen. Exposed to
 * Opportunity - Create - LostBusinessDetailScreen. It loads products from the originating
 * opportunity, searches the active catalogue, and creates Opportunity Products on the
 * Lost Business opportunity. Querying and DML are delegated to LostBusinessProductService.
 */
public with sharing class LostBusinessProductController {

    /**
     * @description
     * GC-3574 - Logger constants used in the class.
     */
    public static final String SCENARIO = 'Lost Business Products';
    public static final String LOGGER_TAG = 'LostBusinessProduct';

    /**
     * @description
     * GC-3574 - One originating Opportunity Product returned to the selection screen.
     */
    public class OriginatingProductRow {
        @AuraEnabled public Id sourceLineItemId;
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productSku;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public String consumptionFrequency;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Id pricebookEntryId;
        @AuraEnabled public Boolean copyable;
        @AuraEnabled public String unavailableReason;
    }

    /**
     * @description
     * GC-3574 - Active product returned to the catalogue search. The LWC paginates these rows client side.
     */
    public class ProductWrapper {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productCode;
        @AuraEnabled public Decimal unitPrice;
    }

    /**
     * @description
     * GC-3574 - One selected product sent by the LWC as JSON. Copy rows set sourceLineItemId.
     * Catalogue rows set productId. Passing the list as a parameter left every field null after
     * Aura deserialisation, so the LWC sends a JSON string.
     */
    public class ProductInput {
        @AuraEnabled public String sourceLineItemId;
        @AuraEnabled public String productId;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public String consumptionFrequency;
        @AuraEnabled public String status;
        @AuraEnabled public String confidenceLevel;
        @AuraEnabled public Date expectedShipDate;
        @AuraEnabled public String contractValue;
        @AuraEnabled public String comments;
    }

    /**
     * @description
     * GC-3574 - Returns Opportunity Products for the originating opportunity.
     *
     * @param originatingOpportunityId Originating opportunity Id from the flow.
     * @return Products on that opportunity. Empty when there are none to copy.
     *
     * @example
     * LostBusinessProductController.getOriginatingProducts(originatingOpportunityId);
     */
    @AuraEnabled
    public static List<OriginatingProductRow> getOriginatingProducts(String originatingOpportunityId) {
        try {
            return LostBusinessProductService.getOriginatingProducts(originatingOpportunityId);
        } catch (Exception exceptionValue) {
            throw buildHandledException(
                'Unable to load products from the originating opportunity.',
                exceptionValue
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description
     * GC-3574 - One Consumption Frequency value for the product selection dropdown.
     */
    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    /**
     * @description
     * GC-3574 - Active Consumption Frequency values. Loaded in Apex so the catalogue screen
     * still has options when the originating opportunity has no products to copy.
     *
     * @return Active picklist options.
     *
     * @example
     * LostBusinessProductController.getConsumptionFrequencyOptions();
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getConsumptionFrequencyOptions() {
        List<PicklistOption> optionList = new List<PicklistOption>();

        for (Schema.PicklistEntry picklistEntry : OpportunityLineItem.ConsumptionFrequency__c.getDescribe().getPicklistValues()) {
            if (!picklistEntry.isActive()) {
                continue;
            }

            PicklistOption option = new PicklistOption();
            option.label = picklistEntry.getLabel();
            option.value = picklistEntry.getValue();
            optionList.add(option);
        }

        return optionList;
    }

    /**
     * @description
     * GC-3574 - Searches the active product catalogue by product name or product code.
     *
     * @param searchKey User-entered product name or product code fragment.
     * @param lostBusinessOpportunityId Lost Business opportunity, used to show Unit Price when the price book has one.
     * @return Matching active products.
     *
     * @example
     * LostBusinessProductController.searchProducts(searchKey, lostBusinessOpportunityId);
     */
    @AuraEnabled
    public static List<ProductWrapper> searchProducts(String searchKey, String lostBusinessOpportunityId) {
        try {
            return LostBusinessProductService.searchProducts(searchKey, lostBusinessOpportunityId);
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to search products.', exceptionValue);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description
     * GC-3574 - Creates Opportunity Products on the Lost Business opportunity for the selected rows.
     *
     * @param lostBusinessOpportunityId Lost Business opportunity created earlier in the flow.
     * @param originatingOpportunityId Originating opportunity. Required when copying its products.
     * @param productInputsJson Selected products, JSON serialised by the LWC.
     * @return Number of Opportunity Products created.
     *
     * @example
     * LostBusinessProductController.createLostBusinessProducts(lostBusinessOpportunityId, originatingOpportunityId, productInputsJson);
     */
    @AuraEnabled
    public static Integer createLostBusinessProducts(
        String lostBusinessOpportunityId,
        String originatingOpportunityId,
        String productInputsJson
    ) {
        try {
            return LostBusinessProductService.createProducts(
                lostBusinessOpportunityId,
                originatingOpportunityId,
                productInputsJson
            );
        } catch (Exception exceptionValue) {
            throw buildHandledException(
                'Unable to add products to the Lost Business Opportunity.',
                exceptionValue
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description
     * GC-3574 - Surfaces validation messages to the LWC and logs unexpected failures.
     *
     * @param message Fallback error message.
     * @param exceptionValue Exception caught by the calling method.
     * @return AuraHandledException to throw to the LWC.
     *
     * @example
     * throw buildHandledException(message, exceptionValue);
     */
    private static AuraHandledException buildHandledException(String message, Exception exceptionValue) {
        Logger.setScenario(SCENARIO);
        Logger.error(message + ' ' + exceptionValue.getMessage()).addTag(LOGGER_TAG);

        if (exceptionValue instanceof AuraHandledException) {
            return (AuraHandledException) exceptionValue;
        }

        if (exceptionValue instanceof LostBusinessProductException) {
            AuraHandledException validationException = new AuraHandledException(exceptionValue.getMessage());
            validationException.setMessage(exceptionValue.getMessage());
            return validationException;
        }

        return new AuraHandledException(message);
    }
}