/**
 * @description Selector for ContractLineItem. Sets the object once so callers only
 *              add fields, filters, ordering, and limits.
 * @author STERIS
 */
public with sharing class ContractLineItemSelector extends SoqlQueryBuilder {

    /**
     * @description Creates a selector for ContractLineItem.
     */
    public ContractLineItemSelector() {
        this.objectName = 'ContractLineItem';
    }
}