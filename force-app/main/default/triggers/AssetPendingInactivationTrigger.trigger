/**
 * @description GW-2459 - Prevents Pending Inactivation → Service Inactive unless
 *              AssetPendingInactivationService evaluated the Asset in this transaction.
 */
trigger AssetPendingInactivationTrigger on Asset (before update) {
    AssetPendingInactivationService.preventUnevaluatedServiceInactive(
        Trigger.new,
        Trigger.oldMap
    );
}