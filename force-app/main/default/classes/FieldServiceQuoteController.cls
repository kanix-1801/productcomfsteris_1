/**
 * @description GW-5892 / GW-6600: Backend for the fieldServiceQuoteEditor LWC (Quote "Edit Quote" action).
 *              Loads the quote header, lines and Rate List, and saves all changes in one transaction (Save All).
 * @group Field Service Quote
 * @see fieldServiceQuoteEditor
 * @see FieldServiceQuoteService
 */
public with sharing class FieldServiceQuoteController {
    @TestVisible
    private static final String PRICE_OVERRIDE_PERMISSION = 'FS_Quote_Price_Override';

    private static final Set<String> EDITOR_LINE_TYPES = new Set<String>{
        FieldServiceQuoteService.LINE_TYPE_PARTS,
        FieldServiceQuoteService.LINE_TYPE_LABOR,
        FieldServiceQuoteService.LINE_TYPE_TRAVEL,
        FieldServiceQuoteService.LINE_TYPE_EXPENSE
    };
    private static final String TRAVEL_TYPE_ACTUAL = 'Actual Travel';

    /** @description Option for comboboxes. */
    public class Option {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    /** @description Quote header strip. */
    public class HeaderView {
        @AuraEnabled public Id quoteId;
        @AuraEnabled public String quoteNumber;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public String accountName;
        @AuraEnabled public String assetName;
        @AuraEnabled public Id accountId;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public Id shipToId;
        @AuraEnabled public String shipToName;
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String rateListName;
        @AuraEnabled public String currencyIsoCode;
        @AuraEnabled public String pricingStatus;
        @AuraEnabled public String pricingMessage;
        @AuraEnabled public Decimal totalPrice;
    }

    /** @description Quote line as edited in the LWC. */
    public class LineView {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String lineType { get; set; }
        @AuraEnabled public Id product2Id { get; set; }
        @AuraEnabled public String productName { get; set; }
        @AuraEnabled public String productCode { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public String rate { get; set; }
        @AuraEnabled public String travelType { get; set; }
        @AuraEnabled public String expenseType { get; set; }
        @AuraEnabled public Decimal listPrice { get; set; }
        @AuraEnabled public Decimal unitPrice { get; set; }
        @AuraEnabled public Decimal discount { get; set; }
        @AuraEnabled public Decimal totalPrice { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Boolean isManualPrice { get; set; }
        @AuraEnabled public String pricingMessage { get; set; }
    }

    /** @description Product picked on a Parts line. */
    public class ProductView {
        @AuraEnabled public Id product2Id;
        @AuraEnabled public String productName;
        @AuraEnabled public String productCode;
        @AuraEnabled public Decimal listPrice;
    }

    /** @description Everything the editor needs. */
    public class QuoteView {
        @AuraEnabled public HeaderView header;
        @AuraEnabled public List<LineView> lines = new List<LineView>();
        @AuraEnabled public WoDebriefRateListController.RateListPrices rateList;
        @AuraEnabled public List<Option> statusOptions = new List<Option>();
        @AuraEnabled public List<Option> expenseTypeOptions = new List<Option>();
        @AuraEnabled public ProductView expenseProduct;
        @AuraEnabled public Boolean canOverridePrice = false;
    }

    /** @description Save All payload from the LWC. */
    public class SavePayload {
        public String status;
        public Id contactId;
        public Id shipToId;
        public Id ownerId;
        public List<LineView> lines = new List<LineView>();
        public List<Id> deletedLineIds = new List<Id>();
    }

    /**
     * @description Loads the quote for the editor.
     * @param quoteId Quote Id
     * @return Quote view
     */
    @AuraEnabled
    public static QuoteView getQuote(Id quoteId) {
        try {
            return buildView(quoteId);
        } catch (Exception ex) {
            throw toAuraException(ex);
        }
    }

    /**
     * @description Product details for a Parts line: code and list price from the quote's price book.
     * @param quoteId Quote Id
     * @param productId Product Id
     * @return Product view
     */
    @AuraEnabled
    public static ProductView getProductInfo(Id quoteId, Id productId) {
        try {
            Quote quoteRecord = selectQuote(quoteId);
            PricebookEntry entry = FieldServiceQuoteService.selectPricebookEntries(
                    quoteRecord.Pricebook2Id,
                    quoteRecord.CurrencyIsoCode,
                    new Set<Id>{ productId }
                )
                .get(productId);
            if (entry == null) {
                throw new FieldServiceQuoteService.FieldServiceQuoteException(
                    'This product has no active price in the quote price book (' + quoteRecord.CurrencyIsoCode + ').'
                );
            }
            return toProductView(entry);
        } catch (Exception ex) {
            throw toAuraException(ex);
        }
    }

    /**
     * @description Save All: header changes, new/changed lines and deleted lines in one transaction.
     *              Nothing is written until this call.
     * @param quoteId Quote Id
     * @param payloadJson Serialized SavePayload
     * @return Refreshed quote view
     */
    @AuraEnabled
    public static QuoteView saveQuote(Id quoteId, String payloadJson) {
        Savepoint savepoint = Database.setSavepoint();
        try {
            SavePayload payload = (SavePayload) JSON.deserialize(payloadJson, SavePayload.class);
            Quote quoteRecord = selectQuote(quoteId);
            Boolean canOverridePrice = FeatureManagement.checkPermission(PRICE_OVERRIDE_PERMISSION);

            Map<Id, QuoteLineItem> existingById = new Map<Id, QuoteLineItem>(selectLines(quoteId));
            List<QuoteLineItem> toInsert = new List<QuoteLineItem>();
            List<QuoteLineItem> toUpdate = new List<QuoteLineItem>();
            Map<String, PricebookEntry> entryByKey = resolveEntries(quoteRecord, payload.lines);

            for (LineView line : payload.lines) {
                validateLine(line);
                if (line.id == null) {
                    toInsert.add(buildNewLine(quoteRecord, line, entryByKey, canOverridePrice));
                } else if (existingById.containsKey(line.id)) {
                    toUpdate.add(buildLineUpdate(existingById.get(line.id), line, canOverridePrice));
                }
            }

            List<QuoteLineItem> toDelete = new List<QuoteLineItem>();
            for (Id lineId : payload.deletedLineIds) {
                if (existingById.containsKey(lineId)) {
                    toDelete.add(new QuoteLineItem(Id = lineId));
                }
            }

            Boolean linesChanged = !toInsert.isEmpty() || !toUpdate.isEmpty() || !toDelete.isEmpty();
            delete toDelete;
            update toUpdate;
            insert toInsert;

            update buildHeaderUpdate(quoteRecord, payload, linesChanged);
            FieldServiceQuoteService.ensureOpportunity(quoteId);
            return buildView(quoteId);
        } catch (Exception ex) {
            Database.rollback(savepoint);
            throw toAuraException(ex);
        }
    }

    private static Quote buildHeaderUpdate(Quote quoteRecord, SavePayload payload, Boolean linesChanged) {
        Quote header = new Quote(Id = quoteRecord.Id);
        if (String.isNotBlank(payload.status)) {
            header.Status = payload.status;
        }
        header.ContactId = payload.contactId;
        header.ShipToAccount__c = payload.shipToId;
        if (payload.ownerId != null) {
            header.OwnerId = payload.ownerId;
        }
        if (linesChanged && quoteRecord.PricingStatus__c == FieldServiceQuoteService.PRICING_PRICED) {
            header.PricingStatus__c = FieldServiceQuoteService.PRICING_REPRICING_REQUIRED;
        }
        return header;
    }

    private static void validateLine(LineView line) {
        if (line.lineType == null || !EDITOR_LINE_TYPES.contains(line.lineType)) {
            throw new FieldServiceQuoteService.FieldServiceQuoteException('Line Type is required.');
        }
        if (line.lineType == FieldServiceQuoteService.LINE_TYPE_PARTS && line.id == null && line.product2Id == null) {
            throw new FieldServiceQuoteService.FieldServiceQuoteException('Select a product for each Parts line.');
        }
        if (line.lineType == FieldServiceQuoteService.LINE_TYPE_LABOR && String.isBlank(line.rate)) {
            throw new FieldServiceQuoteService.FieldServiceQuoteException('Rate is required for Labor lines.');
        }
        if (line.lineType == FieldServiceQuoteService.LINE_TYPE_TRAVEL) {
            if (String.isBlank(line.travelType)) {
                throw new FieldServiceQuoteService.FieldServiceQuoteException('Travel Type is required for Travel lines.');
            }
            if (line.travelType == TRAVEL_TYPE_ACTUAL && String.isBlank(line.rate)) {
                throw new FieldServiceQuoteService.FieldServiceQuoteException('Rate is required for Actual Travel.');
            }
        }
        if (line.lineType == FieldServiceQuoteService.LINE_TYPE_EXPENSE && String.isBlank(line.expenseType)) {
            throw new FieldServiceQuoteService.FieldServiceQuoteException('Expense Type is required for Expense lines.');
        }
        if (line.quantity == null || line.quantity <= 0) {
            throw new FieldServiceQuoteService.FieldServiceQuoteException('Quantity must be greater than zero.');
        }
    }

    /** @description Zone travel is a flat amount: quantity 1 and no rate. */
    private static void normalizeTravel(LineView line) {
        if (line.lineType == FieldServiceQuoteService.LINE_TYPE_TRAVEL && line.travelType != TRAVEL_TYPE_ACTUAL) {
            line.quantity = 1;
            line.rate = null;
        }
    }

    private static QuoteLineItem buildNewLine(
        Quote quoteRecord,
        LineView line,
        Map<String, PricebookEntry> entryByKey,
        Boolean canOverridePrice
    ) {
        normalizeTravel(line);
        PricebookEntry entry = entryByKey.get(entryKey(line));
        if (entry == null) {
            throw new FieldServiceQuoteService.FieldServiceQuoteException(
                'No active price book entry found for the ' + line.lineType + ' product in the quote price book (' +
                quoteRecord.CurrencyIsoCode + ').'
            );
        }
        Boolean priceEditable = canOverridePrice || line.lineType == FieldServiceQuoteService.LINE_TYPE_EXPENSE;
        QuoteLineItem record = new QuoteLineItem(
            QuoteId = quoteRecord.Id,
            PricebookEntryId = entry.Id,
            Product2Id = entry.Product2Id,
            ProductCode__c = entry.Product2.ProductCode,
            LineType__c = line.lineType,
            WorkOrder__c = quoteRecord.WorkOrder__c,
            Asset__c = quoteRecord.Asset__c,
            UnitPrice = priceEditable && line.unitPrice != null ? line.unitPrice : entry.UnitPrice
        );
        applyEditableFields(record, line, canOverridePrice);
        return record;
    }

    private static QuoteLineItem buildLineUpdate(QuoteLineItem existing, LineView line, Boolean canOverridePrice) {
        normalizeTravel(line);
        QuoteLineItem record = new QuoteLineItem(Id = existing.Id);
        Boolean priceEditable = canOverridePrice || existing.LineType__c == FieldServiceQuoteService.LINE_TYPE_EXPENSE;
        if (priceEditable && line.unitPrice != null) {
            record.UnitPrice = line.unitPrice;
        }
        line.lineType = existing.LineType__c;
        applyEditableFields(record, line, canOverridePrice);
        return record;
    }

    private static void applyEditableFields(QuoteLineItem record, LineView line, Boolean canOverridePrice) {
        record.Quantity = line.quantity;
        record.Discount = line.discount;
        record.Description = line.description;
        record.Rate__c = line.lineType == FieldServiceQuoteService.LINE_TYPE_LABOR ||
            line.lineType == FieldServiceQuoteService.LINE_TYPE_TRAVEL
            ? line.rate
            : null;
        record.TravelType__c = line.lineType == FieldServiceQuoteService.LINE_TYPE_TRAVEL ? line.travelType : null;
        record.ExpenseType__c = line.lineType == FieldServiceQuoteService.LINE_TYPE_EXPENSE ? line.expenseType : null;
        if (canOverridePrice && line.isManualPrice != null) {
            record.IsManualPrice__c = line.isManualPrice;
        }
    }

    /**
     * @description Resolves price book entries for new lines: the chosen product for Parts, the configured
     *              product (Custom Labels) for Labor / Travel / Expense.
     */
    private static Map<String, PricebookEntry> resolveEntries(Quote quoteRecord, List<LineView> lines) {
        Set<Id> productIds = new Set<Id>();
        Set<String> productCodes = new Set<String>();
        for (LineView line : lines) {
            if (line.id != null) {
                continue;
            }
            if (line.lineType == FieldServiceQuoteService.LINE_TYPE_PARTS) {
                if (line.product2Id != null) {
                    productIds.add(line.product2Id);
                }
            } else if (configuredProductCode(line.lineType) != null) {
                productCodes.add(configuredProductCode(line.lineType));
            }
        }
        if (!productCodes.isEmpty()) {
            for (Product2 product : [
                SELECT Id
                FROM Product2
                WHERE ProductCode IN :productCodes AND IsActive = TRUE
            ]) {
                productIds.add(product.Id);
            }
        }

        Map<String, PricebookEntry> entryByKey = new Map<String, PricebookEntry>();
        for (PricebookEntry entry : FieldServiceQuoteService.selectPricebookEntries(
                quoteRecord.Pricebook2Id,
                quoteRecord.CurrencyIsoCode,
                productIds
            )
            .values()) {
            entryByKey.put(entry.Product2Id, entry);
            entryByKey.put(entry.Product2.ProductCode, entry);
        }
        return entryByKey;
    }

    private static String entryKey(LineView line) {
        return line.lineType == FieldServiceQuoteService.LINE_TYPE_PARTS
            ? (String) line.product2Id
            : configuredProductCode(line.lineType);
    }

    @TestVisible
    private static String configuredProductCode(String lineType) {
        if (lineType == FieldServiceQuoteService.LINE_TYPE_LABOR) {
            return System.Label.FS_Quote_Labor_Product_Code;
        }
        if (lineType == FieldServiceQuoteService.LINE_TYPE_TRAVEL) {
            return System.Label.FS_Quote_Travel_Product_Code;
        }
        if (lineType == FieldServiceQuoteService.LINE_TYPE_EXPENSE) {
            return System.Label.FS_Quote_Expense_Product_Code;
        }
        return null;
    }

    private static QuoteView buildView(Id quoteId) {
        Quote quoteRecord = selectQuote(quoteId);
        QuoteView view = new QuoteView();
        view.header = toHeaderView(quoteRecord);
        for (QuoteLineItem record : selectLines(quoteId)) {
            if (EDITOR_LINE_TYPES.contains(record.LineType__c)) {
                view.lines.add(toLineView(record));
            }
        }
        view.rateList = selectRateList(quoteRecord.RateList__c);
        view.statusOptions = picklistOptions(Quote.Status.getDescribe());
        view.expenseTypeOptions = picklistOptions(QuoteLineItem.ExpenseType__c.getDescribe());
        view.canOverridePrice = FeatureManagement.checkPermission(PRICE_OVERRIDE_PERMISSION);
        view.expenseProduct = selectExpenseProduct(quoteRecord);
        return view;
    }

    private static ProductView selectExpenseProduct(Quote quoteRecord) {
        String code = System.Label.FS_Quote_Expense_Product_Code;
        List<Product2> products = [SELECT Id FROM Product2 WHERE ProductCode = :code AND IsActive = TRUE LIMIT 1];
        if (products.isEmpty()) {
            return null;
        }
        PricebookEntry entry = FieldServiceQuoteService.selectPricebookEntries(
                quoteRecord.Pricebook2Id,
                quoteRecord.CurrencyIsoCode,
                new Set<Id>{ products[0].Id }
            )
            .get(products[0].Id);
        return entry == null ? null : toProductView(entry);
    }

    private static WoDebriefRateListController.RateListPrices selectRateList(Id rateListId) {
        if (rateListId == null) {
            return null;
        }
        // Same fields as RateListSelector.selectByIdsForDebriefPricing (API 67, user mode); queried here in this
        // class's context so the editor does not depend on the caller's Rate List field access.
        List<RateList__c> rateLists = [
            SELECT Id, Name, LaborHour__c, TravelHour__c, PremiumRateHour__c, ExtendedOvertimeRatePerHour__c,
                TravelZone1__c, TravelZone2__c, TravelZone3__c, TravelZone4__c
            FROM RateList__c
            WHERE Id = :rateListId
        ];
        if (rateLists.isEmpty()) {
            return null;
        }
        RateList__c rateList = rateLists[0];
        WoDebriefRateListController.RateListPrices dto = new WoDebriefRateListController.RateListPrices();
        dto.rateListId = rateList.Id;
        dto.name = rateList.Name;
        dto.laborHour = rateList.LaborHour__c;
        dto.travelHour = rateList.TravelHour__c;
        dto.premiumRateHour = rateList.PremiumRateHour__c;
        dto.extendedOvertimeRatePerHour = rateList.ExtendedOvertimeRatePerHour__c;
        dto.travelZone1 = rateList.TravelZone1__c;
        dto.travelZone2 = rateList.TravelZone2__c;
        dto.travelZone3 = rateList.TravelZone3__c;
        dto.travelZone4 = rateList.TravelZone4__c;
        return dto;
    }

    private static Quote selectQuote(Id quoteId) {
        if (quoteId == null) {
            throw new FieldServiceQuoteService.FieldServiceQuoteException('No quote was provided to the editor.');
        }
        List<Quote> quotes = [
            SELECT Id, QuoteNumber, Name, Status, WorkOrder__c, WorkOrder__r.WorkOrderNumber, AccountId, Account.Name,
                QuoteAccountId, QuoteAccount.Name, Asset__c, Asset__r.Name, ContactId, Contact.Name,
                ShipToAccount__c, ShipToAccount__r.Name, OwnerId, Owner.Name, RateList__c, RateList__r.Name,
                CurrencyIsoCode, Pricebook2Id, PricingStatus__c, PricingMessage__c, GrandTotal
            FROM Quote
            WHERE Id = :quoteId
        ];
        if (quotes.isEmpty()) {
            throw new FieldServiceQuoteService.FieldServiceQuoteException(
                'The quote was not found or you do not have access to it.'
            );
        }
        return quotes[0];
    }

    private static List<QuoteLineItem> selectLines(Id quoteId) {
        return [
            SELECT Id, LineType__c, Product2Id, Product2.Name, Product2.ProductCode, Quantity, Rate__c, TravelType__c,
                ExpenseType__c, ListPrice, UnitPrice, Discount, TotalPrice, Description, IsManualPrice__c,
                PricingMessage__c
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
            ORDER BY SortOrder ASC NULLS LAST, CreatedDate ASC
        ];
    }

    private static HeaderView toHeaderView(Quote quoteRecord) {
        HeaderView header = new HeaderView();
        header.quoteId = quoteRecord.Id;
        header.quoteNumber = quoteRecord.QuoteNumber;
        header.name = quoteRecord.Name;
        header.status = quoteRecord.Status;
        header.workOrderId = quoteRecord.WorkOrder__c;
        header.workOrderNumber = quoteRecord.WorkOrder__r?.WorkOrderNumber;
        header.accountId = quoteRecord.AccountId != null ? quoteRecord.AccountId : quoteRecord.QuoteAccountId;
        header.accountName = quoteRecord.AccountId != null ? quoteRecord.Account?.Name : quoteRecord.QuoteAccount?.Name;
        header.assetName = quoteRecord.Asset__r?.Name;
        header.contactId = quoteRecord.ContactId;
        header.contactName = quoteRecord.Contact?.Name;
        header.shipToId = quoteRecord.ShipToAccount__c;
        header.shipToName = quoteRecord.ShipToAccount__r?.Name;
        header.ownerId = quoteRecord.OwnerId;
        header.ownerName = quoteRecord.Owner?.Name;
        header.rateListName = quoteRecord.RateList__r?.Name;
        header.currencyIsoCode = quoteRecord.CurrencyIsoCode;
        header.pricingStatus = quoteRecord.PricingStatus__c;
        header.pricingMessage = quoteRecord.PricingMessage__c;
        header.totalPrice = quoteRecord.GrandTotal;
        return header;
    }

    private static LineView toLineView(QuoteLineItem record) {
        LineView line = new LineView();
        line.id = record.Id;
        line.lineType = record.LineType__c;
        line.product2Id = record.Product2Id;
        line.productName = record.Product2?.Name;
        line.productCode = record.Product2?.ProductCode;
        line.quantity = record.Quantity;
        line.rate = record.Rate__c;
        line.travelType = record.TravelType__c;
        line.expenseType = record.ExpenseType__c;
        line.listPrice = record.ListPrice;
        line.unitPrice = record.UnitPrice;
        line.discount = record.Discount;
        line.totalPrice = record.TotalPrice;
        line.description = record.Description;
        line.isManualPrice = record.IsManualPrice__c;
        line.pricingMessage = record.PricingMessage__c;
        return line;
    }

    private static ProductView toProductView(PricebookEntry entry) {
        ProductView product = new ProductView();
        product.product2Id = entry.Product2Id;
        product.productName = entry.Product2.Name;
        product.productCode = entry.Product2.ProductCode;
        product.listPrice = entry.UnitPrice;
        return product;
    }

    private static List<Option> picklistOptions(Schema.DescribeFieldResult field) {
        List<Option> options = new List<Option>();
        for (Schema.PicklistEntry entry : field.getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new Option(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    private static AuraHandledException toAuraException(Exception ex) {
        String message = ex instanceof DmlException ? ((DmlException) ex).getDmlMessage(0) : ex.getMessage();
        AuraHandledException auraException = new AuraHandledException(message);
        auraException.setMessage(message);
        return auraException;
    }
}