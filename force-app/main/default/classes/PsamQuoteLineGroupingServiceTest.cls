/**
 * @author PWC Developer
 * @date 2026/07/07
 *
 * @group Generate Quote
 *
 * @description
 * Test class for PSAM-based quote line grouping.
 */
@IsTest
private class PsamQuoteLineGroupingServiceTest {
    @TestSetup
    static void setupPsamData() {
        insert new List<PSAM__c>{
            buildPsam('AER 027', '027', 'AER'),
            buildPsam('AER 045', '045', 'AER'),
            buildPsam('Barrier 700', '700', 'Barrier Products'),
            buildPsam('Barrier 703', '703', 'Barrier Products')
        };
    }

    @IsTest
    static void testBuildGroupedSummaryGroupsByProductPsamLookup() {
        PSAM__c aerPsam = [
            SELECT Id, ProductFAMCode__c, ProductSubgroupDetailName__c
            FROM PSAM__c
            WHERE ProductFAMCode__c = '027'
            LIMIT 1
        ];
        PSAM__c barrierPsam = [
            SELECT Id, ProductFAMCode__c, ProductSubgroupDetailName__c
            FROM PSAM__c
            WHERE ProductFAMCode__c = '700'
            LIMIT 1
        ];

        List<QuoteLineItem> quoteLineItems = new List<QuoteLineItem>{
            buildQuoteLineWithProductPsam('QL-001', 'AER Product 027', aerPsam, 1, 100),
            buildQuoteLineWithProductPsam('QL-002', 'Barrier Product 700', barrierPsam, 2, 50)
        };

        Test.startTest();
        List<GenerateQuoteController.ProductSubgroupSummaryWrapper> groupedSummary =
            PsamQuoteLineGroupingService.buildGroupedSummary(quoteLineItems);
        Test.stopTest();

        Map<String, GenerateQuoteController.ProductSubgroupSummaryWrapper> summaryByName =
            new Map<String, GenerateQuoteController.ProductSubgroupSummaryWrapper>();

        for (GenerateQuoteController.ProductSubgroupSummaryWrapper subgroup : groupedSummary) {
            summaryByName.put(subgroup.productSubgroupDetailName, subgroup);
        }

        System.assertEquals(2, groupedSummary.size(), 'Lines should group by Product PSAM lookup.');
        System.assertEquals(1, summaryByName.get('AER').quoteLines.size());
        System.assertEquals(1, summaryByName.get('Barrier Products').quoteLines.size());
        System.assertEquals('027', summaryByName.get('AER').quoteLines[0].productFAMCode);
    }

    @IsTest
    static void testApplyPsamSubgroupDetailNamesUsesProductPsamLookup() {
        PSAM__c barrierPsam = [
            SELECT Id, ProductFAMCode__c, ProductSubgroupDetailName__c
            FROM PSAM__c
            WHERE ProductFAMCode__c = '700'
            LIMIT 1
        ];
        QuoteLineItem quoteLineItem = buildQuoteLineWithProductPsam(
            'QL-999',
            'Unknown Product',
            barrierPsam,
            1,
            10
        );
        quoteLineItem.Product_FAM_Code__c = null;
        quoteLineItem.Product_Subgroup_Detail_Name__c = null;

        Test.startTest();
        PsamQuoteLineGroupingService.applyPsamSubgroupDetailNames(
            new List<QuoteLineItem>{ quoteLineItem }
        );
        Test.stopTest();

        System.assertEquals('Barrier Products', quoteLineItem.Product_Subgroup_Detail_Name__c);
    }

    @IsTest
    static void testBuildGroupedSummaryGroupsByPsamSubgroupDetailName() {
        List<QuoteLineItem> quoteLineItems = new List<QuoteLineItem>{
            buildQuoteLine('QL-001', 'AER Product 027', '027', 1, 100),
            buildQuoteLine('QL-002', 'AER Product 045', '045', 2, 50),
            buildQuoteLine('QL-003', 'Barrier Product 700', '700', 1, 200),
            buildQuoteLine('QL-004', 'Barrier Product 703', '703', 3, 25)
        };

        Test.startTest();
        List<GenerateQuoteController.ProductSubgroupSummaryWrapper> groupedSummary =
            PsamQuoteLineGroupingService.buildGroupedSummary(quoteLineItems);
        Test.stopTest();

        Map<String, GenerateQuoteController.ProductSubgroupSummaryWrapper> summaryByName =
            new Map<String, GenerateQuoteController.ProductSubgroupSummaryWrapper>();

        for (GenerateQuoteController.ProductSubgroupSummaryWrapper subgroup : groupedSummary) {
            summaryByName.put(subgroup.productSubgroupDetailName, subgroup);
        }

        System.assertEquals(2, groupedSummary.size(), 'Lines should group into two PSAM subgroups.');
        System.assertEquals(2, summaryByName.get('AER').quoteLines.size(), 'Two AER lines expected.');
        System.assertEquals(2, summaryByName.get('Barrier Products').quoteLines.size(), 'Two Barrier lines expected.');
        System.assertEquals(200, summaryByName.get('AER').totalUnitPrice);
        System.assertEquals(275, summaryByName.get('Barrier Products').totalUnitPrice);
        System.assertEquals('027', summaryByName.get('AER').quoteLines[0].productFAMCode);
    }

