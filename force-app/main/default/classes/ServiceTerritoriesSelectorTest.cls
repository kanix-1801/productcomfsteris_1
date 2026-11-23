/**
 * @author Sagar Anand
 * @date 2026-11-06
 * @group Selectors
 * @description GW-2706: Tests for ServiceTerritoriesSelector.
 */
@IsTest
private class ServiceTerritoriesSelectorTest {
	private static final String REGION_NUMBER = 'ST2706-1';

	@IsTest
	static void testSelectorQueriesServiceTerritories() {
		// GIVEN
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

		// WHEN
		Test.startTest();
		List<ServiceTerritory> territoryList = (List<ServiceTerritory>) new ServiceTerritoriesSelector()
			.selectFields(new List<String>{ 'Id', 'TerritoryType__c' })
			.whereIn('RegionNumber__c', new List<String>{ REGION_NUMBER, 'NO-SUCH-NUMBER' })
			.execute();
		Test.stopTest();

		// THEN
		Assert.areEqual(1, territoryList.size(), 'Only the existing Region Number should match.');
		Assert.areEqual('Van Region', territoryList[0].TerritoryType__c, 'The requested fields should be returned.');
	}
}