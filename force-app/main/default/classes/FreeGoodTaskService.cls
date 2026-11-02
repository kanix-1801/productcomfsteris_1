/**
* @author PWC Developer
* @date 2026/08/17
*
* @group Free Good Task
*
* @description
* GC-3230 - Service layer for the Free Goods product selection screen. Searches the active product
* catalogue and creates the Free Goods Task Product records for the Task created earlier in the
* Task - Create - FreeGoodsDetailScreen flow. The records are linked to the Task through the
* TaskId__c external id field and to the Account through the Account__c lookup.
*/
public with sharing class FreeGoodTaskService {

    /**
* @description
* GC-3230 - Constants used in the class.
*/
    public static final String SCENARIO = 'Free Good Task';
    public static final String LOGGER_TAG = 'FreeGoodTask';

    @TestVisible
    private static Boolean throwTestException = false;

    /**
* @description
* GC-3230 - Helper method for getTaskProducts.
* Returns the Free Goods Task Product rows linked to the Task for display on the Task record page.
*
* @param taskId 18 digit Id of the standard Task.
* @return Product rows with Product, Quantity, Account and audit fields.
*
* @example
* FreeGoodTaskService.getTaskProducts(taskId);
*/
    public static List<FreeGoodTaskController.TaskProductRowWrapper> getTaskProducts(String taskId) {
        try {
            if (Test.isRunningTest() && throwTestException) {
                throw new QueryException('Forced test exception');
            }

            List<FreeGoodTaskController.TaskProductRowWrapper> productRowList =
                new List<FreeGoodTaskController.TaskProductRowWrapper>();

            for (Free_Goods_Task_Product__c taskProduct : FreeGoodsTaskProductSelector.selectByTaskId(taskId)) {
                FreeGoodTaskController.TaskProductRowWrapper productRow =
                    new FreeGoodTaskController.TaskProductRowWrapper();
                productRow.productId = taskProduct.Product__c;
                productRow.productName = taskProduct.Product__r != null ? taskProduct.Product__r.Name : null;
                productRow.productCode = taskProduct.Product__r != null ? taskProduct.Product__r.ProductCode : null;
                productRow.lineDescription = taskProduct.LineDescription__c;
                productRow.quantity = taskProduct.Quantity__c;
                productRow.salesPrice = taskProduct.SalesPrice__c;
                productRow.consumptionFrequency = taskProduct.ConsumptionFrequency__c;
                productRow.status = taskProduct.Status__c;
                productRow.confidenceLevel = taskProduct.ConfidenceLevel__c;
                productRow.expectedShipDate = taskProduct.ExpectedShipDateConsumptionStart__c;
                productRow.contractValue = taskProduct.Contract__c;
                productRow.comments = taskProduct.Comments__c;
                productRow.accountId = taskProduct.Account__c;
                productRow.accountName = taskProduct.Account__r != null ? taskProduct.Account__r.Name : null;
                productRow.createdDate = taskProduct.CreatedDate;
                productRow.createdByName = taskProduct.CreatedBy != null ? taskProduct.CreatedBy.Name : null;
                productRowList.add(productRow);
            }

            return productRowList;
        } catch (Exception exceptionValue) {
            Logger.error('Error loading Free Goods Task Products', exceptionValue);
            throw new FreeGoodTaskException('Unable to load Free Goods Task Products.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
* @description
* GC-3230 - Helper method for searchProducts.
* Searches the active product catalogue by product name or product code. The full result set is
* returned so the LWC can paginate it client side.
*
* @param searchKey User-entered product name or product code fragment.
* @return Matching active products for selection.
*
* @example
* FreeGoodTaskService.searchProducts(searchKey);
*/
    public static List<FreeGoodTaskController.ProductWrapper> searchProducts(String searchKey) {
        try {
            if (Test.isRunningTest() && throwTestException) {
                throw new QueryException('Forced test exception');
            }

            List<FreeGoodTaskController.ProductWrapper> productWrapperList =
                new List<FreeGoodTaskController.ProductWrapper>();

            for (Product2 product : Product2Selector.selectActiveBySearchKey(searchKey)) {
                FreeGoodTaskController.ProductWrapper productWrapper =
                    new FreeGoodTaskController.ProductWrapper();
                productWrapper.productId = product.Id;
                productWrapper.productName = product.Name;
                productWrapper.productCode = product.ProductCode;
                productWrapper.productFamily = product.Family;
                productWrapper.productDescription = product.Description;
                productWrapperList.add(productWrapper);
            }

            return productWrapperList;
        } catch (Exception exceptionValue) {
            Logger.error('Error searching products for Free Good Task', exceptionValue);
            throw new FreeGoodTaskException('Unable to search products.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
* @description
* GC-3230 - Helper method for createTaskProducts.
* Validates the selection, then inserts one Free Goods Task Product per selected product for the
* Task created earlier in the flow. The insert is wrapped in a savepoint so a partial set of
* product rows is never left behind.
*
* @param taskId 18 digit Id of the standard Task created by the flow.
* @param accountId Account the free goods are being delivered to.
* @param opportunityId Originating Opportunity, blank when launched from an Account.
* @param productInputsJson Selected products and quantities, JSON serialised by the LWC.
* @return Number of Free Goods Task Product records created.
*
* @example
* FreeGoodTaskService.createTaskProducts(taskId, accountId, opportunityId, productInputsJson);
*/
    public static Integer createTaskProducts(
        String taskId,
        Id accountId,
        String opportunityId,
        String productInputsJson
    ) {
        Savepoint savePointValue = Database.setSavepoint();

        try {
            if (Test.isRunningTest() && throwTestException) {
                throw new DmlException('Forced test exception');
            }

            String taskId18 = validateTaskId(taskId);
            Map<Id, FreeGoodTaskController.TaskProductInput> validatedProductByIdMap =
                validateProducts(parseProductInputs(productInputsJson));

            List<Free_Goods_Task_Product__c> taskProductList = new List<Free_Goods_Task_Product__c>();

            for (Id productId : validatedProductByIdMap.keySet()) {
                FreeGoodTaskController.TaskProductInput productInput = validatedProductByIdMap.get(productId);

                taskProductList.add(new Free_Goods_Task_Product__c(
                    TaskId__c = taskId18,
                    Account__c = accountId,
                    Product__c = productId,
                    Quantity__c = productInput.quantity,
                    SalesPrice__c = productInput.salesPrice,
                    ConsumptionFrequency__c = blankToNull(productInput.consumptionFrequency),
                    Status__c = blankToNull(productInput.status),
                    ConfidenceLevel__c = blankToNull(productInput.confidenceLevel),
                    ExpectedShipDateConsumptionStart__c = productInput.expectedShipDate,
                    Contract__c = blankToNull(productInput.contractValue),
                    ProductDetails__c = productInput.productDetails,
                    Comments__c = blankToNull(productInput.comments),
                    LineDescription__c = blankToNull(productInput.lineDescription)
                ));
            }

            insert taskProductList;

            flagOpportunitySampleActivity(opportunityId);

            return taskProductList.size();
        } catch (FreeGoodTaskException validationException) {
            Database.rollback(savePointValue);
            // Records the raw payload the browser sent so a rejected save can be diagnosed from the log.
            Logger.error('Free Goods product payload rejected: ' + productInputsJson).addTag(LOGGER_TAG);
            throw validationException;
        } catch (Exception exceptionValue) {
            Database.rollback(savePointValue);
            Logger.error('Error creating Free Goods Task Products', exceptionValue);
            throw new FreeGoodTaskException('Unable to create the Free Goods Task Products.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
* @description
* GC-3230 / GC-3228 - Private helper method for createTaskProducts.
* Marks the originating Opportunity as having sample activity. Runs inside the same savepoint as the
* product insert so the flag and the product rows either both stick or both roll back. Does nothing
* when the flow was launched from an Account, where no Opportunity is in play.
*
* @param opportunityId Originating Opportunity, blank when launched from an Account.
*
* @example
* flagOpportunitySampleActivity(opportunityId);
*/
    private static void flagOpportunitySampleActivity(String opportunityId) {
        if (String.isBlank(opportunityId)) {
            return;
        }

        Id opportunityRecordId;

        try {
            opportunityRecordId = Id.valueOf(opportunityId);
        } catch (System.StringException invalidIdException) {
            throw new FreeGoodTaskException('The Opportunity Id provided is not valid.');
        }

        update new Opportunity(
            Id = opportunityRecordId,
            HasSampleActivity__c = true
        );
    }

    /**
* @description
* GC-3230 - Private helper method for createTaskProducts.
* Confirms a Task Id was supplied and normalises it to the 18 character form stored on TaskId__c.
*
* @param taskId Task Id supplied by the flow.
* @return 18 character Task Id.
*
* @example
* validateTaskId(taskId);
*/
    private static String validateTaskId(String taskId) {
        if (String.isBlank(taskId)) {
            throw new FreeGoodTaskException('A Task is required before products can be added.');
        }

        try {
            return String.valueOf(Id.valueOf(taskId));
        } catch (System.StringException invalidIdException) {
            throw new FreeGoodTaskException('The Task Id provided is not valid.');
        }
    }

    /**
* @description
* GC-3230 - Private helper method for createTaskProducts.
* Parses the selection sent by the LWC. The selection is passed as a JSON string and deserialised
* here because supplying it as a List<TaskProductInput> parameter left every field null.
*
* @param productInputsJson Selected products and quantities, JSON serialised by the LWC.
* @return Deserialised product selection.
*
* @example
* parseProductInputs(productInputsJson);
*/
    private static List<FreeGoodTaskController.TaskProductInput> parseProductInputs(String productInputsJson) {
        if (String.isBlank(productInputsJson)) {
            throw new FreeGoodTaskException('At least one product must be selected.');
        }

        try {
            return (List<FreeGoodTaskController.TaskProductInput>) JSON.deserialize(
                productInputsJson,
                List<FreeGoodTaskController.TaskProductInput>.class
            );
        } catch (Exception parseException) {
            throw new FreeGoodTaskException('The selected products could not be read.');
        }
    }

    /**
* @description
* GC-3230 - Private helper method for createTaskProducts.
* Confirms at least one active product was selected and that every product has a quantity above zero.
*
* @param productInputs Selected products and their quantities.
* @return Validated product inputs keyed by Product Id.
*
* @example
* validateProducts(productInputs);
*/
    private static Map<Id, FreeGoodTaskController.TaskProductInput> validateProducts(
        List<FreeGoodTaskController.TaskProductInput> productInputs
    ) {
        List<String> errorMessageList = new List<String>();
        Map<Id, FreeGoodTaskController.TaskProductInput> validatedProductByIdMap =
            new Map<Id, FreeGoodTaskController.TaskProductInput>();

        if (productInputs == null || productInputs.isEmpty()) {
            throw new FreeGoodTaskException('At least one product must be selected.');
        }

        for (FreeGoodTaskController.TaskProductInput productInput : productInputs) {
            if (productInput == null || String.isBlank(productInput.productId)) {
                errorMessageList.add('A selected product is missing its product reference.');
                continue;
            }

            if (productInput.quantity == null || productInput.quantity <= 0) {
                errorMessageList.add('Quantity must be greater than zero for every selected product.');
                continue;
            }

            try {
                validatedProductByIdMap.put(Id.valueOf(productInput.productId), productInput);
            } catch (System.StringException invalidIdException) {
                errorMessageList.add('A selected product reference is not a valid product.');
            }
        }

        if (!validatedProductByIdMap.isEmpty()) {
            Set<Id> activeProductIdSet = new Map<Id, Product2>(
                Product2Selector.selectActiveByIds(validatedProductByIdMap.keySet())
            ).keySet();

            for (Id productId : validatedProductByIdMap.keySet()) {
                if (!activeProductIdSet.contains(productId)) {
                    errorMessageList.add('One or more selected products are no longer active.');
                    break;
                }
            }
        }

        if (!errorMessageList.isEmpty()) {
            throw new FreeGoodTaskException(String.join(errorMessageList, '\n'));
        }

        return validatedProductByIdMap;
    }

    /**
* @description
* GC-3393 - Private helper method for createTaskProducts.
* Converts a blank optional string to null so picklist and text fields are not stored as empty.
*
* @param fieldValue Optional string from the LWC payload.
* @return Null when blank, otherwise the trimmed value.
*
* @example
* blankToNull(fieldValue);
*/
    private static String blankToNull(String fieldValue) {
        return String.isBlank(fieldValue) ? null : fieldValue.trim();
    }
}