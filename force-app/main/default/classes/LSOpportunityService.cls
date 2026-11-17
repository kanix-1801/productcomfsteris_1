/**
 * @description Life Sciences Opportunity service.
 *              GCL-73: owner change is limited to the current owner, a Life Sciences
 *              Business System Admin, or a user above the owner in the role hierarchy.
 *              GCL-23: a standard clone stamps Cloned From and clears the Sales Connection quote link.
 *              Naming stays in LSOpportunityNamingService. Primary contact stays in LSPrimaryContactService.
 */
public with sharing class LSOpportunityService {

    private static final String CLASS_NAME = 'LSOpportunityService';

    public static final String BUSINESS_SYSTEM_ADMIN_PERMISSION_SET = 'LSBusinessSysAdminPS';
    public static final String OWNER_CHANGE_ERROR =
        'You cannot transfer this Opportunity. Only the current owner, a Life Sciences Business System Admin, or a user above the owner in the role hierarchy can transfer it.';

    private static final String OWNER_CHANGE_SCENARIO = 'LS Opportunity Owner';
    private static final String OWNER_CHANGE_LOGGER_TAG = 'LSOpportunityOwner';
    private static final String LIFE_SCIENCES_SALES_PROFILE = 'Life Sciences Sales';
    private static final Set<String> LIFE_SCIENCES_RECORD_TYPES = new Set<String>{
        'LSEquipmentService',
        'LSSalesConsumables'
    };

    @TestVisible
    private static Boolean throwOwnerChangeTestException = false;
    @TestVisible
    private static Boolean treatAsCloneForTest = false;
    @TestVisible
    private static Set<Id> lifeSciencesRecordTypeIds;

    /**
     * @description
     * GCL-23 - Stamps Cloned From on a Life Sciences Opportunity created with the standard Clone action.
     *          Clears the Sales Connection quote link so the clone does not carry it over.
     *          Normal creates and clones of other record types are not changed.
     *          Runs in before insert only. No SOQL or DML.
     *
     * @param opportunities Opportunity records from Trigger.new during before insert.
     *
     * @example
     * LSOpportunityService.stampClonedFrom(opportunities);
     */
    public static void stampClonedFrom(List<Opportunity> opportunities) {
        if (opportunities == null || opportunities.isEmpty()) {
            return;
        }

        Set<Id> recordTypeIds = lifeSciencesRecordTypeIds();
        for (Opportunity opportunity : opportunities) {
            if (opportunity == null
                || !isStandardClone(opportunity)
                || !recordTypeIds.contains(opportunity.RecordTypeId)) {
                continue;
            }
            opportunity.ClonedFrom__c = opportunity.getCloneSourceId();
            opportunity.BypassValidations__c = false;
            opportunity.QuoteLinkageToSalesConnection__c = null;
        }
    }

    /**
     * @description
     * GCL-23 - The standard Clone button sets isClone. Apex tests cannot
     * create that state, so the test flag covers the stamp lines.
     * A real save still uses Opportunity.isClone only.
     */
    private static Boolean isStandardClone(Opportunity opportunity) {
        return treatAsCloneForTest || opportunity.isClone();
    }

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
     * LSOpportunityService.validateOwnerChange(opportunities, oldOpportunities);
     */
    public static void validateOwnerChange(
        List<Opportunity> opportunities,
        Map<Id, Opportunity> oldOpportunities
    ) {
        if (isOwnerCheckDisabled()) {
            return;
        }

        List<Opportunity> changedOpportunities = ownerChanges(opportunities, oldOpportunities);
        if (changedOpportunities.isEmpty()) {
            return;
        }

        User runningUser = OpportunitySelector.selectRunningUser();
        String profileName = OpportunitySelector.selectProfileName(UserInfo.getProfileId());
        if (runningUser == null || profileName != LIFE_SCIENCES_SALES_PROFILE) {
            return;
        }

        try {
            Logger.setScenario(OWNER_CHANGE_SCENARIO);
            if (Test.isRunningTest() && throwOwnerChangeTestException) {
                throw new QueryException('Forced test exception');
            }
            if (OpportunitySelector.hasBusinessSystemAdminPermission(runningUser.Id)) {
                Logger.info(
                    CLASS_NAME + '.validateOwnerChange: allowed for Business System Admin, opportunityCount='
                    + changedOpportunities.size()
                ).addTag(OWNER_CHANGE_LOGGER_TAG);
                return;
            }
            applyOwnerRule(changedOpportunities, oldOpportunities, runningUser);
        } catch (Exception exceptionValue) {
            Logger.error(CLASS_NAME + '.validateOwnerChange', exceptionValue).addTag(OWNER_CHANGE_LOGGER_TAG);
            throw exceptionValue;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description
     * GCL-73 - Org-wide and rule-level switches used by the other Life Sciences
     * Opportunity validations. A checked flag skips this owner check.
     *
     * @return TRUE when the owner check must not run.
     *
     * @example
     * isOwnerCheckDisabled();
     */
    private static Boolean isOwnerCheckDisabled() {
        Automation_Setting_Global__c globalSetting = Automation_Setting_Global__c.getInstance();
        Automation_Setting_Validation_Rule__c validationSetting =
            Automation_Setting_Validation_Rule__c.getInstance();
        return (globalSetting != null && globalSetting.disableAll__c)
            || (validationSetting != null
                && (validationSetting.disableAll__c
                    || validationSetting.LS_Opp_073_RestrictOwnerChange__c));
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

        Map<Id, Id> roleIdByUserId = OpportunitySelector.selectRoleIdByUserId(previousOwnerIds);
        Map<Id, Id> parentRoleIdByRoleId = OpportunitySelector.selectParentRoleIdByRoleId();
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
        ).addTag(OWNER_CHANGE_LOGGER_TAG);
        if (!blockedOpportunityIds.isEmpty()) {
            Logger.warn(
                CLASS_NAME
                + '.applyOwnerRule: blockedCount=' + blockedOpportunityIds.size()
                + ', opportunityIds=' + String.join(blockedOpportunityIds, ',')
            ).addTag(OWNER_CHANGE_LOGGER_TAG);
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
                ).addTag(OWNER_CHANGE_LOGGER_TAG);
                continue;
            }
            lifeSciencesRecordTypeIds.add(recordTypeInfo.getRecordTypeId());
        }
        return lifeSciencesRecordTypeIds;
    }
}