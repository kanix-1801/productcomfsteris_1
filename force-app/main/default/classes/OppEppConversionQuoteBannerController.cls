/**
 * @author Himanshu Chaurasia
 * @date 2026/10/14
 *
 * @description GC-3457 UC3 - Apex controller for the EPP conversion quote closure banner LWC.
 */
public with sharing class OppEppConversionQuoteBannerController {
    @AuraEnabled(cacheable=true)
    public static OppEppConversionQuoteService.BannerContext getBannerContext(Id opportunityId) {
        try {
            return OppEppConversionQuoteService.getBannerContext(opportunityId);
        } catch (Exception exceptionValue) {
            ErrorLogger.logException(
                exceptionValue,
                'OppEppConversionQuoteBannerController',
                'getBannerContext'
            );
            throw new AuraHandledException('Unable to load the EPP conversion quote closure banner.');
        }
    }

    @AuraEnabled
    public static void closeAllOpenQuotes(Id opportunityId) {
        try {
            OppEppConversionQuoteService.closeAllOpenQuotes(opportunityId);
        } catch (AuraHandledException exceptionValue) {
            throw exceptionValue;
        } catch (Exception exceptionValue) {
            ErrorLogger.logException(
                exceptionValue,
                'OppEppConversionQuoteBannerController',
                'closeAllOpenQuotes'
            );
            throw new AuraHandledException('Unable to close the related quotes.');
        }
    }

    @AuraEnabled
    public static void reconcileStaleBanner(Id opportunityId) {
        try {
            OppEppConversionQuoteService.reconcileStaleBanner(opportunityId);
        } catch (Exception exceptionValue) {
            ErrorLogger.logException(
                exceptionValue,
                'OppEppConversionQuoteBannerController',
                'reconcileStaleBanner'
            );
            throw new AuraHandledException('Unable to reconcile the EPP conversion quote closure banner.');
        }
    }

    @AuraEnabled
    public static void dismissBanner(Id opportunityId) {
        try {
            OppEppConversionQuoteService.dismissBanner(opportunityId);
        } catch (AuraHandledException exceptionValue) {
            throw exceptionValue;
        } catch (Exception exceptionValue) {
            ErrorLogger.logException(
                exceptionValue,
                'OppEppConversionQuoteBannerController',
                'dismissBanner'
            );
            throw new AuraHandledException('Unable to dismiss the EPP conversion quote closure banner.');
        }
    }
}