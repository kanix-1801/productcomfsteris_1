/**
 * @description GCL-326 - Covers every method on AccountTeamMemberSelector and
 *              AccountTeamMemberDTO, including the Life Sciences methods and the
 *              shared Healthcare methods, so this class alone reaches 100%.
 */
@IsTest
private class LSAccountTeamMemberSelectorDTOTest {

    private static final String PERMISSION_SET_NAME = 'SalesCustomerOpsSalesSupportSalesAdmin';
    private static final String LS_FIELD_PERMISSION_SET_NAME = 'LSReadOnlyAccessPS';

    @TestSetup
    static void setupData() {
        Account testAccount = new Account(
            Name = 'LS Selector DTO Account',
            SourceSystemID__c = 'LSATMDTO1'
        );
        insert testAccount;

        User testUser = new User(
            FirstName = 'LS',
            LastName = 'Selector',
            Email = 'lsselectordto' + System.currentTimeMillis() + '@example.com',
            Username = 'lsselectordto' + System.currentTimeMillis() + '@example.com',
            Alias = 'lsdto',
            CommunityNickname = 'lsdto' + System.currentTimeMillis(),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = UserInfo.getProfileId()
        );
        insert testUser;

        insert new AccountTeamMember(
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

        List<PermissionSet> permissionSets = [
            SELECT Id, Name
            FROM PermissionSet
            WHERE Name IN :new Set<String>{ PERMISSION_SET_NAME, LS_FIELD_PERMISSION_SET_NAME }
        ];
        Set<String> foundPermissionSetNames = new Set<String>();
        List<PermissionSetAssignment> permissionSetAssignments = new List<PermissionSetAssignment>();
        for (PermissionSet permissionSetRecord : permissionSets) {
            foundPermissionSetNames.add(permissionSetRecord.Name);
            permissionSetAssignments.add(new PermissionSetAssignment(
                AssigneeId = testUser.Id,
                PermissionSetId = permissionSetRecord.Id
            ));
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
     * @description Life Sciences selector returns the team member and the
     *              DTO maps Territory Number while leaving Healthcare fields empty.
     */
    @IsTest
    static void lifeSciencesSelectorAndDtoMapTerritoryNumber() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = getTestUser();

        System.runAs(testUser) {
            Test.startTest();
            List<AccountTeamMember> members =
                AccountTeamMemberSelector.selectByAccountIdForLifeSciences(testAccount.Id);
            Test.stopTest();

            System.assertEquals(1, members.size(), 'Expected the Life Sciences team member.');
            AccountTeamMemberDTO dto = AccountTeamMemberDTO.fromLifeSciencesAccountTeamMember(members[0]);

            System.assertEquals(members[0].Id, dto.id);
            System.assertEquals('L66301', dto.territoryCode);
            System.assertEquals(members[0].User.Name, dto.teamMember);
            System.assertEquals(members[0].TeamMemberRole, dto.teamRole);
            System.assertEquals(members[0].AssignmentType__c, dto.assignmentType);
            System.assertEquals(members[0].SalesCategoryDescription__c, dto.salesCategoryDescription);
            System.assertEquals(false, dto.canViewAccessFields);
            System.assertEquals(null, dto.email);
            System.assertEquals(null, dto.phone);
            System.assertEquals(null, dto.teamJobTitle);
            System.assertEquals(null, dto.salesCategoryCode);
            System.assertEquals(null, dto.expiryDate);
            System.assertEquals(null, dto.accountAccess);
        }
    }

    /**
     * @description Life Sciences selector returns no rows for a null Account Id.
     */
    @IsTest
    static void lifeSciencesSelectorReturnsEmptyForNullAccount() {
        Test.startTest();
        List<AccountTeamMember> members =
            AccountTeamMemberSelector.selectByAccountIdForLifeSciences(null);
        Test.stopTest();

        System.assertEquals(0, members.size());
    }

    /**
     * @description selectByAccountId covers both the access-field query and the
     *              query without those fields. The DTO constructor covers the
     *              access-field branch and the branch that leaves them empty.
     */
    @IsTest
    static void selectByAccountIdCoversBothAccessFieldBranches() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = getTestUser();

        System.runAs(testUser) {
            Test.startTest();
            List<AccountTeamMember> withAccess =
                AccountTeamMemberSelector.selectByAccountId(testAccount.Id, true);
            List<AccountTeamMember> withoutAccess =
                AccountTeamMemberSelector.selectByAccountId(testAccount.Id, false);
            Test.stopTest();

            System.assertEquals(1, withAccess.size());
            System.assertEquals(1, withoutAccess.size());

            AccountTeamMemberDTO visible =
                new AccountTeamMemberDTO(withAccess[0], true);
            AccountTeamMemberDTO hidden =
                new AccountTeamMemberDTO(withoutAccess[0], false);

            System.assertEquals(true, visible.canViewAccessFields);
            System.assertEquals('Edit', visible.accountAccess);
            System.assertEquals('Edit', visible.opportunityAccess);
            System.assertNotEquals(null, visible.caseAccess);
            System.assertNotEquals(null, visible.contactAccess);
            System.assertEquals(withAccess[0].User.Name, visible.teamMember);
            System.assertEquals(withAccess[0].TerritoryCode__c, visible.territoryCode);
            System.assertEquals(false, hidden.canViewAccessFields);
            System.assertEquals(null, hidden.accountAccess);
            System.assertEquals(null, hidden.caseAccess);
            System.assertEquals(null, hidden.contactAccess);
            System.assertEquals(null, hidden.opportunityAccess);
        }
    }

    /**
     * @description selectByAccountsAndUsers returns the team member and rejects empty input.
     */
    @IsTest
    static void selectByAccountsAndUsersCoversQueryAndGuard() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        User testUser = getTestUser();

        System.runAs(testUser) {
            Test.startTest();
            List<AccountTeamMember> found = AccountTeamMemberSelector.selectByAccountsAndUsers(
                new Set<Id>{ testAccount.Id },
                new Set<Id>{ testUser.Id }
            );
            List<AccountTeamMember> nullAccounts = AccountTeamMemberSelector.selectByAccountsAndUsers(
                null, new Set<Id>{ testUser.Id }
            );
            List<AccountTeamMember> emptyAccounts = AccountTeamMemberSelector.selectByAccountsAndUsers(
                new Set<Id>(), new Set<Id>{ testUser.Id }
            );
            List<AccountTeamMember> nullUsers = AccountTeamMemberSelector.selectByAccountsAndUsers(
                new Set<Id>{ testAccount.Id }, null
            );
            List<AccountTeamMember> emptyUsers = AccountTeamMemberSelector.selectByAccountsAndUsers(
                new Set<Id>{ testAccount.Id }, new Set<Id>()
            );
            Test.stopTest();

            System.assertEquals(1, found.size());
            System.assertEquals(0, nullAccounts.size());
            System.assertEquals(0, emptyAccounts.size());
            System.assertEquals(0, nullUsers.size());
            System.assertEquals(0, emptyUsers.size());
        }
    }

