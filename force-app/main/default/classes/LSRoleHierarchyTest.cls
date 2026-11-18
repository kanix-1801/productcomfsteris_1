/**
 * @description GCL-338 tests for the Life Sciences role hierarchy: every chart node
 *              exists with its chart parent, owned records are visible up the branch
 *              only, a Role is required on LS users, and a role change moves
 *              visibility to the new branch.
 */
@IsTest
private class LSRoleHierarchyTest {

    private static final String LS_PROFILE_NAME = 'Life Sciences Sales';
    private static final String ROOT_ROLE = 'LS_Global_Lead';

    private static final Map<String, String> PARENT_BY_ROLE = new Map<String, String>{
        'LS_AVP_Equip_Svc_EUR_EMEA' => 'LS_Global_Lead',
        'LS_Territory_Leader_EUR_EMEA' => 'LS_AVP_Equip_Svc_EUR_EMEA',
        'LS_Sales_Rep_Equip_Svc_EUR_EMEA' => 'LS_Territory_Leader_EUR_EMEA',
        'LS_Assoc_Service_Manager_EUR_EMEA' => 'LS_Territory_Leader_EUR_EMEA',
        'LS_Engineer_Equip_Specialist_EUR_EMEA' => 'LS_Assoc_Service_Manager_EUR_EMEA',
        'LS_AVP_Equip_Svc_NA_LATAM' => 'LS_Global_Lead',
        'LS_AVP_Service_Sales_NA_LATAM' => 'LS_AVP_Equip_Svc_NA_LATAM',
        'LS_Sales_Rep_Equip_Svc_NA_LATAM' => 'LS_AVP_Service_Sales_NA_LATAM',
        'LS_Area_Service_Manager_NA_LATAM' => 'LS_AVP_Service_Sales_NA_LATAM',
        'LS_Service_Tech_NA_LATAM' => 'LS_Area_Service_Manager_NA_LATAM',
        'LS_Director_Ops_Engineering' => 'LS_Global_Lead',
        'LS_Manager_APM' => 'LS_Director_Ops_Engineering',
        'LS_APM_Engineer' => 'LS_Manager_APM',
        'LS_VP_Global_Sales_Consumables' => 'LS_Global_Lead',
        'LS_Sales_Director_FormChem_Asia' => 'LS_VP_Global_Sales_Consumables',
        'LS_Sales_Rep_FormChem_Asia' => 'LS_Sales_Director_FormChem_Asia',
        'LS_Sales_Director_FormChem_Europe' => 'LS_VP_Global_Sales_Consumables',
        'LS_Sales_Rep_FormChem_Europe' => 'LS_Sales_Director_FormChem_Europe',
        'LS_Sales_Director_FormChem_NA_LA' => 'LS_VP_Global_Sales_Consumables',
        'LS_Region_Manager_FormChem_NA_LA' => 'LS_Sales_Director_FormChem_NA_LA',
        'LS_Sales_Rep_FormChem_NA_LA' => 'LS_Region_Manager_FormChem_NA_LA',
        'LS_Global_Sales_Director_SMP' => 'LS_VP_Global_Sales_Consumables',
        'LS_Sales_Rep_SMP_Direct' => 'LS_Global_Sales_Director_SMP',
        'LS_Region_Manager_SMP' => 'LS_Global_Sales_Director_SMP',
        'LS_Sales_Rep_SMP_Region' => 'LS_Region_Manager_SMP',
        'LS_VP_Global_Accounts_Consumables' => 'LS_VP_Global_Sales_Consumables',
        'LS_GAD_Consumables' => 'LS_VP_Global_Accounts_Consumables',
        'LS_VP_Global_Accounts_Equip_Svc' => 'LS_Global_Lead',
        'LS_GAD_Equip_Svc' => 'LS_VP_Global_Accounts_Equip_Svc'
    };

