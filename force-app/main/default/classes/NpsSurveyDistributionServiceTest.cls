/**
 * @author PWC Developer
 * @date 2026/11/20
 *
 * @group Survey Management
 *
 * @description
 * GC-3506. Covers recipient upload, independent cycles, survey contacts, suppression, anonymous links, reminders, and administrator access.
 */
@IsTest
private class NpsSurveyDistributionServiceTest {

    @IsTest
    static void nonAdministratorCannotDistribute() {
        Approved_Nps_Survey__c survey = insertSurvey('HC NPS', 'Healthcare', 'AAA');
        NpsSurveyDistributionService.administratorOverride = false;

        try {
            NpsSurveyDistributionService.uploadRecipients(survey.Id, sampleCsv('new.person@example.com', 'ORACLE000000001'), 30, 1, 7);
            Assert.fail('A user without the Survey Administrator permission should be blocked.');
        } catch (NpsSurveyDistributionService.DistributionException exceptionValue) {
            Assert.areEqual('Only a Survey Administrator can initiate NPS survey distribution.', exceptionValue.getMessage());
        }
    }

    @IsTest
    static void uploadMatchesContactAndCreatesSurveyContact() {
        Account account = insertAccount('ORACLE000000001');
        Contact existing = insertContact('Ada', 'Buyer', 'ada.buyer@example.com', account.Id, 'Sales', false);
        actAsAdministrator();
        Approved_Nps_Survey__c survey = insertSurvey('HC NPS', 'Healthcare', 'AAB');

        NpsSurveyDistributionService.DistributionResult result = NpsSurveyDistributionService.uploadRecipients(
            survey.Id,
            header() + '\nAda,Buyer,ada.buyer@example.com,ORACLE000000001,Healthcare,English\nNed,New,ned.new@example.com,ORACLE000000001,Healthcare,fr',
            30,
            2,
            14
        );

        Survey_Distribution_Recipient__c matched = recipientByEmail(result.distributionId, 'ada.buyer@example.com');
        Survey_Distribution_Recipient__c created = recipientByEmail(result.distributionId, 'ned.new@example.com');
        Contact surveyContact = [SELECT RecordType.DeveloperName, AccountId, Language__c FROM Contact WHERE Id = :created.Contact__c];
        Survey_Distribution__c distribution = [
            SELECT Expiration_Date__c, Reminder_Count__c
            FROM Survey_Distribution__c
            WHERE Id = :result.distributionId
        ];
        Assert.areEqual('Contact', matched.Recipient_Source__c);
        Assert.areEqual(existing.Id, matched.Contact__c);
        Assert.areEqual('Survey Contact', created.Recipient_Source__c);
        Assert.areEqual('Survey_Contact', surveyContact.RecordType.DeveloperName);
        Assert.areEqual(account.Id, surveyContact.AccountId);
        Assert.areEqual('fr', surveyContact.Language__c);
        Assert.areEqual(Date.today().addDays(30), distribution.Expiration_Date__c);
        Assert.areEqual(2, distribution.Reminder_Count__c);
        Assert.areEqual(1, [SELECT COUNT() FROM Contact WHERE Email = 'ada.buyer@example.com']);
    }

    @IsTest
    static void secondUploadDoesNotChangeTheFirstCycle() {
        insertAccount('ORACLE000000002');
        actAsAdministrator();
        Approved_Nps_Survey__c survey = insertSurvey('HC NPS', 'Healthcare', 'AAC');
        Id firstId = NpsSurveyDistributionService.uploadRecipients(
            survey.Id, sampleCsv('first.list@example.com', 'ORACLE000000002'), null, 0, null
        ).distributionId;
        Id secondId = NpsSurveyDistributionService.uploadRecipients(
            survey.Id, sampleCsv('second.list@example.com', 'ORACLE000000002'), null, 0, null
        ).distributionId;

        Assert.areEqual(1, [SELECT COUNT() FROM Survey_Distribution_Recipient__c WHERE Survey_Distribution__c = :firstId]);
        Assert.areEqual('first.list@example.com', recipientByEmail(firstId, 'first.list@example.com').Email__c);
        Assert.areEqual('second.list@example.com', recipientByEmail(secondId, 'second.list@example.com').Email__c);
    }

