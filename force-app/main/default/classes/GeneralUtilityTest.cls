/*****************************************************************************
 * Class Name       : GeneralUtilityTest
 * Author           : Sarthak Pani
 * Date of Dev      : 18th November 2026
 * Last Modified Date   : 18th November 2026
 * Description          : Tests for GeneralUtility profile, permission, app, and business line resolution.
*****************************************************************************/
@IsTest(SeeAllData=false)
private class GeneralUtilityTest {
    private static final String SYSTEM_ADMIN_PROFILE_NAME = 'System Administrator';
    private static final String HC_DEFAULT_USER = 'GU HC Default';
    private static final String LS_PERMISSION_USER = 'GU LS Permission';
    private static final String NON_LS_PERMISSION_USER = 'GU Non LS Permission';
    private static final String HC_PROFILE_USER = 'GU HC Profile';
    private static final String LS_PROFILE_USER = 'GU LS Profile';
    private static final String LS_PROFILE_PERMISSION_USER = 'GU LS Profile Permission';
    private static Integer userSequence = 0;

    @TestSetup
    static void setupUsers() {
        Id roleId = [SELECT Id FROM UserRole WHERE PortalType = 'None' LIMIT 1].Id;
        Map<String, Id> profileIdsByName = profileIdsByName();

        User hcDefaultUser = buildUser(profileIdsByName.get(SYSTEM_ADMIN_PROFILE_NAME), roleId, HC_DEFAULT_USER);
        User lsPermissionUser = buildUser(profileIdsByName.get(SYSTEM_ADMIN_PROFILE_NAME), roleId, LS_PERMISSION_USER);
        User nonLsPermissionUser = buildUser(profileIdsByName.get(SYSTEM_ADMIN_PROFILE_NAME), roleId, NON_LS_PERMISSION_USER);
        User hcProfileUser = buildUser(
            profileIdsByName.get(GeneralUtility.HEALTHCARE_SALES_PROFILE_NAME),
            roleId,
            HC_PROFILE_USER
        );
        User lsProfileUser = buildUser(
            profileIdsByName.get(GeneralUtility.LIFESCIENCES_SALES_PROFILE_NAME),
            roleId,
            LS_PROFILE_USER
        );
        User lsProfilePermissionUser = buildUser(
            profileIdsByName.get(GeneralUtility.LIFESCIENCES_SALES_PROFILE_NAME),
            roleId,
            LS_PROFILE_PERMISSION_USER
        );
        insert new List<User>{
            hcDefaultUser,
            lsPermissionUser,
            nonLsPermissionUser,
            hcProfileUser,
            lsProfileUser,
            lsProfilePermissionUser
        };

        PermissionSet lsPermissionSet = buildPermissionSet('LSGenUtil');
        PermissionSet nonLsPermissionSet = buildPermissionSet('HCGenUtil');
        insert new List<PermissionSet>{ lsPermissionSet, nonLsPermissionSet };
        insert new List<PermissionSetAssignment>{
            new PermissionSetAssignment(AssigneeId = lsPermissionUser.Id, PermissionSetId = lsPermissionSet.Id),
            new PermissionSetAssignment(AssigneeId = nonLsPermissionUser.Id, PermissionSetId = nonLsPermissionSet.Id),
            new PermissionSetAssignment(AssigneeId = hcProfileUser.Id, PermissionSetId = lsPermissionSet.Id),
            new PermissionSetAssignment(AssigneeId = lsProfilePermissionUser.Id, PermissionSetId = lsPermissionSet.Id)
        };
    }

    @IsTest
    static void constantsMatchExpectedValues() {
        System.assertEquals('Life Sciences Sales', GeneralUtility.LIFESCIENCES_SALES_PROFILE_NAME);
        System.assertEquals('Healthcare Sales', GeneralUtility.HEALTHCARE_SALES_PROFILE_NAME);
        System.assertEquals('Healthcare Dealer', GeneralUtility.HEALTHCARE_DEALER_PROFILE_NAME);
        System.assertEquals('LifeSciencesSales', GeneralUtility.LIFESCIENCES_SALES_APP_NAME);
        System.assertEquals('HealthcareSales', GeneralUtility.HEALTHCARE_SALES_APP_NAME);
        System.assertEquals('LS', GeneralUtility.LS_STR);
        System.assertEquals('HC', GeneralUtility.HC_STR);
    }

