/**
 * ES Service Product Configurator: PROOF OF CONCEPT.
 *
 * Copies one configured service product line (e.g. CHAMBER CLEANING under the dynamic
 * bundle) once, with all its attributes and its bundle relationship, and gives the copy a
 * different asset. Uses the Place Sales Transaction API (RevSalesTrxn), so pricing runs on
 * the new line.
 *
 * Fields are copied generically (every createable field that has a value), so the POC
 * doesn't depend on guessing field names. Run from Developer Console > Execute Anonymous:
 *
 *   System.debug(EsServiceLineCopyPoc.copyLineForAsset('0QL...template line', '02i...asset'));
 */
public with sharing class EsServiceLineCopyPoc {

    // Fields we never copy from the template line (set by the API, pricing, or replaced below).
    private static final Set<String> SKIP_LINE_FIELDS = new Set<String>{
        'id', 'quoteid', 'linenumber', 'sortorder', 'opportunitylineitemid',
        'subtotal', 'totalprice', 'discount', 'listprice'
    };

    // Per-asset fields on the copy.
    private static final String F_ASSET = 'Asset__c';
    private static final String F_ASSET_NAME = 'AssetName__c';
    private static final String F_PFCL = 'PFCL__c';
    private static final String F_PFCL_NAME = 'PFCLName__c';

    // Configuration SKIP keeps the copied attributes exactly as they are on the template.
    // Change to SYSTEM to have the configurator (and CML) process the new line.
    private static final RevSalesTrxn.ConfigurationExecutionEnum CONFIG_MODE =
        RevSalesTrxn.ConfigurationExecutionEnum.SKIP;
    private static final RevSalesTrxn.PricingPreferenceEnum PRICING_MODE =
        RevSalesTrxn.PricingPreferenceEnum.SYSTEM;

    public static String copyLineForAsset(Id templateLineId, Id assetId) {
        // ---- Template line ----
        SObject template = queryAll('QuoteLineItem', 'Id = :recordId', templateLineId)[0];
        Id quoteId = (Id) template.get('QuoteId');

        // ---- Asset details for the copy ----
        Asset asset = [
            SELECT Name, Product2.PFCL__c, Product2.PFCL__r.Name
            FROM Asset WHERE Id = :assetId WITH USER_MODE LIMIT 1
        ];

        List<RevSalesTrxn.RecordWithReferenceRequest> records = new List<RevSalesTrxn.RecordWithReferenceRequest>();

        // Quote (PATCH, no changes) so the new records can reference it.
        records.add(new RevSalesTrxn.RecordWithReferenceRequest(
            'refQuote',
            new RevSalesTrxn.RecordResource(Quote.getSObjectType(), 'PATCH', String.valueOf(quoteId))
        ));

        // ---- New quote line: copy of the template with the new asset ----
        Map<String, Object> lineValues = copyFields(template, 'QuoteLineItem', SKIP_LINE_FIELDS);
        lineValues.put('QuoteId', '@{refQuote.id}');
        lineValues.put(F_ASSET, assetId);
        lineValues.put(F_ASSET_NAME, asset.Name);
        lineValues.put(F_PFCL, asset.Product2?.PFCL__c);
        lineValues.put(F_PFCL_NAME, asset.Product2?.PFCL__r?.Name);
        RevSalesTrxn.RecordResource line = new RevSalesTrxn.RecordResource(QuoteLineItem.getSObjectType(), 'POST');
        line.fieldValues = lineValues;
        records.add(new RevSalesTrxn.RecordWithReferenceRequest('refNewLine', line));

        // ---- Attributes: one copy of each template attribute record ----
        Integer i = 0;
        for (SObject attr : queryAll('QuoteLineItemAttribute', 'QuoteLineItemId = :recordId', templateLineId)) {
            Map<String, Object> values = copyFields(attr, 'QuoteLineItemAttribute', new Set<String>{ 'id', 'quotelineitemid' });
            values.put('QuoteLineItemId', '@{refNewLine.id}');
            RevSalesTrxn.RecordResource r = new RevSalesTrxn.RecordResource(QuoteLineItemAttribute.getSObjectType(), 'POST');
            r.fieldValues = values;
            records.add(new RevSalesTrxn.RecordWithReferenceRequest('refAttr' + (i++), r));
        }

        // ---- Bundle relationship: same parent, pointing at the new line ----
        Integer j = 0;
        for (SObject rel : queryAll('QuoteLineRelationship', 'AssociatedQuoteLineId = :recordId', templateLineId)) {
            Map<String, Object> values = copyFields(rel, 'QuoteLineRelationship', new Set<String>{ 'id', 'associatedquotelineid' });
            values.put('AssociatedQuoteLineId', '@{refNewLine.id}');
            RevSalesTrxn.RecordResource r = new RevSalesTrxn.RecordResource(QuoteLineRelationship.getSObjectType(), 'POST');
            r.fieldValues = values;
            records.add(new RevSalesTrxn.RecordWithReferenceRequest('refRel' + (j++), r));
        }

        System.debug('[ESPC POC] records: ' + records.size() + ' (attributes ' + i + ', relationships ' + j + ')');
        System.debug('[ESPC POC] line values: ' + JSON.serialize(lineValues));

        RevSalesTrxn.GraphRequest graph = new RevSalesTrxn.GraphRequest('esServiceLineCopy', records);
        RevSalesTrxn.PlaceSalesTransactionResponse resp = RevSalesTrxn.PlaceSalesTransactionExecutor.execute(
            graph, PRICING_MODE, CONFIG_MODE, new RevSalesTrxn.ConfigurationOptionsInput(), null
        );
        String result = JSON.serialize(resp);
        System.debug('[ESPC POC] response: ' + result);
        return result;
    }

    // ---------- helpers ----------

    /** Every createable, non-null field value, except the ones listed in skip (lower case). */
    private static Map<String, Object> copyFields(SObject source, String objectName, Set<String> skip) {
        Map<String, Object> values = new Map<String, Object>();
        Map<String, Schema.SObjectField> fields = Schema.getGlobalDescribe().get(objectName).getDescribe().fields.getMap();
        Map<String, Object> populated = source.getPopulatedFieldsAsMap();
        for (String name : populated.keySet()) {
            Schema.SObjectField f = fields.get(name.toLowerCase());
            if (f == null || skip.contains(name.toLowerCase())) continue;
            Schema.DescribeFieldResult d = f.getDescribe();
            if (!d.isCreateable() || d.isCalculated() || d.isAutoNumber()) continue;
            Object v = populated.get(name);
            if (v == null) continue;
            // The API expects ISO 8601 text for dates and date/times.
            if (v instanceof Datetime) {
                v = ((Datetime) v).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
            } else if (v instanceof Date) {
                v = String.valueOf((Date) v);
            }
            System.debug('[ESPC POC] ' + objectName + '.' + d.getName() + ' = ' + v);
            values.put(d.getName(), v);
        }
        return values;
    }

    /** Query all createable fields of an object for a filter on :recordId. */
    private static List<SObject> queryAll(String objectName, String whereClause, Id recordId) {
        List<String> names = new List<String>();
        for (Schema.SObjectField f : Schema.getGlobalDescribe().get(objectName).getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult d = f.getDescribe();
            if (d.isCreateable() || d.getName() == 'Id') names.add(d.getName());
        }
        String soql = 'SELECT ' + String.join(names, ', ') + ' FROM ' + objectName + ' WHERE ' + whereClause;
        return Database.queryWithBinds(soql, new Map<String, Object>{ 'recordId' => recordId }, AccessLevel.USER_MODE);
    }
}