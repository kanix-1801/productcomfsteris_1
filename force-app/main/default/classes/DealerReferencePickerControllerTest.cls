/**
 * @description #GC-3598 Unit tests for DealerReferencePickerController.
 */
@IsTest(SeeAllData=false)
private class DealerReferencePickerControllerTest {
    @TestSetup
    static void setupData() {
        insert new List<DealerReferenceValue__c>{
            new DealerReferenceValue__c(Name = 'Alpha Architect', Type__c = 'Architect'),
            new DealerReferenceValue__c(Name = 'Beta Competitor', Type__c = 'Competitor'),
            new DealerReferenceValue__c(Name = 'Gamma Competitor', Type__c = 'Competitor')
        };
    }

    @IsTest
    static void search_returnsMatchingRowsForType() {
        Test.startTest();
        List<DealerReferencePickerController.Option> results =
            DealerReferencePickerController.search('Competitor', 'Beta');
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one competitor match');
        System.assertEquals('Beta Competitor', results[0].name);
    }

    @IsTest
    static void search_blankTerm_returnsRowsForType() {
        Test.startTest();
        List<DealerReferencePickerController.Option> results =
            DealerReferencePickerController.search('Competitor', null);
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Expected both competitor rows');
    }

    @IsTest
    static void create_insertsNewValue() {
        Test.startTest();
        DealerReferencePickerController.Option created =
            DealerReferencePickerController.create('EndCustomer', 'New Hospital');
        Test.stopTest();

        System.assertNotEquals(null, created.id);
        System.assertEquals('New Hospital', created.name);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM DealerReferenceValue__c WHERE Type__c = 'EndCustomer' AND Name = 'New Hospital']
        );
    }

    @IsTest
    static void create_returnsExistingWhenDuplicate() {
        Test.startTest();
        DealerReferencePickerController.Option created =
            DealerReferencePickerController.create('Architect', 'Alpha Architect');
        Test.stopTest();

        System.assertEquals(
            [SELECT Id FROM DealerReferenceValue__c WHERE Name = 'Alpha Architect' LIMIT 1].Id,
            created.id
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM DealerReferenceValue__c WHERE Type__c = 'Architect' AND Name = 'Alpha Architect']
        );
    }

    @IsTest
    static void create_blankName_throws() {
        Boolean threw = false;
        try {
            DealerReferencePickerController.create('Architect', '  ');
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Blank name should throw');
    }

    @IsTest
    static void resolve_createsPendingNameAndKeepsExistingId() {
        Id existingId = [SELECT Id FROM DealerReferenceValue__c WHERE Name = 'Alpha Architect' LIMIT 1].Id;
        DealerReferencePickerController.ResolveRequest request = new DealerReferencePickerController.ResolveRequest();
        request.endCustomerId = 'pending:' + EncodingUtil.urlEncode('City Hospital', 'UTF-8');
        request.architectId = existingId;
        request.competitorIds = 'pending:' + EncodingUtil.urlEncode('New Rival', 'UTF-8');

        Test.startTest();
        List<DealerReferencePickerController.ResolveResult> results =
            DealerReferencePickerController.resolve(new List<DealerReferencePickerController.ResolveRequest>{ request });
        Test.stopTest();

        System.assertEquals(existingId, results[0].architectId);
        DealerReferenceValue__c hospital = [
            SELECT Id FROM DealerReferenceValue__c WHERE Type__c = 'EndCustomer' AND Name = 'City Hospital' LIMIT 1
        ];
        System.assertEquals(hospital.Id, results[0].endCustomerId);
        DealerReferenceValue__c rival = [
            SELECT Id FROM DealerReferenceValue__c WHERE Type__c = 'Competitor' AND Name = 'New Rival' LIMIT 1
        ];
        System.assertEquals(rival.Id, results[0].competitorId);
    }

    @IsTest
    static void resolve_reusesExistingName() {
        DealerReferencePickerController.ResolveRequest request = new DealerReferencePickerController.ResolveRequest();
        request.architectId = 'pending:' + EncodingUtil.urlEncode('Alpha Architect', 'UTF-8');

        Test.startTest();
        List<DealerReferencePickerController.ResolveResult> results =
            DealerReferencePickerController.resolve(new List<DealerReferencePickerController.ResolveRequest>{ request });
        Test.stopTest();

        System.assertEquals(
            [SELECT Id FROM DealerReferenceValue__c WHERE Name = 'Alpha Architect' LIMIT 1].Id,
            results[0].architectId
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM DealerReferenceValue__c WHERE Type__c = 'Architect' AND Name = 'Alpha Architect']
        );
    }

    @IsTest
    static void saveOpportunityReferences_createsOnceAndUpdatesTwoOpportunities() {
        Account account = new Account(Name = 'Cleveland Network');
        insert account;
        List<Opportunity> opportunities = new List<Opportunity>{
            new Opportunity(Name = 'Dealer One', AccountId = account.Id, StageName = 'Discovery', CloseDate = Date.today().addDays(30), BypassValidations__c = true),
            new Opportunity(Name = 'Dealer Two', AccountId = account.Id, StageName = 'Discovery', CloseDate = Date.today().addDays(40), BypassValidations__c = true)
        };
        insert opportunities;
        Id architectId = [SELECT Id FROM DealerReferenceValue__c WHERE Name = 'Alpha Architect' LIMIT 1].Id;

        DealerReferencePickerController.ReferenceUpdate first = new DealerReferencePickerController.ReferenceUpdate();
        first.opportunityId = opportunities[0].Id;
        first.architectToken = architectId;
        first.architectName = 'Alpha Architect';
        first.endCustomerToken = 'pending:' + EncodingUtil.urlEncode('Shared Hospital', 'UTF-8');
        first.endCustomerName = 'Shared Hospital';
        first.competitorTokens = 'pending:' + EncodingUtil.urlEncode('Shared Rival', 'UTF-8');
        first.competitorNames = 'Shared Rival';

        DealerReferencePickerController.ReferenceUpdate second = new DealerReferencePickerController.ReferenceUpdate();
        second.opportunityId = opportunities[1].Id;
        second.architectToken = 'pending:' + EncodingUtil.urlEncode('Shared Hospital', 'UTF-8');
        second.architectName = 'Shared Hospital';
        second.endCustomerToken = 'pending:' + EncodingUtil.urlEncode('Shared Hospital', 'UTF-8');
        second.endCustomerName = 'Shared Hospital';

        Test.startTest();
        DealerReferencePickerController.saveReferenceUpdates(new List<DealerReferencePickerController.ReferenceUpdate>{
            first,
            second
        });
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM DealerReferenceValue__c WHERE Type__c = 'EndCustomer' AND Name = 'Shared Hospital']
        );
        Id hospitalId = [SELECT Id FROM DealerReferenceValue__c WHERE Type__c = 'EndCustomer' AND Name = 'Shared Hospital' LIMIT 1].Id;
        Map<Id, Opportunity> saved = new Map<Id, Opportunity>([
            SELECT EndCustomerName__c, ArchitectName__c, DealerCompetitors__c
            FROM Opportunity
            WHERE Id IN :opportunities
        ]);
        System.assertEquals('Shared Hospital', saved.get(opportunities[0].Id).EndCustomerName__c);
        System.assertEquals('Alpha Architect', saved.get(opportunities[0].Id).ArchitectName__c);
        System.assertEquals('Shared Rival', saved.get(opportunities[0].Id).DealerCompetitors__c);
        System.assertEquals('Shared Hospital', saved.get(opportunities[1].Id).EndCustomerName__c);
        System.assertEquals('Shared Hospital', saved.get(opportunities[1].Id).ArchitectName__c);

        DealerReferencePickerController.OpportunityReferences loaded =
            DealerReferencePickerController.loadOpportunityReferences(opportunities[0].Id);
        System.assertEquals('Shared Hospital', loaded.endCustomerName);
        System.assertEquals(String.valueOf(hospitalId), loaded.endCustomerId);
        System.assertEquals('Alpha Architect', loaded.architectName);
        System.assertEquals(String.valueOf(architectId), loaded.architectId);
        System.assertEquals('Shared Rival', loaded.competitorNames);
    }

    @IsTest
    static void save_textareaCompetitors_storesSemicolonSeparatedNames() {
        Account account = new Account(Name = 'Cleveland Network');
        insert account;
        Opportunity opportunity = new Opportunity(
            Name = 'Competitor Text',
            AccountId = account.Id,
            StageName = 'Discovery',
            CloseDate = Date.today().addDays(15),
            BypassValidations__c = true
        );
        insert opportunity;

        DealerReferencePickerController.ReferenceUpdate updateRow = new DealerReferencePickerController.ReferenceUpdate();
        updateRow.opportunityId = opportunity.Id;
        updateRow.competitorNames = 'Beta Competitor\nNew Rival; Beta Competitor';

        Test.startTest();
        DealerReferencePickerController.saveReferenceUpdates(
            new List<DealerReferencePickerController.ReferenceUpdate>{ updateRow }
        );
        Test.stopTest();

        Opportunity saved = [
            SELECT DealerCompetitors__c
            FROM Opportunity
            WHERE Id = :opportunity.Id
        ];
        System.assertEquals('Beta Competitor;New Rival', saved.DealerCompetitors__c);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM DealerReferenceValue__c WHERE Type__c = 'Competitor' AND Name = 'Beta Competitor']
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM DealerReferenceValue__c WHERE Type__c = 'Competitor' AND Name = 'New Rival']
        );
    }

    @IsTest
    static void resolve_textareaCompetitors_returnsSemicolonNames() {
        DealerReferencePickerController.ResolveRequest request = new DealerReferencePickerController.ResolveRequest();
        request.competitorNames = 'Acme\nBeta Competitor; Acme';

        Test.startTest();
        List<DealerReferencePickerController.ResolveResult> results =
            DealerReferencePickerController.resolve(new List<DealerReferencePickerController.ResolveRequest>{ request });
        Test.stopTest();

        System.assertEquals('Acme;Beta Competitor', results[0].competitorNames);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM DealerReferenceValue__c WHERE Type__c = 'Competitor' AND Name = 'Acme']
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM DealerReferenceValue__c WHERE Type__c = 'Competitor' AND Name = 'Beta Competitor']
        );
    }

    @IsTest
    static void load_returnsStoredName() {
        Account account = new Account(Name = 'Cleveland Network');
        insert account;
        Opportunity opportunity = new Opportunity(
            Name = 'Named Dealer',
            AccountId = account.Id,
            StageName = 'Discovery',
            CloseDate = Date.today().addDays(20),
            BypassValidations__c = true,
            EndCustomerName__c = 'Rahul'
        );
        insert opportunity;

        Test.startTest();
        DealerReferencePickerController.OpportunityReferences loaded =
            DealerReferencePickerController.loadOpportunityReferences(opportunity.Id);
        Test.stopTest();

        System.assertEquals('Rahul', loaded.endCustomerName);
        System.assert(loaded.endCustomerId.startsWith('pending:'), 'Stored name should be shown on the picker');
    }

    @IsTest
    static void search_invalidType_throws() {
        Boolean threw = false;
        try {
            DealerReferencePickerController.search('NotAType', 'x');
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Invalid type should throw');
    }
}