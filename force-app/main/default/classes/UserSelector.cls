/**
* @author PWC Developer
* @date 2026/06/10
*
* @group Overlay Assignment
*
* @description
* GC-3088 - SOQL - only selector for User Object
* GC-3278 - TAS class rename; Healthcare Sales profile and HRIS user resolution for team access.
*/
public without sharing class UserSelector {
    
    public static final Integer USER_SEARCH_LIMIT = 50;
    public static final String HEALTHCARE_SALES_PROFILE_NAME = 'Healthcare Sales';
    public static final String LIFESCIENCES_SALES_PROFILE_NAME = 'Life Sciences Sales';     //GCL-1: Added for LS profile

    /** Lazy-loaded per transaction for Healthcare Sales profile filtering (GC-3189). */
    private static Id healthcareSalesProfileIdCache;
    
    @TestVisible
    private static void resetHealthcareSalesProfileIdCacheForTest() {
        healthcareSalesProfileIdCache = null;
    }

    /**GCL-1: START */
    /** Lazy-loaded per transaction for Life Sciences Sales profile filtering (GCL-1). */
    private static Id lifeSciencesSalesProfileIdCache;

    @TestVisible
    private static void resetLifeSciencesSalesProfileIdCacheForTest() {
        lifeSciencesSalesProfileIdCache = null;
    }
    /**GCL-1: END */

    /**
     * @description Returns Healthcare Sales Profile Id (lazy-loaded, cached per transaction).
     * Profile is read in SYSTEM_MODE because this selector is without sharing and
     * sales users are not granted Profile access.
     * @return Profile Id, or null when the profile does not exist in the org.
     */
    public static Id getHealthcareSalesProfileId() {
        if (healthcareSalesProfileIdCache == null) {
            List<Profile> profiles = [
                SELECT Id
                FROM Profile
                WHERE Name = :HEALTHCARE_SALES_PROFILE_NAME
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            healthcareSalesProfileIdCache = profiles.isEmpty() ? null : profiles[0].Id;
        }
        return healthcareSalesProfileIdCache;
    }

    /**
     * @description: [GCL-1] Returns Life Sciences Sales Profile Id (lazy-loaded, cached per transaction).
     * Profile is read in SYSTEM_MODE because this selector is without sharing and
     * sales users are not granted Profile access.
     * @return Profile Id, or null when the profile does not exist in the org.
     */
    public static Id getLifeSciencesSalesProfileId() {
        if (lifeSciencesSalesProfileIdCache == null) {
            List<Profile> profiles = [
                SELECT Id
                FROM Profile
                WHERE Name = :LIFESCIENCES_SALES_PROFILE_NAME
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            lifeSciencesSalesProfileIdCache = profiles.isEmpty() ? null : profiles[0].Id;
        }
        return lifeSciencesSalesProfileIdCache;
    }
    
    /**
* @description
* GC-3088 - Searches active users by name or email.
* 
* @param searchKey User-entered search text.
* @return Matching active users.
* 
* @example
* UserSelector.selectActiveUsersBySearch(searchKey);
*/
    public static List<User> selectActiveUsersBySearch(String searchKey) {
        String key = '%' + String.escapeSingleQuotes(String.isBlank(searchKey) ? '' : searchKey.trim()) + '%';
        if (!String.isBlank(searchKey) && Schema.sObjectType.User.isAccessible()) {
        return [
            SELECT Id,
            Name,
            Email,
            Country,
            Manager.Name,
            UserRole.Name,
            Title,
            Phone
            FROM User
            WHERE IsActive = true
            AND (Name LIKE :key OR Email LIKE :key)
            LIMIT : USER_SEARCH_LIMIT
        ];
        }
         return new List<User>();
    }
    /**
* @description
* GC-3088 - Selects Users by IDs for TAS writeback mapping.
* 
* @param userIdSet User IDs.
* @return Matching active users.
* 
* @example
* UserSelector.selectByIds(userIdSet);
*/
    public static List<User> selectByIds(Set<Id> userIdSet) {
       
      if (userIdSet != null &&!userIdSet.isEmpty() && Schema.sObjectType.User.isAccessible()) {

        return [
            SELECT Id,
            Name,
            EmployeeNumber__c
            FROM User
            WHERE Id IN :userIdSet
        ];
        }
         return new List<User>();
    }

    /**
     * @author Suraj Thapliyal
     * @description GC-2580 - Selects Users by Id for email notification delivery.
     * @param userIdSet User Ids.
     * @return User rows with Id, Name, Email, and IsActive.
     */
    public static List<User> selectByIdsForEmail(Set<Id> userIdSet) {
        if (userIdSet != null &&!userIdSet.isEmpty() && Schema.sObjectType.User.isAccessible()) {

        return [
            SELECT Id, Name, Email, IsActive
            FROM User
            WHERE Id IN :userIdSet and IsActive = true
            WITH USER_MODE
        ];
        }
         return new List<User>();
    }

    /**
     * GC-3112 / GC-3189 — Loads active Healthcare Sales users keyed by trimmed EmployeeNumber__c
     * for HRIS sales rep resolution.
     * @author Suraj Thapliyal
     * @param employeeNumbers HRIS employee numbers from OrderLineContact__c.HRISSalesRepId__c
     * @return Map of trimmed EmployeeNumber__c to active Healthcare Sales User; first match wins on duplicates
     */
    public static Map<String, User> selectActiveHealthcareSalesUsersByEmployeeNumber(
        Set<String> employeeNumbers
    ) {
        Map<String, User> userByEmployeeNumber = new Map<String, User>();

        if (employeeNumbers == null || employeeNumbers.isEmpty()) {
            return userByEmployeeNumber;
        }

        Id healthcareSalesProfileId = getHealthcareSalesProfileId();
        if (healthcareSalesProfileId == null) {
            throw new TASTeamAccessException(
                'Healthcare Sales profile not found: ' + HEALTHCARE_SALES_PROFILE_NAME
            );
        }

        for (User activeUser : [
            SELECT Id, EmployeeNumber__c
            FROM User
            WHERE ProfileId = :healthcareSalesProfileId
              AND EmployeeNumber__c IN :employeeNumbers
              AND IsActive = true
        ]) {
            String employeeNumber = activeUser.EmployeeNumber__c.trim();

            if (!userByEmployeeNumber.containsKey(employeeNumber)) {
                userByEmployeeNumber.put(employeeNumber, activeUser);
            }
        }

        return userByEmployeeNumber;
    }
    public static Map<String, User> selectActiveLifeSciencesSalesUsersByEmployeeNumber(Set<String> employeeNumbers) {
        Map<String, User> userByEmployeeNumber = new Map<String, User>();

        if (employeeNumbers == null || employeeNumbers.isEmpty()) {
            return userByEmployeeNumber;
        }

        Id lifeScienceSalesProfileId = getLifeSciencesSalesProfileId();
        if (lifeScienceSalesProfileId == null) {
            throw new TASTeamAccessException(
                'Life Science Sales profile not found: ' + LIFESCIENCES_SALES_PROFILE_NAME
            );
        }

        for (User activeUser : [
            SELECT Id, EmployeeNumber__c
            FROM User
            WHERE ProfileId = :lifeScienceSalesProfileId
              AND EmployeeNumber__c IN :employeeNumbers
              AND IsActive = true
        ]) {
            String employeeNumber = activeUser.EmployeeNumber__c.trim();

            if (!userByEmployeeNumber.containsKey(employeeNumber)) {
                userByEmployeeNumber.put(employeeNumber, activeUser);
            }
        }

        return userByEmployeeNumber;
    }

    /**
     * GC-3112-Loads active Users keyed by trimmed EmployeeNumber__c for HRIS sales rep resolution.
     * @author Suraj Thapliyal
     * @param employeeNumbers HRIS employee numbers from OrderLineContact__c.HRISSalesRepId__c
     * @return Map of trimmed EmployeeNumber__c to active User; first match wins on duplicates
     */
    public static Map<String, User> selectActiveUsersByEmployeeNumber(Set<String> employeeNumbers) {
        return selectActiveHealthcareSalesUsersByEmployeeNumber(employeeNumbers);
    }
    /**
     * Returns inactive Users matching the provided User Ids.
     * Used by existing inactive user cleanup logic to identify deactivated accounts for removal.
     * @author vinay
     * @param userIds Set of Salesforce User Ids to filter inactive records
     * @return List of inactive Users whose Id is in the provided set; empty list if none match
     * #GC 2641,GC 3098
     */
    public static List<User> getInactiveUsersByIds(Set<Id> userIds) {
      if (!userIds.isEmpty() && Schema.sObjectType.User.isAccessible()) {
        return [
            SELECT Id
            FROM User
            WHERE Id IN :userIds
            AND IsActive = false
            
        ];
        }
         return new List<User>();
    }
    
    /**
     * Returns active Users matching the provided User Ids.
     * Used by GC 2641 Opportunity Team Member logic to validate and resolve active user assignments.
     * @author vinay
     * @param userIds Set of Salesforce User Ids to filter active records
     * @return List of active Users whose Id is in the provided set; empty list if none match
     */
    public static List<User> getActiveUsersByIds(Set<Id> userIds) {
      if (!userIds.isEmpty() && Schema.sObjectType.User.isAccessible()) {
        return [
            SELECT Id
            FROM User
            WHERE Id IN :userIds
            AND IsActive = true
            WITH USER_MODE
        ];
    }
         return new List<User>();
    }

    /**
     * @description
     * GC-3175 - Searches active Healthcare Sales profile users by name or email.
     *
     * @param searchKey User-entered search text.
     * @return Matching active Healthcare Sales users.
     *
     * @example
     * UserSelector.selectActiveHealthcareSalesUsersBySearch(searchKey);
     */
    public static List<User> selectActiveHealthcareSalesUsersBySearch(String searchKey) {
        String key = '%' + String.escapeSingleQuotes(String.isBlank(searchKey) ? '' : searchKey.trim()) + '%';

        Id healthcareSalesProfileId = getHealthcareSalesProfileId();
        if (healthcareSalesProfileId == null) {
            throw new TASTeamAccessException(
                'Healthcare Sales profile not found: ' + HEALTHCARE_SALES_PROFILE_NAME
            );
        }

        if (!String.isBlank(searchKey) && Schema.sObjectType.User.isAccessible()) {
            return [
                SELECT Id,
                    Name,
                    Email,
                    Profile.Name,
                    Country,
                    Manager.Name,
                    UserRole.Name,
                    Title,
                    Phone
                FROM User
                WHERE IsActive = TRUE
                AND ProfileId = :healthcareSalesProfileId
                AND (Name LIKE :key OR Email LIKE :key)
                LIMIT :USER_SEARCH_LIMIT
            ];
        }

        return new List<User>();
    }
}