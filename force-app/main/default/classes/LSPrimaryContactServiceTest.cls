/**
 * @description GCL-11 - Covers LSPrimaryContactService. Opportunity insert and
 *              update go through the trigger. Guard methods are called directly
 *              as well as through Opportunity Contact Role DML.
 */
@IsTest(SeeAllData=false)
private class LSPrimaryContactServiceTest {

    @IsTest
    static void nullAndEmptyInputsDoNotThrow() {
        LSPrimaryContactService.syncRolesOnInsert(null);
        LSPrimaryContactService.syncRolesOnInsert(new List<Opportunity>());
        LSPrimaryContactService.syncRolesOnUpdate(null, null);
        LSPrimaryContactService.syncRolesOnUpdate(
            new List<Opportunity>(),
            new Map<Id, Opportunity>()
        );
        LSPrimaryContactService.guardPrimaryOnInsert(null);
        LSPrimaryContactService.guardPrimaryOnInsert(new List<OpportunityContactRole>());
        LSPrimaryContactService.guardPrimaryOnUpdate(null, null);
        LSPrimaryContactService.guardPrimaryOnUpdate(
            new List<OpportunityContactRole>(),
            new Map<Id, OpportunityContactRole>()
        );

        System.assert(true, 'Empty input must not throw');
    }

    @IsTest
    static void suspendedGuardsSkipValidation() {
        LSPrimaryContactService.guardsSuspended = true;
        OpportunityContactRole role = new OpportunityContactRole(IsPrimary = true);

        LSPrimaryContactService.guardPrimaryOnInsert(new List<OpportunityContactRole>{ role });
        LSPrimaryContactService.guardPrimaryOnUpdate(
            new List<OpportunityContactRole>{ role },
            new Map<Id, OpportunityContactRole>()
        );

        System.assertEquals(0, role.getErrors().size(), 'A suspended guard must not add an error');
    }

    @IsTest
    static void insertCreatesThePrimaryRole() {
        Contact contact = insertContact(insertAccount(), 'Primary');
        Opportunity opportunityRecord = insertOpportunity(contact);

        OpportunityContactRole primaryRole = primaryRole(opportunityRecord.Id);
        System.assertEquals(contact.Id, primaryRole.ContactId);
        System.assertEquals(true, primaryRole.IsPrimary);
        System.assertEquals(LSPrimaryContactService.DEFAULT_ROLE, primaryRole.Role);
    }

    @IsTest
    static void repeatingInsertWhenRoleAlreadyExistsMakesNoChange() {
        Contact contact = insertContact(insertAccount(), 'Primary');
        Opportunity opportunityRecord = insertOpportunity(contact);
        Integer beforeCount = roleCount(opportunityRecord.Id);

        opportunityRecord = [
            SELECT Id, RecordTypeId, PrimaryContact__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
        ];
        LSPrimaryContactService.syncRolesOnInsert(new List<Opportunity>{ opportunityRecord });

        System.assertEquals(beforeCount, roleCount(opportunityRecord.Id));
        System.assertEquals(true, primaryRole(opportunityRecord.Id).IsPrimary);
    }

    @IsTest
    static void changingPrimaryDemotesTheOldRoleAndCreatesTheNewOne() {
        Account accountRecord = insertAccount();
        Contact firstContact = insertContact(accountRecord, 'First');
        Contact secondContact = insertContact(accountRecord, 'Second');
        Opportunity opportunityRecord = insertOpportunity(firstContact);

        Test.startTest();
        update new Opportunity(
            Id = opportunityRecord.Id,
            PrimaryContact__c = secondContact.Id
        );
        Test.stopTest();

        Map<Id, OpportunityContactRole> rolesByContact = rolesByContact(opportunityRecord.Id);
        System.assertEquals(false, rolesByContact.get(firstContact.Id).IsPrimary);
        System.assertEquals(true, rolesByContact.get(secondContact.Id).IsPrimary);
    }

    @IsTest
    static void clearingPrimaryDemotesWithoutCreatingARole() {
        Contact contact = insertContact(insertAccount(), 'Primary');
        Opportunity opportunityRecord = insertOpportunity(contact);

        Test.startTest();
        update new Opportunity(
            Id = opportunityRecord.Id,
            PrimaryContact__c = null
        );
        Test.stopTest();

        OpportunityContactRole remainingRole = [
            SELECT IsPrimary
            FROM OpportunityContactRole
            WHERE OpportunityId = :opportunityRecord.Id
            LIMIT 1
        ];
        System.assertEquals(false, remainingRole.IsPrimary);
        System.assertEquals(1, roleCount(opportunityRecord.Id));
    }

