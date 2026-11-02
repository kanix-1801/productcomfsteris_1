/**
 * @description Selector class for the ServiceBOM__c SObject.
 *              Centralizes all SOQL queries for Service BOMs.
 *              Centralizes Service BOM SOQL. Classes run with sharing.
 */
public with sharing class ServiceBOMsSelector {

    private static final String BASE_FIELDS =
        'Id, Name, ExternalID__c, Type__c, PFCL__c, ' +
        'CreatedDate, LastModifiedDate';

    /**
     * @description Retrieves ServiceBOM__c records by their Ids.
     * @param ids Set of ServiceBOM__c Ids to query.
     * @return List of ServiceBOM__c records matching the given Ids.
     */
    public static List<ServiceBOM__c> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<ServiceBOM__c>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM ServiceBOM__c' +
            ' WHERE Id IN :ids'
        );
    }

    /**
     * @description Retrieves ServiceBOM__c records by their parent PFCL Ids.
     * @param pfclIds Set of parent PFCL__c Ids to filter by.
     * @return List of ServiceBOM__c records related to the given PFCLs.
     */
    public static List<ServiceBOM__c> selectByPFCLId(Set<Id> pfclIds) {
        if (pfclIds == null || pfclIds.isEmpty()) {
            return new List<ServiceBOM__c>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM ServiceBOM__c' +
            ' WHERE PFCL__c IN :pfclIds' +
            ' ORDER BY Name ASC'
        );
    }
}