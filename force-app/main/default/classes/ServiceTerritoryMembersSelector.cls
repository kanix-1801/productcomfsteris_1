/**
 * @author Sagar Anand
 * @date 2026-10-29
 * @description GW-6099 - Selector for ServiceTerritoryMember. Queries run in USER_MODE through
 *              SoqlQueryBuilder / DynamicSoqlQuery.
 * @group Field Service
 */
public with sharing class ServiceTerritoryMembersSelector extends SoqlQueryBuilder {
    /** @description Fields needed to decide whether a member is active on a given date. */
    private static final List<String> MEMBER_FIELDS = new List<String>{
        'Id',
        'ServiceResourceId',
        'ServiceTerritoryId',
        'TerritoryType',
        'EffectiveStartDate',
        'EffectiveEndDate'
    };

    /**
     * @description Binds this selector to ServiceTerritoryMember for SoqlQueryBuilder queries.
     */
    public ServiceTerritoryMembersSelector() {
        this.objectName = 'ServiceTerritoryMember';
    }

    /**
     * @description Selects the territory memberships of the given Service Resources with the given types.
     *              Effective dates are returned so callers can check them against their own date.
     * @param serviceResourceIdSet Service Resource Ids
     * @param territoryTypes TerritoryType values to include (e.g. 'P', 'S')
     * @return Matching members (empty when an input is missing)
     * @example
     * List<ServiceTerritoryMember> members = ServiceTerritoryMembersSelector
     *     .selectByServiceResourceIdsAndTypes(resourceIds, new List<String>{ 'P', 'S' });
     */
    public static List<ServiceTerritoryMember> selectByServiceResourceIdsAndTypes(
        Set<Id> serviceResourceIdSet,
        List<String> territoryTypes
    ) {
        List<String> serviceResourceIdList = new List<String>();
        if (serviceResourceIdSet != null) {
            for (Id serviceResourceId : serviceResourceIdSet) {
                if (serviceResourceId != null) {
                    serviceResourceIdList.add(serviceResourceId);
                }
            }
        }
        if (serviceResourceIdList.isEmpty() || territoryTypes == null || territoryTypes.isEmpty()) {
            return new List<ServiceTerritoryMember>();
        }

        return (List<ServiceTerritoryMember>) new ServiceTerritoryMembersSelector()
            .selectFields(MEMBER_FIELDS)
            .whereIn('ServiceResourceId', serviceResourceIdList)
            .whereIn('TerritoryType', territoryTypes)
            .execute();
    }
}