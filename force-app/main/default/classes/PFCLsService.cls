/**
 * @description Service class for PFCL__c business operations.
 *              Entry point for all PFCL-related transactions.
 *              Performs DML directly (no Unit of Work).
 */
public with sharing class PFCLsService {

    /**
     * @description Creates new PFCL__c records.
     * @param pfcls List of PFCL__c records to create.
     */
    public static void createPFCLs(List<PFCL__c> pfcls) {
        if (pfcls == null || pfcls.isEmpty()) {
            return;
        }
        Logger.setScenario('PFCL Management');
        try {
            PFCLs domain = new PFCLs(pfcls);
            insert pfcls;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Updates existing PFCL__c records.
     * @param pfcls List of PFCL__c records to update.
     */
    public static void updatePFCLs(List<PFCL__c> pfcls) {
        if (pfcls == null || pfcls.isEmpty()) {
            return;
        }
        Logger.setScenario('PFCL Management');
        try {
            PFCLs domain = new PFCLs(pfcls);
            update pfcls;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Deletes PFCL__c records by their Ids.
     * @param pfclIds Set of PFCL__c Ids to delete.
     */
    public static void deletePFCLs(Set<Id> pfclIds) {
        if (pfclIds == null || pfclIds.isEmpty()) {
            return;
        }
        Logger.setScenario('PFCL Management');
        try {
            List<PFCL__c> pfclList = PFCLsSelector.selectById(pfclIds);
            if (pfclList.isEmpty()) {
                return;
            }
            delete pfclList;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Retrieves PFCL__c records by their Ids.
     * @param pfclIds Set of PFCL__c Ids to retrieve.
     * @return List of PFCL__c records.
     */
    public static List<PFCL__c> getPFCLsById(Set<Id> pfclIds) {
        if (pfclIds == null || pfclIds.isEmpty()) {
            return new List<PFCL__c>();
        }
        return PFCLsSelector.selectById(pfclIds);
    }
}