/**
 * @author Uptima
 * @date 2026-08-15
 * @group Selectors
 * @description Selector class for Schema.Location.
 *              Centralizes SOQL for Location / Rack lookups used by Repair Center flows.
 *              Used by GW-2891 (Divide Instruments) and GW-3816 (Assign Rack).
 */
public with sharing class LocationsSelector {
    private static final String LOCATION_TYPE_RACK = 'Rack';
    private static final String LOCATION_TYPE_REPAIR_CENTER = 'Repair Center';
    private static final String RACK_ASSIGN_FIELDS =
        'Id, Name, Repair_Category__c, LocationType, TrackRackAssignmentHistory__c, ' +
        'StatusAssignment__c, SubStatusAssignment__c';
    private static final String BASE_FIELDS = 'Id, Name, VisitorAddressId';

    /**
     * @description GW-5492 - Repair Center locations for Receiving redirect.
     * @return Location rows ordered by Name
     */
    public static List<Schema.Location> selectRepairCenters() {
        return (List<Schema.Location>) SoqlQueryBuilder.fromObject('Location')
            .selectFields(new List<String>{ 'Id', 'Name', 'LocationType' })
            .whereEquals('LocationType', LOCATION_TYPE_REPAIR_CENTER)
            .orderBy('Name')
            .execute();
    }

    /**
     * @description Retrieves Location records by Id.
     * @param ids Location Ids
     * @return Matching Location rows
     */
    public static List<Schema.Location> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<Schema.Location>();
        }
        return [
            SELECT Id, Name, VisitorAddressId
            FROM Location
            WHERE Id IN :ids
            WITH SECURITY_ENFORCED
        ];
    }

    /**
     * @description GW-2891 - Selects Rack locations for the given repair categories.
     *              Used by Divide Instruments when assigning a rack to Ready for Repair children.
     * @param repairCategories Repair Category picklist values
     * @return Matching Location records ordered by CreatedDate
     */
    public static List<Schema.Location> selectRacksByRepairCategories(Set<String> repairCategories) {
        if (repairCategories == null || repairCategories.isEmpty()) {
            return new List<Schema.Location>();
        }
        return [
            SELECT Id, Name, LocationType, Repair_Category__c
            FROM Location
            WHERE LocationType = 'Rack'
                AND Repair_Category__c IN :repairCategories
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
        ];
    }

    /**
     * @description GW-3816 - Selects a Rack Location by Salesforce Id or Name (barcode).
     *              Uses SYSTEM_MODE because Repair Category / Track Rack Assignment History
     *              FLS is not consistently granted to shop-floor scanner profiles.
     * @param rackInput Location Id or Name
     * @return Matching Rack Location, or null when not found / blank input
     * @example
     * Schema.Location rack = LocationsSelector.selectRackByIdOrName('RACK-01');
     */
    public static Schema.Location selectRackByIdOrName(String rackInput) {
        if (String.isBlank(rackInput)) {
            return null;
        }

        Map<String, Object> binds = new Map<String, Object>{
            'rackInput' => rackInput,
            'locationTypeRack' => LOCATION_TYPE_RACK
        };
        String soqlTemplate =
            'SELECT ' +
            RACK_ASSIGN_FIELDS +
            ' FROM Location WHERE LocationType = :locationTypeRack AND {0} LIMIT 1';

        if (PlatformUtilities.isSalesforceId(rackInput)) {
            List<Schema.Location> byIdList = Database.queryWithBinds(
                String.format(soqlTemplate, new List<String>{ 'Id = :rackInput' }),
                binds,
                AccessLevel.SYSTEM_MODE
            );
            if (!byIdList.isEmpty()) {
                return byIdList[0];
            }
        }

        List<Schema.Location> byNameList = Database.queryWithBinds(
            String.format(soqlTemplate, new List<String>{ 'Name = :rackInput' }),
            binds,
            AccessLevel.SYSTEM_MODE
        );
        return byNameList.isEmpty() ? null : byNameList[0];
    }
}