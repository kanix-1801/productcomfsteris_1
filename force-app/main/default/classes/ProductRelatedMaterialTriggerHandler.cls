/**
 * @description Trigger handler for the ProductRelatedMaterial SObject.
 *              Orchestrates Domain and Service layer calls.
 *              Uses KevinOHara80 TriggerHandler framework.
 *              No SOQL or DML is allowed in this class.
 */
public with sharing class ProductRelatedMaterialTriggerHandler extends TriggerHandler {

    /**
     * @description Executes before insert logic.
     */
    public override void beforeInsert() {
        if (!AutomationControl.isTriggerEnabled('ProductRelatedMaterialTrigger')) {
            return;
        }
        ProductRelatedMaterials domain = new ProductRelatedMaterials((List<ProductRelatedMaterial>) Trigger.new);
        // domain.applyDefaults();
        // domain.validate();
    }

    /**
     * @description Executes before update logic.
     */
    public override void beforeUpdate() {
        if (!AutomationControl.isTriggerEnabled('ProductRelatedMaterialTrigger')) {
            return;
        }
        ProductRelatedMaterials domain = new ProductRelatedMaterials((List<ProductRelatedMaterial>) Trigger.new);
        // domain.validate();
    }

    /**
     * @description Executes after insert logic.
     */
    public override void afterInsert() {
        if (!AutomationControl.isTriggerEnabled('ProductRelatedMaterialTrigger')) {
            return;
        }
        // Set<Id> relatedMaterialIds = new Map<Id, ProductRelatedMaterial>((List<ProductRelatedMaterial>) Trigger.new).keySet();
        // ProductRelatedMaterialsService.handleNewProductRelatedMaterials(relatedMaterialIds);
    }

    /**
     * @description Executes after update logic.
     */
    public override void afterUpdate() {
        if (!AutomationControl.isTriggerEnabled('ProductRelatedMaterialTrigger')) {
            return;
        }
        // Set<Id> relatedMaterialIds = new Map<Id, ProductRelatedMaterial>((List<ProductRelatedMaterial>) Trigger.new).keySet();
        // ProductRelatedMaterialsService.handleUpdatedProductRelatedMaterials(relatedMaterialIds);
    }
}