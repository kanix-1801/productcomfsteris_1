/**
 * @author Himanshu Chaurasia
 * @date 2026/10/14
 *
 * @description GC-3457 UC3 - Apex controller for the EPP conversion quote closure banner LWC.
 */
public with sharing class OppEppConversionQuoteBannerController {
    @TestVisible
    private static Boolean forceExceptionForTest = false;

    @AuraEnabled(cacheable=true)
    public static OppEppConversionQuoteService.BannerContext getBannerContext(Id opportunityId) {
        try {
            if (Test.isRunningTest() && forceExceptionForTest == true) {
                throw new QueryException('Forced test exception for getBannerContext.');
            }

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
            if (Test.isRunningTest() && forceExceptionForTest == true) {
                throw new QueryException('Forced test exception for closeAllOpenQuotes.');
            }

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
            if (Test.isRunningTest() && forceExceptionForTest == true) {
                throw new QueryException('Forced test exception for reconcileStaleBanner.');
            }

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
            if (Test.isRunningTest() && forceExceptionForTest == true) {
                throw new QueryException('Forced test exception for dismissBanner.');
            }

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