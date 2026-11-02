/**
 * @description Tests for Lead SLA clocks.
 *              Leads are inserted as the running user with a country code, because
 *              state and country picklists reject a free-text country.
 *              The Lead trigger handles one after-update per transaction, so a
 *              later owner or status change applies the SLA service directly.
 * @author      Vinay
 * @date        2026-10-13
 */
@IsTest(SeeAllData=false)
private class LeadSlaServiceTest {

    /**
     * @description A regional queue starts an 8 hour clock. Taking the Lead on time
     *              marks that clock Met and starts a 24 hour individual clock.
     */
    @IsTest
    static void regionalClockStopsWhenAUserTakesTheLead() {
        Group regionalQueue = insertQueue('Lead_Country_Sla_Test', 'SLA Regional Test');
        Id leadId = insertLead();

        changeOwner(leadId, regionalQueue.Id);
        Lead_SLA__c regionalClock = [
            SELECT Clock__c, Status__c, DueAt__c, StartedAt__c, Geography__c
            FROM Lead_SLA__c
            WHERE Lead__c = :leadId
        ];
        Assert.areEqual(LeadSlaService.REGIONAL, regionalClock.Clock__c);
        Assert.areEqual('Sla_Test', regionalClock.Geography__c);
        Assert.areEqual(LeadSlaService.RUNNING, regionalClock.Status__c);
        Assert.areEqual(
            BusinessCalendar.addWorkingMinutes(regionalClock.StartedAt__c, 8 * 60),
            regionalClock.DueAt__c
        );

        changeOwner(leadId, UserInfo.getUserId());
        Map<String, Lead_SLA__c> clocks = clocksByType(leadId);
        Assert.areEqual(LeadSlaService.MET, clocks.get(LeadSlaService.REGIONAL).Status__c);
        Assert.isNotNull(clocks.get(LeadSlaService.REGIONAL).PickedUpAt__c);
        Assert.areEqual(LeadSlaService.RUNNING, clocks.get(LeadSlaService.INDIVIDUAL).Status__c);
        Assert.areEqual(
            BusinessCalendar.addWorkingMinutes(clocks.get(LeadSlaService.INDIVIDUAL).StartedAt__c, 24 * 60),
            clocks.get(LeadSlaService.INDIVIDUAL).DueAt__c
        );
    }

    /**
     * @description Confirms Working meets the individual clock.
     */
    @IsTest
    static void workingStatusMeetsTheIndividualClock() {
        Group regionalQueue = insertQueue('Lead_Country_Sla_Status', 'SLA Status Test');
        Id leadId = insertLead();
        changeOwner(leadId, regionalQueue.Id);
        changeOwner(leadId, UserInfo.getUserId());

        changeStatus(leadId, 'Working');

        Lead_SLA__c individualClock = [
            SELECT Status__c
            FROM Lead_SLA__c
            WHERE Lead__c = :leadId
            AND Clock__c = :LeadSlaService.INDIVIDUAL
        ];
        Assert.areEqual(LeadSlaService.MET, individualClock.Status__c);
    }

    /**
     * @description Working set while the Lead is on a queue is stored when the individual clock starts.
     */
    @IsTest
    static void qualifyingStatusBeforePickupMeetsTheIndividualClock() {
        Group regionalQueue = insertQueue('Lead_Country_Sla_Early', 'SLA Early Status');
        Id leadId = insertLead();
        changeOwner(leadId, regionalQueue.Id);
        changeStatus(leadId, 'Working');
        changeOwner(leadId, UserInfo.getUserId());

        Lead_SLA__c individualClock = [
            SELECT Status__c, FirstQualifyingActionAt__c
            FROM Lead_SLA__c
            WHERE Lead__c = :leadId
            AND Clock__c = :LeadSlaService.INDIVIDUAL
        ];
        Assert.areEqual(LeadSlaService.MET, individualClock.Status__c);
        Assert.isNotNull(individualClock.FirstQualifyingActionAt__c);
    }

