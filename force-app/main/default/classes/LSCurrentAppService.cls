/**
 * @description       : This class is used to get the current app developer name for the user.  
 * @author            : Sarthak Pani
 * @last modified on  : 05-10-2026
 * @last modified by  : Sarthak Pani
 * @Change log        : Initial Version
**/

public with sharing class LSCurrentAppService {
    
    /**
     * @description       : This method returns the app DeveloperName the logged-in user is currently on.
     * @param formFactor  : The form factor of the user.
     * @return            : The app DeveloperName the logged-in user is currently on.
     * @author            : Sarthak Pani
     */
    @AuraEnabled(cacheable=true)
    public static String getCurrentAppDeveloperName(String formFactor) {
        List<UserAppInfo> appInfos = [
            SELECT AppDefinitionId
            FROM UserAppInfo
            WHERE UserId = :UserInfo.getUserId()
              AND FormFactor = :formFactor
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (appInfos.isEmpty()) {
            return null;
        }

        List<AppDefinition> apps = [
            SELECT DeveloperName
            FROM AppDefinition
            WHERE DurableId = :appInfos[0].AppDefinitionId
            WITH USER_MODE
            LIMIT 1
        ];
        return apps.isEmpty() ? null : apps[0].DeveloperName;
    }
}