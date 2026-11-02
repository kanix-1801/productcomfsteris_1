/**
 * @description Apex controller for the Free Goods Task Products Flow screen LWC (GC-3230).
 *              Loads product labels and inserts Free_Goods_Task_Product__c rows for a Free Good Task.
 */
public with sharing class FreeGoodsTaskProductController {
    /**
     * @description Product + quantity payload from the LWC.
     */
    public class ProductQuantityInput {
        @AuraEnabled
        public Id productId { get; set; }
        @AuraEnabled
        public Decimal quantity { get; set; }
    }

    /**
     * @description Lightweight product option for selected-row display.
     */
    public class ProductOption {
        @AuraEnabled
        public Id id { get; set; }
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public String productCode { get; set; }
    }

    /**
     * @description Resolves product Name / ProductCode for selected Product2 Ids.
     * @param productIds Product2 Ids selected in the LWC
     * @return Matching active products
     */
    @AuraEnabled(cacheable=true)
    public static List<ProductOption> getProductsByIds(List<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return new List<ProductOption>();
        }

        try {
            List<ProductOption> options = new List<ProductOption>();
            for (Product2 productRecord : [
                SELECT Id, Name, ProductCode
                FROM Product2
                WHERE Id IN :productIds
                WITH USER_MODE
            ]) {
                ProductOption option = new ProductOption();
                option.id = productRecord.Id;
                option.name = productRecord.Name;
                option.productCode = productRecord.ProductCode;
                options.add(option);
            }
            return options;
        } catch (Exception e) {
            throw toAuraHandledException('Unable to load products: ' + e.getMessage());
        }
    }

    /**
     * @description Creates one Free_Goods_Task_Product__c per product/quantity pair.
     *              Stores the Flow taskId and accountId in their text fields.
     * @param taskId Task Id text value from the first Flow screen
     * @param accountId Account Id text value from the Flow (optional)
     * @param products Selected products with quantities
     * @return Ids of inserted Free_Goods_Task_Product__c records
     */
    @AuraEnabled
    public static List<Id> saveTaskProducts(
        String taskId,
        String accountId,
        List<ProductQuantityInput> products
    ) {
        if (String.isBlank(taskId)) {
            throw toAuraHandledException('Task Id is required.');
        }
        if (products == null || products.isEmpty()) {
            throw toAuraHandledException('Select at least one product.');
        }

        try {
            String taskIdValue = taskId.trim();
            String accountIdValue = String.isBlank(accountId) ? null : accountId.trim();

            Set<Id> productIds = new Set<Id>();
            for (ProductQuantityInput item : products) {
                if (item == null || item.productId == null) {
                    throw toAuraHandledException('Each row must include a product.');
                }
                if (item.quantity == null || item.quantity <= 0) {
                    throw toAuraHandledException('Quantity must be greater than zero for every product.');
                }
                productIds.add(item.productId);
            }

            Map<Id, Product2> productsById = new Map<Id, Product2>(
                [
                    SELECT Id, Name, ProductCode
                    FROM Product2
                    WHERE Id IN :productIds
                    WITH USER_MODE
                ]
            );

            if (productsById.size() != productIds.size()) {
                throw toAuraHandledException('One or more selected products could not be found.');
            }

            List<Free_Goods_Task_Product__c> rowsToInsert = new List<Free_Goods_Task_Product__c>();
            for (ProductQuantityInput item : products) {
                Product2 productRecord = productsById.get(item.productId);
                Free_Goods_Task_Product__c row = new Free_Goods_Task_Product__c();
                row.Name = buildRowName(productRecord, item.quantity);
                row.taskId__c = taskIdValue;
                row.Account__c = accountIdValue;
                row.Product__c = item.productId;
                row.Quantity__c = item.quantity;
                rowsToInsert.add(row);
            }

            Database.insert(rowsToInsert, AccessLevel.USER_MODE);

            List<Id> insertedIds = new List<Id>();
            for (Free_Goods_Task_Product__c row : rowsToInsert) {
                insertedIds.add(row.Id);
            }
            return insertedIds;
        } catch (AuraHandledException e) {
            throw e;
        } catch (DmlException e) {
            throw toAuraHandledException(
                'Unable to save free goods products: ' + e.getDmlMessage(0)
            );
        } catch (Exception e) {
            throw toAuraHandledException('Unable to save free goods products: ' + e.getMessage());
        }
    }

    private static String buildRowName(Product2 productRecord, Decimal quantity) {
        String label = String.isNotBlank(productRecord.ProductCode)
            ? productRecord.ProductCode
            : productRecord.Name;
        String nameValue = label + ' x ' + String.valueOf(quantity.intValue());
        return nameValue.length() > 80 ? nameValue.substring(0, 80) : nameValue;
    }

    private static AuraHandledException toAuraHandledException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}