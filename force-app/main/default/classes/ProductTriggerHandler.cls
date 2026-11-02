/**
 * @description Trigger handler for the Product2 SObject.
 *              Orchestrates Domain and Service layer calls.
 *              Uses KevinOHara80 TriggerHandler framework.
 *              No SOQL or DML is allowed in this class.
 */
public with sharing class ProductTriggerHandler extends TriggerHandler {

    /**
     * @description Executes before insert logic.
     */
    public override void beforeInsert() {
        if (!AutomationControl.isTriggerEnabled('ProductTrigger')) {
            return;
        }
        Products domain = new Products((List<Product2>) Trigger.new);
        // domain.applyDefaults();
        // domain.validate();
    }

    /**
     * @description Executes before update logic.
     */
    public override void beforeUpdate() {
        if (!AutomationControl.isTriggerEnabled('ProductTrigger')) {
            return;
        }
        Products domain = new Products((List<Product2>) Trigger.new);
        // domain.validate();
    }

    /**
     * @description Executes after insert logic.
     */
    public override void afterInsert() {
        if (!AutomationControl.isTriggerEnabled('ProductTrigger')) {
            return;
        }
        // Set<Id> productIds = new Map<Id, Product2>((List<Product2>) Trigger.new).keySet();
        // ProductsService.handleNewProducts(productIds);
    }

    /**
     * @description Executes after update logic.
     */
    public override void afterUpdate() {
        if (!AutomationControl.isTriggerEnabled('ProductTrigger')) {
            return;
        }
        // Set<Id> productIds = new Map<Id, Product2>((List<Product2>) Trigger.new).keySet();
        // ProductsService.handleUpdatedProducts(productIds);
    }
}