/**
 * @description Selector for BinTagPrintQuantity__c (GW-3595 / GW-4637).
 *              Queries are built by BinTagPrintQuantitiesService through SoqlQueryBuilder.
 *              This class only binds the object name.
 * @group GW-4637
 */
public with sharing class BinTagPrintQuantitiesSelector extends SoqlQueryBuilder {
    /**
     * @description Creates a selector for BinTagPrintQuantity__c.
     */
    public BinTagPrintQuantitiesSelector() {
        super('BinTagPrintQuantity__c');
    }
}