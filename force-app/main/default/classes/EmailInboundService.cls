/**
 * @description GW-5102 - Generic inbound email orchestration. Resolves the related record from
 *              the email thread (In-Reply-To / References), then from Order # in the subject
 *              when mailto replies have no thread headers. Logs activity, attaches files,
 *              then applies Work Order quote-reply updates through RepairCenterQuoteEmailService.
 */
public with sharing class EmailInboundService {
    private static final Integer BODY_MAX_LENGTH = 32000;
    private static final String EMAIL_STATUS_READ = '1';
    private static final String HEADER_IN_REPLY_TO = 'In-Reply-To';
    private static final String HEADER_REFERENCES = 'References';
    private static final String QUOTE_MARKER_ORIGINAL_MESSAGE = '-----Original Message-----';
    private static final String QUOTE_MARKER_FROM_PREFIX = 'from:';

    /**
     * @description Context for one inbound email after thread and intent resolution.
     */
    public class Request {
        public Messaging.InboundEmail email;
        public Messaging.InboundEnvelope envelope;
        public String intent;
        public Id relatedRecordId;
        public Id sourceRecordId;
        public Id emailMessageId;
        public SObject sourceRecord;
    }

    /**
     * @description Handles one inbound email. Always returns success so customer replies are not bounced.
     * @param email Inbound email payload
     * @param envelope Inbound envelope
     * @return Inbound email result
     */
    public static Messaging.InboundEmailResult handleInboundEmail(
        Messaging.InboundEmail email,
        Messaging.InboundEnvelope envelope
    ) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
        result.success = true;
        Logger.setScenario('Inbound Email');

        try {
            Request request = buildRequest(email, envelope);
            if (request.relatedRecordId != null) {
                request.emailMessageId = logActivity(request);
                attachFiles(request);
            } else {
                Logger.warn(
                    'EmailInboundService: could not resolve Related To from thread headers or Order # in the subject. Candidates=' +
                    String.join(new List<String>(collectMessageIds(email)), ',')
                );
            }
            if (request.sourceRecord instanceof WorkOrder &&
                isRepairCenterWorkOrder((WorkOrder) request.sourceRecord)
            ) {
                RepairCenterQuoteEmailService.applyReply(
                    (WorkOrder) request.sourceRecord,
                    request.intent
                );
            }
        } catch (Exception e) {
            Logger.error('EmailInboundService.handleInboundEmail', e);
        } finally {
            Logger.saveLog();
        }
        return result;
    }

    @TestVisible
    private static Request buildRequest(
        Messaging.InboundEmail email,
        Messaging.InboundEnvelope envelope
    ) {
        Request request = new Request();
        request.email = email;
        request.envelope = envelope;
        request.intent = resolveIntent(email);

        request.sourceRecord = resolveSourceWorkOrder(email);
        if (request.sourceRecord != null) {
            request.sourceRecordId = (Id) request.sourceRecord.get('Id');
            request.relatedRecordId = resolveRelatedRecordId(request.sourceRecord);
        }
        return request;
    }

    private static SObject resolveSourceWorkOrder(Messaging.InboundEmail email) {
        EmailMessage originalMessage = resolveOriginalEmailMessage(email);
        if (originalMessage != null &&
            originalMessage.RelatedToId != null &&
            originalMessage.RelatedToId.getSObjectType() == WorkOrder.SObjectType
        ) {
            return WorkOrdersSelector.selectForQuoteEmailReply(
                String.valueOf(originalMessage.RelatedToId)
            );
        }

        String workOrderNumber = extractWorkOrderNumberFromSubject(
            email == null ? null : email.subject
        );
        if (String.isBlank(workOrderNumber)) {
            return null;
        }
        return WorkOrdersSelector.selectForQuoteEmailReply(workOrderNumber);
    }

    @TestVisible
    private static String extractWorkOrderNumberFromSubject(String subject) {
        if (String.isBlank(subject)) {
            return null;
        }

        EmailInboundRoute__mdt route = EmailInboundRoutesSelector.selectRepairCenterQuote();
        if (route == null || String.isBlank(route.RecordKeyRegex__c)) {
            return null;
        }
        if (String.isNotBlank(route.SubjectContains__c) &&
            !subject.toLowerCase().contains(route.SubjectContains__c.toLowerCase())
        ) {
            return null;
        }

        try {
            Matcher matcher = Pattern.compile(route.RecordKeyRegex__c).matcher(subject);
            if (!matcher.find() || matcher.groupCount() < 1) {
                return null;
            }
            String recordKey = matcher.group(1);
            return String.isBlank(recordKey) ? null : recordKey.trim();
        } catch (Exception ignored) {
            return null;
        }
    }

    private static EmailMessage resolveOriginalEmailMessage(Messaging.InboundEmail email) {
        Set<String> messageIds = collectMessageIds(email);
        if (messageIds.isEmpty()) {
            return null;
        }
        List<EmailMessage> matches = EmailMessagesSelector.selectByMessageIdentifiers(messageIds);
        return matches.isEmpty() ? null : matches[0];
    }

    @TestVisible
    private static Set<String> collectMessageIds(Messaging.InboundEmail email) {
        Set<String> messageIds = new Set<String>();
        if (email == null) {
            return messageIds;
        }
        addNormalizedMessageId(messageIds, email.inReplyTo);
        if (email.headers == null) {
            return messageIds;
        }
        for (Messaging.InboundEmail.Header header : email.headers) {
            if (header == null || String.isBlank(header.name) || String.isBlank(header.value)) {
                continue;
            }
            if (header.name.equalsIgnoreCase(HEADER_IN_REPLY_TO) ||
                header.name.equalsIgnoreCase(HEADER_REFERENCES)
            ) {
                for (String token : header.value.split('\\s+')) {
                    addNormalizedMessageId(messageIds, token);
                }
            }
        }
        return messageIds;
    }

    private static void addNormalizedMessageId(Set<String> messageIds, String rawValue) {
        String normalized = normalizeMessageId(rawValue);
        if (String.isBlank(normalized)) {
            return;
        }
        messageIds.add(normalized);
        messageIds.add('<' + normalized + '>');
    }

    private static Boolean isRepairCenterWorkOrder(WorkOrder workOrder) {
        String recordTypeName = workOrder == null || workOrder.RecordType == null
            ? null
            : workOrder.RecordType.DeveloperName;
        return recordTypeName == 'RepairCenterDevices' ||
            recordTypeName == 'RepairCenterInstruments' ||
            recordTypeName == 'RepairCenterOther';
    }

    @TestVisible
    private static String normalizeMessageId(String rawValue) {
        if (String.isBlank(rawValue)) {
            return null;
        }
        String trimmed = rawValue.trim();
        if (trimmed.startsWith('<') && trimmed.endsWith('>') && trimmed.length() > 2) {
            trimmed = trimmed.substring(1, trimmed.length() - 1).trim();
        }
        return String.isBlank(trimmed) ? null : trimmed;
    }

    @TestVisible
    private static String resolveIntent(Messaging.InboundEmail email) {
        String firstLine = stripEmphasis(extractFirstLine(email == null ? null : email.plainTextBody));
        InboundEmailReplyConfig__mdt config = InboundEmailReplyConfigsSelector.selectRepairCenterQuote();
        if (String.isBlank(firstLine) || config == null) {
            return RepairCenterQuoteEmailService.INTENT_HELP;
        }
        List<String> rejectKeywords = parseKeywords(
            firstNonBlank(config.RejectKeywordList__c, config.RejectKeywords__c)
        );
        if (matchesExactKeyword(firstLine, rejectKeywords)) {
            return RepairCenterQuoteEmailService.INTENT_REJECT;
        }
        List<String> approveKeywords = parseKeywords(
            firstNonBlank(config.ApproveKeywordList__c, config.ApproveKeywords__c)
        );
        if (matchesExactKeyword(firstLine, approveKeywords)) {
            return RepairCenterQuoteEmailService.INTENT_APPROVE;
        }
        return RepairCenterQuoteEmailService.INTENT_HELP;
    }

    @TestVisible
    private static String extractFirstLine(String plainTextBody) {
        if (String.isBlank(plainTextBody)) {
            return '';
        }
        String normalizedBody = plainTextBody.replace('\r\n', '\n').replace('\r', '\n');
        for (String rawLine : normalizedBody.split('\n')) {
            if (isQuoteMarker(rawLine)) {
                break;
            }
            String trimmed = rawLine == null ? '' : rawLine.trim();
            if (String.isNotBlank(trimmed)) {
                return trimmed;
            }
        }
        return '';
    }

    /**
     * @description Removes Gmail/markdown/HTML bold wrappers so *Reject* still matches Reject.
     *              Does not change the exact-token rule for the unwrapped line.
     * @param firstLine First non-quoted body line
     * @return Unwrapped, trimmed line
     */
    @TestVisible
    private static String stripEmphasis(String firstLine) {
        if (String.isBlank(firstLine)) {
            return firstLine;
        }
        String current = firstLine.trim();
        Boolean stripped = true;
        while (stripped && String.isNotBlank(current)) {
            stripped = false;
            Integer length = current.length();
            if (length >= 4 && current.startsWith('**') && current.endsWith('**')) {
                current = current.substring(2, length - 2).trim();
                stripped = true;
            } else if (length >= 2 && current.startsWith('*') && current.endsWith('*')) {
                current = current.substring(1, length - 1).trim();
                stripped = true;
            } else if (length >= 2 && current.startsWith('_') && current.endsWith('_')) {
                current = current.substring(1, length - 1).trim();
                stripped = true;
            } else {
                Matcher htmlMatcher = Pattern.compile('(?i)^<(b|strong|em|i)>(.*)</\\1>$')
                    .matcher(current);
                if (htmlMatcher.matches()) {
                    current = htmlMatcher.group(2).trim();
                    stripped = true;
                }
            }
        }
        return current;
    }

    private static Boolean isQuoteMarker(String line) {
        if (line == null) {
            return false;
        }
        String trimmed = line.trim();
        if (trimmed.startsWith('>')) {
            return true;
        }
        if (trimmed.startsWith(QUOTE_MARKER_ORIGINAL_MESSAGE)) {
            return true;
        }
        return trimmed.toLowerCase().startsWith(QUOTE_MARKER_FROM_PREFIX);
    }

    private static String firstNonBlank(String preferred, String fallback) {
        return String.isNotBlank(preferred) ? preferred : fallback;
    }

    private static List<String> parseKeywords(String commaSeparated) {
        List<String> keywords = new List<String>();
        if (String.isBlank(commaSeparated)) {
            return keywords;
        }
        for (String token : commaSeparated.split(',')) {
            String trimmed = token == null ? '' : token.trim();
            if (String.isNotBlank(trimmed)) {
                keywords.add(trimmed);
            }
        }
        return keywords;
    }

    private static Boolean matchesExactKeyword(String firstLine, List<String> keywords) {
        for (String keyword : keywords) {
            if (firstLine.equalsIgnoreCase(keyword)) {
                return true;
            }
        }
        return false;
    }

    private static Id resolveRelatedRecordId(SObject sourceRecord) {
        if (sourceRecord == null) {
            return null;
        }
        if (sourceRecord instanceof WorkOrder) {
            WorkOrder workOrder = (WorkOrder) sourceRecord;
            return workOrder.ParentWorkOrderId != null
                ? workOrder.ParentWorkOrderId
                : workOrder.Id;
        }
        return (Id) sourceRecord.get('Id');
    }

    private static Id logActivity(Request request) {
        EmailMessage emailMessage = new EmailMessage();
        emailMessage.Incoming = true;
        emailMessage.Status = EMAIL_STATUS_READ;
        emailMessage.MessageDate = Datetime.now();
        emailMessage.RelatedToId = request.relatedRecordId;
        emailMessage.Subject = truncate(
            request.email == null ? null : request.email.subject,
            3000
        );
        emailMessage.TextBody = truncate(
            request.email == null ? null : request.email.plainTextBody,
            BODY_MAX_LENGTH
        );
        emailMessage.HtmlBody = truncate(
            request.email == null ? null : request.email.htmlBody,
            BODY_MAX_LENGTH
        );
        emailMessage.FromAddress = resolveFromAddress(request);
        emailMessage.FromName = request.email == null ? null : request.email.fromName;
        emailMessage.ToAddress = truncate(collectToAddresses(request.email, request.envelope), 4000);
        List<EmailMessage> inserted =
            EmailMessagesService.createInboundEmailMessages(new List<EmailMessage>{ emailMessage });
        return inserted.isEmpty() ? null : inserted[0].Id;
    }

    private static void attachFiles(Request request) {
        if (request == null || request.relatedRecordId == null || request.email == null) {
            return;
        }

        List<ContentVersion> versions = new List<ContentVersion>();
        if (request.email.binaryAttachments != null) {
            for (Messaging.InboundEmail.BinaryAttachment attachment : request.email.binaryAttachments) {
                ContentVersion version = toContentVersion(
                    request.relatedRecordId,
                    attachment == null ? null : attachment.fileName,
                    attachment == null ? null : attachment.body
                );
                if (version != null) {
                    versions.add(version);
                }
            }
        }
        if (request.email.textAttachments != null) {
            for (Messaging.InboundEmail.TextAttachment attachment : request.email.textAttachments) {
                Blob body = attachment == null || attachment.body == null
                    ? null
                    : Blob.valueOf(attachment.body);
                ContentVersion version = toContentVersion(
                    request.relatedRecordId,
                    attachment == null ? null : attachment.fileName,
                    body
                );
                if (version != null) {
                    versions.add(version);
                }
            }
        }
        if (versions.isEmpty()) {
            return;
        }

        List<ContentVersion> created = ContentVersionsService.createContentVersions(versions);
        if (request.emailMessageId == null || created == null || created.isEmpty()) {
            return;
        }

        List<Id> documentIds = new List<Id>();
        for (ContentVersion createdVersion : created) {
            if (createdVersion.ContentDocumentId != null) {
                documentIds.add(createdVersion.ContentDocumentId);
            }
        }
        ContentDocumentLinksService.attachDocumentsToLinkedEntity(
            request.emailMessageId,
            documentIds
        );
    }

    private static ContentVersion toContentVersion(Id relatedRecordId, String fileName, Blob body) {
        if (relatedRecordId == null || body == null) {
            return null;
        }
        String resolvedName = String.isBlank(fileName) ? 'InboundAttachment' : fileName.trim();
        ContentVersion version = new ContentVersion();
        version.Title = resolvedName.contains('.')
            ? resolvedName.substringBeforeLast('.')
            : resolvedName;
        version.PathOnClient = resolvedName.contains('.') ? resolvedName : resolvedName + '.txt';
        version.VersionData = body;
        version.FirstPublishLocationId = relatedRecordId;
        return version;
    }

    private static String collectToAddresses(
        Messaging.InboundEmail email,
        Messaging.InboundEnvelope envelope
    ) {
        List<String> addresses = new List<String>();
        if (envelope != null && String.isNotBlank(envelope.toAddress)) {
            addresses.add(envelope.toAddress);
        }
        if (email != null && email.toAddresses != null) {
            addresses.addAll(email.toAddresses);
        }
        if (email != null && email.ccAddresses != null) {
            addresses.addAll(email.ccAddresses);
        }
        return String.join(addresses, ';');
    }

    private static String resolveFromAddress(Request request) {
        if (request.email != null && String.isNotBlank(request.email.fromAddress)) {
            return request.email.fromAddress;
        }
        if (request.envelope != null) {
            return request.envelope.fromAddress;
        }
        return null;
    }

    private static String truncate(String value, Integer maxLength) {
        if (String.isBlank(value) || maxLength == null || value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }
}