    @IsTest
    static void invalidRowsAreRejectedWithReasons() {
        insertAccount('ORACLE000000003');
        insertContact('Ann', 'One', 'shared@example.com', null, 'Sales', false);
        insertContact('Ann', 'Two', 'shared@example.com', null, 'Transaction', false);
        actAsAdministrator();
        Approved_Nps_Survey__c survey = insertSurvey('HC NPS', 'Healthcare', 'AAD');

        try {
            NpsSurveyDistributionService.uploadRecipients(survey.Id, 'First Name,Last Name\nAda,Lovelace', 30, 0, null);
            Assert.fail('A file without the required columns should be rejected.');
        } catch (NpsSurveyDistributionService.DistributionException exceptionValue) {
            Assert.isTrue(exceptionValue.getMessage().contains('Customer Number'));
        }

        Id distributionId = NpsSurveyDistributionService.uploadRecipients(
            survey.Id,
            header() + ',Transaction Date'
                + '\n,Missing,missing.last@example.com,ORACLE000000003,Healthcare,English,'
                + '\nBad,Email,not-an-email,ORACLE000000003,Healthcare,English,'
                + '\nNo,Account,no.account@example.com,MISSING00000001,Healthcare,English,'
                + '\nWrong,Unit,wrong.unit@example.com,ORACLE000000003,Life Sciences,English,'
                + '\nAnn,One,shared@example.com,ORACLE000000003,Healthcare,English,'
                + '\nAnn,Copy,shared@example.com,ORACLE000000003,Healthcare,English,'
                + '\nBad,Date,bad.date@example.com,ORACLE000000003,Healthcare,English,13/40/2026',
            30,
            0,
            null
        ).distributionId;

        Assert.areEqual('First Name is required.', reasonContaining(distributionId, 'First Name'));
        Assert.areEqual('Email is missing or invalid.', reasonContaining(distributionId, 'Email is missing'));
        Assert.areEqual('No Account matches this Customer Number.', reasonContaining(distributionId, 'No Account'));
        Assert.areEqual('Business Unit does not match the selected survey.', reasonContaining(distributionId, 'does not match'));
        Assert.areEqual('More than one Contact uses this email.', reasonContaining(distributionId, 'More than one Contact'));
        Assert.areEqual('Duplicate email in this upload. Duplicate rules are owned by GC-3055.', reasonContaining(distributionId, 'Duplicate email'));
        Assert.areEqual('Transaction Date is not a valid date.', reasonContaining(distributionId, 'Transaction Date'));
    }

    @IsTest
    static void sendSkipsOptOutAndRecordsFailure() {
        Account account = insertAccount('ORACLE000000004');
        insertContact('Opt', 'Out', 'opt.out@example.com', account.Id, 'Sales', true);
        actAsAdministrator();
        Approved_Nps_Survey__c survey = insertSurvey('HC NPS', 'Healthcare', 'AAE');
        Id distributionId = NpsSurveyDistributionService.uploadRecipients(
            survey.Id, sampleCsv('opt.out@example.com', 'ORACLE000000004'), 30, 1, 7
        ).distributionId;

        NpsSurveyDistributionService.DistributionResult sent = NpsSurveyDistributionService.sendDistribution(distributionId);
        Survey_Distribution_Recipient__c row = recipientByEmail(distributionId, 'opt.out@example.com');
        Approved_Nps_Survey__c unchanged = [SELECT Is_Active__c FROM Approved_Nps_Survey__c WHERE Id = :survey.Id];

        Assert.areEqual('Failed', sent.status);
        Assert.areEqual('Contact is opted out of surveys.', row.Failure_Reason__c);
        Assert.areEqual(true, unchanged.Is_Active__c);
        Assert.areEqual(Date.today().addDays(30), [SELECT Expiration_Date__c FROM Survey_Distribution__c WHERE Id = :distributionId].Expiration_Date__c);
    }

    @IsTest
    static void correctedSurveyContactCanBeResent() {
        Account account = insertAccount('ORACLE000000005');
        actAsAdministrator();
        Approved_Nps_Survey__c survey = insertSurvey('HC NPS', 'Healthcare', 'AAF');
        Id distributionId = NpsSurveyDistributionService.uploadRecipients(
            survey.Id, sampleCsv('resend.me@example.com', 'ORACLE000000005'), null, 0, null
        ).distributionId;
        Survey_Distribution_Recipient__c row = recipientByEmail(distributionId, 'resend.me@example.com');
        row.Delivery_Status__c = 'Failed';
        row.Failure_Reason__c = 'Simulated delivery failure';
        update row;

        NpsSurveyDistributionService.updateFailedRecipient(row.Id, 'Resend', 'Person', 'fixed.person@example.com', 'ORACLE000000005');
        NpsSurveyDistributionService.emailsThatFail.add('fixed.person@example.com');
        NpsSurveyDistributionService.DistributionResult failedAgain = NpsSurveyDistributionService.sendDistribution(distributionId);
        Assert.areEqual('Failed', failedAgain.status);

        NpsSurveyDistributionService.emailsThatFail.clear();
        NpsSurveyDistributionService.DistributionResult sent = NpsSurveyDistributionService.sendDistribution(distributionId);
        Contact updated = [SELECT Email, FirstName FROM Contact WHERE Email = 'fixed.person@example.com'];
        Assert.areEqual('Sent', sent.status);
        Assert.areEqual('Resend', updated.FirstName);
    }

