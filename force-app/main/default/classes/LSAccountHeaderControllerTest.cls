/**
 * @author PWC Developer
 * @date 2026/10/30
 *
 * @group Life Sciences Account
 *
 * @description
 * GCL-100 - Tests Full and Base for the Life Sciences Customer 360 panes.
 * Covers an owner who is not on the team, an Account Team member, a user on
 * neither, a missing Account Id, and a query failure.
 */
@IsTest(SeeAllData=false)
private class LSAccountHeaderControllerTest {

    /**
     * @description GCL-100 - The Account owner gets Full even when not on the Account Team.
     */
    @IsTest
    static void ownerSeesFull() {
        /********************************************
         * SETUP
         ********************************************/
        User ownerUser = createUser('owner');
        insert ownerUser;

        /********************************************
         * WHEN
         ********************************************/
        System.runAs(ownerUser) {
            Account accountRecord = insertAccount(ownerUser.Id, 'Customer');
            LSAccountHeaderService.HeaderView headerView =
                LSAccountHeaderController.getHeaderView(accountRecord.Id);

            System.assertEquals(LSAccountHeaderService.ACCESS_FULL, headerView.accessLevel);
            System.assertEquals(false, headerView.showHeaderOnly);
        }
    }

    /**
     * @description GCL-100 - A user who is not the owner and not on the Account Team gets Base.
     */
    @IsTest
    static void userOutsideTheTeamSeesBase() {
        /********************************************
         * SETUP
         ********************************************/
        User ownerUser = createUser('owner');
        User outsideUser = createUser('outside');
        insert new List<User>{ ownerUser, outsideUser };

        Account accountRecord;
        System.runAs(ownerUser) {
            accountRecord = insertAccount(ownerUser.Id, 'Customer');
        }

        /********************************************
         * WHEN
         ********************************************/
        System.runAs(outsideUser) {
            LSAccountHeaderService.HeaderView headerView =
                LSAccountHeaderController.getHeaderView(accountRecord.Id);

            System.assertEquals(LSAccountHeaderService.ACCESS_BASE, headerView.accessLevel);
            System.assertEquals(true, headerView.showHeaderOnly);
        }
    }

    /**
     * @description GCL-100 - An Account Team member gets Full.
     */
    @IsTest
    static void teamMemberSeesFull() {
        /********************************************
         * SETUP
         ********************************************/
        User ownerUser = createUser('owner');
        User teamUser = createUser('team');
        insert new List<User>{ ownerUser, teamUser };

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

        /********************************************
         * WHEN
         ********************************************/
        System.runAs(teamUser) {
            LSAccountHeaderService.HeaderView headerView =
                LSAccountHeaderController.getHeaderView(accountRecord.Id);

            System.assertEquals(LSAccountHeaderService.ACCESS_FULL, headerView.accessLevel);
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
            Account accountRecord = insertAccount(ownerUser.Id, 'Customer');
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
    /**
     * @description GCL-100 - A non-Customer record type is never reduced to Base.
     */
    @IsTest
    static void prospectOutsideTheTeamSeesFull() {
        User ownerUser = createUser('owner');
        User outsideUser = createUser('outside');
        insert new List<User>{ ownerUser, outsideUser };

        Account accountRecord;
        System.runAs(ownerUser) {
            accountRecord = insertAccount(ownerUser.Id, 'Prospect');
        }

        System.runAs(outsideUser) {
            LSAccountHeaderService.HeaderView headerView =
                LSAccountHeaderController.getHeaderView(accountRecord.Id);

            System.assertEquals(LSAccountHeaderService.ACCESS_FULL, headerView.accessLevel);
            System.assertEquals(false, headerView.showHeaderOnly);
        }
    }

    @IsTest
    static void selectorReturnsEmptyForNullId() {
        System.assertEquals(0, LSAccountHeaderSelector.selectById(null).size());
        System.assertEquals(0, LSAccountHeaderSelector.selectCurrentUserTeamMember(null).size());
    }

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

    private static Id recordTypeId(String developerName) {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get(developerName)
            .getRecordTypeId();
    }

    private static String operatingUnitValue() {
        for (Schema.PicklistEntry entry : Account.OrgIDs__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
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