    @TestSetup
    static void setupUsers() {
        Id profileId = lifeSciencesProfileId();
        Map<String, Id> roleIds = roleIdsByDeveloperName();
        insert new List<User>{
            buildUser(profileId, roleIds.get('LS_Sales_Rep_FormChem_Asia'), 'gcl338rep'),
            buildUser(profileId, roleIds.get('LS_Sales_Director_FormChem_Asia'), 'gcl338dirasia'),
            buildUser(profileId, roleIds.get('LS_VP_Global_Sales_Consumables'), 'gcl338vp'),
            buildUser(profileId, roleIds.get(ROOT_ROLE), 'gcl338lead'),
            buildUser(profileId, roleIds.get('LS_Sales_Director_FormChem_Europe'), 'gcl338direu'),
            buildUser(profileId, roleIds.get('LS_AVP_Equip_Svc_EUR_EMEA'), 'gcl338avpeu')
        };
    }

    /**
     * @description AC1 - every chart node is a distinct Role with exactly the chart parent,
     *              and Sales Rep nodes are separate roles per branch.
     */
    @IsTest
    static void testEveryChartNodeIsARoleWithItsChartParent() {
        Set<String> chartRoles = new Set<String>(PARENT_BY_ROLE.keySet());
        chartRoles.add(ROOT_ROLE);

        Map<Id, String> developerNameById = new Map<Id, String>();
        Map<String, UserRole> roleByDeveloperName = new Map<String, UserRole>();
        for (UserRole role : [
            SELECT Id, DeveloperName, ParentRoleId
            FROM UserRole
            WHERE DeveloperName IN :chartRoles
        ]) {
            developerNameById.put(role.Id, role.DeveloperName);
            roleByDeveloperName.put(role.DeveloperName, role);
        }

        System.assertEquals(chartRoles.size(), roleByDeveloperName.size(), 'Every chart node exists as a Role.');
        for (String roleName : PARENT_BY_ROLE.keySet()) {
            System.assertEquals(
                PARENT_BY_ROLE.get(roleName),
                developerNameById.get(roleByDeveloperName.get(roleName).ParentRoleId),
                roleName + ' reports to its chart parent.'
            );
        }
        System.assertEquals(
            null,
            developerNameById.get(roleByDeveloperName.get(ROOT_ROLE).ParentRoleId),
            'The Global Lead role is the top of the LS branch.'
        );

        Integer salesRepRoles = 0;
        for (String roleName : chartRoles) {
            if (roleName.startsWith('LS_Sales_Rep_')) {
                salesRepRoles++;
            }
        }
        System.assertEquals(7, salesRepRoles, 'Each chart Sales Rep node is its own Role.');
    }

    /**
     * @description AC2 - a rep's Account is visible to every role above the rep in the
     *              same branch and not to peer branches.
     */
    @IsTest
    static void testOwnedRecordIsVisibleUpTheBranchOnly() {
        Account ownedAccount = insertAccountOwnedBy(userByLastName('gcl338rep'));

        System.assert(access(userByLastName('gcl338dirasia'), ownedAccount.Id).HasReadAccess, 'Direct manager role sees the record.');
        System.assert(access(userByLastName('gcl338vp'), ownedAccount.Id).HasReadAccess, 'VP role sees the record.');
        System.assert(access(userByLastName('gcl338lead'), ownedAccount.Id).HasReadAccess, 'Global Lead role sees the record.');
        assertNoHierarchyAccess(userByLastName('gcl338direu'), ownedAccount.Id);
        assertNoHierarchyAccess(userByLastName('gcl338avpeu'), ownedAccount.Id);
    }

    /**
     * @description AC5 - moving the owner to another branch moves visibility with them.
     */
    @IsTest
    static void testRoleChangeMovesVisibilityToTheNewBranch() {
        User rep = userByLastName('gcl338rep');
        Account ownedAccount = insertAccountOwnedBy(rep);
        Id europeRepRoleId = roleIdsByDeveloperName().get('LS_Sales_Rep_FormChem_Europe');

        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            rep.UserRoleId = europeRepRoleId;
            update rep;
        }
        Test.stopTest();

