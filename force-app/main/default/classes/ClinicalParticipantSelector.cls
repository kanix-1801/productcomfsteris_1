/**
 * @description GC-3542 - SOQL for the clinical participant popup and save.
 */
public with sharing class ClinicalParticipantSelector {
    /**
     * @description GC-3542 - Active User name and email for the popup.
     * @param userId Salesforce User Id.
     * @return The active User, or null.
     */
    public static User selectActiveUser(Id userId) {
        if (userId == null) {
            return null;
        }
        List<User> users = [
            SELECT Name, Email
            FROM User
            WHERE Id = :userId AND IsActive = TRUE
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0];
    }

    /**
     * @description GC-3542 - Users named on the participant JSON.
     * @param userIds Salesforce User Ids.
     * @return Users by Id.
     */
    public static Map<Id, User> selectUsersByIds(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return new Map<Id, User>();
        }
        return new Map<Id, User>([
            SELECT Name, Email
            FROM User
            WHERE Id IN :userIds
        ]);
    }
}