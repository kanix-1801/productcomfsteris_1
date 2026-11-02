/**
 * @description Trigger handler for the ProductItem SObject.
 *              Orchestrates Domain and Service layer calls.
 *              Uses KevinOHara80 TriggerHandler framework.
 *              No SOQL or DML is allowed in this class.
 */
public with sharing class ProductItemTriggerHandler extends TriggerHandler {

    /**
     * @description Executes before insert logic.
     */
    public override void beforeInsert() {
        if (!AutomationControl.isTriggerEnabled('ProductItemTrigger')) {
            return;
        }
        ProductItems domain = new ProductItems((List<ProductItem>) Trigger.new);
        // domain.applyDefaults();
        // domain.validate();
    }

    /**
     * @description Executes before update logic.
     */
    public override void beforeUpdate() {
        if (!AutomationControl.isTriggerEnabled('ProductItemTrigger')) {
            return;
        }
        ProductItems domain = new ProductItems((List<ProductItem>) Trigger.new);
        // domain.validate();
    }

    /**
     * @description Executes after insert logic.
     */
    public override void afterInsert() {
        if (!AutomationControl.isTriggerEnabled('ProductItemTrigger')) {
            return;
        }
        // Set<Id> productItemIds = new Map<Id, ProductItem>((List<ProductItem>) Trigger.new).keySet();
        // ProductItemsService.handleNewProductItems(productItemIds);
    }

    /**
     * @description Executes after update logic.
     */
    public override void afterUpdate() {
        if (!AutomationControl.isTriggerEnabled('ProductItemTrigger')) {
            return;
        }
        // Set<Id> productItemIds = new Map<Id, ProductItem>((List<ProductItem>) Trigger.new).keySet();
        // ProductItemsService.handleUpdatedProductItems(productItemIds);
    }
}