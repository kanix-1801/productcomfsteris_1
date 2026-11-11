/**
 * @description GW-3458 - Aura entry points for the Modifier Codes tab on Device and Instrument Evaluation.
 */
public with sharing class ModifierCodesController {
    /**
     * @description Loads the Modifier Codes tables for a work order.
     * @param workOrderId Work Order being evaluated
     * @param variant device or instrument
     * @return Tables for the requested evaluation screen
     */
    @AuraEnabled
    public static ModifierCodesService.Workspace getWorkspace(Id workOrderId, String variant) {
        try {
            return ModifierCodesService.getWorkspace(workOrderId, variant);
        } catch (ModifierCodesService.ModifierCodesException e) {
            throw PlatformUtilities.buildAuraException(e.getMessage());
        } catch (Exception e) {
            Logger.error('ModifierCodesController.getWorkspace failed', e);
            throw PlatformUtilities.buildAuraException('Unable to load modifier codes.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Active pricing modifiers for an item or a service dropdown.
     * @param appliesTo item or service
     * @return Dropdown options
     */
    @AuraEnabled
    public static List<ModifierCodesService.PickOption> getPricingModifierOptions(String appliesTo) {
        try {
            return ModifierCodesService.getPricingModifierOptions(appliesTo);
        } catch (ModifierCodesService.ModifierCodesException e) {
            throw PlatformUtilities.buildAuraException(e.getMessage());
        } catch (Exception e) {
            Logger.error('ModifierCodesController.getPricingModifierOptions failed', e);
            throw PlatformUtilities.buildAuraException('Unable to load pricing modifiers.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Modifier Reason Code picklist values.
     * @return Dropdown options
     */
    @AuraEnabled
    public static List<ModifierCodesService.PickOption> getReasonCodeOptions() {
        try {
            return ModifierCodesService.getReasonCodeOptions();
        } catch (Exception e) {
            Logger.error('ModifierCodesController.getReasonCodeOptions failed', e);
            throw PlatformUtilities.buildAuraException('Unable to load modifier reason codes.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Shipped work orders for the asset, newest completion first.
     * @param assetId Asset on the line being modified
     * @return Dropdown options for Modifier Reason Code and Order Reference
     */
    @AuraEnabled
    public static List<ModifierCodesService.PickOption> getPriorWorkOrders(Id assetId) {
        try {
            return ModifierCodesService.getPriorWorkOrders(assetId);
        } catch (Exception e) {
            Logger.error('ModifierCodesController.getPriorWorkOrders failed', e);
            throw PlatformUtilities.buildAuraException('Unable to load prior work orders.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Saves one modifier onto a work order line and cascades Item and Service modifiers.
     *              Arguments are separate because an LWC cannot populate an Apex inner-class parameter.
     * @param workOrderLineItemId Line receiving the modifier
     * @param pricingModifierId Pricing Modifier to apply
     * @param modifierReasonCode Modifier Reason Code picklist value
     * @param orderReferenceId Shipped work order for this asset
     * @param applyOrderReference True on Device Evaluation, where Order Reference is shown
     */
    @AuraEnabled
    public static void saveModifier(
        Id workOrderLineItemId,
        Id pricingModifierId,
        String modifierReasonCode,
        Id orderReferenceId,
        Boolean applyOrderReference
    ) {
        ModifierCodesService.SaveRequest request = new ModifierCodesService.SaveRequest();
        request.workOrderLineItemId = workOrderLineItemId;
        request.pricingModifierId = pricingModifierId;
        request.modifierReasonCode = modifierReasonCode;
        request.orderReferenceId = orderReferenceId;
        request.applyOrderReference = applyOrderReference;
        try {
            ModifierCodesService.saveModifier(request);
        } catch (ModifierCodesService.ModifierCodesException e) {
            throw PlatformUtilities.buildAuraException(e.getMessage());
        } catch (DmlException e) {
            Logger.error('ModifierCodesController.saveModifier DML', e);
            throw PlatformUtilities.buildAuraException('Unable to save the modifier: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            Logger.error('ModifierCodesController.saveModifier failed', e);
            throw PlatformUtilities.buildAuraException('Unable to save the modifier.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Clears the modifier on a line and removes an inherited Item and Service modifier from its services.
     * @param workOrderLineItemId Line whose modifier is being removed
     */
    @AuraEnabled
    public static void removeModifier(Id workOrderLineItemId) {
        try {
            ModifierCodesService.removeModifier(workOrderLineItemId);
        } catch (ModifierCodesService.ModifierCodesException e) {
            throw PlatformUtilities.buildAuraException(e.getMessage());
        } catch (DmlException e) {
            Logger.error('ModifierCodesController.removeModifier DML', e);
            throw PlatformUtilities.buildAuraException('Unable to remove the modifier: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            Logger.error('ModifierCodesController.removeModifier failed', e);
            throw PlatformUtilities.buildAuraException('Unable to remove the modifier.');
        } finally {
            Logger.saveLog();
        }
    }
}