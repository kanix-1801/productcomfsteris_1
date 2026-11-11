/**
 * @description Tests for nurture follow-up Task creation on Lead.
 */
@IsTest(SeeAllData=false)
private class LeadNurtureFollowUpServiceTest {

    @IsTest
    static void createsTaskWhenStatusChangesToNurturingWithReminderDate() {
        Lead leadRecord = insertSalesLead();
        Lead previous = snapshot(leadRecord, 'New', null, null, null);
        Lead updated = snapshot(leadRecord, 'Nurturing', 'Customer Timing', null, Date.today().addDays(7));

        Test.startTest();
        LeadNurtureFollowUpService.apply(new List<Lead>{ updated }, new Map<Id, Lead>{ leadRecord.Id => previous });
        Test.stopTest();

        Task followUp = [
            SELECT Subject, ActivityDate, WhoId, OwnerId, IsReminderSet, Description, ReminderDateTime
            FROM Task
            WHERE WhoId = :leadRecord.Id
            LIMIT 1
        ];
        System.assertEquals(updated.Nurture_Reminder_Date__c, followUp.ActivityDate);
        System.assertEquals(leadRecord.Id, followUp.WhoId);
        System.assertEquals(true, followUp.IsReminderSet);
        System.assert(followUp.Subject.contains('Lead nurture follow-up'));
        System.assert(followUp.Description.contains('Customer Timing'));
    }

    @IsTest
    static void createsTaskWhenReminderDateChangesWhileNurturing() {
        Lead leadRecord = insertSalesLead();
        Lead previous = snapshot(leadRecord, 'Nurturing', 'Budget', null, Date.today().addDays(3));
        Lead updated = snapshot(leadRecord, 'Nurturing', 'Budget', null, Date.today().addDays(30));

        Test.startTest();
        LeadNurtureFollowUpService.apply(new List<Lead>{ updated }, new Map<Id, Lead>{ leadRecord.Id => previous });
        Test.stopTest();

        Task followUp = [
            SELECT ActivityDate
            FROM Task
            WHERE WhoId = :leadRecord.Id
            LIMIT 1
        ];
        System.assertEquals(updated.Nurture_Reminder_Date__c, followUp.ActivityDate);
    }

    @IsTest
    static void doesNotCreateTaskWithoutReminderDate() {
        Lead leadRecord = insertSalesLead();
        Lead previous = snapshot(leadRecord, 'New', null, null, null);
        Lead updated = snapshot(leadRecord, 'Nurturing', 'STERIS Timing', null, null);

        Test.startTest();
        LeadNurtureFollowUpService.apply(new List<Lead>{ updated }, new Map<Id, Lead>{ leadRecord.Id => previous });
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhoId = :leadRecord.Id]);
    }

    @IsTest
    static void includesDetailWhenNurtureReasonIsOther() {
        Lead leadRecord = insertSalesLead();
        Lead previous = snapshot(leadRecord, 'New', null, null, null);
        Lead updated = snapshot(leadRecord, 'Nurturing', 'Other', 'Call back in Q3', Date.today().addDays(14));

        Test.startTest();
        LeadNurtureFollowUpService.apply(new List<Lead>{ updated }, new Map<Id, Lead>{ leadRecord.Id => previous });
        Test.stopTest();

        Task followUp = [
            SELECT Description
            FROM Task
            WHERE WhoId = :leadRecord.Id
            LIMIT 1
        ];
        System.assert(followUp.Description.contains('Call back in Q3'));
    }

    @IsTest
    static void assignsTaskToRunningUserWhenLeadOwnerIsQueue() {
        Group queueRecord = new Group(
            Name = 'Nurture Queue Test',
            DeveloperName = 'Nurture_Queue_Test',
            Type = 'Queue'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert queueRecord;
            insert new QueueSObject(QueueId = queueRecord.Id, SObjectType = 'Lead');
        }

        Lead leadRecord = insertSalesLead();
        update new Lead(Id = leadRecord.Id, OwnerId = queueRecord.Id);
        leadRecord = [SELECT Id, OwnerId, LastName, Status FROM Lead WHERE Id = :leadRecord.Id];

        Lead previous = snapshot(leadRecord, 'New', null, null, null);
        Lead updated = snapshot(leadRecord, 'Nurturing', 'Budget', null, Date.today().addDays(10));
        updated.OwnerId = queueRecord.Id;

        Test.startTest();
        LeadNurtureFollowUpService.apply(new List<Lead>{ updated }, new Map<Id, Lead>{ leadRecord.Id => previous });
        Test.stopTest();

        Task followUp = [
            SELECT OwnerId
            FROM Task
            WHERE WhoId = :leadRecord.Id
            LIMIT 1
        ];
        System.assertEquals(UserInfo.getUserId(), followUp.OwnerId);
    }

    @IsTest
    static void doesNotCreateTaskWhenStatusIsNotNurturing() {
        Lead leadRecord = insertSalesLead();
        Lead previous = snapshot(leadRecord, 'New', null, null, null);
        Lead updated = snapshot(leadRecord, 'New', null, null, Date.today().addDays(5));

        Test.startTest();
        LeadNurtureFollowUpService.apply(new List<Lead>{ updated }, new Map<Id, Lead>{ leadRecord.Id => previous });
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhoId = :leadRecord.Id]);
    }

    private static Lead insertSalesLead() {
        String token = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 8);
        Lead leadRecord = new Lead(
            FirstName = 'Nurture',
            LastName = 'Test' + token,
            Company = 'Steris',
            CountryCode = 'US',
            Email = 'nurture.' + token + '@example.com',
            LeadSource = 'Web',
            Status = 'New'
        );
        insert leadRecord;
        return [
            SELECT Id, OwnerId, LastName, Status
            FROM Lead
            WHERE Id = :leadRecord.Id
        ];
    }

    private static Lead snapshot(
        Lead leadRecord,
        String status,
        String nurtureReason,
        String nurtureDetail,
        Date reminderDate
    ) {
        return new Lead(
            Id = leadRecord.Id,
            OwnerId = leadRecord.OwnerId,
            LastName = leadRecord.LastName,
            Status = status,
            NurtureReason__c = nurtureReason,
            NurtureDetail__c = nurtureDetail,
            Nurture_Reminder_Date__c = reminderDate
        );
    }
}