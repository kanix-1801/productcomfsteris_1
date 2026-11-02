/**
 * @description GC-3541 Part 1. Duplicate classification before Lead insert.
 */
@IsTest
private class LeadDuplicateServiceTest {

    @IsTest
    static void standardSaveIsNotBlockedByGc3541() {
        insert new Contact(LastName = 'Doe', Email = 'GC3541.Part1@example.com');

        Lead incoming = newLead('gc3541.part1@example.com', 'Pat', 'Doe', 'Clinic', '5551112222');
        LeadDuplicateService.MatchResult result = LeadDuplicateService.findDuplicates(new List<Lead>{ incoming })[0];
        Database.DMLOptions options = new Database.DMLOptions();
        options.DuplicateRuleHeader.allowSave = true;
        Database.SaveResult saved = Database.insert(incoming, options);

        System.assertEquals(LeadDuplicateService.STATUS_DEFINITIVE, result.status);
        System.assertEquals(true, saved.isSuccess(), 'A standard Lead Save must not receive the GC-3541 block.');
    }

    @IsTest
    static void bulkDefinitiveContactMatchBlocksLead() {
        insert new Contact(LastName = 'Doe', Email = 'GC3541.Part1@example.com');

        LeadDuplicateService.quiddityOverride = Quiddity.BULK_API;
        Lead incoming = newLead('gc3541.part1@example.com', 'Pat', 'Doe', 'Clinic', '5551112222');
        DmlException thrown;
        try {
            insert incoming;
        } catch (DmlException ex) {
            thrown = ex;
        }

        System.assertNotEquals(null, thrown, 'A bulk definitive Contact email match must block the Lead.');
        System.assert(thrown.getDmlMessage(0).toLowerCase().contains('doe, gc3541.part1@example.com (contact)'));
        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE Email = 'gc3541.part1@example.com']);
    }

    @IsTest
    static void bulkDefinitiveLeadMatchIgnoresCase() {
        insert newLead('gc3541.open@example.com', 'Pat', 'Doe', 'Clinic', '5550001111');

        TriggerControl.reset(Lead.SObjectType, 'beforeInsert');
        LeadDuplicateService.quiddityOverride = Quiddity.BULK_API;
        Lead incoming = newLead('GC3541.Open@example.com', 'Sam', 'Roe', 'Other', '5550009999');
        DmlException thrown;
        try {
            insert incoming;
        } catch (DmlException ex) {
            thrown = ex;
        }

        System.assertNotEquals(null, thrown);
        System.assert(thrown.getDmlMessage(0).toLowerCase().contains('pat doe, gc3541.open@example.com, clinic (lead)'));
    }

    @IsTest
    static void manualPotentialMatchIsAllowed() {
        Account accountRecord = new Account(Name = 'Steris Clinic');
        insert accountRecord;
        insert new Contact(
            FirstName = 'Ann',
            LastName = 'Lee',
            Email = 'ann.existing@example.com',
            Phone = '555-111-2222',
            AccountId = accountRecord.Id
        );

        Lead incoming = newLead('ann.new@example.com', 'Ann', 'Lee', 'Steris Clinic', '(555) 111-2222');
        LeadDuplicateService.MatchResult result = LeadDuplicateService.findDuplicates(new List<Lead>{ incoming })[0];
        Database.DMLOptions options = new Database.DMLOptions();
        options.DuplicateRuleHeader.allowSave = true;
        Database.SaveResult saved = Database.insert(incoming, options);

        System.assertEquals(true, saved.isSuccess(), 'A standard Lead Save must not receive the GC-3541 block.');
        System.assertEquals(LeadDuplicateService.STATUS_POTENTIAL, result.status);
        System.assertEquals(LeadDuplicateService.REASON_NAME_PHONE_COMPANY, result.reason);
        System.assertEquals(1, [SELECT COUNT() FROM Lead WHERE Email = 'ann.new@example.com']);
    }

    @IsTest
    static void bulkPotentialMatchIsRejected() {
        Account accountRecord = new Account(Name = 'Facility A');
        insert accountRecord;
        insert new Contact(
            FirstName = 'Bob',
            LastName = 'Stone',
            Email = 'bob.existing@example.com',
            Phone = '5559998888',
            AccountId = accountRecord.Id
        );

        LeadDuplicateService.bulkRejectOverride = null;
        LeadDuplicateService.quiddityOverride = Quiddity.BULK_API;
        Lead incoming = newLead('zoe.new@example.com', 'Zoe', 'Miles', 'Facility A', '555-999-8888');
        DmlException thrown;
        try {
            insert incoming;
        } catch (DmlException ex) {
            thrown = ex;
        }

        System.assertNotEquals(null, thrown, 'Bulk upload must reject a potential match.');
        System.assert(thrown.getDmlMessage(0).contains(LeadDuplicateService.STATUS_POTENTIAL));
        System.assert(thrown.getDmlMessage(0).contains('Bob Stone, bob.existing@example.com, Facility A (Contact)'));
    }

    @IsTest
    static void manualAmbiguousEmailMatchCanProceed() {
        insert new Contact(LastName = 'One', Email = 'gc3541.shared@example.com');
        insert new Contact(LastName = 'Two', Email = 'gc3541.shared@example.com');

        Lead incoming = newLead('gc3541.shared@example.com', 'New', 'Person', 'Clinic', null);
        LeadDuplicateService.MatchResult result = LeadDuplicateService.findDuplicates(new List<Lead>{ incoming })[0];
        Database.DMLOptions options = new Database.DMLOptions();
        options.DuplicateRuleHeader.allowSave = true;
        Database.SaveResult saved = Database.insert(incoming, options);

        System.assertEquals(true, saved.isSuccess(), 'A standard Lead Save must not receive the GC-3541 block.');
        System.assertEquals(LeadDuplicateService.STATUS_AMBIGUOUS, result.status);
        System.assertEquals(1, [SELECT COUNT() FROM Lead WHERE Email = 'gc3541.shared@example.com']);
    }

    @IsTest
    static void noMatchLeavesStatusBlank() {
        Lead incoming = newLead('gc3541.unique@example.com', 'Uma', 'Unique', 'New Clinic', '5552223333');
        LeadDuplicateService.MatchResult result = LeadDuplicateService.findDuplicates(new List<Lead>{ incoming })[0];
        insert incoming;

        System.assertEquals(null, result.status);
        System.assertEquals(null, result.buildDetail());
    }

    @IsTest
    static void bulkKeepsFirstSameFileEmailAndRejectsTheRest() {
        List<Lead> incoming = new List<Lead>{
            newLead('gc3541.batch@example.com', 'Ann', 'One', 'Clinic', null),
            newLead('gc3541.batch@example.com', 'Bob', 'Two', 'Clinic', null)
        };

        LeadDuplicateService.quiddityOverride = Quiddity.BULK_API;
        Database.SaveResult[] results = Database.insert(incoming, allowStandardDuplicateAlert());
        System.assertEquals(true, results[0].isSuccess(), 'The first row in the file is created.');
        System.assertEquals(false, results[1].isSuccess());
        System.assert(results[1].getErrors()[0].getMessage().contains('Ann One'));
        System.assert(results[1].getErrors()[0].getMessage().contains(LeadDuplicateService.STATUS_DEFINITIVE));
        System.assertEquals(1, [SELECT COUNT() FROM Lead WHERE Email = 'gc3541.batch@example.com']);
    }

    @IsTest
    static void bulkKeepsFirstSameFilePotentialAndRejectsTheRest() {
        List<Lead> incoming = new List<Lead>{
            newLead('gc3541.first@example.com', 'Ann', 'Lee', 'Clinic', '5551112222'),
            newLead('gc3541.second@example.com', 'Ann', 'Lee', 'Clinic', '(555) 111-2222')
        };

        LeadDuplicateService.quiddityOverride = Quiddity.BULK_API;
        Database.SaveResult[] results = Database.insert(incoming, allowStandardDuplicateAlert());
        System.assertEquals(true, results[0].isSuccess(), 'The first row in the file is created.');
        System.assertEquals(false, results[1].isSuccess());
        System.assert(results[1].getErrors()[0].getMessage().contains(LeadDuplicateService.STATUS_POTENTIAL));
        System.assert(results[1].getErrors()[0].getMessage().contains('Ann Lee'));
        System.assertEquals(1, [SELECT COUNT() FROM Lead WHERE LastName = 'Lee' AND Company = 'Clinic']);
    }

    @IsTest
    static void bulkRejectsFirstRowWhenItMatchesAnExistingRecord() {
        insert new Contact(LastName = 'Doe', Email = 'gc3541.part1@example.com');
        List<Lead> incoming = new List<Lead>{
            newLead('gc3541.part1@example.com', 'Pat', 'Doe', 'Clinic', '5551112222'),
            newLead('gc3541.clean@example.com', 'Uma', 'Unique', 'New Clinic', '5552223333')
        };

        LeadDuplicateService.quiddityOverride = Quiddity.BULK_API;
        Database.SaveResult[] results = Database.insert(incoming, allowStandardDuplicateAlert());
        System.assertEquals(false, results[0].isSuccess());
        System.assert(results[0].getErrors()[0].getMessage().contains(LeadDuplicateService.STATUS_DEFINITIVE));
        System.assertEquals(true, results[1].isSuccess(), 'A later row with no match is still created.');
    }

    private static Database.DMLOptions allowStandardDuplicateAlert() {
        Database.DMLOptions options = new Database.DMLOptions();
        options.DuplicateRuleHeader.allowSave = true;
        options.optAllOrNone = false;
        return options;
    }

    private static Lead newLead(String email, String firstName, String lastName, String company, String phone) {
        return new Lead(
            FirstName = firstName,
            LastName = lastName,
            Company = company,
            Email = email,
            Phone = phone,
            CountryCode = 'US',
            LeadSource = 'Marketing Campaign'
        );
    }
}