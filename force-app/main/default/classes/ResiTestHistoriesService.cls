/**
 * @description Service for ResiTestHistory__c (GW-5492 Receiving).
 */
public with sharing class ResiTestHistoriesService {
    /**
     * @description Creates a Resi-Test History row for Finish Receiving.
     * @param workOrderId Child Work Order Id
     * @param workOrderLineItemId Product Serviced WOLI Id (optional)
     * @param disinfectedUiValue Clean / Contaminated UI value
     * @return Created record Id
     */
    public static Id createForReceiving(
        Id workOrderId,
        Id workOrderLineItemId,
        String disinfectedUiValue
    ) {
        if (workOrderId == null) {
            throw new ResiTestHistoriesServiceException('Work Order is required.');
        }
        ResiTestHistory__c history = new ResiTestHistory__c();
        history.WorkOrder__c = workOrderId;
        history.WorkOrderLineItem__c = workOrderLineItemId;
        history.TestCompletionDate__c = System.now();
        history.DisinfectionStatus__c = mapDisinfectionStatus(disinfectedUiValue);
        try {
            Database.insert(history, AccessLevel.USER_MODE);
            return history.Id;
        } catch (Exception e) {
            Logger.error('ResiTestHistoriesService.createForReceiving: Unexpected error.', e);
            Logger.saveLog();
            throw new ResiTestHistoriesServiceException(
                'Unable to create Resi-Test History: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    private static String mapDisinfectionStatus(String uiValue) {
        if ('Contaminated'.equalsIgnoreCase(uiValue)) {
            return 'Contaminated';
        }
        if ('Clean'.equalsIgnoreCase(uiValue)) {
            return 'Clean';
        }
        return uiValue;
    }

    /**
     * @description Thrown when Resi-Test History operations fail.
     */
    public class ResiTestHistoriesServiceException extends Exception {
    }
}