    @IsTest
    static void constructorLoadsContextForCurrentUser() {
        User contextUser = userByLastName(HC_DEFAULT_USER);
        resetState();

        Test.startTest();
        System.runAs(contextUser) {
            new GeneralUtility();
        }
        Test.stopTest();

        System.assertEquals(SYSTEM_ADMIN_PROFILE_NAME, GeneralUtility.userProfileName);
        System.assertEquals(GeneralUtility.HC_STR, GeneralUtility.userPermission);
        System.assertEquals(null, GeneralUtility.appName);
        System.assertEquals(GeneralUtility.HC_STR, GeneralUtility.currentBusinessLine);
    }

    @IsTest
    static void loadUserProfileNameMatchesAssignedProfile() {
        User contextUser = userByLastName(LS_PROFILE_USER);
        resetState();

        Test.startTest();
        System.runAs(contextUser) {
            GeneralUtility.loadUserProfileName();
        }
        Test.stopTest();

        System.assertEquals(GeneralUtility.LIFESCIENCES_SALES_PROFILE_NAME, GeneralUtility.userProfileName);
    }

    @IsTest
    static void loadUserPermissionDefaultsToHealthcare() {
        User contextUser = userByLastName(HC_DEFAULT_USER);
        resetState();

        Test.startTest();
        System.runAs(contextUser) {
            GeneralUtility.loadUserPermission();
        }
        Test.stopTest();

        System.assertEquals(GeneralUtility.HC_STR, GeneralUtility.userPermission);
    }

    @IsTest
    static void loadUserPermissionIgnoresPermissionSetThatDoesNotStartWithLs() {
        User contextUser = userByLastName(NON_LS_PERMISSION_USER);
        resetState();

        Test.startTest();
        System.runAs(contextUser) {
            GeneralUtility.loadUserPermission();
        }
        Test.stopTest();

        System.assertEquals(GeneralUtility.HC_STR, GeneralUtility.userPermission);
    }

    @IsTest
    static void loadUserPermissionUsesLifeSciencesWhenPermissionSetStartsWithLs() {
        User contextUser = userByLastName(LS_PERMISSION_USER);
        resetState();

        Test.startTest();
        System.runAs(contextUser) {
            GeneralUtility.loadUserPermission();
        }
        Test.stopTest();

        System.assertEquals(GeneralUtility.LS_STR, GeneralUtility.userPermission);
    }

    @IsTest
    static void loadCurrentAppNameIsNullWhenUserHasNoApp() {
        User contextUser = userByLastName(HC_DEFAULT_USER);
        resetState();

        Test.startTest();
        System.runAs(contextUser) {
            GeneralUtility.loadCurrentAppName();
        }
        Test.stopTest();

        System.assertEquals(null, GeneralUtility.appName);
    }

    @IsTest
    static void loadCurrentAppNameReturnsDeveloperName() {
        User contextUser = userByLastName(HC_DEFAULT_USER);
        AppDefinition appDefinition = appDefinitionByDeveloperName(null);
        assignApp(contextUser.Id, appDefinition.DurableId);
        resetState();

        Test.startTest();
        System.runAs(contextUser) {
            GeneralUtility.loadCurrentAppName();
        }
        Test.stopTest();

        System.assertEquals(appDefinition.DeveloperName, GeneralUtility.appName);
    }

    @IsTest
    static void businessLineIsHealthcareWithoutLifeSciencesPermission() {
        assertBusinessLine(userByLastName(HC_DEFAULT_USER), GeneralUtility.HC_STR);
        System.assertEquals(GeneralUtility.HC_STR, GeneralUtility.userPermission);
        System.assertEquals(null, GeneralUtility.appName);
    }

