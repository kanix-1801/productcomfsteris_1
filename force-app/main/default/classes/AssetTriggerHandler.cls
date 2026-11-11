/**
 * @description Trigger handler for the Asset SObject.
 *              Orchestrates Domain and Service layer calls.
 *              Uses KevinOHara80 TriggerHandler framework.
 *              No SOQL or DML is allowed in this class.
 *              GW-2459 blocks Pending Inactivation → Service Inactive unless the
 *              evaluation update ran in this same transaction.
 * @see AssetPendingInactivationService
 */
public with sharing class AssetTriggerHandler extends TriggerHandler {

    /**
     * @description Executes before insert logic.
     */
    public override void beforeInsert() {
        if (!AutomationControl.isTriggerEnabled('AssetTrigger')) {
            return;
        }
        Assets domain = new Assets((List<Asset>) Trigger.new);
        // domain.applyDefaults();
        // domain.validate();
    }

    /**
     * @description Executes before update logic.
     *              GW-2459: Pending Inactivation can become Service Inactive only when
     *              AssetPendingInactivationService evaluated the Asset in this transaction.
     */
    public override void beforeUpdate() {
        if (!AutomationControl.isTriggerEnabled('AssetTrigger')) {
            return;
        }
        AssetPendingInactivationService.preventUnevaluatedServiceInactive(
            (List<Asset>) Trigger.new,
            (Map<Id, Asset>) Trigger.oldMap
        );
        Assets domain = new Assets((List<Asset>) Trigger.new);
        // domain.validate();
    }

    /**
     * @description Executes before delete logic.
     */
    public override void beforeDelete() {
        if (!AutomationControl.isTriggerEnabled('AssetTrigger')) {
            return;
        }
    }

    /**
     * @description Executes after insert logic.
     */
    public override void afterInsert() {
        if (!AutomationControl.isTriggerEnabled('AssetTrigger')) {
            return;
        }
        // Set<Id> assetIds = new Map<Id, Asset>((List<Asset>) Trigger.new).keySet();
        // AssetsService.handleNewAssets(assetIds);
    }

    /**
     * @description Executes after update logic.
     */
    public override void afterUpdate() {
        if (!AutomationControl.isTriggerEnabled('AssetTrigger')) {
            return;
        }
        // Set<Id> assetIds = new Map<Id, Asset>((List<Asset>) Trigger.new).keySet();
        // AssetsService.handleUpdatedAssets(assetIds);
    }
}