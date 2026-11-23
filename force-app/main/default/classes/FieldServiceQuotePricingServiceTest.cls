/**
 * @description GW-5890: Covers the mobile pricing result without starting the Oracle flow.
 */
@IsTest
private class FieldServiceQuotePricingServiceTest {
    @IsTest
    static void calculatePricingRequiresAQuote() {
        AuraHandledException thrown;
        try {
            FieldServiceQuotePricingService.calculatePricing(null);
        } catch (AuraHandledException ex) {
            thrown = ex;
        }
        System.assertNotEquals(null, thrown, 'A missing quote should be rejected.');
        System.assert(thrown.getMessage().contains('quote'), thrown.getMessage());
    }

    @IsTest
    static void calculatePricingReturnsTheQuoteMessage() {
        Quote quoteRecord = insertQuote('GW-5890 Pricing', 'Pricing Error', 'Account Org ID is required for Oracle pricing.');

        Test.startTest();
        FieldServiceQuotePricingService.PricingResult result = FieldServiceQuotePricingService.calculatePricing(quoteRecord.Id);
        Test.stopTest();

        System.assertEquals('Pricing Error', result.status);
        System.assertEquals('Account Org ID is required for Oracle pricing.', result.message);
    }

    @IsTest
    static void calculatePricingPrefersTheFlowFault() {
        Quote quoteRecord = insertQuote('GW-5890 Fault', null, null);
        FieldServiceQuotePricingService.testFlowMessage = 'Ship-to account 1001 has no Oracle org id.';

        Test.startTest();
        FieldServiceQuotePricingService.PricingResult result = FieldServiceQuotePricingService.calculatePricing(quoteRecord.Id);
        Test.stopTest();

        System.assertEquals('Ship-to account 1001 has no Oracle org id.', result.message);
    }

    @IsTest
    static void calculatePricingReportsSuccessWhenTheQuoteIsPriced() {
        Quote quoteRecord = insertQuote('GW-5890 Priced', 'Priced', null);

        Test.startTest();
        FieldServiceQuotePricingService.PricingResult result = FieldServiceQuotePricingService.calculatePricing(quoteRecord.Id);
        Test.stopTest();

        System.assertEquals('Priced', result.status);
        System.assertEquals('Pricing calculated.', result.message);
    }

    @IsTest
    static void calculatePricingReportsAMissingQuote() {
        Quote quoteRecord = insertQuote('GW-5890 Missing', null, null);
        delete quoteRecord;

        AuraHandledException thrown;
        Test.startTest();
        try {
            FieldServiceQuotePricingService.calculatePricing(quoteRecord.Id);
        } catch (AuraHandledException ex) {
            thrown = ex;
        }
        Test.stopTest();

        System.assertNotEquals(null, thrown, 'A deleted quote should be reported.');
        System.assert(thrown.getMessage().contains('not found'), thrown.getMessage());
    }

    @IsTest
    static void calculatePricingReportsFailureWhenNothingWasPriced() {
        Quote quoteRecord = insertQuote('GW-5890 Empty', null, null);
        FieldServiceQuotePricingService.testFlowMessage = '   ';

        Test.startTest();
        FieldServiceQuotePricingService.PricingResult result = FieldServiceQuotePricingService.calculatePricing(quoteRecord.Id);
        Test.stopTest();

        System.assertEquals('Pricing could not be completed.', result.message);
    }

    private static Quote insertQuote(String name, String pricingStatus, String pricingMessage) {
        Account accountRecord = new Account(
            Name = name + ' Account',
            SourceSystemID__c = 'GW5890' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );
        insert accountRecord;
        Contact contactRecord = new Contact(FirstName = 'GW', LastName = '5890', AccountId = accountRecord.Id);
        insert contactRecord;

        String opportunityType;
        for (Schema.PicklistEntry entry : Opportunity.Type.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                opportunityType = entry.getValue();
                break;
            }
        }
        Opportunity opportunityRecord = new Opportunity(
            Name = name + ' Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Discovery',
            ForecastConfidenceLevel__c = 'Pipeline',
            CloseDate = Date.today().addDays(30),
            Amount = 1000,
            Probability = 10,
            Type = opportunityType,
            PrimaryContact__c = contactRecord.Id
        );
        Schema.RecordTypeInfo healthcareSales = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get('Healthcare_Sales');
        if (healthcareSales != null) {
            opportunityRecord.RecordTypeId = healthcareSales.getRecordTypeId();
        }
        insert opportunityRecord;

        Quote quoteRecord = new Quote(
            Name = name + ' Quote',
            OpportunityId = opportunityRecord.Id,
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId(),
            PricingStatus__c = pricingStatus,
            PricingMessage__c = pricingMessage
        );
        insert quoteRecord;
        return quoteRecord;
    }
}