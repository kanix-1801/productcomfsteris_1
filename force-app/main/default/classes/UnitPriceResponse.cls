/**
 * @author Sahithi PWC
 * @date 01-07-2026
 * @description  Unit Price Response DTO.
 *
 * Sample Response
 *
 * {
 *   "products":[
 *      {
 *          "opportunityLineItemId":"00kXXXXXXXXXXXX",
 *          "unitPriceValue":125.50,
 *          "contractValue":"TEST1234567890123"
 *      },
 *      {
 *          "opportunityLineItemId":"00kYYYYYYYYYYYY",
 *          "unitPriceValue":250.75,
 *          "contractValue":"TEST9876543210987"
 *      }
 *   ]
 * }
 */
public class UnitPriceResponse {

    /**
     * Opportunity Product pricing returned by TAS
     */
    public List<ProductPrice> products;

    /**
     * Product level response
     */
    public class ProductPrice {

        /**
         * Opportunity Line Item Id
         */
        public String opportunityLineItemId;

        /**
         * Unit Price returned by TAS
         */
        public Decimal unitPriceValue;

        /**
         * Contract Value returned by TAS
         * (Temporarily using String since
         * Contract__c is a Text(18) field)
         */
        public String contractValue;

    }

    /**
     * Parse Response JSON
     */
    public static UnitPriceResponse parse(
        String responseBody
    ) {

        if (String.isBlank(responseBody)) {
            return null;
        }

        return (UnitPriceResponse)
            JSON.deserialize(
                responseBody,
                UnitPriceResponse.class
            );
    }

    /**
     * Returns Map<OpportunityLineItemId, ProductPrice>
     */
    public Map<String, ProductPrice> getPriceMap() {

        Map<String, ProductPrice> result =
            new Map<String, ProductPrice>();

        if (products == null) {
            return result;
        }

        for (ProductPrice product : products) {

            result.put(
                product.opportunityLineItemId,
                product
            );
        }

        return result;
    }
    

}