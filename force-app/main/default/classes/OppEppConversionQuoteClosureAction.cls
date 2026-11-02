/**
 * @author Himanshu Chaurasia
 * @date 2026/10/14
 *
 * @description GC-3457 UC3 - Invocable entry point for Convert Capital Opportunity to EPP flow.
 */
public with sharing class OppEppConversionQuoteClosureAction {
    public class FlowInput {
        @InvocableVariable(label='Opportunity Id' required=true)
        public Id opportunityId;
    }

    @InvocableMethod(
        label='Stage EPP conversion quote closure banner'
        description='Sets PendingEppConversionQuoteClosure__c when open Sales Connection quotes exist after Capital → EPP conversion.'
        category='Opportunity'
    )
    public static void stageBanner(List<FlowInput> inputs) {
        if (inputs == null) {
            return;
        }

        for (FlowInput inputRecord : inputs) {
            if (inputRecord == null || inputRecord.opportunityId == null) {
                continue;
            }

            OppEppConversionQuoteService.stageBannerAfterConversion(inputRecord.opportunityId);
        }
    }
}