/**
 * @description Service for ResiTestHistory__c (GW-5492 Receiving).
 */
public with sharing class ResiTestHistoriesService {
    private static final String DISINFECTION_STATUS_CLEAN = 'Clean';
    private static final String DISINFECTION_STATUS_CONTAMINATED = 'Contaminated';

    private static final List<String> BASE_FIELDS = new List<String>{
        'Id',
        'WorkOrder__c',
        'WorkOrderLineItem__c',
        'TestCompletionDate__c',
        'DisinfectionStatus__c'
    };

    /**
     * @description Loads Resi-Test History rows by Id.
     * @param ids Record Ids
     * @return Matching rows
     */
    public static List<ResiTestHistory__c> getById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<ResiTestHistory__c>();
        }
        return (List<ResiTestHistory__c>) new ResiTestHistoriesSelector()
            .selectFields(BASE_FIELDS)
            .whereIn('Id', new List<Id>(ids))
            .execute();
    }

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
            throw new ResiTestHistoriesServiceException(
                'Unable to create Resi-Test History: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    private static String mapDisinfectionStatus(String uiValue) {
        if (uiValue == DISINFECTION_STATUS_CONTAMINATED) {
            return DISINFECTION_STATUS_CONTAMINATED;
        }
        if (uiValue == DISINFECTION_STATUS_CLEAN) {
            return DISINFECTION_STATUS_CLEAN;
        }
        return uiValue;
    }

    /**
     * @description Thrown when Resi-Test History operations fail.
     */
    public class ResiTestHistoriesServiceException extends Exception {
    }
}