/**
 * @author Vinay Soni
 * @date 2026/10/22
 * @description GW-5676 - Controller class for the imsProductConfigurator LWC (Contract Adjustments in the RCA product
 *              configurator). Reads only. The LWC writes the adjustments into the configuration
 *              (QuoteLineItem.ModelQtyCoverage__c through the context); ContractModifierService creates the
 *              ContractModifier__c records on save.
 */
public with sharing class ImsProductConfiguratorController {

    private static final String CLASS_NAME = 'ImsProductConfiguratorController';
    private static final String SCENARIO = 'Contract Adjustments';
    private static final String LOGGER_TAG = 'ContractAdjustments';


    /**
     * @description Saved Contract Adjustments of a quote line, as JSON (the ModelQtyCoverage__c shape). Unsaved
     *              configurator lines (temporary "ref_" Ids) have nothing stored yet and return empty adjustments.
     * @param lineId Quote Line Item Id from the configurator
     * @return JSON: {"inclusions":[{criteria, "exclusions":[criteria]}], "models":[{criteria, "qty"}]}
     */
    @AuraEnabled
    public static String getCoverage(String lineId) {
        Id quoteLineItemId = toQuoteLineId(lineId);
        if (quoteLineItemId == null) {
            return JSON.serialize(new ContractModifierService.ContractAdjustments());
        }
        try {
            return JSON.serialize(ContractModifierService.getContractAdjustments(quoteLineItemId));
        } catch (Exception e) {
            throw toAuraException('getCoverage: unable to load adjustments', quoteLineItemId, e,
                                  'Unable to load the contract adjustments for this line.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Valid Sub Product Lines for a Product Line (master data).
     * @param productLine Product Line value
     * @return Sub Product Line values; empty when no Product Line is given
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getSubProductLines(String productLine) {
        try {
            return ContractModifierService.getSubProductLines(productLine);
        } catch (Exception e) {
            throw toAuraException('getSubProductLines: lookup failed for ' + productLine, null, e,
                                  'Unable to load the Sub Product Lines.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Manufacturers of the repair assets on the quote's account (and its parent accounts),
     *              narrowed to the Product Line and Sub Product Line picked on an Inclusion / Exclusion row.
     * @param quoteId Quote Id
     * @param productLine Product Line (optional)
     * @param subProductLine Sub Product Line (optional)
     * @return Manufacturer names
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getManufacturers(Id quoteId, String productLine, String subProductLine) {
        try {
            return ContractModifierService.getManufacturers(quoteId, productLine, subProductLine);
        } catch (Exception e) {
            throw toAuraException('getManufacturers: lookup failed', quoteId, e,
                                  'Unable to load the Manufacturers.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Repair assets on the quote's account (and its parent accounts), grouped by Product Line,
     *              Sub Product Line, Product Type, Manufacturer and Model, with counts.
     * @param quoteId Quote Id
     * @return Asset groups
     */
    @AuraEnabled(cacheable=true)
    public static List<ContractModifierService.AssetGroup> getAssetCatalog(Id quoteId) {
        try {
            return ContractModifierService.getAssetCatalog(quoteId);
        } catch (Exception e) {
            throw toAuraException('getAssetCatalog: lookup failed', quoteId, e,
                                  'Unable to load the assets on this account.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Checking for valid Quote Line Item Id.
     * @param lineId Quote Line Item Id
     * @return Id, or null for blank, temporary ("ref_") or malformed Ids
     */
    private static Id toQuoteLineId(String lineId) {
        if (String.isBlank(lineId) || !lineId.startsWith('0QL')) {
            return null;
        }
        try {
            return Id.valueOf(lineId);
        } catch (StringException e) {
            Logger.debug(CLASS_NAME + '.toQuoteLineId: not a valid Quote Line Id: ' + lineId).addTag(LOGGER_TAG);
            Logger.saveLog();
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