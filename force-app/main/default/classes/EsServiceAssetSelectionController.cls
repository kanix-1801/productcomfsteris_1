/**
 * @description ES Service Product Configurator: asset selection for the bundle-level "Assets Selected"
 *              launcher and the "Choose Assets" picker. Reads only; the selection is written into the
 *              configuration by the launcher (QuoteLineItem.SelectedAssets__c via the context).
 */
public with sharing class EsServiceAssetSelectionController {

    private static final String CLASS_NAME = 'EsServiceAssetSelectionController';
    private static final String SCENARIO = 'ES Service Product Configurator';
    private static final String LOGGER_TAG = 'ESPC';

    /**
     * @description The picker loads all assets once and searches/sorts in the browser.
     *              Raise with care: very large lists slow the first load.
     */
    private static final Integer MAX_ASSETS = 10000;

    public class AssetRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String address;
        @AuraEnabled public Date installDate;
        @AuraEnabled public String productLine;
        @AuraEnabled public String subProductLine;
        @AuraEnabled public String productType;
        @AuraEnabled public String manufacturer;
        @AuraEnabled public String model;
        @AuraEnabled public String pfcl;
    }

    public class AssetList {
        @AuraEnabled public List<AssetRow> rows = new List<AssetRow>();
        @AuraEnabled public Id quoteAccountId;
        @AuraEnabled public Integer relatedAccountCount = 0;
        @AuraEnabled public Boolean truncated = false;
        @AuraEnabled public Integer maxRows = MAX_ASSETS;
    }

    /**
     * @description Assets for the picker: only assets on the quote's account or on its parent accounts,
     *              i.e. AccountAccountRelationship__c.ParentAccount__c where ChildAccount__c is the
     *              quote's account (one level). Search and sort in the picker work within this list.
     * @param quoteId Quote Id
     * @return List of custom data type frecords
     */
    @AuraEnabled
    public static AssetList getAssets(Id quoteId) {
        AssetList result = new AssetList();
        if (quoteId == null) {
            return result;
        }

        try {
            Quote quoteRecord = (Quote) new QuoteSelector()
                .selectField('AccountId')
                .whereEquals('Id', quoteId)
                .first();
            if (quoteRecord == null || quoteRecord.AccountId == null) {
                return result;
            }
            Id quoteAccountId = quoteRecord.AccountId;
            result.quoteAccountId = quoteAccountId;

            Set<Id> accountIds = new Set<Id>{ quoteAccountId };
            List<AccountAccountRelationship__c> relationshipList =
                (List<AccountAccountRelationship__c>) new AccountAccountRelationshipSelector()
                    .selectField('ParentAccount__c')
                    .whereEquals('ChildAccount__c', quoteAccountId)
                    .whereField('ParentAccount__c', '!=', null)
                    .execute();
            for (AccountAccountRelationship__c rel : relationshipList) {
                accountIds.add(rel.ParentAccount__c);
            }
            result.relatedAccountCount = accountIds.size() - 1;

            Integer queryLimit = MAX_ASSETS + 1;
            // Must stay a List<Id> at runtime: binding a List<Object> to an Id column fails in SOQL.
            List<Object> accountIdValues = new List<Id>(accountIds);
            List<String> assetFields = new List<String>{
                'Id', 'SerialNumber', 'Name', 'Status', 'AccountId',
                'AssetAccountName_f__c', 'Street', 'City', 'State',
                'PostalCode', 'Country', 'InstallDate',
                'ProductLineCalculated__c', 'SubProductLineCalculated__c',
                'ProductTypeCalculated__c', 'ManufacturerCalculated__c',
                'ModelCalculated__c', 'PFCL__c', 'Product2.PFCL__r.Name'
            };
            List<Asset> assets = (List<Asset>) new AssetsSelector()
                .selectFields(assetFields)
                .whereField('AccountId', 'IN', accountIdValues)
                .orderBy('SerialNumber', false, true)
                .orderBy('Name')
                .limitTo(queryLimit)
                .execute();
            if (assets.size() > MAX_ASSETS) {
                result.truncated = true;
                assets.remove(assets.size() - 1);
            }
            for (Asset a : assets) {
                result.rows.add(toRow(a));
            }
            return result;
        } catch (Exception e) {
            throw toAuraException('getAssets: unable to load assets for the quote', quoteId, e,
                                  'Unable to load the assets for this quote.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Assets by Id, for the launcher's preview of a saved selection.
     * @param assetIds List of Asset Ids
     * @return List of custom data type records
     */
    @AuraEnabled
    public static List<AssetRow> getAssetsByIds(List<Id> assetIds) {
        List<AssetRow> rows = new List<AssetRow>();
        if (assetIds == null || assetIds.isEmpty()) {
            return rows;
        }
        try {
            // Must stay a List<Id> at runtime: binding a List<Object> to an Id column fails in SOQL.
            List<Object> assetIdValues = new List<Id>(assetIds);
            List<String> assetFields = new List<String>{
                'Id', 'SerialNumber', 'Name', 'Status', 'AccountId', 'AssetAccountName_f__c',
                'Street', 'City', 'State', 'PostalCode', 'Country', 'InstallDate',
                'ProductLineCalculated__c', 'SubProductLineCalculated__c', 'ProductTypeCalculated__c',
                'ManufacturerCalculated__c', 'ModelCalculated__c', 'PFCL__c', 'Product2.PFCL__r.Name'
            };
            List<Asset> assetList = (List<Asset>) new AssetsSelector()
                .selectFields(assetFields)
                .whereField('Id', 'IN', assetIdValues)
                .orderBy('SerialNumber', false, true)
                .orderBy('Name')
                .execute();
            for (Asset a : assetList) {
                rows.add(toRow(a));
            }
            return rows;
        } catch (Exception e) {
            throw toAuraException('getAssetsByIds: unable to load ' + assetIds.size() + ' assets', null, e,
                                  'Unable to load the selected assets.');
        } finally {
            Logger.saveLog();
        }
    }

    public class LineAsset {
        @AuraEnabled public Id assetId;
        @AuraEnabled public String assetName;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String pfclName;
        @AuraEnabled public Decimal requestedVisits;
    }

    /**
     * @description Product on a saved quote line. Used to recognize the bundle screen in the configurator.
     * @param lineId Quoe Line Item Id
     * @return Product Id
     */
    @AuraEnabled(cacheable=true)
    public static Id getLineProductId(String lineId) {
        Id qliId = toQuoteLineId(lineId);
        if (qliId == null) {
            return null;
        }
        try {
            QuoteLineItem lineRecord = (QuoteLineItem) new QuoteLineItemSelector()
                .selectField('Product2Id')
                .whereEquals('Id', qliId)
                .first();
            return lineRecord == null ? null : lineRecord.Product2Id;
        } catch (Exception e) {
            throw toAuraException('getLineProductId: unable to load the line product', qliId, e,
                                  'Unable to load the quote line product.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description The asset written to one service product line, with its PFCL and requested visits.
     * @param lineId Quoe Line Item Id
     * @return Custom data type record
     */
    @AuraEnabled
    public static LineAsset getLineAsset(String lineId) {
        Id qliId = toQuoteLineId(lineId);
        if (qliId == null) {
            return null;
        }
        try {
            QuoteLineItem r = (QuoteLineItem) new QuoteLineItemSelector()
                .selectFields(new List<String>{
                    'Asset__c', 'AssetName__c', 'Asset__r.Name', 'Asset__r.SerialNumber',
                    'PFCLName__c', 'PFCL__r.Name', 'RequestedNumberofPMVisits__c'
                })
                .whereEquals('Id', qliId)
                .first();
            if (r == null) {
                return null;
            }
            LineAsset a = new LineAsset();
            a.assetId = r.Asset__c;
            a.assetName = String.isNotBlank(r.AssetName__c) ? r.AssetName__c : r.Asset__r?.Name;
            a.serialNumber = r.Asset__r?.SerialNumber;
            a.pfclName = String.isNotBlank(r.PFCLName__c) ? r.PFCLName__c : r.PFCL__r?.Name;
            a.requestedVisits = r.RequestedNumberofPMVisits__c;
            return a;
        } catch (Exception e) {
            throw toAuraException('getLineAsset: unable to load the line asset', qliId, e,
                                  'Unable to load this line\'s asset.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Saved per-asset visits (JSON map of Asset Id to requested visits) for a service product
     *              line that exists as a record.
     * @param lineId Quoe Line Item Id
     * @return Asset Visits
     */
    @AuraEnabled
    public static String getSavedVisits(String lineId) {
        Id qliId = toQuoteLineId(lineId);
        if (qliId == null) {
            return null;
        }
        try {
            QuoteLineItem lineRecord = (QuoteLineItem) new QuoteLineItemSelector()
                .selectField('AssetVisits__c')
                .whereEquals('Id', qliId)
                .first();
            return lineRecord?.AssetVisits__c;
        } catch (Exception e) {
            throw toAuraException('getSavedVisits: unable to load the saved visits', qliId, e,
                                  'Unable to load the saved PM visits.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Checking for valid Quote Line Item Id.
     * @param lineId Quoe Line Item Id
     * @return Id
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
     * @description Saved selection (JSON list of Asset Ids) for a bundle line that exists as a record.
     * @param lineId Quoe Line Item Id
     * @return Selected Asset
     */
    @AuraEnabled
    public static String getSavedSelection(String lineId) {
        if (String.isBlank(lineId) || !lineId.startsWith('0QL')) {
            return null;
        }
        Id qliId;
        try {
            qliId = Id.valueOf(lineId);
        } catch (StringException e) {
            Logger.debug(CLASS_NAME + '.getSavedSelection: not a valid Quote Line Id: ' + lineId)
                  .addTag(LOGGER_TAG);
            Logger.saveLog();
            return null;
        }
        try {
            QuoteLineItem lineRecord = (QuoteLineItem) new QuoteLineItemSelector()
                .selectField('SelectedAssets__c')
                .whereEquals('Id', qliId)
                .first();
            return lineRecord?.SelectedAssets__c;
        } catch (Exception e) {
            throw toAuraException('getSavedSelection: unable to load the saved selection', qliId, e,
                                  'Unable to load the saved asset selection.');
        } finally {
            Logger.saveLog();
        }
    }

    private static String text(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static AssetRow toRow(Asset a) {
        AssetRow r = new AssetRow();
        r.id = a.Id;
        r.serialNumber = a.SerialNumber;
        r.name = a.Name;
        r.status = a.Status;
        r.accountId = a.AccountId;
        r.accountName = a.AssetAccountName_f__c;
        r.installDate = a.InstallDate;
        r.productLine = text(a.get('ProductLineCalculated__c'));
        r.subProductLine = text(a.get('SubProductLineCalculated__c'));
        r.productType = text(a.get('ProductTypeCalculated__c'));
        r.manufacturer = text(a.get('ManufacturerCalculated__c'));
        r.model = text(a.get('ModelCalculated__c'));
        // PFCL name from the asset's product; Asset.PFCL__c (formula) as the fallback.
        String pfclName = a.Product2?.PFCL__r?.Name;
        r.pfcl = String.isNotBlank(pfclName) ? pfclName : text(a.get('PFCL__c'));
        List<String> parts = new List<String>();
        if (String.isNotBlank(a.Street)) {
            parts.add(a.Street);
        }
        if (String.isNotBlank(a.City)) {
            parts.add(a.City);
        }
        String statePostal = String.join(
            new List<String>{ a.State == null ? '' : a.State, a.PostalCode == null ? '' : a.PostalCode }, ' '
        ).trim();
        if (String.isNotBlank(statePostal)) {
            parts.add(statePostal);
        }
        if (String.isNotBlank(a.Country)) {
            parts.add(a.Country);
        }
        r.address = String.join(parts, ', ');
        return r;
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