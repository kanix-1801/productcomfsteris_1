/**
 * @author PSL
 * @date 11-26-2025
 * @description Helper class for Case trigger operations, specifically managing synchronization of child cases with parent case Customer_Want_Date__c values.
 */
public with sharing class CaseTriggerHelper {
    
    /**
     * @description Record type ID for Capital Line Sub Case
     */
    public static Id capitalLineRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Capital Line Sub Case').getRecordTypeId();
    
    /**
     * @description Record type ID for CBM Case
     */
    public static Id cbmCaseRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByName().get('CBM Case').getRecordTypeId();
    /**
     * @description Updates child cases with the same Customer_Want_Date__c as their parent when the parent case has a Customer_Want_Date__c change
     * @param newCases List of updated Case records
     * @param oldMap Map of old Case records keyed by ID
     * @param newMap Map of new Case records keyed by ID
     * @return void
     */
    public static void updateChildCasesWithParentWantDate(List<Case> newCases, Map<Id, Case> oldMap, Map<Id, Case> newMap) {
        // Get all updated cases that have a parent and have Customer_Want_Date__c changed
        Set<Id> parentCaseIds = new Set<Id>();
        
        for (Case parentCase : newCases) {
            if (parentCase.ParentId == null && parentCase.recordTypeId == cbmCaseRecordTypeId && parentCase.Customer_Want_Date__c != oldMap.get(parentCase.Id).Customer_Want_Date__c) {
                parentCaseIds.add(parentCase.Id);
            }
        }
        
        // If no parent cases were updated, exit early
        if (parentCaseIds.isEmpty()) {
            return;
        }
        
        // Find all child cases with record type "Capital Line" for these parent cases
        List<Case> childCasesToUpdate = [
            SELECT Id, Customer_Want_Date__c, ParentId 
            FROM Case 
            WHERE ParentId IN :parentCaseIds 
            AND RecordTypeId = :capitalLineRecordTypeId
            AND Status NOT IN ('Cancelled', 'Invoiced/Closed', 'Closed')
        ];
        
        // Prepare list of cases to update
        List<Case> casesToUpdate = new List<Case>();
        
        // Update child cases with the same Want Date as the parent
        for (Case childCase : childCasesToUpdate) {
            Case updatedCase = new Case(
                Id = childCase.Id,
                Customer_Want_Date__c = newMap.get(childCase.ParentId).Customer_Want_Date__c
            );
            casesToUpdate.add(updatedCase);
        }
        
        // Perform bulk update
        if (!casesToUpdate.isEmpty()) {
            update casesToUpdate;
        }
    }

    /**
     * @description Creates Schedule Check-In Tasks for Orders when a parent CBM Case
     *              transitions from a non NO-GO state to NO-GO.
     *              
     *              This method:
     *              - Runs only for parent CBM cases
     *              - Detects OverAll_GO_NOGODecision__c change to 'NO-GO'
     *              - Ensures related Order and Order Number exist
     *              - Invokes task creation and SLA calculation for affected Orders
     *
     * @param newCases List of updated Case records (Trigger.new)
     * @param oldMap   Map of old Case records keyed by Id (Trigger.oldMap)
     */
    
    Public static void createScheduleCheckInTask(List<Case> newCases, Map<Id, Case> oldMap){
        
        
        set<Id> paretnIdSet= new set<id>();        
        list<string> ordNumber= new list<string>();
            for (Case parentCase : newCases) {
                
                
         if ( !oldMap.containsKey(parentCase.Id)) {
                    continue;
                }
            
            if(
            parentCase.RecordTypeId == cbmCaseRecordTypeId &&
            oldMap.get(parentCase.id).OverAll_GO_NOGODecision__c != 'NO-GO' &&
            parentCase.OverAll_GO_NOGODecision__c == 'NO-GO' &&
            parentCase.order__c!=null) {  
               
            paretnIdSet.add(parentCase.order__c);
            
            
        }
    }
    
    if(!paretnIdSet.isEmpty()){
    
    list<order> ordList = [select id, orderNumber__C from order where id IN: paretnIdSet];
    
    if(!ordList.isEmpty()){
        for(order ord: ordList){
            if(!String.isBlank(ord.OrderNumber__c) ){
                ordNumber.add(ord.OrderNumber__c);
            }
        }
    }
    
    if(!ordNumber.isEmpty()){
        
        
        CreateTaskHandler.createTasksForOrder(ordNumber);
        CreateTaskHandler.calculateTaskSLA(ordNumber);
    }
    
}
}
}