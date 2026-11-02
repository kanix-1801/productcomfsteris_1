/**
 * @author Sahithi PWC
 * @date 01-07-2026
 * @description #GC-3162 Request DTO for Oracle Pricing integration (Part2).
 */
public class OraclePricingRequestPart2 {

    private static final String PRICE_LIST_LEVEL = 'ST_ADDRESS';
    private static final String DISCOUNT_ACCOUNT = 'ST_ACCOUNT';

    public String sfOpportunityId;
    public String operatingUnit;
    public String shipToCustomerNumber;
    public String shipToAddressSiteId;
    public String accountType;
    public String priceListName;
    public String sourceSystem;
    public List<ProductPartNumber> productPartNumbers;

    // ONLY inner class — no classes inside this
    public class ProductPartNumber {
        public String partNumber;
        public Decimal quantity;

        public ProductPartNumber() {
        }

        public ProductPartNumber(String partNumber, Decimal quantity) {
            this.partNumber = partNumber;
            this.quantity = quantity;
        }
    }

    public Map<String, Object> toJsonMap() {
        List<Object> itemRows = new List<Object>();

        if (productPartNumbers != null) {
            for (ProductPartNumber product : productPartNumbers) {
                if (String.isBlank(product.partNumber)) {
                    continue;
                }
                itemRows.add(new Map<String, Object>{
                    'PARTNUMBER' => product.partNumber,
                    'QUANTITY' => String.valueOf(
                        product.quantity != null ? product.quantity.intValue() : 1
                    )
                });
            }
        }

        Map<String, Object> inputParameters = new Map<String, Object>{
            'P_OU_NAME' => null,
            'P_OU_ID' => operatingUnit,
            'P_ST_ACCT_NUM' => shipToCustomerNumber,
            'P_ST_ACCT_ID' => null,
            'P_ST_ACCT_SITE_ID' => shipToAddressSiteId,
            'P_ST_SITE_USE_ID' => null,
            'P_BT_ACCT_NUM' => null,
            'P_BT_ACCT_ID' => null,
            'P_BT_ACCT_SITE_ID' => null,
            'P_BT_SITE_USE_ID' => null,
            'P_PRICE_LIST_NAME' => accountType == 'Prospect' ? priceListName : null,
            'P_PRICE_LIST_ID' => null,
            'P_CURRENCY' => null,
            'P_PRICE_LIST_LEVEL' => PRICE_LIST_LEVEL,
            'P_DISCOUNT_ACCOUNT' => DISCOUNT_ACCOUNT,
            'P_ITEMS_TBL' => new List<Object>{
                new Map<String, Object>{ 'P_ITEMS_TBL_ITEM' => itemRows }
            },
            'P_PRICING_DATE' => null,
            'P_ORDER_SOURCE_NAME' => null,
            'P_SOURCE_SYSTEM' => sourceSystem
        };

        return new Map<String, Object>{ 'InputParameters' => inputParameters };
    }

    public String toJsonString() {
        List<String> itemJsonList = new List<String>();

        if (productPartNumbers != null) {
            for (ProductPartNumber product : productPartNumbers) {
                if (String.isBlank(product.partNumber)) {
                    continue;
                }
                String qty = String.valueOf(
                    product.quantity != null ? product.quantity.intValue() : 1
                );
                itemJsonList.add(
                    '{"PARTNUMBER":"' + escapeJson(product.partNumber) +
                    '","QUANTITY":"' + qty + '"}'
                );
            }
        }

        String prospectPriceListName =
            accountType == 'Prospect' ? priceListName : null;

        return '{' +
            '"InputParameters":{' +
            '"P_OU_NAME":null,' +
            '"P_OU_ID":' + jsonStringValue(operatingUnit) + ',' +
            '"P_ST_ACCT_NUM":' + jsonStringValue(shipToCustomerNumber) + ',' +
            '"P_ST_ACCT_ID":null,' +
            '"P_ST_ACCT_SITE_ID":' + jsonStringValue(shipToAddressSiteId) + ',' +
            '"P_ST_SITE_USE_ID":null,' +
            '"P_BT_ACCT_NUM":null,' +
            '"P_BT_ACCT_ID":null,' +
            '"P_BT_ACCT_SITE_ID":null,' +
            '"P_BT_SITE_USE_ID":null,' +
            '"P_PRICE_LIST_NAME":' + jsonStringValue(prospectPriceListName) + ',' +
            '"P_PRICE_LIST_ID":null,' +
            '"P_CURRENCY":null,' +
            '"P_PRICE_LIST_LEVEL":"' + PRICE_LIST_LEVEL + '",' +
            '"P_DISCOUNT_ACCOUNT":"' + DISCOUNT_ACCOUNT + '",' +
            '"P_ITEMS_TBL":[{"P_ITEMS_TBL_ITEM":[' +
                String.join(itemJsonList, ',') +
            ']}],' +
            '"P_PRICING_DATE":null,' +
            '"P_ORDER_SOURCE_NAME":null,' +
            '"P_SOURCE_SYSTEM":' + jsonStringValue(sourceSystem) +
            '}}';
    }

    // These methods go on OUTER class — NOT inside ProductPartNumber
    private static String jsonStringValue(String value) {
        return String.isBlank(value) ? 'null' : '"' + escapeJson(value) + '"';
    }

    private static String escapeJson(String value) {
        if (value == null) {
            return '';
        }
        return value.replace('\\', '\\\\').replace('"', '\\"');
    }
}