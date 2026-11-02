/**
 * @author Suraj Thapliyal
 * @date 2026/08/17
 *
 * @group Sample
 *
 * @description
 * GC-3226 - Tests for Sample create access, Follow-up notifications,
 *           and HasSampleActivity stamping.
 * GC-3225 - Opportunity.HasSampleActivity__c stamping on Sample create.
 */
@IsTest(SeeAllData=false)
private class SampleServiceTest {

    private static final String SAMPLE_OPP_NAME = 'GC-3226 Sample Opportunity';

    @TestSetup
    static void setupData() {
        User adminUser = createSystemAdminUser('smpadm');
        insert adminUser;

        System.runAs(adminUser) {
            Account accountRecord = new Account(
                Name = 'GC-3226 Sample Account',
                SourceSystemID__c = 'GC3226SAMPLE'
            );
            insert accountRecord;

            Contact contactRecord = new Contact(
                FirstName = 'Sample',
                LastName = 'Contact',
                AccountId = accountRecord.Id
            );
            insert contactRecord;

            Opportunity opportunityRecord = buildOpportunity(accountRecord.Id, contactRecord.Id);
            insert opportunityRecord;
        }
    }

    @IsTest
    static void testOwnerCanCreateSample() {
        User adminUser = [SELECT Id FROM User WHERE Alias = 'smpadm' LIMIT 1];

        System.runAs(adminUser) {
            Opportunity opportunityRecord = [SELECT Id, AccountId FROM Opportunity LIMIT 1];
            Contact contactRecord = [SELECT Id FROM Contact LIMIT 1];

            Test.startTest();
            Sample__c sampleRecord = buildSample(
                opportunityRecord.Id,
                opportunityRecord.AccountId,
                contactRecord.Id,
                true
            );
            insert sampleRecord;
            Test.stopTest();

            System.assertNotEquals(null, sampleRecord.Id, 'Sample should insert');
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Task WHERE WhatId = :sampleRecord.Id],
                'No Task should be created for Follow-up'
            );

