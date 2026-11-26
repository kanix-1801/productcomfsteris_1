/**
 * @author Vinay Soni
 * @date 2026/11/25
 * @group IMS Asset Assignment
 * @description GW-6456 - Covered Equipment for the IMS Service Agreement in the RCA configurator.
 *              - Reads the inventory groups on the quote's opportunity (OpportunityAsset__c) and the assets the
 *                rep can pick (group devices + the quote's account and its parent accounts).
 *              - Owns the selection JSON stored on QuoteLineItem.ImsAssetSelection__c (written by the
 *                imsCoveredEquipment LWC through the configurator context).
 *              - Turns a saved selection into ContractAsset__c records for a Contract Line (buildContractAssets).
 *                ContractAsset__c is a Master-Detail of ContractLineItem, so the rows can only be created once the
 *                contract line exists; nothing is written when the quote is saved.
 */
public with sharing class ImsAssetAssignmentService {

	public static final String SELECTION_FIELD = 'ImsAssetSelection__c';
	public static final String SOURCE_OPPORTUNITY = 'Opportunity';
	public static final String SOURCE_ACCOUNT = 'Account';
	public static final String DEFAULT_GROUP = 'Default Group';
	@TestVisible private static final Integer PREVIEW_PAGE_SIZE = 50;
	@TestVisible private static final Integer MAX_PREVIEW_OFFSET = 2000; // SOQL OFFSET limit
	@TestVisible private static final Integer MAX_ASSETS = 10000;
	private static final String LOGGER_TAG = 'ImsAssets';

	public class ImsAssetAssignmentException extends Exception {}

	/**
	 * @description The JSON stored on QuoteLineItem.ImsAssetSelection__c. Property names are shared with the LWC.
	 *              Covered set = (includeOpportunityAssets ? devices of groups : none) - removedAssetIds + addedAssetIds.
	 *              counts is for display only; it is never used to work out the covered set.
	 */
	public class Selection {
		public Integer version = 1;
		public Id opportunityId;
		public Boolean includeOpportunityAssets = true;
		public List<String> groups = new List<String>();
		public List<Id> removedAssetIds = new List<Id>();
		public List<Id> addedAssetIds = new List<Id>();
		public Map<String, Integer> counts;
	}

	public class InventoryGroup {
		@AuraEnabled public String name;
		@AuraEnabled public Integer deviceCount;
		@AuraEnabled public Datetime uploadedOn;
	}

	public class AssignmentContext {
		@AuraEnabled public Id quoteId;
		@AuraEnabled public Id opportunityId;
		@AuraEnabled public String opportunityName;
		@AuraEnabled public List<InventoryGroup> groups = new List<InventoryGroup>();
		@AuraEnabled public Integer opportunityDeviceCount = 0;
		@AuraEnabled public String savedSelection; // JSON; null when nothing is saved on the line
	}

	public class EligibleAssets {
		@AuraEnabled public List<EsServiceAssetSelectionController.AssetRow> rows =
			new List<EsServiceAssetSelectionController.AssetRow>();
		@AuraEnabled public Id quoteAccountId;
		@AuraEnabled public Integer relatedAccountCount = 0;
		@AuraEnabled public Boolean truncated = false;
		@AuraEnabled public Integer maxRows = MAX_ASSETS;
	}

	/**
	 * @description Reads the selection JSON. Unreadable JSON is logged and treated as "nothing selected", so a bad
	 *              value never blocks a save.
	 * @param raw Value of ImsAssetSelection__c
	 * @return The selection, or null when blank or unreadable
	 */
	public static Selection parse(String raw) {
		if (String.isBlank(raw)) {
			return null;
		}
		try {
			Selection s = (Selection) JSON.deserialize(raw, Selection.class);
			if (s == null) {
				return null;
			}
			if (s.groups == null) {
				s.groups = new List<String>();
			}
			if (s.removedAssetIds == null) {
				s.removedAssetIds = new List<Id>();
			}
			if (s.addedAssetIds == null) {
				s.addedAssetIds = new List<Id>();
			}
			if (s.includeOpportunityAssets == null) {
				s.includeOpportunityAssets = true;
			}
			return s;
		} catch (Exception e) { // JSONException, or a malformed Id (StringException)
			Logger.warn('ImsAssetAssignmentService.parse: unreadable ' + SELECTION_FIELD, e).addTag(LOGGER_TAG);
			return null;
		}
	}

	/**
	 * @description What the Covered Equipment card needs on load: the quote's opportunity, its inventory groups and
	 *              the selection saved on the line.
	 * @param quoteId Quote Id
	 * @param lineId Saved Quote Line Item Id, or null for an unsaved configurator line
	 * @return Assignment context
	 */
	public static AssignmentContext getContext(Id quoteId, Id lineId) {
		AssignmentContext ctx = new AssignmentContext();
		ctx.quoteId = quoteId;
		Quote quoteRecord = (Quote) new QuoteSelector()
			.selectFields(new List<String>{ 'Id', 'OpportunityId', 'Opportunity.Name' })
			.whereEquals('Id', quoteId)
			.first();
		if (quoteRecord == null) {
			throw new ImsAssetAssignmentException('Quote not found: ' + quoteId);
		}
		ctx.opportunityId = quoteRecord.OpportunityId;
		ctx.opportunityName = quoteRecord.Opportunity?.Name;
		if (quoteRecord.OpportunityId != null) {
			for (AggregateResult ar : OpportunityAssetSelector.selectGroupCounts(quoteRecord.OpportunityId)) {
				InventoryGroup g = new InventoryGroup();
				g.name = toDisplayGroup((String) ar.get('groupName'));
				g.deviceCount = (Integer) ar.get('deviceCount');
				g.uploadedOn = (Datetime) ar.get('uploadedOn');
				ctx.groups.add(g);
				ctx.opportunityDeviceCount += g.deviceCount;
			}
		}
		if (lineId != null) {
			QuoteLineItem line = (QuoteLineItem) new QuoteLineItemSelector()
				.selectField(SELECTION_FIELD)
				.whereEquals('Id', lineId)
				.first();
			ctx.savedSelection = line == null ? null : (String) line.get(SELECTION_FIELD);
		}
		return ctx;
	}

	/**
	 * @description One page (50 rows) of a group's devices for the preview panel.
	 * @param opportunityId Opportunity Id
	 * @param groupName Group name as shown (DEFAULT_GROUP for the blank group)
	 * @param offset Rows already loaded; capped at 2,000
	 * @return Asset rows
	 */
	public static List<EsServiceAssetSelectionController.AssetRow> getGroupPage(Id opportunityId, String groupName,
																				Integer offset) {
		Integer safeOffset = Math.min(Math.max(offset == null ? 0 : offset, 0), MAX_PREVIEW_OFFSET);
		List<Id> assetIds = OpportunityAssetSelector.selectGroupPageAssetIds(
			opportunityId, toDbGroup(groupName), PREVIEW_PAGE_SIZE, safeOffset);
		return EsServiceAssetSelectionController.loadRowsByIds(new Set<Id>(assetIds));
	}

	/**
	 * @description Picker data: the chosen groups' devices (Source = Opportunity, listed first) plus the assets on
	 *              the quote's account and its parent accounts (Source = Account), each asset once.
	 * @param quoteId Quote Id
	 * @param opportunityId Opportunity Id (the quote's)
	 * @param groups Group names as shown
	 * @return Rows, the number of related accounts and whether the list was cut off at MAX_ASSETS
	 */
	public static EligibleAssets getEligibleAssets(Id quoteId, Id opportunityId, List<String> groups) {
		EligibleAssets result = new EligibleAssets();
		Set<Id> groupAssetIds = OpportunityAssetSelector.selectAssetIdsByGroups(opportunityId, toDbGroups(groups));

		Set<Id> seen = new Set<Id>();
		for (EsServiceAssetSelectionController.AssetRow r : EsServiceAssetSelectionController.loadRowsByIds(groupAssetIds)) {
			r.source = SOURCE_OPPORTUNITY;
			result.rows.add(r);
			seen.add(r.id);
		}
		EsServiceAssetSelectionController.AssetList accountAssets =
			EsServiceAssetSelectionController.loadAccountAssets(quoteId);
		result.quoteAccountId = accountAssets.quoteAccountId;
		result.relatedAccountCount = accountAssets.relatedAccountCount;
		result.truncated = accountAssets.truncated;
		for (EsServiceAssetSelectionController.AssetRow r : accountAssets.rows) {
			if (seen.add(r.id)) {
				r.source = SOURCE_ACCOUNT;
				result.rows.add(r);
			}
		}
		if (result.rows.size() > MAX_ASSETS) {
			while (result.rows.size() > MAX_ASSETS) {
				result.rows.remove(result.rows.size() - 1);
			}
			result.truncated = true;
		}
		return result;
	}

	/**
	 * @description The assets a selection covers, with where each one came from.
	 * @param s Selection (may be null)
	 * @return Asset Id -> SOURCE_OPPORTUNITY or SOURCE_ACCOUNT
	 */
	public static Map<Id, String> coveredAssets(Selection s) {
		Map<Id, String> covered = new Map<Id, String>();
		if (s == null) {
			return covered;
		}
		if (s.includeOpportunityAssets == true && s.opportunityId != null && !s.groups.isEmpty()) {
			for (Id assetId : OpportunityAssetSelector.selectAssetIdsByGroups(s.opportunityId, toDbGroups(s.groups))) {
				covered.put(assetId, SOURCE_OPPORTUNITY);
			}
		}
		for (Id removed : s.removedAssetIds) {
			covered.remove(removed);
		}
		for (Id added : s.addedAssetIds) {
			if (!covered.containsKey(added)) {
				covered.put(added, SOURCE_ACCOUNT);
			}
		}
		return covered;
	}

	/**
	 * @description For the contract-creation step: the ContractAsset__c records each Contract Line needs, from the
	 *              Covered Equipment saved on its source quote line (a line whose card was never changed gets the
	 *              card's default: every inventory group on the quote's opportunity). Assets already linked to the contract line are
	 *              skipped, so calling it again does not create duplicates. The records are returned, not inserted:
	 *              the caller inserts them in its own transaction (chunk large lists, e.g. in a Queueable, to stay
	 *              within the 10,000 DML-row limit).
	 * @param contractLineIdByQuoteLineId Quote Line Item Id -> Contract Line Item Id created from it
	 * @return ContractAsset__c records to insert (ContractLineItem__c, Asset__c, StartDate__c, EndDate__c)
	 */
	public static List<ContractAsset__c> buildContractAssets(Map<Id, Id> contractLineIdByQuoteLineId) {
		List<ContractAsset__c> toInsert = new List<ContractAsset__c>();
		if (contractLineIdByQuoteLineId == null || contractLineIdByQuoteLineId.isEmpty()) {
			return toInsert;
		}
		// Must stay a List<Id> at runtime: binding a List<Object> to an Id column fails in SOQL.
		List<Object> quoteLineIds = new List<Id>(contractLineIdByQuoteLineId.keySet());
		List<Object> contractLineIds = new List<Id>(new Set<Id>(contractLineIdByQuoteLineId.values()));

		Map<Id, ContractLineItem> contractLines = new Map<Id, ContractLineItem>(
			(List<ContractLineItem>) new ContractLineItemSelector()
				.selectFields(new List<String>{ 'Id', 'StartDate', 'EndDate' })
				.whereField('Id', 'IN', contractLineIds)
				.execute()
		);
		Map<Id, Set<Id>> linkedAssetsByContractLine = new Map<Id, Set<Id>>();
		for (ContractAsset__c existing : (List<ContractAsset__c>) SoqlQueryBuilder.fromObject('ContractAsset__c')
			.selectFields(new List<String>{ 'ContractLineItem__c', 'Asset__c' })
			.whereField('ContractLineItem__c', 'IN', contractLineIds)
			.execute()) {
			if (!linkedAssetsByContractLine.containsKey(existing.ContractLineItem__c)) {
				linkedAssetsByContractLine.put(existing.ContractLineItem__c, new Set<Id>());
			}
			linkedAssetsByContractLine.get(existing.ContractLineItem__c).add(existing.Asset__c);
		}

		for (QuoteLineItem line : (List<QuoteLineItem>) new QuoteLineItemSelector()
			.selectFields(new List<String>{ 'Id', 'Quote.OpportunityId', SELECTION_FIELD })
			.whereField('Id', 'IN', quoteLineIds)
			.execute()) {
			Id contractLineId = contractLineIdByQuoteLineId.get(line.Id);
			ContractLineItem contractLine = contractLines.get(contractLineId);
			if (contractLine == null) {
				continue;
			}
			Set<Id> linked = linkedAssetsByContractLine.containsKey(contractLineId)
				? linkedAssetsByContractLine.get(contractLineId)
				: new Set<Id>();
			Selection s = parse((String) line.get(SELECTION_FIELD));
			if (s == null && String.isBlank((String) line.get(SELECTION_FIELD))) {
				// Card never changed: its default applies (toggle on, every group on the quote's opportunity)
				s = defaultSelection(line.Quote?.OpportunityId);
			}
			for (Id assetId : coveredAssets(s).keySet()) {
				if (linked.add(assetId)) {
					toInsert.add(new ContractAsset__c(
						ContractLineItem__c = contractLineId,
						Asset__c = assetId,
						StartDate__c = contractLine.StartDate,
						EndDate__c = contractLine.EndDate
					));
				}
			}
		}
		return toInsert;
	}

	/**
	 * @description The selection the Covered Equipment card shows before the rep changes anything: the opportunity's
	 *              devices included, every inventory group chosen, nothing removed or added.
	 * @param opportunityId The quote's opportunity
	 * @return Default selection, or null without an opportunity
	 */
	public static Selection defaultSelection(Id opportunityId) {
		if (opportunityId == null) {
			return null;
		}
		Selection s = new Selection();
		s.opportunityId = opportunityId;
		for (AggregateResult ar : OpportunityAssetSelector.selectGroupCounts(opportunityId)) {
			s.groups.add(toDisplayGroup((String) ar.get('groupName')));
		}
		return s;
	}

	// Group name as shown -> as stored (the blank group is shown as DEFAULT_GROUP)
	private static String toDbGroup(String groupName) {
		return String.isBlank(groupName) || groupName == DEFAULT_GROUP ? null : groupName;
	}

	private static String toDisplayGroup(String stored) {
		return String.isBlank(stored) ? DEFAULT_GROUP : stored;
	}

	private static Set<String> toDbGroups(List<String> groups) {
		Set<String> result = new Set<String>();
		if (groups == null) {
			return result;
		}
		for (String g : groups) {
			result.add(toDbGroup(g));
		}
		return result;
	}
}
