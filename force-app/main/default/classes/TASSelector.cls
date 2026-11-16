/**
* @author PWC Developer
* @date 2026/06/10
*
* @group Overlay Assignment
*
* @description
* GC-3088 - SOQL - only selector for OrderLineContact__c Object
*/
public with sharing class TASSelector {
    
    public static final Integer TERRITORY_SEARCH_LIMIT = 100;
 /**
* @description
* GC-3088 - Finds territory records matching user search text.
* 
* @param searchKey User-entered search text.
* @return Matching OrderLineContact__c records.
* 
* @example
* TASSelector.selectByTerritorySearch(searchKey);
*/
    public static List<OrderLineContact__c> selectByTerritorySearch(String searchKey) {
        String key = '%' + String.escapeSingleQuotes(String.isBlank(searchKey) ? '' : searchKey.trim()) + '%';
        
        return [
            SELECT TerritoryID__c,
            TerritoryDescription__c,
            TerritoryNumber__c,
            TASAddressId__c,
            TASZone__c,
            //Commented as part of GC#3108  ZoneName__c,
            RegionName__c
            FROM OrderLineContact__c
            WHERE (TerritoryID__c != null
                   AND TerritoryID__c LIKE :key)
            OR TerritoryDescription__c LIKE :key
            OR TerritoryNumber__c LIKE :key
            WITH SECURITY_ENFORCED
            LIMIT :TERRITORY_SEARCH_LIMIT
        ];
    }
    
    /**
* @description
* GC-3088 - Selects TAS source records by Territory IDs.
* 
* @param territoryIdSet Territory IDs.
* @return Matching OrderLineContact__c records.
* 
* @example
* TASSelector.selectByTerritoryIds(territoryIdSet);
*/
    public static List<OrderLineContact__c> selectByTerritoryIds(Set<String> territoryIdSet) {
        if (territoryIdSet == null || territoryIdSet.isEmpty()) {
            return new List<OrderLineContact__c>();
        }
        
        return [
            SELECT TerritoryID__c,
            TerritoryDescription__c,
            TerritoryNumber__c,
            TASAddressId__c
            FROM OrderLineContact__c
            WHERE TerritoryID__c IN :territoryIdSet
            AND TASAddressId__c != null
            WITH SECURITY_ENFORCED
        ];
    }
    
    /**
* @description
* GC-3088 - Selects TAS source records by Territory IDs and TAS Address IDs.
* 
* @param territoryIdSet Territory IDs.
* @param tasAddressIdSet TAS Address IDs.
* @return Matching OrderLineContact__c records.
* 
* @example
* TASSelector.selectAssignmentSources(territoryIdSet. tasAddressIdSet);
*/
    public static List<OrderLineContact__c> selectAssignmentSources(
        Set<String> territoryIdSet,
        Set<String> tasAddressIdSet
    ) {
        if (territoryIdSet == null || territoryIdSet.isEmpty() || tasAddressIdSet == null || tasAddressIdSet.isEmpty()) {
            return new List<OrderLineContact__c>();
        }
        
        return [
            SELECT TerritoryID__c,
            TerritoryDescription__c,
            TerritoryNumber__c,
            TASAddressId__c,
            BusinessUnit__c,
            TASZone__c,
            TAS_Sales_Category__c, //GC#3352
            SalesCategoryDescription__c, //GC#3352
           //Commented as part of GC#3108  ZoneName__c,
           
            RegionName__c
            FROM OrderLineContact__c
            WHERE TerritoryID__c IN :territoryIdSet
            AND TASAddressId__c IN :tasAddressIdSet
            AND TASAddressId__c != null
            WITH SECURITY_ENFORCED
        ];
    }

    /**
     * @description GCL-79 - Life Sciences territory rows matching Territory ID, Description, or Number.
     *              Existing Healthcare search is unchanged.
     * @param searchKey User-entered search text.
     * @param classCodes Life Sciences ClassCode__c values.
     * @param rowLimit Maximum rows to return.
     * @return Matching Order Line rows. Empty when the search text or class codes are blank.
     */
    public static List<OrderLineContact__c> selectLifeSciencesTerritoriesBySearch(
        String searchKey,
        Set<String> classCodes,
        Integer rowLimit
    ) {
        if (String.isBlank(searchKey) || classCodes == null || classCodes.isEmpty() || rowLimit == null || rowLimit <= 0) {
            return new List<OrderLineContact__c>();
        }
        String key = '%' + searchKey.trim() + '%';
        return [
            SELECT TerritoryID__c, TerritoryDescription__c
            FROM OrderLineContact__c
            WHERE TerritoryID__c != null
            AND (
                TerritoryID__c LIKE :key
                OR TerritoryDescription__c LIKE :key
                OR TerritoryNumber__c LIKE :key
            )
            AND ClassCode__c IN :classCodes
            WITH USER_MODE
            LIMIT :rowLimit
        ];
    }

    /**
     * @description GCL-79 - Life Sciences territory rows for the selected Territory IDs.
     * @param territoryIds Territory IDs to load.
     * @param classCodes Life Sciences ClassCode__c values.
     * @return Rows with a TAS address. The caller keeps the first row per address.
     */
    public static List<OrderLineContact__c> selectLifeSciencesTerritoriesByIds(
        Set<String> territoryIds,
        Set<String> classCodes
    ) {
        if (territoryIds == null || territoryIds.isEmpty() || classCodes == null || classCodes.isEmpty()) {
            return new List<OrderLineContact__c>();
        }
        return [
            SELECT TerritoryID__c, TerritoryDescription__c, TerritoryNumber__c, TASAddressId__c,
                   TAS_Sales_Category__c, SalesCategoryDescription__c,
                   BusinessUnit__c, TASZone__c, RegionName__c
            FROM OrderLineContact__c
            WHERE TerritoryID__c IN :territoryIds
            AND TASAddressId__c != null
            AND ClassCode__c IN :classCodes
            WITH USER_MODE
        ];
    }
}