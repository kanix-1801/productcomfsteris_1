/**
 * @description Selector for ResiTestHistory__c (GW-5492 Receiving).
 *              Queries are built by ResiTestHistoriesService through SoqlQueryBuilder.
 */
public with sharing class ResiTestHistoriesSelector extends SoqlQueryBuilder {
    /**
     * @description Binds this selector to ResiTestHistory__c.
     */
    public ResiTestHistoriesSelector() {
        super('ResiTestHistory__c');
    }
}