    @IsTest
    static void anonymousLinkIsReusedAndHasNoSeparateExpiration() {
        actAsAdministrator();
        Approved_Nps_Survey__c survey = insertSurvey('LS NPS', 'Life Sciences', 'AAG');
        NpsSurveyDistributionService.DistributionResult firstLink = NpsSurveyDistributionService.generateAnonymousLink(survey.Id);
        NpsSurveyDistributionService.DistributionResult secondLink = NpsSurveyDistributionService.generateAnonymousLink(survey.Id);
        Survey_Distribution__c linkDistribution = [
            SELECT Expiration_Date__c
            FROM Survey_Distribution__c
            WHERE Id = :firstLink.distributionId
        ];
        Assert.areEqual(firstLink.anonymousLink, secondLink.anonymousLink);
        Assert.areEqual(null, linkDistribution.Expiration_Date__c);
        Assert.areEqual(1, [SELECT COUNT() FROM Survey_Distribution__c WHERE Approved_Nps_Survey__c = :survey.Id]);

        NpsSurveyDistributionService.activeSurveyIdsForTest.clear();
        NpsSurveyDistributionService.DistributionResult inactive = NpsSurveyDistributionService.refreshSurveyAvailability(survey.Id);
        Assert.areEqual(NpsSurveyDistributionService.INACTIVE_MESSAGE, inactive.message);
        try {
            NpsSurveyDistributionService.generateAnonymousLink(survey.Id);
            Assert.fail('A deactivated survey should not issue another link.');
        } catch (NpsSurveyDistributionService.DistributionException exceptionValue) {
            Assert.areEqual(NpsSurveyDistributionService.INACTIVE_MESSAGE, exceptionValue.getMessage());
        }
    }

    @IsTest
    static void searchReturnsSalesServiceAndSurveyContacts() {
        Account account = insertAccount('ORACLE000000006');
        insertContact('Sally', 'Sales', 'sally.sales@example.com', account.Id, 'Sales', false);
        insertContact('Sam', 'Service', 'sam.service@example.com', account.Id, 'Transaction', false);
        actAsAdministrator();
        Approved_Nps_Survey__c survey = insertSurvey('HC NPS', 'Healthcare', 'AAH');
        NpsSurveyDistributionService.uploadRecipients(survey.Id, sampleCsv('survey.person@example.com', 'ORACLE000000006'), null, 0, null);

        List<NpsSurveyDistributionService.SearchRow> rows = NpsSurveyDistributionService.searchRecipients('example.com');
        Set<String> audiences = new Set<String>();
        for (NpsSurveyDistributionService.SearchRow row : rows) {
            audiences.add(row.audience);
        }
        Assert.isTrue(audiences.contains('Sales'));
        Assert.isTrue(audiences.contains('Service'));
        Assert.isTrue(audiences.contains('Survey Contact'));
    }

