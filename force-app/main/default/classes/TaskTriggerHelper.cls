/**
 * @author PSL
 * @date 01-20-2026
 * @description Helper class for preventing deletion from Non admin user.
 */
public class TaskTriggerHelper {
    
    
	Public static Id adminProfileId;
    Public static string taskRecordTypeId;
    public static Boolean bypassDeleteValidation = false; // CBM-609
    
 

    // Entry point from trigger (before delete)
    public static void preventTaskDeletion(List<Task> oldTasks) {
    /**
     * @description Prevents deletion of CBM Task record type tasks for non-admin users.
     * @param oldTasks List of Task records from trigger.old slated for deletion
     * @return void
     */
    
        try{
        taskRecordTypeId=Schema.SObjectType.Task.getRecordTypeInfosByDeveloperName().get('CBM_Task').getRecordTypeId();
        if (oldTasks == null || oldTasks.isEmpty()) return;
            
          // CBM-609  
            if (bypassDeleteValidation == true) {
                return;
            }


        // Resolve running user's profile once
        if (adminProfileId == null) {
            adminProfileId = [
                SELECT Id
                FROM Profile
                WHERE Name = 'System Administrator'
                LIMIT 1
            ].Id;
        }

        // If current user is admin, allow deletes
           
            if (UserInfo.getProfileId() == adminProfileId || bypassDeleteValidation == true) {
                return;
            }

       /* if (UserInfo.getProfileId() == adminProfileId) {
            return;
        }*/
        
        for (Task t : oldTasks) {
            if (t.RecordTypeId != null && taskRecordTypeId==t.RecordTypeId) {
                t.addError('You are not allowed to delete Tasks. Please contact your administrator.');
            }
        }
    }Catch(exception ex){
        ErrorLogger.logException(ex, 'TaskTriggerHelper', 'preventTaskDeletion');
            throw ex;
    }
    }
 // CBM-526    
    public static void restrictPriorityForNonAdmin(
        List<Task> newTasks,
        Map<Id, Task> oldMap,
        Boolean isInsert,
        Boolean isUpdate
    ) {
        try {
            if (newTasks == null || newTasks.isEmpty()) return;

            // Resolve admin profile once per transaction
            if (adminProfileId == null) {
                adminProfileId = [
                    SELECT Id
                    FROM Profile
                    WHERE Name = 'System Administrator'
                    LIMIT 1
                ].Id;
            }

            // Admin: always allow, do not touch bypass flag
            if (UserInfo.getProfileId() == adminProfileId) return;

            for (Task t : newTasks) {

                // One-time bypass: allow, then reset
                if (t.BypassValidation__c == true) {
                    t.BypassValidation__c = false;
                    continue;
                }

                // Match original behavior: no restriction on insert
                if (isInsert) {
                    continue;
                }

                // Update: restrict only if Priority changed
                if (isUpdate && oldMap != null && oldMap.containsKey(t.Id)) {
                    Task oldT = oldMap.get(t.Id);

                    // Safe compare (handles nulls)
                    if (String.valueOf(t.Priority) != String.valueOf(oldT.Priority)) {
                        t.Priority.addError('Urgency is not Editable for you');
                    }
                }
            }

        } catch (Exception ex) {
            ErrorLogger.logException(ex, 'TaskTriggerHelper', 'restrictPriorityForNonAdmin');
            throw ex;
        }
    }
    
    
}