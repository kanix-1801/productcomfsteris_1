/**
 * @description Looks up trunk-stock Product Items by Product Code for WO debrief barcode scans.
 * @group Work Order Debrief
 * @see woDebriefES, woDebriefIMSchildWO
 */
public with sharing class WoDebriefProductItemController {

    /**
     * @description Match result for a Product Code scan within a Service Resource location.
     */
    public class MatchResult {
        /** @description ProductItem Id when a match is found. */
        @AuraEnabled public Id productItemId;
        /** @description Product Item display name. */
        @AuraEnabled public String productName;
        /** @description Related Product2 Id. */
        @AuraEnabled public Id product2Id;
        /** @description Product2.IsReturnable__c when available. */
        @AuraEnabled public Boolean isReturnable;
        /** @description Product2.ProductCode when available. */
        @AuraEnabled public String productCode;
        /** @description Product2.Description when available (stamped to Part Description). */
        @AuraEnabled public String description;
        /** @description Product2.RefurbishedProduct__c when the selected product has a refurbished part. */
        @AuraEnabled public Id refurbishedProductId;
        /** @description Name of Product2.RefurbishedProduct__c. */
        @AuraEnabled public String refurbishedProductName;
        /** @description Number of matching Product Items (capped at query limit). */
        @AuraEnabled public Integer matchCount;
        /** @description Service Resource Location Id used for the search. */
        @AuraEnabled public Id locationId;
    }

    /**
     * @description Finds an in-stock Product Item at the Service Resource trunk location by Product Code.
     * @param productCode Scanned / typed Product Code
     * @param serviceResourceId Assigned Service Resource Id
     * @return Match result; productItemId is null when no match exists
     */
    @AuraEnabled
    public static MatchResult findByProductCode(String productCode, Id serviceResourceId) {
        MatchResult result = new MatchResult();
        result.matchCount = 0;

        if (String.isBlank(productCode) || serviceResourceId == null) {
            return result;
        }

        List<ServiceResource> resources = [
            SELECT LocationId
            FROM ServiceResource
            WHERE Id = :serviceResourceId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (resources.isEmpty() || resources[0].LocationId == null) {
            return result;
        }

        Id locationId = resources[0].LocationId;
        result.locationId = locationId;
        String code = productCode.trim();

        List<ProductItem> matches = [
            SELECT Id, ProductName, Product2Id, Product2.IsReturnable__c,
                   Product2.ProductCode, Product2.Description,
                   Product2.RefurbishedProduct__c, Product2.RefurbishedProduct__r.Name
            FROM ProductItem
            WHERE LocationId = :locationId
                AND QuantityOnHand > 0
                AND Product2.ProductCode = :code
            WITH SECURITY_ENFORCED
            ORDER BY QuantityOnHand DESC, LastModifiedDate DESC
            LIMIT 2
        ];

        result.matchCount = matches.size();
        if (matches.isEmpty()) {
            return result;
        }

        ProductItem item = matches[0];
        result.productItemId = item.Id;
        result.productName = item.ProductName;
        result.product2Id = item.Product2Id;
        result.isReturnable = item.Product2 != null ? item.Product2.IsReturnable__c : null;
        result.productCode = item.Product2 != null ? item.Product2.ProductCode : null;
        result.description = item.Product2 != null ? item.Product2.Description : null;
        result.refurbishedProductId = item.Product2 != null ? item.Product2.RefurbishedProduct__c : null;
        result.refurbishedProductName = item.Product2 != null && item.Product2.RefurbishedProduct__r != null
            ? item.Product2.RefurbishedProduct__r.Name
            : null;
        return result;
    }

    /**
     * @description Location Id for any Service Resource, used to filter trunk-stock Product Items.
     * @param serviceResourceId Assigned Service Resource Id
     * @return Location Id, or null when the resource has no inventory location
     */
    @AuraEnabled
    public static Id getLocationIdForServiceResource(Id serviceResourceId) {
        if (serviceResourceId == null) {
            return null;
        }
        List<ServiceResource> resources = [
            SELECT LocationId
            FROM ServiceResource
            WHERE Id = :serviceResourceId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return resources.isEmpty() ? null : resources[0].LocationId;
    }

    /**
     * @description GW-4311 / GW-2965 - Finds an active Product2 by Product Code for barcode scans.
     * @param productCode Scanned / typed Product Code
     * @param productType Optional ProductType__c filter (Part, Service Code). Null skips the filter.
     * @return Match result; product2Id is null when no match exists
     */
    @AuraEnabled
    public static MatchResult findProductByProductCode(String productCode, String productType) {
        MatchResult result = new MatchResult();
        result.matchCount = 0;

        if (String.isBlank(productCode)) {
            return result;
        }

        String code = productCode.trim();
        List<Product2> matches;
        if (String.isBlank(productType)) {
            matches = [
                SELECT Id, Name, ProductCode, Description, IsReturnable__c,
                       RefurbishedProduct__c, RefurbishedProduct__r.Name
                FROM Product2
                WHERE ProductCode = :code
                    AND IsActive = true
                WITH SECURITY_ENFORCED
                ORDER BY LastModifiedDate DESC
                LIMIT 2
            ];
        } else {
            matches = [
                SELECT Id, Name, ProductCode, Description, IsReturnable__c,
                       RefurbishedProduct__c, RefurbishedProduct__r.Name
                FROM Product2
                WHERE ProductCode = :code
                    AND IsActive = true
                    AND ProductType__c = :productType
                WITH SECURITY_ENFORCED
                ORDER BY LastModifiedDate DESC
                LIMIT 2
            ];
        }

        result.matchCount = matches.size();
        if (matches.isEmpty()) {
            return result;
        }

        Product2 product = matches[0];
        result.product2Id = product.Id;
        result.productName = product.Name;
        result.isReturnable = product.IsReturnable__c;
        result.productCode = product.ProductCode;
        result.description = product.Description;
        result.refurbishedProductId = product.RefurbishedProduct__c;
        result.refurbishedProductName = product.RefurbishedProduct__r != null
            ? product.RefurbishedProduct__r.Name
            : null;
        return result;
    }

    /**
     * @description Picklist-style option for a matching Service Code product.
     */
    public class RepairCodeOption {
        /** @description Product2 Id of the service code. */
        @AuraEnabled public Id id;
        /** @description Product Code value. */
        @AuraEnabled public String productCode;
        /** @description Product Name. */
        @AuraEnabled public String name;
        /** @description Product Description. */
        @AuraEnabled public String description;
        /** @description Display label combining product code and name when both are present. */
        @AuraEnabled public String label;
    }

    /**
     * @description Result payload for repair-code lookup against a Device Type / part Product2.
     */
    public class RepairCodesForProductResult {
        /** @description Trimmed Base Service Code from the product. */
        @AuraEnabled public String baseServiceCode;
        /** @description Matching Service Code product options. */
        @AuraEnabled public List<RepairCodeOption> options;
    }

    /**
     * @description Service Code options for a Device Type / part product.
     * @param product2Id Device Type or part Product2 Id
     * @return Base service code and matching Service Code options
     */
    @AuraEnabled
    public static RepairCodesForProductResult getRepairCodesForProduct(Id product2Id) {
        WoDebriefIMSchildWOController.RepairCodesForProductResult source =
            WoDebriefIMSchildWOController.getRepairCodesForProduct(product2Id);

        RepairCodesForProductResult result = new RepairCodesForProductResult();
        result.baseServiceCode = source == null ? '' : source.baseServiceCode;
        result.options = new List<RepairCodeOption>();
        if (source == null || source.options == null) {
            return result;
        }

        for (WoDebriefIMSchildWOController.RepairCodeOption sourceOption : source.options) {
            RepairCodeOption option = new RepairCodeOption();
            option.id = sourceOption.id;
            option.productCode = sourceOption.productCode;
            option.name = sourceOption.name;
            option.description = sourceOption.description;
            option.label = sourceOption.label;
            result.options.add(option);
        }
        return result;
    }

    /**
     * @description Pricebook entry for a Device Type product on the Work Order pricebook.
     * @param workOrderId Work Order Id
     * @param product2Id Device Type Product2 Id
     * @return PricebookEntry Id, or null when no matching entry exists
     */
    @AuraEnabled
    public static Id resolvePricebookEntryId(Id workOrderId, Id product2Id) {
        return WoDebriefIMSchildWOController.resolvePricebookEntryId(workOrderId, product2Id);
    }

    /**
     * @description Allowed Unit for a Product Item. Returns unevaluated when the
     *              WorkOrderLineItemService class is not available in this org.
     * @param workOrderId Work Order Id
     * @param productItemId Selected Product Item Id
     * @return Allowed Unit evaluation DTO
     */
    @AuraEnabled(cacheable=true)
    public static AllowedUnitEvaluationDTO evaluateAllowedUnit(Id workOrderId, Id productItemId) {
        return AllowedUnitEvaluationDTO.unevaluated();
    }

    /**
     * @description Allowed Unit for a Product2. Returns unevaluated when the
     *              WorkOrderLineItemService class is not available in this org.
     * @param workOrderId Work Order Id
     * @param product2Id Selected Product2 Id
     * @return Allowed Unit evaluation DTO
     */
    @AuraEnabled(cacheable=true)
    public static AllowedUnitEvaluationDTO evaluateAllowedUnitByProduct(Id workOrderId, Id product2Id) {
        return AllowedUnitEvaluationDTO.unevaluated();
    }

    /**
     * @description UsageConsumption record type Id for ES debrief Work Order Line Item creates.
     * @return Record type Id, or null when the record type is not available
     */
    @AuraEnabled(cacheable=true)
    public static Id getUsageConsumptionRecordTypeId() {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'WorkOrderLineItem'
                AND DeveloperName = 'UsageConsumption'
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return recordTypes.isEmpty() ? null : recordTypes[0].Id;
    }

    /**
     * @description ProductServiced record type Id for woDebrief Product Serviced lines.
     * @return Record type Id, or null when the record type is not available
     */
    @AuraEnabled(cacheable=true)
    public static Id getProductServicedRecordTypeId() {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'WorkOrderLineItem'
                AND DeveloperName = 'ProductServiced'
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return recordTypes.isEmpty() ? null : recordTypes[0].Id;
    }
}