/**
 * Domain Builder for CaseRoutingRule__c
 * Follows a4d-apex-domainbuilder-rules:
 * - Class name adb_CaseRoutingRule_c (custom object __c -> _c), extends adb_DomainBuilder
 * - Constructor calls super(CaseRoutingRule__c.SObjectType) and sets sensible defaults
 * - Fluent setters return adb_CaseRoutingRule_c and use set(SObjectField, Object)
 * - Relationship helpers use setParent(SObjectField, adb_DomainBuilder)
 *
 * GW-1279 - Defines keyword-based routing and labeling rules for incoming Cases.
 * Each record represents a rule used to evaluate Case fields such as Subject, Description,
 * Supplied Email, and Origin, and to stamp target Case values when a match is found
 */
@IsTest
public with sharing class adb_CaseRoutingRule_c extends adb_DomainBuilder {

    /**
     * Constructs a CaseRoutingRule__c builder with sensible defaults.
     * Defaults chosen to create a valid, commonly-accepted rule:
     * - Name: unique rule name with timestamp
     * - IsActive__c: true (most rules are active by default)
     * - Priority__c: 100 (middle priority)
     */
    public adb_CaseRoutingRule_c() {
        super(CaseRoutingRule__c.SObjectType);
        // Provide sensible defaults
        set(CaseRoutingRule__c.Name, 'Rule - ' + Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''));
        set(CaseRoutingRule__c.IsActive__c, true);
        set(CaseRoutingRule__c.Priority__c, 100);
    }

    // ---------------------------
    // Standard Field Setters
    // ---------------------------

    /**
     * Set the rule name
     */
    public adb_CaseRoutingRule_c name(String value) {
        return (adb_CaseRoutingRule_c) set(CaseRoutingRule__c.Name, value);
    }

    /**
     * Set whether the rule is active (IsActive__c field)
     */
    public adb_CaseRoutingRule_c isActive(Boolean value) {
        return (adb_CaseRoutingRule_c) set(CaseRoutingRule__c.IsActive__c, value);
    }

    /**
     * Set the priority for rule evaluation order (lower numbers evaluated first)
     */
    public adb_CaseRoutingRule_c priority(Decimal value) {
        return (adb_CaseRoutingRule_c) set(CaseRoutingRule__c.Priority__c, value);
    }

    /**
     * Set the Case Assignment picklist value
     */
    public adb_CaseRoutingRule_c caseAssignment(String value) {
        return (adb_CaseRoutingRule_c) set(CaseRoutingRule__c.CaseAssignment__c, value);
    }

    /**
     * Set the Category Value
     */
    public adb_CaseRoutingRule_c categoryValue(String value) {
        return (adb_CaseRoutingRule_c) set(CaseRoutingRule__c.CategoryValue__c, value);
    }

    /**
     * Set the Close Code
     */
    public adb_CaseRoutingRule_c closeCode(String value) {
        return (adb_CaseRoutingRule_c) set(CaseRoutingRule__c.CloseCode__c, value);
    }

    /**
     * Set the Description Search String for pattern matching
     */
    public adb_CaseRoutingRule_c descriptionSearchString(String value) {
        return (adb_CaseRoutingRule_c) set(CaseRoutingRule__c.DescriptionSearchString__c, value);
    }

    /**
     * Set whether the rule is system generated
     */
    public adb_CaseRoutingRule_c isSystemGenerated(Boolean value) {
        return (adb_CaseRoutingRule_c) set(CaseRoutingRule__c.IsSystemGenerated__c, value);
    }

    /**
     * Set the Label Value
     */
    public adb_CaseRoutingRule_c labelValue(String value) {
        return (adb_CaseRoutingRule_c) set(CaseRoutingRule__c.LabelValue__c, value);
    }

    /**
     * Set the Sub Category Value
     */
    public adb_CaseRoutingRule_c subCategoryValue(String value) {
        return (adb_CaseRoutingRule_c) set(CaseRoutingRule__c.SubCategoryValue__c, value);
    }

    /**
     * Set the Subject Search String for pattern matching
     */
    public adb_CaseRoutingRule_c subjectSearchString(String value) {
        return (adb_CaseRoutingRule_c) set(CaseRoutingRule__c.SubjectSearchString__c, value);
    }

    /**
     * Set the Supplied Email From Address for matching
     */
    public adb_CaseRoutingRule_c suppliedEmailFromAddress(String value) {
        return (adb_CaseRoutingRule_c) set(CaseRoutingRule__c.SuppliedEmailFromAddress__c, value);
    }
}