    @IsTest
    static void businessLineIsLifeSciencesWhenPermissionStartsWithLs() {
        assertBusinessLine(userByLastName(LS_PERMISSION_USER), GeneralUtility.LS_STR);
        System.assertEquals(GeneralUtility.LS_STR, GeneralUtility.userPermission);
        System.assertEquals(SYSTEM_ADMIN_PROFILE_NAME, GeneralUtility.userProfileName);
    }

    @IsTest
    static void healthcareSalesProfileStaysHealthcareWithLifeSciencesPermission() {
        assertBusinessLine(userByLastName(HC_PROFILE_USER), GeneralUtility.HC_STR);
        System.assertEquals(GeneralUtility.HEALTHCARE_SALES_PROFILE_NAME, GeneralUtility.userProfileName);
        System.assertEquals(GeneralUtility.LS_STR, GeneralUtility.userPermission);
    }

    @IsTest
    static void lifeSciencesSalesProfileWithoutLsPermissionStaysHealthcare() {
        assertBusinessLine(userByLastName(LS_PROFILE_USER), GeneralUtility.HC_STR);
        System.assertEquals(GeneralUtility.LIFESCIENCES_SALES_PROFILE_NAME, GeneralUtility.userProfileName);
        System.assertEquals(GeneralUtility.HC_STR, GeneralUtility.userPermission);
    }

    @IsTest
    static void lifeSciencesSalesProfileWithLsPermissionIsLifeSciences() {
        assertBusinessLine(userByLastName(LS_PROFILE_PERMISSION_USER), GeneralUtility.LS_STR);
        System.assertEquals(GeneralUtility.LIFESCIENCES_SALES_PROFILE_NAME, GeneralUtility.userProfileName);
        System.assertEquals(GeneralUtility.LS_STR, GeneralUtility.userPermission);
    }

    @IsTest
    static void healthcareAppOverridesLifeSciencesPermission() {
        User contextUser = userByLastName(LS_PERMISSION_USER);
        AppDefinition healthcareApp = appDefinitionByDeveloperName(GeneralUtility.HEALTHCARE_SALES_APP_NAME);
        assignApp(contextUser.Id, healthcareApp.DurableId);

        assertBusinessLine(contextUser, GeneralUtility.HC_STR);
        System.assertEquals(GeneralUtility.HEALTHCARE_SALES_APP_NAME, GeneralUtility.appName);
        System.assertEquals(GeneralUtility.LS_STR, GeneralUtility.userPermission);
    }

    @IsTest
    static void lifeSciencesAppWithLifeSciencesPermissionIsLifeSciences() {
        User contextUser = userByLastName(LS_PERMISSION_USER);
        AppDefinition lifeSciencesApp = appDefinitionByDeveloperName(GeneralUtility.LIFESCIENCES_SALES_APP_NAME);
        assignApp(contextUser.Id, lifeSciencesApp.DurableId);

        assertBusinessLine(contextUser, GeneralUtility.LS_STR);
        System.assertEquals(GeneralUtility.LIFESCIENCES_SALES_APP_NAME, GeneralUtility.appName);
    }

    @IsTest
    static void getCurrentBusinessLineReturnsCachedValue() {
        resetState();
        GeneralUtility.currentBusinessLine = GeneralUtility.LS_STR;

        Test.startTest();
        String businessLine = GeneralUtility.getCurrentBusinessLine();
        Test.stopTest();

        System.assertEquals(GeneralUtility.LS_STR, businessLine);
        System.assertEquals('', GeneralUtility.userProfileName);
    }

    @IsTest
    static void getCurrentBusinessLineLoadsWhenBlank() {
        User contextUser = userByLastName(LS_PERMISSION_USER);
        resetState();

        Test.startTest();
        String businessLine;
        System.runAs(contextUser) {
            businessLine = GeneralUtility.getCurrentBusinessLine();
        }
        Test.stopTest();

        System.assertEquals(GeneralUtility.LS_STR, businessLine);
        System.assertEquals(GeneralUtility.LS_STR, GeneralUtility.currentBusinessLine);
        System.assertEquals(SYSTEM_ADMIN_PROFILE_NAME, GeneralUtility.userProfileName);
    }

