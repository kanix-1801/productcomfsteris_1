/**
 * @author PWC Developer
 * @date 2026-11-25
 * @group Life Sciences
 * @description GCL-74 - Detects Life Sciences users who were deactivated and enqueues the Life Sciences
 *              team cleanup. Runs after, and independently of, the Healthcare UserService so a failure
 *              here can never block the Healthcare path.
 *
 *              Ordinary User updates do no work here: the profile lookup and the log are only used
 *              when a user was actually deactivated.
 */
public with sharing class LSUserService {

    private static final String SCENARIO = 'GCL-74 LS Inactive User Cleanup';
    private static final String LOG_TAG = 'GCL-74';
    private static final String CONFIG_DEVELOPER_NAME = 'LS_Inactive_User_Assignment_Types';
    private static final String DEFAULT_ASSIGNMENT_TYPES = 'Oracle Assigned,Salesforce Assigned,Temporary Assignment';

    /**
     * @description Users already queued in this transaction. Stops a re-fired update from queueing twice.
     */
    private static Set<Id> processedUserIdSet = new Set<Id>();

    /**
     * @description Enqueues the Life Sciences cleanup for users who went from active to inactive.
     * @param newUserList Trigger.new
     * @param oldUserMap Trigger.oldMap
     * @example
     * LSUserService.processInactiveLifeSciencesUsers(Trigger.new, Trigger.oldMap);
     */
    public static void processInactiveLifeSciencesUsers(List<User> newUserList, Map<Id, User> oldUserMap) {
        List<User> deactivatedUserList = getDeactivatedUsers(newUserList, oldUserMap);
        if (deactivatedUserList.isEmpty()) {
            return;
        }
        Boolean hasLoggedError = false;
        try {
            if (isAutomationBypassed()) {
                return;
            }
            Map<Id, Date> inactiveDateByUserIdMap = getLifeSciencesUsers(deactivatedUserList, oldUserMap);
            if (inactiveDateByUserIdMap.isEmpty()) {
                return;
            }
            processedUserIdSet.addAll(inactiveDateByUserIdMap.keySet());
            System.enqueueJob(new LSInactiveUserCleanupQueueable(inactiveDateByUserIdMap, getAssignmentTypeSet()));
        } catch (Exception lsError) {
            // Broad on purpose: any failure here is logged and swallowed so Healthcare deactivation still works.
            hasLoggedError = true;
            Logger.setScenario(SCENARIO);
            Logger.error('LSUserService could not enqueue the LS inactive user cleanup.', lsError)
                .addTag(LOG_TAG);
        } finally {
            if (hasLoggedError) {
                Logger.saveLog();
            }
        }
    }

    /**
     * @description GCL-74 - Automation bypass per Standards Section 8.1. The LS cleanup is skipped when the
     *              global Disable All checkbox is set, or when this automation's own bypass checkbox is set
     *              on the Automation Setting Trigger record for the running user.
     * @return TRUE when the LS cleanup must not run.
     * @example
     * isAutomationBypassed();
     */
    private static Boolean isAutomationBypassed() {
        Automation_Setting_Global__c globalSetting = Automation_Setting_Global__c.getInstance();
        Automation_Setting_Trigger__c triggerSetting = Automation_Setting_Trigger__c.getInstance();
        return (globalSetting != null && globalSetting.disableAll__c)
            || (triggerSetting != null && triggerSetting.IsLSInactiveUserCleanupBypassed__c);
    }

    /**
     * @description Picks users who were active before, are inactive now, and were not already queued.
     * @param newUserList Trigger.new
     * @param oldUserMap Trigger.oldMap
     * @return Deactivated users in this transaction.
     */
    private static List<User> getDeactivatedUsers(List<User> newUserList, Map<Id, User> oldUserMap) {
        List<User> deactivatedUserList = new List<User>();
        for (User newUser : newUserList) {
            User oldUser = oldUserMap.get(newUser.Id);
            Boolean isDeactivated = oldUser != null && oldUser.IsActive && !newUser.IsActive;
            if (isDeactivated && !processedUserIdSet.contains(newUser.Id)) {
                deactivatedUserList.add(newUser);
            }
        }
        return deactivatedUserList;
    }

    /**
     * @description Keeps only the deactivated users who are Life Sciences users, before or after the change.
     * @param deactivatedUserList Users deactivated in this transaction.
     * @param oldUserMap Trigger.oldMap
     * @return Life Sciences user Id mapped to today's date.
     */
    private static Map<Id, Date> getLifeSciencesUsers(List<User> deactivatedUserList, Map<Id, User> oldUserMap) {
        Map<Id, Date> inactiveDateByUserIdMap = new Map<Id, Date>();
        Id lifeSciencesProfileId = UserSelector.getLifeSciencesSalesProfileIdForOverlay();
        if (lifeSciencesProfileId == null) {
            return inactiveDateByUserIdMap;
        }
        for (User deactivatedUser : deactivatedUserList) {
            Boolean isLifeSciences = deactivatedUser.ProfileId == lifeSciencesProfileId
                || oldUserMap.get(deactivatedUser.Id).ProfileId == lifeSciencesProfileId;
            if (isLifeSciences) {
                inactiveDateByUserIdMap.put(deactivatedUser.Id, System.today());
            }
        }
        return inactiveDateByUserIdMap;
    }

    /**
     * @description Reads the assignment types to remove from Custom Metadata, and falls back to the
     *              agreed defaults when the record is missing, inactive or blank.
     * @return AssignmentType__c values to remove.
     */
    private static Set<String> getAssignmentTypeSet() {
        CBM_Generic_Configuration__mdt config = CBM_Generic_Configuration__mdt.getInstance(CONFIG_DEVELOPER_NAME);
        Boolean hasUsableConfig = config != null && config.Is_Active__c && String.isNotBlank(config.Value__c);
        String rawValue = hasUsableConfig ? config.Value__c : DEFAULT_ASSIGNMENT_TYPES;
        Set<String> assignmentTypeSet = new Set<String>();
        for (String assignmentType : rawValue.split(',')) {
            if (String.isNotBlank(assignmentType)) {
                assignmentTypeSet.add(assignmentType.trim());
            }
        }
        return assignmentTypeSet;
    }
}