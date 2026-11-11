/**
 * @description GW-3458 - Selector for PricingModifier__c.
 */
public with sharing class PricingModifiersSelector extends SoqlQueryBuilder {
    public PricingModifiersSelector() {
        this.objectName = 'PricingModifier__c';
    }

    /**
     * @description Active pricing modifiers whose level is one of the requested values.
     * @param levels Modifier Level values to include
     * @return Active modifiers ordered by name
     */
    public static List<PricingModifier__c> selectActiveByLevels(List<String> levels) {
        if (levels == null || levels.isEmpty()) {
            return new List<PricingModifier__c>();
        }
        return (List<PricingModifier__c>) new PricingModifiersSelector()
            .selectFields(new List<String>{ 'Id', 'Name', 'ModifierLevel__c', 'ModifierValue__c', 'Active__c' })
            .whereEquals('Active__c', true)
            .whereField('ModifierLevel__c', 'IN', levels)
            .orderBy('Name')
            .limitTo(200)
            .execute();
    }

    /**
     * @description Loads one pricing modifier for a save.
     * @param pricingModifierId Pricing Modifier Id
     * @return Matching modifier, or an empty list
     */
    public static List<PricingModifier__c> selectById(Id pricingModifierId) {
        if (pricingModifierId == null) {
            return new List<PricingModifier__c>();
        }
        return (List<PricingModifier__c>) new PricingModifiersSelector()
            .selectFields(new List<String>{ 'Id', 'Name', 'ModifierLevel__c', 'ModifierValue__c', 'Active__c' })
            .whereEquals('Id', pricingModifierId)
            .limitTo(1)
            .execute();
    }
}