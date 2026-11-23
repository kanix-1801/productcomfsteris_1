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
	public static ModifierCodesService.Workspace getWorkspace(
		Id workOrderId,
		String variant
	) {
		try {
			return ModifierCodesService.getWorkspace(workOrderId, variant);
		} catch (Exception e) {
			throw handledException(
				e,
				'ModifierCodesController.getWorkspace failed',
				'Unable to load modifier codes.'
			);
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
	public static List<ModifierCodesService.PickOption> getPricingModifierOptions(
		String appliesTo
	) {
		try {
			return ModifierCodesService.getPricingModifierOptions(appliesTo);
		} finally {
			Logger.saveLog();
		}
	}

	/**
	 * @description Shipped work orders for the asset, newest completion first.
	 * @param assetId Asset on the line being modified
	 * @param workOrderId Work order the user is on; omitted from Order Reference
	 * @return Dropdown options for Order Reference
	 */
	@AuraEnabled
	public static List<ModifierCodesService.PickOption> getPriorWorkOrders(
		Id assetId,
		Id workOrderId
	) {
		try {
			return ModifierCodesService.getPriorWorkOrders(
				assetId,
				workOrderId
			);
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
		} catch (Exception e) {
			throw handledException(
				e,
				'ModifierCodesController.saveModifier failed',
				'Unable to save the modifier.'
			);
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
		} catch (Exception e) {
			throw handledException(
				e,
				'ModifierCodesController.removeModifier failed',
				'Unable to remove the modifier.'
			);
		} finally {
			Logger.saveLog();
		}
	}

	/**
	 * @description Turns a service or DML failure into the message the Modifier Codes tab shows.
	 * @param error Exception raised while loading or saving
	 * @param logLabel Log entry name
	 * @param fallback Message used when the failure has no user-facing text
	 * @return Aura exception for the Lightning client
	 */
	private static AuraHandledException handledException(
		Exception error,
		String logLabel,
		String fallback
	) {
		if (error instanceof ModifierCodesService.ModifierCodesException) {
			return PlatformUtilities.buildAuraException(error.getMessage());
		}
		Logger.error(logLabel, error);
		if (error instanceof DmlException) {
			return PlatformUtilities.buildAuraException(
				fallback + ': ' + ((DmlException) error).getDmlMessage(0)
			);
		}
		return PlatformUtilities.buildAuraException(fallback);
	}
}