        System.assert(access(userByLastName('gcl338direu'), ownedAccount.Id).HasReadAccess, 'New branch manager sees the record.');
        System.assert(access(userByLastName('gcl338vp'), ownedAccount.Id).HasReadAccess, 'Shared VP still sees the record.');
        assertNoHierarchyAccess(userByLastName('gcl338dirasia'), ownedAccount.Id);
    }

    /**
     * @description AC4 - an active Life Sciences user cannot be saved without a Role.
     */
    @IsTest
    static void testLifeSciencesUserWithoutRoleIsRejected() {
        User noRoleUser = buildUser(lifeSciencesProfileId(), null, 'gcl338norole');

        Test.startTest();
        Database.SaveResult result = Database.insert(noRoleUser, false);
        Test.stopTest();

        System.assert(!result.isSuccess(), 'User without a Role is rejected.');
        System.assert(
            result.getErrors()[0].getMessage().contains('A Role is required for Life Sciences users'),
            'The LS role validation message is shown.'
        );
    }

    /**
     * @description AC4 - an existing Life Sciences user cannot have the Role removed.
     */
    @IsTest
    static void testRoleCannotBeRemovedFromLifeSciencesUser() {
        User rep = userByLastName('gcl338rep');
        rep.UserRoleId = null;

        Test.startTest();
        Database.SaveResult result = Database.update(rep, false);
        Test.stopTest();

        System.assert(!result.isSuccess(), 'Removing the Role is rejected.');
    }

    private static void assertNoHierarchyAccess(User viewer, Id recordId) {
        String defaultAccess = [SELECT DefaultAccountAccess FROM Organization LIMIT 1].DefaultAccountAccess;
        UserRecordAccess recordAccess = access(viewer, recordId);
        if (defaultAccess == 'None') {
            System.assert(!recordAccess.HasReadAccess, 'Peer branch does not see the record.');
        } else if (defaultAccess == 'Read') {
            System.assert(!recordAccess.HasEditAccess, 'Peer branch does not get hierarchy edit access.');
        }
    }

    private static UserRecordAccess access(User viewer, Id recordId) {
        return [
            SELECT RecordId, HasReadAccess, HasEditAccess
            FROM UserRecordAccess
            WHERE UserId = :viewer.Id
            AND RecordId = :recordId
        ];
    }

    private static Account insertAccountOwnedBy(User owner) {
        Automation_Setting_Trigger__c settings = Automation_Setting_Trigger__c.getInstance();
        settings.AccountTriggerByPass__c = true;
        upsert settings;

        Account ownedAccount = new Account(
            Name = 'GCL338 Hierarchy ' + String.valueOf(System.currentTimeMillis()),
            OwnerId = owner.Id,
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Prospect')
                .getRecordTypeId(),
            CustomerClassCode__c = 'SC',
            OrgIDs__c = '83',
            BillingStreet = '123 Main St',
            BillingCity = 'Cleveland',
            BillingCountryCode = 'US',
            BillingStateCode = 'OH',
            BillingPostalCode = '44113'
        );
        insert ownedAccount;
        return ownedAccount;
    }

    private static User userByLastName(String lastName) {
        return [SELECT Id, UserRoleId FROM User WHERE LastName = :lastName LIMIT 1];
    }

    private static Id lifeSciencesProfileId() {
        return [SELECT Id FROM Profile WHERE Name = :LS_PROFILE_NAME LIMIT 1].Id;
    }

    private static Map<String, Id> roleIdsByDeveloperName() {
        Set<String> chartRoles = new Set<String>(PARENT_BY_ROLE.keySet());
        chartRoles.add(ROOT_ROLE);
        Map<String, Id> roleIds = new Map<String, Id>();
        for (UserRole role : [SELECT Id, DeveloperName FROM UserRole WHERE DeveloperName IN :chartRoles]) {
            roleIds.put(role.DeveloperName, role.Id);
        }
        return roleIds;
    }

    private static User buildUser(Id profileId, Id roleId, String lastName) {
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        String username = lastName + suffix + '@test.steris.com';
        return new User(
            FirstName = 'GCL338',
            LastName = lastName,
            Alias = ('g' + suffix).left(8),
            Email = username,
            Username = username,
            CommunityNickname = (lastName + suffix).left(40),
            ProfileId = profileId,
            UserRoleId = roleId,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }
}