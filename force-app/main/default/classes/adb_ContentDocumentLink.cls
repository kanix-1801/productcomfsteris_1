/**
 * @description Domain Builder for the ContentDocumentLink SObject.
 *              Provides a fluent API for creating test ContentDocumentLink records.
 *
 *              ContentDocumentLink records link a ContentDocument to a Salesforce record.
 *              ContentDocumentId and LinkedEntityId must be set before insert.
 *              ContentDocumentLink records are immutable after insert — delete and re-insert
 *              to change ShareType or Visibility.
 *
 *              NOTE: ContentDocumentId must reference a ContentDocument created by a prior
 *              ContentVersion insert. Re-query ContentVersion.ContentDocumentId after persist()
 *              and pass it to contentDocumentId() before inserting the link.
 */
@IsTest
public class adb_ContentDocumentLink extends adb_DomainBuilder {

    /**
     * @description Constructs a ContentDocumentLink builder with default ShareType and Visibility.
     */
    public adb_ContentDocumentLink() {
        super(ContentDocumentLink.SObjectType);
        set(ContentDocumentLink.ShareType, 'V');
        set(ContentDocumentLink.Visibility, 'AllUsers');
    }

    /**
     * @description Sets the ContentDocumentId (the document to link).
     * @param value The Id of the ContentDocument.
     * @return This builder instance.
     */
    public adb_ContentDocumentLink contentDocumentId(Id value) {
        return (adb_ContentDocumentLink) set(ContentDocumentLink.ContentDocumentId, value);
    }

    /**
     * @description Sets the LinkedEntityId (the record to link the document to).
     * @param value The Id of the target SObject record.
     * @return This builder instance.
     */
    public adb_ContentDocumentLink linkedEntityId(Id value) {
        return (adb_ContentDocumentLink) set(ContentDocumentLink.LinkedEntityId, value);
    }

    /**
     * @description Sets the ShareType (V = Viewer, C = Collaborator, I = Inferred).
     * @param value The share type value.
     * @return This builder instance.
     */
    public adb_ContentDocumentLink shareType(String value) {
        return (adb_ContentDocumentLink) set(ContentDocumentLink.ShareType, value);
    }

    /**
     * @description Sets the Visibility (AllUsers, InternalUsers, SharedUsers).
     * @param value The visibility value.
     * @return This builder instance.
     */
    public adb_ContentDocumentLink visibility(String value) {
        return (adb_ContentDocumentLink) set(ContentDocumentLink.Visibility, value);
    }
}