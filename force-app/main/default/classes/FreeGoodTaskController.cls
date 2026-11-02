/**
* @author PWC Developer
* @date 2026/08/17
*
* @group Free Good Task
*
* @description
* GC-3230 - LWC controller for the Free Goods product selection screen. Exposed to the
* Task - Create - FreeGoodsDetailScreen flow, it searches the active product catalogue and
* creates the Free Goods Task Product records for the Task created earlier in the flow.
* All querying, validation, and DML is delegated to FreeGoodTaskService.
*/
public with sharing class FreeGoodTaskController {

    /**
* @description
* GC-3230 - Logger constants used in the class.
*/
    public static final String SCENARIO = 'Free Good Task';
    public static final String LOGGER_TAG = 'FreeGoodTask';

    /**
* @description
* GC-3230 - Active product returned to the product search datatable. The LWC paginates these rows client side.
*/
    public class ProductWrapper {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productCode;
        @AuraEnabled public String productFamily;
        @AuraEnabled public String productDescription;
    }

    /**
* @description
* GC-3230 / GC-3393 - One selected product and the line fields captured on the Add Products screen.
* The LWC sends these as a JSON string that the service parses, because passing them as a
* List<TaskProductInput> parameter left every field null after Aura deserialisation.
*/
    public class TaskProductInput {
        @AuraEnabled public String productId;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal salesPrice;
        @AuraEnabled public String consumptionFrequency;
        @AuraEnabled public String status;
        @AuraEnabled public String confidenceLevel;
        @AuraEnabled public Date expectedShipDate;
        @AuraEnabled public String contractValue;
        @AuraEnabled public String productDetails;
        @AuraEnabled public String comments;
        @AuraEnabled public String lineDescription;
    }

    /**
* @description
* GC-3230 - One Free Goods Task Product row returned to the Task record page tab.
*/
    public class TaskProductRowWrapper {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productCode;
        @AuraEnabled public String lineDescription;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal salesPrice;
        @AuraEnabled public String consumptionFrequency;
        @AuraEnabled public String status;
        @AuraEnabled public String confidenceLevel;
        @AuraEnabled public Date expectedShipDate;
        @AuraEnabled public String contractValue;
        @AuraEnabled public String comments;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String createdByName;
    }

    /**
* @description
* GC-3230 - Searches the active Salesforce product catalogue by product name or product code.
*
* @param searchKey User-entered product name or product code fragment.
* @return Matching active products for selection.
*
* @example
* FreeGoodTaskController.searchProducts(searchKey);
*/
    @AuraEnabled
    public static List<ProductWrapper> searchProducts(String searchKey) {
        try {
            return FreeGoodTaskService.searchProducts(searchKey);
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to search products.', exceptionValue);
        } finally {
            Logger.saveLog();
        }
    }

    /**
* @description
* GC-3230 - Creates one Free Goods Task Product record per selected product for the Task created
* earlier in the flow. The standard Task Id is stored on the TaskId__c external id field and the
* Account is stored on the Account__c lookup.
*
* @param taskId 18 digit Id of the standard Task created by the flow.
* @param accountId Account the free goods are being delivered to.
* @param opportunityId Originating Opportunity, blank when launched from an Account.
* @param productInputsJson Selected products, quantities and optional line fields, JSON serialised by the LWC.
* @return Number of Free Goods Task Product records created.
*
* @example
* FreeGoodTaskController.createTaskProducts(taskId, accountId, opportunityId, productInputsJson);
*/
    @AuraEnabled
    public static Integer createTaskProducts(
        String taskId,
        Id accountId,
        String opportunityId,
        String productInputsJson
    ) {
        try {
            return FreeGoodTaskService.createTaskProducts(taskId, accountId, opportunityId, productInputsJson);
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to create the Free Goods Task Products.', exceptionValue);
        } finally {
            Logger.saveLog();
        }
    }

    /**
* @description
* GC-3230 - Returns the Free Goods Task Product rows linked to the Task for the record page tab.
*
* @param taskId 18 digit Id of the standard Task.
* @return Product rows with Product, Quantity, Account and audit fields.
*
* @example
* FreeGoodTaskController.getTaskProducts(taskId);
*/
    @AuraEnabled(cacheable=true)
    public static List<TaskProductRowWrapper> getTaskProducts(String taskId) {
        try {
            return FreeGoodTaskService.getTaskProducts(taskId);
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to load Free Goods Task Products.', exceptionValue);
        } finally {
            Logger.saveLog();
        }
    }

    /**
* @description
* GC-3230 - Helper exception handling method. Validation messages raised by the service are surfaced to the
* user unchanged so the LWC can display the specific field that failed.
*
* @param message Fallback error message.
* @param exceptionValue Exception caught by the calling method.
* @return AuraHandledException exception to throw to the LWC caller.
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

        if (exceptionValue instanceof FreeGoodTaskException) {
            AuraHandledException validationException = new AuraHandledException(exceptionValue.getMessage());
            validationException.setMessage(exceptionValue.getMessage());
            return validationException;
        }

        return new AuraHandledException(message);
    }
}