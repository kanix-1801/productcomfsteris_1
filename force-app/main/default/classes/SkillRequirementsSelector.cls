/**
 * @author Sagar Anand
 * @date 2026-10-29
 * @description GW-6099 - Selector for SkillRequirement. Queries run in USER_MODE through
 *              SoqlQueryBuilder / DynamicSoqlQuery.
 * @group Field Service
 */
public with sharing class SkillRequirementsSelector extends SoqlQueryBuilder {
    /** @description Fields needed to compare required skills with a resource's skills. */
    private static final List<String> REQUIREMENT_FIELDS = new List<String>{
        'Id',
        'RelatedRecordId',
        'SkillId',
        'SkillLevel',
        'IsAdditionalSkill'
    };

    /**
     * @description Binds this selector to SkillRequirement for SoqlQueryBuilder queries.
     */
    public SkillRequirementsSelector() {
        this.objectName = 'SkillRequirement';
    }

    /**
     * @description Selects the skill requirements of the given records (e.g. Work Orders or Work Types).
     * @param relatedRecordIdSet Ids of the records the requirements belong to
     * @return Matching skill requirements (empty when the input is missing)
     * @example
     * List<SkillRequirement> requirements = SkillRequirementsSelector.selectByRelatedRecordIds(workOrderIds);
     */
    public static List<SkillRequirement> selectByRelatedRecordIds(Set<Id> relatedRecordIdSet) {
        List<String> relatedRecordIdList = new List<String>();
        if (relatedRecordIdSet != null) {
            for (Id relatedRecordId : relatedRecordIdSet) {
                if (relatedRecordId != null) {
                    relatedRecordIdList.add(relatedRecordId);
                }
            }
        }
        if (relatedRecordIdList.isEmpty()) {
            return new List<SkillRequirement>();
        }

        return (List<SkillRequirement>) new SkillRequirementsSelector()
            .selectFields(REQUIREMENT_FIELDS)
            .whereIn('RelatedRecordId', relatedRecordIdList)
            .execute();
    }
}