/**
 * @author PWC Developer
 * @date 2026/10/30
 *
 * @group Life Sciences Account
 *
 * @description
 * GCL-100 - Tests Full and Base for the Life Sciences Customer 360 panes.
 * Covers an owner who is not on the team, an Account Team member, a user on
 * neither, a Prospect, a missing Account Id, and a query failure.
 */
@IsTest(SeeAllData=false)
private class LSAccountHeaderControllerTest {

    /**
     * @description GCL-100 - Creates the owner, outside user, and team user shared by the tests.
     */
    @TestSetup
    static void setupData() {
        insert new List<User>{
            createUser('owner'),
            createUser('outside'),
            createUser('team')
        };
    }

    /**
     * @description GCL-100 - The Account owner gets Full even when not on the Account Team.
     */
    @IsTest
    static void testGetHeaderViewOwnerSeesFull() {
        /********************************************
         * SETUP
         ********************************************/
        User ownerUser = userBySeed('owner');

        /********************************************
         * GIVEN
         ********************************************/
        Account accountRecord;
        System.runAs(ownerUser) {
            accountRecord = insertAccount(ownerUser.Id, 'Customer');
        }
        System.assertEquals(
            ownerUser.Id,
            accountRecord.OwnerId,
            'The owner should own the Customer account before the check.'
        );
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM AccountTeamMember
                WHERE AccountId = :accountRecord.Id
                AND UserId = :ownerUser.Id
            ],
            'The owner should not be on the Account Team before the check.'
        );

        /********************************************
         * WHEN
         ********************************************/
        LSAccountHeaderService.HeaderView headerView;
        Test.startTest();
        System.runAs(ownerUser) {
            headerView = LSAccountHeaderController.getHeaderView(accountRecord.Id);
        }
        Test.stopTest();

        /********************************************
         * THEN
         ********************************************/
        System.assertEquals(
            LSAccountHeaderService.ACCESS_FULL,
            headerView.accessLevel,
            'The Account owner should get Full.'
        );
        System.assertEquals(false, headerView.showHeaderOnly, 'The owner should not see the short header.');
    }

    /**
     * @description GCL-100 - A user who is not the owner and not on the Account Team gets Base.
     */
    @IsTest
    static void testGetHeaderViewUserOutsideTeamSeesBase() {
        /********************************************
         * SETUP
         ********************************************/
        User ownerUser = userBySeed('owner');
        User outsideUser = userBySeed('outside');

        /********************************************
         * GIVEN
         ********************************************/
        Account accountRecord;
        System.runAs(ownerUser) {
            accountRecord = insertAccount(ownerUser.Id, 'Customer');
        }
        System.assertNotEquals(
            outsideUser.Id,
            accountRecord.OwnerId,
            'The outside user should not own the Customer account.'
        );

        /********************************************
         * WHEN
         ********************************************/
        LSAccountHeaderService.HeaderView headerView;
        Test.startTest();
        System.runAs(outsideUser) {
            headerView = LSAccountHeaderController.getHeaderView(accountRecord.Id);
        }
        Test.stopTest();

        /********************************************
         * THEN
         ********************************************/
        System.assertEquals(
            LSAccountHeaderService.ACCESS_BASE,
            headerView.accessLevel,
            'A user outside the Account Team should get Base.'
        );
        System.assertEquals(true, headerView.showHeaderOnly, 'The outside user should see the short header.');
    }

    /**
     * @description GCL-100 - An Account Team member gets Full.
     */
    @IsTest
    static void testGetHeaderViewTeamMemberSeesFull() {
        /********************************************
         * SETUP
         ********************************************/
        User ownerUser = userBySeed('owner');
        User teamUser = userBySeed('team');

        /********************************************
         * GIVEN
         ********************************************/
        Account accountRecord;
        System.runAs(ownerUser) {
            accountRecord = insertAccount(ownerUser.Id, 'Customer');
            insert new AccountTeamMember(
                AccountId = accountRecord.Id,
                UserId = teamUser.Id,
                TeamMemberRole = accountTeamRole(),
                AccountAccessLevel = 'Read'
            );
        }
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM AccountTeamMember
                WHERE AccountId = :accountRecord.Id
                AND UserId = :teamUser.Id
            ],
            'The team user should be on the Account Team before the check.'
        );

        /********************************************
         * WHEN
         ********************************************/
        LSAccountHeaderService.HeaderView headerView;
        Test.startTest();
        System.runAs(teamUser) {
            headerView = LSAccountHeaderController.getHeaderView(accountRecord.Id);
        }
        Test.stopTest();

        /********************************************
         * THEN
         ********************************************/
        System.assertEquals(
            LSAccountHeaderService.ACCESS_FULL,
            headerView.accessLevel,
            'An Account Team member should get Full.'
        );
        System.assertEquals(false, headerView.showHeaderOnly, 'A team member should not see the short header.');
    }

    /**
     * @description GCL-100 - The page cannot ask for a header without an Account Id.
     */
    @IsTest
    static void testGetHeaderViewNullAccountIdIsRejected() {
        /********************************************
         * SETUP
         ********************************************/
        Boolean rejected = false;

        /********************************************
         * GIVEN
         ********************************************/
        Id accountId = null;
        System.assertEquals(null, accountId, 'The Account Id should be missing before the check.');

        /********************************************
         * WHEN
         ********************************************/
        Test.startTest();
        try {
            LSAccountHeaderController.getHeaderView(accountId);
        } catch (AuraHandledException expectedException) {
            rejected = true;
        }
        Test.stopTest();

        /********************************************
         * THEN
         ********************************************/
        System.assertEquals(true, rejected, 'A missing Account Id should be rejected.');
    }

    /**
     * @description GCL-100 - A selector failure is returned as a handled error.
     */
    @IsTest
    static void testGetHeaderViewUnexpectedErrorIsHandled() {
        /********************************************
         * SETUP
         ********************************************/
        User ownerUser = userBySeed('owner');
        Boolean rejected = false;

        /********************************************
         * GIVEN
         ********************************************/
        Account accountRecord;
        System.runAs(ownerUser) {
            accountRecord = insertAccount(ownerUser.Id, 'Customer');
        }
        LSAccountHeaderService.throwTestException = true;

        /********************************************
         * WHEN
         ********************************************/
        Test.startTest();
        System.runAs(ownerUser) {
            try {
                LSAccountHeaderController.getHeaderView(accountRecord.Id);
            } catch (AuraHandledException expectedException) {
                rejected = true;
            }
        }
        Test.stopTest();

        /********************************************
         * THEN
         ********************************************/
        System.assertEquals(true, rejected, 'A selector failure should be rejected.');
    }

    /**
     * @description GCL-100 - A non-Customer record type is never reduced to Base.
     */
    @IsTest
    static void testGetHeaderViewProspectOutsideTeamSeesFull() {
        /********************************************
         * SETUP
         ********************************************/
        User ownerUser = userBySeed('owner');
        User outsideUser = userBySeed('outside');

        /********************************************
         * GIVEN
         ********************************************/
        Account accountRecord;
        System.runAs(ownerUser) {
            accountRecord = insertAccount(ownerUser.Id, 'Prospect');
        }
        System.assertNotEquals(
            outsideUser.Id,
            accountRecord.OwnerId,
            'The outside user should not own the Prospect.'
        );

        /********************************************
         * WHEN
         ********************************************/
        LSAccountHeaderService.HeaderView headerView;
        Test.startTest();
        System.runAs(outsideUser) {
            headerView = LSAccountHeaderController.getHeaderView(accountRecord.Id);
        }
        Test.stopTest();

        /********************************************
         * THEN
         ********************************************/
        System.assertEquals(
            LSAccountHeaderService.ACCESS_FULL,
            headerView.accessLevel,
            'A Prospect should stay Full for a user outside the Account Team.'
        );
        System.assertEquals(false, headerView.showHeaderOnly, 'A Prospect should not use the short header.');
    }

    /**
     * @description GCL-100 - A missing Account Id does not run a query.
     */
    @IsTest
    static void testSelectByIdNullIdReturnsEmpty() {
        /********************************************
         * GIVEN
         ********************************************/
        Id accountId = null;

        /********************************************
         * WHEN
         ********************************************/
        Test.startTest();
        Integer accountCount = AccountSelector.selectById(accountId).size();
        Integer teamCount = AccountTeamMemberSelector.selectCurrentUserTeamMember(accountId).size();
        Test.stopTest();

        /********************************************
         * THEN
         ********************************************/
        System.assertEquals(0, accountCount, 'A missing Account Id should not return an Account.');
        System.assertEquals(0, teamCount, 'A missing Account Id should not return an Account Team row.');
    }

    /**
     * @description GCL-100 - Inserts an Account for the supplied owner and record type.
     * @param ownerId User who owns the Account.
     * @param recordTypeDeveloperName Account record type developer name.
     * @return The inserted Account.
     */
    private static Account insertAccount(Id ownerId, String recordTypeDeveloperName) {
        Account accountRecord = new Account(
            Name = 'ADC Tech',
            SourceSystemID__c = uniqueToken('acct'),
            OwnerId = ownerId,
            RecordTypeId = recordTypeId(recordTypeDeveloperName)
        );
        if (recordTypeDeveloperName == 'Prospect') {
            accountRecord.BillingStreet = '2210 Stockton Street';
            accountRecord.BillingCity = 'San Francisco';
            accountRecord.BillingStateCode = 'CA';
            accountRecord.BillingPostalCode = '94133';
            accountRecord.BillingCountryCode = 'US';
            accountRecord.OrgIDs__c = operatingUnitValue();
        }
        insert accountRecord;
        return accountRecord;
    }

    /**
     * @description GCL-100 - Builds a System Administrator user. The caller inserts it.
     * @param seed Short name used in the username and last name.
     * @return The unsaved User.
     */
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

    /**
     * @description GCL-100 - Returns the user created in the test setup.
     * @param seed Short name used when the user was created.
     * @return The saved User.
     */
    private static User userBySeed(String seed) {
        return [
            SELECT Id
            FROM User
            WHERE LastName = :('Header ' + seed)
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }

    /**
     * @description GCL-100 - Returns the System Administrator profile Id.
     * @return Profile Id.
     */
    private static Id adminProfileId() {
        return [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
    }

    /**
     * @description GCL-100 - Returns an internal role so the test user can own Accounts.
     * @return UserRole Id.
     */
    private static Id internalRoleId() {
        return [SELECT Id FROM UserRole WHERE PortalType = 'None' LIMIT 1].Id;
    }

    /**
     * @description GCL-100 - Returns the Account record type Id for a developer name.
     * @param developerName Account record type developer name.
     * @return Record type Id.
     */
    private static Id recordTypeId(String developerName) {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get(developerName)
            .getRecordTypeId();
    }

    /**
     * @description GCL-100 - Returns an active Operating Unit so the Prospect insert skips the User Org Id query.
     * @return Active Account.OrgIDs__c value, or null when none is active.
     */
    private static String operatingUnitValue() {
        for (Schema.PicklistEntry entry : Account.OrgIDs__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }

    /**
     * @description GCL-100 - Returns an active Account Team role.
     * @return Team member role value.
     */
    private static String accountTeamRole() {
        List<Schema.PicklistEntry> roles =
            AccountTeamMember.TeamMemberRole.getDescribe().getPicklistValues();
        return roles.isEmpty() ? 'Sales Rep' : roles[0].getValue();
    }

    /**
     * @description GCL-100 - Builds a unique token for usernames and source system ids.
     * @param seed Short prefix for the token.
     * @return Unique token.
     */
    private static String uniqueToken(String seed) {
        return 'lsh' + seed + String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }
}