    @IsTest
    static void existingRoleIsPromoted() {
        Account accountRecord = insertAccount();
        Contact firstContact = insertContact(accountRecord, 'First');
        Contact secondContact = insertContact(accountRecord, 'Second');
        Opportunity opportunityRecord = insertOpportunity(firstContact);
        insert new OpportunityContactRole(
            OpportunityId = opportunityRecord.Id,
            ContactId = secondContact.Id,
            Role = 'Evaluator',
            IsPrimary = false
        );

        Test.startTest();
        update new Opportunity(
            Id = opportunityRecord.Id,
            PrimaryContact__c = secondContact.Id
        );
        Test.stopTest();

        Map<Id, OpportunityContactRole> rolesByContact = rolesByContact(opportunityRecord.Id);
        System.assertEquals(false, rolesByContact.get(firstContact.Id).IsPrimary);
        System.assertEquals(true, rolesByContact.get(secondContact.Id).IsPrimary);
        System.assertEquals(2, roleCount(opportunityRecord.Id));
    }

    @IsTest
    static void secondPrimaryRoleIsRejected() {
        Account accountRecord = insertAccount();
        Contact firstContact = insertContact(accountRecord, 'First');
        Contact secondContact = insertContact(accountRecord, 'Second');
        Opportunity opportunityRecord = insertOpportunity(firstContact);

        try {
            insert new OpportunityContactRole(
                OpportunityId = opportunityRecord.Id,
                ContactId = secondContact.Id,
                Role = LSPrimaryContactService.DEFAULT_ROLE,
                IsPrimary = true
            );
            System.assert(false, 'A second Primary role should be rejected');
        } catch (DmlException exceptionValue) {
            System.assert(
                exceptionValue.getDmlMessage(0).contains(Label.LS_OCRPrimaryRemovalError),
                exceptionValue.getDmlMessage(0)
            );
        }
    }

    @IsTest
    static void twoNewPrimaryRolesInOneSaveAreRejected() {
        Account accountRecord = insertAccount();
        Contact firstContact = insertContact(accountRecord, 'First');
        Contact secondContact = insertContact(accountRecord, 'Second');
        Contact thirdContact = insertContact(accountRecord, 'Third');
        Opportunity opportunityRecord = insertOpportunity(firstContact);

        try {
            insert new List<OpportunityContactRole>{
                new OpportunityContactRole(
                    OpportunityId = opportunityRecord.Id,
                    ContactId = secondContact.Id,
                    Role = 'Evaluator',
                    IsPrimary = true
                ),
                new OpportunityContactRole(
                    OpportunityId = opportunityRecord.Id,
                    ContactId = thirdContact.Id,
                    Role = 'Evaluator',
                    IsPrimary = true
                )
            };
            System.assert(false, 'Two new Primary roles in one save should be rejected');
        } catch (DmlException exceptionValue) {
            System.assert(
                exceptionValue.getNumDml() > 0,
                'At least one Primary role should have an error'
            );
        }
    }

    @IsTest
    static void demotingTheSelectedPrimaryIsRejected() {
        Contact contact = insertContact(insertAccount(), 'Primary');
        Opportunity opportunityRecord = insertOpportunity(contact);
        OpportunityContactRole primary = primaryRole(opportunityRecord.Id);
        primary.IsPrimary = false;

        try {
            update primary;
            System.assert(false, 'Demoting the selected Primary role should be rejected');
        } catch (DmlException exceptionValue) {
            System.assert(
                exceptionValue.getDmlMessage(0).contains(Label.LS_OCRPrimaryRemovalErrors),
                exceptionValue.getDmlMessage(0)
            );
        }
    }

    @IsTest
    static void nonPrimaryRoleUpdateIsAllowed() {
        Account accountRecord = insertAccount();
        Contact firstContact = insertContact(accountRecord, 'First');
        Contact secondContact = insertContact(accountRecord, 'Second');
        Opportunity opportunityRecord = insertOpportunity(firstContact);
        OpportunityContactRole extraRole = new OpportunityContactRole(
            OpportunityId = opportunityRecord.Id,
            ContactId = secondContact.Id,
            Role = 'Evaluator',
            IsPrimary = false
        );
        insert extraRole;
        OpportunityContactRole updatedRole = extraRole.clone(true, true, false, false);
        updatedRole.Role = 'Influencer';
        OpportunityContactRole previousRole = extraRole.clone(true, true, false, false);

        LSPrimaryContactService.guardPrimaryOnUpdate(
            new List<OpportunityContactRole>{ updatedRole },
            new Map<Id, OpportunityContactRole>{ updatedRole.Id => previousRole }
        );

        System.assertEquals(0, updatedRole.getErrors().size(), 'A non-primary role change must be allowed');
        System.assertEquals(false, updatedRole.IsPrimary);
    }

