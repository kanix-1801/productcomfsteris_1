/**
 * ES Service Product Configurator: expands service product lines to one line per asset.
 *
 * Runs in the background after quote lines are saved (started by EsServiceQuoteLineTrigger).
 * For each bundle line with a selection in SelectedAssets__c, and each service product
 * under it:
 *   1. A line without an asset (the one the rep configured) becomes the first missing
 *      asset's line.
 *   2. For every other selected asset without a line, a copy of that product's template line
 *      is created: same fields and attributes, same bundle relationship, its own asset.
 *   3. Lines whose asset is no longer selected are deleted (only when the selection isn't
 *      empty, so clearing the list never wipes the bundle).
 * Requested visits: each new or assigned line gets the visits entered for its asset in the
 * PM Visits by Asset table (AssetVisits__c on the line it came from), otherwise 2.
 * Existing lines that already have a selected asset are never changed.
 * All changes for a quote go through one Place Sales Transaction call, with pricing.
 */
public with sharing class EsServiceLineExpansion implements Queueable {

    // Set while this process runs, so the lines it writes don't start it again.
    public static Boolean running = false;

    private static final Integer DEFAULT_VISITS = 2;

    private static final String F_SELECTION = 'SelectedAssets__c';
    private static final String F_ASSET = 'Asset__c';
    private static final String F_ASSET_NAME = 'AssetName__c';
    private static final String F_PFCL = 'PFCL__c';
    private static final String F_PFCL_NAME = 'PFCLName__c';
    private static final String F_VISITS = 'RequestedNumberofPMVisits__c';
    private static final String F_ASSET_VISITS = 'AssetVisits__c';

    // Fields never copied from the template line.
    private static final Set<String> SKIP_LINE_FIELDS = new Set<String>{
        'id', 'quoteid', 'linenumber', 'sortorder', 'opportunitylineitemid',
        'subtotal', 'totalprice', 'discount', 'listprice',
        'asset__c', 'assetname__c', 'pfcl__c', 'pfclname__c',
        'requestednumberofpmvisits__c', 'selectedassets__c', 'assetvisits__c'
    };

    private final Set<Id> quoteIds;

    public EsServiceLineExpansion(Set<Id> quoteIds) {
        this.quoteIds = quoteIds;
    }

    public void execute(QueueableContext context) {
        running = true;
        for (Id quoteId : quoteIds) {
            try {
                expandQuote(quoteId);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, '[ESPC Expand] quote ' + quoteId + ': ' + e.getMessage() + '\n' + e.getStackTraceString());
            }
        }
    }

    // ---------- Per quote ----------

    public static void expandQuote(Id quoteId) {
        List<SObject> lines = queryAll('QuoteLineItem', 'QuoteId = :recordId ORDER BY CreatedDate, Id', quoteId);
        Map<Id, SObject> lineById = new Map<Id, SObject>(lines);

        // Bundle (main) line -> child lines, from the bundle relationships.
        List<SObject> rels = queryAll(
            'QuoteLineRelationship',
            'AssociatedQuoteLineId IN (SELECT Id FROM QuoteLineItem WHERE QuoteId = :recordId)',
            quoteId
        );
        Map<Id, List<SObject>> relsByChild = new Map<Id, List<SObject>>();
        Map<Id, List<Id>> childrenByBundle = new Map<Id, List<Id>>();
        for (SObject rel : rels) {
            Id child = (Id) rel.get('AssociatedQuoteLineId');
            Id main = (Id) rel.get('MainQuoteLineId');
            if (!relsByChild.containsKey(child)) relsByChild.put(child, new List<SObject>());
            relsByChild.get(child).add(rel);
            if (!childrenByBundle.containsKey(main)) childrenByBundle.put(main, new List<Id>());
            childrenByBundle.get(main).add(child);
        }

        List<RevSalesTrxn.RecordWithReferenceRequest> records = new List<RevSalesTrxn.RecordWithReferenceRequest>();
        Map<Id, Asset> assets = new Map<Id, Asset>();
        Integer refCount = 0;
        Integer changes = 0;

        for (SObject bundle : lines) {
            List<Id> selected = parseIds((String) bundle.get(F_SELECTION));
            if (selected.isEmpty() || !childrenByBundle.containsKey(bundle.Id)) continue;
            assets.putAll(loadAssets(selected, assets.keySet()));
            Set<Id> selectedSet = new Set<Id>(selected);

            // Children of this bundle, grouped by product, in creation order.
            Map<Id, List<SObject>> byProduct = new Map<Id, List<SObject>>();
            for (SObject line : lines) {
                if (!childrenByBundle.get(bundle.Id).contains(line.Id)) continue;
                Id productId = (Id) line.get('Product2Id');
                if (!byProduct.containsKey(productId)) byProduct.put(productId, new List<SObject>());
                byProduct.get(productId).add(line);
            }

            for (Id productId : byProduct.keySet()) {
                List<SObject> productLines = byProduct.get(productId);
                Set<Id> covered = new Set<Id>();
                List<SObject> unassigned = new List<SObject>();
                List<SObject> removed = new List<SObject>();
                for (SObject line : productLines) {
                    Id assetId = (Id) line.get(F_ASSET);
                    if (assetId == null) unassigned.add(line);
                    else if (!selectedSet.contains(assetId)) removed.add(line);
                    else covered.add(assetId);
                }

                List<Id> missing = new List<Id>();
                for (Id a : selected) if (!covered.contains(a)) missing.add(a);

                // Template: the first line without an asset, otherwise the first line kept.
                SObject template = !unassigned.isEmpty() ? unassigned[0] : null;
                if (template == null) {
                    for (SObject line : productLines) {
                        if (!removed.contains(line)) { template = line; break; }
                    }
                }
                if (template == null) template = productLines[0];

                // 1. Lines without an asset take the first missing assets.
                for (SObject line : unassigned) {
                    if (missing.isEmpty()) break;
                    Id assetId = missing.remove(0);
                    Map<String, Object> values = assetValues(assets.get(assetId));
                    Integer entered = parseVisits((String) line.get(F_ASSET_VISITS)).get(assetId);
                    if (entered != null) values.put(F_VISITS, entered);
                    else if (line.get(F_VISITS) == null) values.put(F_VISITS, DEFAULT_VISITS);
                    RevSalesTrxn.RecordResource r = new RevSalesTrxn.RecordResource(
                        QuoteLineItem.getSObjectType(), 'PATCH', String.valueOf(line.Id));
                    r.fieldValues = values;
                    records.add(new RevSalesTrxn.RecordWithReferenceRequest('refUpd' + (refCount++), r));
                    changes++;
                }

                // 2. Copies of the template for the remaining missing assets.
                if (!missing.isEmpty()) {
                    List<SObject> attrs = queryAll('QuoteLineItemAttribute', 'QuoteLineItemId = :recordId', template.Id);
                    List<SObject> templateRels = relsByChild.containsKey(template.Id) ? relsByChild.get(template.Id) : new List<SObject>();
                    Map<Id, Integer> enteredVisits = parseVisits((String) template.get(F_ASSET_VISITS));
                    for (Id assetId : missing) {
                        String lineRef = 'refNew' + (refCount++);
                        Map<String, Object> values = copyFields(template, 'QuoteLineItem', SKIP_LINE_FIELDS);
                        values.put('QuoteId', '@{refQuote.id}');
                        values.putAll(assetValues(assets.get(assetId)));
                        values.put(F_VISITS, enteredVisits.containsKey(assetId) ? enteredVisits.get(assetId) : DEFAULT_VISITS);
                        RevSalesTrxn.RecordResource line = new RevSalesTrxn.RecordResource(QuoteLineItem.getSObjectType(), 'POST');
                        line.fieldValues = values;
                        records.add(new RevSalesTrxn.RecordWithReferenceRequest(lineRef, line));

                        for (SObject attr : attrs) {
                            Map<String, Object> av = copyFields(attr, 'QuoteLineItemAttribute', new Set<String>{ 'id', 'quotelineitemid' });
                            av.put('QuoteLineItemId', '@{' + lineRef + '.id}');
                            RevSalesTrxn.RecordResource r = new RevSalesTrxn.RecordResource(QuoteLineItemAttribute.getSObjectType(), 'POST');
                            r.fieldValues = av;
                            records.add(new RevSalesTrxn.RecordWithReferenceRequest('refAttr' + (refCount++), r));
                        }
                        for (SObject rel : templateRels) {
                            Map<String, Object> rv = copyFields(rel, 'QuoteLineRelationship', new Set<String>{ 'id', 'associatedquotelineid' });
                            rv.put('AssociatedQuoteLineId', '@{' + lineRef + '.id}');
                            RevSalesTrxn.RecordResource r = new RevSalesTrxn.RecordResource(QuoteLineRelationship.getSObjectType(), 'POST');
                            r.fieldValues = rv;
                            records.add(new RevSalesTrxn.RecordWithReferenceRequest('refRel' + (refCount++), r));
                        }
                        changes++;
                    }
                }

                // 3. Delete lines for assets no longer selected.
                for (SObject line : removed) {
                    RevSalesTrxn.RecordResource r = new RevSalesTrxn.RecordResource(
                        QuoteLineItem.getSObjectType(), 'DELETE', String.valueOf(line.Id));
                    records.add(new RevSalesTrxn.RecordWithReferenceRequest('refDel' + (refCount++), r));
                    changes++;
                }
            }
        }

        if (changes == 0) {
            System.debug('[ESPC Expand] quote ' + quoteId + ': nothing to change');
            return;
        }

        records.add(0, new RevSalesTrxn.RecordWithReferenceRequest(
            'refQuote', new RevSalesTrxn.RecordResource(Quote.getSObjectType(), 'PATCH', String.valueOf(quoteId))));

        System.debug('[ESPC Expand] quote ' + quoteId + ': ' + changes + ' line change(s), ' + records.size() + ' records');
        RevSalesTrxn.PlaceSalesTransactionResponse resp = RevSalesTrxn.PlaceSalesTransactionExecutor.execute(
            new RevSalesTrxn.GraphRequest('esServiceExpand', records),
            RevSalesTrxn.PricingPreferenceEnum.SYSTEM,
            RevSalesTrxn.ConfigurationExecutionEnum.SKIP,
            new RevSalesTrxn.ConfigurationOptionsInput(),
            null
        );
        System.debug('[ESPC Expand] response: ' + JSON.serialize(resp));
    }

    // ---------- Helpers ----------

    private static Map<String, Object> assetValues(Asset a) {
        Map<String, Object> values = new Map<String, Object>();
        values.put(F_ASSET, a?.Id);
        values.put(F_ASSET_NAME, a?.Name);
        values.put(F_PFCL, a?.Product2?.PFCL__c);
        values.put(F_PFCL_NAME, a?.Product2?.PFCL__r?.Name);
        return values;
    }

    private static Map<Id, Asset> loadAssets(List<Id> ids, Set<Id> alreadyLoaded) {
        Set<Id> toLoad = new Set<Id>(ids);
        toLoad.removeAll(alreadyLoaded);
        if (toLoad.isEmpty()) return new Map<Id, Asset>();
        return new Map<Id, Asset>([
            SELECT Id, Name, Product2.PFCL__c, Product2.PFCL__r.Name
            FROM Asset WHERE Id IN :toLoad WITH USER_MODE
        ]);
    }

    private static List<Id> parseIds(String raw) {
        List<Id> ids = new List<Id>();
        if (String.isBlank(raw)) return ids;
        try {
            for (Object o : (List<Object>) JSON.deserializeUntyped(raw)) {
                if (o != null) ids.add(Id.valueOf(String.valueOf(o)));
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, '[ESPC Expand] could not read selection: ' + e.getMessage());
        }
        return ids;
    }

    /** AssetVisits__c JSON ({ assetId: visits }) as a map; bad entries are skipped. */
    private static Map<Id, Integer> parseVisits(String raw) {
        Map<Id, Integer> visits = new Map<Id, Integer>();
        if (String.isBlank(raw)) return visits;
        try {
            Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(raw);
            for (String k : m.keySet()) {
                Object v = m.get(k);
                if (v == null) continue;
                try {
                    visits.put(Id.valueOf(k), Integer.valueOf(String.valueOf(v)));
                } catch (Exception entryError) {
                    // skip this entry
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, '[ESPC Expand] could not read asset visits: ' + e.getMessage());
        }
        return visits;
    }

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
            if (v instanceof Datetime) {
                v = ((Datetime) v).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
            } else if (v instanceof Date) {
                v = String.valueOf((Date) v);
            }
            values.put(d.getName(), v);
        }
        return values;
    }

    /** All createable fields (plus Id and CreatedDate) of an object, for a filter on :recordId. */
    private static List<SObject> queryAll(String objectName, String whereClause, Id recordId) {
        Set<String> names = new Set<String>{ 'Id' };
        for (Schema.SObjectField f : Schema.getGlobalDescribe().get(objectName).getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult d = f.getDescribe();
            if (d.isCreateable()) names.add(d.getName());
        }
        String soql = 'SELECT ' + String.join(new List<String>(names), ', ') + ' FROM ' + objectName + ' WHERE ' + whereClause;
        return Database.queryWithBinds(soql, new Map<String, Object>{ 'recordId' => recordId }, AccessLevel.USER_MODE);
    }
}