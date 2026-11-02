/**
 * @description Trigger handler for the ProductRequest SObject.
 *              Orchestrates Domain and Service layer calls.
 *              Uses KevinOHara80 TriggerHandler framework.
 *              No SOQL or DML is allowed in this class.
 */
public with sharing class ProductRequestTriggerHandler extends TriggerHandler {

    /**
     * @description Executes before insert logic.
     *              Delegates to Domain for defaults and validation.
     */
    public override void beforeInsert() {
        if (!AutomationControl.isTriggerEnabled('ProductRequestTrigger')) {
            return;
        }
        ProductRequests domain = new ProductRequests((List<ProductRequest>) Trigger.new);
        // domain.applyDefaults();
        // domain.validate();
    }

    /**
     * @description Executes before update logic.
     *              Delegates to Domain for validation.
     */
    public override void beforeUpdate() {
        if (!AutomationControl.isTriggerEnabled('ProductRequestTrigger')) {
            return;
        }
        ProductRequests domain = new ProductRequests((List<ProductRequest>) Trigger.new);
        // domain.validate();
    }

    /**
     * @description Executes after insert logic.
     *              Delegates to Service for cross-object operations.
     */
    public override void afterInsert() {
        if (!AutomationControl.isTriggerEnabled('ProductRequestTrigger')) {
            return;
        }
        // Set<Id> productRequestIds = new Map<Id, ProductRequest>((List<ProductRequest>) Trigger.new).keySet();
        // ProductRequestsService.handleNewProductRequests(productRequestIds);
    }

    /**
     * @description Executes after update logic.
     *              Delegates to Service for cross-object operations.
     */
    public override void afterUpdate() {
        if (!AutomationControl.isTriggerEnabled('ProductRequestTrigger')) {
            return;
        }
        // Set<Id> productRequestIds = new Map<Id, ProductRequest>((List<ProductRequest>) Trigger.new).keySet();
        // ProductRequestsService.handleUpdatedProductRequests(productRequestIds);
    }
}