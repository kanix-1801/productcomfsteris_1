/**
 * @author PWC Developer
 * @date 2026/07/08
 *
 * @group Generate Quote
 *
 * @description Test class for RefreshQuoteSyncService.
 */
@IsTest
private class RefreshQuoteSyncServiceTest {
    private static final String TEST_OPPORTUNITY_NAME = 'Refresh Sync Test Opportunity';

    @TestSetup
    static void setupData() {
        Id standardPricebookId = Test.getStandardPricebookId();

        Product2 productRecord = new Product2(
            Name = 'Refresh Sync Product',
            ProductCode = '027',
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

        Account accountRecord = new Account(
            Name = 'Refresh Sync Account',
            SourceSystemID__c = 'RS-ACCT',
            OracleAddressId__c = '638265'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            FirstName = 'Refresh',
            LastName = 'Sync Contact',
            AccountId = accountRecord.Id
        );
        insert contactRecord;

        Opportunity opportunityRecord = buildOpportunity(
            TEST_OPPORTUNITY_NAME,
            accountRecord.Id,
            contactRecord.Id,
            standardPricebookId
        );
        insert opportunityRecord;

        insert new OpportunityLineItem(
            OpportunityId = opportunityRecord.Id,
            PricebookEntryId = pricebookEntryRecord.Id,
            Quantity = 1,
            UnitPrice = 100
        );
    }

    private static Opportunity buildOpportunity(
        String opportunityName,
        Id accountId,
        Id primaryContactId,
        Id pricebookId
    ) {
        Opportunity opportunityRecord = new Opportunity(
            Name = opportunityName,
            AccountId = accountId,
            StageName = getValidStageName(),
            ForecastConfidenceLevel__c = getValidForecastConfidenceLevel(),
            CloseDate = Date.today().addDays(30),
            Amount = 1000,
            Probability = 10,
            PrimaryContact__c = primaryContactId
        );

        String opportunityType = getValidOpportunityType();
        if (String.isNotBlank(opportunityType)) {
            opportunityRecord.Type = opportunityType;
        }

        if (pricebookId != null) {
            opportunityRecord.Pricebook2Id = pricebookId;
        }

        return opportunityRecord;
    }

    @IsTest
    static void syncReturnsEmptySetWhenIntegrationPayloadIsEmpty() {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        Test.startTest();
        Set<Id> syncedQuoteIds = RefreshQuoteSyncService.syncIntegrationQuotes(
            opportunityRecord.Id,
            new List<GenerateQuoteController.QuoteWrapper>()
        );
        Test.stopTest();

        System.assertEquals(0, syncedQuoteIds.size());
    }

    @IsTest
    static void syncUpdatesExistingQuoteHeaderAndLines() {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        Quote existingQuote = insertOpenTestQuote(opportunityRecord.Id);
        existingQuote = [
            SELECT Id, SalesConnectionQuoteID__c, QuoteNumber__c, Description, Approval_Status__c,
                (SELECT Id, Description, Product_FAM_Code__c, SalesConnectionQuoteLineID__c, UnitPrice
                 FROM QuoteLineItems)
            FROM Quote
            WHERE Id = :existingQuote.Id
            LIMIT 1
        ];

        GenerateQuoteController.QuoteWrapper integrationQuote = buildIntegrationQuoteWrapper();

        Test.startTest();
        Set<Id> syncedQuoteIds = RefreshQuoteSyncService.syncIntegrationQuotes(
            opportunityRecord.Id,
            new List<GenerateQuoteController.QuoteWrapper>{ integrationQuote }
        );
        Test.stopTest();

        System.assertEquals(1, syncedQuoteIds.size());
        System.assert(syncedQuoteIds.contains(existingQuote.Id));

        Quote updatedQuote = [
            SELECT SalesConnectionQuoteID__c,
                QuoteNumber__c,
                Description,
                Approval_Status__c,
                Quote_Total_Without_Freight__c,
                (
                    SELECT Description,
                        Product_FAM_Code__c,
                        Product_Subgroup_Detail_Name__c,
                        SalesConnectionQuoteLineID__c,
                        UnitPrice,
                        Total_Unit_Price__c
                    FROM QuoteLineItems
                    ORDER BY SalesConnectionQuoteLineID__c ASC
                )
            FROM Quote
            WHERE Id = :existingQuote.Id
        ];

        System.assertEquals('00003956', updatedQuote.QuoteNumber__c);
        System.assertEquals('2283624', updatedQuote.SalesConnectionQuoteID__c);
        System.assertEquals('Endoscopy equipment upgrade', updatedQuote.Description);
        System.assertEquals('Approved', updatedQuote.Approval_Status__c);
        System.assertEquals(30000, updatedQuote.Quote_Total_Without_Freight__c);
        System.assert(updatedQuote.QuoteLineItems.size() >= 1);

        QuoteLineItem updatedLine;
        for (QuoteLineItem quoteLineItem : updatedQuote.QuoteLineItems) {
            if (quoteLineItem.SalesConnectionQuoteLineID__c != null
                && quoteLineItem.SalesConnectionQuoteLineID__c.endsWith('QL-001')) {
                updatedLine = quoteLineItem;
                break;
            }
        }

        System.assertNotEquals(null, updatedLine, 'Expected refreshed QL-001 line to exist.');
        System.assertEquals('Refresh Sync Product', updatedLine.Description);
        System.assertEquals('027', updatedLine.Product_FAM_Code__c);
        System.assertEquals(30000, updatedLine.UnitPrice);
    }

    @IsTest
    static void syncDemotesOpenQuotesToDraft() {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        Quote openQuote = insertOpenTestQuote(opportunityRecord.Id);
        openQuote = [
            SELECT Id, Status
            FROM Quote
            WHERE Id = :openQuote.Id
        ];
        System.assertEquals('Open', openQuote.Status, 'Precondition: generated quote should be Open.');

        GenerateQuoteController.QuoteWrapper integrationQuote = buildIntegrationQuoteWrapper();
        integrationQuote.id = openQuote.Id;
        integrationQuote.status = 'Open';

        Test.startTest();
        RefreshQuoteSyncService.syncIntegrationQuotes(
            opportunityRecord.Id,
            new List<GenerateQuoteController.QuoteWrapper>{ integrationQuote }
        );
        Test.stopTest();

        Quote refreshedQuote = [
            SELECT Status
            FROM Quote
            WHERE Id = :openQuote.Id
        ];
        System.assertEquals(
            'Draft',
            refreshedQuote.Status,
            'Refresh Quote should demote Open quotes to Draft.'
        );
    }

    @IsTest
    static void syncInsertsQuoteWhenNoExistingQuoteFound() {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        GenerateQuoteController.QuoteWrapper integrationQuote = buildIntegrationQuoteWrapper();

        Test.startTest();
        Set<Id> syncedQuoteIds = RefreshQuoteSyncService.syncIntegrationQuotes(
            opportunityRecord.Id,
            new List<GenerateQuoteController.QuoteWrapper>{ integrationQuote }
        );
        Test.stopTest();

        System.assertEquals(1, syncedQuoteIds.size());

        Quote insertedQuote = [
            SELECT Id, SalesConnectionQuoteID__c, QuoteNumber__c, Name,
                (SELECT Id FROM QuoteLineItems)
            FROM Quote
            WHERE OpportunityId = :opportunityRecord.Id
            LIMIT 1
        ];

        System.assertEquals('00003956', insertedQuote.QuoteNumber__c);
        System.assertEquals('2283624', insertedQuote.SalesConnectionQuoteID__c);
        System.assertEquals('Quote - QA_GC2628_Test1', insertedQuote.Name);
        System.assertEquals(1, insertedQuote.QuoteLineItems.size());
    }

    @IsTest
    static void syncMatchesExistingQuoteBySalesConnectionQuoteId() {
        Opportunity opportunityRecord = [
            SELECT Id, Pricebook2Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];

        Quote existingQuote = new Quote(
            Name = 'Existing Sync Quote',
            OpportunityId = opportunityRecord.Id,
            Pricebook2Id = opportunityRecord.Pricebook2Id,
            Status = 'Draft',
            ExpirationDate = Date.today().addDays(10),
            SalesConnectionQuoteID__c = '2283624'
        );
        insert existingQuote;

        GenerateQuoteController.QuoteWrapper integrationQuote = buildIntegrationQuoteWrapper();

        Test.startTest();
        Set<Id> syncedQuoteIds = RefreshQuoteSyncService.syncIntegrationQuotes(
            opportunityRecord.Id,
            new List<GenerateQuoteController.QuoteWrapper>{ integrationQuote }
        );
        Test.stopTest();

        System.assertEquals(1, syncedQuoteIds.size());
        System.assert(syncedQuoteIds.contains(existingQuote.Id));
    }

    @IsTest
    static void syncRequiresPricebookForInsert() {
        Account accountRecord = [SELECT Id FROM Account LIMIT 1];
        Contact contactRecord = [SELECT Id FROM Contact LIMIT 1];

        Opportunity opportunityWithoutPricebook = buildOpportunity(
            'Refresh Sync No Pricebook',
            accountRecord.Id,
            contactRecord.Id,
            null
        );
        insert opportunityWithoutPricebook;

        GenerateQuoteController.QuoteWrapper integrationQuote = buildIntegrationQuoteWrapper();
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            RefreshQuoteSyncService.syncIntegrationQuotes(
                opportunityWithoutPricebook.Id,
                new List<GenerateQuoteController.QuoteWrapper>{ integrationQuote }
            );
        } catch (GenerateQuoteException exceptionValue) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected sync to fail when Price Book is missing.');
    }

