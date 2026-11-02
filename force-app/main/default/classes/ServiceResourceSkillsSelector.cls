/**
 * @author Sagar Anand
 * @date 2026-10-29
 * @description GW-6099 - Selector for ServiceResourceSkill. Queries run in USER_MODE through
 *              SoqlQueryBuilder / DynamicSoqlQuery.
 * @group Field Service
 */
public with sharing class ServiceResourceSkillsSelector extends SoqlQueryBuilder {
    /** @description Fields needed to decide whether a resource has a skill on a given date. */
    private static final List<String> SKILL_FIELDS = new List<String>{
        'Id',
        'ServiceResourceId',
        'SkillId',
        'SkillLevel',
        'EffectiveStartDate',
        'EffectiveEndDate'
    };

    /**
     * @description Binds this selector to ServiceResourceSkill for SoqlQueryBuilder queries.
     */
    public ServiceResourceSkillsSelector() {
        this.objectName = 'ServiceResourceSkill';
    }

    /**
     * @description Selects the skills of the given Service Resources. Effective dates are returned so
     *              callers can check them against their own date.
     * @param serviceResourceIdSet Service Resource Ids
     * @return Matching resource skills (empty when the input is missing)
     * @example
     * List<ServiceResourceSkill> skills = ServiceResourceSkillsSelector.selectByServiceResourceIds(resourceIds);
     */
    public static List<ServiceResourceSkill> selectByServiceResourceIds(Set<Id> serviceResourceIdSet) {
        List<String> serviceResourceIdList = new List<String>();
        if (serviceResourceIdSet != null) {
            for (Id serviceResourceId : serviceResourceIdSet) {
                if (serviceResourceId != null) {
                    serviceResourceIdList.add(serviceResourceId);
                }
            }
        }
        if (serviceResourceIdList.isEmpty()) {
            return new List<ServiceResourceSkill>();
        }

        return (List<ServiceResourceSkill>) new ServiceResourceSkillsSelector()
            .selectFields(SKILL_FIELDS)
            .whereIn('ServiceResourceId', serviceResourceIdList)
            .execute();
    }
}