/**
 * @author Sagar Anand
 * @date 2026-11-06
 * @group Selectors
 * @description GW-2706: Selector for ServiceTerritory. Queries are built by the caller with SoqlQueryBuilder
 *              and run in user mode.
 */
public with sharing class ServiceTerritoriesSelector extends SoqlQueryBuilder {
	/**
	 * @description GW-2706: Binds this selector to ServiceTerritory.
	 * @example
	 * List<ServiceTerritory> territories = (List<ServiceTerritory>) new ServiceTerritoriesSelector()
	 *     .selectField('Id')
	 *     .whereIn('RegionNumber__c', regionNumbers)
	 *     .execute();
	 */
	public ServiceTerritoriesSelector() {
		this.objectName = 'ServiceTerritory';
	}
}