    /**
     * @description Confirms a due regional clock is breached and the Lead owner stays on the queue.
     */
    @IsTest
    static void dueQueueClockIsMissedWithoutReassignment() {
        Group regionalQueue = insertQueue('Lead_Country_Sla_Due', 'SLA Due Test');
        Id leadId = insertLead();
        changeOwner(leadId, regionalQueue.Id);
        Lead_SLA__c clock = [SELECT Id FROM Lead_SLA__c WHERE Lead__c = :leadId];
        clock.DueAt__c = System.now().addMinutes(-5);
        updateAsUser(clock);

        markDueClocks();

        Assert.areEqual(LeadSlaService.MISSED, [SELECT Status__c FROM Lead_SLA__c WHERE Id = :clock.Id].Status__c);
        Assert.areEqual(regionalQueue.Id, [SELECT OwnerId FROM Lead WHERE Id = :leadId].OwnerId);
    }

    /**
     * @description A late Working stays Missed, and the ultimate queue starts a new regional clock.
     */
    @IsTest
    static void lateDispositionStaysMissedAndReassignmentRestartsTheClock() {
        Group regionalQueue = insertQueue('Lead_Country_Sla_Late', 'SLA Late Test');
        Id leadId = insertLead();
        changeOwner(leadId, regionalQueue.Id);
        changeOwner(leadId, UserInfo.getUserId());
        Lead_SLA__c individualClock = [
            SELECT Id
            FROM Lead_SLA__c
            WHERE Lead__c = :leadId
            AND Clock__c = :LeadSlaService.INDIVIDUAL
        ];
        individualClock.DueAt__c = System.now().addMinutes(-5);
        updateAsUser(individualClock);

        changeStatus(leadId, 'Working');
        Assert.areEqual(LeadSlaService.MISSED, [SELECT Status__c FROM Lead_SLA__c WHERE Id = :individualClock.Id].Status__c);

        Group nextQueue = insertQueue('Lead_Sla_Ultimate_Test', 'SLA Ultimate Test');
        LeadSlaService.ultimateQueue = 'Lead_Sla_Ultimate_Test';
        changeOwner(leadId, nextQueue.Id);
        Lead_SLA__c queueClock = [
            SELECT Clock__c, Status__c, DueAt__c, StartedAt__c, Geography__c
            FROM Lead_SLA__c
            WHERE Lead__c = :leadId
            AND Status__c = :LeadSlaService.RUNNING
        ];
        Assert.areEqual(LeadSlaService.REGIONAL, queueClock.Clock__c);
        Assert.areEqual('Ultimate', queueClock.Geography__c);
        Assert.areEqual(
            BusinessCalendar.addWorkingMinutes(queueClock.StartedAt__c, 8 * 60),
            queueClock.DueAt__c
        );
    }

    /**
     * @description The Sales Development queue gets a 2 hour clock.
     */
    @IsTest
    static void salesDevelopmentClockIsTwoHours() {
        String queueName = uniqueQueueName('Lead_Sla_Sd');
        Group salesQueue = insertQueue(queueName, 'SLA Sales Development');
        LeadSlaService.salesDevelopmentQueue = queueName;
        Id leadId = insertLead();

        changeOwner(leadId, salesQueue.Id);

        Lead_SLA__c clock = [
            SELECT Clock__c, Status__c, TargetHours__c, Geography__c, DueAt__c, StartedAt__c
            FROM Lead_SLA__c
            WHERE Lead__c = :leadId
        ];
        Assert.areEqual(LeadSlaService.SALES_DEVELOPMENT, clock.Clock__c);
        Assert.areEqual(LeadSlaService.RUNNING, clock.Status__c);
        Assert.areEqual(2, clock.TargetHours__c);
        Assert.areEqual('Sales Development', clock.Geography__c);
        Assert.areEqual(
            BusinessCalendar.addWorkingMinutes(clock.StartedAt__c, 2 * 60),
            clock.DueAt__c
        );
    }

