/**
 * @author PWC Developer
 * @date 2026/07/08
 *
 * @group Generate Quote
 *
 * @description Test class for SalesConnectionQuoteMockService.
 */
@IsTest
private class SalesConnectionQuoteMockServiceTest {
    @IsTest
    static void testGetTemplateAlwaysUsesOpenStatus() {
        for (Integer templateIndex = 0; templateIndex <= 6; templateIndex++) {
            System.assertEquals(
                'Open',
                SalesConnectionQuoteMockService.getTemplate(templateIndex).quoteStatus,
                'Every generated quote should use Open status for template index ' + templateIndex
            );
        }
    }

    @IsTest
    static void testTemplatesStatusResolutionAndLineBuilder() {
        Id standardPricebookId = Test.getStandardPricebookId();
        Product2 productRecord = new Product2(Name = 'Mock Service Product', IsActive = true);
        insert productRecord;

        PricebookEntry pricebookEntryRecord = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = productRecord.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pricebookEntryRecord;

        Product2 secondaryProductRecord = new Product2(
            Name = 'Mock Service Product 2',
            ProductCode = 'MOCK-SVC-002',
            IsActive = true
        );
        insert secondaryProductRecord;

        PricebookEntry secondaryPricebookEntryRecord = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = secondaryProductRecord.Id,
            UnitPrice = 200,
            IsActive = true
        );
        insert secondaryPricebookEntryRecord;

        Account accountRecord = new Account(
            Name = 'Mock Service Account',
            SourceSystemID__c = 'MOCK-SVC-ACCT',
            OracleAddressId__c = '638265'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            FirstName = 'Mock',
            LastName = 'Service Contact',
            AccountId = accountRecord.Id
        );
        insert contactRecord;

        Opportunity opportunityRecord = new Opportunity(
            Name = 'Mock Service Opportunity',
            AccountId = accountRecord.Id,
            StageName = getValidStageName(),
            CloseDate = Date.today().addDays(30),
            Amount = 1000,
            Probability = 10,
            Pricebook2Id = standardPricebookId,
            Type = getValidOpportunityType(),
            PrimaryContact__c = contactRecord.Id
        );
        insert opportunityRecord;

        Quote quoteRecord = new Quote(
            Name = 'Mock Service Quote',
            OpportunityId = opportunityRecord.Id,
            Pricebook2Id = standardPricebookId,
            Status = 'Draft',
            ExpirationDate = Date.today().addDays(30)
        );
        insert quoteRecord;

