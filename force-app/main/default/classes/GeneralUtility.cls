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
        userPermission = HC_STR;    //Default to HC
        for (PermissionSetAssignment psa : [SELECT Id, PermissionSet.Name
                                            FROM PermissionSetAssignment
                                            WHERE AssigneeId = :UserInfo.getUserId()]) {
            if (psa.PermissionSet.Name.startsWith(LS_STR)) {
                userPermission = LS_STR;
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
        //If the user is a Healthcare Sales user or a Healthcare Dealer user
        //or the app name is Healthcare Sales or the user permission is HC,
        //then the business line is HC.
        //Otherwise, the business line is LS.
        if(userProfileName == HEALTHCARE_SALES_PROFILE_NAME
            || userProfileName == HEALTHCARE_DEALER_PROFILE_NAME
            || appName == HEALTHCARE_SALES_APP_NAME
            || userPermission == HC_STR) {
            currentBusinessLine = HC_STR;

        } else if(userProfileName == LIFESCIENCES_SALES_PROFILE_NAME || appName == LIFESCIENCES_SALES_APP_NAME || userPermission == LS_STR) {
            currentBusinessLine = LS_STR;
        }
    }

    /*****************************************************************************
     * Method Name       : getCurrentBusinessLine
     * Author           : Sarthak Pani
     * Date of Dev      : 16th November 2026
     * Last Modified Date   : 16th November 2026
     * Description          : get the current business line. This calculated only once and cached for the session.
    *****************************************************************************/
    public static String getCurrentBusinessLine() {
        if(String.isBlank(currentBusinessLine)) {
            loadUserProfileName();
            loadUserPermission();
            loadCurrentAppName();
            loadCurrentBusinessLine();
        }
        return currentBusinessLine;
    }

    /*****************************************************************************
     * Method Name       : getCurrentBusinessLineFromOpportunity
     * Author           : Sarthak Pani
     * Date of Dev      : 24th November 2026
     * Last Modified Date   : 24th November 2026
     * Description          : get the current business line from the opportunity record.
    *****************************************************************************/
    public static String getCurrentBusinessLineFromOpportunity(Id oppId) {
        if(String.isBlank(currentBusinessLine)) {
            Opportunity opportunityRecord = [SELECT Id, RecordType.DeveloperName FROM Opportunity WHERE Id = :oppId LIMIT 1];
            if(opportunityRecord.RecordType.DeveloperName.startsWith(LS_STR)) {
                currentBusinessLine = LS_STR;
            } else {
                currentBusinessLine = HC_STR;
            }
        }
        return currentBusinessLine;
    }

    /*****************************************************************************
     * Method Name       : getCurrentBusinessLineFromAccount
     * Author           : Sarthak Pani
     * Date of Dev      : 24th November 2026
     * Last Modified Date   : 24th November 2026
     * Description          : get the current business line from the account record.
    *****************************************************************************/
    public static String getCurrentBusinessLineFromAccount(Id accId) {
        if(String.isBlank(currentBusinessLine)) {
            Account accountRecord = [SELECT Id, RecordType.DeveloperName FROM Account WHERE Id = :accId LIMIT 1];
            if(accountRecord.RecordType.DeveloperName.startsWith(LS_STR)) {
                currentBusinessLine = LS_STR;
            } else {
                currentBusinessLine = HC_STR;
            }
        }
        return currentBusinessLine;
    }

    /*****************************************************************************
     * Method Name       : getCurrentBusinessLineFromQuote
     * Author           : Sarthak Pani
     * Date of Dev      : 24th November 2026
     * Last Modified Date   : 24th November 2026
     * Description          : get the current business line from the quote record.
    *****************************************************************************/
    public static String getCurrentBusinessLineFromQuote(Id quoteId) {
        if(String.isBlank(currentBusinessLine)) {
            Quote quoteRecord = [SELECT Id, RecordType.DeveloperName FROM Quote WHERE Id = :quoteId LIMIT 1];
            if(quoteRecord.RecordType.DeveloperName.startsWith(LS_STR)) {
                currentBusinessLine = LS_STR;
            } else {
                currentBusinessLine = HC_STR;
            }
        }
        return currentBusinessLine;
    }


}