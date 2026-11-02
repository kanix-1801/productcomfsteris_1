/**
 * @description Trigger handler for the AccountDepartment__c SObject.
 *              Orchestrates Domain and Service layer calls.
 *              Uses KevinOHara80 TriggerHandler framework.
 *              No SOQL or DML is allowed in this class.
 */
public with sharing class AccountDepartmentTriggerHandler extends TriggerHandler {

    /**
     * @description Executes before insert logic.
     */
    public override void beforeInsert() {
        if (!AutomationControl.isTriggerEnabled('AccountDepartmentTrigger')) {
            return;
        }
        AccountDepartments domain = new AccountDepartments((List<AccountDepartment__c>) Trigger.new);
        // domain.applyDefaults();
        // domain.validate();
    }

    /**
     * @description Executes before update logic.
     */
    public override void beforeUpdate() {
        if (!AutomationControl.isTriggerEnabled('AccountDepartmentTrigger')) {
            return;
        }
        AccountDepartments domain = new AccountDepartments((List<AccountDepartment__c>) Trigger.new);
        // domain.validate();
    }

    /**
     * @description Executes after insert logic.
     */
    public override void afterInsert() {
        if (!AutomationControl.isTriggerEnabled('AccountDepartmentTrigger')) {
            return;
        }
        // Set<Id> accountDepartmentIds = new Map<Id, AccountDepartment__c>((List<AccountDepartment__c>) Trigger.new).keySet();
        // AccountDepartmentsService.handleNewAccountDepartments(accountDepartmentIds);
    }

    /**
     * @description Executes after update logic.
     */
    public override void afterUpdate() {
        if (!AutomationControl.isTriggerEnabled('AccountDepartmentTrigger')) {
            return;
        }
        // Set<Id> accountDepartmentIds = new Map<Id, AccountDepartment__c>((List<AccountDepartment__c>) Trigger.new).keySet();
        // AccountDepartmentsService.handleUpdatedAccountDepartments(accountDepartmentIds);
    }
}