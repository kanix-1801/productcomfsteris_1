/**
 * @description Tests for BinTagPrintQuantitiesSelector and BinTagPrintQuantitiesService (GW-3595 / GW-4637).
 */
@IsTest
private class BinTagPrintQuantitiesServiceTest {
	private static final String PRODUCT_LINE = 'INSTRUMENT';
	private static final String RUNNER_LAST_NAME = 'BinTagQtyRunner';

	@TestSetup
	static void setupData() {
		User runner = createUserWithBinTagAccess();
		System.runAs(runner) {
			Schema.Location repairCenter = new Schema.Location(
				Name = 'Bin Tag Qty Repair Center',
				LocationType = 'Repair Center'
			);
			insert repairCenter;

			insert new BinTagPrintQuantity__c(
				RepairCenter__c = repairCenter.Id,
				Country__c = 'United States',
				Product_Line__c = PRODUCT_LINE,
				PrintQuantity__c = 3
			);
		}
	}

	private static User createUserWithBinTagAccess() {
		Profile standardProfile = [
			SELECT Id
			FROM Profile
			WHERE Name = 'Standard User'
			LIMIT 1
		];
		String uniqueKey = 'btq' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
		User runner = new User(
			Alias = uniqueKey.left(8),
			Email = uniqueKey + '@example.com',
			EmailEncodingKey = 'UTF-8',
			LastName = RUNNER_LAST_NAME,
			LanguageLocaleKey = 'en_US',
			LocaleSidKey = 'en_US',
			ProfileId = standardProfile.Id,
			TimeZoneSidKey = 'America/Los_Angeles',
			Username = uniqueKey + '@example.com'
		);
		insert runner;

		PermissionSet printerAccess = [
			SELECT Id
			FROM PermissionSet
			WHERE Name = 'ManageRepairCenterOperations'
			LIMIT 1
		];
		insert new PermissionSetAssignment(
			AssigneeId = runner.Id,
			PermissionSetId = printerAccess.Id
		);
		return runner;
	}

	private static User binTagRunner() {
		return [SELECT Id FROM User WHERE LastName = :RUNNER_LAST_NAME LIMIT 1];
	}

	@IsTest
	static void testSelectorBuilderReturnsMappingByRepairCenterAndProductLine() {
		System.runAs(binTagRunner()) {
			Schema.Location repairCenter = [
				SELECT Id
				FROM Location
				WHERE Name = 'Bin Tag Qty Repair Center'
				LIMIT 1
			];

			Test.startTest();
			List<BinTagPrintQuantity__c> rows = (List<BinTagPrintQuantity__c>) new BinTagPrintQuantitiesSelector()
				.selectFields(
					new List<String>{ 'Id', 'PrintQuantity__c', 'RepairCenter__c', 'Product_Line__c' }
				)
				.whereEquals('RepairCenter__c', repairCenter.Id)
				.whereEquals('Product_Line__c', PRODUCT_LINE)
				.orderByDesc('LastModifiedDate')
				.limitTo(1)
				.execute();
			Test.stopTest();

			Assert.areEqual(1, rows.size(), 'Should return the mapping without using Country');
			Assert.areEqual(3, Integer.valueOf(rows[0].PrintQuantity__c));
		}
	}

	@IsTest
	static void testServiceReturnsQuantityWithoutCountry() {
		System.runAs(binTagRunner()) {
			Schema.Location repairCenter = [
				SELECT Id
				FROM Location
				WHERE Name = 'Bin Tag Qty Repair Center'
				LIMIT 1
			];

			Test.startTest();
			Integer copies = BinTagPrintQuantitiesService.getPrintQuantity(
				repairCenter.Id,
				PRODUCT_LINE
			);
			Test.stopTest();

			Assert.areEqual(3, copies);
		}
	}

	@IsTest
	static void testServiceDefaultsNullPrintQuantityToOne() {
		System.runAs(binTagRunner()) {
			Schema.Location repairCenter = [
				SELECT Id
				FROM Location
				WHERE Name = 'Bin Tag Qty Repair Center'
				LIMIT 1
			];
			BinTagPrintQuantity__c mapping = [
				SELECT Id
				FROM BinTagPrintQuantity__c
				WHERE RepairCenter__c = :repairCenter.Id
				LIMIT 1
			];
			mapping.PrintQuantity__c = null;
			update mapping;

			Test.startTest();
			Integer copies = BinTagPrintQuantitiesService.getPrintQuantity(
				repairCenter.Id,
				PRODUCT_LINE
			);
			Test.stopTest();

			Assert.areEqual(BinTagPrintQuantitiesService.DEFAULT_PRINT_QUANTITY, copies);
		}
	}

	@IsTest
	static void testServiceUsesTestOverride() {
		BinTagPrintQuantitiesService.testPrintQuantity = 7;

		Test.startTest();
		Integer copies = BinTagPrintQuantitiesService.getPrintQuantity(
			UserInfo.getUserId(),
			PRODUCT_LINE
		);
		Test.stopTest();

		Assert.areEqual(7, copies);
		BinTagPrintQuantitiesService.testPrintQuantity = null;
	}

	@IsTest
	static void testServiceDefaultsToOneWhenInputsMissing() {
		Test.startTest();
		Integer copies = BinTagPrintQuantitiesService.getPrintQuantity(null, PRODUCT_LINE);
		Integer blankProductLine = BinTagPrintQuantitiesService.getPrintQuantity(
			UserInfo.getUserId(),
			'  '
		);
		Test.stopTest();

		Assert.areEqual(BinTagPrintQuantitiesService.DEFAULT_PRINT_QUANTITY, copies);
		Assert.areEqual(BinTagPrintQuantitiesService.DEFAULT_PRINT_QUANTITY, blankProductLine);
	}

	@IsTest
	static void testServiceDefaultsToOneWhenMappingMissing() {
		System.runAs(binTagRunner()) {
			Schema.Location repairCenter = [
				SELECT Id
				FROM Location
				WHERE Name = 'Bin Tag Qty Repair Center'
				LIMIT 1
			];

			Test.startTest();
			Integer copies = BinTagPrintQuantitiesService.getPrintQuantity(
				repairCenter.Id,
				'UNKNOWN LINE'
			);
			Test.stopTest();

			Assert.areEqual(BinTagPrintQuantitiesService.DEFAULT_PRINT_QUANTITY, copies);
		}
	}

	@IsTest
	static void testSelectorConstructor() {
		Test.startTest();
		BinTagPrintQuantitiesSelector selector = new BinTagPrintQuantitiesSelector();
		Test.stopTest();

		Assert.isNotNull(selector);
	}
}