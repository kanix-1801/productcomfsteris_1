/**
 * @description GW-2494: Verifies a Service Resource has Work Type Skill Requirements for ES debrief Time lines.
 * @group Work Order Debrief
 * @see woDebriefES
 */
public with sharing class WoDebriefSkillCheckController {
    /**
     * @description Result of comparing Work Type Skill Requirements to Service Resource Skills.
     */
    public class SkillCheckResult {
        /** @description True when no check is needed or the resource has every required skill. */
        @AuraEnabled public Boolean hasRequiredSkills;
        /** @description True when the selected Work Type differs from the Work Order Work Type. */
        @AuraEnabled public Boolean checkRequired;
        /** @description Labels of required skills the resource does not currently hold. */
        @AuraEnabled public List<String> missingSkillNames;
        /** @description Service Resource name used in the check. */
        @AuraEnabled public String serviceResourceName;
    }

    /** @description Test-only Skill Requirements used when Skill DML is not permitted. */
    @TestVisible
    private static List<SkillRequirement> testSkillRequirements;
    /** @description Test-only Skill Ids currently held by the Service Resource. */
    @TestVisible
    private static Set<Id> testResourceSkillIds;
    /** @description Test-only Skill labels keyed by Skill Id. */
    @TestVisible
    private static Map<Id, String> testSkillNames;

    /**
     * @description Latest active Service Resource assigned to a Work Order Service Appointment.
     * @param workOrderId Work Order Id
     * @return Service Resource Id, or null when none is assigned
     */
    @AuraEnabled
    public static Id getAssignedServiceResourceId(Id workOrderId) {
        if (workOrderId == null) {
            return null;
        }
        return new SkillAccess().selectAssignedResourceId(workOrderId);
    }

    /**
     * @description Active Service Resource for the running user (mobile-safe; does not use GraphQL).
     * @return Service Resource Id, or null
     */
    @AuraEnabled
    public static Id getCurrentUserServiceResourceId() {
        return new SkillAccess().selectCurrentUserResourceId();
    }

    /**
     * @description Checks Service Resource Skills against Skill Requirements on the selected Work Type.
     *              Runs only when workTypeId differs from the Work Order Work Type.
     * @param workTypeId Selected Time-line Work Type Id
     * @param serviceResourceId Selected Service Resource Id
     * @param workOrderWorkTypeId Work Order header Work Type Id
     * @param cacheBust Client timestamp so Field Service does not reuse a stale response
     * @return Skill check result
     */
    @AuraEnabled
    public static SkillCheckResult checkServiceResourceSkills(
        Id workTypeId,
        Id serviceResourceId,
        Id workOrderWorkTypeId,
        Long cacheBust
    ) {
        SkillCheckResult result = new SkillCheckResult();
        result.hasRequiredSkills = true;
        result.checkRequired = false;
        result.missingSkillNames = new List<String>();

        if (workTypeId == null || workTypeId == workOrderWorkTypeId) {
            return result;
        }

        result.checkRequired = true;
        if (serviceResourceId == null) {
            return result;
        }
        result.serviceResourceName = new SkillAccess().selectResourceName(serviceResourceId);

        List<SkillRequirement> requirements = querySkillRequirements(workTypeId);
        if (requirements.isEmpty()) {
            return result;
        }

        Set<Id> requiredSkillIds = new Set<Id>();
        Map<Id, String> skillNameById = new Map<Id, String>();
        for (SkillRequirement requirement : requirements) {
            if (requirement.SkillId == null) {
                continue;
            }
            requiredSkillIds.add(requirement.SkillId);
            String injectedName = testSkillNames != null ? testSkillNames.get(requirement.SkillId) : null;
            String skillName = !String.isBlank(injectedName)
                ? injectedName
                : requirement.Skill?.MasterLabel;
            skillNameById.put(requirement.SkillId, skillName);
        }
        if (requiredSkillIds.isEmpty()) {
            return result;
        }

        Set<Id> resourceSkillIds = queryCurrentResourceSkillIds(serviceResourceId, requiredSkillIds);
        for (Id skillId : requiredSkillIds) {
            if (!resourceSkillIds.contains(skillId)) {
                String skillName = skillNameById.get(skillId);
                result.missingSkillNames.add(String.isBlank(skillName) ? String.valueOf(skillId) : skillName);
            }
        }
        result.hasRequiredSkills = result.missingSkillNames.isEmpty();
        return result;
    }

    /**
     * @description Loads required Skill Requirements for the Work Type, or test doubles when injected.
     * @param workTypeId Selected Work Type Id
     * @return Skill Requirements
     */
    private static List<SkillRequirement> querySkillRequirements(Id workTypeId) {
        if (Test.isRunningTest() && testSkillRequirements != null) {
            return testSkillRequirements;
        }
        return new SkillAccess().selectRequiredSkills(workTypeId);
    }

    /**
     * @description Loads current Service Resource Skill Ids, or test doubles when injected.
     * @param serviceResourceId Selected Service Resource Id
     * @param requiredSkillIds Skill Ids required by the Work Type
     * @return Skill Ids the resource currently holds
     */
    private static Set<Id> queryCurrentResourceSkillIds(Id serviceResourceId, Set<Id> requiredSkillIds) {
        if (Test.isRunningTest() && testResourceSkillIds != null) {
            return testResourceSkillIds;
        }
        return new SkillAccess().selectCurrentResourceSkillIds(serviceResourceId, requiredSkillIds);
    }

    /**
     * @description Reads Skill Requirement and Service Resource Skill without user sharing.
     *              Field Service techs can select the resource in debrief, but USER_MODE / sharing
     *              often hides ServiceResourceSkill rows after a briefcase sync.
     */
    private without sharing class SkillAccess {
        /**
         * @description Required (non-additional) Skill Requirements on the Work Type.
         * @param workTypeId Selected Work Type Id
         * @return Skill Requirements
         */
        private List<SkillRequirement> selectRequiredSkills(Id workTypeId) {
            return [
                SELECT SkillId, Skill.MasterLabel
                FROM SkillRequirement
                WHERE RelatedRecordId = :workTypeId
                    AND IsAdditionalSkill = FALSE
            ];
        }

        /**
         * @description Service Resource display name.
         * @param serviceResourceId Selected Service Resource Id
         * @return Name, or null when not found
         */
        /**
         * @description Latest Service Resource assigned on a Work Order appointment.
         * @param workOrderId Work Order Id
         * @return Service Resource Id, or null
         */
        /**
         * @description Active Service Resource for the running user.
         * @return Service Resource Id, or null
         */
        private Id selectCurrentUserResourceId() {
            List<ServiceResource> resources = [
                SELECT Id
                FROM ServiceResource
                WHERE RelatedRecordId = :UserInfo.getUserId()
                    AND IsActive = TRUE
                LIMIT 1
            ];
            return resources.isEmpty() ? null : resources[0].Id;
        }

        private Id selectAssignedResourceId(Id workOrderId) {
            List<AssignedResource> assignments = [
                SELECT ServiceResourceId
                FROM AssignedResource
                WHERE ServiceAppointment.ParentRecordId = :workOrderId
                    AND ServiceResourceId != NULL
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            return assignments.isEmpty() ? null : assignments[0].ServiceResourceId;
        }

        private String selectResourceName(Id serviceResourceId) {
            List<ServiceResource> resources = [
                SELECT Name
                FROM ServiceResource
                WHERE Id = :serviceResourceId
                LIMIT 1
            ];
            return resources.isEmpty() ? null : resources[0].Name;
        }

        /**
         * @description Skill Ids the Service Resource currently holds.
         * @param serviceResourceId Selected Service Resource Id
         * @param requiredSkillIds Skill Ids required by the Work Type
         * @return Current Skill Ids
         */
        private Set<Id> selectCurrentResourceSkillIds(Id serviceResourceId, Set<Id> requiredSkillIds) {
            DateTime now = DateTime.now();
            Set<Id> resourceSkillIds = new Set<Id>();
            if (serviceResourceId == null || requiredSkillIds == null || requiredSkillIds.isEmpty()) {
                return resourceSkillIds;
            }
            for (ServiceResourceSkill resourceSkill : [
                SELECT SkillId
                FROM ServiceResourceSkill
                WHERE ServiceResourceId = :serviceResourceId
                    AND SkillId IN :requiredSkillIds
                    AND EffectiveStartDate <= :now
                    AND (EffectiveEndDate = NULL OR EffectiveEndDate >= :now)
            ]) {
                resourceSkillIds.add(resourceSkill.SkillId);
            }
            return resourceSkillIds;
        }
    }
}