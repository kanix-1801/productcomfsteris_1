/**
 * @description Selector class for CaseRoutingRule__c object - handles all SOQL queries
 * @author Agentforce
 * @date 2026-04-27
 * @group Selectors
 */
public with sharing class CaseRoutingRulesSelector {
    /**
     * @description Base fields used across all queries for consistency
     */
    private static final String BASE_FIELDS = 'Id, Name, IsActive__c, Priority__c, CaseAssignment__c, CategoryValue__c, SubCategoryValue__c, CloseCode__c, LabelValue__c, IsSystemGenerated__c, SubjectSearchString__c, DescriptionSearchString__c, SuppliedEmailFromAddress__c, CreatedDate, CreatedById, LastModifiedDate, LastModifiedById';

    /**
     * @description Selects CaseRoutingRule__c records by Id
     * @param ids Set of record Ids to query
     * @return List of CaseRoutingRule__c records
     */
    public static List<CaseRoutingRule__c> selectById(Set<Id> ids) {
        // Guard against null or empty input
        if (ids == null || ids.isEmpty()) {
            return new List<CaseRoutingRule__c>();
        }

        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM CaseRoutingRule__c' +
            ' WHERE Id IN :ids' +
            ' WITH SECURITY_ENFORCED' +
            ' ORDER BY Priority__c ASC NULLS LAST, Name ASC'
        );
    }

    /**
     * @description Selects all active CaseRoutingRule__c records ordered by priority
     * @return List of active CaseRoutingRule__c records
     */
    public static List<CaseRoutingRule__c> selectActiveRules() {
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM CaseRoutingRule__c' +
            ' WHERE IsActive__c = true' +
            ' WITH SECURITY_ENFORCED' +
            ' ORDER BY Priority__c ASC NULLS LAST, Name ASC'
        );
    }

    /**
     * @description Selects CaseRoutingRule__c records by Active status
     * @param isActive Boolean indicating whether to select active or inactive rules
     * @return List of CaseRoutingRule__c records matching the active status
     */
    public static List<CaseRoutingRule__c> selectByActiveStatus(Boolean isActive) {
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM CaseRoutingRule__c' +
            ' WHERE IsActive__c = :isActive' +
            ' WITH SECURITY_ENFORCED' +
            ' ORDER BY Priority__c ASC NULLS LAST, Name ASC'
        );
    }

    /**
     * @description GW-1279 - Selects active CaseRoutingRule__c records whose Case Assignment (CaseAssignment__c) is in
     *              the given set. CaseAssignment__c stores the Case Origin value the rule applies to.
     * @param caseAssignments Distinct Case Origin / Case Assignment API values
     * @return Active matching rules ordered by priority
     */
    public static List<CaseRoutingRule__c> selectActiveCRRsByAssignment(Set<String> caseAssignments) {
        if (caseAssignments == null || caseAssignments.isEmpty()) {
            return new List<CaseRoutingRule__c>();
        }

        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM CaseRoutingRule__c' +
            ' WHERE IsActive__c = true' +
            ' AND CaseAssignment__c IN :caseAssignments' +
            ' WITH SECURITY_ENFORCED' +
            ' ORDER BY Priority__c ASC NULLS LAST, Name ASC'
        );
    }

    /**
     * @description Selects all CaseRoutingRule__c records with specific ordering
     * @return List of all CaseRoutingRule__c records
     */
    public static List<CaseRoutingRule__c> selectAll() {
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM CaseRoutingRule__c' +
            ' WITH SECURITY_ENFORCED' +
            ' ORDER BY Priority__c ASC NULLS LAST, Name ASC' +
            ' LIMIT 2000'
        );
    }
}