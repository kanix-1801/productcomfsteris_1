/**
 * GC-3606 Keeps the Product, the family code, and the class code on a Lead Product in step.
 * When a Product is chosen, its family and class codes are copied onto the row.
 * When HubSpot sends only the codes, the Product is found from them. If the codes match more
 * than one Product, the submitted product name picks one. If it is still not one Product, the
 * Product stays empty and the codes are still sent to TAS.
 */
public with sharing class LeadProductTriggerHandler extends TriggerHandler {

    protected override void beforeInsert() {
        syncProducts((List<LeadProduct__c>) Trigger.new, new Map<Id, LeadProduct__c>());
    }

    protected override void beforeUpdate() {
        syncProducts((List<LeadProduct__c>) Trigger.new, (Map<Id, LeadProduct__c>) Trigger.oldMap);
    }

    // Copies codes from the chosen Product, or finds the Product from the codes.
    private static void syncProducts(List<LeadProduct__c> rows, Map<Id, LeadProduct__c> oldRows) {
        if (!Schema.sObjectType.Product2.isAccessible()) {
            return;
        }
        List<LeadProduct__c> needCodes = new List<LeadProduct__c>();
        List<LeadProduct__c> needProduct = new List<LeadProduct__c>();
        Set<String> families = new Set<String>();
        Set<String> classes = new Set<String>();
        for (LeadProduct__c row : rows) {
            LeadProduct__c oldRow = oldRows.get(row.Id);
            Boolean hasCodes = String.isNotBlank(row.Product_Family_Code__c) && String.isNotBlank(row.Product_Class_Code__c);
            if (row.Product__c != null && (oldRow == null || oldRow.Product__c != row.Product__c || !hasCodes)) {
                needCodes.add(row);
            } else if (row.Product__c == null && hasCodes) {
                needProduct.add(row);
                families.add(row.Product_Family_Code__c.trim());
                classes.add(row.Product_Class_Code__c.trim());
            }
        }

        if (!needCodes.isEmpty()) {
            Set<Id> productIds = new Set<Id>();
            for (LeadProduct__c row : needCodes) {
                productIds.add(row.Product__c);
            }
            Map<Id, Product2> products = new Map<Id, Product2>([
                SELECT Id, ItemFamily__c, ProductClassCode__c FROM Product2 WHERE Id IN :productIds WITH USER_MODE
            ]);
            for (LeadProduct__c row : needCodes) {
                Product2 product = products.get(row.Product__c);
                if (product != null) {
                    row.Product_Family_Code__c = product.ItemFamily__c;
                    row.Product_Class_Code__c = product.ProductClassCode__c;
                }
            }
        }

        if (needProduct.isEmpty()) {
            return;
        }
        List<Product2> candidates = [
            SELECT Id, Name, ItemFamily__c, ProductClassCode__c FROM Product2
            WHERE IsActive = true AND ItemFamily__c IN :families AND ProductClassCode__c IN :classes
            WITH USER_MODE
        ];
        for (LeadProduct__c row : needProduct) {
            List<Product2> matches = new List<Product2>();
            for (Product2 candidate : candidates) {
                if (candidate.ItemFamily__c.equalsIgnoreCase(row.Product_Family_Code__c.trim())
                    && candidate.ProductClassCode__c.equalsIgnoreCase(row.Product_Class_Code__c.trim())) {
                    matches.add(candidate);
                }
            }
            if (matches.size() > 1 && String.isNotBlank(row.Submitted_Product_Name__c)) {
                List<Product2> sameName = new List<Product2>();
                for (Product2 match : matches) {
                    if (match.Name.equalsIgnoreCase(row.Submitted_Product_Name__c.trim())) {
                        sameName.add(match);
                    }
                }
                matches = sameName;
            }
            if (matches.size() == 1) {
                row.Product__c = matches[0].Id;
            }
        }
    }
}