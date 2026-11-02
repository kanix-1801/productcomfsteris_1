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
            IsTemporaryAccess__c = true
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
     * @description Returns the Life Sciences panel fields, including Temporary Access
     *              from IsTemporaryAccess__c, and leaves Healthcare-only fields empty.
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
            System.assertEquals(true, result[0].temporaryAccessIndicator);
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