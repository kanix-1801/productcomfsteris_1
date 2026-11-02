/**
 * @author Surya
 * @date 2026/10/30
 *
 * @group Life Sciences Account
 *
 * @description
 * GCL-100 - Tests the out-of-territory Account header decision. Covers the owner,
 * an Account Team member, a user on neither, a missing Account Id, and a query failure.
 */
@IsTest(SeeAllData=false)
private class LSAccountHeaderControllerTest {

    /**
     * @description GCL-100 - The Account owner keeps the standard page.
     */
    @IsTest
    static void ownerDoesNotSeeHeaderOnly() {
        /********************************************
         * SETUP
         ********************************************/
        User ownerUser = createUser('owner');
        insert ownerUser;

        /********************************************
         * WHEN
         ********************************************/
        System.runAs(ownerUser) {
            Account accountRecord = insertAccount(ownerUser.Id);
            LSAccountHeaderService.HeaderView headerView =
                LSAccountHeaderController.getHeaderView(accountRecord.Id);

            System.assertEquals(false, headerView.showHeaderOnly);
        }
    }

    /**
     * @description GCL-100 - A user who is not the owner and not on the Account Team sees the header.
     */
    @IsTest
    static void outsiderSeesHeaderOnly() {
        /********************************************
         * SETUP
         ********************************************/
        User ownerUser = createUser('owner');
        User outsideUser = createUser('outside');
        insert new List<User>{ ownerUser, outsideUser };

        Account accountRecord;
        System.runAs(ownerUser) {
            accountRecord = insertAccount(ownerUser.Id);
        }

        /********************************************
         * WHEN
         ********************************************/
        System.runAs(outsideUser) {
            LSAccountHeaderService.HeaderView headerView =
                LSAccountHeaderController.getHeaderView(accountRecord.Id);

            System.assertEquals(true, headerView.showHeaderOnly);
        }
    }

    /**
     * @description GCL-100 - Joining the Account Team removes the header-only view.
     */
    @IsTest
    static void teamMemberDoesNotSeeHeaderOnly() {
        /********************************************
         * SETUP
         ********************************************/
        User ownerUser = createUser('owner');
        User teamUser = createUser('team');
        insert new List<User>{ ownerUser, teamUser };

        Account accountRecord;
        System.runAs(ownerUser) {
            accountRecord = insertAccount(ownerUser.Id);
            insert new AccountTeamMember(
                AccountId = accountRecord.Id,
                UserId = teamUser.Id,
                TeamMemberRole = accountTeamRole(),
                AccountAccessLevel = 'Read'
            );
        }

        /********************************************
         * WHEN
         ********************************************/
        System.runAs(teamUser) {
            LSAccountHeaderService.HeaderView headerView =
                LSAccountHeaderController.getHeaderView(accountRecord.Id);

            System.assertEquals(false, headerView.showHeaderOnly);
        }
    }

    /**
     * @description GCL-100 - The page cannot ask for a header without an Account Id.
     */
    @IsTest
    static void nullAccountIdIsRejected() {
        try {
            LSAccountHeaderController.getHeaderView(null);
            System.assert(false, 'A missing Account Id should be rejected.');
        } catch (AuraHandledException expectedException) {
            System.assertNotEquals(null, expectedException);
        }
    }

    /**
     * @description GCL-100 - A selector failure is returned as a handled error.
     */
    @IsTest
    static void unexpectedErrorIsHandled() {
        User ownerUser = createUser('owner');
        insert ownerUser;

        System.runAs(ownerUser) {
            Account accountRecord = insertAccount(ownerUser.Id);
            LSAccountHeaderService.throwTestException = true;

            try {
                LSAccountHeaderController.getHeaderView(accountRecord.Id);
                System.assert(false, 'A selector failure should be rejected.');
            } catch (AuraHandledException expectedException) {
                System.assertNotEquals(null, expectedException);
            }
        }
    }

    /**
     * @description GCL-100 - A missing Account Id does not run a query.
     */
    @IsTest
    static void selectorReturnsEmptyForNullId() {
        System.assertEquals(0, LSAccountHeaderSelector.selectById(null).size());
        System.assertEquals(0, LSAccountHeaderSelector.selectCurrentUserTeamMember(null).size());
    }

    private static Account insertAccount(Id ownerId) {
        Account accountRecord = new Account(
            Name = 'ADC Tech',
            SourceSystemID__c = uniqueToken('acct'),
            OwnerId = ownerId
        );
        insert accountRecord;
        return accountRecord;
    }

    private static User createUser(String seed) {
        String token = uniqueToken(seed);
        return new User(
            Alias = ('lsh' + seed).left(8),
            Email = token + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Header ' + seed,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfileId(),
            UserRoleId = internalRoleId(),
            TimeZoneSidKey = 'America/New_York',
            Username = token + '@example.com'
        );
    }

    private static Id adminProfileId() {
        return [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
    }

    private static Id internalRoleId() {
        return [SELECT Id FROM UserRole WHERE PortalType = 'None' LIMIT 1].Id;
    }

    private static String accountTeamRole() {
        List<Schema.PicklistEntry> roles =
            AccountTeamMember.TeamMemberRole.getDescribe().getPicklistValues();
        return roles.isEmpty() ? 'Sales Rep' : roles[0].getValue();
    }

    private static String uniqueToken(String seed) {
        return 'lsh' + seed + String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }
}