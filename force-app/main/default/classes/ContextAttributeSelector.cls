/**
 * @description Selector class for the ContextAttribute SObject (Revenue Cloud context definitions).
 *              Callers build their queries with the inherited SoqlQueryBuilder methods. Security checks
 *              are applied by SoqlQueryBuilder / DynamicSoqlQuery.
 */
public with sharing class ContextAttributeSelector extends SoqlQueryBuilder {

    public ContextAttributeSelector() {
        this.objectName = 'ContextAttribute';
    }
}