/**
 * @description GW-5892: Field Service Quote helpers used by the Edit Quote editor.
 *              - GW-6603: finds or creates the Field Service opportunity (one per Work Order) so the quote can be
 *                shared (Quote OWD is Controlled by Parent) and Quote.AccountId is populated.
 *              Quote creation from a Work Order is done by the Field Service mobile flow
 *              WorkOrder_MobileFlow_CreateFieldServiceQuote and its subflows.
 * @group Field Service Quote
 * @see FieldServiceQuoteController
 */
public inherited sharing class FieldServiceQuoteService {
	public static final String OPPORTUNITY_RECORD_TYPE = 'Field_Service_Quote';
	public static final String STAGE_OPEN = 'Open';
	public static final String PRICING_PRICED = 'Priced';
	public static final String PRICING_REPRICING_REQUIRED = 'Repricing Required';
	public static final String LINE_TYPE_PARTS = 'Parts';
	public static final String LINE_TYPE_LABOR = 'Labor';
	public static final String LINE_TYPE_TRAVEL = 'Travel';
	public static final String LINE_TYPE_EXPENSE = 'Expense';
	/** @description Days a new quote stays valid; also drives the opportunity Close Date. */
	public static final Integer QUOTE_VALIDITY_DAYS = 30;

	/** @description Product codes used for the non-Parts line types. */
	public static final String LABOR_PRODUCT_CODE = 'FSLABOR';
	public static final String TRAVEL_PRODUCT_CODE = 'FSTRAVEL';
	public static final String EXPENSE_PRODUCT_CODE = 'FSEXPPRT';

	private static final Map<String, String> PRODUCT_CODE_BY_LINE_TYPE = new Map<String, String>{
		LINE_TYPE_LABOR => LABOR_PRODUCT_CODE,
		LINE_TYPE_TRAVEL => TRAVEL_PRODUCT_CODE,
		LINE_TYPE_EXPENSE => EXPENSE_PRODUCT_CODE
	};

	private static final Integer OPPORTUNITY_NAME_MAX = 120;
	private static final Id OPPORTUNITY_RECORD_TYPE_ID = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
		.get(OPPORTUNITY_RECORD_TYPE)
		.getRecordTypeId();

	/**
	 * @description Loads a Field Service quote, or throws a FieldServiceQuoteException the user can read.
	 * @param quoteId Quote Id
	 * @return Quote
	 */
	public static Quote getQuote(Id quoteId) {
		List<Quote> quotes = QuoteSelector.selectFieldServiceQuoteById(quoteId);
		if (quotes.isEmpty()) {
			throw new FieldServiceQuoteException('The quote was not found or you do not have access to it.');
		}
		return quotes[0];
	}

	/**
	 * @description Product code used for a Labor, Travel or Expense line.
	 * @param lineType Quote line type
	 * @return Product code, or null for Parts and unknown line types
	 */
	public static String productCodeFor(String lineType) {
		return PRODUCT_CODE_BY_LINE_TYPE.get(lineType);
	}

	/**
	 * @description Makes sure a Field Service quote has its parent opportunity (GW-6603), and links an
	 *              account-only opportunity to the Work Order once the quote has one.
	 * @param quoteId Quote Id
	 */
	public static void ensureOpportunity(Id quoteId) {
		Quote quoteRecord = getQuote(quoteId);
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
	 * @description Active price book entries keyed by Product Id.
	 * @param pricebookId Price Book Id
	 * @param currencyIsoCode Currency
	 * @param productIds Product Ids
	 * @return Map of Product Id to entry
	 */
	public static Map<Id, PricebookEntry> getPricebookEntriesByProductId(
		Id pricebookId,
		String currencyIsoCode,
		Set<Id> productIds
	) {
		Map<Id, PricebookEntry> entryByProductId = new Map<Id, PricebookEntry>();
		for (PricebookEntry entry : PricebookEntriesSelector.selectActiveWithPriceByPricebookProductAndCurrency(
				pricebookId,
				productIds,
				currencyIsoCode
			)) {
			entryByProductId.put(entry.Product2Id, entry);
		}
		return entryByProductId;
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
			List<Opportunity> existing = OpportunitySelector.selectFieldServiceByWorkOrderId(
				workOrderId,
				OPPORTUNITY_RECORD_TYPE_ID
			);
			if (!existing.isEmpty()) {
				return existing[0].Id;
			}

			String accountName = '';
			if (accountId != null) {
				List<Account> accounts = AccountSelector.selectByIds(new Set<Id>{ accountId });
				accountName = accounts.isEmpty() ? '' : accounts[0].Name;
			}
			String name = 'FS Quote - ' + (String.isBlank(reference) ? '' : reference) +
				(String.isBlank(accountName) ? '' : ' - ' + accountName);

			Id ownerId = quoteRecord.OwnerId;
			if (ownerId == null || ownerId.getSObjectType() != User.SObjectType) {
				ownerId = UserInfo.getUserId();
			}

			Opportunity opportunityRecord = new Opportunity(
				RecordTypeId = OPPORTUNITY_RECORD_TYPE_ID,
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
			if (workOrderId == null) {
				return;
			}
			List<Opportunity> opportunities = OpportunitySelector.selectFieldServiceWithoutWorkOrderById(
				opportunityId,
				OPPORTUNITY_RECORD_TYPE_ID
			);
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