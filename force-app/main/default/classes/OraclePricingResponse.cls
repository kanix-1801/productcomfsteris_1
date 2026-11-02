/**
 * @author Sahithi PWC
 * @date 01-07-2026
 * @description #GC-3162,#GC-3294 Response DTO for Oracle Pricing integration.
 *              #GC-3317 Added Prospect/Boomi response parsing and mock support.
 */
public class OraclePricingResponse  {

    public static final String MESSAGE_KEY_SUCCESS = 'Success';

    public String sfOpportunityId;
    public String messageKey;
    public String errorCode;
    public List<PriceInfo> priceInfo;
    public Id prospectId;

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

    public static OraclePricingResponse parse(String body) {
        if (String.isBlank(body)) {
            return null;
        }

        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(body);
        Map<String, Object> outputParams = (Map<String, Object>) root.get('OutputParameters');

        if (outputParams == null) {
            outputParams = root;
        }

        OraclePricingResponse response = new OraclePricingResponse();
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

    public static OraclePricingResponse parseProspect(String body) {
        if (String.isBlank(body)) {
            return null;
        }

        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(body);
        OraclePricingResponse response = new OraclePricingResponse();
        response.sfOpportunityId = getString(root, 'opportunityId');
        response.prospectId = parseId(getString(root, 'prospectId'));
        response.priceInfo = new List<PriceInfo>();

        Object partNumbersObj = root.get('partNumbers');
        if (!(partNumbersObj instanceof List<Object>)) {
            return response;
        }

        for (Object itemObj : (List<Object>) partNumbersObj) {
            if (!(itemObj instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> row = (Map<String, Object>) itemObj;
            PriceInfo info = new PriceInfo();
            info.productPartNumber = getString(row, 'partNumber');
            info.messageKey = getString(row, 'messageKey');
            info.errorCode = getString(row, 'errorCode');
            info.oraclePriceListId = getString(row, 'oraclePriceListId');
            info.oraclePriceListName = getString(row, 'oraclePriceListName');
            info.currencyCode = getString(row, 'currency');
            info.listPrice = parseDecimal(getString(row, 'listPrice'));
            info.price = resolveUnitPrice(info);
            response.priceInfo.add(info);
        }

        return response;
    }

    public static Boolean isPricingSuccess(String itemMessageKey) {
        return isPricingSuccess(itemMessageKey, null);
    }

    public static Boolean isPricingSuccess(String itemMessageKey, String errorCode) {
        if (String.isNotBlank(errorCode)) {
            return errorCode.trim() == '0';
        }

        return String.isNotBlank(itemMessageKey)
            && itemMessageKey.equalsIgnoreCase(MESSAGE_KEY_SUCCESS);
    }

    public static Decimal resolveUnitPrice(PriceInfo info) {
        if (info == null) {
            return null;
        }

        if (info.price != null) {
            return info.price;
        }

        return info.listPrice;
    }

    public static Map<String, PriceInfo> buildPricingMap(
        OraclePricingResponse response,
        OraclePricingRequest request
    ) {
        Map<String, PriceInfo> pricingMap = new Map<String, PriceInfo>();

        if (response == null || response.priceInfo == null) {
            return pricingMap;
        }

        List<String> requestedPartNumbers = new List<String>();

        if (request != null && request.productPartNumbers != null) {
            for (OraclePricingRequest.ProductPartNumber product : request.productPartNumbers) {
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

    public static OraclePricingResponse getMockResponse(
        OraclePricingRequest request
    ) {
        OraclePricingResponse response = new OraclePricingResponse();
        response.sfOpportunityId = request.sfOpportunityId;
        response.messageKey = MESSAGE_KEY_SUCCESS;
        response.errorCode = '0';
        response.priceInfo = new List<PriceInfo>();

        Integer index = 0;

        if (request.productPartNumbers != null) {
            for (OraclePricingRequest.ProductPartNumber product : request.productPartNumbers) {
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

    public static OraclePricingResponse getMockProspectResponse(
        OraclePricingRequest request
    ) {
        OraclePricingResponse response = new OraclePricingResponse();
        response.sfOpportunityId = request.sfOpportunityId;
        response.prospectId = request.prospectId;
        response.priceInfo = new List<PriceInfo>();

        if (request.productPartNumbers == null) {
            return response;
        }

        Integer index = 0;
        Boolean singleItem = request.productPartNumbers.size() == 1;

        for (OraclePricingRequest.ProductPartNumber product : request.productPartNumbers) {
            PriceInfo info = new PriceInfo();
            info.productPartNumber = product.partNumber;
            info.oraclePriceListId = '6125';
            info.oraclePriceListName = 'USA HEALTHCARE';
            info.currencyCode = 'USD';

            // Single OLI should always price successfully; only even-index failures apply to multi-item batches.
            if (!singleItem && Math.mod(index, 2) == 0) {
                info.messageKey = 'Item not on pricelist';
                info.errorCode = '700';
                info.listPrice = null;
                info.price = null;
            } else {
                info.messageKey = MESSAGE_KEY_SUCCESS;
                info.errorCode = '0';
                info.listPrice = 63.61;
                info.price = 63.61;
            }

            response.priceInfo.add(info);
            index++;
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

        if (itemsTable instanceof Map<String, Object>) {
            addItemsFromWrapper(rows, ((Map<String, Object>) itemsTable).get('P_ITEMS_TBL_ITEM'));
            return rows;
        }

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
    private static Id parseId(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        try {
            return (Id) value;
        } catch (Exception ex) {
            return null;
        }
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