/**
 * @author Sahithi PWC
 * @date 01-07-2026
 * @description  Unit Price Request DTO.
 *GC-3162
 * Temporary Request
 *
 * {
 *   "opportunityLineItems":[
 *      {
 *          "opportunityLineItemId":"00kXXXXXXXXXXXX"
 *      },
 *      {
 *          "opportunityLineItemId":"00kYYYYYYYYYYYY"
 *      }
 *   ]
 * }
 */
public class UnitPriceRequest {

    public List<ProductRequest> opportunityLineItems;

    /**
     * Opportunity Product Request
     */
    public class ProductRequest {

        public String opportunityLineItemId;

    }

    /**
     * Build request from Opportunity Products
     */
    public static UnitPriceRequest fromOpportunityLines(
        List<OpportunityLineItem> lineItems
    ) {

        UnitPriceRequest request = new UnitPriceRequest();

        request.opportunityLineItems = new List<ProductRequest>();

        for (OpportunityLineItem oli : lineItems) {

            ProductRequest product = new ProductRequest();
            product.opportunityLineItemId = oli.Id;

            request.opportunityLineItems.add(product);
        }

        return request;
    }

    /**
     * JSON payload for SO_Callout
     */
    public Map<String, Object> toJsonMap() {

        List<Object> items = new List<Object>();

        for (ProductRequest p : opportunityLineItems) {

            items.add(
                new Map<String, Object>{
                    'opportunityLineItemId' => p.opportunityLineItemId
                }
            );
        }

        return new Map<String, Object>{
            'opportunityLineItems' => items
        };
    }
}