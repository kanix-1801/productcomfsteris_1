/**
 * @description Trigger handler for the Department__c SObject.
 *              Orchestrates Domain and Service layer calls.
 *              Uses KevinOHara80 TriggerHandler framework.
 *              No SOQL or DML is allowed in this class.
 */
public with sharing class DepartmentTriggerHandler extends TriggerHandler {

    /**
     * @description Executes before insert logic.
     */
    public override void beforeInsert() {
        if (!AutomationControl.isTriggerEnabled('DepartmentTrigger')) {
            return;
        }
        Departments domain = new Departments((List<Department__c>) Trigger.new);
        // domain.applyDefaults();
        // domain.validate();
    }

    /**
     * @description Executes before update logic.
     */
    public override void beforeUpdate() {
        if (!AutomationControl.isTriggerEnabled('DepartmentTrigger')) {
            return;
        }
        Departments domain = new Departments((List<Department__c>) Trigger.new);
        // domain.validate();
    }

    /**
     * @description Executes after insert logic.
     */
    public override void afterInsert() {
        if (!AutomationControl.isTriggerEnabled('DepartmentTrigger')) {
            return;
        }
        // Set<Id> departmentIds = new Map<Id, Department__c>((List<Department__c>) Trigger.new).keySet();
        // DepartmentsService.handleNewDepartments(departmentIds);
    }

    /**
     * @description Executes after update logic.
     */
    public override void afterUpdate() {
        if (!AutomationControl.isTriggerEnabled('DepartmentTrigger')) {
            return;
        }
        // Set<Id> departmentIds = new Map<Id, Department__c>((List<Department__c>) Trigger.new).keySet();
        // DepartmentsService.handleUpdatedDepartments(departmentIds);
    }
}