    @IsTest
    static void roleForAnUnknownOpportunityIsIgnored() {
        OpportunityContactRole role = new OpportunityContactRole(
            OpportunityId = fakeId(Opportunity.SObjectType),
            ContactId = fakeId(Contact.SObjectType),
            IsPrimary = true
        );

        LSPrimaryContactService.guardPrimaryOnInsert(new List<OpportunityContactRole>{ role });
        LSPrimaryContactService.guardPrimaryOnUpdate(
            new List<OpportunityContactRole>{ role },
            new Map<Id, OpportunityContactRole>{
                fakeId(OpportunityContactRole.SObjectType) => role
            }
        );

        System.assertEquals(0, role.getErrors().size());
    }

    @IsTest
    static void primaryChangeWithNoSelectorIsRethrown() {
        Account accountRecord = insertAccount();
        Contact contact = insertContact(accountRecord, 'Primary');
        Contact otherContact = insertContact(accountRecord, 'Other');
        Opportunity opportunityRecord = insertOpportunity(contact);
        Opportunity previous = opportunityRecord.clone(true, true, false, false);
        opportunityRecord.PrimaryContact__c = otherContact.Id;
        LSPrimaryContactService.ocrSelector = null;

        try {
            LSPrimaryContactService.syncRolesOnInsert(new List<Opportunity>{ opportunityRecord });
            System.assert(false, 'A missing selector should be rethrown on insert');
        } catch (NullPointerException exceptionValue) {
            System.assertNotEquals(null, exceptionValue);
        }

        try {
            LSPrimaryContactService.syncRolesOnUpdate(
                new List<Opportunity>{ opportunityRecord },
                new Map<Id, Opportunity>{ opportunityRecord.Id => previous }
            );
            System.assert(false, 'A missing selector should be rethrown on update');
        } catch (NullPointerException exceptionValue) {
            System.assertNotEquals(null, exceptionValue);
        }
    }

    @IsTest
    static void guardWithNoSelectorIsRethrown() {
        OpportunityContactRole role = new OpportunityContactRole(
            OpportunityId = fakeId(Opportunity.SObjectType),
            ContactId = fakeId(Contact.SObjectType),
            IsPrimary = true
        );
        LSPrimaryContactService.opportunitySelector = null;

        try {
            LSPrimaryContactService.guardPrimaryOnInsert(new List<OpportunityContactRole>{ role });
            System.assert(false, 'A missing selector should be rethrown on guard insert');
        } catch (NullPointerException exceptionValue) {
            System.assertNotEquals(null, exceptionValue);
        }

        try {
            LSPrimaryContactService.guardPrimaryOnUpdate(
                new List<OpportunityContactRole>{ role },
                new Map<Id, OpportunityContactRole>()
            );
            System.assert(false, 'A missing selector should be rethrown on guard update');
        } catch (NullPointerException exceptionValue) {
            System.assertNotEquals(null, exceptionValue);
        }
    }

    private static Account insertAccount() {
        Account accountRecord = new Account(
            Name = 'GCL11 ' + uniqueToken(),
            SourceSystemID__c = uniqueToken()
        );
        insert accountRecord;
        return accountRecord;
    }

    private static Contact insertContact(Account accountRecord, String lastName) {
        Contact contactRecord = new Contact(
            LastName = lastName,
            AccountId = accountRecord.Id
        );
        insert contactRecord;
        return contactRecord;
    }

    private static Opportunity insertOpportunity(Contact contactRecord) {
        Opportunity opportunityRecord = new Opportunity(
            Name = 'GCL11 Opportunity',
            AccountId = contactRecord.AccountId,
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

    private static OpportunityContactRole primaryRole(Id opportunityId) {
        return [
            SELECT Id, ContactId, IsPrimary, Role
            FROM OpportunityContactRole
            WHERE OpportunityId = :opportunityId AND IsPrimary = true
            LIMIT 1
        ];
    }

    private static Integer roleCount(Id opportunityId) {
        return [SELECT COUNT() FROM OpportunityContactRole WHERE OpportunityId = :opportunityId];
    }

    private static Map<Id, OpportunityContactRole> rolesByContact(Id opportunityId) {
        Map<Id, OpportunityContactRole> rolesByContact = new Map<Id, OpportunityContactRole>();
        for (OpportunityContactRole role : [
            SELECT Id, ContactId, IsPrimary, Role
            FROM OpportunityContactRole
            WHERE OpportunityId = :opportunityId
        ]) {
            rolesByContact.put(role.ContactId, role);
        }
        return rolesByContact;
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