    @IsTest
    static void resolveStatusHelpersMapIntegrationValues() {
        System.assertEquals('Open', SalesConnectionQuoteMockService.resolveQuoteStatus('Open'));
        System.assertEquals('Closed', SalesConnectionQuoteMockService.resolveQuoteStatus('Closed'));
        System.assertEquals('Budget', SalesConnectionQuoteMockService.resolveQuoteStatus('Budget'));
        System.assertEquals('Draft', SalesConnectionQuoteMockService.resolveQuoteStatus('Draft'));
        System.assertEquals('Draft', SalesConnectionQuoteMockService.resolveQuoteStatus('Unknown'));
        System.assertEquals('Approved', SalesConnectionQuoteMockService.resolveApprovalStatus('Approved'));
        System.assertEquals(
            'SCQ-001-QL-001',
            SalesConnectionQuoteMockService.buildUniqueQuoteLineId('QL-001', 'SCQ-001')
        );
    }

    private static Quote insertOpenTestQuote(Id opportunityId) {
        Opportunity opportunityRecord = [
            SELECT Id, Pricebook2Id
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        Quote quoteRecord = new Quote(
            Name = 'Open Sync Quote',
            OpportunityId = opportunityRecord.Id,
            Pricebook2Id = opportunityRecord.Pricebook2Id,
            Status = 'Open',
            ExpirationDate = Date.today().addDays(30),
            SalesConnectionQuoteID__c = '2283624'
        );

        Id recordTypeId = GenerateQuoteService.resolveHcSalesQuoteRecordTypeId();
        if (recordTypeId != null) {
            quoteRecord.RecordTypeId = recordTypeId;
        }

        insert quoteRecord;
        return quoteRecord;
    }

    private static GenerateQuoteController.QuoteWrapper buildIntegrationQuoteWrapper() {
        GenerateQuoteController.QuoteLineDetailWrapper lineWrapper =
            new GenerateQuoteController.QuoteLineDetailWrapper();
        lineWrapper.quoteLineId = 'QL-001';
        lineWrapper.productName = 'Refresh Sync Product';
        lineWrapper.productFAMCode = '027';
        lineWrapper.productSubgroupDetailName = 'AER';
        lineWrapper.quantity = 1;
        lineWrapper.unitPrice = 30000;
        lineWrapper.lineTotal = 30000;

        GenerateQuoteController.ProductSubgroupSummaryWrapper subgroupWrapper =
            new GenerateQuoteController.ProductSubgroupSummaryWrapper();
        subgroupWrapper.productSubgroupDetailName = 'AER';
        subgroupWrapper.totalUnitPrice = 30000;
        subgroupWrapper.quoteLines = new List<GenerateQuoteController.QuoteLineDetailWrapper>{ lineWrapper };

        GenerateQuoteController.QuoteWrapper quoteWrapper = new GenerateQuoteController.QuoteWrapper();
        quoteWrapper.quoteNumber = '00003956';
        quoteWrapper.salesConnectionQuoteId = '2283624';
        quoteWrapper.quoteName = 'Quote - QA_GC2628_Test1';
        quoteWrapper.expirationDate = Date.newInstance(2026, 8, 5);
        quoteWrapper.description = 'Endoscopy equipment upgrade';
        quoteWrapper.status = 'Draft';
        quoteWrapper.approvalStatus = 'Approved';
        quoteWrapper.quoteTotalWithoutFreight = 97000;
        quoteWrapper.productSubgroupSummary =
            new List<GenerateQuoteController.ProductSubgroupSummaryWrapper>{ subgroupWrapper };

        return quoteWrapper;
    }

    private static String getValidStageName() {
        for (Schema.PicklistEntry picklistEntry : Opportunity.StageName.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return 'Discovery';
    }

    private static String getValidForecastConfidenceLevel() {
        for (Schema.PicklistEntry picklistEntry :
            Opportunity.ForecastConfidenceLevel__c.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return null;
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