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
    private static final String ADMIN_LAST_NAME = 'GCL73 Admin';

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
        User adminUser = newUser(ADMIN_LAST_NAME, 'System Administrator', null, token);
        insert new List<User>{ ownerUser, peerUser, managerUser, businessSystemAdmin, newOwner, adminUser };

        PermissionSet businessSystemAdminPermissionSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :LSOpportunityOwnerService.BUSINESS_SYSTEM_ADMIN_PERMISSION_SET
            LIMIT 1
        ];
        PermissionSet transferPermissionSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'LSTransferRecord'
            LIMIT 1
        ];
        PermissionSet opportunityAccessPermissionSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'LSInsideSalesPS'
            LIMIT 1
        ];
        insert new List<PermissionSetAssignment>{
            new PermissionSetAssignment(
                AssigneeId = businessSystemAdmin.Id,
                PermissionSetId = businessSystemAdminPermissionSet.Id
            ),
            new PermissionSetAssignment(
                AssigneeId = ownerUser.Id,
                PermissionSetId = transferPermissionSet.Id
            ),
            new PermissionSetAssignment(
                AssigneeId = peerUser.Id,
                PermissionSetId = transferPermissionSet.Id
            ),
            new PermissionSetAssignment(
                AssigneeId = managerUser.Id,
                PermissionSetId = transferPermissionSet.Id
            ),
            new PermissionSetAssignment(
                AssigneeId = businessSystemAdmin.Id,
                PermissionSetId = transferPermissionSet.Id
            ),
            new PermissionSetAssignment(
                AssigneeId = ownerUser.Id,
                PermissionSetId = opportunityAccessPermissionSet.Id
            ),
            new PermissionSetAssignment(
                AssigneeId = peerUser.Id,
                PermissionSetId = opportunityAccessPermissionSet.Id
            ),
            new PermissionSetAssignment(
                AssigneeId = managerUser.Id,
                PermissionSetId = opportunityAccessPermissionSet.Id
            )
        };
    }

    /**
     * @description
     * GCL-73 - A Life Sciences Sales user can resolve the profile name
     * without querying the User.Profile relationship.
     */
    @IsTest
    static void lifeSciencesUserCanResolveProfileName() {
        User lifeSciencesUser = userByLastName(OWNER_LAST_NAME);

        System.runAs(lifeSciencesUser) {
            User runningUser = LSOpportunityOwnerSelector.selectRunningUser();
            String profileName = LSOpportunityOwnerSelector.selectProfileName(UserInfo.getProfileId());

            System.assertEquals(lifeSciencesUser.Id, runningUser.Id);
            System.assertEquals('Life Sciences Sales', profileName);
        }
    }

    /**
     * @description
     * GCL-73 - A null or empty save does not query and does not throw.
     */
    @IsTest
    static void nullInputDoesNotThrow() {
        Id ownerId = UserInfo.getUserId();
        Opportunity opportunityRecord = new Opportunity(
            Id = fakeId(Opportunity.SObjectType, '000000000001'),
            RecordTypeId = lifeSciencesRecordTypeId(),
            OwnerId = ownerId,
            BypassValidations__c = false
        );
        Opportunity previousOpportunity = opportunityRecord.clone(true, true, false, false);

        LSOpportunityOwnerService.validateOwnerChange(null, null);
        LSOpportunityOwnerService.validateOwnerChange(new List<Opportunity>(), new Map<Id, Opportunity>());
        LSOpportunityOwnerService.validateOwnerChange(
            new List<Opportunity>{ opportunityRecord },
            new Map<Id, Opportunity>{ opportunityRecord.Id => previousOpportunity }
        );

        System.assertEquals(ownerId, opportunityRecord.OwnerId);
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
        shareAccountRead(opportunityRecord.AccountId, newOwner.Id);

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
        shareAccountRead(opportunityRecord.AccountId, newOwner.Id);

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
        shareAccountRead(opportunityRecord.AccountId, newOwner.Id);

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
        shareAccountRead(opportunityRecord.AccountId, newOwner.Id);
        update new Opportunity(
            Id = opportunityRecord.Id,
            BypassValidations__c = true
        );

        Test.startTest();
        changeOwner(peerUser, opportunityRecord.Id, newOwner.Id, false);
        Test.stopTest();

        System.assertEquals(newOwner.Id, refreshedOwnerId(opportunityRecord.Id));
    }

    /**
     * @description
     * GCL-73 - System Administrator is outside the Life Sciences Sales check.
     */
    @IsTest
    static void systemAdminIsNotBlocked() {
        User adminUser = userByLastName(ADMIN_LAST_NAME);
        User newOwner = userByLastName(NEW_OWNER_LAST_NAME);
        Opportunity opportunityRecord = insertLifeSciencesOpportunity(userByLastName(OWNER_LAST_NAME));

        Test.startTest();
        changeOwner(adminUser, opportunityRecord.Id, newOwner.Id, false);
        Test.stopTest();

        System.assertEquals(newOwner.Id, refreshedOwnerId(opportunityRecord.Id));
    }

    /**
     * @description
     * GCL-73 - The validation-rule automation setting skips the owner check.
     */
    @IsTest
    static void automationSettingSkipsOwnerCheck() {
        User ownerUser = userByLastName(OWNER_LAST_NAME);
        User peerUser = userByLastName(PEER_LAST_NAME);
        User newOwner = userByLastName(NEW_OWNER_LAST_NAME);
        insert new Automation_Setting_Validation_Rule__c(
            SetupOwnerId = peerUser.Id,
            LS_Opp_073_RestrictOwnerChange__c = true
        );

        Opportunity opportunityRecord;
        System.runAs(userByLastName(ADMIN_LAST_NAME)) {
            opportunityRecord = insertLifeSciencesOpportunity(ownerUser);
            shareEdit(opportunityRecord.Id, peerUser.Id);
            shareAccountRead(opportunityRecord.AccountId, newOwner.Id);
        }

        Test.startTest();
        changeOwner(peerUser, opportunityRecord.Id, newOwner.Id, false);
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
        Opportunity updatedOpportunity = lifeSciencesOwnerChange('000000000001');
        Opportunity previousOpportunity = updatedOpportunity.clone(true, true, false, false);
        previousOpportunity.OwnerId = fakeId(User.SObjectType, '000000000002');

        System.runAs(userByLastName(OWNER_LAST_NAME)) {
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
    }

    private static Opportunity insertLifeSciencesOpportunity(User ownerUser) {
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
        Opportunity opportunityRecord = new Opportunity(
            Name = 'GCL73 Opportunity',
            AccountId = accountRecord.Id,
            OwnerId = ownerUser.Id,
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
        return opportunityRecord;
    }

    private static void changeOwner(User actingUser, Id opportunityId, Id newOwnerId, Boolean bypassValidations) {
        System.runAs(actingUser) {
            Opportunity opportunityRecord = new Opportunity(
                Id = opportunityId,
                OwnerId = newOwnerId
            );
            if (bypassValidations) {
                opportunityRecord.BypassValidations__c = true;
            }
            update opportunityRecord;
        }
    }

    private static void shareAccountRead(Id accountId, Id userId) {
        insert new AccountShare(
            AccountId = accountId,
            UserOrGroupId = userId,
            AccountAccessLevel = 'Read',
            OpportunityAccessLevel = 'Read',
            CaseAccessLevel = 'None'
        );
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

    private static Opportunity lifeSciencesOwnerChange(String suffix) {
        return new Opportunity(
            Id = fakeId(Opportunity.SObjectType, suffix),
            RecordTypeId = lifeSciencesRecordTypeId(),
            OwnerId = fakeId(User.SObjectType, suffix),
            BypassValidations__c = false
        );
    }

    private static Id lifeSciencesRecordTypeId() {
        return Opportunity.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .getRecordTypeInfosByDeveloperName()
            .get('LSSalesConsumables')
            .getRecordTypeId();
    }

    private static Id fakeId(Schema.SObjectType sobjectType, String suffix) {
        return Id.valueOf(sobjectType.getDescribe().getKeyPrefix() + suffix);
    }

    private static String uniqueToken() {
        return String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }
}