    /**
     * @description selectByUserIds returns the team member and rejects null or empty input.
     */
    @IsTest
    static void selectByUserIdsCoversQueryAndGuard() {
        User testUser = getTestUser();

        System.runAs(testUser) {
            Test.startTest();
            List<AccountTeamMember> found =
                AccountTeamMemberSelector.selectByUserIds(new Set<Id>{ testUser.Id });
            List<AccountTeamMember> nullUsers = AccountTeamMemberSelector.selectByUserIds(null);
            List<AccountTeamMember> emptyUsers = AccountTeamMemberSelector.selectByUserIds(new Set<Id>());
            Test.stopTest();

            System.assertEquals(1, found.size());
            System.assertEquals(0, nullUsers.size());
            System.assertEquals(0, emptyUsers.size());
        }
    }

    /**
     * @description selectByAccountsUsersAndRole returns the matching row and rejects bad input.
     */
    @IsTest
    static void selectByAccountsUsersAndRoleCoversQueryAndGuard() {
        AccountTeamMember member = [
            SELECT AccountId, UserId, TeamMemberRole
            FROM AccountTeamMember
            LIMIT 1
        ];
        User testUser = getTestUser();

        System.runAs(testUser) {
            Test.startTest();
            List<AccountTeamMember> found = AccountTeamMemberSelector.selectByAccountsUsersAndRole(
                new Set<Id>{ member.AccountId },
                new Set<Id>{ member.UserId },
                member.TeamMemberRole
            );
            List<AccountTeamMember> nullAccounts = AccountTeamMemberSelector.selectByAccountsUsersAndRole(
                null, new Set<Id>{ testUser.Id }, member.TeamMemberRole
            );
            List<AccountTeamMember> emptyAccounts = AccountTeamMemberSelector.selectByAccountsUsersAndRole(
                new Set<Id>(), new Set<Id>{ testUser.Id }, member.TeamMemberRole
            );
            List<AccountTeamMember> emptyUsers = AccountTeamMemberSelector.selectByAccountsUsersAndRole(
                new Set<Id>{ member.AccountId }, new Set<Id>(), member.TeamMemberRole
            );
            List<AccountTeamMember> blankRole = AccountTeamMemberSelector.selectByAccountsUsersAndRole(
                new Set<Id>{ member.AccountId }, new Set<Id>{ member.UserId }, ' '
            );
            Test.stopTest();

            System.assertEquals(1, found.size());
            System.assertEquals(0, nullAccounts.size());
            System.assertEquals(0, emptyAccounts.size());
            System.assertEquals(0, emptyUsers.size());
            System.assertEquals(0, blankRole.size());
        }
    }

