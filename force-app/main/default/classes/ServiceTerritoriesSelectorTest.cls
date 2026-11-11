/**
 * @author Sagar Anand
 * @date 2026-11-06
 * @group Selectors
 * @description GW-2706: Tests for ServiceTerritoriesSelector.
 */
@IsTest
private class ServiceTerritoriesSelectorTest {
	private static final String REGION_NUMBER = 'ST2706-1';

	@TestSetup
	static void setupData() {
		// SETUP
		OperatingHours hours = (OperatingHours) new adb_OperatingHours()
			.name('GW2706 Selector Hours')
			.timeZone('America/New_York')
			.persist();
		Database.insert(
			new ServiceTerritory(
				Name = 'GW2706 Selector Territory',
				RegionNumber__c = REGION_NUMBER,
				TerritoryType__c = 'Van Region',
				OperatingHoursId = hours.Id,
				IsActive = true
			),
			AccessLevel.SYSTEM_MODE
		);
	}

	@IsTest
	static void testSelectByRegionNumbersReturnsMatchingTerritories() {
		// GIVEN
		Set<String> regionNumberSet = new Set<String>{ REGION_NUMBER, 'NO-SUCH-NUMBER' };

		// WHEN
		Test.startTest();
		List<ServiceTerritory> territoryList = ServiceTerritoriesSelector.selectByRegionNumbers(
			regionNumberSet,
			new List<String>{ 'Id', 'RegionNumber__c', 'TerritoryType__c' }
		);
		Test.stopTest();

		// THEN
		Assert.areEqual(1, territoryList.size(), 'Only the existing Region Number should match.');
		Assert.areEqual(REGION_NUMBER, territoryList[0].RegionNumber__c, 'Unexpected territory.');
		Assert.areEqual('Van Region', territoryList[0].TerritoryType__c, 'The requested fields should be returned.');
	}

	@IsTest
	static void testSelectByRegionNumbersReturnsEmptyListWithoutNumbers() {
		// GIVEN
		List<String> fieldList = new List<String>{ 'Id' };

		// WHEN
		Test.startTest();
		Set<String> emptySet = new Set<String>();
		List<ServiceTerritory> fromEmptySet = ServiceTerritoriesSelector.selectByRegionNumbers(emptySet, fieldList);
		List<ServiceTerritory> fromNull = ServiceTerritoriesSelector.selectByRegionNumbers(null, fieldList);
		Test.stopTest();

		// THEN
		Assert.isTrue(fromEmptySet.isEmpty(), 'An empty set should return no territories.');
		Assert.isTrue(fromNull.isEmpty(), 'A null set should return no territories.');
	}
}