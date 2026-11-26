/**
 * @author Vinay Soni
 * @date 2026/11/25
 * @group IMS Asset Assignment
 * @description GW-6456 - Tests for ImsAssetAssignmentService, ImsAssetAssignmentController and
 *              OpportunityAssetSelector. Uses ImsProductConfiguratorTestDataFactory.createQuoteWithLine() for the
 *              account / opportunity / quote / line (plus one asset on the account).
 */
@IsTest
private class ImsAssetAssignmentServiceTest {

	private static final String GROUP_MAIN = 'Main Campus';
	private static final String GROUP_EAST = 'East Wing';

	/**
	 * @description Read/edit on the new objects and fields for the running user (new fields deployed without a
	 *              profile have no FLS, and the selectors run in USER_MODE).
	 */
	private static void grantAccess() {
		System.runAs(new User(Id = UserInfo.getUserId())) {
			PermissionSet permissionSetRecord = new PermissionSet(
				Name = 'ImsAssetAssignmentTestAccess',
				Label = 'IMS Asset Assignment Test Access'
			);
			insert permissionSetRecord;
			List<ObjectPermissions> objectPermissionList = new List<ObjectPermissions>();
			for (String objectName : new List<String>{ 'OpportunityAsset__c', 'ContractAsset__c' }) {
				objectPermissionList.add(new ObjectPermissions(
					ParentId = permissionSetRecord.Id,
					SobjectType = objectName,
					PermissionsRead = true,
					PermissionsCreate = true,
					PermissionsEdit = true,
					PermissionsDelete = true
				));
			}
			insert objectPermissionList;
			List<FieldPermissions> fieldPermissionList = new List<FieldPermissions>();
			for (String field : new List<String>{
				'OpportunityAsset__c.Asset__c', 'OpportunityAsset__c.InventoryGroup__c',
				'OpportunityAsset__c.UniqueKey__c', 'QuoteLineItem.ImsAssetSelection__c',
				'ContractAsset__c.Asset__c', 'ContractAsset__c.StartDate__c', 'ContractAsset__c.EndDate__c'
			}) {
				fieldPermissionList.add(new FieldPermissions(
					ParentId = permissionSetRecord.Id,
					SobjectType = field.substringBefore('.'),
					Field = field,
					PermissionsRead = true,
					PermissionsEdit = true
				));
			}
			insert fieldPermissionList;
			insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = permissionSetRecord.Id);
		}
	}

	@TestSetup
	static void setup() {
		grantAccess();
		QuoteLineItem line = ImsProductConfiguratorTestDataFactory.createQuoteWithLine();
		Quote quoteRecord = [SELECT Id, OpportunityId, AccountId FROM Quote WHERE Id = :line.QuoteId];
		createInventoryGroup(quoteRecord.OpportunityId, quoteRecord.AccountId, GROUP_MAIN, 5);
		createInventoryGroup(quoteRecord.OpportunityId, quoteRecord.AccountId, GROUP_EAST, 2);
		createInventoryGroup(quoteRecord.OpportunityId, quoteRecord.AccountId, null, 1); // blank = Default Group
	}

	// ---------- helpers ----------

	/**
	 * @description The running user. Permissions assigned in setup only take effect inside System.runAs.
	 */
	private static User testUser() {
		return new User(Id = UserInfo.getUserId());
	}

	private static List<OpportunityAsset__c> createInventoryGroup(Id opportunityId, Id accountId, String groupName,
																  Integer n) {
		String label = groupName == null ? 'Default' : groupName.deleteWhitespace();
		List<Asset> assets = new List<Asset>();
		for (Integer i = 0; i < n; i++) {
			assets.add(new Asset(Name = 'IMS ' + label + ' ' + i, AccountId = accountId,
								 SerialNumber = 'SN-' + label + '-' + i, Quantity = 1));
		}
		insert assets;
		List<OpportunityAsset__c> rows = new List<OpportunityAsset__c>();
		for (Asset a : assets) {
			rows.add(new OpportunityAsset__c(
				Opportunity__c = opportunityId,
				Asset__c = a.Id,
				InventoryGroup__c = groupName,
				UniqueKey__c = String.valueOf(opportunityId).left(15) + String.valueOf(a.Id).left(15)
			));
		}
		Database.insert(rows, AccessLevel.SYSTEM_MODE); // test data: independent of FLS on the new fields
		return rows;
	}

	private static QuoteLineItem getLine() {
		return [SELECT Id, QuoteId, Quote.OpportunityId, Quote.AccountId, PricebookEntryId FROM QuoteLineItem LIMIT 1];
	}

	private static List<Id> groupAssetIds(String groupName) {
		List<Id> ids = new List<Id>();
		for (OpportunityAsset__c row : [
			SELECT Asset__c FROM OpportunityAsset__c WHERE InventoryGroup__c = :groupName WITH SYSTEM_MODE
			ORDER BY Asset__r.SerialNumber
		]) {
			ids.add(row.Asset__c);
		}
		return ids;
	}

	private static String selectionJson(Id opportunityId, Boolean include, List<String> groups, List<Id> removed,
										List<Id> added) {
		return JSON.serialize(new Map<String, Object>{
			'version' => 1,
			'opportunityId' => opportunityId,
			'includeOpportunityAssets' => include,
			'groups' => groups,
			'removedAssetIds' => removed,
			'addedAssetIds' => added
		});
	}

	// Service contract + one contract line for the quote line's product and the test term
	private static ContractLineItem createContractLine(QuoteLineItem line) {
		AutomationControl.setAllDisabled(true);
		ServiceContract contractRecord = new ServiceContract(
			Name = 'IMS Covered Equipment Test',
			AccountId = line.Quote.AccountId,
			Pricebook2Id = Test.getStandardPricebookId(),
			StartDate = ImsProductConfiguratorTestDataFactory.TERM_START,
			EndDate = ImsProductConfiguratorTestDataFactory.TERM_END
		);
		insert contractRecord;
		ContractLineItem contractLine = new ContractLineItem(
			ServiceContractId = contractRecord.Id,
			PricebookEntryId = line.PricebookEntryId,
			Quantity = 1,
			UnitPrice = 100,
			StartDate = ImsProductConfiguratorTestDataFactory.TERM_START,
			EndDate = ImsProductConfiguratorTestDataFactory.TERM_END
		);
		insert contractLine;
		AutomationControl.setAllDisabled(false);
		return contractLine;
	}

	private static Id accountOnlyAssetId() {
		// the asset createQuoteWithLine puts on the account (not in any group)
		return [SELECT Id FROM Asset WHERE SerialNumber = 'SN-MQ-0001' LIMIT 1].Id;
	}

	// ---------- parse ----------

	@IsTest
	static void parse_handlesBlankInvalidAndMissingLists() {
		System.runAs(testUser()) { // applies the permission set assigned in setup
			Test.startTest();
			ImsAssetAssignmentService.Selection blank = ImsAssetAssignmentService.parse('  ');
			ImsAssetAssignmentService.Selection bad = ImsAssetAssignmentService.parse('{bad');
			ImsAssetAssignmentService.Selection partial = ImsAssetAssignmentService.parse('{"version":1}');
			Test.stopTest();

			Assert.isNull(blank, 'Blank JSON is no selection');
			Assert.isNull(bad, 'Unreadable JSON is no selection');
			Assert.isNotNull(partial, 'Readable JSON is parsed');
			Assert.isTrue(partial.includeOpportunityAssets, 'Toggle defaults to on');
			Assert.areEqual(0, partial.groups.size(), 'Missing groups become an empty list');
			Assert.areEqual(0, partial.removedAssetIds.size(), 'Missing removed list becomes empty');
			Assert.areEqual(0, partial.addedAssetIds.size(), 'Missing added list becomes empty');
		}
	}

	// ---------- getContext ----------

	@IsTest
	static void getContext_returnsGroupsCountsAndSavedSelection() {
		System.runAs(testUser()) { // applies the permission set assigned in setup
			QuoteLineItem line = getLine();
			String saved = selectionJson(line.Quote.OpportunityId, true, new List<String>{ GROUP_MAIN }, new List<Id>(),
										 new List<Id>());
			line.put(ImsAssetAssignmentService.SELECTION_FIELD, saved);
			Database.update(line, AccessLevel.SYSTEM_MODE);

			Test.startTest();
			ImsAssetAssignmentService.AssignmentContext ctx = ImsAssetAssignmentController.getAssignmentContext(
				line.QuoteId, String.valueOf(line.Id));
			ImsAssetAssignmentService.AssignmentContext unsaved = ImsAssetAssignmentController.getAssignmentContext(
				line.QuoteId, 'ref_123');
			Test.stopTest();

			Assert.areEqual(line.Quote.OpportunityId, ctx.opportunityId, 'Opportunity comes from the quote');
			Assert.areEqual(3, ctx.groups.size(), 'Two named groups and the default group');
			Assert.areEqual(8, ctx.opportunityDeviceCount, '5 + 2 + 1 devices');
			Assert.areEqual(ImsAssetAssignmentService.DEFAULT_GROUP, ctx.groups[2].name, 'Blank group shown last as Default Group');
			Assert.areEqual(saved, ctx.savedSelection, 'Saved JSON returned for a saved line');
			Assert.isNull(unsaved.savedSelection, 'Nothing saved for an unsaved configurator line');
		}
	}

	@IsTest
	static void getContext_unknownQuote_throwsAuraException() {
		System.runAs(testUser()) { // applies the permission set assigned in setup
			Id missingQuoteId = '0Q0000000000000';
			Boolean thrown = false;
			Test.startTest();
			try {
				ImsAssetAssignmentController.getAssignmentContext(missingQuoteId, null);
			} catch (AuraHandledException e) {
				thrown = true;
				Assert.areEqual('Unable to load the covered equipment.', e.getMessage(), 'User message returned');
			}
			Test.stopTest();
			Assert.isTrue(thrown, 'An unknown quote raises an AuraHandledException');
		}
	}

	// ---------- getGroupPage ----------

	@IsTest
	static void getGroupAssets_pagesAndDefaultGroup() {
		System.runAs(testUser()) { // applies the permission set assigned in setup
			QuoteLineItem line = getLine();

			Test.startTest();
			List<EsServiceAssetSelectionController.AssetRow> mainRows =
				ImsAssetAssignmentController.getGroupAssets(line.Quote.OpportunityId, GROUP_MAIN, 0);
			List<EsServiceAssetSelectionController.AssetRow> pastEnd =
				ImsAssetAssignmentController.getGroupAssets(line.Quote.OpportunityId, GROUP_MAIN, 5);
			List<EsServiceAssetSelectionController.AssetRow> defaultRows = ImsAssetAssignmentController.getGroupAssets(
				line.Quote.OpportunityId, ImsAssetAssignmentService.DEFAULT_GROUP, null);
			Test.stopTest();

			Assert.areEqual(5, mainRows.size(), 'All devices of the group on the first page');
			Assert.areEqual(0, pastEnd.size(), 'Nothing past the last row');
			Assert.areEqual(1, defaultRows.size(), 'Default Group reads the blank group');
		}
	}

	// ---------- getEligibleAssets ----------

	@IsTest
	static void getEligibleAssets_groupDevicesFirstWithoutDuplicates() {
		System.runAs(testUser()) { // applies the permission set assigned in setup
			QuoteLineItem line = getLine();

			Test.startTest();
			ImsAssetAssignmentService.EligibleAssets result = ImsAssetAssignmentController.getEligibleAssets(
				line.QuoteId, line.Quote.OpportunityId, new List<String>{ GROUP_MAIN });
			Test.stopTest();

			// group assets are also on the quote's account: 5 (Opportunity) + 2 East + 1 Default + 1 account-only
			Assert.areEqual(9, result.rows.size(), 'Each asset once');
			for (Integer i = 0; i < 5; i++) {
				Assert.areEqual(ImsAssetAssignmentService.SOURCE_OPPORTUNITY, result.rows[i].source, 'Group devices first');
			}
			for (Integer i = 5; i < result.rows.size(); i++) {
				Assert.areEqual(ImsAssetAssignmentService.SOURCE_ACCOUNT, result.rows[i].source, 'Then account assets');
			}
			Assert.isFalse(result.truncated, 'Small list is not cut off');
			Assert.areEqual(line.Quote.AccountId, result.quoteAccountId, 'Quote account returned');
		}
	}

	// ---------- coveredAssets ----------

	@IsTest
	static void coveredAssets_appliesToggleRemovedAndAdded() {
		System.runAs(testUser()) { // applies the permission set assigned in setup
			QuoteLineItem line = getLine();
			List<Id> mainIds = groupAssetIds(GROUP_MAIN);
			Id extra = accountOnlyAssetId();

			Test.startTest();
			Map<Id, String> includeOn = ImsAssetAssignmentService.coveredAssets(ImsAssetAssignmentService.parse(selectionJson(
				line.Quote.OpportunityId, true, new List<String>{ GROUP_MAIN }, new List<Id>{ mainIds[0] }, new List<Id>{ extra }
			)));
			Map<Id, String> includeOff = ImsAssetAssignmentService.coveredAssets(ImsAssetAssignmentService.parse(selectionJson(
				line.Quote.OpportunityId, false, new List<String>{ GROUP_MAIN }, new List<Id>(), new List<Id>{ extra }
			)));
			Map<Id, String> none = ImsAssetAssignmentService.coveredAssets(null);
			Test.stopTest();

			Assert.areEqual(5, includeOn.size(), '5 group devices - 1 removed + 1 added');
			Assert.isFalse(includeOn.containsKey(mainIds[0]), 'Removed device is not covered');
			Assert.areEqual(ImsAssetAssignmentService.SOURCE_ACCOUNT, includeOn.get(extra), 'Added asset has Source Account');
			Assert.areEqual(ImsAssetAssignmentService.SOURCE_OPPORTUNITY, includeOn.get(mainIds[1]), 'Group device has Source Opportunity');
			Assert.areEqual(1, includeOff.size(), 'Toggle off covers only the added assets');
			Assert.isTrue(none.isEmpty(), 'No selection covers nothing');
		}
	}

	// ---------- buildContractAssets ----------

	@IsTest
	static void buildContractAssets_createsRowsOnceForTheContractLine() {
		System.runAs(testUser()) { // applies the permission set assigned in setup
			QuoteLineItem line = getLine();
			List<Id> eastIds = groupAssetIds(GROUP_EAST);
			Id extra = accountOnlyAssetId();
			line.put(ImsAssetAssignmentService.SELECTION_FIELD, selectionJson(
				line.Quote.OpportunityId, true, new List<String>{ GROUP_EAST }, new List<Id>(), new List<Id>{ extra }));
			Database.update(line, AccessLevel.SYSTEM_MODE);
			ContractLineItem contractLine = createContractLine(line);

			Map<Id, Id> contractLineByQuoteLine = new Map<Id, Id>{ line.Id => contractLine.Id };

			Test.startTest();
			List<ContractAsset__c> first = ImsAssetAssignmentService.buildContractAssets(contractLineByQuoteLine);
			Database.insert(first, AccessLevel.SYSTEM_MODE);
			List<ContractAsset__c> second = ImsAssetAssignmentService.buildContractAssets(contractLineByQuoteLine);
			Test.stopTest();

			Assert.areEqual(3, first.size(), '2 East Wing devices + 1 added asset');
			Set<Id> assetIds = new Set<Id>();
			for (ContractAsset__c row : first) {
				assetIds.add(row.Asset__c);
				Assert.areEqual(contractLine.Id, row.ContractLineItem__c, 'Linked to the contract line');
				Assert.areEqual(ImsProductConfiguratorTestDataFactory.TERM_START, row.StartDate__c, 'Start date from the contract line');
				Assert.areEqual(ImsProductConfiguratorTestDataFactory.TERM_END, row.EndDate__c, 'End date from the contract line');
			}
			Assert.isTrue(assetIds.containsAll(eastIds), 'Every East Wing device is covered');
			Assert.isTrue(assetIds.contains(extra), 'The added asset is covered');
			Assert.areEqual(0, second.size(), 'Assets already linked are not built again');
		}
	}

	@IsTest
	static void buildContractAssets_blankSelection_usesCardDefault() {
		System.runAs(testUser()) { // applies the permission set assigned in setup
			QuoteLineItem line = getLine(); // ImsAssetSelection__c never written
			ContractLineItem contractLine = createContractLine(line);

			Test.startTest();
			List<ContractAsset__c> rows = ImsAssetAssignmentService.buildContractAssets(
				new Map<Id, Id>{ line.Id => contractLine.Id });
			Test.stopTest();

			Assert.areEqual(8, rows.size(), 'Every device of every group (5 + 2 + 1), as the card shows by default');
		}
	}

	@IsTest
	static void buildContractAssets_unreadableSelection_coversNothing() {
		System.runAs(testUser()) { // applies the permission set assigned in setup
			QuoteLineItem line = getLine();
			line.put(ImsAssetAssignmentService.SELECTION_FIELD, '{bad');
			Database.update(line, AccessLevel.SYSTEM_MODE);
			ContractLineItem contractLine = createContractLine(line);

			Test.startTest();
			List<ContractAsset__c> rows = ImsAssetAssignmentService.buildContractAssets(
				new Map<Id, Id>{ line.Id => contractLine.Id });
			Test.stopTest();

			Assert.areEqual(0, rows.size(), 'Unreadable JSON is logged and covers nothing (no guess)');
		}
	}

	@IsTest
	static void buildContractAssets_emptyInput_returnsNothing() {
		System.runAs(testUser()) { // applies the permission set assigned in setup
			Test.startTest();
			List<ContractAsset__c> rows = ImsAssetAssignmentService.buildContractAssets(new Map<Id, Id>());
			List<ContractAsset__c> nullRows = ImsAssetAssignmentService.buildContractAssets(null);
			Test.stopTest();
			Assert.areEqual(0, rows.size(), 'Empty map builds nothing');
			Assert.areEqual(0, nullRows.size(), 'Null map builds nothing');
		}
	}

	// ---------- controller helpers ----------

	@IsTest
	static void toQuoteLineId_rejectsTemporaryAndMalformedIds() {
		System.runAs(testUser()) { // applies the permission set assigned in setup
			Test.startTest();
			Id fromRef = ImsAssetAssignmentController.toQuoteLineId('ref_abc');
			Id fromBlank = ImsAssetAssignmentController.toQuoteLineId('');
			Id fromBad = ImsAssetAssignmentController.toQuoteLineId('0QLnotAnId');
			Test.stopTest();
			Assert.isNull(fromRef, 'Temporary configurator Id');
			Assert.isNull(fromBlank, 'Blank Id');
			Assert.isNull(fromBad, 'Malformed Id');
		}
	}
}