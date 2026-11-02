/**
 * @description Selector for WorkstationPrinter__c (GW-4751). Queries are built by callers
 *              through SoqlQueryBuilder; this class only binds the object name.
 * @group GW-4751
 */
public with sharing class WorkstationPrintersSelector extends SoqlQueryBuilder {
    /**
     * @description GW-4751 - Creates a selector for WorkstationPrinter__c.
     */
    public WorkstationPrintersSelector() {
        super('WorkstationPrinter__c');
    }
}