    /**
     * @description selectByAccountsUsersRoleAssignmentType returns the matching row
     *              and rejects each invalid argument.
     */
    @IsTest
    static void selectByAccountsUsersRoleAndAssignmentTypeCoversQueryAndGuard() {
        AccountTeamMember member = [
            SELECT AccountId, UserId, TeamMemberRole, AssignmentType__c
            FROM AccountTeamMember
            LIMIT 1
        ];
        User testUser = getTestUser();

        System.runAs(testUser) {
            Test.startTest();
            List<AccountTeamMember> found = AccountTeamMemberSelector.selectByAccountsUsersRoleAssignmentType(
                new Set<Id>{ member.AccountId },
                new Set<Id>{ member.UserId },
                member.TeamMemberRole,
                member.AssignmentType__c
            );
            List<AccountTeamMember> nullAccounts = AccountTeamMemberSelector.selectByAccountsUsersRoleAssignmentType(
                null, new Set<Id>{ testUser.Id }, member.TeamMemberRole, member.AssignmentType__c
            );
            List<AccountTeamMember> emptyUsers = AccountTeamMemberSelector.selectByAccountsUsersRoleAssignmentType(
                new Set<Id>{ member.AccountId }, new Set<Id>(), member.TeamMemberRole, member.AssignmentType__c
            );
            List<AccountTeamMember> blankRole = AccountTeamMemberSelector.selectByAccountsUsersRoleAssignmentType(
                new Set<Id>{ member.AccountId },
                new Set<Id>{ member.UserId },
                '',
                member.AssignmentType__c
            );
            List<AccountTeamMember> blankAssignment = AccountTeamMemberSelector.selectByAccountsUsersRoleAssignmentType(
                new Set<Id>{ member.AccountId },
                new Set<Id>{ member.UserId },
                member.TeamMemberRole,
                ''
            );
            Test.stopTest();

            System.assertEquals(1, found.size());
            System.assertEquals(0, nullAccounts.size());
            System.assertEquals(0, emptyUsers.size());
            System.assertEquals(0, blankRole.size());
            System.assertEquals(0, blankAssignment.size());
        }
    }

    /**
     * @description Life Sciences selector returns no rows when the Account has no team.
     */
    @IsTest
    static void lifeSciencesSelectorReturnsEmptyWhenAccountHasNoTeam() {
        Account emptyAccount = new Account(
            Name = 'LS Selector Empty Account',
            SourceSystemID__c = 'LSATMDTO2'
        );
        insert emptyAccount;

        Test.startTest();
        List<AccountTeamMember> members =
            AccountTeamMemberSelector.selectByAccountIdForLifeSciences(emptyAccount.Id);
        Test.stopTest();

        System.assertEquals(0, members.size());
    }

    private static User getTestUser() {
        return [
            SELECT Id
            FROM User
            WHERE Username LIKE 'lsselectordto%@example.com'
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