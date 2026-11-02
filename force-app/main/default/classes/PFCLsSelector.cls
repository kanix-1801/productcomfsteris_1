/**
 * @description Selector class for the PFCL__c SObject.
 *              Centralizes all SOQL queries for PFCLs.
 */
public with sharing class PFCLsSelector {

    private static final String BASE_FIELDS =
        'Id, Name, PFCL__c, Description__c, BusinessUnit__c, DeviceType__c, ' +
        'Manufacturer__c, Productline__c, SubProductLine__c, ' +
        'CalibrationRequired__c, ChecklistRequired__c, Parent__c, ' +
        'CreatedDate, LastModifiedDate';

    /**
     * @description Retrieves PFCL__c records by their Ids.
     * @param ids Set of PFCL__c Ids to query.
     * @return List of PFCL__c records matching the given Ids.
     */
    public static List<PFCL__c> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<PFCL__c>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM PFCL__c' +
            ' WHERE Id IN :ids'
        );
    }

    /**
     * @description Retrieves PFCL__c records by Name.
     * @param names Set of PFCL Names to filter by.
     * @return List of PFCL__c records matching the given Names.
     */
    public static List<PFCL__c> selectByName(Set<String> names) {
        if (names == null || names.isEmpty()) {
            return new List<PFCL__c>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM PFCL__c' +
            ' WHERE Name IN :names' +
            ' ORDER BY Name ASC'
        );
    }

    /**
     * @description Selects Version PFCL records matching Asset.PFCL__c by Name or PFCL#.
     *              Includes Root Parent SBOMRequired__c for the GW-4218 cross-reference gate.
     * @param assetPfclValueSet Asset PFCL formula values
     * @return Matching PFCL records with Parent and SBOM Required
     */
    public static List<PFCL__c> selectByAssetPfclValues(Set<String> assetPfclValueSet) {
        if (assetPfclValueSet == null || assetPfclValueSet.isEmpty()) {
            return new List<PFCL__c>();
        }

        return [
            SELECT
                Id,
                Parent__c,
                Name,
                PFCL__c,
                SBOMRequired__c,
                Parent__r.SBOMRequired__c
            FROM PFCL__c
            WHERE Name IN :assetPfclValueSet
            OR PFCL__c IN :assetPfclValueSet
        ];
    }
}