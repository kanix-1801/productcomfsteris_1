/**
 * @author Vinay Soni
 * @date 2026/11/25
 * @group IMS Asset Assignment
 * @description GW-6456 - Controller for the IMS Covered Equipment LWCs (imsCoveredEquipment,
 *              imsInventoryGroupPicker / imsInventoryGroupPreview and imsAssetPicker). Reads only: the selection is
 *              written into the configuration by imsCoveredEquipment (QuoteLineItem.ImsAssetSelection__c via the
 *              context) and saved with the quote line.
 */
public with sharing class ImsAssetAssignmentController {

	private static final String CLASS_NAME = 'ImsAssetAssignmentController';
	private static final String SCENARIO = 'IMS Asset Assignment';
	private static final String LOGGER_TAG = 'ImsAssets';

	/**
	 * @description Quote opportunity, its inventory groups and the selection saved on the line.
	 * @param quoteId Quote Id (configuratorContext.transactionId)
	 * @param lineId Quote Line Item Id from the configurator; unsaved "ref_" Ids have nothing saved
	 * @return Assignment context
	 */
	@AuraEnabled
	public static ImsAssetAssignmentService.AssignmentContext getAssignmentContext(Id quoteId, String lineId) {
		try {
			return ImsAssetAssignmentService.getContext(quoteId, toQuoteLineId(lineId));
		} catch (Exception e) {
			throw toAuraException('getAssignmentContext: unable to load the context', quoteId, e,
								  'Unable to load the covered equipment.');
		} finally {
			Logger.saveLog();
		}
	}

	/**
	 * @description One page of an inventory group's devices, for the preview panel.
	 * @param opportunityId Opportunity Id
	 * @param groupName Group name as shown
	 * @param offset Rows already loaded
	 * @return Asset rows (up to 50)
	 */
	@AuraEnabled
	public static List<EsServiceAssetSelectionController.AssetRow> getGroupAssets(Id opportunityId, String groupName,
																				  Integer offset) {
		try {
			return ImsAssetAssignmentService.getGroupPage(opportunityId, groupName, offset);
		} catch (Exception e) {
			throw toAuraException('getGroupAssets: unable to load group ' + groupName, opportunityId, e,
								  'Unable to load the devices in this group.');
		} finally {
			Logger.saveLog();
		}
	}

	/**
	 * @description Assets for the Choose Assets picker: the groups' devices first, then the account assets.
	 * @param quoteId Quote Id
	 * @param opportunityId Opportunity Id
	 * @param groups Group names chosen in step 1
	 * @return Eligible assets
	 */
	@AuraEnabled
	public static ImsAssetAssignmentService.EligibleAssets getEligibleAssets(Id quoteId, Id opportunityId,
																			 List<String> groups) {
		try {
			return ImsAssetAssignmentService.getEligibleAssets(quoteId, opportunityId, groups);
		} catch (Exception e) {
			throw toAuraException('getEligibleAssets: unable to load assets', quoteId, e,
								  'Unable to load the assets for this quote.');
		} finally {
			Logger.saveLog();
		}
	}

	/**
	 * @description Checks for a saved Quote Line Item Id.
	 * @param lineId Quote Line Item Id
	 * @return Id, or null for blank, temporary ("ref_") or malformed Ids
	 */
	@TestVisible
	private static Id toQuoteLineId(String lineId) {
		if (String.isBlank(lineId) || !lineId.startsWith('0QL')) {
			return null;
		}
		try {
			return Id.valueOf(lineId);
		} catch (StringException e) {
			Logger.debug(CLASS_NAME + '.toQuoteLineId: not a valid Quote Line Id: ' + lineId).addTag(LOGGER_TAG);
			return null;
		}
	}

	/**
	 * @description Logs a failed @AuraEnabled call and builds the exception the LWC receives.
	 * @param context Method name and what failed, for the log entry
	 * @param recordId Record the call was for (may be null)
	 * @param error The caught exception
	 * @param userMessage Message shown in the LWC
	 * @return AuraHandledException for the caller to throw
	 */
	@TestVisible
	private static AuraHandledException toAuraException(String context, Id recordId, Exception error,
														String userMessage) {
		Logger.setScenario(SCENARIO);
		Logger.error(CLASS_NAME + '.' + context, recordId, error).addTag(LOGGER_TAG);
		AuraHandledException auraException = new AuraHandledException(userMessage);
		auraException.setMessage(userMessage);
		return auraException;
	}
}
