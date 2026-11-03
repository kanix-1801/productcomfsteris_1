/**
 * @description ES Service Product Configurator: server-side support for the Asset & PM Visits modal.
 *              Reads only. All writes go through the configurator (Data Manager), never to records.
 */
public with sharing class EsServiceProductConfigController {

    private static final String CLASS_NAME = 'EsServiceProductConfigController';
    private static final String SCENARIO = 'ES Service Product Configurator';
    private static final String LOGGER_TAG = 'ESPC';


    public class LineValues {
        @AuraEnabled public Id assetId;
        @AuraEnabled public String assetName;
        @AuraEnabled public Id pfclId;
        @AuraEnabled public String pfclName;
        @AuraEnabled public Decimal requestedVisits;
    }

    public class AssetOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String pfcl;
    }

    public class LineContext {
        @AuraEnabled public Id accountId;
        @AuraEnabled public LineValues line;
    }

    /**
     * @description Account for the Asset filter, plus saved values when the line exists as a record.
     * @param quoteId Quote Id
     * @param lineId Quote Line Item Id
     * @return RCA Line Context
     */
    @AuraEnabled
    public static LineContext getLineContext(Id quoteId, String lineId) {
        try {
            LineContext ctx = new LineContext();
            if (quoteId != null) {
                Quote quoteRecord = (Quote) new QuoteSelector()
                    .selectField('AccountId')
                    .whereEquals('Id', quoteId)
                    .first();
                if (quoteRecord != null) {
                    ctx.accountId = quoteRecord.AccountId;
                }
            }

            Id qliId = toQuoteLineId(lineId);
            if (qliId != null) {
                QuoteLineItem r = (QuoteLineItem) new QuoteLineItemSelector()
                    .selectFields(new List<String>{
                        'Asset__c', 'Asset__r.Name', 'PFCL__c', 'PFCL__r.Name', 'RequestedNumberofPMVisits__c'
                    })
                    .whereEquals('Id', qliId)
                    .first();
                if (r != null) {
                    LineValues v = new LineValues();
                    v.assetId = r.Asset__c;
                    v.assetName = r.Asset__r?.Name;
                    v.pfclId = r.PFCL__c;
                    v.pfclName = r.PFCL__r?.Name;
                    v.requestedVisits = r.RequestedNumberofPMVisits__c;
                    ctx.line = v;
                }
            }
            return ctx;
        } catch (Exception e) {
            throw toAuraException('getLineContext: unable to load line ' + lineId, quoteId, e,
                                  'Unable to load the quote line details.');
        } finally {
            Logger.saveLog();
        }
    }

    private static final Integer SEARCH_LIMIT = 20;

    /**
     * @description Asset search for the modal's lookup: assets on the given account whose Name,
     *              Serial Number, or PFCL contains the search text. AccountId is indexed, so the
     *              text match only runs over that account's assets.
     * @param accountId Account Id
     * @param searchText Search Text entered by User
     * @return List of custom data type record
     */
    @AuraEnabled
    public static List<AssetOption> searchAssets(Id accountId, String searchText) {
        List<AssetOption> results = new List<AssetOption>();
        if (accountId == null || String.isBlank(searchText) || searchText.trim().length() < 2) {
            return results;
        }
        try {
            // Escape LIKE wildcards in the user's text so they're matched literally.
            String term = '%' + searchText.trim().replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_')
                          + '%';
            List<Asset> assetList = (List<Asset>) new AssetsSelector()
                .selectFields(new List<String>{ 'Id', 'Name', 'SerialNumber', 'PFCL__c' })
                .whereEquals('AccountId', accountId)
                .whereField('Name', 'LIKE', term)
                .whereField('SerialNumber', 'LIKE', term)
                .whereField('PFCL__c', 'LIKE', term)
                .withFilterLogic('1 AND (2 OR 3 OR 4)')
                .orderBy('Name')
                .limitTo(SEARCH_LIMIT)
                .execute();
            for (Asset a : assetList) {
                AssetOption o = new AssetOption();
                o.id = a.Id;
                o.name = a.Name;
                o.serialNumber = a.SerialNumber;
                o.pfcl = a.PFCL__c;
                results.add(o);
            }
            return results;
        } catch (Exception e) {
            throw toAuraException('searchAssets: asset search failed', accountId, e,
                                  'Unable to search assets.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Name and PFCL for the chosen Asset. The PFCL record comes from the Asset's product:
     *              Asset.Product2.PFCL__c (lookup to the PFCL object). Asset.PFCL__c is a formula that
     *              shows the same thing, but it's text, so it can't supply the record Id.
     * @param assetId Asset Id
     * @return List of custom data type record
     */
    @AuraEnabled
    public static LineValues getAssetDetails(Id assetId) {
        try {
            LineValues v = new LineValues();
            v.assetId = assetId;
            Asset assetRecord = assetId == null ? null : (Asset) new AssetsSelector()
                .selectFields(new List<String>{ 'Name', 'Product2.PFCL__c', 'Product2.PFCL__r.Name' })
                .whereEquals('Id', assetId)
                .first();
            if (assetRecord != null) {
                v.assetName = assetRecord.Name;
                v.pfclId = assetRecord.Product2?.PFCL__c;
                v.pfclName = assetRecord.Product2?.PFCL__r?.Name;
            }
            return v;
        } catch (Exception e) {
            throw toAuraException('getAssetDetails: unable to load asset', assetId, e,
                                  'Unable to load the asset details.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Context attribute Ids by field name (ContextAttribute.Title), needed for
     *              ContextFields updates. Returns an empty map if they can't be queried;
     *              the LWC then falls back to its configured Ids.
     * @param fieldNames Context attribute titles (Quote line field API names) to look up
     * @return Map of field name to context attribute Id
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getAttributeIds(List<String> fieldNames) {
        Map<String, String> result = new Map<String, String>();
        try {
            List<ContextAttribute> attributeList = new List<ContextAttribute>();
            if (fieldNames != null && !fieldNames.isEmpty()) {
                attributeList = (List<ContextAttribute>) new ContextAttributeSelector()
                    .selectFields(new List<String>{ 'Id', 'Title' })
                    .whereField('Title', 'IN', fieldNames)
                    .orderBy('Title')
                    .execute();
            }
            for (ContextAttribute r : attributeList) {
                String title = r.Title;
                if (result.containsKey(title)) {
                    Logger.setScenario(SCENARIO);
                    Logger.warn(CLASS_NAME + '.getAttributeIds: duplicate context attribute for ' + title
                                + '; using the first.').addTag(LOGGER_TAG);
                    continue;
                }
                result.put(title, (String) r.Id);
            }
        } catch (Exception e) {
            // Not rethrown on purpose: the LWC falls back to its configured Ids.
            Logger.setScenario(SCENARIO);
            Logger.warn(CLASS_NAME + '.getAttributeIds: ContextAttribute lookup failed', e).addTag(LOGGER_TAG);
        } finally {
            Logger.saveLog();
        }
        return result;
    }

    /**
     * @description Checking for valid Quote Line Item Id.
     * @param lineId Quote Line Item Id
     * @return Id
     */
    private static Id toQuoteLineId(String lineId) {
        if (String.isBlank(lineId) || !lineId.startsWith('0QL')) {
            return null; // unsaved lines use temporary "ref_" Ids
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