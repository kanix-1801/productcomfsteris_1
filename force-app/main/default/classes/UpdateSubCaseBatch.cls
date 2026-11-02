/**
 * @author PSL
 * @date 01-09-2026
 * @description Batch class to update sub cases for order lines
 */
global class UpdateSubCaseBatch implements Database.Batchable<SObject>, Database.Stateful {
    // Configuration key in CBM_Generic_Configuration__mdt
    private static final String CFG_KEY_CASE_ALL_STAGES = 'ProcessAllStagesFlag';
    
    /**
     * @description  It will update subcases for orderLines whoes case__c and SubCase__C lookup is blank
     * @param        orderNumbers - List of OrderNumber__c values (Text) for which cases and subcase need to be created.
     * @return       void     
     */
    global Database.QueryLocator start(Database.BatchableContext bc) {
        // Read configuration value for Process All Stages from CBM_Generic_Configuration__mdt  
        List<CBM_Generic_Configuration__mdt> cfgList = [
            SELECT Value__c
            FROM CBM_Generic_Configuration__mdt
            WHERE Key__c = :CFG_KEY_CASE_ALL_STAGES AND Is_Active__c = true
            LIMIT 1
        ];

        CBM_Generic_Configuration__mdt cfg = cfgList.isEmpty() ? null : cfgList[0];
        String processAllStagesFlag = cfg != null ? String.valueOf(cfg.Value__c) : 'false';
        String dynamicWhereClause = ' ';
        if(processAllStagesFlag.equalsIgnoreCase('false')){ 
            dynamicWhereClause = ' AND parentCase__r.status NOT IN (\'Closed\',\'Cancelled\') ';
        }
        String query = 'SELECT Id, OrderNumber__c, parentCase__c FROM Order WHERE parentCase__c != null '
        +dynamicWhereClause+' AND Id IN ( SELECT OrderId FROM OrderItem WHERE (Case__c != NULL AND SubCase__c != NULL) AND CreateSubcase__c != null )';

        return Database.getQueryLocator(query);
    }

    global void execute(Database.BatchableContext bc, List<Order> scope) {
        List<String> orderNumbers = new List<String>();
        for (Order ord : scope) {
            if (ord.OrderNumber__c != null) {
                orderNumbers.add(ord.OrderNumber__c);
            }
        }

        if (!orderNumbers.isEmpty()) {
            
            UpdateCaseHandler.evaluateAndUpdateCaseStatus(orderNumbers);
        }
    }

    global void finish(Database.BatchableContext bc) {

        System.debug('UpdateSubCaseBatch completed.');
      // CBM -152
         CBMCaseAutoCloseBatch autoCloseCase = new CBMCaseAutoCloseBatch();

        Database.executeBatch(autoCloseCase, 2);   
    }
}