    /**
     * @description A pickup after the queue clock is due stays Missed.
     */
    @IsTest
    static void latePickupStaysMissed() {
        Group regionalQueue = insertQueue(uniqueQueueName('Lead_Country_Sla_LatePk'), 'SLA Late Pickup');
        Id leadId = insertLead();
        changeOwner(leadId, regionalQueue.Id);
        Lead_SLA__c clock = [SELECT Id FROM Lead_SLA__c WHERE Lead__c = :leadId];
        clock.DueAt__c = System.now().addMinutes(-5);
        updateAsUser(clock);

        changeOwner(leadId, UserInfo.getUserId());

        Lead_SLA__c pickedUp = [
            SELECT Status__c, PickedUpAt__c
            FROM Lead_SLA__c
            WHERE Id = :clock.Id
        ];
        Assert.areEqual(LeadSlaService.MISSED, pickedUp.Status__c);
        Assert.isNotNull(pickedUp.PickedUpAt__c);
    }

    /**
     * @description Moving a Lead from one person to another stops the prior individual clock.
     *              The new owner's country is stored on the new clock.
     */
    @IsTest
    static void reassignmentStopsThePriorIndividualClock() {
        User countryOwner = userInCountry('US');
        Group regionalQueue = insertQueue(uniqueQueueName('Lead_Country_Sla_Move'), 'SLA Move');
        Id leadId = insertLead();
        changeOwner(leadId, regionalQueue.Id);
        changeOwner(leadId, countryOwner.Id);

        Lead_SLA__c individualClock = [
            SELECT Geography__c
            FROM Lead_SLA__c
            WHERE Lead__c = :leadId
            AND Clock__c = :LeadSlaService.INDIVIDUAL
            AND Status__c = :LeadSlaService.RUNNING
        ];
        Assert.areEqual('US', individualClock.Geography__c);

        changeOwner(leadId, UserInfo.getUserId());
        List<Lead_SLA__c> individualClocks = [
            SELECT Status__c
            FROM Lead_SLA__c
            WHERE Lead__c = :leadId
            AND Clock__c = :LeadSlaService.INDIVIDUAL
            ORDER BY CreatedDate
        ];
        Assert.areEqual(2, individualClocks.size());
        Assert.areEqual(LeadSlaService.STOPPED, individualClocks[0].Status__c);
        Assert.areEqual(LeadSlaService.RUNNING, individualClocks[1].Status__c);
    }

    /**
     * @description Converting the Lead stops the running clock.
     */
    @IsTest
    static void convertedLeadStopsTheRunningClock() {
        Group regionalQueue = insertQueue(uniqueQueueName('Lead_Country_Sla_Conv'), 'SLA Convert');
        Id leadId = insertLead();
        changeOwner(leadId, regionalQueue.Id);
        changeOwner(leadId, UserInfo.getUserId());
        Lead previous = leadForSla(leadId);
        Lead current = (Lead) JSON.deserialize(
            '{"attributes":{"type":"Lead"},"Id":"' + leadId
                + '","OwnerId":"' + previous.OwnerId
                + '","Status":"' + previous.Status
                + '","IsConverted":true}',
            Lead.class
        );

        System.runAs(runningUser()) {
            LeadSlaService.apply(new List<Lead>{ current }, new Map<Id, Lead>{ leadId => previous });
        }

        Assert.areEqual(
            LeadSlaService.STOPPED,
            [
                SELECT Status__c
                FROM Lead_SLA__c
                WHERE Lead__c = :leadId
                AND Status__c = :LeadSlaService.STOPPED
                LIMIT 1
            ].Status__c
        );
    }

