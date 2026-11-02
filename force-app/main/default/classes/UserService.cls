/**
 * User Service Class
 * @description 	:Service class responsible for identifying inactive Sales Users
 * 					 and initiating Account Team Member and Opportunity Team Member cleanup processing.
 * @author 			: Vinay
 * @date 			:2026-06-12
 */
public with sharing class UserService {
    @TestVisible
    private static String salesProfileName = 'Steris Sales';
    private static final String SCENARIO = 'Inactive Sales User Team Cleanup';
	private static final String CLASS_NAME = 'UserService';

    /**
     *Identifies Sales Users that changed from active to inactive
     * and initiates assignment cleanup processing.
     */
    public static void processInactiveSalesUsers(List<User> newUsers, Map<Id, User> oldUserMap) {
        Map<Id, Date> userIdToInactiveDate = new Map<Id, Date>();

        for (User newUser : newUsers) {
            User oldUser = oldUserMap.get(newUser.Id);

            if (oldUser != null && oldUser.IsActive && !newUser.IsActive) {
                userIdToInactiveDate.put(newUser.Id, System.today());
            }
        }

        if (userIdToInactiveDate.isEmpty()) { return;
        }

        Set<Id> inactiveSalesUserIds = getInactiveSalesUserIds(userIdToInactiveDate.keySet());

        if (inactiveSalesUserIds.isEmpty()) {
            return;
        }
        
        Boolean shouldSaveLog = false;
        try {
            System.enqueueJob(
                new InactiveUserTeamCleanup(
                    inactiveSalesUserIds,
                    getTeamMemberRolesToDelete(),
                    userIdToInactiveDate
                )
            );
        } catch (Exception exceptionRecord) {
            shouldSaveLog = true;
            Logger.setScenario(SCENARIO);
            Logger.error( 'Unable to enqueue inactive Sales User team cleanup job. Error: ' + exceptionRecord.getMessage())
            .addTag('User')
            .addTag('Inactive User Cleanup')
            .addTag(CLASS_NAME);
        
        } finally {
            if (shouldSaveLog) {
                Logger.saveLog();
            }
        }
    }

    /**
     *Returns inactive Users from the provided User Ids.
     */
    private static Set<Id> getInactiveSalesUserIds(Set<Id> userIds) {
        Set<Id> inactiveSalesUserIds = new Set<Id>();

        for (User userRecord : UserSelector.getInactiveUsersByIds(userIds)){
            inactiveSalesUserIds.add(userRecord.Id);
        }

        return inactiveSalesUserIds;
    }
        /**
         *Returns the list of team member roles eligible for cleanup
         * from the TeamMemberRolesToDelete custom label.
         */
    private static Set<String> getTeamMemberRolesToDelete() {
        Set<String> rolesToDelete = new Set<String>();

        for (String roleValue : System.Label.TeamMemberRolesToDelete.split(',')) {
            if (String.isNotBlank(roleValue)) {
                rolesToDelete.add(roleValue.trim());
            }
        }

        return rolesToDelete;
    }
}