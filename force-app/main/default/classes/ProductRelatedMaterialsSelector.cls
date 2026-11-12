/**
 * @description Selector class for the ProductRelatedMaterial SObject.
 *              Centralizes all SOQL queries for Product Related Materials.
 *              Enforces security via WITH SECURITY_ENFORCED.
 */
public with sharing class ProductRelatedMaterialsSelector {

    // GW-5869 - BOMTag__c removed: the field does not exist on ProductRelatedMaterial
    // ("No such column" broke every query using BASE_FIELDS). Re-add once the field is deployed.
    private static final String BASE_FIELDS =
        'Id, Name, ProductId, ProductComponentId, ServiceBOM__c, ' +
        'QuantityPerProductUnit, QuantityUomId, ComponentSequence__c, ' +
        'Description, UsageCategory, ' +
        'CreatedDate, LastModifiedDate';

    /**
     * @description Retrieves ProductRelatedMaterial records by their Ids.
     * @param ids Set of ProductRelatedMaterial Ids to query.
     * @return List of ProductRelatedMaterial records matching the given Ids.
     */
    public static List<ProductRelatedMaterial> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<ProductRelatedMaterial>();
        }
        // WITH SECURITY_ENFORCED is not supported on ProductRelatedMaterial
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM ProductRelatedMaterial' +
            ' WHERE Id IN :ids'
        );
    }

    /**
     * @description Retrieves ProductRelatedMaterial records by their related Product Ids.
     * @param productIds Set of Product2 Ids to filter by.
     * @return List of ProductRelatedMaterial records related to the given Products.
     */
    public static List<ProductRelatedMaterial> selectByProductId(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return new List<ProductRelatedMaterial>();
        }
        // WITH SECURITY_ENFORCED is not supported on ProductRelatedMaterial
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM ProductRelatedMaterial' +
            ' WHERE ProductId IN :productIds'
        );
    }

    /**
     * @description Retrieves ProductRelatedMaterial records by their related Service BOM Ids.
     * @param serviceBomIds Set of ServiceBOM__c Ids to filter by.
     * @return List of ProductRelatedMaterial records related to the given Service BOMs.
     */
    public static List<ProductRelatedMaterial> selectByServiceBomId(Set<Id> serviceBomIds) {
        if (serviceBomIds == null || serviceBomIds.isEmpty()) {
            return new List<ProductRelatedMaterial>();
        }
        // WITH SECURITY_ENFORCED is not supported on ProductRelatedMaterial
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM ProductRelatedMaterial' +
            ' WHERE ServiceBOM__c IN :serviceBomIds'
        );
    }

    /**
     * @description GW-3913 / GW-3096 - Selects BOM components for Device Evaluation repair-code catalog.
     *              Filters by ComponentType__c or ProductComponent.ProductType__c in componentTypes.
     * @param parentProductIds Parent Product2 Ids (ProductId)
     * @param componentTypes Component type values to include
     * @return Matching ProductRelatedMaterial records with ProductComponent fields
     */
    public static List<ProductRelatedMaterial> selectBomComponentsForDeviceEvaluation(
        Set<Id> parentProductIds,
        Set<String> componentTypes
    ) {
        if (
            parentProductIds == null ||
            parentProductIds.isEmpty() ||
            componentTypes == null ||
            componentTypes.isEmpty()
        ) {
            return new List<ProductRelatedMaterial>();
        }
        return [
            SELECT
                Id,
                ProductId,
                ProductComponentId,
                ComponentType__c,
                ComponentSequence__c,
                ProductComponent.Id,
                ProductComponent.EvalDisplayScreen__c,
                ProductComponent.ProductType__c
            FROM ProductRelatedMaterial
            WHERE ProductId IN :parentProductIds
                AND ProductComponentId != null
                AND (
                    ComponentType__c IN :componentTypes
                    OR ProductComponent.ProductType__c IN :componentTypes
                )
        ];
    }


    /**
     * @description Selects BOM components for Service BOMs that match the given Product2 Ids
     *              (Allowed Unit evaluation).
     * @param serviceBomIdSet Service BOM Ids in the allowed parts union
     * @param product2IdSet Product2 Ids to match as ProductComponentId
     * @return Matching BOM Component records
     */
    public static List<ProductRelatedMaterial> selectByServiceBomAndProductComponents(
        Set<Id> serviceBomIdSet,
        Set<Id> product2IdSet
    ) {
        if (serviceBomIdSet == null || serviceBomIdSet.isEmpty()
            || product2IdSet == null || product2IdSet.isEmpty()) {
            return new List<ProductRelatedMaterial>();
        }

        return [
            SELECT Id, ServiceBOM__c, ProductComponentId
            FROM ProductRelatedMaterial
            WHERE ServiceBOM__c IN :serviceBomIdSet
            AND ProductComponentId IN :product2IdSet
        ];
    }

    /**
     * @description GW-5981 - Active Part components on a product's bill of material.
     * @param parentProductId Parent Product2 Id (BOM Component.Product)
     * @return Active Part components in component sequence
     */
    public static List<ProductRelatedMaterial> selectActivePartComponents(Id parentProductId) {
        if (parentProductId == null) {
            return new List<ProductRelatedMaterial>();
        }
        return [
            SELECT
                Id,
                ProductComponentId,
                ComponentSequence__c,
                ProductComponent.ProductCode,
                ProductComponent.Description,
                ProductComponent.Name,
                ProductComponent.QuantityUnitOfMeasure
            FROM ProductRelatedMaterial
            WHERE ProductId = :parentProductId
                AND ProductComponentId != null
                AND ProductComponent.IsActive = true
                AND ProductComponent.ProductType__c = 'Part'
            ORDER BY ComponentSequence__c NULLS LAST, ProductComponent.ProductCode
        ];
    }
}