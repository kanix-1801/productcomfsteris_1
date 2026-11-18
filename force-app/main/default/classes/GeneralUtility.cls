/*****************************************************************************
 * Class Name       : GeneralUtility
 * Test Class       : GeneralUtilityTest
 * Author           : Sarthak Pani
 * Date of Dev      : 16th November 2026
 * Last Modified Date   : 16th November 2026
*****************************************************************************/
public without sharing class GeneralUtility {
    public static final String LIFESCIENCES_SALES_PROFILE_NAME = 'Life Sciences Sales';
    public static final String HEALTHCARE_SALES_PROFILE_NAME = 'Healthcare Sales';
    public static final String HEALTHCARE_DEALER_PROFILE_NAME = 'Healthcare Dealer';
    public static final String LIFESCIENCES_SALES_APP_NAME = 'LifeSciencesSales';
    public static final String HEALTHCARE_SALES_APP_NAME = 'HealthcareSales';
    public static final String LS_STR = 'LS';
    public static final String HC_STR = 'HC';

    public static String userProfileName = '';
    public static String userPermission = '';
    public static String appName = '';
    public static String currentBusinessLine = '';


    public GeneralUtility() {
        loadUserProfileName();
        loadUserPermission();
        loadCurrentAppName();
        loadCurrentBusinessLine();
    }


    /*****************************************************************************
     * Method Name       : loadUserProfileName
     * Author           : Sarthak Pani
     * Date of Dev      : 16th November 2026
     * Last Modified Date   : 16th November 2026
     * Description          : check if the user is HC or LS
    *****************************************************************************/
    public static void loadUserProfileName() {
        User currentUser = [SELECT Id, Name, Profile.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        userProfileName = currentUser.Profile.Name;
    }


    /*****************************************************************************
     * Method Name       : loadUserPermission
     * Author           : Sarthak Pani
     * Date of Dev      : 16th November 2026
     * Last Modified Date   : 16th November 2026
     * Description          : check if the user is HC or LS
    *****************************************************************************/
    public static void loadUserPermission() {
        for (PermissionSetAssignment psa : [SELECT Id, PermissionSet.Name
                                            FROM PermissionSetAssignment
                                            WHERE AssigneeId = :UserInfo.getUserId()]) {
            if (psa.PermissionSet.Name.startsWith(LS_STR)) {
                userPermission = LS_STR;
                break;
            } else if(psa.PermissionSet.Name.startsWith(HC_STR)) {
                userPermission = HC_STR;
                break;
            }
        }
    }


    /*****************************************************************************
     * Method Name       : loadCurrentAppName
     * Author           : Sarthak Pani
     * Date of Dev      : 16th November 2026
     * Last Modified Date   : 16th November 2026
     * Description          : get the current app name
    *****************************************************************************/
    public static void loadCurrentAppName() {
        List<UserAppInfo> appInfos = [SELECT AppDefinitionId
                                        FROM UserAppInfo
                                        WHERE UserId = :UserInfo.getUserId()
                                        ORDER BY LastModifiedDate DESC LIMIT 1];
        if (appInfos.isEmpty()) {
            appName = null;
            return;
        }

        List<AppDefinition> apps = [SELECT DeveloperName
                                    FROM AppDefinition
                                    WHERE DurableId = :appInfos[0].AppDefinitionId LIMIT 1];

        appName = apps.isEmpty() ? null : apps[0].DeveloperName;
    }

    /*****************************************************************************
     * Method Name       : loadCurrentBusinessLine
     * Author           : Sarthak Pani
     * Date of Dev      : 16th November 2026
     * Last Modified Date   : 16th November 2026
     * Description          : get the current scenario
    *****************************************************************************/
    public static void loadCurrentBusinessLine() {
        loadUserProfileName();
        loadUserPermission();
        loadCurrentAppName();
        if(userProfileName == HEALTHCARE_SALES_PROFILE_NAME
            || userProfileName == HEALTHCARE_DEALER_PROFILE_NAME
            || appName == HEALTHCARE_SALES_APP_NAME
            || userPermission == HC_STR) {
            currentBusinessLine = HC_STR;
        } else if(userProfileName == LIFESCIENCES_SALES_PROFILE_NAME || appName == LIFESCIENCES_SALES_APP_NAME || userPermission == LS_STR) {
            currentBusinessLine = LS_STR;
        }
    }

    public static String getCurrentBusinessLine() {
        if(String.isBlank(currentBusinessLine)) {
            loadCurrentBusinessLine();
        }
        return currentBusinessLine;
    }
}