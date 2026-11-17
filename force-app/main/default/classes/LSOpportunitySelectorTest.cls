/**
 * @description GCL-66 - Covers LSOpportunitySelector.selectById.
 */
@IsTest(SeeAllData=false)
private class LSOpportunitySelectorTest {

    @IsTest
    static void returnsNullWhenIdIsMissing() {
        System.assertEquals(null, LSOpportunitySelector.selectById(null));
    }

    @IsTest
    static void returnsNullWhenTheOpportunityDoesNotExist() {
        Id missingId = Id.valueOf(
            Opportunity.SObjectType.getDescribe().getKeyPrefix() + '000000000001'
        );

        System.assertEquals(null, LSOpportunitySelector.selectById(missingId));
    }

    @IsTest
    static void returnsTheOpportunity() {
        Account accountRecord = new Account(
            Name = 'GCL66 ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            SourceSystemID__c = String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );
        insert accountRecord;
        Contact contactRecord = new Contact(
            LastName = 'GCL66',
            AccountId = accountRecord.Id
        );
        insert contactRecord;
        Opportunity opportunityRecord = new Opportunity(
            Name = 'GCL66 Opportunity',
            AccountId = accountRecord.Id,
            RecordTypeId = Opportunity.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .getRecordTypeInfosByDeveloperName()
                .get('LSSalesConsumables')
                .getRecordTypeId(),
            StageName = 'Discovery',
            PositionInFunnel__c = 'Above Funnel',
            ForecastConfidenceLevel__c = 'Pipeline',
            Type = 'New Business',
            Amount = 1000,
            Probability = 10,
            PrimaryContact__c = contactRecord.Id,
            CloseDate = Date.today().addDays(30)
        );
        insert opportunityRecord;

        Opportunity selected = LSOpportunitySelector.selectById(opportunityRecord.Id);

        System.assertEquals(opportunityRecord.Id, selected.Id);
    }
}