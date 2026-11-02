/**
 * @description Trigger handler for the ContentDocument SObject.
 *              Orchestrates Domain and Service layer calls.
 *              Uses KevinOHara80 TriggerHandler framework.
 *              No SOQL or DML is allowed in this class.
 *
 *              IMPORTANT — ContentDocument trigger context restrictions:
 *
 *              SUPPORTED contexts (wired up in ContentDocumentTrigger):
 *                - beforeUpdate   : Fire before an update is committed. Domain defaults and
 *                                   validations run here.
 *                - beforeDelete   : Fire before a ContentDocument is deleted. Use to validate
 *                                   or prevent deletion.
 *                - afterUpdate    : Fire after an update is committed. Use to delegate cross-object
 *                                   logic to the Service layer.
 *                - afterDelete    : Fire after a ContentDocument is deleted. Use for cleanup.
 *                - afterUndelete  : Fire after a ContentDocument is restored from the Recycle Bin.
 *
 *              NOT SUPPORTED — do not override these methods for ContentDocument:
 *                - beforeInsert / afterInsert : ContentDocument records are created implicitly by
 *                  the platform when a ContentVersion is inserted. No insert trigger contexts fire
 *                  on ContentDocument itself. To react to new document creation, use the
 *                  ContentVersionTriggerHandler.afterInsert() context instead, where
 *                  Trigger.new[n].ContentDocumentId is already populated.
 */
public with sharing class ContentDocumentTriggerHandler extends TriggerHandler {

    // ── Before Update ─────────────────────────────────────────────────────────
    public override void beforeUpdate() {
        if (!AutomationControl.isTriggerEnabled('ContentDocumentTrigger')) { return; }
        ContentDocuments domain = new ContentDocuments((List<ContentDocument>) Trigger.new);
        // domain.applyDefaults();
        // domain.validate();
    }

    // ── Before Delete ─────────────────────────────────────────────────────────
    public override void beforeDelete() {
        if (!AutomationControl.isTriggerEnabled('ContentDocumentTrigger')) { return; }
        // Trigger.old contains the records being deleted; Trigger.new is null in delete contexts.
        ContentDocuments domain = new ContentDocuments((List<ContentDocument>) Trigger.old);
        // domain.validate();
    }

    // ── After Update ──────────────────────────────────────────────────────────
    public override void afterUpdate() {
        if (!AutomationControl.isTriggerEnabled('ContentDocumentTrigger')) { return; }
        // Set<Id> contentDocumentIds = new Map<Id, ContentDocument>((List<ContentDocument>) Trigger.new).keySet();
        // ContentDocumentsService.handleUpdatedContentDocuments(contentDocumentIds);
    }

    // ── After Delete ──────────────────────────────────────────────────────────
    public override void afterDelete() {
        if (!AutomationControl.isTriggerEnabled('ContentDocumentTrigger')) { return; }
        // Set<Id> contentDocumentIds = new Map<Id, ContentDocument>((List<ContentDocument>) Trigger.old).keySet();
        // ContentDocumentsService.handleDeletedContentDocuments(contentDocumentIds);
    }

    // ── After Undelete ────────────────────────────────────────────────────────
    public override void afterUndelete() {
        if (!AutomationControl.isTriggerEnabled('ContentDocumentTrigger')) { return; }
        // Set<Id> contentDocumentIds = new Map<Id, ContentDocument>((List<ContentDocument>) Trigger.new).keySet();
        // ContentDocumentsService.handleUndeletedContentDocuments(contentDocumentIds);
    }

    // ── NOT SUPPORTED — Insert contexts are intentionally absent ──────────────
    // beforeInsert() and afterInsert() are NOT overridden here.
    // ContentDocument has no insert trigger context — see class header for details.
}