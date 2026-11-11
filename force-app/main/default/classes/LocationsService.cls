/**
 * @author Uptima Development Team
 * @date 2026-09-03
 * @group Services
 * @description Service-layer Location / Rack lookups. New queries are built here via
 *              LocationsSelector; legacy selector static methods remain for QACBM parity.
 */
public with sharing class LocationsService {
    private static final String LOCATION_TYPE_REPAIR_CENTER = 'Repair Center';

    /**
     * @description Loads a Location by Id.
     * @param locationId Location Id
     * @return Location row, or null when not found
     */
    public static Schema.Location getLocationById(Id locationId) {
        if (locationId == null) {
            return null;
        }
        List<Schema.Location> locations = LocationsSelector.selectById(new Set<Id>{ locationId });
        return locations.isEmpty() ? null : locations[0];
    }

    /**
     * @description GW-3816 - Resolves a Rack Location by Id or barcode Name.
     * @param rackInput Location Id or Name
     * @return Matching Rack Location, or null
     */
    public static Schema.Location getRackByIdOrName(String rackInput) {
        return LocationsSelector.selectRackByIdOrName(rackInput);
    }

    /**
     * @description GW-2891 - Lists Rack locations for repair categories.
     * @param repairCategories Repair Category values
     * @return Matching Rack Location records
     */
    public static List<Schema.Location> getRacksByRepairCategories(Set<String> repairCategories) {
        return LocationsSelector.selectRacksByRepairCategories(repairCategories);
    }

    /**
     * @description GW-5231 - Loads Locations by Id for Service Team candidate details.
     * @param locationIds Location Ids
     * @return Matching Location rows
     */
    public static List<Schema.Location> getLocationsById(Set<Id> locationIds) {
        return LocationsSelector.selectById(locationIds);
    }

    /**
     * @description GW-5492 - Repair Center locations for Receiving redirect.
     * @return Location rows ordered by Name
     */
    public static List<Schema.Location> getRepairCenters() {
        return (List<Schema.Location>) new LocationsSelector()
            .selectFields(new List<String>{ 'Id', 'Name', 'LocationType' })
            .whereEquals('LocationType', LOCATION_TYPE_REPAIR_CENTER)
            .orderBy('Name')
            .execute();
    }
}