    @IsTest
    static void reminderIsRecordedAndStopsAfterResponse() {
        actAsAdministrator();
        Approved_Nps_Survey__c survey = insertSurvey('HC NPS', 'Healthcare', 'AAI');
        Survey_Distribution__c distribution = new Survey_Distribution__c(
            Approved_Nps_Survey__c = survey.Id,
            Survey_Id__c = survey.Survey_Id__c,
            Survey_Name__c = survey.Name,
            Business_Unit__c = 'Healthcare',
            Distribution_Method__c = 'Email',
            Status__c = 'Sent',
            Reminder_Count__c = 2,
            Reminder_Interval_Days__c = 7,
            Reminders_Sent__c = 0,
            Next_Reminder_Date__c = Date.today(),
            Expiration_Date__c = Date.today().addDays(30)
        );
        insert distribution;
        Survey_Distribution_Recipient__c recipient = new Survey_Distribution_Recipient__c(
            Survey_Distribution__c = distribution.Id,
            First_Name__c = 'Remy',
            Last_Name__c = 'Mind',
            Email__c = 'remy.mind@example.com',
            Delivery_Status__c = 'Sent',
            Invitation_Link__c = 'https://survey.example/reminder',
            Response_Status__c = 'NotStarted',
            Distribution_Date__c = Date.today().addDays(-7)
        );
        insert recipient;

        Test.startTest();
        Database.executeBatch(new NpsSurveyReminderJob(), 20);
        Test.stopTest();

        Survey_Distribution_Recipient__c reminded = [
            SELECT Reminder_Dates__c
            FROM Survey_Distribution_Recipient__c
            WHERE Id = :recipient.Id
        ];
        Survey_Distribution__c advanced = [
            SELECT Reminders_Sent__c, Next_Reminder_Date__c
            FROM Survey_Distribution__c
            WHERE Id = :distribution.Id
        ];
        Assert.isTrue(reminded.Reminder_Dates__c.contains(String.valueOf(Date.today())));
        Assert.areEqual(1, advanced.Reminders_Sent__c);
        Assert.areEqual(Date.today().addDays(7), advanced.Next_Reminder_Date__c);

        reminded.Response_Status__c = 'Completed';
        update reminded;
        List<Survey_Distribution_Recipient__c> due = [
            SELECT Id, Email__c, Invitation_Link__c, Reminder_Dates__c, Response_Status__c,
                Survey_Distribution__r.Reminders_Sent__c, Survey_Distribution__r.Reminder_Count__c,
                Survey_Distribution__r.Reminder_Interval_Days__c, Survey_Distribution__r.Expiration_Date__c,
                Survey_Distribution__r.Survey_Id__c, Survey_Distribution__r.Business_Unit__c
            FROM Survey_Distribution_Recipient__c
            WHERE Id = :recipient.Id
        ];
        NpsSurveyDistributionService.sendDueReminders(due);
        Assert.areEqual(1, [SELECT Reminders_Sent__c FROM Survey_Distribution__c WHERE Id = :distribution.Id].Reminders_Sent__c);
    }

    @IsTest
    static void batchesCoverLargeUploadAndSend() {
        insertAccount('ORACLE000000009');
        actAsAdministrator();
        Approved_Nps_Survey__c survey = insertSurvey('HC NPS', 'Healthcare', 'AAM');
        ContentVersion badFile = new ContentVersion(
            Title = 'bad',
            PathOnClient = 'bad.csv',
            VersionData = Blob.valueOf('First Name\nAda'),
            FirstPublishLocationId = survey.Id
        );
        insert badFile;
        badFile = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :badFile.Id];
        Id distributionId = NpsSurveyDistributionService.uploadRecipients(
            survey.Id, sampleCsv('batch.person@example.com', 'ORACLE000000009'), 10, 0, null
        ).distributionId;

        NpsSurveyUploadBatch uploadBatch = new NpsSurveyUploadBatch(distributionId, badFile.ContentDocumentId);
        uploadBatch.start(null);
        uploadBatch.finish(null);
        Assert.areEqual('The file is missing a required column: Last Name, Email, Customer Number, Business Unit.', reasonContaining(distributionId, 'missing a required column'));

