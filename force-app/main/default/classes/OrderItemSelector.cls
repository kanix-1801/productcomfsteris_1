/**
 * @author PSL
 * @date 06-11-2026
 * @description Helper class for fetching records from Order Object.
 */
public with sharing class OrderItemSelector {

    /*
     * Used only by the test class to cover the exception block.
     */
    @TestVisible
    private static Boolean forceException = false;

    public static List<OrderItem> orderItemRecord(Id caseId) {

        try {

            /*
             * This condition runs only during unit testing.
             * It does not affect production execution.
             */
            if (Test.isRunningTest() && forceException) {
                throw new OrderItemSelectorException(
                    'Forced exception for test coverage'
                );
            }

            return [
                SELECT Id,
                       LineNumber__c,
                       Product2.ProductCode,
                       Product2.Description,
                       Quantity,
                       ScheduledDate__c,
                       ShipToAddressID__r.Street,
                       ShipToAddressID__r.City,
                       ShipToAddressID__r.State,
                       ShipToAddressID__r.PostalCode,
                       ShipToAddressID__r.Country
                FROM OrderItem
                WHERE OrderLineType__c = 'Trade In Lines'
                AND ScheduledDate__c != 2049-12-31
                AND Order.ParentCase__c = :caseId
                AND OrderLineStatus__c NOT IN ('Cancelled', 'Closed')
                AND OrderLineNumber__c != 0
                ORDER BY OrderLineNumber__c ASC
            ];

        } catch (Exception ex) {

            ErrorLogger.logException(
                ex,
                'OrderItemSelector',
                'orderItemRecord'
            );

            throw ex;
        }
    }

    /*
     * Custom exception used only to test the catch block.
     */
    public class OrderItemSelectorException extends Exception {
    }
}