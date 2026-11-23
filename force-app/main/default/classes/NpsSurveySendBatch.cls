/**
 * @author PWC Developer
 * @date 2026/11/20
 *
 * @group Survey Management
 *
 * @description
 * GC-3506. Sends NPS invitations in groups of 200, which is within the Salesforce Surveys email limit of 300.
 */
public with sharing class NpsSurveySendBatch implements Database.Batchable<SObject> {

    private Id distributionId;

    public NpsSurveySendBatch(Id distributionId) {
        this.distributionId = distributionId;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, Email__c, Contact__c, First_Name__c, Delivery_Status__c, Failure_Reason__c
            FROM Survey_Distribution_Recipient__c
            WHERE Survey_Distribution__c = :distributionId
            AND Delivery_Status__c IN ('Pending', 'Failed')
        ]);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        Survey_Distribution__c distribution = [
            SELECT Id, Business_Unit__c, Survey_Id__c, Survey_Name__c, Expiration_Date__c,
                Reminder_Count__c, Reminder_Interval_Days__c, Reminders_Sent__c, Next_Reminder_Date__c,
                Approved_Nps_Survey__c
            FROM Survey_Distribution__c
            WHERE Id = :distributionId
            LIMIT 1
        ];
        NpsSurveyDistributionService.sendChunk(distribution, (List<Survey_Distribution_Recipient__c>) scope);
    }

    public void finish(Database.BatchableContext context) {
        NpsSurveyDistributionService.rollup(distributionId);
    }
}