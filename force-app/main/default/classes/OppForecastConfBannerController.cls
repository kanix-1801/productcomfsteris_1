/**
 * @author Himanshu Chaurasia
 * @date 2026/09/09
 *
 * @description Apex controller for the Opportunity forecast confidence propagation banner LWC.
 */
public with sharing class OppForecastConfBannerController {
    @TestVisible
    private static Boolean forceExceptionForTest = false;

    /**
     * @description Returns banner visibility and applicable quotes for an Opportunity.
     * @param opportunityId Opportunity record Id.
     * @return Banner context for the UI.
     */
    @AuraEnabled(cacheable=true)
    public static OppForecastConfPropagateService.BannerContext getBannerContext(Id opportunityId) {
        try {
            if (Test.isRunningTest() && forceExceptionForTest == true) {
                throw new QueryException('Forced test exception for getBannerContext.');
            }

            return OppForecastConfPropagateService.getBannerContext(opportunityId);
        } catch (Exception exceptionValue) {
            ErrorLogger.logException(
                exceptionValue,
                'OppForecastConfBannerController',
                'getBannerContext'
            );
            throw new AuraHandledException('Unable to load the forecast confidence propagation banner.');
        }
    }

    /**
     * @description Propagates the pending forecast confidence to selected quotes.
     * @param opportunityId Opportunity record Id.
     * @param quoteIds Selected Quote Ids.
     */
    @AuraEnabled
    public static void propagateSelectedQuotes(Id opportunityId, List<Id> quoteIds) {
        try {
            if (Test.isRunningTest() && forceExceptionForTest == true) {
                throw new QueryException('Forced test exception for propagateSelectedQuotes.');
            }

            OppForecastConfPropagateService.propagateSelectedQuotes(opportunityId, quoteIds);
        } catch (AuraHandledException exceptionValue) {
            throw exceptionValue;
        } catch (Exception exceptionValue) {
            ErrorLogger.logException(
                exceptionValue,
                'OppForecastConfBannerController',
                'propagateSelectedQuotes'
            );
            throw new AuraHandledException('Unable to propagate forecast confidence to selected quotes.');
        }
    }

}