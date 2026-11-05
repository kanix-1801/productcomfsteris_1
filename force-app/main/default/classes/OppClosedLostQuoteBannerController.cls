/**
 * @author Himanshu Chaurasia
 * @date 2026/09/09
 *
 * @description Apex controller for the Closed Lost quote closure banner LWC.
 */
public with sharing class OppClosedLostQuoteBannerController {
    @TestVisible
    private static Boolean forceExceptionForTest = false;

    @AuraEnabled(cacheable=true)
    public static OppClosedLostQuoteService.BannerContext getBannerContext(Id opportunityId) {
        try {
            if (Test.isRunningTest() && forceExceptionForTest == true) {
                throw new QueryException('Forced test exception for getBannerContext.');
            }

            return OppClosedLostQuoteService.getBannerContext(opportunityId);
        } catch (Exception exceptionValue) {
            ErrorLogger.logException(
                exceptionValue,
                'OppClosedLostQuoteBannerController',
                'getBannerContext'
            );
            throw new AuraHandledException('Unable to load the Closed Lost quote closure banner.');
        }
    }

    @AuraEnabled
    public static void closeAllOpenQuotes(Id opportunityId) {
        try {
            if (Test.isRunningTest() && forceExceptionForTest == true) {
                throw new QueryException('Forced test exception for closeAllOpenQuotes.');
            }

            OppClosedLostQuoteService.closeAllOpenQuotes(opportunityId);
        } catch (AuraHandledException exceptionValue) {
            throw exceptionValue;
        } catch (Exception exceptionValue) {
            ErrorLogger.logException(
                exceptionValue,
                'OppClosedLostQuoteBannerController',
                'closeAllOpenQuotes'
            );
            throw new AuraHandledException('Unable to close the related quotes.');
        }
    }

    @AuraEnabled
    public static void dismissBanner(Id opportunityId) {
        try {
            if (Test.isRunningTest() && forceExceptionForTest == true) {
                throw new QueryException('Forced test exception for dismissBanner.');
            }

            OppClosedLostQuoteService.dismissBanner(opportunityId);
        } catch (AuraHandledException exceptionValue) {
            throw exceptionValue;
        } catch (Exception exceptionValue) {
            ErrorLogger.logException(
                exceptionValue,
                'OppClosedLostQuoteBannerController',
                'dismissBanner'
            );
            throw new AuraHandledException('Unable to dismiss the Closed Lost quote closure banner.');
        }
    }
}