/**
 * @description Trigger handler for the Contact SObject.
 *              Orchestrates Domain and Service layer calls.
 *              Uses KevinOHara80 TriggerHandler framework.
 *              No SOQL or DML is allowed in this class.
 */
public with sharing class ContactTriggerHandler extends TriggerHandler {

    /**
     * @description Executes before insert logic.
     */
    public override void beforeInsert() {
        if (!AutomationControl.isTriggerEnabled('ContactTrigger')) {
            return;
        }
        Contacts domain = new Contacts((List<Contact>) Trigger.new);
        // domain.applyDefaults();
        // domain.validate();
    }

    /**
     * @description Executes before update logic.
     */
    public override void beforeUpdate() {
        if (!AutomationControl.isTriggerEnabled('ContactTrigger')) {
            return;
        }
        Contacts domain = new Contacts((List<Contact>) Trigger.new);
        // domain.validate();
    }

    /**
     * @description Executes after insert logic.
     */
    public override void afterInsert() {
        if (!AutomationControl.isTriggerEnabled('ContactTrigger')) {
            return;
        }
        // Set<Id> contactIds = new Map<Id, Contact>((List<Contact>) Trigger.new).keySet();
        // ContactsService.handleNewContacts(contactIds);
    }

    /**
     * @description Executes after update logic.
     */
    public override void afterUpdate() {
        if (!AutomationControl.isTriggerEnabled('ContactTrigger')) {
            return;
        }
        // Set<Id> contactIds = new Map<Id, Contact>((List<Contact>) Trigger.new).keySet();
        // ContactsService.handleUpdatedContacts(contactIds);
    }
}