        for (Integer templateIndex = 0; templateIndex < SalesConnectionQuoteMockService.TEMPLATE_COUNT; templateIndex++) {
            SalesConnectionQuoteMockService.MockQuoteTemplate template =
                SalesConnectionQuoteMockService.getTemplate(templateIndex);
            System.assertNotEquals(null, template);
            System.assertNotEquals(null, template.quoteLines);

            SalesConnectionQuoteMockService.applyTemplateToQuote(quoteRecord, template);
            System.assertEquals(
                SalesConnectionQuoteMockService.resolveQuoteStatus(template.quoteStatus),
                quoteRecord.Status
            );
            System.assert(
                new Set<String>{ 'Open', 'Closed', 'Budget', 'Draft' }
                    .contains(quoteRecord.Status),
                'Quote status should be an HC Sales value.'
            );
            System.assertEquals(
                template.approvalStatus,
                SalesConnectionQuoteMockService.resolveApprovalStatus(template.approvalStatus)
            );
            System.assertEquals(template.lastModifiedDate, quoteRecord.LastModifiedDate__c);

            List<QuoteLineItem> quoteLineItems = SalesConnectionQuoteMockService.buildQuoteLineItems(
                quoteRecord.Id,
                new List<PricebookEntry>{ pricebookEntryRecord, secondaryPricebookEntryRecord },
                template,
                'SCQ-TEST'
            );
            System.assertEquals(template.quoteLines.size(), quoteLineItems.size());

            if (template.quoteLines.size() > 1) {
                Set<Id> assignedPricebookEntryIds = new Set<Id>();
                for (QuoteLineItem quoteLineItem : quoteLineItems) {
                    assignedPricebookEntryIds.add(quoteLineItem.PricebookEntryId);
                }

                System.assert(
                    assignedPricebookEntryIds.size() > 1,
                    'Mock quote lines should rotate across available price book entries.'
                );
            }
        }
    }

    @IsTest
    static void resolvePricebookEntryIdRotatesAcrossEntries() {
        Id standardPricebookId = Test.getStandardPricebookId();
        Product2 firstProduct = new Product2(Name = 'Rotation Product A', ProductCode = 'ROT-A', IsActive = true);
        Product2 secondProduct = new Product2(Name = 'Rotation Product B', ProductCode = 'ROT-B', IsActive = true);
        insert new List<Product2>{ firstProduct, secondProduct };

        PricebookEntry firstEntry = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = firstProduct.Id,
            UnitPrice = 100,
            IsActive = true
        );
        PricebookEntry secondEntry = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = secondProduct.Id,
            UnitPrice = 200,
            IsActive = true
        );
        insert new List<PricebookEntry>{ firstEntry, secondEntry };

        List<PricebookEntry> entries = new List<PricebookEntry>{ firstEntry, secondEntry };
        Id firstResolved = SalesConnectionQuoteMockService.resolvePricebookEntryId('999', 'Unknown Product', 0, entries);
        Id secondResolved = SalesConnectionQuoteMockService.resolvePricebookEntryId('999', 'Unknown Product', 1, entries);

        System.assertEquals(firstEntry.Id, firstResolved);
        System.assertEquals(secondEntry.Id, secondResolved);
        System.assertNotEquals(firstResolved, secondResolved);
    }

    @IsTest
    static void resolveQuoteLineDescriptionUsesIntegrationNameForRotatedEntry() {
        Id standardPricebookId = Test.getStandardPricebookId();
        Product2 productRecord = new Product2(
            Name = ']',
            ProductCode = 'BAD-001',
            IsActive = true
        );
        insert productRecord;

        PricebookEntry pricebookEntryRecord = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = productRecord.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pricebookEntryRecord;

        pricebookEntryRecord = [
            SELECT Id, Product2.Name
            FROM PricebookEntry
            WHERE Id = :pricebookEntryRecord.Id
            LIMIT 1
        ];

        SalesConnectionQuoteMockService.PricebookEntryResolution resolution =
            new SalesConnectionQuoteMockService.PricebookEntryResolution();
        resolution.pricebookEntryId = pricebookEntryRecord.Id;
        resolution.exactMatch = false;

        System.assertEquals(
            'Washer-Disinfector',
            SalesConnectionQuoteMockService.resolveQuoteLineDescription(
                'Washer-Disinfector',
                resolution,
                new List<PricebookEntry>{ pricebookEntryRecord }
            )
        );
    }

    @IsTest
    static void resolveLineDescriptionPrefersProductName() {
        Id standardPricebookId = Test.getStandardPricebookId();
        Product2 productRecord = new Product2(
            Name = 'Actual Product Name',
            ProductCode = 'DESC-TEST-001',
            IsActive = true
        );
        insert productRecord;

        PricebookEntry pricebookEntryRecord = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = productRecord.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pricebookEntryRecord;

        pricebookEntryRecord = [
            SELECT Id, Product2.Name
            FROM PricebookEntry
            WHERE Id = :pricebookEntryRecord.Id
            LIMIT 1
        ];

        System.assertEquals(
            'Actual Product Name',
            SalesConnectionQuoteMockService.resolveLineDescription(
                'Barrier Product 700',
                pricebookEntryRecord.Id,
                new List<PricebookEntry>{ pricebookEntryRecord }
            )
        );
    }

    @IsTest
    static void buildRefreshQuoteResponseBodyReturnsExistingQuotes() {
        Id standardPricebookId = Test.getStandardPricebookId();
        Account accountRecord = new Account(
            Name = 'Refresh Body Account',
            SourceSystemID__c = 'MOCK-REFRESH-BODY',
            OracleAddressId__c = '638267'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            FirstName = 'Refresh',
            LastName = 'Body Contact',
            AccountId = accountRecord.Id
        );
        insert contactRecord;

        Opportunity opportunityRecord = new Opportunity(
            Name = 'Refresh Body Opportunity',
            AccountId = accountRecord.Id,
            StageName = getValidStageName(),
            CloseDate = Date.today().addDays(30),
            Amount = 1000,
            Probability = 10,
            Pricebook2Id = standardPricebookId,
            Type = getValidOpportunityType(),
            PrimaryContact__c = contactRecord.Id
        );
        insert opportunityRecord;

        Quote quoteRecord = new Quote(
            Name = 'Refresh Body Quote',
            OpportunityId = opportunityRecord.Id,
            Pricebook2Id = standardPricebookId,
            Status = 'Draft',
            ExpirationDate = Date.today().addDays(45)
        );
        insert quoteRecord;

        Test.startTest();
        String responseBody = SalesConnectionQuoteMockService.buildRefreshQuoteResponseBody(
            opportunityRecord.Id
        );
        Test.stopTest();

        List<Object> apiQuotes = (List<Object>) JSON.deserializeUntyped(responseBody);
        System.assertEquals(1, apiQuotes.size());

        Map<String, Object> apiQuote = (Map<String, Object>) apiQuotes[0];
        System.assertEquals(String.valueOf(quoteRecord.Id), apiQuote.get('id'));
        System.assertEquals('Refresh Body Quote', apiQuote.get('quoteName'));
        System.assertEquals('Open', apiQuote.get('status'));
        System.assertNotEquals(null, apiQuote.get('productSubgroupSummary'));
    }

    @IsTest
    static void buildRefreshQuoteResponseBodyReturnsEmptyArrayForNullOpportunity() {
        System.assertEquals('[]', SalesConnectionQuoteMockService.buildRefreshQuoteResponseBody(null));
    }

    private static String getValidStageName() {
        for (Schema.PicklistEntry picklistEntry : Opportunity.StageName.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return 'Discovery';
    }

    private static String getValidOpportunityType() {
        for (Schema.PicklistEntry picklistEntry : Opportunity.Type.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return null;
    }
}