    private static void assertBusinessLine(User contextUser, String expectedBusinessLine) {
        resetState();

        Test.startTest();
        System.runAs(contextUser) {
            GeneralUtility.loadCurrentBusinessLine();
        }
        Test.stopTest();

        System.assertEquals(
            expectedBusinessLine,
            GeneralUtility.currentBusinessLine,
            'Profile ' + GeneralUtility.userProfileName
                + ', permission ' + GeneralUtility.userPermission
                + ', app ' + GeneralUtility.appName
        );
    }

    private static void assignApp(Id userId, String appDefinitionId) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new UserAppInfo(
                UserId = userId,
                AppDefinitionId = appDefinitionId,
                FormFactor = 'Large'
            );
        }
    }

    private static AppDefinition appDefinitionByDeveloperName(String developerName) {
        String soql = 'SELECT DurableId, DeveloperName FROM AppDefinition';
        if (String.isNotBlank(developerName)) {
            soql += ' WHERE DeveloperName = :developerName';
        }
        soql += ' LIMIT 1';
        List<AppDefinition> appDefinitions = Database.query(soql);
        System.assertEquals(1, appDefinitions.size(), 'App definition not found for ' + developerName);
        return appDefinitions[0];
    }

    private static Map<String, Id> profileIdsByName() {
        Map<String, Id> profileIdsByName = new Map<String, Id>();
        for (Profile profileRecord : [
            SELECT Id, Name
            FROM Profile
            WHERE Name IN :new Set<String>{
                SYSTEM_ADMIN_PROFILE_NAME,
                GeneralUtility.HEALTHCARE_SALES_PROFILE_NAME,
                GeneralUtility.LIFESCIENCES_SALES_PROFILE_NAME
            }
        ]) {
            profileIdsByName.put(profileRecord.Name, profileRecord.Id);
        }
        System.assertNotEquals(null, profileIdsByName.get(SYSTEM_ADMIN_PROFILE_NAME), 'System Administrator profile is required');
        System.assertNotEquals(
            null,
            profileIdsByName.get(GeneralUtility.HEALTHCARE_SALES_PROFILE_NAME),
            'Healthcare Sales profile is required'
        );
        System.assertNotEquals(
            null,
            profileIdsByName.get(GeneralUtility.LIFESCIENCES_SALES_PROFILE_NAME),
            'Life Sciences Sales profile is required'
        );
        return profileIdsByName;
    }

    private static User buildUser(Id profileId, Id roleId, String lastName) {
        userSequence++;
        String seed = String.valueOf(userSequence) + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        String username = 'generalutility.' + lastName.replace(' ', '').toLowerCase() + seed + '@test.invalid';
        return new User(
            FirstName = 'General',
            LastName = lastName,
            Alias = ('gu' + seed).left(8),
            Email = username,
            Username = username,
            CommunityNickname = ('gu' + lastName.replace(' ', '') + seed).left(40),
            ProfileId = profileId,
            UserRoleId = roleId,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            EmployeeNumber__c = ('GU' + seed).left(20),
            FederationIdentifier = ('GU' + seed).left(20),
            IsActive = true
        );
    }

    private static PermissionSet buildPermissionSet(String namePrefix) {
        String uniqueName = (namePrefix + String.valueOf(Math.abs(Crypto.getRandomInteger()))).left(40);
        return new PermissionSet(Name = uniqueName, Label = uniqueName);
    }

    private static User userByLastName(String lastName) {
        return [SELECT Id, Profile.Name FROM User WHERE LastName = :lastName LIMIT 1];
    }

    private static void resetState() {
        GeneralUtility.userProfileName = '';
        GeneralUtility.userPermission = '';
        GeneralUtility.appName = '';
        GeneralUtility.currentBusinessLine = '';
    }
}