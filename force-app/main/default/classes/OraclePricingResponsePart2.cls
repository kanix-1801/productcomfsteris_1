/**
 * @author Sahithi PWC
 * @date 01-07-2026
 * @description #GC-3162 Response DTO for Oracle Pricing integration (Part2).
 *              Parses OutputParameters / P_ITEMS_TBL Oracle response.
 */
public class OraclePricingResponsePart2 {

    public static final String MESSAGE_KEY_SUCCESS = 'Success';

    public String sfOpportunityId;
    public String messageKey;
    public String errorCode;
    public List<PriceInfo> priceInfo;

    public class PriceInfo {
        public String productPartNumber;
        public String contractNumber;
        public Decimal price;
        public Decimal listPrice;
        public String messageKey;
        public String currencyCode;
        public String errorCode;
        public String uom;
        public String oraclePriceListId;
        public String oraclePriceListName;
    }

    public static OraclePricingResponsePart2 parse(String body) {
        if (String.isBlank(body)) {
            return null;
        }

        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(body);
        Map<String, Object> outputParams = (Map<String, Object>) root.get('OutputParameters');

        if (outputParams == null) {
            outputParams = root;
        }

        OraclePricingResponsePart2 response = new OraclePricingResponsePart2();
        response.messageKey = getString(outputParams, 'P_MESSAGEKEY');
        response.errorCode = getString(outputParams, 'P_ERRORCODE');
        response.priceInfo = new List<PriceInfo>();

        for (Map<String, Object> row : extractItemRows(outputParams)) {
            PriceInfo info = new PriceInfo();
            info.productPartNumber = getString(row, 'PARTNUMBER');
            info.messageKey = getString(row, 'MESSAGEKEY');
            info.currencyCode = getString(row, 'CURRENCY');
            info.errorCode = getString(row, 'ERRORCODE');
            info.uom = getString(row, 'UOM');
            info.oraclePriceListId = getString(row, 'ORACLEPRICELISTID');
            info.oraclePriceListName = getString(row, 'ORACLEPRICELISTNAME');
            info.price = parseDecimal(getString(row, 'PRICE'));
            info.listPrice = parseDecimal(getString(row, 'LIST_PRICE'));
            info.contractNumber = getString(row, 'ORACLEMODIFIERNUMBER');
            response.priceInfo.add(info);
        }

        return response;
    }

    public static Boolean isPricingSuccess(String itemMessageKey) {
        return String.isNotBlank(itemMessageKey)
            && itemMessageKey.equalsIgnoreCase(MESSAGE_KEY_SUCCESS);
    }

    public static Boolean isPricingFailure(String itemMessageKey) {
        if (String.isBlank(itemMessageKey)) {
            return true;
        }

        String normalizedKey = itemMessageKey.toLowerCase();
        return normalizedKey.contains('notin')
            || normalizedKey.contains('not in')
            || normalizedKey.contains('not found');
    }

    /**
     * Builds a PARTNUMBER -> PriceInfo map.
     * Falls back to request order when Oracle omits PARTNUMBER on failed items.
     */
    public static Map<String, PriceInfo> buildPricingMap(
        OraclePricingResponsePart2 response,
        OraclePricingRequestPart2 request
    ) {
        Map<String, PriceInfo> pricingMap = new Map<String, PriceInfo>();

        if (response == null || response.priceInfo == null) {
            return pricingMap;
        }

        List<String> requestedPartNumbers = new List<String>();

        if (request != null && request.productPartNumbers != null) {
            for (OraclePricingRequestPart2.ProductPartNumber product : request.productPartNumbers) {
                if (String.isNotBlank(product.partNumber)) {
                    requestedPartNumbers.add(product.partNumber);
                }
            }
        }

        for (Integer i = 0; i < response.priceInfo.size(); i++) {
            PriceInfo info = response.priceInfo[i];
            String partNumber = info.productPartNumber;

            if (String.isBlank(partNumber) && i < requestedPartNumbers.size()) {
                partNumber = requestedPartNumbers[i];
                info.productPartNumber = partNumber;
            }

            if (String.isNotBlank(partNumber)) {
                pricingMap.put(partNumber, info);
            }
        }

        return pricingMap;
    }

    public static OraclePricingResponsePart2 getMockResponse(
        OraclePricingRequestPart2 request
    ) {
        OraclePricingResponsePart2 response = new OraclePricingResponsePart2();
        response.sfOpportunityId = request.sfOpportunityId;
        response.messageKey = MESSAGE_KEY_SUCCESS;
        response.errorCode = '0';
        response.priceInfo = new List<PriceInfo>();

        Integer index = 0;

        if (request.productPartNumbers != null) {
            for (OraclePricingRequestPart2.ProductPartNumber product : request.productPartNumbers) {
                PriceInfo info = new PriceInfo();
                info.productPartNumber = product.partNumber;
                info.currencyCode = 'USD';
                info.contractNumber = '30881';
                info.oraclePriceListId = '6125';
                info.oraclePriceListName = 'USA HEALTHCARE';

                if (Math.mod(index, 2) == 0) {
                    info.messageKey = MESSAGE_KEY_SUCCESS;
                    info.errorCode = '0';
                    info.price = 130;
                } else {
                    info.messageKey = 'Item_Notin_Pricelist';
                    info.errorCode = '700';
                    info.price = null;
                }

                response.priceInfo.add(info);
                index++;
            }
        }

        return response;
    }

    @TestVisible
    private static List<Map<String, Object>> extractItemRows(
        Map<String, Object> outputParams
    ) {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();

        if (outputParams == null || !outputParams.containsKey('P_ITEMS_TBL')) {
            return rows;
        }

        Object itemsTable = outputParams.get('P_ITEMS_TBL');

        // Response shape: "P_ITEMS_TBL": { "P_ITEMS_TBL_ITEM": [ ... ] }
        if (itemsTable instanceof Map<String, Object>) {
            addItemsFromWrapper(rows, ((Map<String, Object>) itemsTable).get('P_ITEMS_TBL_ITEM'));
            return rows;
        }

        // Fallback if Oracle ever returns array wrapper like request payload
        if (itemsTable instanceof List<Object>) {
            for (Object wrapper : (List<Object>) itemsTable) {
                if (wrapper instanceof Map<String, Object>) {
                    addItemsFromWrapper(
                        rows,
                        ((Map<String, Object>) wrapper).get('P_ITEMS_TBL_ITEM')
                    );
                }
            }
        }

        return rows;
    }

    @TestVisible
    private static void addItemsFromWrapper(List<Map<String, Object>> rows, Object items) {
        if (items instanceof List<Object>) {
            for (Object item : (List<Object>) items) {
                if (item instanceof Map<String, Object>) {
                    rows.add((Map<String, Object>) item);
                }
            }
        } else if (items instanceof Map<String, Object>) {
            rows.add((Map<String, Object>) items);
        }
    }

    @TestVisible
    private static String getString(Map<String, Object> data, String key) {
        if (data == null || !data.containsKey(key) || data.get(key) == null) {
            return null;
        }
        return String.valueOf(data.get(key));
    }

    @TestVisible
    private static Decimal parseDecimal(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Decimal.valueOf(value.trim());
        } catch (Exception ex) {
            return null;
        }
    }
}