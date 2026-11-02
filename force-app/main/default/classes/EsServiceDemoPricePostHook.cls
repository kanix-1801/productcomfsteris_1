/**
 * ES Service Product Configurator: TEMPORARY DEMO post-hook.
 *
 * Runs AFTER the pricing procedure (add it as the last Apex section in the procedure plan),
 * so its prices aren't overwritten by the procedure's List Price step. For each line with
 * a Requested Number of PM Visits of 1-4, it sets the list price to a hard-coded amount.
 *
 * Remove this section from the procedure plan (or set DEMO_ENABLED = false) after the demo.
 * The real pricing comes from the PFCL Pricing decision table in the pricing procedure.
 */
global with sharing class EsServiceDemoPricePostHook implements RevSignaling.SignalingApexProcessor {

    private static final Boolean DEMO_ENABLED = true;

    // Requested Number of PM Visits -> list price
    private static final Map<Integer, Decimal> PRICE_BY_VISITS = new Map<Integer, Decimal>{
        1 => 1000,
        2 => 2000,
        3 => 3000,
        4 => 4000
    };

    // Price fields written on the line. Each is written separately, so if one doesn't exist
    // in this context definition, the others still apply (check the debug log).
    private static final List<String> UNIT_PRICE_FIELDS = new List<String>{ 'ListPrice', 'UnitPrice', 'NetUnitPrice' };
    private static final String TOTAL_PRICE_FIELD = 'NetTotalPrice';

    private static final String LOG_PREFIX = '[ESPC DemoPrice] ';

    public RevSignaling.TransactionResponse execute(RevSignaling.TransactionRequest request) {
        RevSignaling.TransactionResponse response = new RevSignaling.TransactionResponse();
        response.status = RevSignaling.TransactionStatus.SUCCESS;
        if (!DEMO_ENABLED) {
            response.message = 'Demo price post-hook disabled.';
            return response;
        }

        String contextId = request.ctxInstanceId;
        Context.IndustriesContext ctx = new Context.IndustriesContext();
        Integer linesPriced = 0;

        try {
            for (Object o : queryNodes(ctx, contextId, 'SalesTransactionItem')) {
                Map<String, Object> node = (Map<String, Object>) o;
                Map<String, Object> tags = (Map<String, Object>) node.get('tagValue');
                List<Object> dataPath = (List<Object>) node.get('dataPath');
                if (tags == null || dataPath == null || dataPath.size() < 3 || isDeleted(tags)) continue;

                if (linesPriced == 0) {
                    System.debug(LOG_PREFIX + 'Line tags available: ' + tags.keySet());
                }
                Integer visits = toInteger(findTag(tags, 'requestednumberofpmvisits'));
                if (visits == null || !PRICE_BY_VISITS.containsKey(visits)) continue;

                Decimal price = PRICE_BY_VISITS.get(visits);
                Decimal quantity = toDecimal(findTag(tags, 'quantity'));
                List<Object> path = new List<Object>{ dataPath.get(1), dataPath.get(2) };

                for (String field : UNIT_PRICE_FIELDS) {
                    write(ctx, contextId, path, field, price);
                }
                if (quantity != null) {
                    write(ctx, contextId, path, TOTAL_PRICE_FIELD, price * quantity);
                }
                linesPriced++;
                System.debug(LOG_PREFIX + 'Line ' + dataPath.get(2) + ': visits=' + visits + ', price=' + price);
            }
            response.message = 'Demo price post-hook: priced ' + linesPriced + ' line(s).';
        } catch (Exception e) {
            // Don't block pricing for a demo helper.
            System.debug(LoggingLevel.ERROR, LOG_PREFIX + e.getMessage() + '\n' + e.getStackTraceString());
            response.message = 'Demo price post-hook skipped: ' + e.getMessage();
        }
        return response;
    }

    private static void write(Context.IndustriesContext ctx, String contextId, List<Object> path, String field, Decimal value) {
        try {
            ctx.updateContextAttributes(new Map<String, Object>{
                'contextId' => contextId,
                'nodePathAndAttributes' => new List<Object>{
                    new Map<String, Object>{
                        'nodePath' => new Map<String, Object>{ 'dataPath' => path },
                        'attributes' => new List<Object>{
                            new Map<String, Object>{ 'attributeName' => field, 'attributeValue' => value }
                        }
                    }
                }
            });
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, LOG_PREFIX + 'Could not set ' + field + ': ' + e.getMessage());
        }
    }

    // Finds a tag on the node by name, ignoring case, underscores, and a trailing "__c".
    private static Object findTag(Map<String, Object> tags, String wanted) {
        for (String key : tags.keySet()) {
            String normalized = key.toLowerCase().removeEnd('__c').replaceAll('[^a-z0-9]', '');
            if (normalized == wanted) {
                Map<String, Object> t = (Map<String, Object>) tags.get(key);
                return t?.get('tagValue');
            }
        }
        return null;
    }

    private static List<Object> queryNodes(Context.IndustriesContext ctx, String contextId, String tag) {
        Map<String, Object> output = ctx.queryTags(new Map<String, Object>{
            'contextId' => contextId,
            'tags' => new List<String>{ tag }
        });
        Map<String, Object> queryResult = (Map<String, Object>) output?.get('queryResult');
        List<Object> nodes = (List<Object>) queryResult?.get(tag);
        return nodes == null ? new List<Object>() : nodes;
    }

    private static Boolean isDeleted(Map<String, Object> tags) {
        for (String tag : new List<String>{ 'LineItemPath', 'LineItem' }) {
            Map<String, Object> t = (Map<String, Object>) tags.get(tag);
            if (t != null && 'DELETED'.equals(t.get('dmlStatus'))) return true;
        }
        return false;
    }

    private static Decimal toDecimal(Object v) {
        if (v == null) return null;
        try {
            return Decimal.valueOf(String.valueOf(v));
        } catch (Exception e) {
            return null;
        }
    }

    private static Integer toInteger(Object v) {
        Decimal d = toDecimal(v);
        return d == null ? null : d.intValue();
    }
}