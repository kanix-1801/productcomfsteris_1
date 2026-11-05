/**
 * @author PWC Developer
 * @date 2026/11/04
 *
 * @group Life Sciences Opportunity
 *
 * @description
 * GCL-73 - Tests the Life Sciences Opportunity owner check. The current owner,
 * a Business System Admin, and a parent role can change Owner. A peer cannot.
 * System Administrator is outside the Life Sciences Sales profile.
 */
@IsTest(SeeAllData=false)
private class LSOpportunityOwnerServiceTest {

    private static final String OWNER_LAST_NAME = 'GCL73 Owner';
    private static final String PEER_LAST_NAME = 'GCL73 Peer';
    private static final String MANAGER_LAST_NAME = 'GCL73 Manager';
    private static final String ADMIN_PERMISSION_LAST_NAME = 'GCL73 BSA';
    private static final String NEW_OWNER_LAST_NAME = 'GCL73 New Owner';

    /**
     * @description
     * GCL-73 - Creates the role hierarchy and the Life Sciences Sales users.
     *
     * @return void
     */
    @TestSetup
    static void setupUsers() {
        String token = uniqueToken();
        UserRole managerRole = new UserRole(
            Name = 'GCL73 Manager ' + token,
            DeveloperName = 'GCL73_Manager_' + token
        );
        insert managerRole;
        UserRole ownerRole = new UserRole(
            Name = 'GCL73 Owner ' + token,
            DeveloperName = 'GCL73_Owner_' + token,
            ParentRoleId = managerRole.Id
        );
        UserRole otherRole = new UserRole(
            Name = 'GCL73 Other ' + token,
            DeveloperName = 'GCL73_Other_' + token
        );
        insert new List<UserRole>{ ownerRole, otherRole };

        User ownerUser = newUser(OWNER_LAST_NAME, 'Life Sciences Sales', ownerRole.Id, token);
        User peerUser = newUser(PEER_LAST_NAME, 'Life Sciences Sales', ownerRole.Id, token);
        User managerUser = newUser(MANAGER_LAST_NAME, 'Life Sciences Sales', managerRole.Id, token);
        User businessSystemAdmin = newUser(ADMIN_PERMISSION_LAST_NAME, 'Life Sciences Sales', otherRole.Id, token);
        User newOwner = newUser(NEW_OWNER_LAST_NAME, 'Life Sciences Sales', otherRole.Id, token);
        insert new List<User>{ ownerUser, peerUser, managerUser, businessSystemAdmin, newOwner };

        PermissionSet businessSystemAdminPermissionSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :LSOpportunityOwnerService.BUSINESS_SYSTEM_ADMIN_PERMISSION_SET
            LIMIT 1
        ];
        insert new PermissionSetAssignment(
            AssigneeId = businessSystemAdmin.Id,
            PermissionSetId = businessSystemAdminPermissionSet.Id
        );
    }

    /**
     * @description
     * GCL-73 - A null or empty save does not query and does not throw.
     */
    @IsTest
    static void nullInputDoesNotThrow() {
        LSOpportunityOwnerService.validateOwnerChange(null, null);
        LSOpportunityOwnerService.validateOwnerChange(new List<Opportunity>(), new Map<Id, Opportunity>());
        System.assert(true, 'Empty owner validation should return without an exception.');
    }

    /**
     * @description
     * GCL-73 - The current owner can assign a new owner.
     */
    @IsTest
    static void currentOwnerCanChangeOwner() {
        User ownerUser = userByLastName(OWNER_LAST_NAME);
        User newOwner = userByLastName(NEW_OWNER_LAST_NAME);
        Opportunity opportunityRecord = insertLifeSciencesOpportunity(ownerUser);

        Test.startTest();
        changeOwner(ownerUser, opportunityRecord.Id, newOwner.Id, false);
        Test.stopTest();

        System.assertEquals(newOwner.Id, refreshedOwnerId(opportunityRecord.Id));
    }

    /**
     * @description
     * GCL-73 - A Life Sciences Sales user in the same role cannot change Owner.
     */
    @IsTest
    static void peerInSameRoleIsBlocked() {
        User ownerUser = userByLastName(OWNER_LAST_NAME);
        User peerUser = userByLastName(PEER_LAST_NAME);
        User newOwner = userByLastName(NEW_OWNER_LAST_NAME);
        Opportunity opportunityRecord = insertLifeSciencesOpportunity(ownerUser);
        shareEdit(opportunityRecord.Id, peerUser.Id);

        Test.startTest();
        try {
            changeOwner(peerUser, opportunityRecord.Id, newOwner.Id, false);
            System.assert(false, 'A peer in the same role should be blocked.');
        } catch (DmlException exceptionValue) {
            System.assert(
                exceptionValue.getDmlMessage(0).contains(LSOpportunityOwnerService.OWNER_CHANGE_ERROR),
                exceptionValue.getDmlMessage(0)
            );
        }
        Test.stopTest();

        System.assertEquals(ownerUser.Id, refreshedOwnerId(opportunityRecord.Id));
    }

    /**
     * @description
     * GCL-73 - A user in the parent role can change Owner.
     */
    @IsTest
    static void parentRoleCanChangeOwner() {
        User managerUser = userByLastName(MANAGER_LAST_NAME);
        User newOwner = userByLastName(NEW_OWNER_LAST_NAME);
        Opportunity opportunityRecord = insertLifeSciencesOpportunity(userByLastName(OWNER_LAST_NAME));
        shareEdit(opportunityRecord.Id, managerUser.Id);

        Test.startTest();
        changeOwner(managerUser, opportunityRecord.Id, newOwner.Id, false);
        Test.stopTest();

        System.assertEquals(newOwner.Id, refreshedOwnerId(opportunityRecord.Id));
    }

    /**
     * @description
     * GCL-73 - LSBusinessSysAdminPS can change Owner from outside the owner role.
     */
    @IsTest
    static void businessSystemAdminCanChangeOwner() {
        User businessSystemAdmin = userByLastName(ADMIN_PERMISSION_LAST_NAME);
        User newOwner = userByLastName(NEW_OWNER_LAST_NAME);
        Opportunity opportunityRecord = insertLifeSciencesOpportunity(userByLastName(OWNER_LAST_NAME));
        shareEdit(opportunityRecord.Id, businessSystemAdmin.Id);

        Test.startTest();
        changeOwner(businessSystemAdmin, opportunityRecord.Id, newOwner.Id, false);
        Test.stopTest();

        System.assertEquals(newOwner.Id, refreshedOwnerId(opportunityRecord.Id));
    }

    /**
     * @description
     * GCL-73 - BypassValidations__c skips the owner check for a data load.
     */
    @IsTest
    static void bypassAllowsOwnerChange() {
        User ownerUser = userByLastName(OWNER_LAST_NAME);
        User peerUser = userByLastName(PEER_LAST_NAME);
        User newOwner = userByLastName(NEW_OWNER_LAST_NAME);
        Opportunity opportunityRecord = insertLifeSciencesOpportunity(ownerUser);
        shareEdit(opportunityRecord.Id, peerUser.Id);

        Test.startTest();
        changeOwner(peerUser, opportunityRecord.Id, newOwner.Id, true);
        Test.stopTest();

        System.assertEquals(newOwner.Id, refreshedOwnerId(opportunityRecord.Id));
    }

    /**
     * @description
     * GCL-73 - System Administrator is outside the Life Sciences Sales check.
     */
    @IsTest
    static void systemAdminIsNotBlocked() {
        User adminUser = newUser('GCL73 Admin', 'System Administrator', null, uniqueToken());
        insert adminUser;
        User newOwner = userByLastName(NEW_OWNER_LAST_NAME);
        Opportunity opportunityRecord = insertLifeSciencesOpportunity(userByLastName(OWNER_LAST_NAME));

        Test.startTest();
        changeOwner(adminUser, opportunityRecord.Id, newOwner.Id, false);
        Test.stopTest();

        System.assertEquals(newOwner.Id, refreshedOwnerId(opportunityRecord.Id));
    }

    /**
     * @description
     * GCL-73 - An unexpected failure is logged and rethrown.
     */
    @IsTest
    static void unexpectedErrorIsLoggedAndRethrown() {
        LSOpportunityOwnerService.throwTestException = true;
        Opportunity updatedOpportunity = lifeSciencesOwnerChange();
        Opportunity previousOpportunity = updatedOpportunity.clone(true, true, false, false);
        previousOpportunity.OwnerId = fakeId(User.SObjectType);

        try {
            LSOpportunityOwnerService.validateOwnerChange(
                new List<Opportunity>{ updatedOpportunity },
                new Map<Id, Opportunity>{ updatedOpportunity.Id => previousOpportunity }
            );
            System.assert(false, 'A selector failure should be rethrown.');
        } catch (QueryException exceptionValue) {
            System.assertEquals('Forced test exception', exceptionValue.getMessage());
        }
    }

    private static Opportunity insertLifeSciencesOpportunity(User ownerUser) {
        Opportunity opportunityRecord;
        System.runAs(ownerUser) {
            Account accountRecord = new Account(
                Name = 'GCL73 ' + uniqueToken(),
                SourceSystemID__c = uniqueToken()
            );
            insert accountRecord;
            Contact contactRecord = new Contact(
                LastName = 'GCL73 Contact',
                AccountId = accountRecord.Id
            );
            insert contactRecord;
            opportunityRecord = new Opportunity(
                Name = 'GCL73 Opportunity',
                AccountId = accountRecord.Id,
                RecordTypeId = lifeSciencesRecordTypeId(),
                StageName = 'Discovery',
                PositionInFunnel__c = 'Above Funnel',
                ForecastConfidenceLevel__c = 'Pipeline',
                Type = 'New Business',
                Amount = 1000,
                Probability = 10,
                PrimaryContact__c = contactRecord.Id,
                CloseDate = Date.today().addDays(30),
                BypassValidations__c = false
            );
            insert opportunityRecord;
        }
        return opportunityRecord;
    }

    private static void changeOwner(User actingUser, Id opportunityId, Id newOwnerId, Boolean bypassValidations) {
        System.runAs(actingUser) {
            update new Opportunity(
                Id = opportunityId,
                OwnerId = newOwnerId,
                BypassValidations__c = bypassValidations
            );
        }
    }

    private static void shareEdit(Id opportunityId, Id userId) {
        insert new OpportunityShare(
            OpportunityId = opportunityId,
            UserOrGroupId = userId,
            OpportunityAccessLevel = 'Edit',
            RowCause = Schema.OpportunityShare.RowCause.Manual
        );
    }

    private static Id refreshedOwnerId(Id opportunityId) {
        return [SELECT OwnerId FROM Opportunity WHERE Id = :opportunityId].OwnerId;
    }

    private static User userByLastName(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName ORDER BY CreatedDate DESC LIMIT 1];
    }

    private static User newUser(String lastName, String profileName, Id roleId, String token) {
        String uniqueName = lastName.replace(' ', '') + token;
        return new User(
            Alias = uniqueName.left(8),
            Email = uniqueName + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = lastName,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1].Id,
            UserRoleId = roleId,
            TimeZoneSidKey = 'America/New_York',
            Username = uniqueName + '@example.com'
        );
    }

    private static Opportunity lifeSciencesOwnerChange() {
        return new Opportunity(
            Id = fakeId(Opportunity.SObjectType),
            RecordTypeId = lifeSciencesRecordTypeId(),
            OwnerId = fakeId(User.SObjectType),
            BypassValidations__c = false
        );
    }

    private static Id lifeSciencesRecordTypeId() {
        return Opportunity.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .getRecordTypeInfosByDeveloperName()
            .get('LSSalesConsumables')
            .getRecordTypeId();
    }

    private static Id fakeId(Schema.SObjectType sobjectType) {
        return Id.valueOf(sobjectType.getDescribe().getKeyPrefix() + '000000000001');
    }

    private static String uniqueToken() {
        return String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }
}