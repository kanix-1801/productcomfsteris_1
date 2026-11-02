/**
 * Oracle ESB HTTP gateway for getPricingDetail. Uses Named Credential {@code Oracle_Pricing_API}.
 * Holds request/response DTOs and {@link OraclePricingGatewayException} as inner types per Apex file rules.
 * Response rows are built from JSON via {@code deserializeUntyped} (nested inners are not used with
 * {@code JSON.deserialize} in this org).
 * <p>Callouts run here; {@code Logger.*} calls buffer to Nebula until {@code OraclePricingService} runs
 * {@code Logger.saveLog} in a {@code finally} block, per
 * <a href="https://github.com/jongpie/NebulaLogger/wiki/Logging-in-Apex" target="_top">Nebula Apex logging</a>.
 * This class does not call {@code saveLog}.</p>
 * No SOQL/DML.
 *
 * @author Michal David (Uptima)
 */
public with sharing class OraclePricingGateway {
    private static final String CALLOUT_ENDPOINT = 'callout:Oracle_Pricing_API/getPricingDetail/';
    private static final Integer CALLOUT_TIMEOUT_MS = 20000;
    private static final Integer LOG_BODY_MAX_CHARS = 1000;

    /**
     * Integration failure (HTTP, validation, or JSON).
     */
    public class OraclePricingGatewayException extends Exception {
    }

    /**
     * Request root for getPricingDetail POST body.
     */
    public class GetPricingDetailRequestDto {
        public InputParametersDto InputParameters;
    }

    /**
     * Oracle getPricingDetail {@code InputParameters}. Property order here is not used for JSON: we emit
     * the wire format in document order via {@link #serializeGetPricingDetailRequest}.
     */
    public class InputParametersDto {
        public String P_OU_NAME;
        public String P_ST_ACCT_NUM;
        public String P_BT_ACCT_NUM;
        public String P_PRICE_LIST_LEVEL;
        public String P_DISCOUNT_ACCOUNT;
        public List<ItemsTableBlockDto> P_ITEMS_TBL;
        public String P_SOURCE_SYSTEM;
    }

    /**
     * One element of the {@code P_ITEMS_TBL} array; contains {@code P_ITEMS_TBL_ITEM} per Oracle API.
     */
    public class ItemsTableBlockDto {
        public List<LineItemRequestDto> P_ITEMS_TBL_ITEM;
    }

    /**
     * One part line inside {@code P_ITEMS_TBL_ITEM}.
     */
    public class LineItemRequestDto {
        public String PARTNUMBER;
    }

    /**
     * Response root; populated by {@link #parseResponseBody(String)}.
     */
    public class GetPricingDetailResponseDto {
        public OutputParametersDto OutputParameters;
    }

    /**
     * In-memory list of pricing lines. Populated from either {@code X_ITEMS_TBL} (flat) or
     * {@code P_ITEMS_TBL} / {@code P_ITEMS_TBL_ITEM} in the Oracle response wire format.
     */
    public class OutputParametersDto {
        public List<LineItemResponseDto> X_ITEMS_TBL;
    }

    /**
     * One pricing line; service maps {@code LIST_PRICE} to {@code OracleListPrice__c} and {@code PRICE} to
     * {@code OracleDiscountedPrice__c} / {@code UnitPrice}.
     */
    public class LineItemResponseDto {
        public String PARTNUMBER;
        public Decimal LIST_PRICE;
        public Decimal PRICE;
    }

    /**
     * POSTs {@code request} as JSON and returns a parsed response DTO.
     *
     * @param request {@code InputParameters} with {@code P_ST_ACCT_NUM}, {@code P_BT_ACCT_NUM}, and nested
     *     {@code P_ITEMS_TBL} / {@code P_ITEMS_TBL_ITEM} as per Oracle ESB (see {@link #validateRequest}).
     */
    public GetPricingDetailResponseDto sendGetPricingDetail(GetPricingDetailRequestDto request) {
        validateRequest(request);
        HttpRequest httpRequest = buildHttpRequest(request);
        String requestSnippet = truncateForLog(httpRequest.getBody());
        // WARN (not only DEBUG) so Nebula stores entries when org LoggerSettings cap at WARN
        Logger.warn('OraclePricingGateway.sendGetPricingDetail request=' + requestSnippet);
        // TODO(Oracle pricing): remove temporary System.debug — troubleshooting only
        System.debug(LoggingLevel.DEBUG, 'OraclePricingGateway.sendGetPricingDetail request=' + requestSnippet);
        Http http = new Http();
        try {
            HTTPResponse httpResponse = http.send(httpRequest);
            String responseBody = httpResponse != null ? httpResponse.getBody() : null;
            String responseSnippet = truncateForLog(responseBody);
            Logger.warn('OraclePricingGateway.sendGetPricingDetail response=' + responseSnippet);
            System.debug(LoggingLevel.DEBUG, 'OraclePricingGateway.sendGetPricingDetail response=' + responseSnippet);
            return parseSuccessResponse(httpResponse);
        } catch (OraclePricingGatewayException e) {
            throw e;
        } catch (CalloutException e) {
            Logger.error('OraclePricingGateway.sendGetPricingDetail callout', e);
            throw new OraclePricingGatewayException('Oracle pricing callout failed: ' + e.getMessage());
        } catch (Exception e) {
            Logger.error('OraclePricingGateway.sendGetPricingDetail', e);
            throw new OraclePricingGatewayException('Oracle pricing request failed: ' + e.getMessage());
        }
    }

    private void validateRequest(GetPricingDetailRequestDto request) {
        if (request == null) {
            throw new OraclePricingGatewayException('Request is required.');
        }
        if (request.InputParameters == null) {
            throw new OraclePricingGatewayException('InputParameters is required.');
        }
        InputParametersDto inputParams = request.InputParameters;
        if (String.isBlank(inputParams.P_OU_NAME)) {
            throw new OraclePricingGatewayException('P_OU_NAME is required.');
        }
        if (String.isBlank(inputParams.P_ST_ACCT_NUM)) {
            throw new OraclePricingGatewayException('P_ST_ACCT_NUM is required.');
        }
        if (String.isBlank(inputParams.P_BT_ACCT_NUM)) {
            throw new OraclePricingGatewayException('P_BT_ACCT_NUM is required.');
        }
        if (String.isBlank(inputParams.P_PRICE_LIST_LEVEL)) {
            throw new OraclePricingGatewayException('P_PRICE_LIST_LEVEL is required.');
        }
        if (String.isBlank(inputParams.P_DISCOUNT_ACCOUNT)) {
            throw new OraclePricingGatewayException('P_DISCOUNT_ACCOUNT is required.');
        }
        if (String.isBlank(inputParams.P_SOURCE_SYSTEM)) {
            throw new OraclePricingGatewayException('P_SOURCE_SYSTEM is required.');
        }
        if (inputParams.P_ITEMS_TBL == null || inputParams.P_ITEMS_TBL.isEmpty()) {
            throw new OraclePricingGatewayException('P_ITEMS_TBL is required.');
        }
        Boolean hasLines = false;
        for (ItemsTableBlockDto block : inputParams.P_ITEMS_TBL) {
            if (block == null || block.P_ITEMS_TBL_ITEM == null || block.P_ITEMS_TBL_ITEM.isEmpty()) {
                continue;
            }
            for (LineItemRequestDto line : block.P_ITEMS_TBL_ITEM) {
                if (line == null || String.isBlank(line.PARTNUMBER)) {
                    throw new OraclePricingGatewayException('P_ITEMS_TBL_ITEM lines must have PARTNUMBER.');
                }
            }
            hasLines = true;
        }
        if (!hasLines) {
            throw new OraclePricingGatewayException('P_ITEMS_TBL with P_ITEMS_TBL_ITEM lines is required.');
        }
    }

    private HttpRequest buildHttpRequest(GetPricingDetailRequestDto request) {
        HttpRequest httpRequest = new HttpRequest();
        httpRequest.setEndpoint(CALLOUT_ENDPOINT);
        httpRequest.setMethod('POST');
        httpRequest.setHeader('Content-Type', 'application/json; charset=UTF-8');
        httpRequest.setTimeout(CALLOUT_TIMEOUT_MS);
        httpRequest.setBody(serializeGetPricingDetailRequest(request));
        return httpRequest;
    }

    /**
     * Builds the JSON request body in the order defined by the Oracle ESB getPricingDetail API (Apex
     * {@code JSON.serialize} of public types sorts keys alphabetically, which is not acceptable here).
     */
    private String serializeGetPricingDetailRequest(GetPricingDetailRequestDto request) {
        InputParametersDto inputParams = request.InputParameters;
        System.JSONGenerator gen = System.JSON.createGenerator(false);
        gen.writeStartObject();
        gen.writeFieldName('InputParameters');
        gen.writeStartObject();
        gen.writeStringField('P_OU_NAME', inputParams.P_OU_NAME);
        gen.writeStringField('P_ST_ACCT_NUM', inputParams.P_ST_ACCT_NUM);
        gen.writeStringField('P_BT_ACCT_NUM', inputParams.P_BT_ACCT_NUM);
        gen.writeStringField('P_PRICE_LIST_LEVEL', inputParams.P_PRICE_LIST_LEVEL);
        gen.writeStringField('P_DISCOUNT_ACCOUNT', inputParams.P_DISCOUNT_ACCOUNT);
        gen.writeFieldName('P_ITEMS_TBL');
        gen.writeStartArray();
        if (inputParams.P_ITEMS_TBL != null) {
            for (ItemsTableBlockDto block : inputParams.P_ITEMS_TBL) {
                gen.writeStartObject();
                gen.writeFieldName('P_ITEMS_TBL_ITEM');
                gen.writeStartArray();
                if (block != null && block.P_ITEMS_TBL_ITEM != null) {
                    for (LineItemRequestDto line : block.P_ITEMS_TBL_ITEM) {
                        gen.writeStartObject();
                        if (line != null && String.isNotBlank(line.PARTNUMBER)) {
                            gen.writeStringField('PARTNUMBER', line.PARTNUMBER);
                        }
                        gen.writeEndObject();
                    }
                }
                gen.writeEndArray();
                gen.writeEndObject();
            }
        }
        gen.writeEndArray();
        gen.writeStringField('P_SOURCE_SYSTEM', inputParams.P_SOURCE_SYSTEM);
        gen.writeEndObject();
        gen.writeEndObject();
        return gen.getAsString();
    }

    private GetPricingDetailResponseDto parseSuccessResponse(HTTPResponse httpResponse) {
        Integer statusCode = httpResponse != null ? httpResponse.getStatusCode() : 0;
        String body = httpResponse != null ? httpResponse.getBody() : null;
        if (statusCode < 200 || statusCode >= 300) {
            Logger.error(
                'OraclePricingGateway.sendGetPricingDetail HTTP error status='
                    + String.valueOf(statusCode)
                    + ' body='
                    + truncateForLog(body)
            );
            throw new OraclePricingGatewayException(
                'Oracle pricing returned HTTP status ' + String.valueOf(statusCode)
            );
        }
        if (String.isBlank(body)) {
            Logger.error('OraclePricingGateway.sendGetPricingDetail empty response body');
            throw new OraclePricingGatewayException('Oracle pricing returned an empty response.');
        }
        return parseResponseBody(body);
    }

    private GetPricingDetailResponseDto parseResponseBody(String body) {
        Object parsedRoot;
        try {
            parsedRoot = JSON.deserializeUntyped(body);
        } catch (Exception e) {
            Logger.error('OraclePricingGateway.sendGetPricingDetail JSON parse', e);
            throw new OraclePricingGatewayException('Oracle pricing response could not be parsed.');
        }
        if (!(parsedRoot instanceof Map<String, Object>)) {
            throw new OraclePricingGatewayException('Oracle pricing response could not be parsed.');
        }
        Map<String, Object> root = (Map<String, Object>) parsedRoot;

        GetPricingDetailResponseDto result = new GetPricingDetailResponseDto();
        result.OutputParameters = new OutputParametersDto();
        result.OutputParameters.X_ITEMS_TBL = new List<LineItemResponseDto>();

        // JSON key casing can differ (ESB, proxies); use case-insensitive lookup
        Object outputParamsObj = getMapValueIgnoreCase(root, 'OutputParameters');
        if (outputParamsObj == null) {
            return result;
        }
        if (!(outputParamsObj instanceof Map<String, Object>)) {
            return result;
        }
        Map<String, Object> outputParams = (Map<String, Object>) outputParamsObj;
        assertNoOracleOutputError(outputParams);

        // Success payloads: legacy flat list in X_ITEMS_TBL, or (typical) P_ITEMS_TBL with P_ITEMS_TBL_ITEM
        List<LineItemResponseDto> lineRows = new List<LineItemResponseDto>();
        collectLinesFromXItemsTable(outputParams, lineRows);
        if (lineRows.isEmpty()) {
            collectLinesFromPItemsTable(outputParams, lineRows);
        }
        result.OutputParameters.X_ITEMS_TBL = lineRows;
        Logger.warn(
            'OraclePricingGateway.parseResponseBody: '
                + String.valueOf(lineRows.size())
                + ' line(s) (X_ITEMS_TBL and/or P_ITEMS_TBL/P_ITEMS_TBL_ITEM).'
        );
        return result;
    }

    private void collectLinesFromXItemsTable(
        Map<String, Object> outputParams,
        List<LineItemResponseDto> lineRows
    ) {
        Object tableObj = getMapValueIgnoreCase(outputParams, 'X_ITEMS_TBL');
        if (tableObj == null || !(tableObj instanceof List<Object>)) {
            return;
        }
        for (Object rowObj : (List<Object>) tableObj) {
            if (rowObj instanceof Map<String, Object>) {
                addLineFromPricingRowMap((Map<String, Object>) rowObj, lineRows);
            }
        }
    }

    /**
     * Oracle getPricingDetail success response nests rows under {@code P_ITEMS_TBL} and
     * {@code P_ITEMS_TBL_ITEM} (not always {@code X_ITEMS_TBL} as a flat array).
     */
    private void collectLinesFromPItemsTable(
        Map<String, Object> outputParams,
        List<LineItemResponseDto> lineRows
    ) {
        Object pItemsTbl = getMapValueIgnoreCase(outputParams, 'P_ITEMS_TBL');
        if (pItemsTbl == null) {
            return;
        }
        if (pItemsTbl instanceof Map<String, Object>) {
            addLinesFromPItemsTblItemNode((Map<String, Object>) pItemsTbl, lineRows);
            return;
        }
        if (pItemsTbl instanceof List<Object>) {
            for (Object blockObj : (List<Object>) pItemsTbl) {
                if (blockObj instanceof Map<String, Object>) {
                    addLinesFromPItemsTblItemNode((Map<String, Object>) blockObj, lineRows);
                }
            }
        }
    }

    private void addLinesFromPItemsTblItemNode(Map<String, Object> blockOrWrapper, List<LineItemResponseDto> lineRows) {
        Object itemsObj = getMapValueIgnoreCase(blockOrWrapper, 'P_ITEMS_TBL_ITEM');
        if (itemsObj == null || !(itemsObj instanceof List<Object>)) {
            return;
        }
        for (Object rowObj : (List<Object>) itemsObj) {
            if (rowObj instanceof Map<String, Object>) {
                addLineFromPricingRowMap((Map<String, Object>) rowObj, lineRows);
            }
        }
    }

    private void addLineFromPricingRowMap(Map<String, Object> row, List<LineItemResponseDto> lineRows) {
        if (row == null) {
            return;
        }
        Object rowErr = getMapValueIgnoreCase(row, 'ERRORCODE');
        if (rowErr != null) {
            String rowCode = String.valueOf(rowErr).trim();
            if (String.isNotBlank(rowCode) && !isSuccessErrorCodeToken(rowCode)) {
                return;
            }
        }
        LineItemResponseDto line = new LineItemResponseDto();
        Object partNum = getMapValueIgnoreCase(row, 'PARTNUMBER');
        line.PARTNUMBER = partNum != null ? String.valueOf(partNum) : null;
        line.LIST_PRICE = coalesceDecimal(getMapValueIgnoreCase(row, 'LIST_PRICE'));
        line.PRICE = coalesceDecimal(getMapValueIgnoreCase(row, 'PRICE'));
        if (String.isNotBlank(line.PARTNUMBER)) {
            lineRows.add(line);
        }
    }

    /**
     * The Oracle ESB often returns HTTP 200 with {@code P_ERRORMESSAGE} / {@code P_ERRORCODE} in
     * {@code OutputParameters} when the request is rejected (e.g. {@code MISSING_MANDATORY_PARAMETER}).
     * That must be surfaced to the user, not treated as an empty {@code X_ITEMS_TBL} / no part match.
     */
    private void assertNoOracleOutputError(Map<String, Object> outputParams) {
        if (outputParams == null || outputParams.isEmpty()) {
            return;
        }
        Object emObj = getMapValueIgnoreCase(outputParams, 'P_ERRORMESSAGE');
        String errMessage = emObj != null ? String.valueOf(emObj).trim() : null;
        Object errCodeObj = getMapValueIgnoreCase(outputParams, 'P_ERRORCODE');
        String errCode = errCodeObj != null ? String.valueOf(errCodeObj).trim() : null;
        if (String.isNotBlank(errMessage)) {
            String userMsg = errMessage;
            if (String.isNotBlank(errCode)) {
                userMsg += ' (Oracle error code ' + errCode + ')';
            }
            Logger.error('OraclePricingGateway: Oracle business error. ' + userMsg);
            throw new OraclePricingGatewayException(userMsg);
        }
        // Some responses omit P_ERRORMESSAGE but still return a non-zero error code.
        if (String.isNotBlank(errCode) && !isSuccessErrorCodeToken(errCode)) {
            Object keyObj = getMapValueIgnoreCase(outputParams, 'P_MESSAGEKEY');
            String key = keyObj != null ? String.valueOf(keyObj) : null;
            String userMsg = 'Oracle returned error code ' + errCode;
            if (String.isNotBlank(key)) {
                userMsg += ' — ' + key;
            }
            userMsg += '.';
            Logger.error('OraclePricingGateway: Oracle business error. ' + userMsg);
            throw new OraclePricingGatewayException(userMsg);
        }
    }

    private static Object getMapValueIgnoreCase(Map<String, Object> valueMap, String key) {
        if (valueMap == null || String.isBlank(key)) {
            return null;
        }
        if (valueMap.containsKey(key)) {
            return valueMap.get(key);
        }
        for (String k : valueMap.keySet()) {
            if (k != null && k.equalsIgnoreCase(key)) {
                return valueMap.get(k);
            }
        }
        return null;
    }

    /**
     * Treats common success tokens so we do not throw when only a zero success code is present.
     */
    private static Boolean isSuccessErrorCodeToken(String errCode) {
        return '0' == errCode
            || '00' == errCode
            || '000' == errCode;
    }

    private static Decimal coalesceDecimal(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        if (value instanceof Integer) {
            return Decimal.valueOf((Integer) value);
        }
        if (value instanceof Long) {
            return Decimal.valueOf((Long) value);
        }
        if (value instanceof Double) {
            return Decimal.valueOf((Double) value);
        }
        return Decimal.valueOf(String.valueOf(value));
    }

    private static String truncateForLog(String value) {
        if (String.isBlank(value)) {
            return '';
        }
        if (value.length() > LOG_BODY_MAX_CHARS) {
            return value.substring(0, LOG_BODY_MAX_CHARS);
        }
        return value;
    }
}