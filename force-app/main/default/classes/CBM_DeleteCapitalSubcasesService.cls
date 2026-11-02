/**
* @author PSL
* @date 12-03-2026
* @description This Apex service supports listing and deleting Capital Line Subcases for a parent Case, including task counts for UI display.
  It also deletes related Order-level Tasks and flags the parent Case when all Capital Subcases are removed.
*/
public without sharing class CBM_DeleteCapitalSubcasesService {

    /* ---------- DTO FOR UI ---------- */
    public class SubcaseRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public DateTime createdDate;
        @AuraEnabled public Integer taskCount;
        @AuraEnabled public String recordUrl;
    }
 /**
    * @description Fetches all Capital Line Subcases related to a given parent Case and prepares lightweight row data for UI display.
	  Each row includes case details, task count per subcase, and a direct record URL for navigation.
    * @param parentCaseId -- CBM Case 
    * @return List
    */
    /* ---------- FETCH CAPITAL SUBCASES ---------- */
    @AuraEnabled(cacheable=true)
    public static List<SubcaseRow> getCapitalSubcaseRows(Id parentCaseId) {
        if (parentCaseId == null) {
            return new List<SubcaseRow>();
        }

        List<Case> capitalSubcases = [
            SELECT Id, CaseNumber, Subject, Status, CreatedDate
            FROM Case
            WHERE ParentId = :parentCaseId
              AND RecordType.DeveloperName = 'Capital_Line_Sub_Case'
            ORDER BY CreatedDate ASC
        ];

        if (capitalSubcases.isEmpty()) {
            return new List<SubcaseRow>();
        }

        Set<Id> subcaseIds = new Set<Id>();
        for (Case c : capitalSubcases) {
            subcaseIds.add(c.Id);
        }

        Map<Id, Integer> taskCounts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT WhatId w, COUNT(Id) c
            FROM Task
            WHERE WhatId IN :subcaseIds
            GROUP BY WhatId
        ]) {
            taskCounts.put((Id)ar.get('w'), (Integer)ar.get('c'));
        }

        List<SubcaseRow> rows = new List<SubcaseRow>();
        for (Case c : capitalSubcases) {
            SubcaseRow r = new SubcaseRow();
            r.id = c.Id;
            r.caseNumber = c.CaseNumber;
            r.subject = c.Subject;
            r.status = c.Status;
            r.createdDate = c.CreatedDate;
            r.taskCount = taskCounts.get(c.Id);
            r.recordUrl = '/' + c.Id;
            rows.add(r);
        }
        return rows;
    }
 /**
    * @description Deletes all Capital Line Subcases for the specified parent Case and removes all Tasks associated with the related Order.
      If all Capital Subcases are deleted, it updates the parent Case to indicate capital subcases were fully removed.
    * @param parentCaseId -- CBM Case 
    * @return String
    */
    /* ---------- DELETE ALL CAPITAL SUBCASES ---------- */
    @AuraEnabled
    public static String deleteAllCapitalSubcases(Id parentCaseId, String reason) {
        if (parentCaseId == null) {
            throw new AuraHandledException('Parent Case Id is required.');
        }

        Case parentCase = [
            SELECT Id, Order__c
            FROM Case
            WHERE Id = :parentCaseId
            LIMIT 1
        ];

        Id orderId = parentCase.Order__c;

        List<Case> capitalSubcases = [
            SELECT Id
            FROM Case
            WHERE ParentId = :parentCaseId
              AND RecordType.DeveloperName = 'Capital_Line_Sub_Case'
        ];

        if (capitalSubcases.isEmpty()) {
            return 'No Capital Line Subcases found to delete.';
        }

        Set<Id> whatIds = new Set<Id>();
        whatIds.add(parentCaseId);

        for (Case c : capitalSubcases) {
            whatIds.add(c.Id);
        }
        if (orderId != null) {
            whatIds.add(orderId);
        }

        List<Task> tasksToDelete = [
            SELECT Id
            FROM Task
            WHERE WhatId IN :whatIds
        ];
        
        Database.delete(capitalSubcases, false);

        parentCase.put('isCapitalSubCaseDeleted__c', true);
        update parentCase;
        

        if (!tasksToDelete.isEmpty()) {
            TaskTriggerHelper.bypassDeleteValidation = true;
            Database.delete(tasksToDelete, false);
            TaskTriggerHelper.bypassDeleteValidation = false;
        }

        return 'Deleted ' + capitalSubcases.size()
            + ' Capital Line Subcase(s) and '
            + tasksToDelete.size() + ' related Task(s).';
    }
}