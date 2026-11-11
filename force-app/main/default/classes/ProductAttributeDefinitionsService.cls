/**
 * @description GW-5102 - ProductAttributeDefinition inspection-fee lookups.
 *              Fields are queried dynamically so this class compiles before those fields exist.
 */
public with sharing class ProductAttributeDefinitionsService {
    private static final String OBJECT_API_NAME = 'ProductAttributeDefinition';
    private static final String FIELD_INSPECTION_APPLICABLE = 'InspectionFeeApplicable__c';
    private static final String FIELD_INSPECTION_SERVICE_CODE = 'InspectionServiceCode__c';

    @TestVisible
    private static Boolean schemaAvailableOverride;

    /**
     * @description Product Attribute Definitions where Inspection Fee Applicable is true.
     * @param productIds Product2 Ids (the Product Serviced QLI product)
     * @return Matching SObject rows (empty when schema or rows are unavailable)
     */
    public static List<SObject> getInspectionFeeApplicableByProductIds(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty() || !isInspectionFeeSchemaAvailable()) {
            return new List<SObject>();
        }

        String productField = resolveProductLookupField();
        if (String.isBlank(productField)) {
            return new List<SObject>();
        }

        String query =
            'SELECT Id, ' +
            productField +
            ', ' +
            FIELD_INSPECTION_SERVICE_CODE +
            ' FROM ' +
            OBJECT_API_NAME +
            ' WHERE ' +
            productField +
            ' IN :productIds AND ' +
            FIELD_INSPECTION_APPLICABLE +
            ' = true WITH SYSTEM_MODE';
        try {
            return Database.query(query);
        } catch (Exception ignored) {
            return new List<SObject>();
        }
    }

    /**
     * @description Reads the Inspection Service Code Product Id from a PAD row.
     * @param attributeDefinition ProductAttributeDefinition row
     * @return Inspection service Product2 Id, or null
     */
    public static Id getInspectionServiceCodeProductId(SObject attributeDefinition) {
        if (attributeDefinition == null) {
            return null;
        }
        try {
            return (Id) attributeDefinition.get(FIELD_INSPECTION_SERVICE_CODE);
        } catch (Exception ignored) {
            return null;
        }
    }

    /**
     * @description Reads the Product lookup from a PAD row.
     * @param attributeDefinition ProductAttributeDefinition row
     * @return Product2 Id, or null
     */
    public static Id getProductId(SObject attributeDefinition) {
        if (attributeDefinition == null) {
            return null;
        }
        String productField = resolveProductLookupField();
        if (String.isBlank(productField)) {
            return null;
        }
        try {
            return (Id) attributeDefinition.get(productField);
        } catch (Exception ignored) {
            return null;
        }
    }

    @TestVisible
    private static Boolean isInspectionFeeSchemaAvailable() {
        if (Test.isRunningTest() && schemaAvailableOverride != null) {
            return schemaAvailableOverride;
        }
        if (!Schema.getGlobalDescribe().containsKey(OBJECT_API_NAME)) {
            return false;
        }
        Map<String, Schema.SObjectField> fieldMap =
            Schema.getGlobalDescribe().get(OBJECT_API_NAME).getDescribe().fields.getMap();
        return fieldMap.containsKey(FIELD_INSPECTION_APPLICABLE.toLowerCase()) &&
            fieldMap.containsKey(FIELD_INSPECTION_SERVICE_CODE.toLowerCase()) &&
            String.isNotBlank(resolveProductLookupField());
    }

    private static String resolveProductLookupField() {
        if (!Schema.getGlobalDescribe().containsKey(OBJECT_API_NAME)) {
            return null;
        }
        Map<String, Schema.SObjectField> fieldMap =
            Schema.getGlobalDescribe().get(OBJECT_API_NAME).getDescribe().fields.getMap();
        if (fieldMap.containsKey('product2id')) {
            return 'Product2Id';
        }
        if (fieldMap.containsKey('productid')) {
            return 'ProductId';
        }
        return null;
    }
}