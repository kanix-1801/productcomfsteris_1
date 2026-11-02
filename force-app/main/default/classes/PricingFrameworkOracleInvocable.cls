/**
 * @description GW-4585 Flow entry point for common Oracle pricing. Business logic lives in
 *              {@link PricingFrameworkService} so other interfaces can reuse it.
 * @group Pricing Framework
 */
public with sharing class PricingFrameworkOracleInvocable {
    /** @description Invocable request for execute_pricing. */
    public class Request {
        @InvocableVariable(label='Account Id' required=true)
        public Id accountId;

        @InvocableVariable(label='Bill To Account Id')
        public Id billToAccountId;

        @InvocableVariable(label='Workstream')
        public String workstream;

        @InvocableVariable(label='Pricing Line JSON')
        public String pricingLineJson;

        @InvocableVariable(label='Record Id')
        public Id recordId;
    }

    /** @description Invocable result with Oracle prices merged into pricing JSON. */
    public class Result {
        @InvocableVariable(label='Is Success')
        public Boolean isSuccess;

        @InvocableVariable(label='Error Message')
        public String errorMessage;

        @InvocableVariable(label='Pricing Data JSON')
        public String pricingDataJson;

        @InvocableVariable(label='Workstream')
        public String workstream;
    }

    /** @description Line payload accepted from quote and work order pricing flows. */
    public class PricingLine {
        public String lineId;
        public String productCode;
        public Decimal quantity;
        public String pricingSource;
        public Decimal listPrice;
        public Decimal oracleDiscountedPrice;
    }

    /**
     * @description Common Oracle pricing entry point used by the GW-4585 subflow.
     * @param requests Flow requests
     * @return Pricing JSON with Oracle list and discounted prices
     */
    @InvocableMethod(
        label='execute_pricing'
        description='Calls the common Oracle pricing API and returns pricing JSON for Salesforce Pricing.'
    )
    public static List<Result> executePricing(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        for (Request request : requests) {
            results.add(PricingFrameworkService.executePricing(request));
        }
        return results;
    }
}