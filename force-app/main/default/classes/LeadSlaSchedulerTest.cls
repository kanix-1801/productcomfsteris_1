/**
 * @description Tests the hourly Lead SLA job.
 *              The Lead is inserted as the running user with a country code.
 * @author      Vinay
 * @date        2026-10-26
 */
@IsTest(SeeAllData=false)
private class LeadSlaSchedulerTest {

    /**
     * @description A due clock is marked Missed when the scheduled job runs, and the owner stays on the queue.
     */
    @IsTest
    static void executeMarksADueClockWithoutChangingTheOwner() {
        String token = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 6);
        Group regionalQueue = insertQueue('Lead_Country_Sla_Sch_' + token, 'SLA Schedule');
        LeadService.skipInsertTas = true;
        Id leadId = insertLead(token);
        System.runAs(runningUser()) {
            update new Lead(Id = leadId, OwnerId = regionalQueue.Id);
        }
        Lead_SLA__c clock = [SELECT Id FROM Lead_SLA__c WHERE Lead__c = :leadId];
        clock.DueAt__c = System.now().addMinutes(-5);
        System.runAs(runningUser()) {
            update clock;
        }

        new LeadSlaScheduler().execute(null);

        Assert.areEqual(
            LeadSlaService.MISSED,
            [SELECT Status__c FROM Lead_SLA__c WHERE Id = :clock.Id].Status__c
        );
        Assert.areEqual(regionalQueue.Id, [SELECT OwnerId FROM Lead WHERE Id = :leadId].OwnerId);
    }

    /**
     * @description Inserts a Lead queue. Kept outside runAs so it is not mixed with the Lead insert.
     * @param developerName Queue developer name. Must not already exist in the org.
     * @param label Queue label.
     * @return Inserted queue.
     */
    private static Group insertQueue(String developerName, String label) {
        Group queueRecord = new Group(Name = label, Type = 'Queue', DeveloperName = developerName);
        insert queueRecord;
        insert new QueueSobject(QueueId = queueRecord.Id, SobjectType = 'Lead');
        return queueRecord;
    }

    /**
     * @description Inserts a Sales Lead as the running user.
     * @param token Value used to keep the email unique.
     * @return Lead Id.
     */
    private static Id insertLead(String token) {
        Lead leadRecord = new Lead(
            FirstName = 'Ada',
            LastName = 'Schedule' + token,
            Company = 'Steris',
            CountryCode = 'US',
            Email = 'schedule.' + token + '@example.com',
            LeadSource = 'Web',
            Status = 'New'
        );
        System.runAs(runningUser()) {
            insert leadRecord;
        }
        return leadRecord.Id;
    }

    /**
     * @description The user the test is already running as.
     * @return Current user, without a User insert.
     */
    private static User runningUser() {
        return new User(Id = UserInfo.getUserId());
    }
}