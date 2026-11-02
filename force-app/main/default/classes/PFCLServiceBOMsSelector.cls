/**
 * @description Selector class for the PFCLServiceBOM__c SObject.
 *              Centralizes all SOQL queries for the PFCL/Service BOM junction.
 *              Enforces security via WITH USER_MODE.
 */
public with sharing class PFCLServiceBOMsSelector {

    private static final String BASE_FIELDS =
        'Id, Name, PFCL__c, ServiceBOM__c, ' +
        'CreatedDate, LastModifiedDate';

    /**
     * @description Retrieves PFCLServiceBOM__c records by their Ids.
     * @param ids Set of PFCLServiceBOM__c Ids to query.
     * @return List of PFCLServiceBOM__c records matching the given Ids.
     */
    public static List<PFCLServiceBOM__c> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<PFCLServiceBOM__c>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM PFCLServiceBOM__c' +
            ' WHERE Id IN :ids' +
            ' WITH USER_MODE'
        );
    }

    /**
     * @description Retrieves PFCLServiceBOM__c records by their parent PFCL Ids.
     * @param pfclIds Set of parent PFCL__c Ids to filter by.
     * @return List of PFCLServiceBOM__c records related to the given PFCLs.
     */
    public static List<PFCLServiceBOM__c> selectByPFCLId(Set<Id> pfclIds) {
        if (pfclIds == null || pfclIds.isEmpty()) {
            return new List<PFCLServiceBOM__c>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM PFCLServiceBOM__c' +
            ' WHERE PFCL__c IN :pfclIds' +
            ' WITH USER_MODE'
        );
    }

    /**
     * @description Retrieves PFCLServiceBOM__c records by their parent Service BOM Ids.
     * @param serviceBomIds Set of parent ServiceBOM__c Ids to filter by.
     * @return List of PFCLServiceBOM__c records related to the given Service BOMs.
     */
    public static List<PFCLServiceBOM__c> selectByServiceBOMId(Set<Id> serviceBomIds) {
        if (serviceBomIds == null || serviceBomIds.isEmpty()) {
            return new List<PFCLServiceBOM__c>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM PFCLServiceBOM__c' +
            ' WHERE ServiceBOM__c IN :serviceBomIds' +
            ' WITH USER_MODE'
        );
    }
}