    /**
     * @description A due individual clock sends the 24 hour reminder, then the 48 hour reminder.
     */
    @IsTest
    static void dueIndividualClockSendsTheReminders() {
        Group regionalQueue = insertQueue(uniqueQueueName('Lead_Country_Sla_Rem'), 'SLA Reminder');
        Id leadId = insertLead();
        changeOwner(leadId, regionalQueue.Id);
        changeOwner(leadId, UserInfo.getUserId());
        Lead_SLA__c clock = [
            SELECT Id
            FROM Lead_SLA__c
            WHERE Lead__c = :leadId
            AND Clock__c = :LeadSlaService.INDIVIDUAL
        ];
        clock.DueAt__c = System.now().addMinutes(-5);
        clock.ReminderSent__c = false;
        updateAsUser(clock);

        markDueClocks();
        Lead_SLA__c reminded = [
            SELECT Status__c, ReminderSent__c
            FROM Lead_SLA__c
            WHERE Id = :clock.Id
        ];
        Assert.areEqual(LeadSlaService.MISSED, reminded.Status__c);
        Assert.areEqual(true, reminded.ReminderSent__c);

        reminded.EscalationAt__c = System.now().addMinutes(-5);
        reminded.EscalationSent__c = false;
        updateAsUser(reminded);
        markDueClocks();
        Assert.areEqual(
            true,
            [SELECT EscalationSent__c FROM Lead_SLA__c WHERE Id = :clock.Id].EscalationSent__c
        );
    }

    /**
     * @description A missed individual clock stops its reminders when the Lead moves to a queue.
     */
    @IsTest
    static void missedIndividualClockStopsRemindersOnReassignment() {
        Group regionalQueue = insertQueue(uniqueQueueName('Lead_Country_Sla_Stop'), 'SLA Stop');
        Group nextQueue = insertQueue(uniqueQueueName('Lead_Sla_Next'), 'SLA Next');
        Id leadId = insertLead();
        changeOwner(leadId, regionalQueue.Id);
        changeOwner(leadId, UserInfo.getUserId());
        Lead_SLA__c clock = [
            SELECT Id
            FROM Lead_SLA__c
            WHERE Lead__c = :leadId
            AND Clock__c = :LeadSlaService.INDIVIDUAL
        ];
        clock.Status__c = LeadSlaService.MISSED;
        clock.ReminderSent__c = false;
        clock.EscalationSent__c = false;
        updateAsUser(clock);

        changeOwner(leadId, nextQueue.Id);

        Lead_SLA__c stopped = [
            SELECT ReminderSent__c, EscalationSent__c
            FROM Lead_SLA__c
            WHERE Id = :clock.Id
        ];
        Assert.areEqual(true, stopped.ReminderSent__c);
        Assert.areEqual(true, stopped.EscalationSent__c);
    }

