/**
 * @description GW-3458 - Selector for PricingModifier__c. Callers add fields, filters, and limits.
 */
public with sharing class PricingModifiersSelector extends SoqlQueryBuilder {
	/**
	 * @description Creates a selector for Pricing Modifier.
	 */
	public PricingModifiersSelector() {
		this.objectName = 'PricingModifier__c';
	}
}