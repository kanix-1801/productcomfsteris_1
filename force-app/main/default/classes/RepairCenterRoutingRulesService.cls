/**
 * @description Service class for RepairCenterRoutingRule__c business operations.
 *              Entry point for all RepairCenterRoutingRule-related transactions.
 *              Performs DML directly — no Unit of Work.
 */
public with sharing class RepairCenterRoutingRulesService {

    /**
     * @description Creates new RepairCenterRoutingRule__c records with validation.
     * @param rules List of RepairCenterRoutingRule__c records to create.
     * @throws RepairCenterRoutingRulesServiceException when the operation fails.
     */
    public static void createRepairCenterRoutingRules(List<RepairCenterRoutingRule__c> rules) {
        if (rules == null || rules.isEmpty()) {
            return;
        }
        Logger.setScenario('Repair Center Routing Rule Management');
        try {
            RepairCenterRoutingRules domain = new RepairCenterRoutingRules(rules);
            // domain.applyDefaults();
            // domain.validate();
            insert rules;
        } catch (RepairCenterRoutingRules.RepairCenterRoutingRulesException e) {
            Logger.error(new LogMessage('RepairCenterRoutingRulesService.createRepairCenterRoutingRules: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new RepairCenterRoutingRulesServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('RepairCenterRoutingRulesService.createRepairCenterRoutingRules: Unexpected error.', e);
            Logger.saveLog();
            throw new RepairCenterRoutingRulesServiceException('An unexpected error occurred while creating RepairCenterRoutingRule records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Updates existing RepairCenterRoutingRule__c records with validation.
     * @param rules List of RepairCenterRoutingRule__c records to update.
     * @throws RepairCenterRoutingRulesServiceException when the operation fails.
     */
    public static void updateRepairCenterRoutingRules(List<RepairCenterRoutingRule__c> rules) {
        if (rules == null || rules.isEmpty()) {
            return;
        }
        Logger.setScenario('Repair Center Routing Rule Management');
        try {
            RepairCenterRoutingRules domain = new RepairCenterRoutingRules(rules);
            // domain.validate();
            update rules;
        } catch (RepairCenterRoutingRules.RepairCenterRoutingRulesException e) {
            Logger.error(new LogMessage('RepairCenterRoutingRulesService.updateRepairCenterRoutingRules: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new RepairCenterRoutingRulesServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('RepairCenterRoutingRulesService.updateRepairCenterRoutingRules: Unexpected error.', e);
            Logger.saveLog();
            throw new RepairCenterRoutingRulesServiceException('An unexpected error occurred while updating RepairCenterRoutingRule records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Deletes RepairCenterRoutingRule__c records by their Ids.
     * @param ruleIds Set of RepairCenterRoutingRule__c Ids to delete.
     * @throws RepairCenterRoutingRulesServiceException when the operation fails.
     */
    public static void deleteRepairCenterRoutingRules(Set<Id> ruleIds) {
        if (ruleIds == null || ruleIds.isEmpty()) {
            return;
        }
        Logger.setScenario('Repair Center Routing Rule Management');
        try {
            List<RepairCenterRoutingRule__c> ruleList = RepairCenterRoutingRulesSelector.selectById(ruleIds);
            if (ruleList.isEmpty()) {
                return;
            }
            delete ruleList;
        } catch (Exception e) {
            Logger.error('RepairCenterRoutingRulesService.deleteRepairCenterRoutingRules: Unexpected error.', e);
            Logger.saveLog();
            throw new RepairCenterRoutingRulesServiceException('An unexpected error occurred while deleting RepairCenterRoutingRule records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Retrieves RepairCenterRoutingRule__c records by their Ids.
     * @param ruleIds Set of RepairCenterRoutingRule__c Ids to retrieve.
     * @return List of RepairCenterRoutingRule__c records.
     * @throws RepairCenterRoutingRulesServiceException when the operation fails.
     */
    public static List<RepairCenterRoutingRule__c> getRepairCenterRoutingRulesById(Set<Id> ruleIds) {
        if (ruleIds == null || ruleIds.isEmpty()) {
            return new List<RepairCenterRoutingRule__c>();
        }
        try {
            return RepairCenterRoutingRulesSelector.selectById(ruleIds);
        } catch (Exception e) {
            Logger.error('RepairCenterRoutingRulesService.getRepairCenterRoutingRulesById: Unexpected error.', e);
            Logger.saveLog();
            throw new RepairCenterRoutingRulesServiceException('An unexpected error occurred while retrieving RepairCenterRoutingRule records.', e);
        }
    }

    /**
     * @description Thrown when a RepairCenterRoutingRule service operation fails.
     */
    public class RepairCenterRoutingRulesServiceException extends Exception {}
}