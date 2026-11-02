/**
 * @author PSL
 * @date 11-25-2025
 * @description Controller for handling task quick actions
 */
public with sharing class TaskQuickActionController {
    
    /**
     * @description Retrieves a task by its ID
     * @param taskId The ID of the task to retrieve
     * @return Task object or null if not found
     */
    @AuraEnabled
    public static Task getTaskById(String taskId) {
        if (taskId != null) {
            try {
                return [SELECT Id, WhatId, EmailType__c FROM Task WHERE Id = :taskId LIMIT 1];
            } catch (Exception e) {
                ErrorLogger.logException(e, 'TaskQuickActionController', 'getTaskById');
                return null;
            }
        }
        return null;
    }
    
    /**
     * @description Updates the email type of a case
     * @param caseId The ID of the case to update
     * @param emailType The new email type to set
     */
    @AuraEnabled
    public static void updateCaseEmailType(String caseId, String emailType) {
        if (caseId != null && emailType != null && emailType != '') {
            try {
                
                Case existingCase = [SELECT EmailType__c FROM Case WHERE Id = :caseId LIMIT 1];
                if (existingCase.EmailType__c != emailType) {
                    
                    Case caseToUpdate = new Case(Id = caseId, EmailType__c = emailType);
                    update caseToUpdate;
                }
                 
            } catch (Exception e) {
                ErrorLogger.logException(e, 'TaskQuickActionController', 'updateCaseEmailType');
                
                throw e;
            }
        }
    }
    
  //CBM-119: Separate method to update Case Email Language field
   
    @AuraEnabled
    public static void updateCaseEmailLanguage(String caseId, String language) {
        if (String.isBlank(caseId) || String.isBlank(language)) {
            return;
        }
        try {
            // Query only the fields we need
            Case existingCase = [
                SELECT Id, EmailLanguage__c
                FROM Case
                WHERE Id = :caseId
                LIMIT 1
                FOR UPDATE
            ];
            
            // Update only if the value changed
            if (existingCase.EmailLanguage__c != language) {
                existingCase.EmailLanguage__c = language;
                update existingCase;
            }
        } catch (Exception e) {
            ErrorLogger.logException(e, 'TaskQuickActionController', 'updateCaseEmailLanguage');
            throw e;
        }
    }

}