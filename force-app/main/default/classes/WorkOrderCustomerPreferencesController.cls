/**
 * @description Aura entry point for the Work Order Customer Preferences LWC (GW-2860).
 *              Controllers call CustomerPreferencesService (not the Selector) per STERIS layering.
 * @author Uptima
 * @date 2026-07-16
 */
public with sharing class WorkOrderCustomerPreferencesController {
    @TestVisible
    private interface ICustomerPreferencesWorkOrdersClient {
        List<WorkOrder> getWorkOrdersForCustomerPreferences(Set<Id> workOrderIds);
    }

    private class DefaultCustomerPreferencesWorkOrdersClient
        implements ICustomerPreferencesWorkOrdersClient {
        public List<WorkOrder> getWorkOrdersForCustomerPreferences(Set<Id> workOrderIds) {
            return WorkOrdersService.getWorkOrdersForCustomerPreferences(workOrderIds);
        }
    }

    @TestVisible
    private static ICustomerPreferencesWorkOrdersClient facadeOverride;

    private static ICustomerPreferencesWorkOrdersClient workOrdersClient() {
        return facadeOverride == null
            ? new DefaultCustomerPreferencesWorkOrdersClient()
            : facadeOverride;
    }

    /**
     * @description Row DTO for the shared customerPreferencesTable LWC.
     */
    public class PreferenceRow {
        @AuraEnabled public Id preferenceId;
        @AuraEnabled public String name;
        @AuraEnabled public String preferenceType;
        @AuraEnabled public String productLine;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
    }

    /**
     * @description Payload for the Work Order record-page LWC.
     */
    public class PreferenceListResult {
        /** False when the Work Order cannot be loaded — LWC should render nothing. */
        @AuraEnabled public Boolean isVisible;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public List<PreferenceRow> preferences;
    }

    /**
     * @description GW-2860 - Loads active IMS Customer Preferences for a Work Order (parent or child).
     *              When the WO has no Asset / Product Line, returns preferences where ProductLine__c is blank.
     *              Otherwise returns blank Product Line preferences plus those matching the Asset Product Line.
     *              Work Order context is loaded via WorkOrdersService (not direct SOQL).
     * @param workOrderId Work Order Id from the record page
     * @return PreferenceListResult with visibility flag and preference rows
     */
    @AuraEnabled(cacheable=true)
    public static PreferenceListResult getPreferencesForWorkOrder(Id workOrderId) {
        PreferenceListResult result = new PreferenceListResult();
        result.isVisible = false;
        result.preferences = new List<PreferenceRow>();

        try {
            if (workOrderId == null) {
                return result;
            }

            List<WorkOrder> workOrders = workOrdersClient().getWorkOrdersForCustomerPreferences(
                new Set<Id>{ workOrderId }
            );
            if (workOrders.isEmpty()) {
                return result;
            }

            WorkOrder workOrder = workOrders[0];
            result.workOrderNumber = workOrder.WorkOrderNumber;
            result.isVisible = true;
            if (workOrder.AccountId == null) {
                return result;
            }

            String productLine = resolveProductLine(workOrder);
            List<CustomerPreference__c> preferences =
                CustomerPreferencesService.getActiveImsPreferences(workOrder.AccountId, productLine);
            result.preferences = mapPreferenceRows(preferences);
            return result;
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'WorkOrderCustomerPreferencesController.getPreferencesForWorkOrder failed for {0}: {1}',
                    workOrderId,
                    e.getMessage()
                ),
                e
            );
            try {
                Logger.saveLog(Logger.SaveMethod.SYNCHRONOUS_DML);
            } catch (Exception saveEx) {
                Logger.saveLog();
            }
            AuraHandledException auraEx = new AuraHandledException(
                'Unable to load Customer Preferences: ' + e.getMessage()
            );
            auraEx.setMessage('Unable to load Customer Preferences: ' + e.getMessage());
            throw auraEx;
        }
    }

    private static String resolveProductLine(WorkOrder workOrder) {
        if (workOrder.Asset == null) {
            return null;
        }
        if (String.isNotBlank(workOrder.Asset.ProductLineCalculated__c)) {
            return workOrder.Asset.ProductLineCalculated__c;
        }
        if (
            workOrder.Asset.Product2 != null &&
            String.isNotBlank(workOrder.Asset.Product2.ProductLine__c)
        ) {
            return workOrder.Asset.Product2.ProductLine__c;
        }
        return null;
    }

    private static List<PreferenceRow> mapPreferenceRows(List<CustomerPreference__c> preferences) {
        List<PreferenceRow> rows = new List<PreferenceRow>();
        if (preferences == null || preferences.isEmpty()) {
            return rows;
        }
        for (CustomerPreference__c preference : preferences) {
            PreferenceRow row = new PreferenceRow();
            row.preferenceId = preference.Id;
            row.name = preference.Name;
            row.preferenceType = preference.PreferenceType__c;
            row.productLine = preference.ProductLine__c;
            row.startDate = preference.StartDate__c;
            row.endDate = preference.EndDate__c;
            rows.add(row);
        }
        return rows;
    }
}