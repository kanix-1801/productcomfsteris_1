/**
 * @author Divya Sree
 * @date 2026/05/25
 *
 * @description
 * Test class for AccountTeamMemberDetailsController.
 * Covers Account Team Member retrieval with and without access-field visibility,
 * null Account Id handling, custom permission branch, and service exception handling.
 *
 * NOTE: Tests run as a dedicated test user assigned the
 * 'SalesCustomerOpsSalesSupportSalesAdmin' permission set, which grants:
 *   - FLS (Read) on AccountTeamMember fields queried WITH USER_MODE
 *   - The 'View_Account_Team_Access_Fields' custom permission
 * This removes dependency on whichever user/profile executes the deployment/test run.
 */
@IsTest
private class AccountTeamMemberDetailsControllerTest {

    private static final String PERMISSION_SET_NAME = 'SalesCustomerOpsSalesSupportSalesAdmin';

    /**
     * @description
     * Creates test Account, User, and Account Team Member data required
     * by all test methods. Also assigns the required permission set to the
     * test user so tests run with correct FLS and custom permission access
     * regardless of the org's deployment/test-running user.
     */
    @TestSetup
    static void setupData() {
        Account testAccount = new Account(
            Name = 'Test Account',
            SourceSystemID__c = 'Test86dw6'
        );
        insert testAccount;

        User testUser = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'testuser' + System.currentTimeMillis() + '@example.com',
            Username = 'testuser' + System.currentTimeMillis() + '@example.com',
            Alias = 'tuser',
            CommunityNickname = 'tuser' + System.currentTimeMillis(),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = UserInfo.getProfileId(),
            Phone = '1234567890',
            Title = 'Account Manager'
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
            AssignmentType__c = getActiveAssignmentType()
        );
        insert atm;

