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

	private static final Integer OPPORTUNITY_NAME_MAX = 120;
	private static final Id OPPORTUNITY_RECORD_TYPE_ID = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
		.get(OPPORTUNITY_RECORD_TYPE)
		.getRecordTypeId();

	/**
	 * @description Makes sure a Field Service quote has its parent opportunity (GW-6603), and links an
	 *              account-only opportunity to the Work Order once the quote has one.
	 * @param quoteId Quote Id
	 */
	public static void ensureOpportunity(Id quoteId) {
		Quote quoteRecord = [
			SELECT Id, OpportunityId, OwnerId, CurrencyIsoCode, Pricebook2Id, ExpirationDate, WorkOrder__c,
				WorkOrder__r.WorkOrderNumber, ShipToAccount__c, QuoteAccountId, Name
			FROM Quote
			WHERE Id = :quoteId
		];
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
	public static Map<Id, PricebookEntry> selectPricebookEntries(
		Id pricebookId,
		String currencyIsoCode,
		Set<Id> productIds
	) {
		Map<Id, PricebookEntry> entryByProductId = new Map<Id, PricebookEntry>();
		if (pricebookId == null || productIds.isEmpty()) {
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
	 * @description GW-6603: Field Service opportunity access runs without sharing so the existing opportunity for a
	 *              Work Order is reused even when the current user cannot see it (opportunities are private).
	 */
	private without sharing class OpportunityGateway {
		/**
		 * @description Returns the Field Service opportunity for the Work Order, creating it when missing.
		 *              Quotes without a Work Order get a new account-only opportunity.
		 */
		public Id findOrCreate(Quote quoteRecord, Id workOrderId, Id accountId, String reference) {
			if (workOrderId != null) {
				List<Opportunity> existing = [
					SELECT Id
					FROM Opportunity
					WHERE WorkOrder__c = :workOrderId AND RecordTypeId = :OPPORTUNITY_RECORD_TYPE_ID
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
			List<Opportunity> opportunities = [
				SELECT Id
				FROM Opportunity
				WHERE Id = :opportunityId AND RecordTypeId = :OPPORTUNITY_RECORD_TYPE_ID AND WorkOrder__c = NULL
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