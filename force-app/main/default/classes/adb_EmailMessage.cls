@IsTest
/**
 * Domain Builder for standard object EmailMessage
 * Follows adb_DomainBuilder conventions defined in a4d-apex-domainbuilder-rules.md
 *
 * Location: force-app/main/default/classes
 *
 * Provides:
 * - Constructor calling super(EmailMessage.SObjectType) with sensible defaults
 * - Fluent setters for common fields
 * - Relationship helpers for lookups/parents (ParentId, ActivityId, FromId, RelatedToId, ReplyToEmailMessageId, EmailTemplateId, EmailRoutingAddressId)
 *
 * Note:
 * - Extend with additional field setters as needed.
 */
public with sharing class adb_EmailMessage extends adb_DomainBuilder {

    /**
     * Create an EmailMessage builder with sensible defaults.
     * Defaults:
     * - Subject: 'Test Email ' + unique suffix
     * - TextBody: 'Hello from test builder'
     * - Incoming: false (outbound by default)
     * - Status: '3' (Sent) is typical in UI; leave unset unless tests require it
     * - MessageDate: Datetime.now()
     */
    public adb_EmailMessage() {
        super(EmailMessage.SObjectType);
        subject('Test Email ' + uniqueSuffix());
        textBody('Hello from test builder');
        incoming(false);
        messageDate(Datetime.now());
    }

    private static String uniqueSuffix() {
        return String.valueOf(Datetime.now().getTime()).right(6);
    }

    // -----------------------------
    // Core fields
    // -----------------------------

    public adb_EmailMessage subject(String value) {
        return (adb_EmailMessage) set(EmailMessage.Subject, value);
    }

    public adb_EmailMessage textBody(String value) {
        return (adb_EmailMessage) set(EmailMessage.TextBody, value);
    }

    public adb_EmailMessage htmlBody(String value) {
        return (adb_EmailMessage) set(EmailMessage.HtmlBody, value);
    }

    public adb_EmailMessage headers(String value) {
        return (adb_EmailMessage) set(EmailMessage.Headers, value);
    }

    public adb_EmailMessage fromName(String value) {
        return (adb_EmailMessage) set(EmailMessage.FromName, value);
    }

    public adb_EmailMessage fromAddress(String value) {
        return (adb_EmailMessage) set(EmailMessage.FromAddress, value);
    }

    public adb_EmailMessage validatedFromAddress(String value) {
        return (adb_EmailMessage) set(EmailMessage.ValidatedFromAddress, value);
    }

    public adb_EmailMessage toAddress(String value) {
        return (adb_EmailMessage) set(EmailMessage.ToAddress, value);
    }

    public adb_EmailMessage ccAddress(String value) {
        return (adb_EmailMessage) set(EmailMessage.CcAddress, value);
    }

    public adb_EmailMessage bccAddress(String value) {
        return (adb_EmailMessage) set(EmailMessage.BccAddress, value);
    }

    public adb_EmailMessage incoming(Boolean value) {
        return (adb_EmailMessage) set(EmailMessage.Incoming, value);
    }

    public adb_EmailMessage hasAttachment(Boolean value) {
        return (adb_EmailMessage) set(EmailMessage.HasAttachment, value);
    }

    public adb_EmailMessage status(String value) {
        return (adb_EmailMessage) set(EmailMessage.Status, value);
    }

    public adb_EmailMessage messageDate(Datetime value) {
        return (adb_EmailMessage) set(EmailMessage.MessageDate, value);
    }

    public adb_EmailMessage isExternallyVisible(Boolean value) {
        return (adb_EmailMessage) set(EmailMessage.IsExternallyVisible, value);
    }

    public adb_EmailMessage messageIdentifier(String value) {
        return (adb_EmailMessage) set(EmailMessage.MessageIdentifier, value);
    }

    public adb_EmailMessage threadIdentifier(String value) {
        return (adb_EmailMessage) set(EmailMessage.ThreadIdentifier, value);
    }

    public adb_EmailMessage clientThreadIdentifier(String value) {
        return (adb_EmailMessage) set(EmailMessage.ClientThreadIdentifier, value);
    }

    public adb_EmailMessage isClientManaged(Boolean value) {
        return (adb_EmailMessage) set(EmailMessage.IsClientManaged, value);
    }

    public adb_EmailMessage attachmentIds(String value) {
        return (adb_EmailMessage) set(EmailMessage.AttachmentIds, value);
    }

    public adb_EmailMessage isTracked(Boolean value) {
        return (adb_EmailMessage) set(EmailMessage.IsTracked, value);
    }

    public adb_EmailMessage isOpened(Boolean value) {
        return (adb_EmailMessage) set(EmailMessage.IsOpened, value);
    }

    public adb_EmailMessage firstOpenedDate(Datetime value) {
        return (adb_EmailMessage) set(EmailMessage.FirstOpenedDate, value);
    }

    public adb_EmailMessage lastOpenedDate(Datetime value) {
        return (adb_EmailMessage) set(EmailMessage.LastOpenedDate, value);
    }

    public adb_EmailMessage isBounced(Boolean value) {
        return (adb_EmailMessage) set(EmailMessage.IsBounced, value);
    }

    public adb_EmailMessage automationType(String value) {
        return (adb_EmailMessage) set(EmailMessage.AutomationType, value);
    }

    // -----------------------------
    // Ownership / audit
    // -----------------------------

    public adb_EmailMessage ownerUser(Id userId) {
        // CreatedById is audit, but allow explicit setting for tests via generic set if permitted
        return (adb_EmailMessage) set(EmailMessage.CreatedById, userId);
    }

    // -----------------------------
    // Relationship lookups (Id)
    // -----------------------------

    public adb_EmailMessage parent(Id caseId) {
        return (adb_EmailMessage) set(EmailMessage.ParentId, caseId);
    }

    public adb_EmailMessage activity(Id taskId) {
        return (adb_EmailMessage) set(EmailMessage.ActivityId, taskId);
    }

    // Use setFromId to avoid reserved keyword conflicts with 'from'
    public adb_EmailMessage setFromId(Id fromSObjectId) {
        return (adb_EmailMessage) set(EmailMessage.FromId, fromSObjectId);
    }

    public adb_EmailMessage relatedTo(Id relatedToId) {
        return (adb_EmailMessage) set(EmailMessage.RelatedToId, relatedToId);
    }

    public adb_EmailMessage replyToEmailMessage(Id emailMessageId) {
        return (adb_EmailMessage) set(EmailMessage.ReplyToEmailMessageId, emailMessageId);
    }

    public adb_EmailMessage emailTemplate(Id templateId) {
        return (adb_EmailMessage) set(EmailMessage.EmailTemplateId, templateId);
    }

    public adb_EmailMessage emailRoutingAddress(Id routingAddressId) {
        return (adb_EmailMessage) set(EmailMessage.EmailRoutingAddressId, routingAddressId);
    }

    // -----------------------------
    // Relationship helpers (builder overloads)
    // -----------------------------

    // public adb_EmailMessage parent(adb_Case c) {
    //     return (adb_EmailMessage) setParent(EmailMessage.ParentId, c);
    // }

    // public adb_EmailMessage activity(adb_Task t) {
    //     return (adb_EmailMessage) setParent(EmailMessage.ActivityId, t);
    // }

    // // Use fromRecord for polymorphic parent helper to avoid 'from' as identifier
    // public adb_EmailMessage fromRecord(adb_DomainBuilder sobjBuilder) {
    //     // EmailMessage.From is polymorphic; accept any adb_DomainBuilder and link via Id field
    //     return (adb_EmailMessage) setParent(EmailMessage.FromId, sobjBuilder);
    // }

    // public adb_EmailMessage relatedTo(adb_DomainBuilder sobjBuilder) {
    //     // EmailMessage.RelatedTo is polymorphic; accept any adb_DomainBuilder and link via Id field
    //     return (adb_EmailMessage) setParent(EmailMessage.RelatedToId, sobjBuilder);
    // }

    // public adb_EmailMessage replyToEmailMessage(adb_EmailMessage em) {
    //     return (adb_EmailMessage) setParent(EmailMessage.ReplyToEmailMessageId, em);
    // }

    // No builder class expected for EmailTemplate/EmailRoutingAddress; set via Id methods above.
}