/**
 * @author PWC Developer
 * @date 2026/10/30
 *
 * @group Lost Business Products
 *
 * @description
 * GC-3574 - Service for the Lost Business product selection screen. Loads products from the
 * originating opportunity, searches the active catalogue when that opportunity has none, and
 * inserts Opportunity Products on the new Lost Business opportunity only.
 */
public with sharing class LostBusinessProductService {

    /**
     * @description
     * GC-3574 - Constants used in the class.
     */
    public static final String SCENARIO = 'Lost Business Products';
    public static final String LOGGER_TAG = 'LostBusinessProduct';
    public static final Integer CONTRACT_MAX_LENGTH = 18;
    public static final Integer COMMENTS_MAX_LENGTH = 250;

    @TestVisible
    private static Boolean throwTestException = false;

    /**
     * @description
     * GC-3574 - Returns Opportunity Products for the originating opportunity. An empty list means
     * the screen should offer the product catalogue instead.
     *
     * @param originatingOpportunityId Originating opportunity Id from the flow.
     * @return Products on that opportunity, including rows that cannot be copied.
     *
     * @example
     * LostBusinessProductService.getOriginatingProducts(originatingOpportunityId);
     */
    public static List<LostBusinessProductController.OriginatingProductRow> getOriginatingProducts(
        String originatingOpportunityId
    ) {
        try {
            if (Test.isRunningTest() && throwTestException) {
                throw new QueryException('Forced test exception');
            }

            if (String.isBlank(originatingOpportunityId)) {
                return new List<LostBusinessProductController.OriginatingProductRow>();
            }

            Id opportunityId = parseId(
                originatingOpportunityId,
                'The originating Opportunity Id provided is not valid.'
            );

            List<LostBusinessProductController.OriginatingProductRow> productRowList =
                new List<LostBusinessProductController.OriginatingProductRow>();

            for (OpportunityLineItem lineItem : LostBusinessProductSelector.selectLinesByOpportunityId(opportunityId)) {
                productRowList.add(toOriginatingRow(lineItem));
            }

            return productRowList;
        } catch (LostBusinessProductException validationException) {
            throw validationException;
        } catch (Exception exceptionValue) {
            Logger.error('Error loading originating Lost Business products', exceptionValue).addTag(LOGGER_TAG);
            throw new LostBusinessProductException('Unable to load products from the originating opportunity.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description
     * GC-3574 - Searches the active product catalogue by product name or product code.
     *
     * @param searchKey User-entered product name or product code fragment.
     * @param lostBusinessOpportunityId Lost Business opportunity, used to show Unit Price when the price book has one.
     * @return Matching active products.
     *
     * @example
     * LostBusinessProductService.searchProducts(searchKey, lostBusinessOpportunityId);
     */
    public static List<LostBusinessProductController.ProductWrapper> searchProducts(
        String searchKey,
        String lostBusinessOpportunityId
    ) {
        try {
            if (Test.isRunningTest() && throwTestException) {
                throw new QueryException('Forced test exception');
            }

            List<Product2> productList = Product2Selector.selectActiveBySearchKey(searchKey);
            Map<Id, Decimal> unitPriceByProductId = unitPriceByProductId(productList, lostBusinessOpportunityId);
            List<LostBusinessProductController.ProductWrapper> productWrapperList =
                new List<LostBusinessProductController.ProductWrapper>();

            for (Product2 product : productList) {
                LostBusinessProductController.ProductWrapper productWrapper =
                    new LostBusinessProductController.ProductWrapper();
                productWrapper.productId = product.Id;
                productWrapper.productName = product.Name;
                productWrapper.productCode = product.ProductCode;
                productWrapper.unitPrice = unitPriceByProductId.get(product.Id);
                productWrapperList.add(productWrapper);
            }

            return productWrapperList;
        } catch (Exception exceptionValue) {
            Logger.error('Error searching products for Lost Business', exceptionValue).addTag(LOGGER_TAG);
            throw new LostBusinessProductException('Unable to search products.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description
     * GC-3574 - Unit price from the Lost Business price book, keyed by product. Missing prices stay blank.
     *
     * @param productList Products returned by the catalogue search.
     * @param lostBusinessOpportunityId Lost Business opportunity.
     * @return Unit price by Product2 Id.
     *
     * @example
     * unitPriceByProductId(productList, lostBusinessOpportunityId);
     */
    private static Map<Id, Decimal> unitPriceByProductId(
        List<Product2> productList,
        String lostBusinessOpportunityId
    ) {
        Map<Id, Decimal> unitPriceByProductId = new Map<Id, Decimal>();

        if (productList == null || productList.isEmpty() || String.isBlank(lostBusinessOpportunityId)) {
            return unitPriceByProductId;
        }

        Id lostOpportunityId;

        try {
            lostOpportunityId = Id.valueOf(lostBusinessOpportunityId);
        } catch (Exception invalidIdException) {
            return unitPriceByProductId;
        }

        Opportunity lostOpportunity = LostBusinessProductSelector.selectOpportunityById(lostOpportunityId);

        if (lostOpportunity == null) {
            return unitPriceByProductId;
        }

        Id pricebookId = lostOpportunity.Pricebook2Id == null
            ? LostBusinessProductSelector.selectStandardPricebookId()
            : lostOpportunity.Pricebook2Id;
        Set<Id> productIds = new Map<Id, Product2>(productList).keySet();

        for (PricebookEntry pricebookEntry : LostBusinessProductSelector.selectActiveEntries(
            pricebookId,
            productIds,
            lostOpportunity.CurrencyIsoCode
        )) {
            unitPriceByProductId.put(pricebookEntry.Product2Id, pricebookEntry.UnitPrice);
        }

        return unitPriceByProductId;
    }

    /**
     * @description
     * GC-3574 - Inserts one Opportunity Product on the Lost Business opportunity for each selected
     * product. Copy rows keep the originating unit price and SKU. An empty selection is allowed.
     * A repeated submit does not create a second line for a price book entry already on the opportunity.
     * The originating opportunity's products are not updated.
     *
     * @param lostBusinessOpportunityId Lost Business opportunity created earlier in the flow.
     * @param originatingOpportunityId Originating opportunity. Required when copying its products.
     * @param productInputsJson Selected products, JSON serialised by the LWC.
     * @return Number of Opportunity Products created by this call.
     *
     * @example
     * LostBusinessProductService.createProducts(lostBusinessOpportunityId, originatingOpportunityId, productInputsJson);
     */
    public static Integer createProducts(
        String lostBusinessOpportunityId,
        String originatingOpportunityId,
        String productInputsJson
    ) {
        Savepoint savePointValue = Database.setSavepoint();

        try {
            if (Test.isRunningTest() && throwTestException) {
                throw new CalloutException('Forced test exception');
            }

            Id lostOpportunityId = parseId(
                lostBusinessOpportunityId,
                'A Lost Business Opportunity is required before products can be added.',
                'The Lost Business Opportunity Id provided is not valid.'
            );
            Id originatingOpportunityRecordId = String.isBlank(originatingOpportunityId)
                ? null
                : parseId(originatingOpportunityId, 'The originating Opportunity Id provided is not valid.');

            List<LostBusinessProductController.ProductInput> productInputs = parseProductInputs(productInputsJson);

            if (productInputs.isEmpty()) {
                return 0;
            }

            Opportunity lostOpportunity = LostBusinessProductSelector.selectOpportunityById(lostOpportunityId);

            if (lostOpportunity == null) {
                throw new LostBusinessProductException('The Lost Business Opportunity could not be found.');
            }

            Id pricebookId = resolvePricebookId(lostOpportunity, originatingOpportunityRecordId);
            ensurePricebook(lostOpportunity, pricebookId);

            String currencyCode = lostOpportunity.CurrencyIsoCode;
            Set<Id> existingPricebookEntryIds = LostBusinessProductSelector.selectPricebookEntryIds(lostOpportunityId);
            List<OpportunityLineItem> lineItemList = new List<OpportunityLineItem>();
            Set<Id> pricebookEntriesInThisSave = new Set<Id>();

            lineItemList.addAll(buildCopiedLines(
                productInputs,
                lostOpportunity.Id,
                originatingOpportunityRecordId,
                pricebookId,
                currencyCode,
                existingPricebookEntryIds,
                pricebookEntriesInThisSave
            ));
            lineItemList.addAll(buildCatalogLines(
                productInputs,
                lostOpportunity.Id,
                pricebookId,
                currencyCode,
                existingPricebookEntryIds,
                pricebookEntriesInThisSave
            ));

            if (lineItemList.isEmpty()) {
                return 0;
            }

            insert lineItemList;
            return lineItemList.size();
        } catch (LostBusinessProductException validationException) {
            Database.rollback(savePointValue);
            Logger.error('Lost Business product payload rejected: ' + productInputsJson).addTag(LOGGER_TAG);
            throw validationException;
        } catch (Exception exceptionValue) {
            Database.rollback(savePointValue);
            Logger.error('Error creating Lost Business Opportunity Products', exceptionValue).addTag(LOGGER_TAG);
            throw new LostBusinessProductException(dmlOrFallbackMessage(exceptionValue));
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description
     * GC-3574 - Builds the display row for one originating Opportunity Product.
     *
     * @param lineItem Originating Opportunity Product.
     * @return Row returned to the selection screen.
     *
     * @example
     * toOriginatingRow(lineItem);
     */
    private static LostBusinessProductController.OriginatingProductRow toOriginatingRow(
        OpportunityLineItem lineItem
    ) {
        LostBusinessProductController.OriginatingProductRow productRow =
            new LostBusinessProductController.OriginatingProductRow();
        productRow.sourceLineItemId = lineItem.Id;
        productRow.productId = lineItem.PricebookEntry.Product2Id;
        productRow.productName = lineItem.PricebookEntry.Product2.Name;
        productRow.productSku = productSku(lineItem);
        productRow.quantity = lineItem.Quantity;
        productRow.consumptionFrequency = lineItem.ConsumptionFrequency__c;
        productRow.unitPrice = lineItem.UnitPrice;
        productRow.pricebookEntryId = lineItem.PricebookEntryId;
        productRow.copyable = lineItem.PricebookEntry.IsActive == true;
        productRow.unavailableReason = productRow.copyable
            ? null
            : 'This product cannot be copied because its price book entry is inactive.';
        return productRow;
    }

    /**
     * @description
     * GC-3574 - Builds Lost Business lines from the selected originating Opportunity Products.
     *
     * @param productInputs Full payload from the LWC.
     * @param lostOpportunityId Lost Business opportunity.
     * @param originatingOpportunityId Originating opportunity.
     * @param pricebookId Price book on the Lost Business opportunity.
     * @param currencyCode Lost Business opportunity currency.
     * @param existingPricebookEntryIds Price book entries already on the Lost Business opportunity.
     * @param pricebookEntriesInThisSave Price book entries already added by this save.
     * @return New Opportunity Products to insert.
     *
     * @example
     * buildCopiedLines(productInputs, lostOpportunityId, originatingOpportunityId, pricebookId, currencyCode, existingPricebookEntryIds, pricebookEntriesInThisSave);
     */
    private static List<OpportunityLineItem> buildCopiedLines(
        List<LostBusinessProductController.ProductInput> productInputs,
        Id lostOpportunityId,
        Id originatingOpportunityId,
        Id pricebookId,
        String currencyCode,
        Set<Id> existingPricebookEntryIds,
        Set<Id> pricebookEntriesInThisSave
    ) {
        Map<Id, LostBusinessProductController.ProductInput> inputByLineId =
            new Map<Id, LostBusinessProductController.ProductInput>();
        List<String> errorMessageList = new List<String>();

        for (LostBusinessProductController.ProductInput productInput : productInputs) {
            if (productInput == null || String.isBlank(productInput.sourceLineItemId)) {
                continue;
            }

            if (productInput.quantity == null || productInput.quantity <= 0) {
                errorMessageList.add('Quantity must be greater than zero for every selected product.');
                continue;
            }

            try {
                inputByLineId.put(Id.valueOf(productInput.sourceLineItemId), productInput);
            } catch (System.StringException invalidIdException) {
                errorMessageList.add('A selected product reference is not a valid Opportunity Product.');
            }
        }

        throwIfErrors(errorMessageList);

        if (inputByLineId.isEmpty()) {
            return new List<OpportunityLineItem>();
        }

        if (originatingOpportunityId == null) {
            throw new LostBusinessProductException(
                'An originating Opportunity is required to copy products.'
            );
        }

        Map<Id, OpportunityLineItem> sourceLineById = new Map<Id, OpportunityLineItem>(
            LostBusinessProductSelector.selectLinesByIdsAndOpportunity(
                inputByLineId.keySet(),
                originatingOpportunityId
            )
        );

        Set<Id> productIdsNeedingEntry = new Set<Id>();

        for (Id lineItemId : inputByLineId.keySet()) {
            OpportunityLineItem sourceLine = sourceLineById.get(lineItemId);

            if (sourceLine == null) {
                errorMessageList.add('A selected product does not belong to the originating opportunity.');
                continue;
            }

            if (!canReusePricebookEntry(sourceLine, pricebookId, currencyCode)) {
                productIdsNeedingEntry.add(sourceLine.PricebookEntry.Product2Id);
            }
        }

        throwIfErrors(errorMessageList);

        Map<Id, PricebookEntry> entryByProductId = entryByProductId(
            pricebookId,
            productIdsNeedingEntry,
            currencyCode
        );
        List<OpportunityLineItem> lineItemList = new List<OpportunityLineItem>();

        for (Id lineItemId : inputByLineId.keySet()) {
            OpportunityLineItem sourceLine = sourceLineById.get(lineItemId);
            LostBusinessProductController.ProductInput productInput = inputByLineId.get(lineItemId);
            PricebookEntry pricebookEntry = resolveCopyEntry(
                sourceLine,
                pricebookId,
                currencyCode,
                entryByProductId
            );

            if (pricebookEntry == null) {
                errorMessageList.add(
                    sourceLine.PricebookEntry.Product2.Name +
                    ' cannot be copied because its price book entry is inactive.'
                );
                continue;
            }

            if (existingPricebookEntryIds.contains(pricebookEntry.Id)) {
                continue;
            }

            if (pricebookEntriesInThisSave.contains(pricebookEntry.Id)) {
                errorMessageList.add(
                    'Two selected products use the same price book entry and cannot both be added.'
                );
                continue;
            }

            pricebookEntriesInThisSave.add(pricebookEntry.Id);
            lineItemList.add(new OpportunityLineItem(
                OpportunityId = lostOpportunityId,
                PricebookEntryId = pricebookEntry.Id,
                Quantity = productInput.quantity,
                UnitPrice = sourceLine.UnitPrice == null ? pricebookEntry.UnitPrice : sourceLine.UnitPrice,
                ConsumptionFrequency__c = blankToNull(productInput.consumptionFrequency),
                Product_Number_SKU__c = productSku(sourceLine)
            ));
        }

        throwIfErrors(errorMessageList);
        return lineItemList;
    }

    /**
     * @description
     * GC-3574 - Builds Lost Business lines for products the rep searched and selected.
     *
     * @param productInputs Full payload from the LWC.
     * @param lostOpportunityId Lost Business opportunity.
     * @param pricebookId Price book on the Lost Business opportunity.
     * @param currencyCode Lost Business opportunity currency.
     * @param existingPricebookEntryIds Price book entries already on the Lost Business opportunity.
     * @param pricebookEntriesInThisSave Price book entries already added by this save.
     * @return New Opportunity Products to insert.
     *
     * @example
     * buildCatalogLines(productInputs, lostOpportunityId, pricebookId, currencyCode, existingPricebookEntryIds, pricebookEntriesInThisSave);
     */
    private static List<OpportunityLineItem> buildCatalogLines(
        List<LostBusinessProductController.ProductInput> productInputs,
        Id lostOpportunityId,
        Id pricebookId,
        String currencyCode,
        Set<Id> existingPricebookEntryIds,
        Set<Id> pricebookEntriesInThisSave
    ) {
        Map<Id, LostBusinessProductController.ProductInput> inputByProductId =
            new Map<Id, LostBusinessProductController.ProductInput>();
        List<String> errorMessageList = new List<String>();

        for (LostBusinessProductController.ProductInput productInput : productInputs) {
            if (productInput == null || String.isNotBlank(productInput.sourceLineItemId)) {
                continue;
            }

            if (String.isBlank(productInput.productId)) {
                errorMessageList.add('A selected product is missing its product reference.');
                continue;
            }

            if (productInput.quantity == null || productInput.quantity <= 0) {
                errorMessageList.add('Quantity must be greater than zero for every selected product.');
                continue;
            }

            if (productInput.unitPrice != null && productInput.unitPrice < 0) {
                errorMessageList.add('Unit Price cannot be negative.');
                continue;
            }

            if (blankToNull(productInput.contractValue) != null
                && productInput.contractValue.trim().length() > CONTRACT_MAX_LENGTH) {
                errorMessageList.add('Contract cannot be longer than 18 characters.');
                continue;
            }

            if (blankToNull(productInput.comments) != null
                && productInput.comments.trim().length() > COMMENTS_MAX_LENGTH) {
                errorMessageList.add('Comments cannot be longer than 250 characters.');
                continue;
            }

            try {
                inputByProductId.put(Id.valueOf(productInput.productId), productInput);
            } catch (System.StringException invalidIdException) {
                errorMessageList.add('A selected product reference is not a valid product.');
            }
        }

        throwIfErrors(errorMessageList);

        if (inputByProductId.isEmpty()) {
            return new List<OpportunityLineItem>();
        }

        Map<Id, Product2> activeProductById =
            LostBusinessProductSelector.selectActiveProducts(inputByProductId.keySet());
        Map<Id, PricebookEntry> entryByProductId = entryByProductId(
            pricebookId,
            inputByProductId.keySet(),
            currencyCode
        );
        List<OpportunityLineItem> lineItemList = new List<OpportunityLineItem>();

        for (Id productId : inputByProductId.keySet()) {
            Product2 product = activeProductById.get(productId);

            if (product == null) {
                errorMessageList.add('One or more selected products are no longer active.');
                continue;
            }

            PricebookEntry pricebookEntry = entryByProductId.get(productId);

            if (pricebookEntry == null) {
                errorMessageList.add(product.Name + ' is not available on the opportunity price book.');
                continue;
            }

            if (existingPricebookEntryIds.contains(pricebookEntry.Id)
                || pricebookEntriesInThisSave.contains(pricebookEntry.Id)) {
                continue;
            }

            LostBusinessProductController.ProductInput productInput = inputByProductId.get(productId);
            pricebookEntriesInThisSave.add(pricebookEntry.Id);
            lineItemList.add(new OpportunityLineItem(
                OpportunityId = lostOpportunityId,
                PricebookEntryId = pricebookEntry.Id,
                Quantity = productInput.quantity,
                UnitPrice = productInput.unitPrice == null ? pricebookEntry.UnitPrice : productInput.unitPrice,
                ConsumptionFrequency__c = blankToNull(productInput.consumptionFrequency),
                Status__c = blankToNull(productInput.status),
                ConfidenceLevel__c = blankToNull(productInput.confidenceLevel),
                ExpectedShipDate_ConsumptionStart__c = productInput.expectedShipDate,
                Contract__c = blankToNull(productInput.contractValue),
                Comments__c = blankToNull(productInput.comments),
                Product_Number_SKU__c = product.ProductCode
            ));
        }

        throwIfErrors(errorMessageList);
        return lineItemList;
    }

    /**
     * @description
     * GC-3574 - Uses the Lost Business price book, then the originating price book, then the
     * standard price book.
     *
     * @param lostOpportunity Lost Business opportunity.
     * @param originatingOpportunityId Originating opportunity Id.
     * @return Price book Id to use for the new lines.
     *
     * @example
     * resolvePricebookId(lostOpportunity, originatingOpportunityId);
     */
    private static Id resolvePricebookId(Opportunity lostOpportunity, Id originatingOpportunityId) {
        if (lostOpportunity.Pricebook2Id != null) {
            return lostOpportunity.Pricebook2Id;
        }

        if (originatingOpportunityId != null) {
            Opportunity originatingOpportunity =
                LostBusinessProductSelector.selectOpportunityById(originatingOpportunityId);

            if (originatingOpportunity != null && originatingOpportunity.Pricebook2Id != null) {
                return originatingOpportunity.Pricebook2Id;
            }
        }

        return LostBusinessProductSelector.selectStandardPricebookId();
    }

    /**
     * @description
     * GC-3574 - Sets the price book on the Lost Business opportunity before products are inserted.
     *
     * @param lostOpportunity Lost Business opportunity.
     * @param pricebookId Price book the products will use.
     *
     * @example
     * ensurePricebook(lostOpportunity, pricebookId);
     */
    private static void ensurePricebook(Opportunity lostOpportunity, Id pricebookId) {
        if (pricebookId == null) {
            throw new LostBusinessProductException('A price book is required before products can be added.');
        }

        if (lostOpportunity.Pricebook2Id != null) {
            return;
        }

        update new Opportunity(
            Id = lostOpportunity.Id,
            Pricebook2Id = pricebookId
        );
        lostOpportunity.Pricebook2Id = pricebookId;
    }

    /**
     * @description
     * GC-3574 - A copied line can keep its price book entry when that entry is active and belongs
     * to the Lost Business price book and currency.
     *
     * @param sourceLine Originating Opportunity Product.
     * @param pricebookId Lost Business price book.
     * @param currencyCode Lost Business currency.
     * @return True when the originating price book entry can be reused.
     *
     * @example
     * canReusePricebookEntry(sourceLine, pricebookId, currencyCode);
     */
    private static Boolean canReusePricebookEntry(
        OpportunityLineItem sourceLine,
        Id pricebookId,
        String currencyCode
    ) {
        PricebookEntry pricebookEntry = sourceLine.PricebookEntry;
        return pricebookEntry != null
            && pricebookEntry.IsActive == true
            && pricebookEntry.Pricebook2Id == pricebookId
            && pricebookEntry.CurrencyIsoCode == currencyCode;
    }

    /**
     * @description
     * GC-3574 - Resolves the price book entry to copy. Reuses the originating entry when it is
     * still valid, otherwise uses the active entry for the same product.
     *
     * @param sourceLine Originating Opportunity Product.
     * @param pricebookId Lost Business price book.
     * @param currencyCode Lost Business currency.
     * @param entryByProductId Active entries keyed by product.
     * @return Price book entry to insert, or null when the product cannot be copied.
     *
     * @example
     * resolveCopyEntry(sourceLine, pricebookId, currencyCode, entryByProductId);
     */
    private static PricebookEntry resolveCopyEntry(
        OpportunityLineItem sourceLine,
        Id pricebookId,
        String currencyCode,
        Map<Id, PricebookEntry> entryByProductId
    ) {
        if (canReusePricebookEntry(sourceLine, pricebookId, currencyCode)) {
            return sourceLine.PricebookEntry;
        }

        return entryByProductId.get(sourceLine.PricebookEntry.Product2Id);
    }

    /**
     * @description
     * GC-3574 - Active price book entries keyed by product.
     *
     * @param pricebookId Lost Business price book.
     * @param productIds Products that need an entry.
     * @param currencyCode Lost Business currency.
     * @return Entries keyed by Product2 Id.
     *
     * @example
     * entryByProductId(pricebookId, productIds, currencyCode);
     */
    private static Map<Id, PricebookEntry> entryByProductId(
        Id pricebookId,
        Set<Id> productIds,
        String currencyCode
    ) {
        Map<Id, PricebookEntry> entryByProductId = new Map<Id, PricebookEntry>();

        for (PricebookEntry pricebookEntry : LostBusinessProductSelector.selectActiveEntries(
            pricebookId,
            productIds,
            currencyCode
        )) {
            entryByProductId.put(pricebookEntry.Product2Id, pricebookEntry);
        }

        return entryByProductId;
    }

    /**
     * @description
     * GC-3574 - SKU stored on the originating line, or the product code when that field is blank.
     *
     * @param lineItem Originating Opportunity Product.
     * @return SKU to display and copy.
     *
     * @example
     * productSku(lineItem);
     */
    private static String productSku(OpportunityLineItem lineItem) {
        if (String.isNotBlank(lineItem.Product_Number_SKU__c)) {
            return lineItem.Product_Number_SKU__c;
        }

        return lineItem.PricebookEntry.Product2.ProductCode;
    }

    /**
     * @description
     * GC-3574 - Parses the selection sent by the LWC. An empty payload is a valid finish with no products.
     *
     * @param productInputsJson Selected products, JSON serialised by the LWC.
     * @return Deserialised product selection.
     *
     * @example
     * parseProductInputs(productInputsJson);
     */
    private static List<LostBusinessProductController.ProductInput> parseProductInputs(String productInputsJson) {
        if (String.isBlank(productInputsJson)) {
            return new List<LostBusinessProductController.ProductInput>();
        }

        try {
            List<LostBusinessProductController.ProductInput> productInputs =
                (List<LostBusinessProductController.ProductInput>) JSON.deserialize(
                    productInputsJson,
                    List<LostBusinessProductController.ProductInput>.class
                );
            return productInputs == null
                ? new List<LostBusinessProductController.ProductInput>()
                : productInputs;
        } catch (Exception parseException) {
            throw new LostBusinessProductException('The selected products could not be read.');
        }
    }

    /**
     * @description
     * GC-3574 - Parses a required Id.
     *
     * @param recordId Id text from the flow.
     * @param blankMessage Message used when the Id is missing.
     * @param invalidMessage Message used when the Id is not valid.
     * @return Parsed Id.
     *
     * @example
     * parseId(recordId, blankMessage, invalidMessage);
     */
    private static Id parseId(String recordId, String blankMessage, String invalidMessage) {
        if (String.isBlank(recordId)) {
            throw new LostBusinessProductException(blankMessage);
        }

        return parseId(recordId, invalidMessage);
    }

    /**
     * @description
     * GC-3574 - Parses an Id that is already known to be present.
     *
     * @param recordId Id text from the flow.
     * @param invalidMessage Message used when the Id is not valid.
     * @return Parsed Id.
     *
     * @example
     * parseId(recordId, invalidMessage);
     */
    private static Id parseId(String recordId, String invalidMessage) {
        try {
            return Id.valueOf(recordId);
        } catch (Exception invalidIdException) {
            throw new LostBusinessProductException(invalidMessage);
        }
    }

    /**
     * @description
     * GC-3574 - Raises the collected field messages as one exception.
     *
     * @param errorMessageList Messages collected while validating the selection.
     *
     * @example
     * throwIfErrors(errorMessageList);
     */
    private static void throwIfErrors(List<String> errorMessageList) {
        if (!errorMessageList.isEmpty()) {
            throw new LostBusinessProductException(String.join(errorMessageList, '\n'));
        }
    }

    /**
     * @description
     * GC-3574 - Converts a blank optional string to null so picklist and text fields are not stored as empty.
     *
     * @param fieldValue Optional string from the LWC payload.
     * @return Null when blank, otherwise the trimmed value.
     *
     * @example
     * blankToNull(fieldValue);
     */
    private static String blankToNull(String fieldValue) {
        return String.isBlank(fieldValue) ? null : fieldValue.trim();
    }

    /**
     * @description
     * GC-3574 - Uses the first DML message when the platform rejected a row, otherwise a generic message.
     *
     * @param exceptionValue Exception caught while creating products.
     * @return Message to show the rep.
     *
     * @example
     * dmlOrFallbackMessage(exceptionValue);
     */
    private static String dmlOrFallbackMessage(Exception exceptionValue) {
        if (exceptionValue instanceof DmlException) {
            DmlException dmlException = (DmlException) exceptionValue;

            if (dmlException.getNumDml() > 0) {
                return dmlException.getDmlMessage(0);
            }
        }

        return 'Unable to add products to the Lost Business Opportunity.';
    }
}