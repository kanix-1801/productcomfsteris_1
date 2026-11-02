/**
 * @description Creates a follow-up Task when a Lead enters Nurturing with a reminder date,
 *              or when the reminder date changes while the Lead remains in Nurturing.
 * @author      Cursor
 * @date        2026-10-26
 */
public with sharing class LeadNurtureFollowUpService {

    private static final String NURTURING_STATUS = 'Nurturing';
    private static final String TASK_STATUS = 'Not Started';
    private static final String TASK_PRIORITY = 'Normal';

    /**
     * @description Inserts nurture follow-up tasks for eligible Lead updates.
     * @param newLeads Leads after update.
     * @param oldLeads Leads before update.
     */
    public static void apply(List<Lead> newLeads, Map<Id, Lead> oldLeads) {
        List<Lead> eligibleLeads = new List<Lead>();
        Set<Id> ownerIds = new Set<Id>();
        for (Lead leadRecord : newLeads) {
            Lead previous = oldLeads.get(leadRecord.Id);
            if (previous == null || !shouldCreateTask(leadRecord, previous)) {
                continue;
            }
            eligibleLeads.add(leadRecord);
            if (leadRecord.OwnerId != null) {
                ownerIds.add(leadRecord.OwnerId);
            }
        }
        if (eligibleLeads.isEmpty()) {
            return;
        }

        Set<Id> queueOwnerIds = queueOwnerIds(ownerIds);
        Id runningUserId = UserInfo.getUserId();
        List<Task> tasksToInsert = new List<Task>();
        for (Lead leadRecord : eligibleLeads) {
            Id taskOwnerId = resolveTaskOwnerId(leadRecord.OwnerId, queueOwnerIds, runningUserId);
            tasksToInsert.add(buildTask(leadRecord, taskOwnerId));
        }
        insert tasksToInsert;
    }

    @TestVisible
    private static Boolean shouldCreateTask(Lead leadRecord, Lead previous) {
        if (leadRecord.Status != NURTURING_STATUS || leadRecord.Nurture_Reminder_Date__c == null) {
            return false;
        }
        Boolean movedToNurturing = previous.Status != NURTURING_STATUS && leadRecord.Status == NURTURING_STATUS;
        Boolean reminderChanged = leadRecord.Nurture_Reminder_Date__c != previous.Nurture_Reminder_Date__c;
        return movedToNurturing || reminderChanged;
    }

    @TestVisible
    private static Set<Id> queueOwnerIds(Set<Id> ownerIds) {
        Set<Id> queueOwnerIds = new Set<Id>();
        if (ownerIds.isEmpty()) {
            return queueOwnerIds;
        }
        for (Group queueRecord : [
            SELECT Id
            FROM Group
            WHERE Id IN :ownerIds
            AND Type = 'Queue'
        ]) {
            queueOwnerIds.add(queueRecord.Id);
        }
        return queueOwnerIds;
    }

    @TestVisible
    private static Id resolveTaskOwnerId(Id leadOwnerId, Set<Id> queueOwnerIds, Id runningUserId) {
        if (leadOwnerId == null || queueOwnerIds.contains(leadOwnerId)) {
            return runningUserId;
        }
        return leadOwnerId;
    }

    @TestVisible
    private static Task buildTask(Lead leadRecord, Id taskOwnerId) {
        Task followUpTask = new Task();
        followUpTask.WhoId = leadRecord.Id;
        followUpTask.OwnerId = taskOwnerId;
        followUpTask.Subject = 'Lead nurture follow-up: ' + leadRecord.LastName;
        followUpTask.ActivityDate = leadRecord.Nurture_Reminder_Date__c;
        followUpTask.Status = TASK_STATUS;
        followUpTask.Priority = TASK_PRIORITY;
        followUpTask.IsReminderSet = true;
        followUpTask.ReminderDateTime = DateTime.newInstance(
            leadRecord.Nurture_Reminder_Date__c,
            Time.newInstance(9, 0, 0, 0)
        );
        if (String.isNotBlank(leadRecord.NurtureReason__c)) {
            followUpTask.Description = 'Nurture reason: ' + leadRecord.NurtureReason__c;
            if (leadRecord.NurtureReason__c == 'Other' && String.isNotBlank(leadRecord.NurtureDetail__c)) {
                followUpTask.Description += '\nDetail: ' + leadRecord.NurtureDetail__c;
            }
        }
        return followUpTask;
    }
}