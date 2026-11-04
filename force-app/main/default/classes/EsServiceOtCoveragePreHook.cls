/**
 * @author Chad Huffman
 * @date 2026/10/01
 *
 * @group ES Service Product Configurator
 *
 * @description
 * Pricing pre-hook, run before the pricing procedure (as the Apex section of a procedure plan). For each
 * quote line, it reads the "OT Coverage" product attribute from the context and writes its value to the
 * line's OT_Coverage__c context field, so the pricing procedure can use it as an input to the PFCL Pricing
 * decision table. It runs on every pricing call, so the field always reflects the attribute's current value.
 *
 * If a line has no OT Coverage attribute of its own, it uses the value from its bundle's root line
 * (e.g. ES Service Agreement), so it works wherever the attribute lives.
 */
global with sharing class EsServiceOtCoveragePreHook implements RevSignaling.SignalingApexProcessor {

    private static final String CLASS_NAME = 'EsServiceOtCoveragePreHook';
    private static final String SCENARIO = 'ES Service Product Configurator';
    private static final String LOGGER_TAG = 'ESPC';

    /**
     * @description Attribute name as configured in the catalog. Matching ignores case, spaces and
     *              underscores, so "OT Coverage", "OT_Coverage" and "OTCoverage" all match.
     */
    private static final String ATTRIBUTE_NAME = 'OT Coverage';

    /**
     * @description Context attribute on the SalesTransactionItem node (mapped to QuoteLineItem.OTCoverage__c).
     */
    private static final String TARGET_FIELD = 'OT_Coverage__c';

    private static final String CONTEXT_ID_KEY = 'contextId';
    private static final String DATA_PATH_KEY = 'dataPath';
    private static final String TAG_VALUE_KEY = 'tagValue';
    private static final String LINE_ITEM_TAG = 'LineItem';
    private static final String LINE_ITEM_PATH_TAG = 'LineItemPath';

    /**
     * @description Writes each line's OT Coverage attribute value to its OT_Coverage__c context field.
     * @param request Pricing signal request with the context instance Id
     * @return SUCCESS with the number of lines updated, or FAILED with the error message
     */
    public RevSignaling.TransactionResponse execute(RevSignaling.TransactionRequest request) {
        RevSignaling.TransactionResponse response = new RevSignaling.TransactionResponse();
        String contextId = request.ctxInstanceId;
        Context.IndustriesContext industriesContext = new Context.IndustriesContext();

        try {
            Map<String, String> otCoverageByLineIdMap = readOtCoverageByLine(
                queryNodes(industriesContext, contextId, 'SalesTransactionItemAttribute')
            );
            List<Map<String, Object>> lineUpdateList = otCoverageByLineIdMap.isEmpty()
                ? new List<Map<String, Object>>()
                : buildLineUpdates(
                      queryNodes(industriesContext, contextId, 'SalesTransactionItem'), otCoverageByLineIdMap
                  );

            if (lineUpdateList.isEmpty()) {
                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = 'OT Coverage pre-hook: no updates needed.';
                return response;
            }

            industriesContext.updateContextAttributes(new Map<String, Object>{
                CONTEXT_ID_KEY => contextId,
                'nodePathAndAttributes' => lineUpdateList
            });
            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'OT Coverage pre-hook: updated ' + lineUpdateList.size() + ' line(s).';
        } catch (Exception e) {
            Logger.setScenario(SCENARIO);
            Logger.error(CLASS_NAME + '.execute: OT Coverage pre-hook failed for context ' + contextId, e)
                  .addTag(LOGGER_TAG);
            response.status = RevSignaling.TransactionStatus.FAILED;
            response.message = 'OT Coverage pre-hook failed: ' + e.getMessage();
        } finally {
            Logger.saveLog();
        }
        return response;
    }

    /**
     * @description Reads the OT Coverage value of each line from the SalesTransactionItemAttribute nodes.
     * @param nodeList SalesTransactionItemAttribute nodes
     * @return Line context Id (QLI Id or ref_ Id) to OT Coverage value
     */
    @TestVisible
    private static Map<String, String> readOtCoverageByLine(List<Object> nodeList) {
        Map<String, String> otCoverageByLineIdMap = new Map<String, String>();
        String wantedName = normalize(ATTRIBUTE_NAME);
        Set<String> attributeNameSet = new Set<String>();

        for (Object nodeObject : nodeList) {
            Map<String, Object> tagByNameMap =
                (Map<String, Object>) ((Map<String, Object>) nodeObject).get(TAG_VALUE_KEY);
            if (tagByNameMap == null) {
                continue;
            }
            String attributeName = getTagValue(tagByNameMap, 'Attribute');
            if (attributeName != null) {
                attributeNameSet.add(attributeName);
            }
            if (attributeName == null || normalize(attributeName) != wantedName) {
                continue;
            }

            String lineId = getTagValue(tagByNameMap, 'SalesTransactionItemAttrParent');
            if (lineId != null) {
                otCoverageByLineIdMap.put(lineId, getTagValue(tagByNameMap, 'AttributeValue'));
            }
        }
        Logger.debug(CLASS_NAME + '.readOtCoverageByLine: attribute names in context: ' + attributeNameSet)
              .addTag(LOGGER_TAG);
        Logger.debug(CLASS_NAME + '.readOtCoverageByLine: OT Coverage by line: ' + otCoverageByLineIdMap)
              .addTag(LOGGER_TAG);
        return otCoverageByLineIdMap;
    }

    /**
     * @description Builds one update per active line that has an OT Coverage value (its own, or its
     *              root line's).
     * @param lineNodeList SalesTransactionItem nodes
     * @param otCoverageByLineIdMap Line context Id to OT Coverage value
     * @return Context attribute updates (nodePath + attributes) for updateContextAttributes
     */
    @TestVisible
    private static List<Map<String, Object>> buildLineUpdates(List<Object> lineNodeList,
                                                              Map<String, String> otCoverageByLineIdMap) {
        List<Map<String, Object>> lineUpdateList = new List<Map<String, Object>>();
        for (Object nodeObject : lineNodeList) {
            Map<String, Object> nodeMap = (Map<String, Object>) nodeObject;
            Map<String, Object> tagByNameMap = (Map<String, Object>) nodeMap.get(TAG_VALUE_KEY);
            List<Object> dataPathList = (List<Object>) nodeMap.get(DATA_PATH_KEY);
            if (tagByNameMap == null || dataPathList == null || dataPathList.size() < 3) {
                continue;
            }
            if (isDeleted(tagByNameMap)) {
                continue;
            }

            String lineId = getTagValue(tagByNameMap, LINE_ITEM_TAG);
            String linePath = getTagValue(tagByNameMap, LINE_ITEM_PATH_TAG);
            String otCoverage = otCoverageByLineIdMap.get(lineId);
            if (otCoverage == null && linePath != null && linePath.contains('/')) {
                otCoverage = otCoverageByLineIdMap.get(linePath.split('/')[0]); // root (bundle) line
            }
            if (otCoverage == null) {
                continue;
            }

            lineUpdateList.add(new Map<String, Object>{
                'nodePath' => new Map<String, Object>{
                    DATA_PATH_KEY => new List<Object>{ dataPathList.get(1), dataPathList.get(2) }
                },
                'attributes' => new List<Object>{
                    new Map<String, Object>{ 'attributeName' => TARGET_FIELD, 'attributeValue' => otCoverage }
                }
            });
        }
        return lineUpdateList;
    }

    /**
     * @description Queries the context nodes with the given tag.
     * @param industriesContext Context service
     * @param contextId Context instance Id
     * @param tag Node tag (e.g. SalesTransactionItem)
     * @return Matching nodes; empty when there are none
     */
    private static List<Object> queryNodes(Context.IndustriesContext industriesContext, String contextId,
                                           String tag) {
        Map<String, Object> outputMap = industriesContext.queryTags(new Map<String, Object>{
            CONTEXT_ID_KEY => contextId,
            'tags' => new List<String>{ tag }
        });
        Map<String, Object> queryResultMap = (Map<String, Object>) outputMap?.get('queryResult');
        List<Object> nodeList = (List<Object>) queryResultMap?.get(tag);
        return nodeList == null ? new List<Object>() : nodeList;
    }

    /**
     * @description Reads one tag's value from a node's tags.
     * @param tagByNameMap The node's tags
     * @param tag Tag name
     * @return The tag's value as text; null when the tag or its value is missing
     */
    private static String getTagValue(Map<String, Object> tagByNameMap, String tag) {
        Map<String, Object> tagMap = (Map<String, Object>) tagByNameMap.get(tag);
        Object value = tagMap?.get(TAG_VALUE_KEY);
        return value == null ? null : String.valueOf(value);
    }

    /**
     * @description Whether the line is being deleted in this transaction.
     * @param tagByNameMap The line node's tags
     * @return True when LineItemPath or LineItem has dmlStatus DELETED
     */
    private static Boolean isDeleted(Map<String, Object> tagByNameMap) {
        for (String tag : new List<String>{ LINE_ITEM_PATH_TAG, LINE_ITEM_TAG }) {
            Map<String, Object> tagMap = (Map<String, Object>) tagByNameMap.get(tag);
            if (tagMap != null && 'DELETED'.equals(tagMap.get('dmlStatus'))) {
                return true;
            }
        }
        return false;
    }

    /**
     * @description Lower-cases a name and strips everything but letters and digits, for loose matching.
     * @param value Name to normalize
     * @return Normalized name; null when the input is null
     */
    private static String normalize(String value) {
        return value == null ? null : value.toLowerCase().replaceAll('[^a-z0-9]', '');
    }
}