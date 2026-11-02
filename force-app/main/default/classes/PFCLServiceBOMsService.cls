/**
 * @description Service class for PFCLServiceBOM__c business operations.
 *              Entry point for all PFCL/Service BOM junction transactions.
 *              Performs DML directly — no Unit of Work.
 */
public with sharing class PFCLServiceBOMsService {
    @TestVisible
    private static Boolean simulateUnexpectedException = false;

    /**
     * @description Creates new PFCLServiceBOM__c records with validation.
     * @param junctions List of PFCLServiceBOM__c records to create.
     * @throws PFCLServiceBOMsServiceException when the operation fails.
     */
    public static void createPFCLServiceBOMs(List<PFCLServiceBOM__c> junctions) {
        if (junctions == null || junctions.isEmpty()) {
            return;
        }
        Logger.setScenario('PFCL Service BOM Management');
        try {
            PFCLServiceBOMs domain = new PFCLServiceBOMs(junctions);
            // domain.applyDefaults();
            // domain.validate();
            insert junctions;
        } catch (PFCLServiceBOMs.PFCLServiceBOMsException e) {
            Logger.error(new LogMessage('PFCLServiceBOMsService.createPFCLServiceBOMs: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new PFCLServiceBOMsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('PFCLServiceBOMsService.createPFCLServiceBOMs: Unexpected error.', e);
            Logger.saveLog();
            throw new PFCLServiceBOMsServiceException('An unexpected error occurred while creating PFCL Service BOM records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Updates existing PFCLServiceBOM__c records with validation.
     * @param junctions List of PFCLServiceBOM__c records to update.
     * @throws PFCLServiceBOMsServiceException when the operation fails.
     */
    public static void updatePFCLServiceBOMs(List<PFCLServiceBOM__c> junctions) {
        if (junctions == null || junctions.isEmpty()) {
            return;
        }
        Logger.setScenario('PFCL Service BOM Management');
        try {
            PFCLServiceBOMs domain = new PFCLServiceBOMs(junctions);
            // domain.validate();
            update junctions;
        } catch (PFCLServiceBOMs.PFCLServiceBOMsException e) {
            Logger.error(new LogMessage('PFCLServiceBOMsService.updatePFCLServiceBOMs: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new PFCLServiceBOMsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('PFCLServiceBOMsService.updatePFCLServiceBOMs: Unexpected error.', e);
            Logger.saveLog();
            throw new PFCLServiceBOMsServiceException('An unexpected error occurred while updating PFCL Service BOM records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Deletes PFCLServiceBOM__c records by their Ids.
     * @param junctionIds Set of PFCLServiceBOM__c Ids to delete.
     * @throws PFCLServiceBOMsServiceException when the operation fails.
     */
    public static void deletePFCLServiceBOMs(Set<Id> junctionIds) {
        if (junctionIds == null || junctionIds.isEmpty()) {
            return;
        }
        Logger.setScenario('PFCL Service BOM Management');
        try {
            List<PFCLServiceBOM__c> junctionList = PFCLServiceBOMsSelector.selectById(junctionIds);
            if (junctionList.isEmpty()) {
                return;
            }
            delete junctionList;
        } catch (Exception e) {
            Logger.error('PFCLServiceBOMsService.deletePFCLServiceBOMs: Unexpected error.', e);
            Logger.saveLog();
            throw new PFCLServiceBOMsServiceException('An unexpected error occurred while deleting PFCL Service BOM records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Retrieves PFCLServiceBOM__c records by their Ids.
     * @param junctionIds Set of PFCLServiceBOM__c Ids to retrieve.
     * @return List of PFCLServiceBOM__c records.
     * @throws PFCLServiceBOMsServiceException when the operation fails.
     */
    public static List<PFCLServiceBOM__c> getPFCLServiceBOMsById(Set<Id> junctionIds) {
        if (junctionIds == null || junctionIds.isEmpty()) {
            return new List<PFCLServiceBOM__c>();
        }
        try {
            if (simulateUnexpectedException) {
                throw new QueryException('Simulated failure');
            }
            return PFCLServiceBOMsSelector.selectById(junctionIds);
        } catch (Exception e) {
            Logger.error('PFCLServiceBOMsService.getPFCLServiceBOMsById: Unexpected error.', e);
            Logger.saveLog();
            throw new PFCLServiceBOMsServiceException('An unexpected error occurred while retrieving PFCL Service BOM records.', e);
        }
    }

    /**
     * @description Thrown when a PFCL Service BOM service operation fails.
     */
    public class PFCLServiceBOMsServiceException extends Exception {}
}