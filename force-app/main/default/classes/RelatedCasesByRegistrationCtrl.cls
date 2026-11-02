/**
* @author PSL
* @date 19-02-2026
* @description controller class for displaying realted cases with same registration Number.
*/
public with sharing class RelatedCasesByRegistrationCtrl {
    
    
    /**
    * @description getSiblings method to display all the cases with ame registration Number.
    * @param caseId case ID from current case.
    * @return List
    */

    // Card (limited) —  returns up to 50 parent cases
    @AuraEnabled(cacheable=true)
    public static List<Case> getSiblings(Id caseId) {
        if (caseId == null) return new List<Case>();

        Case currentCase = [
            SELECT Id, RegistrationNumber__c
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];
        if (String.isBlank(currentCase.RegistrationNumber__c)) return new List<Case>();

        return [
            SELECT Id,
                   CaseNumber,
                   Subject,
                   Customer_Want_Date__c,
                   FirstNonPreInstallScheduledShipDate__c,
                   Status
            FROM Case
            WHERE RegistrationNumber__c = :currentCase.RegistrationNumber__c
              AND Id != :currentCase.Id
              AND ParentId = NULL 
              AND RecordType.Name = 'CBM Case'
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];
    }
    
     /**
    * @description getSiblings method to display all the cases with ame registration Number.
    * @param caseId case ID from current case.
    * @return List
    */
    // View All (full) — returns up to 2000 parent cases (same filter as the card)
    @AuraEnabled(cacheable=true)
    public static List<Case> getAllByRegistration(Id caseId) {
        if (caseId == null) return new List<Case>();

        Case currentCase = [
            SELECT Id, RegistrationNumber__c
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];
        if (String.isBlank(currentCase.RegistrationNumber__c)) return new List<Case>();

        return [
            SELECT Id,
                   CaseNumber,
                   Subject,
                   Customer_Want_Date__c,
                   FirstNonPreInstallScheduledShipDate__c,
                   Status
            FROM Case
            WHERE RegistrationNumber__c = :currentCase.RegistrationNumber__c
              AND Id != :currentCase.Id
              AND ParentId = NULL 
              AND RecordType.Name = 'CBM Case'
            ORDER BY CreatedDate DESC
            LIMIT 2000                          
        ];
    }
}