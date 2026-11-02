/**
 * @author Akash Dahinde
 * @date 09-25-2026
 * @story GCL-11
 * @description Verifies Primary Contact synchronization and one-Primary OCR
 *              enforcement for the supported Opportunity record types.
 */
@IsTest
private class PrimaryContactServiceTest {

    // ---------------------------------------------------------------- fixtures

    private static List<Contact> makeContacts(Integer howMany) {
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < howMany; i++) {
            contacts.add(new Contact(LastName = 'Primary Test ' + i));
        }
        insert contacts;
        return contacts;
    }

    private static Opportunity newOpportunity(String name, Id primaryContactId) {
        Opportunity opp = new Opportunity(
            Name = name,
            StageName = Opportunity.StageName.getDescribe().getPicklistValues()[0].getValue(),
            CloseDate = Date.today().addDays(30),
            PrimaryContact__c = primaryContactId
        );
        Id recordTypeId = inScopeRecordTypeId();
        if (recordTypeId != null) {
            opp.RecordTypeId = recordTypeId;
        }
        return opp;
    }

    /** First in-scope record type available in the org, or null if none are. */
    private static Id inScopeRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> byName =
            Opportunity.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName();
        for (String developerName : LSPrimaryContactService.IN_SCOPE_RECORD_TYPE_DEVELOPER_NAMES) {
            Schema.RecordTypeInfo info = byName.get(developerName);
            if (info != null && info.isAvailable()) {
                return info.getRecordTypeId();
            }
        }
        return null;
    }

    private static List<OpportunityContactRole> rolesFor(Id opportunityId) {
        return [
            SELECT Id, ContactId, IsPrimary, Role
            FROM OpportunityContactRole
            WHERE OpportunityId = :opportunityId
            ORDER BY ContactId
        ];
    }

    private static OpportunityContactRole primaryRoleFor(Id opportunityId) {
        List<OpportunityContactRole> roles = [
            SELECT Id, ContactId, IsPrimary
            FROM OpportunityContactRole
            WHERE OpportunityId = :opportunityId AND IsPrimary = TRUE
        ];
        return roles.isEmpty() ? null : roles[0];
    }

    /** Seeds the primary OCR via the service (not OpportunityTrigger). */
    private static void applyPrimaryFromLookup(Opportunity opp) {
        LSPrimaryContactService.syncRolesOnInsert(new List<Opportunity>{ opp });
    }

    private static void applyPrimaryFromLookupChange(Opportunity updated, Opportunity previous) {
        LSPrimaryContactService.syncRolesOnUpdate(
            new List<Opportunity>{ updated },
            new Map<Id, Opportunity>{ previous.Id => previous }
        );
    }

    // ---------------------------------------------------------------- opportunity drives the role

    @IsTest
    static void insertingAnOpportunityCreatesThePrimaryRole() {
        List<Contact> contacts = makeContacts(1);

        Opportunity opp = newOpportunity('Creates role', contacts[0].Id);
        insert opp;

        Test.startTest();
        applyPrimaryFromLookup(opp);
        Test.stopTest();

        List<OpportunityContactRole> roles = rolesFor(opp.Id);
        Assert.areEqual(1, roles.size(), 'Exactly one contact role should have been created.');
        Assert.areEqual(contacts[0].Id, roles[0].ContactId, 'The role should point at Primary Contact.');
        Assert.isTrue(roles[0].IsPrimary, 'The generated role should be flagged as primary.');
        Assert.areEqual(
            LSPrimaryContactService.DEFAULT_ROLE,
            roles[0].Role,
            'The generated role should carry the configured default Role.'
        );
    }

    @IsTest
    static void changingPrimaryContactMovesTheFlagAndKeepsTheOldRole() {
        List<Contact> contacts = makeContacts(2);
        Opportunity opp = newOpportunity('Moves the flag', contacts[0].Id);
        insert opp;
        applyPrimaryFromLookup(opp);

        Test.startTest();
        Opportunity previous = opp.clone(true, true, true, true);
        Opportunity updated = new Opportunity(Id = opp.Id, PrimaryContact__c = contacts[1].Id);
        update updated;
        applyPrimaryFromLookupChange(
            new Opportunity(
                Id = opp.Id,
                PrimaryContact__c = contacts[1].Id,
                RecordTypeId = opp.RecordTypeId
            ),
            previous
        );
        Test.stopTest();

        Map<Id, OpportunityContactRole> byContactId = new Map<Id, OpportunityContactRole>();
        for (OpportunityContactRole role : rolesFor(opp.Id)) {
            byContactId.put(role.ContactId, role);
        }

        Assert.areEqual(2, byContactId.size(), 'The original role should survive the change.');
        Assert.isFalse(byContactId.get(contacts[0].Id).IsPrimary, 'The old contact should be demoted.');
        Assert.isTrue(byContactId.get(contacts[1].Id).IsPrimary, 'The new contact should be primary.');
    }

    @IsTest
    static void reusesAnExistingRoleInsteadOfCreatingADuplicate() {
        List<Contact> contacts = makeContacts(2);
        Opportunity opp = newOpportunity('Reuses a role', contacts[0].Id);
        insert opp;
        applyPrimaryFromLookup(opp);

        insert new OpportunityContactRole(
            OpportunityId = opp.Id,
            ContactId = contacts[1].Id,
            Role = 'Influencer',
            IsPrimary = false
        );

        Test.startTest();
        Opportunity previous = [
            SELECT Id, PrimaryContact__c, RecordTypeId FROM Opportunity WHERE Id = :opp.Id
        ];
        update new Opportunity(Id = opp.Id, PrimaryContact__c = contacts[1].Id);
        applyPrimaryFromLookupChange(
            new Opportunity(
                Id = opp.Id,
                PrimaryContact__c = contacts[1].Id,
                RecordTypeId = previous.RecordTypeId
            ),
            previous
        );
        Test.stopTest();

        Assert.areEqual(2, rolesFor(opp.Id).size(), 'The existing role should be promoted, not duplicated.');
        Assert.areEqual(
            contacts[1].Id,
            primaryRoleFor(opp.Id).ContactId,
            'The role that already existed should now hold the primary flag.'
        );
    }

    @IsTest
    static void clearingPrimaryContactDemotesTheRole() {
        List<Contact> contacts = makeContacts(1);
        Opportunity opp = newOpportunity('Clears the flag', contacts[0].Id);
        insert opp;
        applyPrimaryFromLookup(opp);

        Test.startTest();
        Opportunity previous = [
            SELECT Id, PrimaryContact__c, RecordTypeId FROM Opportunity WHERE Id = :opp.Id
        ];
        update new Opportunity(Id = opp.Id, PrimaryContact__c = null);
        applyPrimaryFromLookupChange(
            new Opportunity(Id = opp.Id, PrimaryContact__c = null, RecordTypeId = previous.RecordTypeId),
            previous
        );
        Test.stopTest();

        Assert.isNull(primaryRoleFor(opp.Id), 'Clearing the lookup should leave no primary role.');
        Assert.areEqual(1, rolesFor(opp.Id).size(), 'The role itself should be kept.');
    }

    // ---------------------------------------------------------------- only one primary

    @IsTest
    static void addingASecondPrimaryRoleIsRejected() {
        List<Contact> contacts = makeContacts(2);
        Opportunity opp = newOpportunity('Second primary', contacts[0].Id);
        insert opp;
        applyPrimaryFromLookup(opp);

        Test.startTest();
        Database.SaveResult result = Database.insert(
            new OpportunityContactRole(
                OpportunityId = opp.Id,
                ContactId = contacts[1].Id,
                Role = 'Influencer',
                IsPrimary = true
            ),
            false
        );
        Test.stopTest();

        Assert.isFalse(result.isSuccess(), 'A second primary contact role must not be accepted.');
        Assert.isTrue(
            result.getErrors()[0].getMessage().contains(
                Label.LS_OCRPrimaryRemovalError
            ),
            'The user should be told that only one primary is allowed. Got: ' +
                result.getErrors()[0].getMessage()
        );
        Assert.areEqual(
            contacts[0].Id,
            primaryRoleFor(opp.Id).ContactId,
            'The original primary should be untouched.'
        );
    }

    @IsTest
    static void addingANonPrimaryRoleIsAllowed() {
        List<Contact> contacts = makeContacts(2);
        Opportunity opp = newOpportunity('Extra role', contacts[0].Id);
        insert opp;
        applyPrimaryFromLookup(opp);

        Test.startTest();
        insert new OpportunityContactRole(
            OpportunityId = opp.Id,
            ContactId = contacts[1].Id,
            Role = 'Influencer',
            IsPrimary = false
        );
        Test.stopTest();

        Assert.areEqual(2, rolesFor(opp.Id).size(), 'Additional non primary roles are fine.');
        Assert.areEqual(
            contacts[0].Id,
            primaryRoleFor(opp.Id).ContactId,
            'The primary flag should not have moved.'
        );
    }

    @IsTest
    static void promotingASecondRoleIsRejected() {
        List<Contact> contacts = makeContacts(2);
        Opportunity opp = newOpportunity('Promote second', contacts[0].Id);
        insert opp;
        applyPrimaryFromLookup(opp);

        OpportunityContactRole extra = new OpportunityContactRole(
            OpportunityId = opp.Id,
            ContactId = contacts[1].Id,
            Role = 'Influencer',
            IsPrimary = false
        );
        insert extra;

        Test.startTest();
        Database.SaveResult result = Database.update(
            new OpportunityContactRole(Id = extra.Id, IsPrimary = true),
            false
        );
        Test.stopTest();

        Assert.isFalse(result.isSuccess(), 'Ticking Primary on a second role must be rejected.');
        Assert.isTrue(
            result.getErrors()[0].getMessage().contains(
                Label.LS_OCRPrimaryRemovalError
            ),
            'Got: ' + result.getErrors()[0].getMessage()
        );
    }

    @IsTest
    static void twoPrimaryRolesInOneInsertAreRejected() {
        List<Contact> contacts = makeContacts(3);
        Opportunity opp = newOpportunity('Bulk primaries', contacts[0].Id);
        insert opp;
        applyPrimaryFromLookup(opp);

        // Covers the Data Loader / API case that a database only check would miss.
        List<OpportunityContactRole> incoming = new List<OpportunityContactRole>{
            new OpportunityContactRole(
                OpportunityId = opp.Id, ContactId = contacts[1].Id, IsPrimary = true
            ),
            new OpportunityContactRole(
                OpportunityId = opp.Id, ContactId = contacts[2].Id, IsPrimary = true
            )
        };

        Test.startTest();
        List<Database.SaveResult> results = Database.insert(incoming, false);
        Test.stopTest();

        Assert.isFalse(results[0].isSuccess(), 'The first extra primary is blocked by the committed one.');
        Assert.isFalse(results[1].isSuccess(), 'The second extra primary is blocked as a same batch duplicate.');
        Assert.areEqual(
            contacts[0].Id,
            primaryRoleFor(opp.Id).ContactId,
            'The opportunity should still have exactly its original primary.'
        );
    }

    @IsTest
    static void eachOpportunityKeepsItsOwnPrimaryInABulkInsert() {
        List<Contact> contacts = makeContacts(2);

        List<Opportunity> opportunities = new List<Opportunity>();
        for (Integer i = 0; i < 200; i++) {
            opportunities.add(newOpportunity('Bulk ' + i, contacts[Math.mod(i, 2)].Id));
        }

        Test.startTest();
        insert opportunities;
        LSPrimaryContactService.syncRolesOnInsert(opportunities);
        Test.stopTest();

        Assert.areEqual(
            200,
            [SELECT COUNT() FROM OpportunityContactRole WHERE OpportunityId IN :opportunities AND IsPrimary = TRUE],
            'Every opportunity in the batch should end up with exactly one primary role.'
        );
    }

    // ---------------------------------------------------------------- one is required

    @IsTest
    static void unmarkingTheOnlyPrimaryIsRejected() {
        List<Contact> contacts = makeContacts(1);
        Opportunity opp = newOpportunity('Unmark primary', contacts[0].Id);
        insert opp;
        applyPrimaryFromLookup(opp);

        Test.startTest();
        Database.SaveResult result = Database.update(
            new OpportunityContactRole(Id = primaryRoleFor(opp.Id).Id, IsPrimary = false),
            false
        );
        Test.stopTest();

        Assert.isFalse(result.isSuccess(), 'The opportunity would be left with no primary contact.');
        Assert.isTrue(
            result.getErrors()[0].getMessage().contains(
                Label.LS_OCRPrimaryRemovalErrors
            ),
            'Got: ' + result.getErrors()[0].getMessage()
        );
    }

    @IsTest
    static void deletingANonPrimaryRoleIsAllowed() {
        List<Contact> contacts = makeContacts(2);
        Opportunity opp = newOpportunity('Delete extra', contacts[0].Id);
        insert opp;
        applyPrimaryFromLookup(opp);

        OpportunityContactRole extra = new OpportunityContactRole(
            OpportunityId = opp.Id, ContactId = contacts[1].Id, IsPrimary = false
        );
        insert extra;

        Test.startTest();
        delete extra;
        Test.stopTest();

        Assert.areEqual(1, rolesFor(opp.Id).size(), 'Only the non primary role should be gone.');
    }

    // ---------------------------------------------------------------- bypass

    @IsTest
    static void suspendedGuardsLetAnythingThrough() {
        List<Contact> contacts = makeContacts(2);
        Opportunity opp = newOpportunity('Suspended', contacts[0].Id);
        insert opp;
        applyPrimaryFromLookup(opp);

        Test.startTest();
        LSPrimaryContactService.guardsSuspended = true;
        try {
            insert new OpportunityContactRole(
                OpportunityId = opp.Id, ContactId = contacts[1].Id, IsPrimary = true
            );
        } finally {
            LSPrimaryContactService.guardsSuspended = false;
        }
        Test.stopTest();

        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM OpportunityContactRole
                WHERE OpportunityId = :opp.Id AND ContactId = :contacts[1].Id AND IsPrimary = TRUE
            ],
            'With the guard suspended the role should have been accepted as primary.'
        );
    }
}