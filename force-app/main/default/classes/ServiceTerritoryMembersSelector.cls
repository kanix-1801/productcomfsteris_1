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

    /**
     * @description GW-2707 - Memberships of the given resources in the given territories that have not ended
     *              before a point in time, newest start first. Runs in USER_MODE; record access comes from the
     *              FieldServiceBackofficeTool permission set.
     * @param resourceIds Service Resource Ids
     * @param territoryIds Service Territory Ids
     * @param endedBefore Memberships that ended before this time are excluded
     * @return Matching members (empty when an input is missing)
     */
    public static List<ServiceTerritoryMember> selectOpenByResourcesAndTerritories(
        Set<Id> resourceIds,
        Set<Id> territoryIds,
        Datetime endedBefore
    ) {
        if (
            resourceIds == null ||
            resourceIds.isEmpty() ||
            territoryIds == null ||
            territoryIds.isEmpty() ||
            endedBefore == null
        ) {
            return new List<ServiceTerritoryMember>();
        }
        return (List<ServiceTerritoryMember>) new ServiceTerritoryMembersSelector()
            .selectFields(
                new List<String>{
                    'Id',
                    'ServiceResourceId',
                    'ServiceTerritoryId',
                    'TerritoryType',
                    'OperatingHoursId',
                    'EffectiveStartDate',
                    'EffectiveEndDate'
                }
            )
            .whereIn('ServiceResourceId', new List<Id>(resourceIds))
            .whereIn('ServiceTerritoryId', new List<Id>(territoryIds))
            .whereEquals('EffectiveEndDate', null)
            .whereField('EffectiveEndDate', '>=', endedBefore)
            .withFilterLogic('1 AND 2 AND (3 OR 4)')
            .orderByDesc('EffectiveStartDate')
            .execute();
    }
}