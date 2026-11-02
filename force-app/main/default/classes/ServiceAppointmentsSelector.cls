/**
 * @author Sagar Anand
 * @date 2026-10-29
 * @description GW-6099 - Selector for ServiceAppointment. Queries run in USER_MODE through
 *              SoqlQueryBuilder / DynamicSoqlQuery.
 * @group Field Service
 * @see ServiceAppointmentRealignmentBatch
 */
public with sharing class ServiceAppointmentsSelector extends SoqlQueryBuilder {
    /** @description Fields needed to evaluate and update the realignment fields. */
    private static final List<String> REALIGNMENT_FIELDS = new List<String>{
        'Id',
        'AppointmentNumber',
        'Status',
        'SchedStartTime',
        'ServiceTerritoryId',
        'FSSK__FSK_Assigned_Service_Resource__c',
        'FSSK__FSK_Work_Order__c',
        'FSSK__FSK_Work_Order__r.ShipToAddressAccount__c',
        'RealignmentConflict__c',
        'RealignmentConflictCategory__c',
        'RealignmentConflictAction__c'
    };

    /**
     * @description Binds this selector to ServiceAppointment for SoqlQueryBuilder queries.
     */
    public ServiceAppointmentsSelector() {
        this.objectName = 'ServiceAppointment';
    }

    /**
     * @description GW-6099 - Query locator over the Service Appointments of the given Service Territories
     *              that start on or after the given time and have one of the given statuses.
     * @param serviceTerritoryIdSet Service Territory Ids (exact territories, no children)
     * @param fromDateTime Earliest SchedStartTime to include
     * @param statuses Status values to include
     * @return Query locator in USER_MODE; matches nothing when an input is missing
     * @example
     * Database.QueryLocator locator = ServiceAppointmentsSelector.selectForRealignmentQueryLocator(
     *     territoryIds, Datetime.now(), ServiceAppointmentRealignmentConstants.ELIGIBLE_STATUSES);
     */
    public static Database.QueryLocator selectForRealignmentQueryLocator(
        Set<Id> serviceTerritoryIdSet,
        Datetime fromDateTime,
        List<String> statuses
    ) {
        List<String> serviceTerritoryIdList = toStringList(serviceTerritoryIdSet);
        if (serviceTerritoryIdList.isEmpty() || fromDateTime == null || statuses == null || statuses.isEmpty()) {
            return Database.getQueryLocator([SELECT Id FROM ServiceAppointment WHERE Id = NULL WITH USER_MODE]);
        }

        DynamicSoqlQuery.PreparedQuery query = new ServiceAppointmentsSelector()
            .selectFields(REALIGNMENT_FIELDS)
            .whereIn('ServiceTerritoryId', serviceTerritoryIdList)
            .whereField('SchedStartTime', '>=', fromDateTime)
            .whereIn('Status', statuses)
            .build();
        return Database.getQueryLocatorWithBinds(query.soql, query.binds, AccessLevel.USER_MODE);
    }

    private static List<String> toStringList(Set<Id> idSet) {
        List<String> idList = new List<String>();
        if (idSet != null) {
            for (Id recordId : idSet) {
                if (recordId != null) {
                    idList.add(recordId);
                }
            }
        }
        return idList;
    }
}