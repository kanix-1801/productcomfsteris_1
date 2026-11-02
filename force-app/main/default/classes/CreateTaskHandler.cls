/**
 * @author PSL
 * @date 12-11-2025
 * @description Handler class to orchestrate task creation and SLA calculation for Orders, Order Lines, and Holds.
 *              Delegates to CreateTaskHelper for core logic.
 */
public with sharing class CreateTaskHandler {
    
    /**
     * @description Creates tasks for the given order numbers using CreateTaskHelper methods.
     * @param orderNumbers List of order numbers to process
     * @return void
     */
    public static void createTasksForOrder(List<String> orderNumbers){
        // Call CreateTaskHelper methods to create tasks
        CreateTaskHelper.createTasksForOrderNumber(orderNumbers);
    }
    
    /**
     * @description Creates tasks for order lines using CreateTaskHelper methods.
     * @param orderNumber Order number to process
     * @return void
     */
    public static void createTasksForOrderLine(String orderNumber){
        // Call CreateTaskHelper methods to create tasks for order lines
        CreateTaskHelper.createTasksForOrderLine(orderNumber);
    }
    
    /**
     * @description Creates tasks for Holds using CreateTaskHelper methods.
     * @param orderNumber Order number to process
     * @return void
     */
    public static void createTasksForHolds(String orderNumber){
        // Call CreateTaskHelper methods to create tasks for Holds
        CreateTaskHelper.createTasksForOrderAndOrderLineHold(orderNumber);
        CreateTaskHelper.createTasksForPhasewiseHolds(orderNumber);
    }
    
    /**
     * @description Calculates SLA for tasks related to order numbers using CreateTaskHelper methods.
     * @param orderNumbers List of order numbers to process
     * @return void
     */
    public static void calculateTaskSLA(List<String> orderNumbers){
        // Call CreateTaskHelper methods to calculate task SLA
        CreateTaskHelper.calculateTaskSLAs(orderNumbers);
    }

}