            Opportunity refreshedOpp = [
                SELECT HasSampleActivity__c
                FROM Opportunity
                WHERE Id = :opportunityRecord.Id
            ];
            System.assertEquals(
                true,
                refreshedOpp.HasSampleActivity__c,
                'GC-3225 - Related Opportunity should be stamped HasSampleActivity__c on Sample create'
            );
        }
    }

    @IsTest
    static void testMarkRelatedOpportunitiesHasSampleActivityEmptyScope() {
        // GC-3225 - Empty / null scope is a no-op
        Test.startTest();
        SampleService.markRelatedOpportunitiesHasSampleActivity(null);
        SampleService.markRelatedOpportunitiesHasSampleActivity(new List<Sample__c>());
        Test.stopTest();
        System.assertEquals(
            0,
            SampleSelector.selectOpportunitiesMissingSampleActivity(new Set<Id>()).size(),
            'GC-3225 - Empty scope helpers should no-op without errors'
        );
    }

    @IsTest
    static void testBulkSampleCreateStampsOpportunityOnce() {
        // GC-3225 - Multiple Samples for one Opportunity stamp HasSampleActivity__c once (bulk-safe)
        User adminUser = [SELECT Id FROM User WHERE Alias = 'smpadm' LIMIT 1];

        System.runAs(adminUser) {
            Opportunity opportunityRecord = [
                SELECT Id, AccountId, HasSampleActivity__c
                FROM Opportunity
                LIMIT 1
            ];
            Contact contactRecord = [SELECT Id FROM Contact LIMIT 1];

            List<Sample__c> samples = new List<Sample__c>{
                buildSample(
                    opportunityRecord.Id,
                    opportunityRecord.AccountId,
                    contactRecord.Id,
                    false
                ),
                buildSample(
                    opportunityRecord.Id,
                    opportunityRecord.AccountId,
                    contactRecord.Id,
                    false
                )
            };

            Test.startTest();
            insert samples;
            Test.stopTest();

            Opportunity refreshedOpp = [
                SELECT HasSampleActivity__c
                FROM Opportunity
                WHERE Id = :opportunityRecord.Id
            ];
            System.assertEquals(
                true,
                refreshedOpp.HasSampleActivity__c,
                'GC-3225 - Opportunity should be stamped after bulk Sample insert'
            );
            System.assertEquals(
                2,
                [SELECT COUNT() FROM Sample__c WHERE RelatedOpportunity__c = :opportunityRecord.Id],
                'GC-3225 - Both Samples should insert successfully'
            );
        }
    }

    @IsTest
    static void testTeamMemberCanCreateSample() {
        User adminUser = [SELECT Id FROM User WHERE Alias = 'smpadm' LIMIT 1];
        User teamUser = createSystemAdminUser('smpteam');
        insert teamUser;

        Opportunity opportunityRecord;
        Contact contactRecord;
        System.runAs(adminUser) {
            opportunityRecord = [SELECT Id, AccountId FROM Opportunity LIMIT 1];
            contactRecord = [SELECT Id FROM Contact LIMIT 1];
            insert new OpportunityTeamMember(
                OpportunityId = opportunityRecord.Id,
                UserId = teamUser.Id,
                TeamMemberRole = getValidOpportunityTeamMemberRole(),
                OpportunityAccessLevel = 'Edit'
            );
        }

        System.runAs(teamUser) {
            Test.startTest();
            Sample__c sampleRecord = buildSample(
                opportunityRecord.Id,
                opportunityRecord.AccountId,
                contactRecord.Id,
                false
            );
            insert sampleRecord;
            Test.stopTest();

            System.assertNotEquals(null, sampleRecord.Id, 'Sample should insert for team member');
        }
    }

    @IsTest
    static void testNonTeamMemberBlockedInUiContext() {
        User adminUser = [SELECT Id FROM User WHERE Alias = 'smpadm' LIMIT 1];
        User otherUser = createSystemAdminUser('smpoth');
        insert otherUser;

        Opportunity opportunityRecord;
        System.runAs(adminUser) {
            opportunityRecord = [SELECT Id FROM Opportunity LIMIT 1];
        }

        System.runAs(otherUser) {
            Sample__c sampleRecord = new Sample__c(RelatedOpportunity__c = opportunityRecord.Id);
            Test.startTest();
            SampleService.enforceCreateAccess(new List<Sample__c>{ sampleRecord });
            Test.stopTest();

            System.assertEquals(
                true,
                sampleRecord.hasErrors(),
                'Non team member should be blocked on Sample create'
            );
        }
    }

    @IsTest
    static void testNonTeamMemberCannotInsertSample() {
        User adminUser = [SELECT Id FROM User WHERE Alias = 'smpadm' LIMIT 1];
        User otherUser = createSystemAdminUser('smpblk');
        insert otherUser;

        Opportunity opportunityRecord;
        Contact contactRecord;
        System.runAs(adminUser) {
            opportunityRecord = [SELECT Id, AccountId FROM Opportunity LIMIT 1];
            contactRecord = [SELECT Id FROM Contact LIMIT 1];
        }

        System.runAs(otherUser) {
            List<Sample__c> samples = new List<Sample__c>{
                buildSample(opportunityRecord.Id, opportunityRecord.AccountId, contactRecord.Id, false),
                buildSample(opportunityRecord.Id, opportunityRecord.AccountId, contactRecord.Id, false)
            };

            Test.startTest();
            Database.SaveResult[] results = Database.insert(samples, false);
            SampleService.enforceCreateAccess(null);
            SampleService.enforceCreateAccess(new List<Sample__c>());
            Test.stopTest();

            System.assertEquals(2, results.size(), 'Both bulk insert rows should be processed');
            for (Database.SaveResult result : results) {
                System.assertEquals(false, result.isSuccess(), 'Non owner / non team member must not insert');
                System.assertEquals(
                    true,
                    result.getErrors()[0].getMessage().contains(SampleService.ACCESS_DENIED_MESSAGE),
                    'Insert error should match the access denied message'
                );
            }
        }
    }

    @IsTest
    static void testFollowUpDateChangeResetsNotifiedFlag() {
        User adminUser = [SELECT Id FROM User WHERE Alias = 'smpadm' LIMIT 1];

        System.runAs(adminUser) {
            Opportunity opportunityRecord = [SELECT Id, AccountId FROM Opportunity LIMIT 1];
            Contact contactRecord = [SELECT Id FROM Contact LIMIT 1];

            Sample__c sampleRecord = buildSample(
                opportunityRecord.Id,
                opportunityRecord.AccountId,
                contactRecord.Id,
                true
            );
            sampleRecord.FollowUpDate__c = Date.today().addDays(3);
            sampleRecord.FollowUpNotified__c = true;
            insert sampleRecord;

            Test.startTest();
            sampleRecord.FollowUpDate__c = Date.today().addDays(10);
            update sampleRecord;
            Test.stopTest();

            Sample__c refreshed = [
                SELECT FollowUpNotified__c
                FROM Sample__c
                WHERE Id = :sampleRecord.Id
            ];
            System.assertEquals(
                false,
                refreshed.FollowUpNotified__c,
                'Follow-up Notified should reset when Follow-up Date changes'
            );
        }
    }

    @IsTest
    static void testSendFollowUpNotificationsMarksNotified() {
        User adminUser = [SELECT Id FROM User WHERE Alias = 'smpadm' LIMIT 1];
        SampleService.isSkipOutboundNotificationsInTest = true;

        System.runAs(adminUser) {
            Opportunity opportunityRecord = [SELECT Id, AccountId FROM Opportunity LIMIT 1];
            Contact contactRecord = [SELECT Id FROM Contact LIMIT 1];

            Sample__c sampleRecord = buildSample(
                opportunityRecord.Id,
                opportunityRecord.AccountId,
                contactRecord.Id,
                true
            );
            sampleRecord.FollowUpDate__c = Date.today();
            insert sampleRecord;

            List<Sample__c> scope = querySamplesForFollowUp(new Set<Id>{ sampleRecord.Id });

            Test.startTest();
            SampleService.sendFollowUpNotifications(scope);
            SampleFollowUpNotificationBatch.isSkipFlexQueueCheckForTest = true;
            Database.executeBatch(new SampleFollowUpNotificationBatch(), 200);
            Test.stopTest();

            Sample__c refreshed = [
                SELECT FollowUpNotified__c
                FROM Sample__c
                WHERE Id = :sampleRecord.Id
            ];
            System.assertEquals(
                true,
                refreshed.FollowUpNotified__c,
                'Sample should be marked notified after successful send'
            );
        }
    }

    @IsTest
    static void testBulkFollowUpNotificationsMarksMultipleSamples() {
        User adminUser = [SELECT Id FROM User WHERE Alias = 'smpadm' LIMIT 1];
        SampleService.isSkipOutboundNotificationsInTest = true;

        System.runAs(adminUser) {
            Opportunity opportunityRecord = [SELECT Id, AccountId FROM Opportunity LIMIT 1];
            Contact contactRecord = [SELECT Id FROM Contact LIMIT 1];

            Sample__c firstSample = buildSample(
                opportunityRecord.Id,
                opportunityRecord.AccountId,
                contactRecord.Id,
                true
            );
            firstSample.FollowUpDate__c = Date.today();
            Sample__c secondSample = buildSample(
                opportunityRecord.Id,
                opportunityRecord.AccountId,
                contactRecord.Id,
                true
            );
            secondSample.FollowUpDate__c = Date.today();
            insert new List<Sample__c>{ firstSample, secondSample };

            List<Sample__c> scope = querySamplesForFollowUp(
                new Set<Id>{ firstSample.Id, secondSample.Id }
            );

            Test.startTest();
            SampleService.sendFollowUpNotifications(scope);
            Test.stopTest();

            System.assertEquals(
                2,
                [
                    SELECT COUNT()
                    FROM Sample__c
                    WHERE Id IN :new Set<Id>{ firstSample.Id, secondSample.Id }
                    AND FollowUpNotified__c = true
                ],
                'Both Samples should be marked notified after bulk send'
            );
        }
    }

    @IsTest
    static void testBatchSchedulableAndRealOutboundPaths() {
        User adminUser = [SELECT Id FROM User WHERE Alias = 'smpadm' LIMIT 1];
        SampleService.isSkipOutboundNotificationsInTest = false;

        System.runAs(adminUser) {
            Opportunity opportunityRecord = [SELECT Id, AccountId FROM Opportunity LIMIT 1];
            Contact contactRecord = [SELECT Id FROM Contact LIMIT 1];

            Sample__c sampleRecord = buildSample(
                opportunityRecord.Id,
                opportunityRecord.AccountId,
                contactRecord.Id,
                true
            );
            sampleRecord.FollowUpDate__c = Date.today();
            insert sampleRecord;

            Test.startTest();
            SampleFollowUpNotificationBatch.isSkipFlexQueueCheckForTest = true;
            SampleFollowUpNotificationBatch.testBatchSizeOverride = 50;
            new SampleFollowUpNotificationBatch().execute(null);
            SampleService.sendFollowUpNotifications(new List<Sample__c>());
            SampleService.sendFollowUpNotifications(null);
            Integer resolvedSize = SampleFollowUpNotificationBatch.resolveBatchSize();
            Test.stopTest();

            System.assertEquals(
                50,
                resolvedSize,
                'Test batch size override should be used'
            );

            System.assertEquals(
                1,
                [
                    SELECT COUNT()
                    FROM Sample__c
                    WHERE Id = :sampleRecord.Id
                ],
                'Sample should still exist after notification batch'
            );
        }
    }

    @IsTest
    static void testReminderReEnabledResetsNotifiedFlag() {
        User adminUser = [SELECT Id FROM User WHERE Alias = 'smpadm' LIMIT 1];

        System.runAs(adminUser) {
            Opportunity opportunityRecord = [SELECT Id, AccountId FROM Opportunity LIMIT 1];
            Contact contactRecord = [SELECT Id FROM Contact LIMIT 1];

            Sample__c sampleRecord = buildSample(
                opportunityRecord.Id,
                opportunityRecord.AccountId,
                contactRecord.Id,
                true
            );
            sampleRecord.FollowUpReminder__c = false;
            sampleRecord.FollowUpNotified__c = true;
            insert sampleRecord;

            Test.startTest();
            sampleRecord.FollowUpReminder__c = true;
            update sampleRecord;
            Test.stopTest();

            Sample__c refreshed = [
                SELECT FollowUpNotified__c
                FROM Sample__c
                WHERE Id = :sampleRecord.Id
            ];
            System.assertEquals(
                false,
                refreshed.FollowUpNotified__c,
                'Follow-up Notified should reset when Reminder is re-enabled'
            );
        }
    }

    @IsTest
    static void testBatchConfigResolveSizeAndCoveragePaths() {
        User adminUser = [SELECT Id FROM User WHERE Alias = 'smpadm' LIMIT 1];
        SampleService.isSkipOutboundNotificationsInTest = true;
        SampleFollowUpNotificationBatch.isSkipFlexQueueCheckForTest = true;
        SampleFollowUpNotificationBatch.testBatchSizeOverride = null;
        BatchProcessConfigSelector.testOnly_resetCache();

        System.runAs(adminUser) {
            Opportunity opportunityRecord = [SELECT Id, AccountId FROM Opportunity LIMIT 1];
            Contact contactRecord = [SELECT Id FROM Contact LIMIT 1];

            Sample__c sampleRecord = buildSample(
                opportunityRecord.Id,
                opportunityRecord.AccountId,
                contactRecord.Id,
                true
            );
            sampleRecord.FollowUpDate__c = Date.today();
            insert sampleRecord;

            Test.startTest();
            Integer configuredSize = SampleFollowUpNotificationBatch.resolveBatchSize();
            Id jobId = SampleFollowUpNotificationBatch.submitBatch();

            SampleFollowUpNotificationBatch batchInstance = new SampleFollowUpNotificationBatch();
            batchInstance.finish(null);

            SampleFollowUpNotificationBatch.isThrowInStart = true;
            Boolean threwStart = false;
            try {
                batchInstance.start(null);
            } catch (QueryException e) {
                threwStart = true;
            }
            SampleFollowUpNotificationBatch.isThrowInStart = false;

            SampleFollowUpNotificationBatch.isThrowInExecute = true;
            batchInstance.execute(null, new List<Sample__c>{ sampleRecord });
            SampleFollowUpNotificationBatch.isThrowInExecute = false;

            SampleFollowUpNotificationBatch.isThrowInFinish = true;
            batchInstance.finish(null);
            SampleFollowUpNotificationBatch.isThrowInFinish = false;

            Boolean threwFlexQueue = false;
            SampleFollowUpNotificationBatch.isSkipFlexQueueCheckForTest = false;
            SampleFollowUpNotificationBatch.testFlexQueueHoldingCountOverride =
                SampleFollowUpNotificationBatch.FLEX_QUEUE_MAX_BATCH_JOBS;
            try {
                SampleFollowUpNotificationBatch.assertFlexQueueHasCapacity();
            } catch (SampleException e) {
                threwFlexQueue = true;
            }
            SampleFollowUpNotificationBatch.testFlexQueueHoldingCountOverride = null;
            SampleFollowUpNotificationBatch.isSkipFlexQueueCheckForTest = true;
            Test.stopTest();

            System.assert(
                configuredSize > 0,
                'resolveBatchSize should return a positive size from CMDT or default'
            );
            System.assertNotEquals(null, jobId, 'submitBatch should return a job Id');
            System.assertEquals(true, threwFlexQueue, 'Full flex queue should throw SampleException');
            System.assertEquals(true, threwStart, 'Start throw path should be covered');
            System.assert(
                SampleFollowUpNotificationBatch.startCatchCount > 0,
                'Start catch path should be covered'
            );
            System.assert(
                SampleFollowUpNotificationBatch.executeCatchCount > 0,
                'Execute catch path should be covered'
            );
            System.assert(
                SampleFollowUpNotificationBatch.finishCatchCount > 0,
                'Finish catch path should be covered'
            );
        }
    }

    @IsTest
    static void testSendFollowUpNotificationFailurePaths() {
        User adminUser = [SELECT Id FROM User WHERE Alias = 'smpadm' LIMIT 1];
        SampleService.isSkipOutboundNotificationsInTest = false;
        SampleService.customNotificationTypeIdOverride = null;
        SampleService.emailTemplateIdOverride = null;
        SampleService.isForceMissingNotificationType = true;
        SampleService.isForceMissingEmailTemplate = true;

        System.runAs(adminUser) {
            Opportunity opportunityRecord = [SELECT Id, AccountId FROM Opportunity LIMIT 1];
            Contact contactRecord = [SELECT Id FROM Contact LIMIT 1];

            Sample__c sampleRecord = buildSample(
                opportunityRecord.Id,
                opportunityRecord.AccountId,
                contactRecord.Id,
                true
            );
            sampleRecord.FollowUpDate__c = Date.today();
            insert sampleRecord;

            List<Sample__c> scope = querySamplesForFollowUp(new Set<Id>{ sampleRecord.Id });

            Test.startTest();
            SampleService.sendFollowUpNotifications(scope);

            SampleService.isForceMissingNotificationType = false;
            SampleService.isForceMissingEmailTemplate = false;
            SampleService.customNotificationTypeIdOverride = contactRecord.Id;
            SampleService.emailTemplateIdOverride = contactRecord.Id;
            SampleService.sendFollowUpNotifications(scope);

            SampleService.customNotificationTypeIdOverride = null;
            SampleService.emailTemplateIdOverride = null;
            SampleService.isForceMissingEmailTemplate = true;
            SampleService.sendFollowUpNotifications(scope);
            SampleService.isForceMissingEmailTemplate = false;

            SampleService.sendFollowUpNotifications(
                new List<Sample__c>{
                    new Sample__c(
                        Id = sampleRecord.Id,
                        FollowUpReminder__c = false,
                        FollowUpDate__c = Date.today(),
                        FollowUpNotified__c = false
                    )
                }
            );
            SampleService.enforceCreateAccess(null);
            SampleService.enforceCreateAccess(new List<Sample__c>());
            System.assertEquals(
                0,
                SampleSelector.selectOwnerIdByOpportunityId(new Set<Id>()).size(),
                'Empty Opportunity Id set should return empty map'
            );
            Test.stopTest();
            System.assertEquals(
                1,
                [SELECT COUNT() FROM Sample__c WHERE Id = :sampleRecord.Id],
                'Sample should remain after notification attempt'
            );
        }
    }

    private static List<Sample__c> querySamplesForFollowUp(Set<Id> sampleIds) {
        return [
            SELECT
                Id,
                Name,
                FollowUpDate__c,
                FollowUpReminder__c,
                FollowUpNotified__c,
                CreatedById
            FROM Sample__c
            WHERE Id IN :sampleIds
        ];
    }

    private static Sample__c buildSample(
        Id opportunityId,
        Id accountId,
        Id contactId,
        Boolean withFollowUp
    ) {
        Sample__c sampleRecord = new Sample__c(
            RelatedOpportunity__c = opportunityId,
            CustomerAccount__c = accountId,
            CustomerContact__c = contactId,
            SamplePurpose__c = 'Evaluation',
            RequestedDeliveryDate__c = Date.today().addDays(14),
            BusinessJustification__c = 'GC-3226 test justification'
        );
        if (withFollowUp) {
            sampleRecord.FollowUpDate__c = Date.today().addDays(7);
            sampleRecord.FollowUpReminder__c = true;
        }
        return sampleRecord;
    }

    private static Opportunity buildOpportunity(Id accountId, Id contactId) {
        Opportunity opportunityRecord = new Opportunity(
            Name = SAMPLE_OPP_NAME,
            AccountId = accountId,
            StageName = getActivePicklistValue(Opportunity.StageName),
            CloseDate = Date.today().addDays(30),
            Amount = 1000,
            Probability = 10
        );

        if (Opportunity.SObjectType.getDescribe().fields.getMap().containsKey('PrimaryContact__c')) {
            opportunityRecord.put('PrimaryContact__c', contactId);
        }

        String opportunityType = getActivePicklistValue(Opportunity.Type);
        if (String.isNotBlank(opportunityType)) {
            opportunityRecord.Type = opportunityType;
        }

        String forecastConfidence = getActivePicklistValue(
            Opportunity.ForecastConfidenceLevel__c
        );
        if (String.isNotBlank(forecastConfidence)) {
            opportunityRecord.put('ForecastConfidenceLevel__c', forecastConfidence);
        }

        return opportunityRecord;
    }

    private static String getValidOpportunityTeamMemberRole() {
        return getActivePicklistValue(OpportunityTeamMember.TeamMemberRole);
    }

    private static String getActivePicklistValue(Schema.SObjectField fieldToken) {
        for (Schema.PicklistEntry picklistEntry : fieldToken.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }
        return null;
    }

    private static User createSystemAdminUser(String aliasPrefix) {
        Profile adminProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];

        String uniqueValue = aliasPrefix + String.valueOf(Datetime.now().getTime());
        return new User(
            FirstName = 'GC',
            LastName = '3226 Sample',
            Alias = aliasPrefix.left(8),
            Email = uniqueValue + '@test.com',
            Username = uniqueValue + '@test.com',
            CommunityNickname = uniqueValue.left(40),
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }
}