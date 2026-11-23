/**
 * @author PWC Developer
 * @date 2026/11/20
 *
 * @group Survey Management
 *
 * @description
 * GC-3506 AC16. Sends reminder emails for distributions whose reminder date has arrived.
 * Reminders use the original survey link and stop after a response, expiration, or survey deactivation.
 */
public with sharing class NpsSurveyReminderJob implements Schedulable, Database.Batchable<SObject> {

    public void execute(SchedulableContext context) {
        Database.executeBatch(new NpsSurveyReminderJob(), 50);
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, Email__c, Invitation_Link__c, Reminder_Dates__c, Response_Status__c,
                Survey_Distribution__c, Survey_Distribution__r.Reminders_Sent__c,
                Survey_Distribution__r.Reminder_Count__c, Survey_Distribution__r.Reminder_Interval_Days__c,
                Survey_Distribution__r.Expiration_Date__c, Survey_Distribution__r.Survey_Id__c,
                Survey_Distribution__r.Business_Unit__c, Survey_Distribution__r.Survey_Name__c
            FROM Survey_Distribution_Recipient__c
            WHERE Delivery_Status__c = 'Sent'
            AND Survey_Distribution__r.Distribution_Method__c = 'Email'
            AND Survey_Distribution__r.Next_Reminder_Date__c <= TODAY
            AND Survey_Distribution__r.Reminder_Count__c > 0
            AND (Survey_Distribution__r.Expiration_Date__c = null OR Survey_Distribution__r.Expiration_Date__c >= TODAY)
        ]);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        NpsSurveyDistributionService.sendDueReminders((List<Survey_Distribution_Recipient__c>) scope);
    }

    public void finish(Database.BatchableContext context) {
        return;
    }
}