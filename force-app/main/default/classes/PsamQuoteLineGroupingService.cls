/**
 * @author PWC Developer
 * @date 2026/07/07
 *
 * @group Generate Quote
 *
 * @description
 * Groups Quote Line Items by PSAM ProductSubgroupDetailName__c using Product2.PSAM__c lookup,
 * with Product FAM Code as a fallback when the Product PSAM link is unavailable.
 */
public with sharing class PsamQuoteLineGroupingService {
    public static final String UNCATEGORIZED_SUBGROUP_NAME = 'Uncategorized';

    /**
     * @description Preloaded PSAM records for quote line grouping.
     */
    public class PsamIndex {
        public Map<Id, PSAM__c> byId { get; private set; }
        public Map<Id, PSAM__c> byProduct2Id { get; private set; }
        public Map<String, PSAM__c> byFamCode { get; private set; }
        public Map<Id, PSAM__c> byPricebookEntryId { get; private set; }

        public PsamIndex() {
            byId = new Map<Id, PSAM__c>();
            byProduct2Id = new Map<Id, PSAM__c>();
            byFamCode = new Map<String, PSAM__c>();
            byPricebookEntryId = new Map<Id, PSAM__c>();
        }
    }

    /**
     * @description Builds accordion subgroup rows grouped by PSAM Product Subgroup Detail Name.
     * @param quoteLineItems Quote line items for one quote.
     * @return Grouped product subgroup summary rows.
     */
    public static List<GenerateQuoteController.ProductSubgroupSummaryWrapper> buildGroupedSummary(
        List<QuoteLineItem> quoteLineItems
    ) {
        return buildGroupedSummary(quoteLineItems, loadPsamForLines(quoteLineItems));
    }

    /**
     * @description Builds subgroup rows using a preloaded PSAM index (avoids per-quote SOQL).
     * @param quoteLineItems Quote line items for one quote.
     * @param psamByFamCode Deprecated FAM-code index; retained for backward compatibility in tests.
     * @return Grouped product subgroup summary rows.
     */
    public static List<GenerateQuoteController.ProductSubgroupSummaryWrapper> buildGroupedSummary(
        List<QuoteLineItem> quoteLineItems,
        Map<String, PSAM__c> psamByFamCode
    ) {
        PsamIndex psamIndex = new PsamIndex();
        psamIndex.byFamCode = psamByFamCode == null ? new Map<String, PSAM__c>() : psamByFamCode;
        return buildGroupedSummary(quoteLineItems, psamIndex);
    }

    /**
     * @description Builds subgroup rows using a preloaded PSAM index (avoids per-quote SOQL).
     * @param quoteLineItems Quote line items for one quote.
     * @param psamIndex Preloaded PSAM records indexed by Id, FAM code, and Pricebook Entry Id.
     * @return Grouped product subgroup summary rows.
     */
    public static List<GenerateQuoteController.ProductSubgroupSummaryWrapper> buildGroupedSummary(
        List<QuoteLineItem> quoteLineItems,
        PsamIndex psamIndex
    ) {
        Map<String, GenerateQuoteController.ProductSubgroupSummaryWrapper> subgroupsByName =
            new Map<String, GenerateQuoteController.ProductSubgroupSummaryWrapper>();

        if (quoteLineItems == null || quoteLineItems.isEmpty()) {
            return new List<GenerateQuoteController.ProductSubgroupSummaryWrapper>();
        }

        PsamIndex resolvedPsamIndex = psamIndex == null ? loadPsamForLines(quoteLineItems) : psamIndex;

        for (QuoteLineItem quoteLineItem : quoteLineItems) {
            String famCode = resolveFamCode(quoteLineItem, resolvedPsamIndex);
            String subgroupName = resolveSubgroupDetailName(quoteLineItem, resolvedPsamIndex);
            Decimal quantity = normalizeQuantity(quoteLineItem.Quantity);
            Decimal unitPrice = quoteLineItem.UnitPrice == null ? 0 : quoteLineItem.UnitPrice;
            Decimal lineTotal = calculateLineTotal(quoteLineItem, quantity, unitPrice);

            if (!subgroupsByName.containsKey(subgroupName)) {
                GenerateQuoteController.ProductSubgroupSummaryWrapper subgroupWrapper =
                    new GenerateQuoteController.ProductSubgroupSummaryWrapper();
                subgroupWrapper.productSubgroupDetailName = subgroupName;
                subgroupWrapper.totalUnitPrice = 0;
                subgroupWrapper.quoteLines = new List<GenerateQuoteController.QuoteLineDetailWrapper>();
                subgroupsByName.put(subgroupName, subgroupWrapper);
            }

            GenerateQuoteController.ProductSubgroupSummaryWrapper subgroupEntry = subgroupsByName.get(subgroupName);
            subgroupEntry.totalUnitPrice += lineTotal;
            subgroupEntry.quoteLines.add(
                buildLineDetailWrapper(quoteLineItem, famCode, subgroupName, quantity, unitPrice, lineTotal)
            );
        }

        return subgroupsByName.values();
    }

    /**
     * @description Applies PSAM subgroup detail names to quote lines before insert.
     * @param quoteLineItems Quote line items being created.
     */
    public static void applyPsamSubgroupDetailNames(List<QuoteLineItem> quoteLineItems) {
        if (quoteLineItems == null || quoteLineItems.isEmpty()) {
            return;
        }

        PsamIndex psamIndex = loadPsamForLines(quoteLineItems);

        for (QuoteLineItem quoteLineItem : quoteLineItems) {
            quoteLineItem.Product_Subgroup_Detail_Name__c = resolveSubgroupDetailNameFromPsam(
                quoteLineItem,
                psamIndex
            );
        }
    }

    /**
     * @description Loads PSAM records for all quote lines across multiple quotes in one query batch.
     * @param quoteRecords Quote records with child line items.
     * @return PSAM records indexed by Id, FAM code, and Pricebook Entry Id.
     */
    public static PsamIndex loadPsamForQuotes(List<Quote> quoteRecords) {
        List<QuoteLineItem> allQuoteLineItems = new List<QuoteLineItem>();

        if (quoteRecords != null) {
            for (Quote quoteRecord : quoteRecords) {
                if (quoteRecord.QuoteLineItems != null && !quoteRecord.QuoteLineItems.isEmpty()) {
                    allQuoteLineItems.addAll(quoteRecord.QuoteLineItems);
                }
            }
        }

        return loadPsamForLines(allQuoteLineItems);
    }

    /**
     * @description Loads PSAM records needed to resolve subgroup names for quote lines.
     * @param quoteLineItems Quote line items.
     * @return PSAM records indexed by Id, FAM code, and Pricebook Entry Id.
     */
    public static PsamIndex loadPsamForLines(List<QuoteLineItem> quoteLineItems) {
        PsamIndex psamIndex = new PsamIndex();

        if (quoteLineItems == null || quoteLineItems.isEmpty()) {
            return psamIndex;
        }

        Set<Id> psamIds = new Set<Id>();
        Set<Id> product2IdsNeedingPsam = new Set<Id>();
        Set<Id> pricebookEntryIdsNeedingPsam = new Set<Id>();
        Set<String> famCodes = new Set<String>();

        for (QuoteLineItem quoteLineItem : quoteLineItems) {
            if (quoteLineItem == null) {
                continue;
            }

            PSAM__c inlinePsamRecord = resolveInlinePsamFromProduct(quoteLineItem);
            if (inlinePsamRecord != null) {
                if (inlinePsamRecord.Id != null) {
                    psamIndex.byId.put(inlinePsamRecord.Id, inlinePsamRecord);
                }
                continue;
            }

            Id psamId = resolvePsamIdFromProduct(quoteLineItem);
            if (psamId != null) {
                psamIds.add(psamId);
                continue;
            }

            Id product2Id = resolveProduct2Id(quoteLineItem);
            if (product2Id != null) {
                product2IdsNeedingPsam.add(product2Id);
            }

            if (quoteLineItem.PricebookEntryId != null && quoteLineItem.PricebookEntry == null) {
                pricebookEntryIdsNeedingPsam.add(quoteLineItem.PricebookEntryId);
            }

            String famCode = null;
            if (String.isNotBlank(quoteLineItem.Product_FAM_Code__c)) {
                famCode = normalizeFamCode(quoteLineItem.Product_FAM_Code__c);
            } else {
                famCode = resolveFamCode(quoteLineItem, psamIndex);
            }

            if (String.isNotBlank(famCode)) {
                famCodes.add(famCode);
            }
        }

        for (PSAM__c psamRecord : PsamSelector.selectByIds(psamIds)) {
            psamIndex.byId.put(psamRecord.Id, psamRecord);
        }

        psamIndex.byProduct2Id.putAll(
            ProductPsamLookupService.selectPsamByProduct2Ids(product2IdsNeedingPsam)
        );

        psamIndex.byPricebookEntryId.putAll(
            ProductPsamLookupService.selectPsamByPricebookEntryIds(pricebookEntryIdsNeedingPsam)
        );

        for (PSAM__c psamRecord : psamIndex.byProduct2Id.values()) {
            if (psamRecord != null && psamRecord.Id != null) {
                psamIndex.byId.put(psamRecord.Id, psamRecord);
            }
        }

        for (PSAM__c psamRecord : psamIndex.byPricebookEntryId.values()) {
            if (psamRecord != null && psamRecord.Id != null) {
                psamIndex.byId.put(psamRecord.Id, psamRecord);
            }
        }

        psamIndex.byFamCode.putAll(indexPsamByFamCode(famCodes));

        return psamIndex;
    }

    /**
     * @description Loads PSAM records for all quote lines across multiple quotes in one query.
     * @param quoteRecords Quote records with child line items.
     * @return PSAM records indexed by normalized FAM code.
     * @deprecated Use loadPsamForQuotes instead.
     */
    public static Map<String, PSAM__c> loadPsamByFamCodeForQuotes(List<Quote> quoteRecords) {
        return loadPsamForQuotes(quoteRecords).byFamCode;
    }

    /**
     * @description Loads PSAM records needed to resolve subgroup names for quote lines.
     * @param quoteLineItems Quote line items.
     * @return PSAM records indexed by normalized FAM code.
     * @deprecated Use loadPsamForLines instead.
     */
    public static Map<String, PSAM__c> loadPsamByFamCodeForLines(List<QuoteLineItem> quoteLineItems) {
        return loadPsamForLines(quoteLineItems).byFamCode;
    }

    /**
     * @description Resolves the Product FAM Code for a quote line.
     * @param quoteLineItem Quote line item.
     * @return Product FAM code when available.
     */
    public static String resolveFamCode(QuoteLineItem quoteLineItem) {
        return resolveFamCode(quoteLineItem, null);
    }

    /**
     * @description Resolves the Product FAM Code for a quote line.
     * @param quoteLineItem Quote line item.
     * @param psamIndex Optional preloaded PSAM index used to resolve FAM from Product PSAM lookup.
     * @return Product FAM code when available.
     */
    public static String resolveFamCode(QuoteLineItem quoteLineItem, PsamIndex psamIndex) {
        if (quoteLineItem == null) {
            return null;
        }

        if (String.isNotBlank(quoteLineItem.Product_FAM_Code__c)) {
            return normalizeFamCode(quoteLineItem.Product_FAM_Code__c);
        }

        PSAM__c psamRecord = resolvePsamRecord(quoteLineItem, psamIndex);
        if (psamRecord != null && String.isNotBlank(psamRecord.ProductFAMCode__c)) {
            return normalizeFamCode(psamRecord.ProductFAMCode__c);
        }

        return null;
    }

    private static PSAM__c resolveInlinePsamFromProduct(QuoteLineItem quoteLineItem) {
        if (
            quoteLineItem != null
            && quoteLineItem.PricebookEntry != null
            && quoteLineItem.PricebookEntry.Product2 != null
        ) {
            PSAM__c psamRecord = ProductPsamLookupService.getPsamRelationship(
                quoteLineItem.PricebookEntry.Product2
            );
            if (hasPsamDetailFields(psamRecord)) {
                return psamRecord;
            }
        }

        return null;
    }

    private static Boolean hasPsamDetailFields(PSAM__c psamRecord) {
        return psamRecord != null
            && (
                psamRecord.Id != null
                || String.isNotBlank(psamRecord.ProductFAMCode__c)
                || String.isNotBlank(psamRecord.ProductSubgroupDetailName__c)
            );
    }

    private static Id resolvePsamIdFromProduct(QuoteLineItem quoteLineItem) {
        if (
            quoteLineItem != null
            && quoteLineItem.PricebookEntry != null
            && quoteLineItem.PricebookEntry.Product2 != null
        ) {
            return ProductPsamLookupService.getPsamId(quoteLineItem.PricebookEntry.Product2);
        }

        return null;
    }

    private static Id resolveProduct2Id(QuoteLineItem quoteLineItem) {
        if (quoteLineItem == null) {
            return null;
        }

        if (
            quoteLineItem.PricebookEntry != null
            && quoteLineItem.PricebookEntry.Product2Id != null
        ) {
            return quoteLineItem.PricebookEntry.Product2Id;
        }

        if (
            quoteLineItem.PricebookEntry != null
            && quoteLineItem.PricebookEntry.Product2 != null
            && quoteLineItem.PricebookEntry.Product2.Id != null
        ) {
            return quoteLineItem.PricebookEntry.Product2.Id;
        }

        return null;
    }

    private static PSAM__c resolvePsamRecord(QuoteLineItem quoteLineItem, PsamIndex psamIndex) {
        if (quoteLineItem == null) {
            return null;
        }

        PSAM__c inlinePsamRecord = resolveInlinePsamFromProduct(quoteLineItem);
        if (inlinePsamRecord != null) {
            return inlinePsamRecord;
        }

        Id psamId = resolvePsamIdFromProduct(quoteLineItem);
        if (psamId != null && psamIndex != null && psamIndex.byId.containsKey(psamId)) {
            return psamIndex.byId.get(psamId);
        }

        Id product2Id = resolveProduct2Id(quoteLineItem);
        if (
            product2Id != null
            && psamIndex != null
            && psamIndex.byProduct2Id.containsKey(product2Id)
        ) {
            return psamIndex.byProduct2Id.get(product2Id);
        }

        if (
            psamIndex != null
            && quoteLineItem.PricebookEntryId != null
            && psamIndex.byPricebookEntryId.containsKey(quoteLineItem.PricebookEntryId)
        ) {
            return psamIndex.byPricebookEntryId.get(quoteLineItem.PricebookEntryId);
        }

        String famCode = null;
        if (String.isNotBlank(quoteLineItem.Product_FAM_Code__c)) {
            famCode = normalizeFamCode(quoteLineItem.Product_FAM_Code__c);
        }

        if (String.isNotBlank(famCode) && psamIndex != null && psamIndex.byFamCode.containsKey(famCode)) {
            return psamIndex.byFamCode.get(famCode);
        }

        return null;
    }

    private static Map<String, PSAM__c> indexPsamByFamCode(Set<String> famCodes) {
        Map<String, PSAM__c> psamByFamCode = new Map<String, PSAM__c>();

        for (PSAM__c psamRecord : PsamSelector.selectByFamCodes(famCodes)) {
            if (String.isNotBlank(psamRecord.ProductFAMCode__c)) {
                psamByFamCode.put(normalizeFamCode(psamRecord.ProductFAMCode__c), psamRecord);
            }
        }

        return psamByFamCode;
    }

    private static String resolveSubgroupDetailName(
        QuoteLineItem quoteLineItem,
        PsamIndex psamIndex
    ) {
        if (quoteLineItem != null && String.isNotBlank(quoteLineItem.Product_Subgroup_Detail_Name__c)) {
            return quoteLineItem.Product_Subgroup_Detail_Name__c.trim();
        }

        PSAM__c psamRecord = resolvePsamRecord(quoteLineItem, psamIndex);
        if (psamRecord != null && String.isNotBlank(psamRecord.ProductSubgroupDetailName__c)) {
            return psamRecord.ProductSubgroupDetailName__c.trim();
        }

        return UNCATEGORIZED_SUBGROUP_NAME;
    }

    private static String resolveSubgroupDetailNameFromPsam(
        QuoteLineItem quoteLineItem,
        PsamIndex psamIndex
    ) {
        PSAM__c psamRecord = resolvePsamRecord(quoteLineItem, psamIndex);
        if (psamRecord != null && String.isNotBlank(psamRecord.ProductSubgroupDetailName__c)) {
            return psamRecord.ProductSubgroupDetailName__c.trim();
        }

        if (quoteLineItem != null && String.isNotBlank(quoteLineItem.Product_Subgroup_Detail_Name__c)) {
            return quoteLineItem.Product_Subgroup_Detail_Name__c.trim();
        }

        return UNCATEGORIZED_SUBGROUP_NAME;
    }

    private static GenerateQuoteController.QuoteLineDetailWrapper buildLineDetailWrapper(
        QuoteLineItem quoteLineItem,
        String famCode,
        String subgroupName,
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
        lineWrapper.productName = resolveProductName(quoteLineItem);
        lineWrapper.uom = quoteLineItem.UOM__c;
        lineWrapper.productSubgroupDetailName = subgroupName;
        lineWrapper.tasSalesCategory = quoteLineItem.SalesCategory__c;
        lineWrapper.salesCategoryDescription = quoteLineItem.SalesCategory__c;
        lineWrapper.territoryId = quoteLineItem.TerritoryID__c;
        lineWrapper.quantity = quantity;
        lineWrapper.unitPrice = unitPrice;
        lineWrapper.lineTotal = lineTotal;
        return lineWrapper;
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

    private static String normalizeFamCode(String famCode) {
        return famCode == null ? null : famCode.trim().toUpperCase();
    }
}