    /**
     * @description Inserts a Sales Lead as the running user.
     * @return Lead Id.
     */
    private static Id insertLead() {
        String token = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 8);
        Lead leadRecord = newLead('Sla' + token);
        System.runAs(runningUser()) {
            insert leadRecord;
        }
        return leadRecord.Id;
    }

    /**
     * @description Builds a Lead that satisfies the Sales Lead validation rules.
     * @param lastName Last name, also used to keep the email unique.
     * @return Unsaved Lead.
     */
    private static Lead newLead(String lastName) {
        return new Lead(
            FirstName = 'Ada',
            LastName = lastName,
            Company = 'Steris',
            CountryCode = 'US',
            Email = lastName.toLowerCase() + '.sla@example.com',
            LeadSource = 'Web',
            Status = 'New'
        );
    }

    /**
     * @description The user the test is already running as.
     * @return Current user, without a User insert.
     */
    private static User runningUser() {
        return new User(Id = UserInfo.getUserId());
    }

    /**
     * @description Inserts a user in a country. Setup data stays outside the Lead insert.
     * @param countryCode Country code stored on the user.
     * @return Inserted user.
     */
    private static User userInCountry(String countryCode) {
        String token = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 8);
        User owner = new User(
            Alias = token,
            Email = token + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'SlaOwner',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'America/New_York',
            Username = token + '@steris.sla.test',
            CountryCode = countryCode
        );
        insert owner;
        return owner;
    }

    /**
     * @description A queue developer name that does not already exist in the org.
     * @param prefix Short prefix.
     * @return Developer name of 40 characters or fewer.
     */
    private static String uniqueQueueName(String prefix) {
        String developerName = prefix + '_' + EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 6);
        return developerName.length() > 40 ? developerName.substring(0, 40) : developerName;
    }

    /**
     * @description Changes the Lead owner. Applies the SLA when the trigger skips a later update.
     * @param leadId Lead Id.
     * @param ownerId New owner.
     */
    private static void changeOwner(Id leadId, Id ownerId) {
        Lead previous = leadForSla(leadId);
        String before = slaSnapshot(leadId);
        System.runAs(runningUser()) {
            update new Lead(Id = leadId, OwnerId = ownerId);
            if (slaSnapshot(leadId) == before) {
                Lead current = previous.clone(true, true, true, true);
                current.OwnerId = ownerId;
                LeadSlaService.apply(new List<Lead>{ current }, new Map<Id, Lead>{ leadId => previous });
            }
        }
    }

    /**
     * @description Changes the Lead status. Applies the SLA when the trigger skips a later update.
     * @param leadId Lead Id.
     * @param status New status.
     */
    private static void changeStatus(Id leadId, String status) {
        Lead previous = leadForSla(leadId);
        String before = slaSnapshot(leadId);
        System.runAs(runningUser()) {
            update new Lead(Id = leadId, Status = status);
            if (slaSnapshot(leadId) == before) {
                Lead current = previous.clone(true, true, true, true);
                current.Status = status;
                LeadSlaService.apply(new List<Lead>{ current }, new Map<Id, Lead>{ leadId => previous });
            }
        }
    }

    /**
     * @description Updates a Lead or SLA row as the running user, apart from the queue insert.
     * @param record Row to update.
     */
    private static void updateAsUser(SObject record) {
        System.runAs(runningUser()) {
            update record;
        }
    }

    /**
     * @description Marks due clocks as the running user, apart from the queue insert.
     */
    private static void markDueClocks() {
        System.runAs(runningUser()) {
            LeadSlaService.markDueClocks();
        }
    }

    /**
     * @description Lead fields the SLA service reads.
     * @param leadId Lead Id.
     * @return Lead before the change.
     */
    private static Lead leadForSla(Id leadId) {
        return [
            SELECT Id, Name, OwnerId, Status, IsConverted, Company, Phone, Email, Country, CountryCode
            FROM Lead
            WHERE Id = :leadId
        ];
    }

    /**
     * @description Status of every SLA row, used to see whether the trigger already applied the change.
     * @param leadId Lead Id.
     * @return Stable snapshot.
     */
    private static String slaSnapshot(Id leadId) {
        List<String> parts = new List<String>();
        for (Lead_SLA__c clock : [
            SELECT Clock__c, Status__c, PickedUpAt__c, FirstQualifyingActionAt__c
            FROM Lead_SLA__c
            WHERE Lead__c = :leadId
            ORDER BY Clock__c, CreatedDate
        ]) {
            parts.add(
                clock.Clock__c + ':' + clock.Status__c + ':'
                + clock.PickedUpAt__c + ':' + clock.FirstQualifyingActionAt__c
            );
        }
        return String.join(parts, '|');
    }

    /**
     * @description Inserts a Lead queue. Kept outside runAs so it is not mixed with a User insert.
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
     * @description Latest SLA row for each clock type on the Lead.
     * @param leadId Lead Id.
     * @return Clock type to SLA row.
     */
    private static Map<String, Lead_SLA__c> clocksByType(Id leadId) {
        Map<String, Lead_SLA__c> clocks = new Map<String, Lead_SLA__c>();
        for (Lead_SLA__c clock : [
            SELECT Clock__c, Status__c, DueAt__c, StartedAt__c, PickedUpAt__c
            FROM Lead_SLA__c
            WHERE Lead__c = :leadId
        ]) {
            clocks.put(clock.Clock__c, clock);
        }
        return clocks;
    }
}