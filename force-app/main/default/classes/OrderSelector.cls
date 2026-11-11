/**
 * @author PSL
 * @date 06-11-2026
 * @description Helper class for fetching records from Order Object.
 */
public with sharing class OrderSelector {

    @TestVisible
    private static Boolean throwTestException = false;

    public static List<Order> orderRecord(Id caseId) {
        try {

            // Only for covering catch block from test class
            if (Test.isRunningTest() && throwTestException) {
                throw new OrderSelectorException('Forced exception for test');
            }

            List<Order> orderList = [
                SELECT Id,
                       FirstScheduledDateNonPreinstall__c
                FROM Order
                WHERE ParentCase__c = :caseId
            ];

            if (!orderList.isEmpty()) {
                return orderList;
            }

            return null;

        } catch (Exception ex) {

            ErrorLogger.logException(
                ex,
                'OrderSelector',
                'orderRecord'
            );

            throw ex;
        }
    }

    public class OrderSelectorException extends Exception {
    }
}