/**
 * @author Sagar Anand
 * @date 2026-11-06
 * @group Selectors
 * @description GW-2706: Selector for ServiceTerritory. Queries run through SoqlQueryBuilder in user mode.
 */
public with sharing class ServiceTerritoriesSelector extends SoqlQueryBuilder {
	/**
	 * @description GW-2706: Binds this selector to ServiceTerritory.
	 * @example
	 * List<ServiceTerritory> territories = (List<ServiceTerritory>) new ServiceTerritoriesSelector()
	 *     .selectField('Id')
	 *     .whereEquals('RegionNumber__c', regionNumber)
	 *     .execute();
	 */
	public ServiceTerritoriesSelector() {
		this.objectName = 'ServiceTerritory';
	}

	/**
	 * @description GW-2706: Service Territories whose Region Number is in the given set.
	 * @param regionNumbers Region Numbers (district or zone numbers).
	 * @param fields Fields to return.
	 * @return Matching territories, or an empty list when no Region Number is given.
	 * @example
	 * ServiceTerritoriesSelector.selectByRegionNumbers(new Set<String>{ 'H41400' }, new List<String>{ 'Id', 'Name' });
	 */
	public static List<ServiceTerritory> selectByRegionNumbers(Set<String> regionNumbers, List<String> fields) {
		if (regionNumbers == null || regionNumbers.isEmpty()) {
			return new List<ServiceTerritory>();
		}
		return (List<ServiceTerritory>) new ServiceTerritoriesSelector()
			.selectFields(fields)
			.whereIn('RegionNumber__c', new List<String>(regionNumbers))
			.execute();
	}
}