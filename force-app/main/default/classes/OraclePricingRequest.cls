/**
 * @author Sahithi PWC
 * @date 01-07-2026
 * @description #GC-3162,#GC-3294 Request DTO for Oracle Pricing integration.
 *              #GC-3317 Added Prospect/Boomi request payload support.
 *              GW-4585 service pricing can send generic call fields: operating unit name,
 *              bill-to account number, ST_ACCOUNT price list level, and BT_ACCOUNT discount.
 */
public class OraclePricingRequest {

    private static final String PRICE_LIST_LEVEL = 'ST_ADDRESS';
    private static final String DISCOUNT_ACCOUNT = 'ST_ACCOUNT';

    public String sfOpportunityId;
    public String operatingUnit;
    public String operatingUnitName;
    public String shipToCustomerNumber;
    public String shipToAddressSiteId;
    public String billToCustomerNumber;
    public String accountType;
    public String priceListName;
    public String genericPriceListLevel;
    public String genericDiscountAccount;
    public String sourceSystem;
    public List<ProductPartNumber> productPartNumbers;

    public Id prospectId;
    public String priceList;

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
            'P_OU_NAME' => operatingUnitName,
            'P_OU_ID' => operatingUnit,
            'P_ST_ACCT_NUM' => shipToCustomerNumber,
            'P_ST_ACCT_ID' => null,
            'P_ST_ACCT_SITE_ID' => shipToAddressSiteId,
            'P_ST_SITE_USE_ID' => null,
            'P_BT_ACCT_NUM' => billToCustomerNumber,
            'P_BT_ACCT_ID' => null,
            'P_BT_ACCT_SITE_ID' => null,
            'P_BT_SITE_USE_ID' => null,
            'P_PRICE_LIST_NAME' => accountType == 'Prospect' ? priceListName : null,
            'P_PRICE_LIST_ID' => null,
            'P_CURRENCY' => null,
            'P_PRICE_LIST_LEVEL' => resolvedPriceListLevel(),
            'P_DISCOUNT_ACCOUNT' => resolvedDiscountAccount(),
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
            '"P_OU_NAME":' + jsonStringValue(operatingUnitName) + ',' +
            '"P_OU_ID":' + jsonStringValue(operatingUnit) + ',' +
            '"P_ST_ACCT_NUM":' + jsonStringValue(shipToCustomerNumber) + ',' +
            '"P_ST_ACCT_ID":null,' +
            '"P_ST_ACCT_SITE_ID":' + jsonStringValue(shipToAddressSiteId) + ',' +
            '"P_ST_SITE_USE_ID":null,' +
            '"P_BT_ACCT_NUM":' + jsonStringValue(billToCustomerNumber) + ',' +
            '"P_BT_ACCT_ID":null,' +
            '"P_BT_ACCT_SITE_ID":null,' +
            '"P_BT_SITE_USE_ID":null,' +
            '"P_PRICE_LIST_NAME":' + jsonStringValue(prospectPriceListName) + ',' +
            '"P_PRICE_LIST_ID":null,' +
            '"P_CURRENCY":null,' +
            '"P_PRICE_LIST_LEVEL":"' + resolvedPriceListLevel() + '",' +
            '"P_DISCOUNT_ACCOUNT":"' + resolvedDiscountAccount() + '",' +
            '"P_ITEMS_TBL":[{"P_ITEMS_TBL_ITEM":[' +
                String.join(itemJsonList, ',') +
            ']}],' +
            '"P_PRICING_DATE":null,' +
            '"P_ORDER_SOURCE_NAME":null,' +
            '"P_SOURCE_SYSTEM":' + jsonStringValue(sourceSystem) +
            '}}';
    }

    public String toProspectJsonString() {
        List<String> partNumbers = new List<String>();

        if (productPartNumbers != null) {
            for (ProductPartNumber product : productPartNumbers) {
                if (String.isBlank(product.partNumber)) {
                    continue;
                }
                partNumbers.add(product.partNumber);
            }
        }

        return '{' +
            '"opportunityId":' + jsonStringValue(sfOpportunityId) + ',' +
            '"prospectId":' + jsonStringValue(String.valueOf(prospectId)) + ',' +
            '"priceList":' + jsonNumberValue(priceList) + ',' +
            '"sourceSystem":' + jsonStringValue(sourceSystem) + ',' +
            '"partNumbers":' + jsonStringValue(String.join(partNumbers, ',')) +
        '}';
    }

    private String resolvedPriceListLevel() {
        return String.isNotBlank(genericPriceListLevel) ? genericPriceListLevel : PRICE_LIST_LEVEL;
    }

    private String resolvedDiscountAccount() {
        return String.isNotBlank(genericDiscountAccount) ? genericDiscountAccount : DISCOUNT_ACCOUNT;
    }

    private static String jsonStringValue(String value) {
        return String.isBlank(value) ? 'null' : '"' + escapeJson(value) + '"';
    }

    private static String jsonNumberValue(String value) {
        if (String.isBlank(value)) {
            return 'null';
        }

        try {
            Decimal.valueOf(value.trim());
            return value.trim();
        } catch (Exception ex) {
            return 'null';
        }
    }

    private static String escapeJson(String value) {
        if (value == null) {
            return '';
        }
        return value.replace('\\', '\\\\').replace('"', '\\"');
    }
}