        NpsSurveySendBatch sendBatch = new NpsSurveySendBatch(distributionId);
        sendBatch.start(null);
        sendBatch.execute(null, new List<Survey_Distribution_Recipient__c>{
            recipientByEmail(distributionId, 'batch.person@example.com')
        });
        sendBatch.finish(null);
        Assert.areEqual('Sent', recipientByEmail(distributionId, 'batch.person@example.com').Delivery_Status__c);
    }

    @IsTest
    static void fileUploadRunsAsABatch() {
        insertAccount('ORACLE000000007');
        actAsAdministrator();
        Approved_Nps_Survey__c survey = insertSurvey('HC NPS', 'Healthcare', 'AAJ');
        ContentVersion version = new ContentVersion(
            Title = 'recipients',
            PathOnClient = 'recipients.csv',
            VersionData = Blob.valueOf(sampleCsv('file.person@example.com', 'ORACLE000000007')),
            FirstPublishLocationId = survey.Id
        );
        insert version;
        version = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id];

        Test.startTest();
        Id distributionId = NpsSurveyDistributionService.startUploadFromFile(survey.Id, version.ContentDocumentId, 15, 1, 10).distributionId;
        Test.stopTest();

        Assert.areEqual('file.person@example.com', recipientByEmail(distributionId, 'file.person@example.com').Email__c);
        Assert.areEqual(Date.today().addDays(15), [SELECT Expiration_Date__c FROM Survey_Distribution__c WHERE Id = :distributionId].Expiration_Date__c);
    }

    @IsTest
    static void controllerRunsTheScreenAndBlocksANonAdministrator() {
        Account account = insertAccount('ORACLE000000008');
        insertContact('Cara', 'Sales', 'cara.sales@example.com', account.Id, 'Sales', false);
        Approved_Nps_Survey__c survey = insertSurvey('HC NPS', 'Healthcare', 'AAK');
        NpsSurveyDistributionService.administratorOverride = false;
        NpsSurveyDistributionService.WorkspaceContext blocked = NpsSurveyDistributionController.getWorkspaceContext(survey.Id);
        Assert.areEqual(false, blocked.canDistribute);

        actAsAdministrator();
        NpsSurveyDistributionService.WorkspaceContext open = NpsSurveyDistributionController.getWorkspaceContext(survey.Id);
        Assert.areEqual(true, open.canDistribute);
        Assert.areEqual('Healthcare', open.businessUnit);
        Id distributionId = NpsSurveyDistributionController.uploadRecipients(
            survey.Id, sampleCsv('cara.sales@example.com', 'ORACLE000000008'), 30, 0, null
        ).distributionId;
        NpsSurveyDistributionController.sendDistribution(distributionId);
        NpsSurveyDistributionService.TrackingPage tracking = NpsSurveyDistributionController.getTracking(distributionId);
        Assert.areEqual(1, tracking.sentCount);
        Assert.areEqual(1, NpsSurveyDistributionController.searchRecipients('cara.sales').size());
        NpsSurveyDistributionController.setSurveyOptOut(accountContactId('cara.sales@example.com'));
        Assert.areEqual(true, [SELECT Survey_Opt_Out__c FROM Contact WHERE Email = 'cara.sales@example.com'].Survey_Opt_Out__c);
        NpsSurveyDistributionService.DistributionResult link = NpsSurveyDistributionController.generateAnonymousLink(survey.Id);
        Assert.isTrue(link.anonymousLink.contains(survey.Survey_Id__c));
        Assert.areEqual('This survey is active.', NpsSurveyDistributionController.refreshSurveyAvailability(survey.Id).message);
    }

    @IsTest
    static void controllerRejectsUnauthorizedActions() {
        Approved_Nps_Survey__c survey = insertSurvey('HC NPS', 'Healthcare', 'AAL');
        NpsSurveyDistributionService.administratorOverride = false;
        assertUploadBlocked(survey.Id);
        assertFileBlocked(survey.Id);
        assertSendBlocked(survey.Id);
        assertLinkBlocked(survey.Id);
        assertRefreshBlocked(survey.Id);
        assertTrackingBlocked(survey.Id);
        assertSearchBlocked();
        assertOptOutBlocked(survey.Id);
        assertUpdateBlocked(survey.Id);
    }

    private static void assertUploadBlocked(Id surveyId) {
        try {
            NpsSurveyDistributionController.uploadRecipients(surveyId, sampleCsv('x@example.com', '1'), 1, 0, null);
            Assert.fail('Upload should be blocked.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isTrue(exceptionValue.getMessage().contains('Survey Administrator'));
        }
    }

    private static void assertFileBlocked(Id surveyId) {
        try {
            NpsSurveyDistributionController.startUploadFromFile(surveyId, surveyId, 1, 0, null);
            Assert.fail('File upload should be blocked.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isTrue(exceptionValue.getMessage().contains('Survey Administrator'));
        }
    }

    private static void assertSendBlocked(Id surveyId) {
        try {
            NpsSurveyDistributionController.sendDistribution(surveyId);
            Assert.fail('Send should be blocked.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isTrue(exceptionValue.getMessage().contains('Survey Administrator'));
        }
    }

    private static void assertLinkBlocked(Id surveyId) {
        try {
            NpsSurveyDistributionController.generateAnonymousLink(surveyId);
            Assert.fail('Anonymous link should be blocked.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isTrue(exceptionValue.getMessage().contains('Survey Administrator'));
        }
    }

    private static void assertRefreshBlocked(Id surveyId) {
        try {
            NpsSurveyDistributionController.refreshSurveyAvailability(surveyId);
            Assert.fail('Refresh should be blocked.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isTrue(exceptionValue.getMessage().contains('Survey Administrator'));
        }
    }

    private static void assertTrackingBlocked(Id surveyId) {
        try {
            NpsSurveyDistributionController.getTracking(surveyId);
            Assert.fail('Tracking should be blocked.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isTrue(exceptionValue.getMessage().contains('Survey Administrator'));
        }
    }

    private static void assertSearchBlocked() {
        try {
            NpsSurveyDistributionController.searchRecipients('a');
            Assert.fail('Search should be blocked.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isTrue(exceptionValue.getMessage().contains('Survey Administrator'));
        }
    }

    private static void assertOptOutBlocked(Id surveyId) {
        try {
            NpsSurveyDistributionController.setSurveyOptOut(surveyId);
            Assert.fail('Opt-out should be blocked.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isTrue(exceptionValue.getMessage().contains('Survey Administrator'));
        }
    }

    private static void assertUpdateBlocked(Id surveyId) {
        try {
            NpsSurveyDistributionController.updateFailedRecipient(surveyId, 'A', 'B', 'a@example.com', '1');
            Assert.fail('Recipient update should be blocked.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isTrue(exceptionValue.getMessage().contains('Survey Administrator'));
        }
    }

    private static void actAsAdministrator() {
        NpsSurveyDistributionService.administratorOverride = true;
        if (NpsSurveyDistributionService.activeSurveyIdsForTest == null) {
            NpsSurveyDistributionService.activeSurveyIdsForTest = new Set<String>();
        }
    }

    private static Approved_Nps_Survey__c insertSurvey(String name, String businessUnit, String suffix) {
        String surveyId = Schema.SObjectType.Survey.getKeyPrefix() + '000000000001' + suffix;
        Approved_Nps_Survey__c survey = new Approved_Nps_Survey__c(
            Name = name,
            Survey_Id__c = surveyId,
            Business_Unit__c = businessUnit,
            Approval_Status__c = 'Approved',
            Is_Active__c = true
        );
        insert survey;
        if (NpsSurveyDistributionService.activeSurveyIdsForTest == null) {
            NpsSurveyDistributionService.activeSurveyIdsForTest = new Set<String>();
        }
        NpsSurveyDistributionService.activeSurveyIdsForTest.add(surveyId);
        return survey;
    }

    private static Account insertAccount(String customerNumber) {
        Account account = new Account(
            Name = 'Customer ' + customerNumber,
            SystemID__c = customerNumber,
            SourceSystemID__c = customerNumber
        );
        insert account;
        return account;
    }

    private static Contact insertContact(String firstName, String lastName, String email, Id accountId, String usedFor, Boolean optedOut) {
        Contact contact = new Contact(
            FirstName = firstName,
            LastName = lastName,
            Email = email,
            AccountId = accountId,
            UsedFor__c = usedFor,
            Survey_Opt_Out__c = optedOut
        );
        insert contact;
        return contact;
    }

    private static String header() {
        return 'First Name,Last Name,Email,Customer Number (Oracle),Business Unit,Language';
    }

    private static String sampleCsv(String email, String customerNumber) {
        return header() + '\nPat,Sample,' + email + ',' + customerNumber + ',Healthcare,English';
    }

    private static Survey_Distribution_Recipient__c recipientByEmail(Id distributionId, String email) {
        return [
            SELECT Email__c, Contact__c, Recipient_Source__c, Failure_Reason__c, Delivery_Status__c
            FROM Survey_Distribution_Recipient__c
            WHERE Survey_Distribution__c = :distributionId AND Email__c = :email
            LIMIT 1
        ];
    }

    private static String reason(Id distributionId, String email) {
        List<Survey_Distribution_Recipient__c> rows = [
            SELECT Failure_Reason__c
            FROM Survey_Distribution_Recipient__c
            WHERE Survey_Distribution__c = :distributionId AND Email__c = null
        ];
        return rows.isEmpty() ? null : rows[0].Failure_Reason__c;
    }

    private static String reasonContaining(Id distributionId, String fragment) {
        for (Survey_Distribution_Recipient__c row : [
            SELECT Failure_Reason__c
            FROM Survey_Distribution_Recipient__c
            WHERE Survey_Distribution__c = :distributionId
        ]) {
            if (row.Failure_Reason__c != null && row.Failure_Reason__c.contains(fragment)) {
                return row.Failure_Reason__c;
            }
        }
        return null;
    }

    private static Id accountContactId(String email) {
        return [SELECT Id FROM Contact WHERE Email = :email LIMIT 1].Id;
    }
}