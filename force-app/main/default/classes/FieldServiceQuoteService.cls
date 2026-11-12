/**
 * @description GW-5892: Field Service Quote creation and the generic Field Service opportunity that parents it.
 *              - GW-6710: builds the Quote header from the Work Order.
 *              - GW-6731: converts the Work Order's Products Required (WO and its WOLIs) into Parts quote lines.
 *              - GW-6603: finds or creates the Field Service opportunity (one per Work Order) so the quote can be
 *                shared (Quote OWD is Controlled by Parent) and Quote.AccountId is populated.
 * @group Field Service Quote
 * @see FieldServiceQuoteCreateAction
 * @see FieldServiceQuoteController
 */
public inherited sharing class FieldServiceQuoteService {
    public static final String QUOTE_RECORD_TYPE = 'Field_Service';
    public static final String OPPORTUNITY_RECORD_TYPE = 'Field_Service_Quote';
    public static final String STAGE_OPEN = 'Open';
    public static final String STATUS_DRAFT = 'Draft';
    public static final String PRICING_NOT_PRICED = 'Not Priced';
    public static final String PRICING_PRICED = 'Priced';
    public static final String PRICING_REPRICING_REQUIRED = 'Repricing Required';
    public static final String LINE_TYPE_PARTS = 'Parts';
    public static final String LINE_TYPE_LABOR = 'Labor';
    public static final String LINE_TYPE_TRAVEL = 'Travel';
    public static final String LINE_TYPE_EXPENSE = 'Expense';
    /** @description Days a new quote stays valid; also drives the opportunity Close Date. */
    public static final Integer QUOTE_VALIDITY_DAYS = 30;

    private static final Integer OPPORTUNITY_NAME_MAX = 120;
    private static final Integer QUOTE_NAME_MAX = 255;

    /**
     * @description Result of creating a quote from a Work Order.
     */
    public class CreateResult {
        /** @description New Quote Id. */
        public Id quoteId;
        /** @description Product codes from Products Required skipped because they have no active price book entry. */
        public List<String> skippedProductCodes = new List<String>();
    }

    /**
     * @description Creates a Field Service quote from a Work Order: header, opportunity and Parts lines.
     *              Everything is rolled back if any step fails.
     * @param workOrderId Work Order Id
     * @return Creation result with the new Quote Id and any skipped products
     */
    public static CreateResult createFromWorkOrder(Id workOrderId) {
        WorkOrder workOrder = selectWorkOrder(workOrderId);
        if (workOrder == null) {
            throw new FieldServiceQuoteException('The Work Order was not found or you do not have access to it.');
        }
        if (workOrder.Pricebook2Id == null) {
            throw new FieldServiceQuoteException(
                'The Work Order has no Price Book. Set the Price Book on the Work Order before creating a quote.'
            );
        }

        Savepoint savepoint = Database.setSavepoint();
        try {
            Quote quoteRecord = buildQuoteHeader(workOrder);
            quoteRecord.OpportunityId = new OpportunityGateway().findOrCreate(
                quoteRecord,
                workOrder.Id,
                resolveOpportunityAccountId(workOrder),
                workOrder.WorkOrderNumber
            );
            insert quoteRecord;

            CreateResult result = new CreateResult();
            result.quoteId = quoteRecord.Id;
            result.skippedProductCodes = createPartLinesFromProductsRequired(quoteRecord, workOrder);
            return result;
        } catch (Exception ex) {
            Database.rollback(savepoint);
            throw ex;
        }
    }

    /**
     * @description Makes sure a Field Service quote has its parent opportunity (GW-6603), and links an
     *              account-only opportunity to the Work Order once the quote has one.
     * @param quoteId Quote Id
     */
    public static void ensureOpportunity(Id quoteId) {
        List<Quote> quotes = [
            SELECT Id, OpportunityId, OwnerId, CurrencyIsoCode, Pricebook2Id, ExpirationDate, WorkOrder__c,
                WorkOrder__r.WorkOrderNumber, ShipToAccount__c, QuoteAccountId, Name
            FROM Quote
            WHERE Id = :quoteId
        ];
        if (quotes.isEmpty()) {
            return;
        }
        Quote quoteRecord = quotes[0];
        if (quoteRecord.OpportunityId != null) {
            new OpportunityGateway().linkWorkOrder(quoteRecord.OpportunityId, quoteRecord.WorkOrder__c);
            return;
        }
        Id accountId = quoteRecord.ShipToAccount__c != null ? quoteRecord.ShipToAccount__c : quoteRecord.QuoteAccountId;
        String reference = quoteRecord.WorkOrder__c != null ? quoteRecord.WorkOrder__r.WorkOrderNumber : quoteRecord.Name;
        quoteRecord.OpportunityId = new OpportunityGateway().findOrCreate(
            quoteRecord,
            quoteRecord.WorkOrder__c,
            accountId,
            reference
        );
        update new Quote(Id = quoteRecord.Id, OpportunityId = quoteRecord.OpportunityId);
    }

    /**
     * @description Builds the quote header from the Work Order (not inserted).
     * @param workOrder Work Order selected by selectWorkOrder
     * @return New Quote
     */
    @TestVisible
    private static Quote buildQuoteHeader(WorkOrder workOrder) {
        Id shipToId = workOrder.ShipTo__c != null ? workOrder.ShipTo__c : workOrder.ShipToAddressAccount__c;
        Id rateListId = workOrder.RateList__c != null ? workOrder.RateList__c : workOrder.Account?.RateList__c;

        return new Quote(
            RecordTypeId = recordTypeId(Quote.SObjectType, QUOTE_RECORD_TYPE),
            Name = buildQuoteName(workOrder),
            Status = STATUS_DRAFT,
            PricingStatus__c = PRICING_NOT_PRICED,
            OwnerId = UserInfo.getUserId(),
            QuoteAccountId = workOrder.AccountId,
            ContactId = workOrder.ContactId,
            Asset__c = workOrder.AssetId,
            WorkOrder__c = workOrder.Id,
            BillToAccount__c = workOrder.BillToAddressAccount__c,
            ShipToAccount__c = shipToId,
            ShippingStreet = workOrder.Street,
            ShippingCity = workOrder.City,
            ShippingStateCode = workOrder.StateCode,
            ShippingPostalCode = workOrder.PostalCode,
            ShippingCountryCode = workOrder.CountryCode,
            CurrencyIsoCode = workOrder.CurrencyIsoCode,
            Pricebook2Id = workOrder.Pricebook2Id,
            RateList__c = rateListId,
            RegionalControl__c = resolveRegionalControlId(workOrder),
            ExpirationDate = Date.today().addDays(QUOTE_VALIDITY_DAYS)
        );
    }

    /**
     * @description Quote name convention: <WO Number> - <Asset or Account name>.
     * @param workOrder Work Order
     * @return Quote name
     */
    @TestVisible
    private static String buildQuoteName(WorkOrder workOrder) {
        String suffix = workOrder.AssetId != null ? workOrder.Asset?.Name : workOrder.Account?.Name;
        String name = String.isBlank(suffix) ? workOrder.WorkOrderNumber : workOrder.WorkOrderNumber + ' - ' + suffix;
        return name.left(QUOTE_NAME_MAX);
    }

    /**
     * @description Regional Control from the Work Order, else matched on Country + Account Customer Class Code.
     * @param workOrder Work Order
     * @return Regional Control Id or null
     */
    private static Id resolveRegionalControlId(WorkOrder workOrder) {
        if (workOrder.RegionalControl__c != null) {
            return workOrder.RegionalControl__c;
        }
        List<Regional_Control__c> matches = RegionalControlSelector.selectByBusinessUnitAndCountry(
            workOrder.Account?.CustomerClassCode__c,
            workOrder.Country
        );
        return matches.isEmpty() ? null : matches[0].Id;
    }

    /**
     * @description Opportunity account is the ship-to account, falling back to the Work Order account.
     * @param workOrder Work Order
     * @return Account Id
     */
    private static Id resolveOpportunityAccountId(WorkOrder workOrder) {
        if (workOrder.ShipTo__c != null) {
            return workOrder.ShipTo__c;
        }
        if (workOrder.ShipToAddressAccount__c != null) {
            return workOrder.ShipToAddressAccount__c;
        }
        return workOrder.AccountId;
    }

    /**
     * @description GW-6731: one Parts line per Product Required on the Work Order or its line items.
     *              Products without an active price book entry for the quote's price book and currency are skipped.
     * @param quoteRecord Inserted quote
     * @param workOrder Source Work Order
     * @return Product codes that were skipped
     */
    private static List<String> createPartLinesFromProductsRequired(Quote quoteRecord, WorkOrder workOrder) {
        Set<Id> parentIds = new Set<Id>{ workOrder.Id };
        for (WorkOrderLineItem lineItem : [SELECT Id FROM WorkOrderLineItem WHERE WorkOrderId = :workOrder.Id]) {
            parentIds.add(lineItem.Id);
        }

        List<ProductRequired> productsRequired = [
            SELECT Id, Product2Id, Product2.ProductCode, Product2.Name, QuantityRequired, ParentRecordId
            FROM ProductRequired
            WHERE ParentRecordId IN :parentIds AND Product2Id != NULL
            ORDER BY ProductRequiredNumber ASC
        ];
        List<String> skipped = new List<String>();
        if (productsRequired.isEmpty()) {
            return skipped;
        }

        Set<Id> productIds = new Set<Id>();
        for (ProductRequired productRequired : productsRequired) {
            productIds.add(productRequired.Product2Id);
        }
        Map<Id, PricebookEntry> entryByProductId = selectPricebookEntries(
            quoteRecord.Pricebook2Id,
            quoteRecord.CurrencyIsoCode,
            productIds
        );

        List<QuoteLineItem> lines = new List<QuoteLineItem>();
        for (ProductRequired productRequired : productsRequired) {
            PricebookEntry entry = entryByProductId.get(productRequired.Product2Id);
            if (entry == null) {
                skipped.add(productRequired.Product2.ProductCode);
                continue;
            }
            Boolean fromLineItem = productRequired.ParentRecordId.getSObjectType() == WorkOrderLineItem.SObjectType;
            lines.add(
                new QuoteLineItem(
                    QuoteId = quoteRecord.Id,
                    PricebookEntryId = entry.Id,
                    Product2Id = productRequired.Product2Id,
                    Quantity = productRequired.QuantityRequired != null && productRequired.QuantityRequired > 0
                        ? productRequired.QuantityRequired
                        : 1,
                    UnitPrice = entry.UnitPrice,
                    LineType__c = LINE_TYPE_PARTS,
                    ProductCode__c = productRequired.Product2.ProductCode,
                    WorkOrder__c = workOrder.Id,
                    WorkOrderLineItem__c = fromLineItem ? productRequired.ParentRecordId : null,
                    Asset__c = workOrder.AssetId
                )
            );
        }
        insert lines;
        return skipped;
    }

    /**
     * @description Active price book entries keyed by Product Id.
     * @param pricebookId Price Book Id
     * @param currencyIsoCode Currency
     * @param productIds Product Ids
     * @return Map of Product Id to entry
     */
    public static Map<Id, PricebookEntry> selectPricebookEntries(
        Id pricebookId,
        String currencyIsoCode,
        Set<Id> productIds
    ) {
        Map<Id, PricebookEntry> entryByProductId = new Map<Id, PricebookEntry>();
        if (pricebookId == null || productIds == null || productIds.isEmpty()) {
            return entryByProductId;
        }
        for (PricebookEntry entry : [
            SELECT Id, Product2Id, UnitPrice, Product2.ProductCode, Product2.Name
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId
                AND CurrencyIsoCode = :currencyIsoCode
                AND Product2Id IN :productIds
                AND IsActive = TRUE
        ]) {
            entryByProductId.put(entry.Product2Id, entry);
        }
        return entryByProductId;
    }

    /**
     * @description Work Order fields used to build a Field Service quote.
     * @param workOrderId Work Order Id
     * @return Work Order or null
     */
    private static WorkOrder selectWorkOrder(Id workOrderId) {
        if (workOrderId == null) {
            return null;
        }
        List<WorkOrder> workOrders = [
            SELECT Id, WorkOrderNumber, AccountId, Account.Name, Account.RateList__c, Account.CustomerClassCode__c,
                ContactId, AssetId, Asset.Name, ShipTo__c, ShipToAddressAccount__c, BillToAddressAccount__c,
                CurrencyIsoCode, Pricebook2Id, RateList__c, RegionalControl__c,
                Street, City, StateCode, PostalCode, Country, CountryCode
            FROM WorkOrder
            WHERE Id = :workOrderId
        ];
        return workOrders.isEmpty() ? null : workOrders[0];
    }

    /**
     * @description Active record type Id by developer name.
     * @param objectType SObject type
     * @param developerName Record type developer name
     * @return Record type Id
     */
    public static Id recordTypeId(SObjectType objectType, String developerName) {
        Schema.RecordTypeInfo info = objectType.getDescribe().getRecordTypeInfosByDeveloperName().get(developerName);
        if (info == null) {
            throw new FieldServiceQuoteException(
                'Record type ' + developerName + ' is missing on ' + objectType.getDescribe().getName() + '.'
            );
        }
        return info.getRecordTypeId();
    }

    /**
     * @description GW-6603: Field Service opportunity access runs without sharing so the existing opportunity for a
     *              Work Order is reused even when the current user cannot see it (opportunities are private).
     */
    private without sharing class OpportunityGateway {
        /**
         * @description Returns the Field Service opportunity for the Work Order, creating it when missing.
         *              Quotes without a Work Order get a new account-only opportunity.
         */
        public Id findOrCreate(Quote quoteRecord, Id workOrderId, Id accountId, String reference) {
            Id opportunityRecordTypeId = recordTypeId(Opportunity.SObjectType, OPPORTUNITY_RECORD_TYPE);
            if (workOrderId != null) {
                List<Opportunity> existing = [
                    SELECT Id
                    FROM Opportunity
                    WHERE WorkOrder__c = :workOrderId AND RecordTypeId = :opportunityRecordTypeId
                    ORDER BY CreatedDate ASC
                    LIMIT 1
                ];
                if (!existing.isEmpty()) {
                    return existing[0].Id;
                }
            }

            String accountName = '';
            if (accountId != null) {
                List<Account> accounts = [SELECT Name FROM Account WHERE Id = :accountId];
                accountName = accounts.isEmpty() ? '' : accounts[0].Name;
            }
            String name = 'FS Quote - ' + (String.isBlank(reference) ? '' : reference) +
                (String.isBlank(accountName) ? '' : ' - ' + accountName);

            Id ownerId = quoteRecord.OwnerId;
            if (ownerId == null || ownerId.getSObjectType() != User.SObjectType) {
                ownerId = UserInfo.getUserId();
            }

            Opportunity opportunityRecord = new Opportunity(
                RecordTypeId = opportunityRecordTypeId,
                Name = name.left(OPPORTUNITY_NAME_MAX),
                AccountId = accountId,
                WorkOrder__c = workOrderId,
                StageName = STAGE_OPEN,
                CloseDate = quoteRecord.ExpirationDate != null
                    ? quoteRecord.ExpirationDate
                    : Date.today().addDays(QUOTE_VALIDITY_DAYS),
                OwnerId = ownerId,
                CurrencyIsoCode = quoteRecord.CurrencyIsoCode,
                Pricebook2Id = quoteRecord.Pricebook2Id
            );
            insert opportunityRecord;
            return opportunityRecord.Id;
        }

        public void linkWorkOrder(Id opportunityId, Id workOrderId) {
            if (opportunityId == null || workOrderId == null) {
                return;
            }
            Id opportunityRecordTypeId = recordTypeId(Opportunity.SObjectType, OPPORTUNITY_RECORD_TYPE);
            List<Opportunity> opportunities = [
                SELECT Id
                FROM Opportunity
                WHERE Id = :opportunityId AND RecordTypeId = :opportunityRecordTypeId AND WorkOrder__c = NULL
            ];
            if (!opportunities.isEmpty()) {
                update new Opportunity(Id = opportunityId, WorkOrder__c = workOrderId);
            }
        }
    }

    /**
     * @description Field Service quote business error, shown to the user.
     */
    public class FieldServiceQuoteException extends Exception {
    }
}