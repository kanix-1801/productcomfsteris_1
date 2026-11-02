/**
 * @description Domain class for CaseRoutingRule__c - handles object-specific business logic and validation
 * @author Agentforce
 * @date 2026-04-27
 * @group Domain
 */
public with sharing class CaseRoutingRules {
    private final List<CaseRoutingRule__c> records;

    /**
     * @description Constructor accepting a list of CaseRoutingRule__c records
     * @param records List of CaseRoutingRule__c records to be managed by this domain instance
     */
    public CaseRoutingRules(List<CaseRoutingRule__c> records) {
        this.records = records;
    }

    /**
     * @description Gets the records managed by this domain instance
     * @return List of CaseRoutingRule__c records
     */
    public List<CaseRoutingRule__c> getRecords() {
        return this.records;
    }

    /**
     * @description Custom exception class for CaseRoutingRules domain
     */
    public class CaseRoutingRulesException extends Exception {}
}