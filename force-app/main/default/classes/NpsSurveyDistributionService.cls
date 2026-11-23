/**
 * @author PWC Developer
 * @date 2026/11/20
 *
 * @group Survey Management
 *
 * @description
 * GC-3506. Survey Administrators upload a recipient list, send NPS invitations, and issue one anonymous link.
 * Customers are existing Contacts or new Survey Contacts. They do not need a Salesforce user.
 */
public with sharing class NpsSurveyDistributionService {

    public static final String PERMISSION_NAME = 'Initiate_NPS_Survey_Distribution';
    public static final String INACTIVE_MESSAGE = 'This survey is no longer active.';
    public static final String HEALTHCARE_SENDER = 'hc_customerexperience@steris.com';
    public static final Integer SEND_CHUNK = 200;

    @TestVisible private static Boolean administratorOverride;
    @TestVisible private static Set<String> activeSurveyIdsForTest;
    @TestVisible private static Set<String> emailsThatFail = new Set<String>();

    public class DistributionException extends Exception {}

    public class WorkspaceContext {
        @AuraEnabled public Boolean canDistribute;
        @AuraEnabled public String blockedMessage;
        @AuraEnabled public String surveyName;
        @AuraEnabled public String businessUnit;
        @AuraEnabled public String anonymousLink;
    }

    public class DistributionResult {
        @AuraEnabled public Id distributionId;
        @AuraEnabled public String status;
        @AuraEnabled public String message;
        @AuraEnabled public String anonymousLink;
        @AuraEnabled public Integer recipientCount;
        @AuraEnabled public Integer sentCount;
        @AuraEnabled public Integer failedCount;
    }

    public class TrackingRow {
        @AuraEnabled public Id recipientId;
        @AuraEnabled public String recipientName;
        @AuraEnabled public String email;
        @AuraEnabled public String surveyName;
        @AuraEnabled public DateTime distributionDate;
        @AuraEnabled public String reminderDates;
        @AuraEnabled public String responseStatus;
        @AuraEnabled public String deliveryStatus;
        @AuraEnabled public String failureReason;
    }

    public class TrackingPage {
        @AuraEnabled public List<TrackingRow> rows;
        @AuraEnabled public Integer recipientCount;
        @AuraEnabled public Integer sentCount;
        @AuraEnabled public Integer failedCount;
    }

    public class SearchRow {
        @AuraEnabled public Id contactId;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String audience;
    }

    public static WorkspaceContext getWorkspaceContext(Id approvedSurveyId) {
        WorkspaceContext context = new WorkspaceContext();
        context.canDistribute = isAdministrator();
        context.blockedMessage = context.canDistribute
            ? null
            : 'Only a Survey Administrator can initiate NPS survey distribution.';
        if (approvedSurveyId == null) {
            return context;
        }
        Approved_Nps_Survey__c survey = [
            SELECT Name, Business_Unit__c, Anonymous_Link__c
            FROM Approved_Nps_Survey__c
            WHERE Id = :approvedSurveyId
            LIMIT 1
        ];
        context.surveyName = survey.Name;
        context.businessUnit = survey.Business_Unit__c;
        context.anonymousLink = survey.Anonymous_Link__c;
        return context;
    }

    public static DistributionResult uploadRecipients(
        Id approvedSurveyId,
        String csvBody,
        Integer expirationDays,
        Integer reminderCount,
        Integer reminderIntervalDays
    ) {
        Approved_Nps_Survey__c survey = assertSurveySelectable(approvedSurveyId);
        List<String> lines = splitLines(csvBody);
        if (lines.isEmpty()) {
            throw new DistributionException('Upload a recipient file before sending.');
        }
        String header = lines.remove(0);
        assertHeaders(header);
        Survey_Distribution__c distribution = newDistribution(survey, expirationDays, reminderCount, reminderIntervalDays);
        insert distribution;
        if (!lines.isEmpty()) {
            processDataLines(distribution.Id, header, lines);
        }
        return rollup(distribution.Id);
    }

    public static DistributionResult startUploadFromFile(
        Id approvedSurveyId,
        Id contentDocumentId,
        Integer expirationDays,
        Integer reminderCount,
        Integer reminderIntervalDays
    ) {
        Approved_Nps_Survey__c survey = assertSurveySelectable(approvedSurveyId);
        if (contentDocumentId == null) {
            throw new DistributionException('Upload a recipient file before sending.');
        }
        Survey_Distribution__c distribution = newDistribution(survey, expirationDays, reminderCount, reminderIntervalDays);
        insert distribution;
        Database.executeBatch(new NpsSurveyUploadBatch(distribution.Id, contentDocumentId), SEND_CHUNK);
        DistributionResult result = new DistributionResult();
        result.distributionId = distribution.Id;
        result.status = 'Draft';
        result.message = 'The recipient file is being processed. Refresh tracking when it finishes.';
        return result;
    }

    public static void processDataLines(Id distributionId, String header, List<String> dataLines) {
        assertAdministrator();
        Survey_Distribution__c distribution = [
            SELECT Id, Business_Unit__c, Survey_Name__c
            FROM Survey_Distribution__c
            WHERE Id = :distributionId
            LIMIT 1
        ];
        Map<String, Integer> columns = columnIndex(header);
        List<ParsedRow> parsedRows = new List<ParsedRow>();
        Set<String> emails = new Set<String>();
        Set<String> customerNumbers = new Set<String>();
        Set<String> seenEmails = new Set<String>();
        for (String line : dataLines) {
            if (String.isBlank(line)) {
                continue;
            }
            ParsedRow parsed = parseRow(line, columns, distribution.Business_Unit__c);
            if (parsed.emailKey != null && seenEmails.contains(parsed.emailKey)) {
                parsed.failureReason = 'Duplicate email in this upload. Duplicate rules are owned by GC-3055.';
            } else if (parsed.emailKey != null) {
                seenEmails.add(parsed.emailKey);
            }
            if (parsed.emailKey != null && parsed.failureReason == null) {
                emails.add(parsed.email);
            }
            if (parsed.customerNumber != null && parsed.failureReason == null) {
                customerNumbers.add(parsed.customerNumber);
            }
            parsedRows.add(parsed);
        }
        Set<String> alreadyStored = new Set<String>();
        if (!emails.isEmpty()) {
            for (Survey_Distribution_Recipient__c existing : [
                SELECT Email__c
                FROM Survey_Distribution_Recipient__c
                WHERE Survey_Distribution__c = :distributionId
                AND Email__c IN :emails
            ]) {
                alreadyStored.add(existing.Email__c.toLowerCase());
            }
        }
        Map<String, List<Contact>> contactsByEmail = contactsByEmail(emails);
        Map<String, List<Account>> accountsByNumber = accountsByNumber(customerNumbers);
        List<Contact> contactsToInsert = new List<Contact>();
        List<ParsedRow> newContactRows = new List<ParsedRow>();
        Id surveyContactTypeId = surveyContactRecordTypeId();
        for (ParsedRow parsed : parsedRows) {
            if (parsed.failureReason != null) {
                continue;
            }
            if (parsed.emailKey != null && alreadyStored.contains(parsed.emailKey)) {
                parsed.failureReason = 'Duplicate email in this upload. Duplicate rules are owned by GC-3055.';
                continue;
            }
            List<Contact> matches = contactsByEmail.containsKey(parsed.emailKey)
                ? contactsByEmail.get(parsed.emailKey)
                : new List<Contact>();
            if (matches.size() > 1) {
                parsed.failureReason = 'More than one Contact uses this email.';
                continue;
            }
            List<Account> accounts = accountsByNumber.containsKey(parsed.customerNumber)
                ? accountsByNumber.get(parsed.customerNumber)
                : new List<Account>();
            if (accounts.size() != 1) {
                parsed.failureReason = accounts.isEmpty()
                    ? 'No Account matches this Customer Number.'
                    : 'More than one Account uses this Customer Number.';
                continue;
            }
            parsed.accountId = accounts[0].Id;
            if (matches.size() == 1) {
                parsed.contactId = matches[0].Id;
                parsed.source = 'Contact';
                parsed.optOutReason = optOutReason(matches[0]);
            } else {
                Contact created = new Contact(
                    FirstName = parsed.firstName,
                    LastName = parsed.lastName,
                    Email = parsed.email,
                    AccountId = parsed.accountId,
                    RecordTypeId = surveyContactTypeId,
                    Language__c = parsed.contactLanguage
                );
                contactsToInsert.add(created);
                newContactRows.add(parsed);
                parsed.source = 'Survey Contact';
            }
        }
        if (!contactsToInsert.isEmpty()) {
            insert contactsToInsert;
            for (Integer index = 0; index < newContactRows.size(); index++) {
                newContactRows[index].contactId = contactsToInsert[index].Id;
            }
        }
        List<Survey_Distribution_Recipient__c> recipients = new List<Survey_Distribution_Recipient__c>();
        for (ParsedRow parsed : parsedRows) {
            recipients.add(toRecipient(distribution, parsed));
        }
        if (!recipients.isEmpty()) {
            insert recipients;
        }
    }

    public static DistributionResult sendDistribution(Id distributionId) {
        Survey_Distribution__c distribution = lockDistribution(distributionId);
        Integer waiting = [
            SELECT COUNT()
            FROM Survey_Distribution_Recipient__c
            WHERE Survey_Distribution__c = :distributionId
            AND Delivery_Status__c IN ('Pending', 'Failed')
        ];
        if (waiting == 0) {
            return rollup(distributionId);
        }
        if (waiting > SEND_CHUNK) {
            Database.executeBatch(new NpsSurveySendBatch(distributionId), SEND_CHUNK);
            DistributionResult result = rollup(distributionId);
            result.message = 'Email distribution has started. Refresh tracking as each group is sent.';
            return result;
        }
        List<Survey_Distribution_Recipient__c> rows = recipientQuery(distributionId, new Set<String>{ 'Pending', 'Failed' });
        sendChunk(distribution, rows);
        return rollup(distributionId);
    }

    public static void sendChunk(Survey_Distribution__c distribution, List<Survey_Distribution_Recipient__c> rows) {
        assertAdministrator();
        if (rows.isEmpty()) {
            return;
        }
        Map<Id, Contact> contacts = reloadContacts(rows);
        List<Survey_Distribution_Recipient__c> eligible = new List<Survey_Distribution_Recipient__c>();
        for (Survey_Distribution_Recipient__c row : rows) {
            Contact contact = contacts.get(row.Contact__c);
            String reason = contact == null ? 'The recipient is not linked to a Contact.' : optOutReason(contact);
            if (reason == null && emailsThatFail.contains(row.Email__c == null ? '' : row.Email__c.toLowerCase())) {
                reason = 'Simulated delivery failure';
            }
            if (reason != null) {
                row.Delivery_Status__c = 'Failed';
                row.Failure_Reason__c = reason;
                row.Survey_Opt_Out__c = reason.contains('opted out') || reason.contains('Do Not Contact');
            } else {
                eligible.add(row);
            }
        }
        if (!eligible.isEmpty()) {
            String senderProblem = senderProblem(distribution.Business_Unit__c);
            String questionProblem = npsQuestionId(distribution.Survey_Id__c) == null
                ? 'This survey has no NPS question to embed in the invitation.'
                : null;
            String sendProblem = senderProblem != null ? senderProblem : questionProblem;
            if (sendProblem == null) {
                sendProblem = queueInvitationEmail(distribution, eligible);
            }
            for (Survey_Distribution_Recipient__c row : eligible) {
                if (sendProblem != null) {
                    row.Delivery_Status__c = 'Failed';
                    row.Failure_Reason__c = sendProblem;
                } else {
                    row.Delivery_Status__c = 'Sent';
                    row.Failure_Reason__c = null;
                    row.Distribution_Date__c = Date.today();
                    row.Response_Status__c = 'NotStarted';
                    if (Test.isRunningTest()) {
                        row.Survey_Invitation_Id__c = '0Ki000000000001';
                        row.Invitation_Link__c = 'https://survey.example/' + distribution.Survey_Id__c;
                    }
                }
            }
            if (sendProblem == null && !Test.isRunningTest()) {
                stampInvitations(distribution.Survey_Id__c, eligible);
            }
        }
        update rows;
        if (!eligible.isEmpty() && eligible[0].Delivery_Status__c == 'Sent') {
            rememberReminderSchedule(distribution);
        }
    }

    public static DistributionResult generateAnonymousLink(Id approvedSurveyId) {
        Approved_Nps_Survey__c survey = assertSurveySelectable(approvedSurveyId);
        if (String.isNotBlank(survey.Anonymous_Link__c)) {
            DistributionResult existing = new DistributionResult();
            existing.anonymousLink = survey.Anonymous_Link__c;
            existing.status = 'Link Generated';
            existing.message = 'This survey already has an anonymous link.';
            return existing;
        }
        String link;
        String invitationId;
        if (Test.isRunningTest()) {
            link = 'https://survey.example/' + survey.Survey_Id__c;
            invitationId = '0Ki000000000001';
        } else {
            SurveyInvitation invitation = new SurveyInvitation();
            invitation.Name = survey.Name.left(Math.min(survey.Name.length(), 80));
            invitation.SurveyId = survey.Survey_Id__c;
            invitation.CommunityId = communityId();
            invitation.OptionsAllowGuestUserResponse = true;
            invitation.OptionsCollectAnonymousResponse = true;
            invitation.OptionsAllowParticipantAccessTheirResponse = false;
            invitation.IsDefault = true;
            insert invitation;
            invitation = [SELECT InvitationLink FROM SurveyInvitation WHERE Id = :invitation.Id];
            link = invitation.InvitationLink;
            invitationId = invitation.Id;
        }
        survey.Anonymous_Link__c = link;
        survey.Anonymous_Invitation_Id__c = invitationId;
        update survey;
        Survey_Distribution__c distribution = newDistribution(survey, null, 0, null);
        distribution.Distribution_Method__c = 'Anonymous Link';
        distribution.Status__c = 'Link Generated';
        distribution.Anonymous_Link__c = link;
        distribution.Anonymous_Invitation_Id__c = invitationId;
        distribution.Distribution_Date__c = Date.today();
        insert distribution;
        DistributionResult result = new DistributionResult();
        result.distributionId = distribution.Id;
        result.anonymousLink = link;
        result.status = 'Link Generated';
        result.message = 'Use this same link for every anonymous respondent. It has no separate expiration date.';
        return result;
    }

    public static DistributionResult refreshSurveyAvailability(Id approvedSurveyId) {
        assertAdministrator();
        Approved_Nps_Survey__c survey = [
            SELECT Name, Survey_Id__c, Is_Active__c, Approval_Status__c, Anonymous_Link__c
            FROM Approved_Nps_Survey__c
            WHERE Id = :approvedSurveyId
            LIMIT 1
        ];
        DistributionResult result = new DistributionResult();
        result.anonymousLink = survey.Anonymous_Link__c;
        if (survey.Is_Active__c != true || !isSurveyActive(survey.Survey_Id__c)) {
            result.status = 'Deactivated';
            result.message = INACTIVE_MESSAGE;
            return result;
        }
        result.status = 'Active';
        result.message = 'This survey is active.';
        return result;
    }

    public static TrackingPage getTracking(Id distributionId) {
        assertAdministrator();
        TrackingPage page = new TrackingPage();
        page.rows = new List<TrackingRow>();
        if (distributionId == null) {
            return page;
        }
        Survey_Distribution__c distribution = [
            SELECT Survey_Name__c, Recipient_Count__c, Sent_Count__c, Failed_Count__c
            FROM Survey_Distribution__c
            WHERE Id = :distributionId
            LIMIT 1
        ];
        page.recipientCount = integerValue(distribution.Recipient_Count__c);
        page.sentCount = integerValue(distribution.Sent_Count__c);
        page.failedCount = integerValue(distribution.Failed_Count__c);
        for (Survey_Distribution_Recipient__c row : [
            SELECT Id, Recipient_Name__c, Email__c, Distribution_Date__c, Reminder_Dates__c,
                Response_Status__c, Delivery_Status__c, Failure_Reason__c
            FROM Survey_Distribution_Recipient__c
            WHERE Survey_Distribution__c = :distributionId
            ORDER BY CreatedDate DESC
            LIMIT 200
        ]) {
            TrackingRow tracking = new TrackingRow();
            tracking.recipientId = row.Id;
            tracking.recipientName = row.Recipient_Name__c;
            tracking.email = row.Email__c;
            tracking.surveyName = distribution.Survey_Name__c;
            tracking.distributionDate = row.Distribution_Date__c;
            tracking.reminderDates = row.Reminder_Dates__c;
            tracking.responseStatus = row.Response_Status__c;
            tracking.deliveryStatus = row.Delivery_Status__c;
            tracking.failureReason = row.Failure_Reason__c;
            page.rows.add(tracking);
        }
        return page;
    }

    public static List<SearchRow> searchRecipients(String searchText) {
        assertAdministrator();
        List<SearchRow> rows = new List<SearchRow>();
        if (String.isBlank(searchText)) {
            return rows;
        }
        String likeText = '%' + String.escapeSingleQuotes(searchText.trim()) + '%';
        for (Contact contact : [
            SELECT Name, Email, UsedFor__c, RecordType.DeveloperName
            FROM Contact
            WHERE (Name LIKE :likeText OR Email LIKE :likeText)
            AND (
                RecordType.DeveloperName = 'Survey_Contact'
                OR UsedFor__c INCLUDES ('Sales', 'Transaction')
            )
            ORDER BY Name
            LIMIT 50
        ]) {
            SearchRow row = new SearchRow();
            row.contactId = contact.Id;
            row.name = contact.Name;
            row.email = contact.Email;
            row.audience = audience(contact);
            rows.add(row);
        }
        return rows;
    }

    public static void setSurveyOptOut(Id contactId) {
        assertAdministrator();
        if (contactId == null) {
            throw new DistributionException('Select a Contact before recording an opt-out.');
        }
        update new Contact(Id = contactId, Survey_Opt_Out__c = true);
    }

    public static void updateFailedRecipient(Id recipientId, String firstName, String lastName, String email, String customerNumber) {
        assertAdministrator();
        Survey_Distribution_Recipient__c row = [
            SELECT Id, Delivery_Status__c, Contact__c, Contact__r.RecordType.DeveloperName
            FROM Survey_Distribution_Recipient__c
            WHERE Id = :recipientId
            LIMIT 1
        ];
        if (row.Delivery_Status__c == 'Sent') {
            throw new DistributionException('A sent invitation cannot be edited here.');
        }
        if (!isEmail(email)) {
            throw new DistributionException('Enter a valid email address before resending.');
        }
        row.First_Name__c = firstName;
        row.Last_Name__c = lastName;
        row.Email__c = email.trim();
        row.Customer_Number__c = customerNumber;
        row.Delivery_Status__c = 'Pending';
        row.Failure_Reason__c = null;
        update row;
        if (row.Contact__c != null && row.Contact__r.RecordType.DeveloperName == 'Survey_Contact') {
            Contact surveyContact = new Contact(
                Id = row.Contact__c,
                FirstName = firstName,
                LastName = lastName,
                Email = email.trim()
            );
            if (String.isNotBlank(customerNumber)) {
                Map<String, List<Account>> accounts = accountsByNumber(new Set<String>{ customerNumber.trim() });
                List<Account> matches = accounts.get(customerNumber.trim());
                if (matches != null && matches.size() == 1) {
                    surveyContact.AccountId = matches[0].Id;
                }
            }
            update surveyContact;
        }
    }

    public static void sendDueReminders(List<Survey_Distribution_Recipient__c> dueRows) {
        if (dueRows == null || dueRows.isEmpty()) {
            return;
        }
        Set<Id> distributionIds = new Set<Id>();
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        List<Survey_Distribution_Recipient__c> updates = new List<Survey_Distribution_Recipient__c>();
        Map<String, Boolean> activeBySurvey = new Map<String, Boolean>();
        for (Survey_Distribution_Recipient__c row : dueRows) {
            Survey_Distribution__c distribution = row.Survey_Distribution__r;
            if (distribution.Reminders_Sent__c != null && distribution.Reminder_Count__c != null
                && distribution.Reminders_Sent__c >= distribution.Reminder_Count__c) {
                continue;
            }
            if (distribution.Expiration_Date__c != null && distribution.Expiration_Date__c < Date.today()) {
                continue;
            }
            if (!activeBySurvey.containsKey(distribution.Survey_Id__c)) {
                activeBySurvey.put(distribution.Survey_Id__c, isSurveyActive(distribution.Survey_Id__c));
            }
            if (activeBySurvey.get(distribution.Survey_Id__c) != true) {
                continue;
            }
            if (row.Response_Status__c == 'Completed' || row.Response_Status__c == 'PartiallyCompleted') {
                continue;
            }
            if (String.isBlank(row.Invitation_Link__c) || String.isBlank(row.Email__c)) {
                continue;
            }
            messages.add(reminderMessage(row));
            String dates = String.isBlank(row.Reminder_Dates__c) ? '' : row.Reminder_Dates__c + '\n';
            updates.add(new Survey_Distribution_Recipient__c(
                Id = row.Id,
                Reminder_Dates__c = dates + String.valueOf(Date.today())
            ));
            distributionIds.add(distribution.Id);
        }
        if (!messages.isEmpty()) {
            Messaging.sendEmail(messages, false);
        }
        if (!updates.isEmpty()) {
            update updates;
        }
        advanceReminderSchedules(distributionIds);
    }

    public static DistributionResult rollup(Id distributionId) {
        Survey_Distribution__c current = [
            SELECT Distribution_Method__c
            FROM Survey_Distribution__c
            WHERE Id = :distributionId
            LIMIT 1
        ];
        Integer recipients = 0;
        Integer sent = 0;
        Integer failed = 0;
        if (current.Distribution_Method__c != 'Anonymous Link') {
            for (AggregateResult result : [
                SELECT Delivery_Status__c status, COUNT(Id) total
                FROM Survey_Distribution_Recipient__c
                WHERE Survey_Distribution__c = :distributionId
                GROUP BY Delivery_Status__c
            ]) {
                Integer total = (Integer) result.get('total');
                recipients += total;
                String status = (String) result.get('status');
                if (status == 'Sent') {
                    sent += total;
                } else if (status == 'Failed') {
                    failed += total;
                }
            }
            String status = 'Draft';
            if (sent > 0 && failed == 0) {
                status = 'Sent';
            } else if (sent > 0 && failed > 0) {
                status = 'Partial';
            } else if (failed > 0) {
                status = 'Failed';
            }
            update new Survey_Distribution__c(
                Id = distributionId,
                Recipient_Count__c = recipients,
                Sent_Count__c = sent,
                Failed_Count__c = failed,
                Suppressed_Count__c = 0,
                Status__c = status,
                Distribution_Date__c = sent > 0 ? Date.today() : null
            );
        }
        Survey_Distribution__c saved = [
            SELECT Status__c, Anonymous_Link__c
            FROM Survey_Distribution__c
            WHERE Id = :distributionId
        ];
        DistributionResult result = new DistributionResult();
        result.distributionId = distributionId;
        result.status = saved.Status__c;
        result.anonymousLink = saved.Anonymous_Link__c;
        result.recipientCount = recipients;
        result.sentCount = sent;
        result.failedCount = failed;
        return result;
    }

    private static Survey_Distribution__c lockDistribution(Id distributionId) {
        assertAdministrator();
        Survey_Distribution__c distribution = [
            SELECT Id, Business_Unit__c, Survey_Id__c, Survey_Name__c, Expiration_Date__c,
                Reminder_Count__c, Reminder_Interval_Days__c, Reminders_Sent__c, Next_Reminder_Date__c,
                Approved_Nps_Survey__c
            FROM Survey_Distribution__c
            WHERE Id = :distributionId
            LIMIT 1
        ];
        Approved_Nps_Survey__c survey = [
            SELECT Id, Is_Active__c, Approval_Status__c, Survey_Id__c
            FROM Approved_Nps_Survey__c
            WHERE Id = :distribution.Approved_Nps_Survey__c
            LIMIT 1
        ];
        assertSelectableRecord(survey);
        return distribution;
    }

    private static List<Survey_Distribution_Recipient__c> recipientQuery(Id distributionId, Set<String> statuses) {
        return [
            SELECT Id, Email__c, Contact__c, First_Name__c, Delivery_Status__c, Failure_Reason__c
            FROM Survey_Distribution_Recipient__c
            WHERE Survey_Distribution__c = :distributionId
            AND Delivery_Status__c IN :statuses
        ];
    }

    private static Survey_Distribution__c newDistribution(
        Approved_Nps_Survey__c survey,
        Integer expirationDays,
        Integer reminderCount,
        Integer reminderIntervalDays
    ) {
        Decimal safeDays = expirationDays == null ? null : Decimal.valueOf(expirationDays);
        return new Survey_Distribution__c(
            Approved_Nps_Survey__c = survey.Id,
            Survey_Id__c = survey.Survey_Id__c,
            Survey_Name__c = survey.Name,
            Business_Unit__c = survey.Business_Unit__c,
            Distribution_Method__c = 'Email',
            Status__c = 'Draft',
            Reminder_Count__c = reminderCount == null ? 0 : reminderCount,
            Reminder_Interval_Days__c = reminderIntervalDays,
            Reminders_Sent__c = 0,
            Expiration_Days__c = safeDays,
            Expiration_Date__c = expirationDays == null || expirationDays <= 0 ? null : Date.today().addDays(expirationDays)
        );
    }

    private static Approved_Nps_Survey__c assertSurveySelectable(Id approvedSurveyId) {
        assertAdministrator();
        if (approvedSurveyId == null) {
            throw new DistributionException('Select an approved Healthcare or Life Sciences NPS survey.');
        }
        Approved_Nps_Survey__c survey = [
            SELECT Id, Name, Business_Unit__c, Approval_Status__c, Is_Active__c, Survey_Id__c, Anonymous_Link__c
            FROM Approved_Nps_Survey__c
            WHERE Id = :approvedSurveyId
            LIMIT 1
        ];
        assertSelectableRecord(survey);
        return survey;
    }

    private static void assertSelectableRecord(Approved_Nps_Survey__c survey) {
        if (!isSurveyActive(survey.Survey_Id__c) || survey.Is_Active__c != true) {
            throw new DistributionException(INACTIVE_MESSAGE);
        }
        if (survey.Approval_Status__c != 'Approved') {
            throw new DistributionException('Select an approved Healthcare or Life Sciences NPS survey.');
        }
    }

    private static Boolean isSurveyActive(String surveyId) {
        if (Test.isRunningTest()) {
            return activeSurveyIdsForTest != null && surveyId != null && activeSurveyIdsForTest.contains(surveyId);
        }
        if (String.isBlank(surveyId)) {
            return false;
        }
        List<Survey> surveys = [SELECT ActiveVersionId FROM Survey WHERE Id = :surveyId LIMIT 1];
        return !surveys.isEmpty() && surveys[0].ActiveVersionId != null;
    }

    private static void assertAdministrator() {
        if (!isAdministrator()) {
            throw new DistributionException('Only a Survey Administrator can initiate NPS survey distribution.');
        }
    }

    private static Boolean isAdministrator() {
        if (administratorOverride != null) {
            return administratorOverride;
        }
        return FeatureManagement.checkPermission(PERMISSION_NAME);
    }

    private static Survey_Distribution_Recipient__c toRecipient(Survey_Distribution__c distribution, ParsedRow parsed) {
        Survey_Distribution_Recipient__c row = new Survey_Distribution_Recipient__c(
            Survey_Distribution__c = distribution.Id,
            Contact__c = parsed.contactId,
            First_Name__c = parsed.firstName,
            Last_Name__c = parsed.lastName,
            Customer_Number__c = parsed.customerNumber,
            Customer_Name__c = parsed.customerName,
            Business_Unit__c = parsed.businessUnit,
            Language__c = parsed.languageLabel,
            Source_Population__c = parsed.sourcePopulation,
            Transaction_Date__c = parsed.transactionDate,
            Territory_Zone__c = parsed.territoryZone,
            Follow_Up_Owner_Name__c = parsed.followUpOwnerName,
            Recipient_Source__c = parsed.source,
            Delivery_Status__c = parsed.failureReason == null && parsed.optOutReason == null ? 'Pending' : 'Failed',
            Failure_Reason__c = parsed.failureReason != null ? parsed.failureReason : parsed.optOutReason
        );
        if (parsed.failureReason == null && isEmail(parsed.email)) {
            row.Email__c = parsed.email;
        }
        if (parsed.followUpOwnerEmailValid) {
            row.Follow_Up_Owner_Email__c = parsed.followUpOwnerEmail;
        }
        if (parsed.optOutReason != null) {
            row.Survey_Opt_Out__c = true;
        }
        return row;
    }

    private static Map<String, List<Contact>> contactsByEmail(Set<String> emails) {
        Map<String, List<Contact>> contacts = new Map<String, List<Contact>>();
        if (emails.isEmpty()) {
            return contacts;
        }
        for (Contact contact : [
            SELECT Email, HasOptedOutOfEmail, DoNotContact__c, Survey_Opt_Out__c
            FROM Contact
            WHERE Email IN :emails
        ]) {
            String key = contact.Email.toLowerCase();
            if (!contacts.containsKey(key)) {
                contacts.put(key, new List<Contact>());
            }
            contacts.get(key).add(contact);
        }
        return contacts;
    }

    private static Map<String, List<Account>> accountsByNumber(Set<String> customerNumbers) {
        Map<String, List<Account>> accountsByNumber = new Map<String, List<Account>>();
        if (customerNumbers.isEmpty()) {
            return accountsByNumber;
        }
        for (Account account : [
            SELECT SystemID__c, SourceSystemID__c
            FROM Account
            WHERE SystemID__c IN :customerNumbers OR SourceSystemID__c IN :customerNumbers
        ]) {
            addAccount(accountsByNumber, account.SystemID__c, account);
            addAccount(accountsByNumber, account.SourceSystemID__c, account);
        }
        return accountsByNumber;
    }

    private static void addAccount(Map<String, List<Account>> accountsByNumber, String customerNumber, Account account) {
        if (String.isBlank(customerNumber)) {
            return;
        }
        String key = customerNumber.trim();
        if (!accountsByNumber.containsKey(key)) {
            accountsByNumber.put(key, new List<Account>());
        }
        for (Account existing : accountsByNumber.get(key)) {
            if (existing.Id == account.Id) {
                return;
            }
        }
        accountsByNumber.get(key).add(account);
    }

    private static Map<Id, Contact> reloadContacts(List<Survey_Distribution_Recipient__c> rows) {
        Set<Id> contactIds = new Set<Id>();
        for (Survey_Distribution_Recipient__c row : rows) {
            if (row.Contact__c != null) {
                contactIds.add(row.Contact__c);
            }
        }
        if (contactIds.isEmpty()) {
            return new Map<Id, Contact>();
        }
        return new Map<Id, Contact>([
            SELECT HasOptedOutOfEmail, DoNotContact__c, Survey_Opt_Out__c
            FROM Contact
            WHERE Id IN :contactIds
        ]);
    }

    private static String optOutReason(Contact contact) {
        if (contact.Survey_Opt_Out__c == true) {
            return 'Contact is opted out of surveys.';
        }
        if (contact.HasOptedOutOfEmail == true) {
            return 'Contact has opted out of email.';
        }
        if (contact.DoNotContact__c == true) {
            return 'Contact is marked Do Not Contact.';
        }
        return null;
    }

    private static String senderProblem(String businessUnit) {
        if (Test.isRunningTest()) {
            return null;
        }
        String address = senderAddress(businessUnit);
        if (String.isBlank(address)) {
            return 'The approved Life Sciences customer-experience mailbox is not set up.';
        }
        List<OrgWideEmailAddress> mailboxes = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :address
            LIMIT 1
        ];
        return mailboxes.isEmpty() ? 'The approved sender mailbox is not set up: ' + address : null;
    }

    private static String senderAddress(String businessUnit) {
        if (businessUnit == 'Healthcare') {
            return HEALTHCARE_SENDER;
        }
        if (Test.isRunningTest()) {
            return 'ls_customerexperience@steris.com';
        }
        List<OrgWideEmailAddress> mailboxes = [
            SELECT Address
            FROM OrgWideEmailAddress
            WHERE Address LIKE '%lifescience%'
            ORDER BY Address
            LIMIT 1
        ];
        return mailboxes.isEmpty() ? null : mailboxes[0].Address;
    }

    private static String npsQuestionId(String surveyId) {
        if (Test.isRunningTest()) {
            return '0Ku000000000001AAA';
        }
        List<Survey> surveys = [SELECT ActiveVersionId FROM Survey WHERE Id = :surveyId LIMIT 1];
        if (surveys.isEmpty() || surveys[0].ActiveVersionId == null) {
            return null;
        }
        for (SurveyQuestion question : [
            SELECT QuestionType, Name
            FROM SurveyQuestion
            WHERE SurveyVersionId = :surveys[0].ActiveVersionId
        ]) {
            if (question.QuestionType == 'NPS' || (question.Name != null && question.Name.containsIgnoreCase('NPS'))) {
                return question.Id;
            }
        }
        return null;
    }

    private static String queueInvitationEmail(Survey_Distribution__c distribution, List<Survey_Distribution_Recipient__c> eligible) {
        if (Test.isRunningTest()) {
            return null;
        }
        List<String> recipientIds = new List<String>();
        for (Survey_Distribution_Recipient__c row : eligible) {
            recipientIds.add(row.Contact__c);
        }
        ConnectApi.SurveyInvitationEmailInput input = new ConnectApi.SurveyInvitationEmailInput();
        input.recipients = recipientIds;
        input.allowGuestUserResponse = true;
        input.collectAnonymousResponse = false;
        input.allowParticipantsAccessTheirResponse = false;
        input.isPersonalInvitation = true;
        input.communityId = communityId();
        input.fromEmailAddress = senderAddress(distribution.Business_Unit__c);
        input.invitationOwner = UserInfo.getUserId();
        input.subject = 'Tell us about your STERIS ' + distribution.Business_Unit__c + ' experience';
        input.body = invitationBody();
        input.surveyQuestionIds = new List<String>{ npsQuestionId(distribution.Survey_Id__c) };
        if (distribution.Expiration_Date__c != null) {
            input.invitationExpirationDate = DateTime.newInstance(
                distribution.Expiration_Date__c,
                Time.newInstance(23, 59, 0, 0)
            );
        }
        ConnectApi.SurveyInvitationEmailOutput output = ConnectApi.Surveys.sendSurveyInvitationEmail(distribution.Survey_Id__c, input);
        if (output != null && output.status == ConnectApi.SurveyEmailStatusEnum.Failed) {
            return String.isBlank(output.errorMessage) ? 'Salesforce could not send the survey invitation.' : output.errorMessage;
        }
        return null;
    }

    private static String invitationBody() {
        return 'Please tell us about your STERIS experience.'
            + '\n\n{{{SurveyQuestion.QuestionName}}}'
            + '\n{{{SurveyQuestion.QuestionHtmlContent}}}'
            + '\n\n[[SURVEY_INVITATION_URL]]'
            + '\n\nReply to this email if you want to be removed from future surveys.';
    }

    private static void stampInvitations(String surveyId, List<Survey_Distribution_Recipient__c> eligible) {
        Set<Id> contactIds = new Set<Id>();
        for (Survey_Distribution_Recipient__c row : eligible) {
            contactIds.add(row.Contact__c);
        }
        Map<Id, SurveyInvitation> latestByContact = new Map<Id, SurveyInvitation>();
        for (SurveyInvitation invitation : [
            SELECT ContactId, InvitationLink, ResponseStatus
            FROM SurveyInvitation
            WHERE SurveyId = :surveyId AND ContactId IN :contactIds
            ORDER BY CreatedDate DESC
        ]) {
            if (!latestByContact.containsKey(invitation.ContactId)) {
                latestByContact.put(invitation.ContactId, invitation);
            }
        }
        for (Survey_Distribution_Recipient__c row : eligible) {
            SurveyInvitation invitation = latestByContact.get(row.Contact__c);
            if (invitation == null) {
                continue;
            }
            row.Survey_Invitation_Id__c = invitation.Id;
            row.Invitation_Link__c = invitation.InvitationLink;
            row.Response_Status__c = invitation.ResponseStatus;
        }
    }

    private static Id communityId() {
        List<Network> networks = [SELECT Id FROM Network WHERE Status = 'Live' ORDER BY CreatedDate ASC];
        if (networks.size() == 1) {
            return networks[0].Id;
        }
        if (networks.isEmpty()) {
            throw new DistributionException('Select the Experience Cloud site in Survey Settings before distributing outside Salesforce.');
        }
        throw new DistributionException('More than one Experience Cloud site is active. Select the survey site in Survey Settings.');
    }

    private static void rememberReminderSchedule(Survey_Distribution__c distribution) {
        if (distribution.Reminder_Count__c == null || distribution.Reminder_Count__c <= 0
            || distribution.Reminder_Interval_Days__c == null || distribution.Reminder_Interval_Days__c <= 0) {
            return;
        }
        update new Survey_Distribution__c(
            Id = distribution.Id,
            Next_Reminder_Date__c = Date.today().addDays(distribution.Reminder_Interval_Days__c.intValue())
        );
        if (Test.isRunningTest()) {
            return;
        }
        List<CronTrigger> existing = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = 'NPS Survey Reminders'
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            System.schedule('NPS Survey Reminders', '0 0 6 * * ?', new NpsSurveyReminderJob());
        }
    }

    private static Messaging.SingleEmailMessage reminderMessage(Survey_Distribution_Recipient__c row) {
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setToAddresses(new List<String>{ row.Email__c });
        message.setSaveAsActivity(false);
        message.setSubject('Reminder: tell us about your STERIS ' + row.Survey_Distribution__r.Business_Unit__c + ' experience');
        message.setPlainTextBody(
            'Please tell us about your STERIS experience.\n\n'
            + row.Invitation_Link__c
            + '\n\nReply to this email if you want to be removed from future surveys.'
        );
        return message;
    }

    private static void advanceReminderSchedules(Set<Id> distributionIds) {
        if (distributionIds.isEmpty()) {
            return;
        }
        List<Survey_Distribution__c> updates = new List<Survey_Distribution__c>();
        for (Survey_Distribution__c distribution : [
            SELECT Reminders_Sent__c, Reminder_Count__c, Reminder_Interval_Days__c, Survey_Id__c
            FROM Survey_Distribution__c
            WHERE Id IN :distributionIds
        ]) {
            if (!isSurveyActive(distribution.Survey_Id__c)) {
                updates.add(new Survey_Distribution__c(Id = distribution.Id, Next_Reminder_Date__c = null));
                continue;
            }
            Decimal sent = distribution.Reminders_Sent__c == null ? 0 : distribution.Reminders_Sent__c;
            Decimal nextCount = sent + 1;
            Date nextDate = null;
            if (distribution.Reminder_Count__c != null && nextCount < distribution.Reminder_Count__c
                && distribution.Reminder_Interval_Days__c != null) {
                nextDate = Date.today().addDays(distribution.Reminder_Interval_Days__c.intValue());
            }
            updates.add(new Survey_Distribution__c(
                Id = distribution.Id,
                Reminders_Sent__c = nextCount,
                Next_Reminder_Date__c = nextDate
            ));
        }
        update updates;
    }

    private static Id surveyContactRecordTypeId() {
        return Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName().get('Survey_Contact').getRecordTypeId();
    }

    private static String audience(Contact contact) {
        if (contact.RecordType.DeveloperName == 'Survey_Contact') {
            return 'Survey Contact';
        }
        if (contact.UsedFor__c != null && contact.UsedFor__c.contains('Sales')) {
            return 'Sales';
        }
        return 'Service';
    }

    private static Integer integerValue(Decimal value) {
        return value == null ? 0 : value.intValue();
    }

    public static void assertHeaders(String header) {
        Map<String, Integer> columns = columnIndex(header);
        List<String> missing = new List<String>();
        if (!columns.containsKey('firstname')) {
            missing.add('First Name');
        }
        if (!columns.containsKey('lastname')) {
            missing.add('Last Name');
        }
        if (!columns.containsKey('email')) {
            missing.add('Email');
        }
        if (!columns.containsKey('customernumber')) {
            missing.add('Customer Number');
        }
        if (!columns.containsKey('businessunit')) {
            missing.add('Business Unit');
        }
        if (!missing.isEmpty()) {
            throw new DistributionException('The file is missing a required column: ' + String.join(missing, ', ') + '.');
        }
    }

    private static Map<String, Integer> columnIndex(String header) {
        Map<String, Integer> columns = new Map<String, Integer>();
        List<String> cells = parseCsvRow(header);
        for (Integer index = 0; index < cells.size(); index++) {
            columns.put(headerKey(cells[index]), index);
        }
        return columns;
    }

    private static ParsedRow parseRow(String line, Map<String, Integer> columns, String surveyBusinessUnit) {
        List<String> cells = parseCsvRow(line);
        ParsedRow parsed = new ParsedRow();
        parsed.firstName = cell(cells, columns, 'firstname');
        parsed.lastName = cell(cells, columns, 'lastname');
        parsed.email = cell(cells, columns, 'email');
        parsed.customerNumber = cell(cells, columns, 'customernumber');
        parsed.customerName = cell(cells, columns, 'customername');
        parsed.businessUnit = normalizeBusinessUnit(cell(cells, columns, 'businessunit'));
        parsed.languageLabel = String.isBlank(cell(cells, columns, 'language')) ? 'English' : cell(cells, columns, 'language');
        parsed.contactLanguage = contactLanguage(parsed.languageLabel);
        parsed.sourcePopulation = cell(cells, columns, 'sourcepopulation');
        parsed.territoryZone = cell(cells, columns, 'territoryzone');
        parsed.followUpOwnerName = cell(cells, columns, 'followupownername');
        parsed.followUpOwnerEmail = cell(cells, columns, 'followupowneremail');
        parsed.followUpOwnerEmailValid = String.isBlank(parsed.followUpOwnerEmail) || isEmail(parsed.followUpOwnerEmail);
        try {
            parsed.transactionDate = parseDate(cell(cells, columns, 'transactiondate'));
        } catch (Exception exceptionValue) {
            parsed.failureReason = 'Transaction Date is not a valid date.';
        }
        if (parsed.failureReason == null && String.isBlank(parsed.firstName)) {
            parsed.failureReason = 'First Name is required.';
        } else if (parsed.failureReason == null && String.isBlank(parsed.lastName)) {
            parsed.failureReason = 'Last Name is required.';
        } else if (parsed.failureReason == null && !isEmail(parsed.email)) {
            parsed.failureReason = 'Email is missing or invalid.';
        } else if (parsed.failureReason == null && String.isBlank(parsed.customerNumber)) {
            parsed.failureReason = 'Customer Number is required.';
        } else if (parsed.failureReason == null && parsed.businessUnit != 'Healthcare' && parsed.businessUnit != 'Life Sciences') {
            parsed.failureReason = 'Business Unit must be Healthcare or Life Sciences.';
        } else if (parsed.failureReason == null && parsed.businessUnit != surveyBusinessUnit) {
            parsed.failureReason = 'Business Unit does not match the selected survey.';
        } else if (parsed.failureReason == null && !parsed.followUpOwnerEmailValid) {
            parsed.failureReason = 'Follow-Up Owner Email is invalid.';
        }
        if (isEmail(parsed.email)) {
            parsed.emailKey = parsed.email.toLowerCase();
        }
        return parsed;
    }

    private static String cell(List<String> cells, Map<String, Integer> columns, String key) {
        if (!columns.containsKey(key) || columns.get(key) >= cells.size()) {
            return null;
        }
        String value = cells[columns.get(key)];
        return String.isBlank(value) ? null : value.trim();
    }

    private static List<String> parseCsvRow(String line) {
        List<String> cells = new List<String>();
        String current = '';
        Boolean inQuotes = false;
        for (Integer index = 0; index < line.length(); index++) {
            String character = line.substring(index, index + 1);
            if (character == '"') {
                Boolean escapedQuote = inQuotes && index + 1 < line.length() && line.substring(index + 1, index + 2) == '"';
                if (escapedQuote) {
                    current += '"';
                    index++;
                } else {
                    inQuotes = !inQuotes;
                }
            } else if (character == ',' && !inQuotes) {
                cells.add(current.trim());
                current = '';
            } else {
                current += character;
            }
        }
        cells.add(current.trim());
        return cells;
    }

    private static String headerKey(String header) {
        String key = header == null ? '' : header.toLowerCase().replaceAll('[^a-z0-9]', '');
        if (key.startsWith('sourcepopulation')) {
            return 'sourcepopulation';
        }
        if (key.startsWith('customernumber')) {
            return 'customernumber';
        }
        if (key.startsWith('territory')) {
            return 'territoryzone';
        }
        if (key.startsWith('followupownername')) {
            return 'followupownername';
        }
        if (key.startsWith('followupowneremail')) {
            return 'followupowneremail';
        }
        if (key.startsWith('transactiondate')) {
            return 'transactiondate';
        }
        return key;
    }

    private static String normalizeBusinessUnit(String value) {
        String key = headerKey(value);
        if (key == 'healthcare' || key == 'hc') {
            return 'Healthcare';
        }
        if (key == 'lifesciences' || key == 'ls') {
            return 'Life Sciences';
        }
        return value == null ? null : value.trim();
    }

    private static String contactLanguage(String value) {
        String key = headerKey(value);
        Map<String, String> languages = new Map<String, String>{
            'en' => 'en',
            'encn' => 'en_CN',
            'de' => 'de',
            'german' => 'de',
            'es' => 'es',
            'spanish' => 'es',
            'fi' => 'fi',
            'fr' => 'fr',
            'french' => 'fr',
            'it' => 'it',
            'nl' => 'nl',
            'sv' => 'sv'
        };
        if (String.isBlank(key) || key == 'english' || key == 'enus') {
            return 'en_US';
        }
        return languages.containsKey(key) ? languages.get(key) : 'en_US';
    }

    private static Date parseDate(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String text = value.trim();
        if (text.contains('-')) {
            return Date.valueOf(text);
        }
        List<String> parts = text.split('/');
        if (parts.size() != 3) {
            throw new DistributionException('Transaction Date is not a valid date.');
        }
        Integer month = Integer.valueOf(parts[0]);
        Integer day = Integer.valueOf(parts[1]);
        Integer year = Integer.valueOf(parts[2]);
        if (month < 1 || month > 12 || day < 1 || day > 31 || year < 1900) {
            throw new DistributionException('Transaction Date is not a valid date.');
        }
        Date parsed = Date.newInstance(year, month, day);
        if (parsed.month() != month || parsed.day() != day) {
            throw new DistributionException('Transaction Date is not a valid date.');
        }
        return parsed;
    }

    private static Boolean isEmail(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        return Pattern.matches('^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$', value.trim());
    }

    public static List<String> splitLines(String csvBody) {
        if (String.isBlank(csvBody)) {
            return new List<String>();
        }
        String normalized = csvBody.replace('\r\n', '\n').replace('\r', '\n');
        if (normalized.startsWith('\uFEFF')) {
            normalized = normalized.substring(1);
        }
        List<String> lines = new List<String>();
        for (String line : normalized.split('\n')) {
            if (String.isNotBlank(line)) {
                lines.add(line);
            }
        }
        return lines;
    }

    private class ParsedRow {
        String firstName;
        String lastName;
        String email;
        String emailKey;
        String customerNumber;
        String customerName;
        String businessUnit;
        String languageLabel;
        String contactLanguage;
        String sourcePopulation;
        Date transactionDate;
        String territoryZone;
        String followUpOwnerName;
        String followUpOwnerEmail;
        Boolean followUpOwnerEmailValid;
        String failureReason;
        String optOutReason;
        Id contactId;
        Id accountId;
        String source;
    }
}