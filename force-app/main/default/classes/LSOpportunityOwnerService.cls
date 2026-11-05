/**
 * @author PWC Developer
 * @date 2026/11/04
 *
 * @group Life Sciences Opportunity
 *
 * @description
 * GCL-73 - Blocks an Opportunity Owner change for a Life Sciences Sales user
 * unless that user is the current owner, has LSBusinessSysAdminPS, or is
 * above the current owner in the role hierarchy.
 */
public with sharing class LSOpportunityOwnerService {

    public static final String SCENARIO = 'LS Opportunity Owner';
    public static final String LOGGER_TAG = 'LSOpportunityOwner';
    public static final String BUSINESS_SYSTEM_ADMIN_PERMISSION_SET = 'LSBusinessSysAdminPS';
    public static final String OWNER_CHANGE_ERROR =
        'You cannot change the Opportunity Owner. Only the current owner, a Life Sciences Business System Admin, or a user above the owner in the role hierarchy can reassign this Opportunity.';

    private static final String CLASS_NAME = 'LSOpportunityOwnerService';
    private static final String LIFE_SCIENCES_SALES_PROFILE = 'Life Sciences Sales';
    private static final Set<String> LIFE_SCIENCES_RECORD_TYPES = new Set<String>{
        'LSEquipmentService',
        'LSSalesConsumables'
    };

    @TestVisible
    private static Boolean throwTestException = false;
    @TestVisible
    private static Set<Id> lifeSciencesRecordTypeIds;

    /**
     * @description
     * GCL-73 - Validates Owner changes on Life Sciences Opportunities.
     * Called from OpportunityTriggerHandller.beforeUpdate.
     *
     * @param opportunities Trigger.new records.
     * @param oldOpportunities Trigger.oldMap records.
     * @return void
     *
     * @example
     * LSOpportunityOwnerService.validateOwnerChange(opportunities, oldOpportunities);
     */
    public static void validateOwnerChange(
        List<Opportunity> opportunities,
        Map<Id, Opportunity> oldOpportunities
    ) {
        List<Opportunity> changedOpportunities = ownerChanges(opportunities, oldOpportunities);
        if (changedOpportunities.isEmpty()) {
            return;
        }

        User runningUser = LSOpportunityOwnerSelector.selectRunningUser();
        if (runningUser == null || runningUser.Profile.Name != LIFE_SCIENCES_SALES_PROFILE) {
            return;
        }

        try {
            Logger.setScenario(SCENARIO);
            if (Test.isRunningTest() && throwTestException) {
                throw new QueryException('Forced test exception');
            }
            if (LSOpportunityOwnerSelector.hasBusinessSystemAdminPermission(runningUser.Id)) {
                Logger.info(
                    CLASS_NAME + '.validateOwnerChange: allowed for Business System Admin, opportunityCount=' + changedOpportunities.size()
                ).addTag(LOGGER_TAG);
                return;
            }
            applyOwnerRule(changedOpportunities, oldOpportunities, runningUser);
        } catch (Exception exceptionValue) {
            Logger.error(CLASS_NAME + '.validateOwnerChange', exceptionValue).addTag(LOGGER_TAG);
            throw exceptionValue;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description
     * GCL-73 - Life Sciences Opportunities whose Owner changed and whose
     * validation bypass is off.
     *
     * @param opportunities Trigger.new records.
     * @param oldOpportunities Trigger.oldMap records.
     * @return Opportunities that need an owner decision.
     *
     * @example
     * ownerChanges(opportunities, oldOpportunities);
     */
    private static List<Opportunity> ownerChanges(
        List<Opportunity> opportunities,
        Map<Id, Opportunity> oldOpportunities
    ) {
        List<Opportunity> changedOpportunities = new List<Opportunity>();
        if (opportunities == null || opportunities.isEmpty() || oldOpportunities == null) {
            return changedOpportunities;
        }

        Set<Id> recordTypeIds = lifeSciencesRecordTypeIds();
        for (Opportunity opportunity : opportunities) {
            Opportunity previousOpportunity = oldOpportunities.get(opportunity.Id);
            if (previousOpportunity == null
                || opportunity.OwnerId == previousOpportunity.OwnerId
                || opportunity.BypassValidations__c == true
                || !recordTypeIds.contains(opportunity.RecordTypeId)) {
                continue;
            }
            changedOpportunities.add(opportunity);
        }
        return changedOpportunities;
    }

    /**
     * @description
     * GCL-73 - Allows the previous owner and a parent role. Blocks every
     * other Life Sciences Sales user.
     *
     * @param changedOpportunities Opportunities with a changed Owner.
     * @param oldOpportunities Trigger.oldMap records.
     * @param runningUser Life Sciences Sales user saving the record.
     * @return void
     *
     * @example
     * applyOwnerRule(changedOpportunities, oldOpportunities, runningUser);
     */
    private static void applyOwnerRule(
        List<Opportunity> changedOpportunities,
        Map<Id, Opportunity> oldOpportunities,
        User runningUser
    ) {
        Set<Id> previousOwnerIds = new Set<Id>();
        for (Opportunity opportunity : changedOpportunities) {
            previousOwnerIds.add(oldOpportunities.get(opportunity.Id).OwnerId);
        }

        Map<Id, Id> roleIdByUserId = LSOpportunityOwnerSelector.selectRoleIdByUserId(previousOwnerIds);
        Map<Id, Id> parentRoleIdByRoleId = LSOpportunityOwnerSelector.selectParentRoleIdByRoleId();
        List<String> blockedOpportunityIds = new List<String>();
        Integer allowedCount = 0;

        for (Opportunity opportunity : changedOpportunities) {
            Id previousOwnerId = oldOpportunities.get(opportunity.Id).OwnerId;
            if (previousOwnerId == runningUser.Id
                || isAboveOwner(
                    roleIdByUserId.get(previousOwnerId),
                    runningUser.UserRoleId,
                    parentRoleIdByRoleId
                )) {
                allowedCount++;
                continue;
            }
            opportunity.OwnerId.addError(OWNER_CHANGE_ERROR);
            blockedOpportunityIds.add(String.valueOf(opportunity.Id));
        }

        Logger.info(
            CLASS_NAME + '.applyOwnerRule: allowedCount=' + allowedCount
        ).addTag(LOGGER_TAG);
        if (!blockedOpportunityIds.isEmpty()) {
            Logger.warn(
                CLASS_NAME + '.applyOwnerRule: blockedCount=' + blockedOpportunityIds.size()
                + ', opportunityIds=' + String.join(blockedOpportunityIds, ',')
            ).addTag(LOGGER_TAG);
        }
    }

    /**
     * @description
     * GCL-73 - TRUE when the running role is a parent of the owner role.
     * A user in the same role returns FALSE.
     *
     * @param ownerRoleId Role of the previous Opportunity owner.
     * @param runningUserRoleId Role of the user saving the record.
     * @param parentRoleIdByRoleId Parent role by role Id.
     * @return TRUE when the running user is above the owner.
     *
     * @example
     * isAboveOwner(ownerRoleId, runningUserRoleId, parentRoleIdByRoleId);
     */
    private static Boolean isAboveOwner(
        Id ownerRoleId,
        Id runningUserRoleId,
        Map<Id, Id> parentRoleIdByRoleId
    ) {
        if (ownerRoleId == null || runningUserRoleId == null) {
            return false;
        }
        Id currentRoleId = parentRoleIdByRoleId.get(ownerRoleId);
        Set<Id> visitedRoleIds = new Set<Id>();
        while (currentRoleId != null && visitedRoleIds.add(currentRoleId)) {
            if (currentRoleId == runningUserRoleId) {
                return true;
            }
            currentRoleId = parentRoleIdByRoleId.get(currentRoleId);
        }
        return false;
    }

    /**
     * @description
     * GCL-73 - Record type Ids for LSEquipmentService and LSSalesConsumables.
     *
     * @return Life Sciences Opportunity record type Ids.
     *
     * @example
     * lifeSciencesRecordTypeIds();
     */
    private static Set<Id> lifeSciencesRecordTypeIds() {
        if (lifeSciencesRecordTypeIds != null) {
            return lifeSciencesRecordTypeIds;
        }

        lifeSciencesRecordTypeIds = new Set<Id>();
        Map<String, Schema.RecordTypeInfo> recordTypesByName =
            Opportunity.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .getRecordTypeInfosByDeveloperName();
        for (String developerName : LIFE_SCIENCES_RECORD_TYPES) {
            Schema.RecordTypeInfo recordTypeInfo = recordTypesByName.get(developerName);
            if (recordTypeInfo == null) {
                Logger.warn(
                    CLASS_NAME + '.lifeSciencesRecordTypeIds: record type not found=' + developerName
                ).addTag(LOGGER_TAG);
                continue;
            }
            lifeSciencesRecordTypeIds.add(recordTypeInfo.getRecordTypeId());
        }
        return lifeSciencesRecordTypeIds;
    }
}