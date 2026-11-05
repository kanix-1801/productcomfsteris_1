/**
 * @author PWC Developer
 * @date 2026/07/27
 *
 * @group Generate Quote
 *
 * @description
 * GC-2642 - Groups quote lines by Sales Category for the Generate Quote LWC.
 * Sales Category values are supplied by Sales Connection on generate/refresh;
 * they are not resolved from OrderLineContact__c / TAS by Territory ID.
 */
public with sharing class QuoteLineSalesCategoryService {
    public static final String UNCATEGORIZED_SALES_CATEGORY = 'Uncategorized';

    /**
     * @description Resolves Sales Category from a Sales Connection quote line payload.
     * @param tasSalesCategory Primary sales category code from integration.
     * @param salesCategoryDescription Optional sales category description from integration.
     * @return Resolved sales category value for QuoteLineItem.SalesCategory__c.
     */
    public static String resolveSalesCategoryFromIntegration(
        String tasSalesCategory,
        String salesCategoryDescription
    ) {
        if (String.isNotBlank(tasSalesCategory)) {
            return tasSalesCategory.trim();
        }

        if (String.isNotBlank(salesCategoryDescription)) {
            return salesCategoryDescription.trim();
        }

        return null;
    }

    /**
     * @description Builds accordion subgroup rows grouped by TAS sales category.
     * @param quoteLineItems Quote line items for one quote.
     * @return Grouped sales category summary rows.
     */
    public static List<GenerateQuoteController.ProductSubgroupSummaryWrapper> buildGroupedSummary(
        List<QuoteLineItem> quoteLineItems
    ) {
        Map<String, GenerateQuoteController.ProductSubgroupSummaryWrapper> groupsByCategory =
            new Map<String, GenerateQuoteController.ProductSubgroupSummaryWrapper>();

        if (quoteLineItems == null || quoteLineItems.isEmpty()) {
            return new List<GenerateQuoteController.ProductSubgroupSummaryWrapper>();
        }

        for (QuoteLineItem quoteLineItem : quoteLineItems) {
            String salesCategory = resolveSalesCategoryLabel(quoteLineItem);
            String famCode = PsamQuoteLineGroupingService.resolveFamCode(quoteLineItem);
            Decimal quantity = normalizeQuantity(quoteLineItem.Quantity);
            Decimal unitPrice = quoteLineItem.UnitPrice == null ? 0 : quoteLineItem.UnitPrice;
            Decimal lineTotal = calculateLineTotal(quoteLineItem, quantity, unitPrice);

            if (!groupsByCategory.containsKey(salesCategory)) {
                GenerateQuoteController.ProductSubgroupSummaryWrapper groupWrapper =
                    new GenerateQuoteController.ProductSubgroupSummaryWrapper();
                groupWrapper.productSubgroupDetailName = salesCategory;
                groupWrapper.totalUnitPrice = 0;
                groupWrapper.quoteLines = new List<GenerateQuoteController.QuoteLineDetailWrapper>();
                groupsByCategory.put(salesCategory, groupWrapper);
            }

            GenerateQuoteController.ProductSubgroupSummaryWrapper groupEntry = groupsByCategory.get(
                salesCategory
            );
            groupEntry.totalUnitPrice += lineTotal;
            groupEntry.quoteLines.add(
                buildLineDetailWrapper(quoteLineItem, famCode, salesCategory, quantity, unitPrice, lineTotal)
            );
        }

        return groupsByCategory.values();
    }

    private static String resolveSalesCategoryLabel(QuoteLineItem quoteLineItem) {
        if (quoteLineItem == null) {
            return UNCATEGORIZED_SALES_CATEGORY;
        }

        if (String.isNotBlank(quoteLineItem.SalesCategory__c)) {
            return quoteLineItem.SalesCategory__c.trim();
        }

        return UNCATEGORIZED_SALES_CATEGORY;
    }

    private static GenerateQuoteController.QuoteLineDetailWrapper buildLineDetailWrapper(
        QuoteLineItem quoteLineItem,
        String famCode,
        String salesCategory,
        Decimal quantity,
        Decimal unitPrice,
        Decimal lineTotal
    ) {
        GenerateQuoteController.QuoteLineDetailWrapper lineWrapper =
            new GenerateQuoteController.QuoteLineDetailWrapper();
        lineWrapper.id = quoteLineItem.Id;
        lineWrapper.quoteLineId = String.isNotBlank(quoteLineItem.SalesConnectionQuoteLineID__c)
            ? quoteLineItem.SalesConnectionQuoteLineID__c
            : String.valueOf(quoteLineItem.Id);
        lineWrapper.productFAMCode = famCode;
        lineWrapper.productCode = resolveProductCode(quoteLineItem);
        lineWrapper.productName = resolveProductName(quoteLineItem);
        lineWrapper.uom = quoteLineItem.UOM__c;
        lineWrapper.productSubgroupDetailName = salesCategory;
        lineWrapper.tasSalesCategory = quoteLineItem.SalesCategory__c;
        lineWrapper.salesCategoryDescription = quoteLineItem.SalesCategory__c;
        lineWrapper.territoryId = quoteLineItem.TerritoryID__c;
        lineWrapper.quantity = quantity;
        lineWrapper.unitPrice = unitPrice;
        lineWrapper.lineTotal = lineTotal;
        return lineWrapper;
    }

    private static String resolveProductCode(QuoteLineItem quoteLineItem) {
        if (
            quoteLineItem == null
            || quoteLineItem.PricebookEntry == null
            || quoteLineItem.PricebookEntry.Product2 == null
        ) {
            return null;
        }

        return quoteLineItem.PricebookEntry.Product2.ProductCode;
    }

    private static String resolveProductName(QuoteLineItem quoteLineItem) {
        if (String.isNotBlank(quoteLineItem.Description)) {
            return quoteLineItem.Description;
        }

        if (
            quoteLineItem.PricebookEntry != null
            && quoteLineItem.PricebookEntry.Product2 != null
            && isUsableCatalogProductName(quoteLineItem.PricebookEntry.Product2.Name)
        ) {
            return quoteLineItem.PricebookEntry.Product2.Name;
        }

        return null;
    }

    private static Boolean isUsableCatalogProductName(String productName) {
        if (String.isBlank(productName)) {
            return false;
        }

        return productName.trim().length() > 1;
    }

    private static Decimal calculateLineTotal(
        QuoteLineItem quoteLineItem,
        Decimal quantity,
        Decimal unitPrice
    ) {
        return QuoteService.calculateQuoteLineTotal(quoteLineItem);
    }

    private static Decimal normalizeQuantity(Decimal quantity) {
        if (quantity == null || quantity <= 0) {
            return 1;
        }

        return quantity;
    }
}