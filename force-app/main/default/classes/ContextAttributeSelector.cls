/**
 * @description Selector class for the ContextAttribute SObject (Revenue Cloud context definitions).
 *              Centralizes all SOQL queries for context attributes. Security checks are applied by
 *              SoqlQueryBuilder / DynamicSoqlQuery.
 */
public with sharing class ContextAttributeSelector extends SoqlQueryBuilder {

    public ContextAttributeSelector() {
        this.objectName = 'ContextAttribute';
    }

    /**
     * @description Retrieves context attributes by Title (the mapped field API name, e.g. Asset__c).
     * @param titles Context attribute titles to match
     * @return List of ContextAttribute records with Id and Title, ordered by Title
     */
    public static List<ContextAttribute> selectByTitles(List<String> titles) {
        if (titles == null || titles.isEmpty()) {
            return new List<ContextAttribute>();
        }

        return (List<ContextAttribute>) SoqlQueryBuilder.fromObject('ContextAttribute')
                                                        .selectFields(new List<String>{ 'Id', 'Title' })
                                                        .whereField('Title', 'IN', titles)
                                                        .orderBy('Title')
                                                        .execute();
    }
}