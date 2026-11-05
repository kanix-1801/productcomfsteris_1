/**
 * @author Himanshu Chaurasia
 * @date 2026/07/29
 *
 * @description Dismiss handling for the quote forecast change banner LWC.
 *              Banner visibility is controlled by FlexiPage component visibility rules.
 */
public without sharing class QuoteForecastChangeBannerController {
    @TestVisible
    private static Boolean forceExceptionForTest = false;

    /**
     * @description Clears the forecast change notification flag after user confirmation.
     * @param opportunityId Opportunity record Id from the record page.
     */
    @AuraEnabled
    public static void dismissNotification(Id opportunityId) {
        try {
            if (opportunityId == null) {
                return;
            }

            if (Test.isRunningTest() && forceExceptionForTest == true) {
                throw new DmlException('Forced test exception for dismissNotification.');
            }

            Database.update(
                new Opportunity(
                    Id = opportunityId,
                    IsForecastChangeNotificationPending__c = false
                ),
                false,
                AccessLevel.SYSTEM_MODE
            );
        } catch (Exception exceptionValue) {
            ErrorLogger.logException(exceptionValue, 'QuoteForecastChangeBannerController', 'dismissNotification');
            throw new AuraHandledException('Unable to dismiss the forecast change notification banner.');
        }
    }
}