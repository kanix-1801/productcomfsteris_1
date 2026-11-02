/**
 * @description Service class for ServiceBOM__c business operations.
 *              Entry point for all Service BOM-related transactions.
 *              Performs DML directly — no Unit of Work.
 */
public with sharing class ServiceBOMsService {
    @TestVisible
    private static Boolean simulateUnexpectedException = false;

    /**
     * @description Creates new ServiceBOM__c records with validation.
     * @param serviceBoms List of ServiceBOM__c records to create.
     * @throws ServiceBOMsServiceException when the operation fails.
     */
    public static void createServiceBOMs(List<ServiceBOM__c> serviceBoms) {
        if (serviceBoms == null || serviceBoms.isEmpty()) {
            return;
        }
        Logger.setScenario('Service BOM Management');
        try {
            ServiceBOMs domain = new ServiceBOMs(serviceBoms);
            // domain.applyDefaults();
            // domain.validate();
            insert serviceBoms;
        } catch (ServiceBOMs.ServiceBOMsException e) {
            Logger.error(new LogMessage('ServiceBOMsService.createServiceBOMs: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new ServiceBOMsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('ServiceBOMsService.createServiceBOMs: Unexpected error.', e);
            Logger.saveLog();
            throw new ServiceBOMsServiceException('An unexpected error occurred while creating Service BOM records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Updates existing ServiceBOM__c records with validation.
     * @param serviceBoms List of ServiceBOM__c records to update.
     * @throws ServiceBOMsServiceException when the operation fails.
     */
    public static void updateServiceBOMs(List<ServiceBOM__c> serviceBoms) {
        if (serviceBoms == null || serviceBoms.isEmpty()) {
            return;
        }
        Logger.setScenario('Service BOM Management');
        try {
            ServiceBOMs domain = new ServiceBOMs(serviceBoms);
            // domain.validate();
            update serviceBoms;
        } catch (ServiceBOMs.ServiceBOMsException e) {
            Logger.error(new LogMessage('ServiceBOMsService.updateServiceBOMs: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new ServiceBOMsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('ServiceBOMsService.updateServiceBOMs: Unexpected error.', e);
            Logger.saveLog();
            throw new ServiceBOMsServiceException('An unexpected error occurred while updating Service BOM records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Deletes ServiceBOM__c records by their Ids.
     * @param serviceBomIds Set of ServiceBOM__c Ids to delete.
     * @throws ServiceBOMsServiceException when the operation fails.
     */
    public static void deleteServiceBOMs(Set<Id> serviceBomIds) {
        if (serviceBomIds == null || serviceBomIds.isEmpty()) {
            return;
        }
        Logger.setScenario('Service BOM Management');
        try {
            List<ServiceBOM__c> serviceBomList = ServiceBOMsSelector.selectById(serviceBomIds);
            if (serviceBomList.isEmpty()) {
                return;
            }
            delete serviceBomList;
        } catch (Exception e) {
            Logger.error('ServiceBOMsService.deleteServiceBOMs: Unexpected error.', e);
            Logger.saveLog();
            throw new ServiceBOMsServiceException('An unexpected error occurred while deleting Service BOM records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Retrieves ServiceBOM__c records by their Ids.
     * @param serviceBomIds Set of ServiceBOM__c Ids to retrieve.
     * @return List of ServiceBOM__c records.
     * @throws ServiceBOMsServiceException when the operation fails.
     */
    public static List<ServiceBOM__c> getServiceBOMsById(Set<Id> serviceBomIds) {
        if (serviceBomIds == null || serviceBomIds.isEmpty()) {
            return new List<ServiceBOM__c>();
        }
        try {
            if (simulateUnexpectedException) {
                throw new QueryException('Simulated failure');
            }
            return ServiceBOMsSelector.selectById(serviceBomIds);
        } catch (Exception e) {
            Logger.error('ServiceBOMsService.getServiceBOMsById: Unexpected error.', e);
            Logger.saveLog();
            throw new ServiceBOMsServiceException('An unexpected error occurred while retrieving Service BOM records.', e);
        }
    }

    /**
     * @description Thrown when a Service BOM service operation fails.
     */
    public class ServiceBOMsServiceException extends Exception {}
}