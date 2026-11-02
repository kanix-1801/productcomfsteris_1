/**
 * ES Service Product Configurator: pricing pre-hook.
 *
 * Runs before the pricing procedure (as the Apex section of a procedure plan). For each
 * quote line, it reads the "OT Coverage" product attribute from the context and writes its
 * value to the line's OT_Coverage__c context field, so the pricing procedure can use it as
 * an input to the PFCL Pricing decision table. It runs on every pricing call, so the field
 * always reflects the attribute's current value.
 *
 * If a line has no OT Coverage attribute of its own, it uses the value from its bundle's
 * root line (e.g. ES Service Agreement), so it works wherever the attribute lives.
 */
global with sharing class EsServiceOtCoveragePreHook implements RevSignaling.SignalingApexProcessor {

    // Attribute name as configured in the catalog. Matching ignores case, spaces, and
    // underscores, so "OT Coverage", "OT_Coverage", and "OTCoverage" all match.
    private static final String ATTRIBUTE_NAME = 'OT Coverage';

    // Context attribute on the SalesTransactionItem node (mapped to QuoteLineItem.OT_Coverage__c).
    private static final String TARGET_FIELD = 'OT_Coverage__c';

    private static final String LOG_PREFIX = '[ESPC PreHook] ';

    public RevSignaling.TransactionResponse execute(RevSignaling.TransactionRequest request) {
        RevSignaling.TransactionResponse response = new RevSignaling.TransactionResponse();
        String contextId = request.ctxInstanceId;
        Context.IndustriesContext ctx = new Context.IndustriesContext();

        try {
            Map<String, String> valueByLine = readOtCoverageByLine(ctx, contextId);
            List<Map<String, Object>> updates = buildLineUpdates(ctx, contextId, valueByLine);

            if (updates.isEmpty()) {
                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = 'OT Coverage pre-hook: no updates needed.';
                return response;
            }

            ctx.updateContextAttributes(new Map<String, Object>{
                'contextId' => contextId,
                'nodePathAndAttributes' => updates
            });
            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'OT Coverage pre-hook: updated ' + updates.size() + ' line(s).';
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, LOG_PREFIX + e.getMessage() + '\n' + e.getStackTraceString());
            response.status = RevSignaling.TransactionStatus.FAILED;
            response.message = 'OT Coverage pre-hook failed: ' + e.getMessage();
        }
        return response;
    }

    /** Line context Id (QLI Id or ref_ Id) -> OT Coverage value, from SalesTransactionItemAttribute nodes. */
    private static Map<String, String> readOtCoverageByLine(Context.IndustriesContext ctx, String contextId) {
        Map<String, String> result = new Map<String, String>();
        List<Object> nodes = queryNodes(ctx, contextId, 'SalesTransactionItemAttribute');
        String wanted = normalize(ATTRIBUTE_NAME);
        Set<String> namesSeen = new Set<String>();

        for (Object o : nodes) {
            Map<String, Object> tags = (Map<String, Object>) ((Map<String, Object>) o).get('tagValue');
            if (tags == null) continue;
            String name = tagValue(tags, 'Attribute');
            if (name != null) namesSeen.add(name);
            if (name == null || normalize(name) != wanted) continue;

            String lineId = tagValue(tags, 'SalesTransactionItemAttrParent');
            if (lineId != null) {
                result.put(lineId, tagValue(tags, 'AttributeValue'));
            }
        }
        System.debug(LOG_PREFIX + 'Attribute names in context: ' + namesSeen);
        System.debug(LOG_PREFIX + 'OT Coverage by line: ' + result);
        return result;
    }

    /** One update per active line that has an OT Coverage value (its own, or its root line's). */
    private static List<Map<String, Object>> buildLineUpdates(
        Context.IndustriesContext ctx, String contextId, Map<String, String> valueByLine
    ) {
        List<Map<String, Object>> updates = new List<Map<String, Object>>();
        if (valueByLine.isEmpty()) return updates;

        for (Object o : queryNodes(ctx, contextId, 'SalesTransactionItem')) {
            Map<String, Object> node = (Map<String, Object>) o;
            Map<String, Object> tags = (Map<String, Object>) node.get('tagValue');
            List<Object> dataPath = (List<Object>) node.get('dataPath');
            if (tags == null || dataPath == null || dataPath.size() < 3) continue;
            if (isDeleted(tags)) continue;

            String lineId = tagValue(tags, 'LineItem');
            String linePath = tagValue(tags, 'LineItemPath');
            String value = valueByLine.get(lineId);
            if (value == null && linePath != null && linePath.contains('/')) {
                value = valueByLine.get(linePath.split('/')[0]); // root (bundle) line
            }
            if (value == null) continue;

            updates.add(new Map<String, Object>{
                'nodePath' => new Map<String, Object>{
                    'dataPath' => new List<Object>{ dataPath.get(1), dataPath.get(2) }
                },
                'attributes' => new List<Object>{
                    new Map<String, Object>{ 'attributeName' => TARGET_FIELD, 'attributeValue' => value }
                }
            });
        }
        return updates;
    }

    // ---------- helpers ----------

    private static List<Object> queryNodes(Context.IndustriesContext ctx, String contextId, String tag) {
        Map<String, Object> output = ctx.queryTags(new Map<String, Object>{
            'contextId' => contextId,
            'tags' => new List<String>{ tag }
        });
        Map<String, Object> queryResult = (Map<String, Object>) output?.get('queryResult');
        List<Object> nodes = (List<Object>) queryResult?.get(tag);
        return nodes == null ? new List<Object>() : nodes;
    }

    private static String tagValue(Map<String, Object> tags, String tag) {
        Map<String, Object> t = (Map<String, Object>) tags.get(tag);
        Object v = t?.get('tagValue');
        return v == null ? null : String.valueOf(v);
    }

    private static Boolean isDeleted(Map<String, Object> tags) {
        for (String tag : new List<String>{ 'LineItemPath', 'LineItem' }) {
            Map<String, Object> t = (Map<String, Object>) tags.get(tag);
            if (t != null && 'DELETED'.equals(t.get('dmlStatus'))) return true;
        }
        return false;
    }

    private static String normalize(String s) {
        return s == null ? null : s.toLowerCase().replaceAll('[^a-z0-9]', '');
    }
}