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