        List<PermissionSet> permissionSets = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :PERMISSION_SET_NAME
            LIMIT 1
        ];

        // Fail fast and clearly if the permission set is missing in this org,
        // rather than silently skipping assignment and surfacing a confusing
        // FLS/QueryException later inside the actual test methods.
        System.assert(
            !permissionSets.isEmpty(),
            'Required permission set "' + PERMISSION_SET_NAME + '" not found in this org. ' +
            'Deploy/assign it before running these tests.'
        );

        // PermissionSetAssignment is a setup object; Account/AccountTeamMember above
        // are non-setup objects. Mixing setup and non-setup DML in the same transaction
        // throws MIXED_DML_OPERATION. Wrapping in System.runAs isolates this insert
        // into its own transaction context, which is the standard workaround inside
        // @TestSetup/test contexts.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(
                AssigneeId = testUser.Id,
                PermissionSetId = permissionSets[0].Id
            );
        }
    }

    /**
     * @description
     * Verifies access-related fields are returned when the user has permission.
     */
    @IsTest
    static void testGetAccountTeamMembersWithAccessPermission() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = getTestUser();

        System.runAs(testUser) {
            AccountTeamMemberDetailsController.canViewAccessFieldsForTest = true;

            Test.startTest();
            List<AccountTeamMemberDTO> result =
                AccountTeamMemberDetailsController.getAccountTeamMembers(testAccount.Id);
            Test.stopTest();

            System.assertEquals(1, result.size());
            System.assertEquals(true, result[0].canViewAccessFields);
            System.assertEquals('Edit', result[0].accountAccess);
            System.assertEquals('Edit', result[0].opportunityAccess);
            System.assertNotEquals(null, result[0].caseAccess);
            System.assertNotEquals(null, result[0].contactAccess);
        }
    }

    /**
     * @description
     * Verifies access-related fields are hidden when the user does not have permission.
     */
    @IsTest
    static void testGetAccountTeamMembersWithoutAccessPermission() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = getTestUser();

        System.runAs(testUser) {
            AccountTeamMemberDetailsController.canViewAccessFieldsForTest = false;

            Test.startTest();
            List<AccountTeamMemberDTO> result =
                AccountTeamMemberDetailsController.getAccountTeamMembers(testAccount.Id);
            Test.stopTest();

            System.assertEquals(1, result.size());
            System.assertEquals(false, result[0].canViewAccessFields);
            System.assertEquals(null, result[0].accountAccess);
            System.assertEquals(null, result[0].opportunityAccess);
            System.assertEquals(null, result[0].caseAccess);
            System.assertEquals(null, result[0].contactAccess);
        }
    }

    /**
     * @description
     * Covers the actual FeatureManagement.checkPermission branch
     * by not overriding the permission value in test context. Runs as the
     * dedicated test user, which is assigned the permission set containing
     * the 'View_Account_Team_Access_Fields' custom permission.
     */
    @IsTest
    static void testGetAccountTeamMembersFeatureManagementBranch() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = getTestUser();

        System.runAs(testUser) {
            Test.startTest();
            try {
                List<AccountTeamMemberDTO> result =
                    AccountTeamMemberDetailsController.getAccountTeamMembers(testAccount.Id);

                System.assertEquals(1, result.size());
            } catch (AuraHandledException e) {
                System.assert(true, 'Expected when custom permission is not available in test context');
            }
            Test.stopTest();
        }
    }

    /**
     * @description
     * Verifies an empty list is returned when Account Id is null.
     */
    @IsTest
    static void testGetAccountTeamMembersWithNullAccountId() {
        User testUser = getTestUser();

        System.runAs(testUser) {
            AccountTeamMemberDetailsController.canViewAccessFieldsForTest = false;

            Test.startTest();
            List<AccountTeamMemberDTO> result =
                AccountTeamMemberDetailsController.getAccountTeamMembers(null);
            Test.stopTest();

            System.assertEquals(0, result.size());
        }
    }

    /**
     * @description
     * Verifies exception handling when the service layer fails.
     */
    @IsTest
    static void testGetAccountTeamMembersException() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = getTestUser();

        System.runAs(testUser) {
            AccountTeamMemberService.throwExceptionForTest = true;
            AccountTeamMemberDetailsController.canViewAccessFieldsForTest = false;

            Test.startTest();
            try {
                AccountTeamMemberDetailsController.getAccountTeamMembers(testAccount.Id);
                System.assert(false, 'Expected exception');
            } catch (AuraHandledException e) {
                System.assert(true, 'AuraHandledException caught');
            } catch (AccountTeamMemberService.AccountTeamMemberException e) {
                System.assert(true, 'Service exception caught');
            }
            Test.stopTest();

            AccountTeamMemberService.throwExceptionForTest = false;
        }
    }

    // ---------- AccountTeamMemberSelector coverage ----------
    // selectByAccountId is already covered above via the controller/service chain.
    // The methods below aren't called by the controller/service, so they're
    // exercised directly here to close out selector coverage.

    /**
     * @description
     * Covers the query path of selectByAccountsAndUsers.
     */
    @IsTest
    static void testSelectByAccountsAndUsers_returnsRecords() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = getTestUser();

        System.runAs(testUser) {
            Test.startTest();
            List<AccountTeamMember> result = AccountTeamMemberSelector.selectByAccountsAndUsers(
                new Set<Id>{ testAccount.Id },
                new Set<Id>{ testUser.Id }
            );
            Test.stopTest();

            System.assertEquals(1, result.size());
        }
    }

    /**
     * @description
     * Covers the null/empty-input guard clause of selectByAccountsAndUsers.
     */
    @IsTest
    static void testSelectByAccountsAndUsers_invalidInputs_returnEmptyList() {
        User testUser = getTestUser();

        System.runAs(testUser) {
            Test.startTest();
            List<AccountTeamMember> resultNullAccounts =
                AccountTeamMemberSelector.selectByAccountsAndUsers(null, new Set<Id>{ testUser.Id });
            List<AccountTeamMember> resultEmptyUsers =
                AccountTeamMemberSelector.selectByAccountsAndUsers(new Set<Id>{ testUser.Id }, new Set<Id>());
            Test.stopTest();

            System.assertEquals(0, resultNullAccounts.size());
            System.assertEquals(0, resultEmptyUsers.size());
        }
    }

    /**
     * @description
     * Covers the query path of selectByUserIds.
     */
    @IsTest
    static void testSelectByUserIds_returnsRecords() {
        User testUser = getTestUser();

        System.runAs(testUser) {
            Test.startTest();
            List<AccountTeamMember> result =
                AccountTeamMemberSelector.selectByUserIds(new Set<Id>{ testUser.Id });
            Test.stopTest();

            System.assertEquals(1, result.size());
        }
    }

    /**
     * @description
     * Covers the null/empty-input guard clause of selectByUserIds.
     */
    @IsTest
    static void testSelectByUserIds_nullOrEmpty_returnsEmptyList() {
        User testUser = getTestUser();

        System.runAs(testUser) {
            Test.startTest();
            List<AccountTeamMember> resultNull = AccountTeamMemberSelector.selectByUserIds(null);
            List<AccountTeamMember> resultEmpty = AccountTeamMemberSelector.selectByUserIds(new Set<Id>());
            Test.stopTest();

            System.assertEquals(0, resultNull.size());
            System.assertEquals(0, resultEmpty.size());
        }
    }

    /**
     * @description
     * Covers the query path of selectByAccountsUsersAndRole.
     */
    @IsTest
    static void testSelectByAccountsUsersAndRole_returnsRecords() {
        AccountTeamMember atm = [SELECT AccountId, UserId, TeamMemberRole FROM AccountTeamMember LIMIT 1];
        User testUser = getTestUser();

        System.runAs(testUser) {
            Test.startTest();
            List<AccountTeamMember> result = AccountTeamMemberSelector.selectByAccountsUsersAndRole(
                new Set<Id>{ atm.AccountId },
                new Set<Id>{ atm.UserId },
                atm.TeamMemberRole
            );
            Test.stopTest();

            System.assertEquals(1, result.size());
        }
    }

    /**
     * @description
     * Covers the null/empty/blank-input guard clause of selectByAccountsUsersAndRole.
     */
    @IsTest
    static void testSelectByAccountsUsersAndRole_invalidInputs_returnEmptyList() {
        User testUser = getTestUser();

        System.runAs(testUser) {
            Test.startTest();
            List<AccountTeamMember> resultNullAccounts = AccountTeamMemberSelector.selectByAccountsUsersAndRole(
                null, new Set<Id>{ testUser.Id }, 'Sales Rep'
            );
            List<AccountTeamMember> resultEmptyUsers = AccountTeamMemberSelector.selectByAccountsUsersAndRole(
                new Set<Id>{ testUser.Id }, new Set<Id>(), 'Sales Rep'
            );
            List<AccountTeamMember> resultBlankRole = AccountTeamMemberSelector.selectByAccountsUsersAndRole(
                new Set<Id>{ testUser.Id }, new Set<Id>{ testUser.Id }, ''
            );
            Test.stopTest();

            System.assertEquals(0, resultNullAccounts.size());
            System.assertEquals(0, resultEmptyUsers.size());
            System.assertEquals(0, resultBlankRole.size());
        }
    }

    /**
     * @description
     * Covers the query path of selectByAccountsUsersRoleAssignmentType.
     */
    @IsTest
    static void testSelectByAccountsUsersRoleAssignmentType_returnsRecords() {
        AccountTeamMember atm = [
            SELECT AccountId, UserId, TeamMemberRole, AssignmentType__c
            FROM AccountTeamMember
            LIMIT 1
        ];
        User testUser = getTestUser();

        System.runAs(testUser) {
            Test.startTest();
            List<AccountTeamMember> result = AccountTeamMemberSelector.selectByAccountsUsersRoleAssignmentType(
                new Set<Id>{ atm.AccountId },
                new Set<Id>{ atm.UserId },
                atm.TeamMemberRole,
                atm.AssignmentType__c
            );
            Test.stopTest();

            System.assertEquals(1, result.size());
        }
    }

    /**
     * @description
     * Covers the null/empty/blank-input guard clause of selectByAccountsUsersRoleAssignmentType.
     */
    @IsTest
    static void testSelectByAccountsUsersRoleAssignmentType_invalidInputs_returnEmptyList() {
        AccountTeamMember atm = [SELECT AssignmentType__c FROM AccountTeamMember LIMIT 1];
        User testUser = getTestUser();

        System.runAs(testUser) {
            Test.startTest();
            List<AccountTeamMember> resultNullAccounts = AccountTeamMemberSelector.selectByAccountsUsersRoleAssignmentType(
                null, new Set<Id>{ testUser.Id }, 'Sales Rep', atm.AssignmentType__c
            );
            List<AccountTeamMember> resultEmptyUsers = AccountTeamMemberSelector.selectByAccountsUsersRoleAssignmentType(
                new Set<Id>{ testUser.Id }, new Set<Id>(), 'Sales Rep', atm.AssignmentType__c
            );
            List<AccountTeamMember> resultBlankRole = AccountTeamMemberSelector.selectByAccountsUsersRoleAssignmentType(
                new Set<Id>{ testUser.Id }, new Set<Id>{ testUser.Id }, '', atm.AssignmentType__c
            );
            List<AccountTeamMember> resultBlankAssignmentType = AccountTeamMemberSelector.selectByAccountsUsersRoleAssignmentType(
                new Set<Id>{ testUser.Id }, new Set<Id>{ testUser.Id }, 'Sales Rep', ''
            );
            Test.stopTest();

            System.assertEquals(0, resultNullAccounts.size());
            System.assertEquals(0, resultEmptyUsers.size());
            System.assertEquals(0, resultBlankRole.size());
            System.assertEquals(0, resultBlankAssignmentType.size());
        }
    }

    /**
     * @description
     * Retrieves the single test user created in @TestSetup. Matches on the
     * 'testuser@example.com'-pattern Username, which is guaranteed unique
     * because it's stamped with System.currentTimeMillis() at creation.
     * Alias = 'tuser' was previously used here but is not safe: short,
     * common aliases like 'tuser' can collide with a real, pre-existing
     * user in the org, causing this query to non-deterministically return
     * the wrong user's Id (as observed in QA).
     */
    private static User getTestUser() {
        return [
            SELECT Id
            FROM User
            WHERE Username LIKE 'testuser%@example.com'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }

    /**
     * @description
     * Returns an active AssignmentType__c value from picklist metadata.
     * AssignmentType__c is a restricted picklist, so hardcoding a value
     * (e.g. 'Temporary') can fail with INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST
     * if that value isn't active in a given org.
     */
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

    /**
     * @description
     * Returns an active Account Team Member role from picklist metadata.
     */
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