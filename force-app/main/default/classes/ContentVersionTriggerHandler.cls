/**
 * @description Trigger handler for the ContentVersion SObject.
 *              Orchestrates Domain and Service layer calls.
 *              Uses KevinOHara80 TriggerHandler framework.
 *              No SOQL or DML is allowed in this class.
 *
 *              IMPORTANT — ContentVersion trigger context notes:
 *
 *              SUPPORTED contexts (wired up in ContentVersionTrigger):
 *                - beforeInsert  : Fire before a ContentVersion is committed. This is the primary
 *                                  extension point for new document creation — inserting a
 *                                  ContentVersion is what causes the platform to implicitly create
 *                                  the parent ContentDocument. Apply defaults and validate here.
 *                - afterInsert   : Fire after the insert is committed. ContentDocumentId is
 *                                  populated on Trigger.new at this point. This is the correct
 *                                  context to create ContentDocumentLink records or fire
 *                                  notifications tied to the new document.
 *                - beforeUpdate  : Fire before a new version is committed to an existing document.
 *                                  Use for validation or field defaults on version updates.
 *                - afterUpdate   : Fire after version updates are committed. Use to delegate
 *                                  cross-object logic to the Service layer.
 *
 *              NOT SUPPORTED — do not override these methods for ContentVersion:
 *                - beforeDelete / afterDelete : Published ContentVersion records (IsLatest = true,
 *                  or the only version on a document) cannot be deleted directly. Delete the parent
 *                  ContentDocument instead. The platform does not reliably fire delete trigger
 *                  contexts for ContentVersion — avoid relying on them for business logic.
 *                - afterUndelete : ContentVersion records cannot be undeleted independently.
 *                  Undeleting the parent ContentDocument restores all its versions. No afterUndelete
 *                  context fires for ContentVersion; use ContentDocument's afterUndelete instead.
 */
public with sharing class ContentVersionTriggerHandler extends TriggerHandler {

    // ── Before Insert ─────────────────────────────────────────────────────────
    // NOTE: This context fires when a new ContentVersion is inserted, which also
    // causes the platform to create the parent ContentDocument implicitly.
    // ContentDocumentId is NOT yet available here (document hasn't been created yet).
    public override void beforeInsert() {
        if (!AutomationControl.isTriggerEnabled('ContentVersionTrigger')) { return; }
        ContentVersions domain = new ContentVersions((List<ContentVersion>) Trigger.new);
        // domain.applyDefaults();
        // domain.validate();
    }

    // ── After Insert ──────────────────────────────────────────────────────────
    // NOTE: ContentDocumentId IS populated on Trigger.new records at this point.
    // This is the correct context for creating ContentDocumentLink records or
    // triggering notifications that require the ContentDocumentId to be known.
    public override void afterInsert() {
        if (!AutomationControl.isTriggerEnabled('ContentVersionTrigger')) { return; }
        // Set<Id> contentVersionIds = new Map<Id, ContentVersion>((List<ContentVersion>) Trigger.new).keySet();
        // ContentVersionsService.handleNewContentVersions(contentVersionIds);
    }

    // ── Before Update ─────────────────────────────────────────────────────────
    public override void beforeUpdate() {
        if (!AutomationControl.isTriggerEnabled('ContentVersionTrigger')) { return; }
        ContentVersions domain = new ContentVersions((List<ContentVersion>) Trigger.new);
        // domain.validate();
    }

    // ── After Update ──────────────────────────────────────────────────────────
    public override void afterUpdate() {
        if (!AutomationControl.isTriggerEnabled('ContentVersionTrigger')) { return; }
        // Set<Id> contentVersionIds = new Map<Id, ContentVersion>((List<ContentVersion>) Trigger.new).keySet();
        // ContentVersionsService.handleUpdatedContentVersions(contentVersionIds);
    }

    // ── NOT SUPPORTED — Delete and Undelete contexts are intentionally absent ─
    // beforeDelete(), afterDelete(), and afterUndelete() are NOT overridden here.
    // See class header for platform restrictions on these contexts for ContentVersion.
}