    @IsTest
    static void testApplyPsamSubgroupDetailNamesUsesPsamMasterData() {
        QuoteLineItem quoteLineItem = buildQuoteLine('QL-999', 'Unknown Product', '700', 1, 10);

        Test.startTest();
        PsamQuoteLineGroupingService.applyPsamSubgroupDetailNames(
            new List<QuoteLineItem>{ quoteLineItem }
        );
        Test.stopTest();

        System.assertEquals('Barrier Products', quoteLineItem.Product_Subgroup_Detail_Name__c);
    }

    @IsTest
    static void testBuildGroupedSummaryUsesPersistedSubgroupWithoutPsamLookup() {
        QuoteLineItem quoteLineItem = buildQuoteLine('QL-100', 'Stored Subgroup Product', '999', 1, 10);
        quoteLineItem.Product_Subgroup_Detail_Name__c = 'Stored Subgroup';

        Test.startTest();
        List<GenerateQuoteController.ProductSubgroupSummaryWrapper> groupedSummary =
            PsamQuoteLineGroupingService.buildGroupedSummary(
                new List<QuoteLineItem>{ quoteLineItem },
                new Map<String, PSAM__c>()
            );
        Test.stopTest();

        System.assertEquals(1, groupedSummary.size());
        System.assertEquals('Stored Subgroup', groupedSummary[0].productSubgroupDetailName);
    }

    @IsTest
    static void testResolveFamCodeFromProductPsamRelationship() {
        QuoteLineItem quoteLineItem = new QuoteLineItem();
        Product2 productRecord = new Product2();
        productRecord.putSObject(
            ProductPsamLookupService.PRODUCT_PSAM_RELATIONSHIP,
            new PSAM__c(ProductFAMCode__c = '027')
        );
        quoteLineItem.PricebookEntry = new PricebookEntry(Product2 = productRecord);

        System.assertEquals('027', PsamQuoteLineGroupingService.resolveFamCode(quoteLineItem));
    }

    @IsTest
    static void testBuildGroupedSummaryPrefersDescriptionOverCatalogName() {
        QuoteLineItem quoteLineItem = buildQuoteLine('QL-200', 'Barrier Product 700', '700', 1, 100);
        quoteLineItem.PricebookEntry = new PricebookEntry(
            Product2 = new Product2(Name = 'Real Salesforce Product')
        );

        List<GenerateQuoteController.ProductSubgroupSummaryWrapper> groupedSummary =
            PsamQuoteLineGroupingService.buildGroupedSummary(
                new List<QuoteLineItem>{ quoteLineItem }
            );

        System.assertEquals(1, groupedSummary.size());
        System.assertEquals('Barrier Product 700', groupedSummary[0].quoteLines[0].productName);
    }

    @IsTest
    static void testBuildGroupedSummarySkipsInvalidCatalogName() {
        QuoteLineItem quoteLineItem = buildQuoteLine('QL-201', 'Steam Sterilizer', 'STER1', 1, 100);
        quoteLineItem.PricebookEntry = new PricebookEntry(
            Product2 = new Product2(Name = ']')
        );

        List<GenerateQuoteController.ProductSubgroupSummaryWrapper> groupedSummary =
            PsamQuoteLineGroupingService.buildGroupedSummary(
                new List<QuoteLineItem>{ quoteLineItem }
            );

        System.assertEquals(1, groupedSummary.size());
        System.assertEquals('Steam Sterilizer', groupedSummary[0].quoteLines[0].productName);
    }

    private static PSAM__c buildPsam(String name, String famCode, String detailName) {
        return new PSAM__c(
            Name = name,
            ProductFAMCode__c = famCode,
            ProductGroupName__c = 'Test Group',
            ProductSubgroupName__c = 'Test Subgroup',
            ProductSubgroupDetailName__c = detailName
        );
    }

    private static QuoteLineItem buildQuoteLineWithProductPsam(
        String quoteLineId,
        String productName,
        PSAM__c psamRecord,
        Decimal quantity,
        Decimal unitPrice
    ) {
        QuoteLineItem quoteLineItem = new QuoteLineItem();
        quoteLineItem.Description = productName;
        quoteLineItem.SalesConnectionQuoteLineID__c = quoteLineId;
        quoteLineItem.Quantity = quantity;
        quoteLineItem.UnitPrice = unitPrice;

        Product2 productRecord = new Product2();
        productRecord.put(ProductPsamLookupService.PRODUCT_PSAM_LOOKUP_FIELD, psamRecord.Id);
        productRecord.putSObject(ProductPsamLookupService.PRODUCT_PSAM_RELATIONSHIP, psamRecord);
        quoteLineItem.PricebookEntry = new PricebookEntry(Product2 = productRecord);
        return quoteLineItem;
    }

    private static QuoteLineItem buildQuoteLine(
        String quoteLineId,
        String productName,
        String famCode,
        Decimal quantity,
        Decimal unitPrice
    ) {
        QuoteLineItem quoteLineItem = new QuoteLineItem();
        quoteLineItem.Description = productName;
        quoteLineItem.Product_FAM_Code__c = famCode;
        quoteLineItem.SalesConnectionQuoteLineID__c = quoteLineId;
        quoteLineItem.Quantity = quantity;
        quoteLineItem.UnitPrice = unitPrice;
        return quoteLineItem;
    }
}