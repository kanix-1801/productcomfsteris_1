/**
 * @author PWC Developer
 * @date 2026/07/27
 *
 * @group Generate Quote
 *
 * @description GC-2642 - Tests for Quote Line sales category resolution and grouping.
 */
@IsTest
private class QuoteLineSalesCategoryServiceTest {
    @IsTest
    static void buildGroupedSummary_groupsBySalesCategory() {
        QuoteLineItem lineOne = buildQuoteLine('SURG SPT', 'Surgical Support', 'TERR-001', 100);
        QuoteLineItem lineTwo = buildQuoteLine('SURG SPT', 'Surgical Support', 'TERR-001', 50);
        QuoteLineItem lineThree = buildQuoteLine('ORI', 'Orthopedic', 'TERR-002', 75);

        Test.startTest();
        List<GenerateQuoteController.ProductSubgroupSummaryWrapper> groups =
            QuoteLineSalesCategoryService.buildGroupedSummary(
                new List<QuoteLineItem>{ lineOne, lineTwo, lineThree }
            );
        Test.stopTest();

        System.assertEquals(2, groups.size(), 'Should create one group per sales category');

        Map<String, GenerateQuoteController.ProductSubgroupSummaryWrapper> groupsByName =
            new Map<String, GenerateQuoteController.ProductSubgroupSummaryWrapper>();
        for (GenerateQuoteController.ProductSubgroupSummaryWrapper groupRow : groups) {
            groupsByName.put(groupRow.productSubgroupDetailName, groupRow);
        }

        System.assertEquals(2, groupsByName.get('SURG SPT').quoteLines.size());
        System.assertEquals(150, groupsByName.get('SURG SPT').totalUnitPrice);
        System.assertEquals(1, groupsByName.get('ORI').quoteLines.size());
    }

    @IsTest
    static void buildGroupedSummary_prefersDescriptionOverInvalidCatalogName() {
        QuoteLineItem quoteLineItem = buildQuoteLine('PMI', 'Preventive Maintenance', 'TERR-001', 84500);
        quoteLineItem.Description = 'Washer Disinfector';
        quoteLineItem.PricebookEntry = new PricebookEntry(
            Product2 = new Product2(Name = ']')
        );

        List<GenerateQuoteController.ProductSubgroupSummaryWrapper> groups =
            QuoteLineSalesCategoryService.buildGroupedSummary(
                new List<QuoteLineItem>{ quoteLineItem }
            );

        System.assertEquals(1, groups.size());
        System.assertEquals(
            'Washer Disinfector',
            groups[0].quoteLines[0].productName,
            'Sales category grouping should prefer line description over invalid catalog names'
        );
    }

    @IsTest
    static void resolveSalesCategoryFromIntegration_prefersTasSalesCategory() {
        System.assertEquals(
            'SURG SPT',
            QuoteLineSalesCategoryService.resolveSalesCategoryFromIntegration(
                'SURG SPT',
                'Surgical Support'
            )
        );
    }

    @IsTest
    static void resolveSalesCategoryFromIntegration_usesDescriptionWhenCodeBlank() {
        System.assertEquals(
            'Surgical Support',
            QuoteLineSalesCategoryService.resolveSalesCategoryFromIntegration(null, 'Surgical Support')
        );
    }

    private static QuoteLineItem buildQuoteLine(
        String salesCategory,
        String salesCategoryDescription,
        String territoryId,
        Decimal lineTotal
    ) {
        QuoteLineItem quoteLineItem = new QuoteLineItem();
        quoteLineItem.SalesCategory__c = salesCategory;
        quoteLineItem.TerritoryID__c = territoryId;
        quoteLineItem.Quantity = 1;
        quoteLineItem.UnitPrice = lineTotal;
        quoteLineItem.Total_Unit_Price__c = lineTotal;
        quoteLineItem.Description = 'Test Product';
        return quoteLineItem;
    }
}