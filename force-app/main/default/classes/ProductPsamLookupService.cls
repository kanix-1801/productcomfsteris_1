/**
 * @author PWC Developer
 * @date 2026/07/07
 *
 * @group GC-2649 Generate Quote
 *
 * @description
 * Resolves Product2.PSAM__c lookup data when the field is available in the org schema.
 */
public with sharing class ProductPsamLookupService {
    public static final String PRODUCT_PSAM_LOOKUP_FIELD = 'PSAM__c';
    public static final String PRODUCT_PSAM_RELATIONSHIP = 'PSAM__r';

    /**
     * @description Indicates whether Product2.PSAM__c exists in the org schema.
     * @return True when the Product PSAM lookup field is available.
     */
    public static Boolean isProductPsamLookupAvailable() {
        return Schema.SObjectType.Product2.fields.getMap().containsKey(PRODUCT_PSAM_LOOKUP_FIELD);
    }

    /**
     * @description Reads the Product PSAM lookup Id from an in-memory Product2 record.
     * @param productRecord Product2 record.
     * @return PSAM record Id when populated.
     */
    public static Id getPsamId(Product2 productRecord) {
        if (productRecord == null || !isPopulatedField(productRecord, PRODUCT_PSAM_LOOKUP_FIELD)) {
            return null;
        }

        return (Id) productRecord.get(PRODUCT_PSAM_LOOKUP_FIELD);
    }

    /**
     * @description Reads the related PSAM record from an in-memory Product2 record.
     * @param productRecord Product2 record.
     * @return Related PSAM record when populated.
     */
    public static PSAM__c getPsamRelationship(Product2 productRecord) {
        if (productRecord == null || !isPopulatedField(productRecord, PRODUCT_PSAM_RELATIONSHIP)) {
            return null;
        }

        return (PSAM__c) productRecord.getSObject(PRODUCT_PSAM_RELATIONSHIP);
    }

    /**
     * @description Loads PSAM records linked to Products.
     * @param product2Ids Product2 Id set.
     * @return PSAM records indexed by Product2 Id.
     */
    public static Map<Id, PSAM__c> selectPsamByProduct2Ids(Set<Id> product2Ids) {
        Map<Id, PSAM__c> psamByProduct2Id = new Map<Id, PSAM__c>();

        if (!isProductPsamLookupAvailable() || product2Ids == null || product2Ids.isEmpty()) {
            return psamByProduct2Id;
        }

        String query =
            'SELECT Id, ' +
            PRODUCT_PSAM_LOOKUP_FIELD +
            ', ' +
            PRODUCT_PSAM_RELATIONSHIP +
            '.Id, ' +
            PRODUCT_PSAM_RELATIONSHIP +
            '.Name, ' +
            PRODUCT_PSAM_RELATIONSHIP +
            '.ProductFAMCode__c, ' +
            PRODUCT_PSAM_RELATIONSHIP +
            '.ProductGroupName__c, ' +
            PRODUCT_PSAM_RELATIONSHIP +
            '.ProductSubgroupName__c, ' +
            PRODUCT_PSAM_RELATIONSHIP +
            '.ProductSubgroupDetailName__c ' +
            'FROM Product2 ' +
            'WHERE Id IN :product2Ids AND ' +
            PRODUCT_PSAM_LOOKUP_FIELD +
            ' != null';

        for (Product2 productRecord : Database.query(query)) {
            PSAM__c psamRecord = getPsamRelationship(productRecord);
            if (psamRecord != null) {
                psamByProduct2Id.put(productRecord.Id, psamRecord);
            }
        }

        return psamByProduct2Id;
    }

    /**
     * @description Loads PSAM records linked to Products on Pricebook Entries.
     * @param pricebookEntryIds Pricebook Entry Id set.
     * @return PSAM records indexed by Pricebook Entry Id.
     */
    public static Map<Id, PSAM__c> selectPsamByPricebookEntryIds(Set<Id> pricebookEntryIds) {
        Map<Id, PSAM__c> psamByPricebookEntryId = new Map<Id, PSAM__c>();

        if (!isProductPsamLookupAvailable() || pricebookEntryIds == null || pricebookEntryIds.isEmpty()) {
            return psamByPricebookEntryId;
        }

        Map<Id, Id> product2IdByPricebookEntryId = new Map<Id, Id>();

        for (PricebookEntry pricebookEntry : [
            SELECT Id, Product2Id
            FROM PricebookEntry
            WHERE Id IN :pricebookEntryIds
                AND Product2Id != null
            WITH USER_MODE
        ]) {
            product2IdByPricebookEntryId.put(pricebookEntry.Id, pricebookEntry.Product2Id);
        }

        Map<Id, PSAM__c> psamByProduct2Id = selectPsamByProduct2Ids(
            new Set<Id>(product2IdByPricebookEntryId.values())
        );

        for (Id pricebookEntryId : product2IdByPricebookEntryId.keySet()) {
            Id product2Id = product2IdByPricebookEntryId.get(pricebookEntryId);
            if (psamByProduct2Id.containsKey(product2Id)) {
                psamByPricebookEntryId.put(pricebookEntryId, psamByProduct2Id.get(product2Id));
            }
        }

        return psamByPricebookEntryId;
    }

    private static Boolean isPopulatedField(SObject record, String fieldName) {
        return record != null
            && record.getPopulatedFieldsAsMap().containsKey(fieldName);
    }
}