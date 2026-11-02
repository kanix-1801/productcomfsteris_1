/**
 * @author Suraj Thapliyal
 * @date 2026/08/17
 *
 * @group Sample
 *
 * @description
 * GC-3226 - Sample create access (trigger), Follow-up Custom Notification + email.
 * GC-3225 - Stamps Opportunity.HasSampleActivity__c when a Sample is created.
 */
public with sharing class SampleService {

    public static final String ACCESS_DENIED_MESSAGE =
        'Only Opportunity Team Members can create a Sample for this Opportunity.';
    public static final String CUSTOM_NOTIFICATION_TYPE_DEVELOPER_NAME = 'SampleFollowUpReminder';
    public static final String EMAIL_TEMPLATE_DEVELOPER_NAME = 'SampleFollowUpReminder';
    public static final String NOTIFICATION_TITLE = 'Sample Follow-up Reminder';
    /**
     * @description Salesforce max SingleEmailMessage count per Messaging.sendEmail call.
     */
    public static final Integer DEFAULT_EMAIL_CHUNK_SIZE = 100;
    private static final String CLASS_NAME = 'SampleService';
    private static final String MERGE_SAMPLE_NAME = '{{{Sample__c.Name}}}';
    private static final String MERGE_FOLLOW_UP_DATE = '{{{Sample__c.FollowUpDate__c}}}';
    private static final String MERGE_RECORD_URL = 'SAMPLE_RECORD_URL';

    @TestVisible
    private static Id emailTemplateIdOverride;
    @TestVisible
    private static Id customNotificationTypeIdOverride;
    @TestVisible
    private static Boolean isSkipOutboundNotificationsInTest = false;
    @TestVisible
    private static Boolean isForceMissingEmailTemplate = false;
    @TestVisible
    private static Boolean isForceMissingNotificationType = false;

    /**
     * @description Private constructor — static utility / service class (PMD UseSingleton).
     */
    private SampleService() {
    }

    /**
     * @description
     * GC-3226 - Before insert: blocks Sample create unless the running user is Opportunity Owner
     *           or Opportunity Team Member of RelatedOpportunity__c. Two queries for the whole
     *           trigger batch (owners + team membership), then addError per failing row.
     *
     * @param samples Trigger.new Sample rows from before insert
     */
    public static void enforceCreateAccess(List<Sample__c> samples) {
        if (samples == null || samples.isEmpty()) {
            Logger.debug(CLASS_NAME + '.enforceCreateAccess: empty scope');
        } else {
            Set<Id> opportunityIds = collectRelatedOpportunityIds(samples);
            Set<Id> allowedOpportunityIds = collectOpportunityIdsCurrentUserMayCreateSampleFor(opportunityIds);

            for (Sample__c sampleRecord : samples) {
                if (sampleRecord != null) {
                    Boolean isAllowed = sampleRecord.RelatedOpportunity__c != null
                        && allowedOpportunityIds.contains(sampleRecord.RelatedOpportunity__c);
                    if (!isAllowed) {
                        sampleRecord.addError(ACCESS_DENIED_MESSAGE);
                    }
                }
            }
        }
    }

    /**
     * @description GC-3226 - Opportunity Ids the running user may create a Sample against.
     *              One owner query and one team-member query for the full Id set.
     * @param opportunityIds Related Opportunity Ids.
     * @return Opportunity Ids where the running user is Owner or Team Member.
     */
    private static Set<Id> collectOpportunityIdsCurrentUserMayCreateSampleFor(Set<Id> opportunityIds) {
        Set<Id> allowedOpportunityIds = new Set<Id>();
        if (opportunityIds != null && !opportunityIds.isEmpty()) {
            Id currentUserId = UserInfo.getUserId();
            Map<Id, Id> ownerIdByOpportunityId =
                SampleSelector.selectOwnerIdByOpportunityId(opportunityIds);
            Set<Id> teamOpportunityIds =
                SampleSelector.selectOpportunityIdsWhereUserIsTeamMember(opportunityIds, currentUserId);

            for (Id opportunityId : opportunityIds) {
                Boolean isOwner = ownerIdByOpportunityId.get(opportunityId) == currentUserId;
                Boolean isTeamMember = teamOpportunityIds.contains(opportunityId);
                if (isOwner || isTeamMember) {
                    allowedOpportunityIds.add(opportunityId);
                }
            }
        }
        return allowedOpportunityIds;
    }

    /**
     * @description
     * GC-3225 - Bulk-stamps Opportunity.HasSampleActivity__c = true for Related Opportunities
     *           on Sample after-insert. Uses SYSTEM_MODE so FLS does not block the stamp.
     *           Deduplicates Opportunity Ids and skips Opportunities already stamped.
     *
     * @param samples Trigger.new Sample rows from after insert
     */
    public static void markRelatedOpportunitiesHasSampleActivity(List<Sample__c> samples) {
        if (samples == null || samples.isEmpty()) {
            Logger.debug(CLASS_NAME + '.markRelatedOpportunitiesHasSampleActivity: empty scope');
        } else {
            Set<Id> opportunityIds = collectRelatedOpportunityIds(samples);
            stampHasSampleActivity(opportunityIds);
            Logger.saveLog();
        }
    }

    /**
     * @description
     * GC-3225 - Collects distinct RelatedOpportunity__c Ids from Sample rows (bulk-safe).
     *
     * @param samples Sample rows
     * @return Distinct related Opportunity Ids
     */
    private static Set<Id> collectRelatedOpportunityIds(List<Sample__c> samples) {
        Set<Id> opportunityIds = new Set<Id>();
        for (Sample__c sampleRecord : samples) {
            if (sampleRecord != null && sampleRecord.RelatedOpportunity__c != null) {
                opportunityIds.add(sampleRecord.RelatedOpportunity__c);
            }
        }
        return opportunityIds;
    }

    /**
     * @description
     * GC-3225 - Queries Opportunities missing HasSampleActivity__c and updates them in one DML.
     *
     * @param opportunityIds Related Opportunity Ids to stamp
     */
    private static void stampHasSampleActivity(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            Logger.debug(
                CLASS_NAME + '.stampHasSampleActivity: no Related Opportunity Ids'
            );
        } else {
            List<Opportunity> opportunitiesMissingFlag =
                SampleSelector.selectOpportunitiesMissingSampleActivity(opportunityIds);

            if (opportunitiesMissingFlag.isEmpty()) {
                Logger.debug(
                    CLASS_NAME + '.stampHasSampleActivity: all Opportunities already stamped'
                );
            } else {
                List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();
                for (Opportunity opportunityRecord : opportunitiesMissingFlag) {
                    opportunitiesToUpdate.add(
                        new Opportunity(
                            Id = opportunityRecord.Id,
                            HasSampleActivity__c = true
                        )
                    );
                }

                List<Database.SaveResult> saveResults = Database.update(
                    opportunitiesToUpdate,
                    false,
                    AccessLevel.SYSTEM_MODE
                );
                logOpportunityStampResults(opportunitiesToUpdate, saveResults);
            }
        }
    }

    /**
     * @description
     * GC-3225 - Logs partial success/failure for Opportunity HasSampleActivity__c stamp DML.
     *
     * @param opportunities Updated Opportunity stubs
     * @param saveResults Database.update results aligned by index
     */
    private static void logOpportunityStampResults(
        List<Opportunity> opportunities,
        List<Database.SaveResult> saveResults
    ) {
        Integer successCount = 0;
        Integer failureCount = 0;

        for (Integer index = 0; index < saveResults.size(); index++) {
            Database.SaveResult saveResult = saveResults[index];
            if (saveResult.isSuccess()) {
                successCount++;
            } else {
                failureCount++;
                for (Database.Error error : saveResult.getErrors()) {
                    Logger.error(
                        CLASS_NAME + '.logOpportunityStampResults: Opportunity=' +
                        opportunities[index].Id +
                        ' statusCode=' +
                        error.getStatusCode() +
                        ' message=' +
                        error.getMessage()
                    );
                }
            }
        }

        if (failureCount > 0) {
            Logger.warn(
                CLASS_NAME + '.logOpportunityStampResults: successCount=' +
                successCount +
                ' failureCount=' +
                failureCount
            );
        } else {
            Logger.info(
                CLASS_NAME + '.logOpportunityStampResults: successCount=' + successCount
            );
        }
    }

    /**
     * @description GC-3226 - Resets Follow-up Notified when Follow-up Date changes or Reminder is re-enabled.
     * @param samples Trigger.new
     * @param oldMap Trigger.oldMap
     */
    public static void resetFollowUpNotifiedOnChange(
        List<Sample__c> samples,
        Map<Id, Sample__c> oldMap
    ) {
        if (samples != null && !samples.isEmpty() && oldMap != null) {
            for (Sample__c sampleRecord : samples) {
                Sample__c oldSample = oldMap.get(sampleRecord.Id);
                if (oldSample == null) {
                    continue;
                }

                Boolean isDateChanged = oldSample.FollowUpDate__c != sampleRecord.FollowUpDate__c;
                Boolean isReminderReEnabled =
                    oldSample.FollowUpReminder__c != true && sampleRecord.FollowUpReminder__c == true;

                if (isDateChanged || isReminderReEnabled) {
                    sampleRecord.FollowUpNotified__c = false;
                }
            }
        }
    }

    /**
     * @description GC-3226 - Sends Follow-up bell + email for due Samples; marks notified only when both succeed.
     *              Emails are sent in bulk (chunked). Each Custom Notification has a unique Sample target,
     *              so bells are sent per record (platform API does not support mixed-target bulk send).
     * @param samples Sample rows with CreatedById / Name / follow-up fields populated.
     */
    public static void sendFollowUpNotifications(List<Sample__c> samples) {
        if (samples == null || samples.isEmpty()) {
            Logger.debug(CLASS_NAME + '.sendFollowUpNotifications: empty scope');
        } else {
            List<Sample__c> eligibleSamples = collectEligibleFollowUpSamples(samples);
            Logger.info(
                CLASS_NAME + '.sendFollowUpNotifications: sampleCount=' + samples.size() +
                ' eligibleCount=' + eligibleSamples.size()
            );

            if (!eligibleSamples.isEmpty()) {
                Id notificationTypeId = resolveCustomNotificationTypeId();
                EmailTemplateContent emailTemplate = loadEmailTemplateContent();
                Set<Id> bellSuccessIds = sendFollowUpBells(eligibleSamples, notificationTypeId);
                Set<Id> emailSuccessIds = sendFollowUpEmails(eligibleSamples, emailTemplate);
                markSuccessfulFollowUpsNotified(eligibleSamples, bellSuccessIds, emailSuccessIds);
            }

            Logger.saveLog();
        }
    }

    /**
     * @description Updates FollowUpNotified__c and logs partial DML failures.
     * @param samplesToMarkNotified Sample stub rows with Id and FollowUpNotified__c
     */
    private static void markSamplesNotified(List<Sample__c> samplesToMarkNotified) {
        Database.SaveResult[] results = Database.update(samplesToMarkNotified, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                Logger.error(
                    CLASS_NAME + '.markSamplesNotified failed Sample=' +
                    samplesToMarkNotified[i].Id + ' errors=' + results[i].getErrors()
                );
            }
        }
    }

    private static List<Sample__c> collectEligibleFollowUpSamples(List<Sample__c> samples) {
        List<Sample__c> eligibleSamples = new List<Sample__c>();
        for (Sample__c sampleRecord : samples) {
            if (isEligibleForFollowUpNotification(sampleRecord)) {
                eligibleSamples.add(sampleRecord);
            }
        }
        return eligibleSamples;
    }

    private static Boolean isEligibleForFollowUpNotification(Sample__c sampleRecord) {
        return sampleRecord != null
            && sampleRecord.FollowUpReminder__c == true
            && sampleRecord.FollowUpDate__c != null
            && sampleRecord.FollowUpNotified__c != true;
    }

    private static void markSuccessfulFollowUpsNotified(
        List<Sample__c> eligibleSamples,
        Set<Id> bellSuccessIds,
        Set<Id> emailSuccessIds
    ) {
        List<Sample__c> samplesToMarkNotified = new List<Sample__c>();
        for (Sample__c sampleRecord : eligibleSamples) {
            Boolean isBellSent = bellSuccessIds.contains(sampleRecord.Id);
            Boolean isEmailSent = emailSuccessIds.contains(sampleRecord.Id);
            if (isBellSent && isEmailSent) {
                samplesToMarkNotified.add(new Sample__c(
                    Id = sampleRecord.Id,
                    FollowUpNotified__c = true
                ));
            } else {
                Logger.warn(
                    CLASS_NAME + '.sendFollowUpNotifications incomplete for Sample=' +
                    sampleRecord.Id + ' bell=' + isBellSent + ' email=' + isEmailSent
                );
            }
        }
        if (!samplesToMarkNotified.isEmpty()) {
            markSamplesNotified(samplesToMarkNotified);
        }
    }

    /**
     * @description Sends one Custom Notification per Sample (unique target record).
     *              Recipients for the same notification can be a Set, but TargetId cannot be bulked.
     */
    private static Set<Id> sendFollowUpBells(List<Sample__c> eligibleSamples, Id notificationTypeId) {
        Set<Id> successIds = new Set<Id>();
        if (isSkipOutboundNotificationsInTest == true) {
            successIds.addAll(collectSampleIds(eligibleSamples));
        } else if (notificationTypeId == null) {
            Logger.warn(CLASS_NAME + '.sendFollowUpBells: notification type not found');
        } else {
            for (Sample__c sampleRecord : eligibleSamples) {
                if (sendFollowUpBell(sampleRecord, notificationTypeId)) {
                    successIds.add(sampleRecord.Id);
                }
            }
        }
        return successIds;
    }

    private static Boolean sendFollowUpBell(Sample__c sampleRecord, Id notificationTypeId) {
        Boolean isSent = false;
        try {
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle(NOTIFICATION_TITLE);
            notification.setBody(
                'Follow up on Sample ' + sampleRecord.Name + '. Open the record to continue.'
            );
            notification.setNotificationTypeId(notificationTypeId);
            notification.setTargetId(sampleRecord.Id);
            notification.send(new Set<String>{ String.valueOf(sampleRecord.CreatedById) });
            isSent = true;
        } catch (Exception e) {
            Logger.error(
                CLASS_NAME + '.sendFollowUpBell failed Sample=' + sampleRecord.Id,
                e
            );
        }
        return isSent;
    }

    /**
     * @description Builds all Follow-up emails in memory, then sends them in chunks (max 100 per invocation).
     *              Template merge is done in Apex so renderStoredEmailTemplate is not called in a loop.
     */
    private static Set<Id> sendFollowUpEmails(
        List<Sample__c> eligibleSamples,
        EmailTemplateContent emailTemplate
    ) {
        Set<Id> successIds = new Set<Id>();
        if (isSkipOutboundNotificationsInTest == true) {
            successIds.addAll(collectSampleIds(eligibleSamples));
        } else {
            List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
            List<Id> mailSampleIds = new List<Id>();
            for (Sample__c sampleRecord : eligibleSamples) {
                mails.add(buildFollowUpEmail(sampleRecord, emailTemplate));
                mailSampleIds.add(sampleRecord.Id);
            }
            successIds.addAll(sendEmailChunks(mails, mailSampleIds));
        }
        return successIds;
    }

    private static Set<Id> sendEmailChunks(
        List<Messaging.SingleEmailMessage> mails,
        List<Id> mailSampleIds
    ) {
        Set<Id> successIds = new Set<Id>();
        Integer chunkSize = resolveEmailChunkSize();
        Integer startIndex = 0;
        while (startIndex < mails.size()) {
            Integer endIndex = Math.min(startIndex + chunkSize, mails.size());
            List<Messaging.SingleEmailMessage> chunk = new List<Messaging.SingleEmailMessage>();
            List<Id> chunkSampleIds = new List<Id>();
            for (Integer i = startIndex; i < endIndex; i++) {
                chunk.add(mails[i]);
                chunkSampleIds.add(mailSampleIds[i]);
            }
            successIds.addAll(sendEmailChunk(chunk, chunkSampleIds));
            startIndex = endIndex;
        }
        return successIds;
    }

    private static Set<Id> sendEmailChunk(
        List<Messaging.SingleEmailMessage> chunk,
        List<Id> chunkSampleIds
    ) {
        Set<Id> successIds = new Set<Id>();
        try {
            Messaging.SendEmailResult[] results = Messaging.sendEmail(chunk, false);
            if (results != null) {
                Integer resultCount = Math.min(results.size(), chunkSampleIds.size());
                for (Integer i = 0; i < resultCount; i++) {
                    if (results[i].isSuccess()) {
                        successIds.add(chunkSampleIds[i]);
                    } else {
                        Logger.warn(
                            CLASS_NAME + '.sendFollowUpEmails: send failed Sample=' +
                            chunkSampleIds[i] + ' errors=' + formatSendEmailErrors(results[i])
                        );
                    }
                }
            }
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.sendFollowUpEmails chunk failed', e);
        }
        return successIds;
    }

    /**
     * @description GC-3226 - Builds a Follow-up email addressed to the Sample Created By user.
     *              TargetObjectId keeps delivery tied to the User (address changes are honoured and
     *              internal-user sends do not consume the daily single-email limit). WhatId is not set
     *              because Salesforce rejects WhatId when TargetObjectId is a User, so Sample merge
     *              fields are resolved in Apex instead.
     */
    private static Messaging.SingleEmailMessage buildFollowUpEmail(
        Sample__c sampleRecord,
        EmailTemplateContent emailTemplate
    ) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setSaveAsActivity(false);
        mail.setTargetObjectId(sampleRecord.CreatedById);
        mail.setTreatTargetObjectAsRecipient(true);

        String recordUrl = getSampleRecordUrl(sampleRecord.Id);
        if (emailTemplate != null && String.isNotBlank(emailTemplate.htmlBody)) {
            mail.setSubject(mergeFollowUpTemplate(emailTemplate.subject, sampleRecord, recordUrl));
            mail.setHtmlBody(mergeFollowUpTemplate(emailTemplate.htmlBody, sampleRecord, recordUrl));
            mail.setPlainTextBody(mergeFollowUpTemplate(emailTemplate.plainBody, sampleRecord, recordUrl));
        } else {
            mail.setSubject(NOTIFICATION_TITLE + ': ' + sampleRecord.Name);
            mail.setHtmlBody(buildFallbackHtml(sampleRecord, recordUrl));
            mail.setPlainTextBody(buildFallbackPlainText(sampleRecord, recordUrl));
        }
        return mail;
    }

    private static String mergeFollowUpTemplate(
        String templateBody,
        Sample__c sampleRecord,
        String recordUrl
    ) {
        String mergedBody = templateBody;
        if (String.isNotBlank(mergedBody)) {
            mergedBody = mergedBody.replace(MERGE_SAMPLE_NAME, String.valueOf(sampleRecord.Name));
            mergedBody = mergedBody.replace(
                MERGE_FOLLOW_UP_DATE,
                String.valueOf(sampleRecord.FollowUpDate__c)
            );
            mergedBody = mergedBody.replace(MERGE_RECORD_URL, recordUrl);
        }
        return mergedBody;
    }

    private static String getSampleRecordUrl(Id sampleId) {
        return URL.getOrgDomainUrl().toExternalForm() +
            '/lightning/r/Sample__c/' + sampleId + '/view';
    }

    private static String buildFallbackHtml(Sample__c sampleRecord, String recordUrl) {
        return '<html><body style="font-family:Arial,Helvetica,sans-serif;color:#181818;">' +
            '<p>Hello,</p>' +
            '<p>This is a reminder to complete follow-up on customer sample <strong>' +
            String.valueOf(sampleRecord.Name) + '</strong>.</p>' +
            '<p>Follow-up Date: ' + String.valueOf(sampleRecord.FollowUpDate__c) + '</p>' +
            '<p><a href="' + recordUrl + '">Open Sample Record</a></p>' +
            '<p>Thank you.</p></body></html>';
    }

    private static String buildFallbackPlainText(Sample__c sampleRecord, String recordUrl) {
        return 'Hello,\n\n' +
            'This is a reminder to complete follow-up on customer sample ' +
            sampleRecord.Name + '.\n\n' +
            'Follow-up Date: ' + String.valueOf(sampleRecord.FollowUpDate__c) + '\n\n' +
            'Open the Sample record: ' + recordUrl + '\n\n' +
            'Thank you.';
    }

    private static Set<Id> collectSampleIds(List<Sample__c> samples) {
        Set<Id> sampleIds = new Set<Id>();
        for (Sample__c sampleRecord : samples) {
            sampleIds.add(sampleRecord.Id);
        }
        return sampleIds;
    }

    private static Integer resolveEmailChunkSize() {
        Integer chunkSize = DEFAULT_EMAIL_CHUNK_SIZE;
        BatchProcessConfig__mdt config = BatchProcessConfigSelector.selectActiveByBatchClassName(
            BatchProcessConfigSelector.SAMPLE_FOLLOW_UP_BATCH_CLASS_NAME
        );
        if (config != null && config.EmailChunkSize__c != null) {
            Integer configuredSize = config.EmailChunkSize__c.intValue();
            if (configuredSize > 0 && configuredSize <= DEFAULT_EMAIL_CHUNK_SIZE) {
                chunkSize = configuredSize;
            } else {
                Logger.warn(
                    CLASS_NAME + '.resolveEmailChunkSize: invalid EmailChunkSize__c=' +
                    configuredSize + '; using fallback=' + DEFAULT_EMAIL_CHUNK_SIZE
                );
            }
        }
        return chunkSize;
    }

    private static String formatSendEmailErrors(Messaging.SendEmailResult sendResult) {
        List<String> errorMessages = new List<String>();
        if (sendResult != null && sendResult.getErrors() != null) {
            for (Messaging.SendEmailError sendError : sendResult.getErrors()) {
                errorMessages.add(String.valueOf(sendError.getStatusCode()) + ': ' + sendError.getMessage());
            }
        }
        return String.join(errorMessages, '; ');
    }

    /**
     * @description Loaded SampleFollowUpReminder content for in-memory merge (one SOQL per transaction).
     */
    private class EmailTemplateContent {
        String subject;
        String htmlBody;
        String plainBody;
    }

    private static Id resolveCustomNotificationTypeId() {
        if (customNotificationTypeIdOverride != null) {
            return customNotificationTypeIdOverride;
        }
        if (isForceMissingNotificationType == true) {
            Logger.warn(
                CLASS_NAME + '.resolveCustomNotificationTypeId: type not found developerName=' +
                CUSTOM_NOTIFICATION_TYPE_DEVELOPER_NAME
            );
            return null;
        }

        CustomNotificationType notificationType =
            TeamMemberSelector.getCustomNotificationTypeByDeveloperName(
                CUSTOM_NOTIFICATION_TYPE_DEVELOPER_NAME
            );
        if (notificationType == null) {
            Logger.warn(
                CLASS_NAME + '.resolveCustomNotificationTypeId: type not found developerName=' +
                CUSTOM_NOTIFICATION_TYPE_DEVELOPER_NAME
            );
            return null;
        }
        return notificationType.Id;
    }

    private static EmailTemplateContent loadEmailTemplateContent() {
        EmailTemplateContent content;
        if (isForceMissingEmailTemplate == true) {
            Logger.warn(
                CLASS_NAME + '.loadEmailTemplateContent: template not found developerName=' +
                EMAIL_TEMPLATE_DEVELOPER_NAME
            );
        } else {
            List<EmailTemplate> templates;
            if (emailTemplateIdOverride != null) {
                templates = [
                    SELECT Id, Subject, HtmlValue, Body
                    FROM EmailTemplate
                    WHERE Id = :emailTemplateIdOverride
                    WITH SYSTEM_MODE
                    LIMIT 1
                ];
            } else {
                templates = [
                    SELECT Id, Subject, HtmlValue, Body
                    FROM EmailTemplate
                    WHERE DeveloperName = :EMAIL_TEMPLATE_DEVELOPER_NAME
                    WITH SYSTEM_MODE
                    LIMIT 1
                ];
            }
            if (templates.isEmpty()) {
                Logger.warn(
                    CLASS_NAME + '.loadEmailTemplateContent: template not found developerName=' +
                    EMAIL_TEMPLATE_DEVELOPER_NAME
                );
            } else {
                content = new EmailTemplateContent();
                content.subject = templates[0].Subject;
                content.htmlBody = templates[0].HtmlValue;
                content.plainBody = templates[0].Body;
            }
        }
        return content;
    }

}