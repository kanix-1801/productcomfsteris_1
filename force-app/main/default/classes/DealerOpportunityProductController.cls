/**
 * @description #GC-3047 Dealer product search and save for the Dealer mode of eppOpportunityProducts.
 * EPP capital and consumable behavior stays in EPPProductController.
 * Catalog queries use system mode because the dealer license cannot be granted View All on Product or Price Book. Opportunity and line access stay in user mode.
 */
public without sharing class DealerOpportunityProductController {
	private static final String DEALER_RECORD_TYPE = 'HCSalesDealer';
	private static final String SERVICE_CATEGORY = 'SERVICE';
	private static final Integer SEARCH_LIMIT = 50;
	private static final Integer RECENT_LIMIT = 10;
	private static final Set<String> STATUSES = new Set<String>{
		'Open',
		'Closed Won',
		'Closed Lost',
		'Closed Cancelled',
		'Closed Did Not Participate/Bid'
	};
	private static final Set<String> CONFIDENCE_LEVELS = new Set<String>{
		'Pipeline',
		'Budget',
		'Upside',
		'Make It',
		'Won',
		'Lost'
	};

	public class DealerContext {
		@AuraEnabled public String currencyCode;
		@AuraEnabled public Date closeDate;
		@AuraEnabled public Date expectedShipDate;
		@AuraEnabled public String forecastConfidence;
		@AuraEnabled public List<CurrencyRate> currencies;
	}

	public class CurrencyRate {
		@AuraEnabled public String isoCode;
		@AuraEnabled public Integer decimalPlaces;
		@AuraEnabled public Decimal conversionRate;
	}

	public class ProductOption {
		@AuraEnabled public Id pricebookEntryId;
		@AuraEnabled public Id productId;
		@AuraEnabled public String productName;
		@AuraEnabled public String productCode;
		@AuraEnabled public String productFamily;
		@AuraEnabled public String businessUnit;
		@AuraEnabled public String salesCategoryCode;
		@AuraEnabled public String productDescription;
		@AuraEnabled public Decimal listPrice;
		@AuraEnabled public String currencyCode;
		@AuraEnabled public Boolean recentlyAdded;
	}

	public class ProductLine {
		@AuraEnabled public Id opportunityLineItemId;
		@AuraEnabled public Id productId;
		@AuraEnabled public String productName;
		@AuraEnabled public String productCode;
		@AuraEnabled public Decimal quantity;
		@AuraEnabled public Decimal unitPrice;
		@AuraEnabled public Decimal totalPrice;
		@AuraEnabled public String currencyCode;
		@AuraEnabled public String status;
		@AuraEnabled public String confidenceLevel;
		@AuraEnabled public Date expectedOrderDate;
		@AuraEnabled public Date expectedShipDate;
		@AuraEnabled public String comments;
	}

	public class LineInput {
		public String pricebookEntryId;
		public Decimal quantity;
		public Decimal unitPrice;
		public String status;
		public String confidenceLevel;
		public Date expectedOrderDate;
		public Date expectedShipDate;
		public String comments;
		public String currencyCode;
	}

    /**
     * @description Header values used to prefill a new dealer product line.
     * @param opportunityId Dealer opportunity open on the page
     * @return Currency and the dates and confidence copied onto a blank line
     */
	@AuraEnabled
	public static DealerContext getDealerContext(Id opportunityId) {
		Opportunity opportunity = requireDealerOpportunity(opportunityId);
		DealerContext context = new DealerContext();
		context.currencyCode = opportunity.CurrencyIsoCode;
		context.closeDate = opportunity.CloseDate;
		context.expectedShipDate = opportunity.Expected_Ship_Date__c;
		context.forecastConfidence = opportunity.ForecastConfidenceLevel__c;
		context.currencies = activeCurrencyRates();
		return context;
	}

    /**
     * @description Searches active Standard Price Book products for one dealer opportunity.
     * Service products are excluded. The price book and currency come from the opportunity.
     * @param opportunityId Dealer opportunity open on the page
     * @param searchKey Product name, item number, or description. Blank lists this dealer's recently added products first, then the price book by name.
     * @return Eligible price book entries
     */
	@AuraEnabled
	public static List<ProductOption> searchProducts(Id opportunityId, String searchKey) {
		Opportunity opportunity = requireDealerOpportunity(opportunityId);
		requirePriceBook(opportunity);
		String likeKey = likeTerm(searchKey);
		List<Id> recentIds = recentProductIds(opportunity);
		Set<Id> recentIdSet = new Set<Id>(recentIds);
		List<ProductOption> options = new List<ProductOption>();
		Set<Id> excludedProductIds = new Set<Id>();
		if (likeKey == null) {
			for (PricebookEntry entry : entriesForProducts(opportunity, recentIds)) {
				if (options.size() == SEARCH_LIMIT) {
					break;
				}
				options.add(toOption(entry, opportunity.CurrencyIsoCode, true));
				excludedProductIds.add(entry.Product2Id);
			}
		}
		Integer remaining = SEARCH_LIMIT - options.size();
		if (remaining > 0) {
			for (PricebookEntry entry : catalogEntries(opportunity, likeKey, excludedProductIds, remaining)) {
				options.add(toOption(
					entry,
					opportunity.CurrencyIsoCode,
					recentIdSet.contains(entry.Product2Id)
				));
			}
		}
		return options;
	}

    /**
     * @description Loads the product lines already saved on a dealer opportunity.
     * @param opportunityId Dealer opportunity open on the page
     * @return Product lines for the dealer grid
     */
	@AuraEnabled
	public static List<ProductLine> getProducts(Id opportunityId) {
		Opportunity opportunity = requireDealerOpportunity(opportunityId);
		List<ProductLine> lines = new List<ProductLine>();
		for (OpportunityLineItem line : [
			SELECT Id, Product2Id, Product2.Name, ProductCode, Quantity, UnitPrice, TotalPrice,
				Status__c, ConfidenceLevel__c, ExpectedOrderDate__c, ExpectedShipDate__c, Comments__c
			FROM OpportunityLineItem
			WHERE OpportunityId = :opportunity.Id
			WITH USER_MODE
			ORDER BY CreatedDate, Id
		]) {
			ProductLine row = new ProductLine();
			row.opportunityLineItemId = line.Id;
			row.productId = line.Product2Id;
			row.productName = line.Product2.Name;
			row.productCode = line.ProductCode;
			row.quantity = line.Quantity;
			row.unitPrice = line.UnitPrice;
			row.totalPrice = line.TotalPrice;
			row.currencyCode = opportunity.CurrencyIsoCode;
			row.status = line.Status__c;
			row.confidenceLevel = line.ConfidenceLevel__c;
			row.expectedOrderDate = line.ExpectedOrderDate__c;
			row.expectedShipDate = line.ExpectedShipDate__c;
			row.comments = line.Comments__c;
			lines.add(row);
		}
		return lines;
	}

    /**
     * @description Adds dealer product lines. Blank status, confidence, and dates are filled from the opportunity.
     * @param opportunityId Dealer opportunity open on the page
     * @param productInputsJson Selected price book entries and the values entered on the grid
     * @return Number of lines created
     */
	@AuraEnabled
	public static Integer createProducts(Id opportunityId, String productInputsJson) {
		Opportunity opportunity = requireDealerOpportunity(opportunityId);
		requirePriceBook(opportunity);
		List<LineInput> inputs = parseInputs(productInputsJson);
		Map<Id, PricebookEntry> entriesById = entriesForInputs(opportunity, inputs);
		Map<String, CurrencyType> ratesByCode = currencyTypesByCode();
		List<OpportunityLineItem> lines = new List<OpportunityLineItem>();
		for (LineInput input : inputs) {
			PricebookEntry entry = entriesById.get(input.pricebookEntryId);
			if (entry == null) {
				throwAura('Select a product from this opportunity price book.');
			}
			OpportunityLineItem line = new OpportunityLineItem();
			line.OpportunityId = opportunity.Id;
			line.PricebookEntryId = entry.Id;
			line.Quantity = input.quantity;
			line.UnitPrice = convertToOpportunityCurrency(
				input.unitPrice,
				input.currencyCode,
				opportunity.CurrencyIsoCode,
				ratesByCode
			);
			line.Status__c = String.isBlank(input.status) ? 'Open' : input.status;
			line.ConfidenceLevel__c = String.isBlank(input.confidenceLevel)
				? opportunity.ForecastConfidenceLevel__c
				: input.confidenceLevel;
			line.ExpectedOrderDate__c = input.expectedOrderDate == null
				? opportunity.CloseDate
				: input.expectedOrderDate;
			line.ExpectedShipDate__c = input.expectedShipDate == null
				? opportunity.Expected_Ship_Date__c
				: input.expectedShipDate;
			line.Comments__c = blankToNull(input.comments);
			lines.add(line);
		}
		insert as user lines;
		return lines.size();
	}

    /**
     * @description Removes one product line from a dealer opportunity.
     * @param opportunityId Dealer opportunity open on the page
     * @param opportunityLineItemId Line selected in the grid
     */
	@AuraEnabled
	public static void deleteProduct(Id opportunityId, Id opportunityLineItemId) {
		Opportunity opportunity = requireDealerOpportunity(opportunityId);
		if (opportunityLineItemId == null) {
			throwAura('Select a product line to remove.');
		}
		List<OpportunityLineItem> lines = [
			SELECT Id
			FROM OpportunityLineItem
			WHERE Id = :opportunityLineItemId
			AND OpportunityId = :opportunity.Id
			WITH USER_MODE
			LIMIT 1
		];
		if (lines.isEmpty()) {
			throwAura('The product line could not be found on this opportunity.');
		}
		delete as user lines;
	}

	private static Opportunity requireDealerOpportunity(Id opportunityId) {
		if (opportunityId == null) {
			throwAura('Opportunity is required.');
		}
		List<Opportunity> opportunities = [
			SELECT Id, AccountId, Pricebook2Id, CurrencyIsoCode, CloseDate, Expected_Ship_Date__c,
				ForecastConfidenceLevel__c, RecordType.DeveloperName
			FROM Opportunity
			WHERE Id = :opportunityId
			WITH USER_MODE
			LIMIT 1
		];
		if (opportunities.isEmpty()) {
			throwAura('You do not have access to this opportunity.');
		}
		if (opportunities[0].RecordType.DeveloperName != DEALER_RECORD_TYPE) {
			throwAura('Products can be added here only for a dealer opportunity.');
		}
		return opportunities[0];
	}

	private static void requirePriceBook(Opportunity opportunity) {
		if (opportunity.Pricebook2Id == null) {
			throwAura('This opportunity has no price book.');
		}
	}

	private static List<LineInput> parseInputs(String productInputsJson) {
		if (String.isBlank(productInputsJson)) {
			throwAura('Select at least one product.');
		}
		List<LineInput> inputs = (List<LineInput>) JSON.deserialize(productInputsJson, List<LineInput>.class);
		if (inputs == null || inputs.isEmpty()) {
			throwAura('Select at least one product.');
		}
		for (LineInput input : inputs) {
			if (input == null || String.isBlank(input.pricebookEntryId)) {
				throwAura('Select a product from the search results.');
			}
			if (input.quantity == null || input.quantity <= 0) {
				throwAura('Enter a quantity greater than zero.');
			}
			if (input.unitPrice == null || input.unitPrice < 0) {
				throwAura('Enter the unit price the dealer expects to pay STERIS.');
			}
			if (String.isNotBlank(input.status) && !STATUSES.contains(input.status)) {
				throwAura('Select a valid product status.');
			}
			if (String.isNotBlank(input.confidenceLevel) && !CONFIDENCE_LEVELS.contains(input.confidenceLevel)) {
				throwAura('Select a valid forecast confidence.');
			}
			if (input.comments != null && input.comments.trim().length() > 250) {
				throwAura('Comments cannot be longer than 250 characters.');
			}
		}
		return inputs;
	}

	private static Map<Id, PricebookEntry> entriesForInputs(Opportunity opportunity, List<LineInput> inputs) {
		Set<Id> entryIds = new Set<Id>();
		for (LineInput input : inputs) {
			entryIds.add(input.pricebookEntryId);
		}
		Map<Id, PricebookEntry> entriesById = new Map<Id, PricebookEntry>();
		for (PricebookEntry entry : [
			SELECT Id, Product2.SalesCategoryCode__c, Pricebook2Id, CurrencyIsoCode, IsActive, Product2.IsActive
			FROM PricebookEntry
			WHERE Id IN :entryIds
			WITH SYSTEM_MODE
		]) {
			if (entry.Product2.SalesCategoryCode__c == SERVICE_CATEGORY) {
				throwAura('Service products cannot be added to a dealer opportunity.');
			}
			if (entry.Pricebook2Id != opportunity.Pricebook2Id
				|| entry.CurrencyIsoCode != opportunity.CurrencyIsoCode
				|| entry.IsActive != true
				|| entry.Product2.IsActive != true) {
				throwAura('Select a product from this opportunity price book.');
			}
			entriesById.put(entry.Id, entry);
		}
		return entriesById;
	}

	private static List<Id> recentProductIds(Opportunity opportunity) {
		List<Id> productIds = new List<Id>();
		if (opportunity.AccountId == null) {
			return productIds;
		}
		for (AggregateResult result : [
			SELECT Product2Id
			FROM OpportunityLineItem
			WHERE Opportunity.AccountId = :opportunity.AccountId
			AND Opportunity.RecordType.DeveloperName = :DEALER_RECORD_TYPE
			AND Product2Id != null
			AND (NOT Product2.SalesCategoryCode__c = :SERVICE_CATEGORY)
			WITH USER_MODE
			GROUP BY Product2Id
			ORDER BY MAX(CreatedDate) DESC
			LIMIT :RECENT_LIMIT
		]) {
			productIds.add((Id) result.get('Product2Id'));
		}
		return productIds;
	}

	private static List<PricebookEntry> entriesForProducts(Opportunity opportunity, List<Id> productIds) {
		List<PricebookEntry> ordered = new List<PricebookEntry>();
		if (productIds.isEmpty()) {
			return ordered;
		}
		Map<Id, PricebookEntry> entriesByProduct = new Map<Id, PricebookEntry>();
		for (PricebookEntry entry : [
			SELECT Id, UnitPrice, Product2Id, Product2.Name, Product2.ProductCode, Product2.Description,
				Product2.ItemFamily__c, Product2.BusinessUnit__c, Product2.SalesCategoryCode__c
			FROM PricebookEntry
			WHERE Pricebook2Id = :opportunity.Pricebook2Id
			AND CurrencyIsoCode = :opportunity.CurrencyIsoCode
			AND IsActive = true
			AND Product2.IsActive = true
			AND Product2Id IN :productIds
			AND (NOT Product2.SalesCategoryCode__c = :SERVICE_CATEGORY)
			WITH SYSTEM_MODE
		]) {
			entriesByProduct.put(entry.Product2Id, entry);
		}
		for (Id productId : productIds) {
			if (entriesByProduct.containsKey(productId)) {
				ordered.add(entriesByProduct.get(productId));
			}
		}
		return ordered;
	}

	private static List<PricebookEntry> catalogEntries(
		Opportunity opportunity,
		String likeKey,
		Set<Id> excludedProductIds,
		Integer rowLimit
	) {
		if (likeKey == null) {
			return [
				SELECT Id, UnitPrice, Product2Id, Product2.Name, Product2.ProductCode, Product2.Description,
				Product2.ItemFamily__c, Product2.BusinessUnit__c, Product2.SalesCategoryCode__c
				FROM PricebookEntry
				WHERE Pricebook2Id = :opportunity.Pricebook2Id
				AND CurrencyIsoCode = :opportunity.CurrencyIsoCode
				AND IsActive = true
				AND Product2.IsActive = true
				AND (NOT Product2.SalesCategoryCode__c = :SERVICE_CATEGORY)
				AND Product2Id NOT IN :excludedProductIds
				WITH SYSTEM_MODE
				ORDER BY Product2.Name
				LIMIT :rowLimit
			];
		}
		return [
			SELECT Id, UnitPrice, Product2Id, Product2.Name, Product2.ProductCode, Product2.Description,
				Product2.ItemFamily__c, Product2.BusinessUnit__c, Product2.SalesCategoryCode__c
			FROM PricebookEntry
			WHERE Pricebook2Id = :opportunity.Pricebook2Id
			AND CurrencyIsoCode = :opportunity.CurrencyIsoCode
			AND IsActive = true
			AND Product2.IsActive = true
			AND (NOT Product2.SalesCategoryCode__c = :SERVICE_CATEGORY)
			AND Product2Id NOT IN :excludedProductIds
			AND (
				Product2.Name LIKE :likeKey
				OR Product2.ProductCode LIKE :likeKey
				OR Product2.Description LIKE :likeKey
			)
			WITH SYSTEM_MODE
			ORDER BY Product2.Name
			LIMIT :rowLimit
		];
	}

	private static ProductOption toOption(PricebookEntry entry, String currencyCode, Boolean recentlyAdded) {
		ProductOption option = new ProductOption();
		option.pricebookEntryId = entry.Id;
		option.productId = entry.Product2Id;
		option.productName = entry.Product2.Name;
		option.productCode = entry.Product2.ProductCode;
		option.productFamily = entry.Product2.ItemFamily__c;
		option.businessUnit = entry.Product2.BusinessUnit__c;
		option.salesCategoryCode = entry.Product2.SalesCategoryCode__c;
		option.productDescription = entry.Product2.Description;
		option.listPrice = entry.UnitPrice;
		option.currencyCode = currencyCode;
		option.recentlyAdded = recentlyAdded;
		return option;
	}

	private static List<CurrencyRate> activeCurrencyRates() {
		List<CurrencyRate> rates = new List<CurrencyRate>();
		for (CurrencyType currencyType : [
			SELECT IsoCode, ConversionRate, DecimalPlaces
			FROM CurrencyType
			WHERE IsActive = true
			ORDER BY IsoCode
		]) {
			CurrencyRate rate = new CurrencyRate();
			rate.isoCode = currencyType.IsoCode;
			rate.decimalPlaces = currencyType.DecimalPlaces;
			rate.conversionRate = currencyType.ConversionRate;
			rates.add(rate);
		}
		return rates;
	}

	private static Map<String, CurrencyType> currencyTypesByCode() {
		Map<String, CurrencyType> ratesByCode = new Map<String, CurrencyType>();
		for (CurrencyType currencyType : [
			SELECT IsoCode, ConversionRate, DecimalPlaces
			FROM CurrencyType
			WHERE IsActive = true
		]) {
			ratesByCode.put(currencyType.IsoCode, currencyType);
		}
		return ratesByCode;
	}

	private static Decimal convertToOpportunityCurrency(
		Decimal amount,
		String enteredCurrency,
		String opportunityCurrency,
		Map<String, CurrencyType> ratesByCode
	) {
		if (String.isBlank(enteredCurrency) || enteredCurrency == opportunityCurrency) {
			return amount;
		}
		CurrencyType fromRate = ratesByCode.get(enteredCurrency);
		CurrencyType toRate = ratesByCode.get(opportunityCurrency);
		if (fromRate == null || toRate == null || fromRate.ConversionRate == null || fromRate.ConversionRate == 0) {
			throwAura('Select a permitted currency.');
		}
		Integer places = toRate.DecimalPlaces == null ? 2 : toRate.DecimalPlaces;
		return (amount * toRate.ConversionRate / fromRate.ConversionRate)
			.setScale(places, System.RoundingMode.HALF_UP);
	}

	private static String likeTerm(String searchKey) {
		if (String.isBlank(searchKey)) {
			return null;
		}
		return '%' + searchKey.trim() + '%';
	}

	private static String blankToNull(String value) {
		return String.isBlank(value) ? null : value.trim();
	}

	private static void throwAura(String message) {
		AuraHandledException handled = new AuraHandledException(message);
		handled.setMessage(message);
		throw handled;
	}
}