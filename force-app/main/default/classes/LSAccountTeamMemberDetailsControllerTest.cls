/**
 * @description Test class for the Life Sciences Coverage Panel.
 * author PWC Developer
 * @date 2026/09/23
 *
 *  GCL-2 AC1: Covers LSAccountTeamMemberDetailsController, the Life Sciences
 *  factory on AccountTeamMemberDTO, and AccountTeamMemberSelector.selectByAccountIdForLifeSciences.
 */
@IsTest
private class LSAccountTeamMemberDetailsControllerTest {

    private static final String PERMISSION_SET_NAME = 'SalesCustomerOpsSalesSupportSalesAdmin';
    private static final String LS_FIELD_PERMISSION_SET_NAME = 'LSReadOnlyAccessPS';

    @TestSetup
    static void setupData() {
        Account testAccount = new Account(
            Name = 'LS Coverage Panel Account',
            SourceSystemID__c = 'LSATM001'
        );
        insert testAccount;

        User testUser = new User(
            FirstName = 'LS',
            LastName = 'Coverage',
            Email = 'lscoverage' + System.currentTimeMillis() + '@example.com',
            Username = 'lscoverage' + System.currentTimeMillis() + '@example.com',
            Alias = 'lscov',
            CommunityNickname = 'lscov' + System.currentTimeMillis(),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = UserInfo.getProfileId()
        );
        insert testUser;

        AccountTeamMember atm = new AccountTeamMember(
            AccountId = testAccount.Id,
            UserId = testUser.Id,
            TeamMemberRole = getActiveTeamMemberRole(),
            AccountAccessLevel = 'Edit',
            OpportunityAccessLevel = 'Edit',
            CaseAccessLevel = 'Read',
            ContactAccessLevel = 'Read',
            AssignmentType__c = getActiveAssignmentType(),
            TerritoryCode__c = 'L66301'
        );
        insert atm;

        List<PermissionSet> permissionSets = [
            SELECT Id, Name
            FROM PermissionSet
            WHERE Name IN :new Set<String>{ PERMISSION_SET_NAME, LS_FIELD_PERMISSION_SET_NAME }
        ];

        Set<String> foundPermissionSetNames = new Set<String>();
        List<PermissionSetAssignment> permissionSetAssignments = new List<PermissionSetAssignment>();
        for (PermissionSet permissionSetRecord : permissionSets) {
            foundPermissionSetNames.add(permissionSetRecord.Name);
            permissionSetAssignments.add(
                new PermissionSetAssignment(
                    AssigneeId = testUser.Id,
                    PermissionSetId = permissionSetRecord.Id
                )
            );
        }

        System.assert(
            foundPermissionSetNames.contains(PERMISSION_SET_NAME),
            'Required permission set "' + PERMISSION_SET_NAME + '" not found in this org.'
        );
        System.assert(
            foundPermissionSetNames.contains(LS_FIELD_PERMISSION_SET_NAME),
            'Required permission set "' + LS_FIELD_PERMISSION_SET_NAME + '" not found in this org.'
        );

        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert permissionSetAssignments;
        }
    }

    /**
     * @description Returns the Life Sciences panel fields, including Territory Number
     *              from TerritoryCode__c, and leaves Healthcare-only fields empty.
     */
    @IsTest
    static void testGetLifeSciencesAccountTeamMembers() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = getTestUser();

        System.runAs(testUser) {
            Test.startTest();
            List<AccountTeamMemberDTO> result =
                LSAccountTeamMemberDetailsController.getLifeSciencesAccountTeamMembers(testAccount.Id);
            Test.stopTest();

            System.assertEquals(1, result.size(), 'Expected the Account Team Member on the Account.');
            System.assertEquals('L66301', result[0].territoryCode);
            System.assertNotEquals(null, result[0].teamMember);
            System.assertNotEquals(null, result[0].teamRole);
            System.assertEquals(null, result[0].email);
            System.assertEquals(null, result[0].phone);
            System.assertEquals(null, result[0].salesCategoryCode);
            System.assertEquals(false, result[0].canViewAccessFields);
        }
    }

    /**
     * @description Returns an empty list when Account Id is null.
     */
    @IsTest
    static void testGetLifeSciencesAccountTeamMembersWithNullAccountId() {
        Test.startTest();
        List<AccountTeamMemberDTO> result =
            LSAccountTeamMemberDetailsController.getLifeSciencesAccountTeamMembers(null);
        Test.stopTest();

        System.assertEquals(0, result.size());
    }

    /**
     * @description Covers the controller catch path.
     */
    @IsTest
    static void testGetLifeSciencesAccountTeamMembersCatch() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        LSAccountTeamMemberDetailsController.throwTestException = true;

        try {
            Test.startTest();
            LSAccountTeamMemberDetailsController.getLifeSciencesAccountTeamMembers(testAccount.Id);
            Test.stopTest();
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException auraException) {
            System.assertNotEquals(null, auraException.getMessage());
        } finally {
            LSAccountTeamMemberDetailsController.throwTestException = false;
        }
    }

    /**
     * @description Covers the selector null-input path.
     */
    @IsTest
    static void testSelectByAccountIdForLifeSciencesWithNullAccountId() {
        Test.startTest();
        List<AccountTeamMember> result =
            AccountTeamMemberSelector.selectByAccountIdForLifeSciences(null);
        Test.stopTest();

        System.assertEquals(0, result.size());
    }

    /**
     * @description GCL-117 AC1 - Prospect owner is shown. No team record is written.
     */
    @IsTest
    static void testLifeSciencesProspectShowsOwnerWithoutChangingTeam() {
        bypassAccountTrigger();
        Account prospect = lifeSciencesAccount('GCL117 Prospect Panel', 'Prospect');
        insert prospect;

        Test.startTest();
        List<AccountTeamMemberDTO> rows =
            LSAccountTeamMemberDetailsController.getLifeSciencesAccountTeamMembers(prospect.Id);
        Test.stopTest();

        Account storedProspect = [SELECT OwnerId, Owner.Name FROM Account WHERE Id = :prospect.Id];
        System.assertEquals(0, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :prospect.Id]);
        System.assertEquals(1, rows.size());
        System.assertEquals(AccountTeamMemberDTO.LIFE_SCIENCES_OWNER_ROLE, rows[0].teamRole);
        System.assertEquals(AccountTeamMemberDTO.LIFE_SCIENCES_OWNER_ASSIGNMENT, rows[0].assignmentType);
        System.assertEquals(storedProspect.OwnerId, rows[0].userId);
        System.assertEquals(storedProspect.Owner.Name, rows[0].teamMember);
    }

    /**
     * @description GCL-117 AC3 - Customer owner is shown beside the existing sales
     *              row. The sales row stored by TAS is not replaced.
     */
    @IsTest
    static void testCustomerOwnerStaysSeparateFromExistingSalesRow() {
        bypassAccountTrigger();
        Account customer = lifeSciencesAccount('GCL117 Customer Panel', 'Customer');
        insert customer;
        AccountTeamMember salesMember = new AccountTeamMember(
            AccountId = customer.Id,
            UserId = UserInfo.getUserId(),
            TeamMemberRole = 'Sales',
            AssignmentType__c = 'Oracle Assigned',
            AccountAccessLevel = 'Edit',
            OpportunityAccessLevel = 'Read',
            CaseAccessLevel = 'Read',
            ContactAccessLevel = 'Read'
        );
        insert salesMember;

        Test.startTest();
        List<AccountTeamMemberDTO> rows =
            LSAccountTeamMemberDetailsController.getLifeSciencesAccountTeamMembers(customer.Id);
        Test.stopTest();

        AccountTeamMember stored = [
            SELECT TeamMemberRole, AssignmentType__c
            FROM AccountTeamMember
            WHERE Id = :salesMember.Id
        ];
        System.assertEquals('Sales', stored.TeamMemberRole);
        System.assertEquals('Oracle Assigned', stored.AssignmentType__c);
        System.assertEquals(1, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :customer.Id]);
        System.assertEquals(2, rows.size());
        System.assertEquals(AccountTeamMemberDTO.LIFE_SCIENCES_OWNER_ROLE, rows[0].teamRole);
        System.assertEquals(AccountTeamMemberDTO.LIFE_SCIENCES_OWNER_ASSIGNMENT, rows[0].assignmentType);
        System.assertEquals('Sales', rows[1].teamRole);
        System.assertEquals('Oracle Assigned', rows[1].assignmentType);
    }

    /**
     * @description Healthcare accounts do not get an Account Owner panel row.
     */
    @IsTest
    static void testHealthcareAccountDoesNotShowOwnerRow() {
        bypassAccountTrigger();
        Account healthcare = lifeSciencesAccount('GCL117 Healthcare Panel', 'Customer');
        healthcare.CustomerClassCode__c = 'HC';
        insert healthcare;

        Test.startTest();
        List<AccountTeamMemberDTO> rows =
            LSAccountTeamMemberDetailsController.getLifeSciencesAccountTeamMembers(healthcare.Id);
        Test.stopTest();

        System.assertEquals(0, rows.size());
        System.assertEquals(0, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :healthcare.Id]);
    }

    /**
     * @description Covers the shared selector and DTO paths used by Healthcare
     *              and Life Sciences. GCL-117 does not change those query results.
     */
    @IsTest
    static void testExistingSelectorAndDtoPathsRemainCovered() {
        Account accountRecord = [
            SELECT Id
            FROM Account
            WHERE Name = 'LS Coverage Panel Account'
            LIMIT 1
        ];
        User member = getTestUser();
        Set<Id> accountIds = new Set<Id>{ accountRecord.Id };
        Set<Id> userIds = new Set<Id>{ member.Id };
        String role = getActiveTeamMemberRole();
        String assignmentType = getActiveAssignmentType();

        System.assertEquals(1, AccountTeamMemberSelector.selectByAccountId(accountRecord.Id, false).size());
        System.assertEquals(1, AccountTeamMemberSelector.selectByAccountId(accountRecord.Id, true).size());
        System.assertEquals(0, AccountTeamMemberSelector.selectByAccountsAndUsers(null, userIds).size());
        System.assertEquals(1, AccountTeamMemberSelector.selectByAccountsAndUsers(accountIds, userIds).size());
        System.assertEquals(0, AccountTeamMemberSelector.selectByUserIds(new Set<Id>()).size());
        System.assertEquals(1, AccountTeamMemberSelector.selectByUserIds(userIds).size());
        System.assertEquals(0, AccountTeamMemberSelector.selectByAccountsUsersAndRole(accountIds, userIds, null).size());
        System.assertEquals(1, AccountTeamMemberSelector.selectByAccountsUsersAndRole(accountIds, userIds, role).size());
        System.assertEquals(
            0,
            AccountTeamMemberSelector.selectByAccountsUsersRoleAssignmentType(accountIds, userIds, role, null).size()
        );
        System.assertEquals(
            1,
            AccountTeamMemberSelector.selectByAccountsUsersRoleAssignmentType(
                accountIds, userIds, role, assignmentType
            ).size()
        );
        System.assertEquals(0, AccountTeamMemberSelector.selectLifeSciencesByAccountsAndUsers(accountIds, new Set<Id>()).size());
        System.assertEquals(1, AccountTeamMemberSelector.selectLifeSciencesByAccountsAndUsers(accountIds, userIds).size());
        System.assertEquals(0, AccountTeamMemberSelector.selectCurrentUserTeamMember(null).size());
        AccountTeamMemberSelector.selectCurrentUserTeamMember(accountRecord.Id);
        System.assertNotEquals(null, AccountTeamMemberSelector.selectOwnerForCoveragePanel(accountRecord.Id));

        AccountTeamMember teamMember = [
            SELECT Id, User.Name, User.Title, User.Email, User.Phone, TeamMemberRole,
                   SalesCategoryDescription__c, ExpiryDate__c, AssignmentType__c,
                   TerritoryCode__c, SalesCategoryCode__c, AccountAccessLevel,
                   CaseAccessLevel, ContactAccessLevel, OpportunityAccessLevel
            FROM AccountTeamMember
            WHERE AccountId = :accountRecord.Id
            LIMIT 1
        ];
        AccountTeamMemberDTO hiddenAccess = new AccountTeamMemberDTO(teamMember, false);
        AccountTeamMemberDTO visibleAccess = new AccountTeamMemberDTO(teamMember, true);
        System.assertEquals(false, hiddenAccess.canViewAccessFields);
        System.assertEquals(null, hiddenAccess.accountAccess);
        System.assertEquals(true, visibleAccess.canViewAccessFields);
        System.assertEquals(teamMember.AccountAccessLevel, visibleAccess.accountAccess);
    }

    private static Account lifeSciencesAccount(String name, String recordTypeName) {
        String suffix = String.valueOf(System.currentTimeMillis());
        Account accountRecord = new Account(
            Name = name + ' ' + suffix,
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get(recordTypeName)
                .getRecordTypeId(),
            CustomerClassCode__c = 'SC',
            OrgIDs__c = '82',
            BillingStreet = '123 Main St',
            BillingCity = 'Cleveland',
            BillingCountryCode = 'US',
            BillingStateCode = 'OH',
            BillingPostalCode = '44113'
        );
        if (recordTypeName == 'Customer') {
            accountRecord.AccountSource = 'Oracle';
            accountRecord.SourceSystemID__c = 'GCL117' + suffix;
            accountRecord.OracleAddressId__c = 'GCL117' + suffix;
        }
        return accountRecord;
    }

    private static void bypassAccountTrigger() {
        Automation_Setting_Trigger__c settings = Automation_Setting_Trigger__c.getInstance();
        settings.AccountTriggerByPass__c = true;
        upsert settings;
    }

    private static User getTestUser() {
        return [
            SELECT Id
            FROM User
            WHERE Username LIKE 'lscoverage%@example.com'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }

    private static String getActiveAssignmentType() {
        for (Schema.PicklistEntry picklistEntry :
            AccountTeamMember.AssignmentType__c.getDescribe().getPicklistValues()
        ) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }
        return null;
    }

    private static String getActiveTeamMemberRole() {
        for (Schema.PicklistEntry picklistEntry :
            AccountTeamMember.TeamMemberRole.getDescribe().getPicklistValues()
        ) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }
        return 'Sales Rep';
    }
}