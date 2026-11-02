/**
 * @author Himanshu Chaurasia
 * @date 2026/07/29
 *
 * @description Sets Opportunity.IsForecastChangeNotificationPending__c when Quote or
 *              Quote Line Item forecast-related data changes.
 */
public with sharing class QuoteForecastChangeNotificationService {
    public static final String NOTIFICATION_MESSAGE =
        'Forecast information has changed. One or more associated quotes have been updated. ' +
        'Please review your Forecast Eligible quotes and Opportunity forecast amount.';

    private static final String CLASS_NAME = 'QuoteForecastChangeNotificationService';

    /**
     * @description Marks a single Opportunity as needing the forecast change banner.
     * @param opportunityId Opportunity record Id.
     */
    public static void markNotificationPending(Id opportunityId) {
        if (opportunityId == null) {
            return;
        }

        markNotificationsPending(new Set<Id>{ opportunityId });
    }

    /**
     * @description Marks multiple Opportunities as needing the forecast change banner.
     * @param opportunityIds Opportunity record Ids.
     */
    public static void markNotificationsPending(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return;
        }

        List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();

        for (Id opportunityId : opportunityIds) {
            if (opportunityId == null) {
                continue;
            }

            opportunitiesToUpdate.add(
                new Opportunity(
                    Id = opportunityId,
                    IsForecastChangeNotificationPending__c = true
                )
            );
        }

        if (opportunitiesToUpdate.isEmpty()) {
            return;
        }

        try {
            Database.SaveResult[] saveResults = Database.update(
                opportunitiesToUpdate,
                false,
                AccessLevel.SYSTEM_MODE
            );

            for (Database.SaveResult saveResult : saveResults) {
                if (saveResult.isSuccess()) {
                    continue;
                }

                List<String> errorMessages = new List<String>();
                for (Database.Error saveError : saveResult.getErrors()) {
                    errorMessages.add(saveError.getMessage());
                }

                throw new DmlException(String.join(errorMessages, ', '));
            }
        } catch (Exception exceptionValue) {
            ErrorLogger.logException(exceptionValue, CLASS_NAME, 'markNotificationsPending');
            throw exceptionValue;
        }
    }
}