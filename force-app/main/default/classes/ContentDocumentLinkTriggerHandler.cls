/**
 * @description Trigger handler for the ContentDocumentLink SObject.
 *              Orchestrates Domain and Service layer calls.
 *              Uses KevinOHara80 TriggerHandler framework.
 *              No SOQL or DML is allowed in this class.
 *
 *              IMPORTANT — ContentDocumentLink trigger context restrictions:
 *
 *              SUPPORTED contexts (wired up in ContentDocumentLinkTrigger):
 *                - beforeInsert  : Fire before a new link is committed. Use to validate the
 *                                  LinkedEntityId and ShareType combination or apply defaults.
 *                - afterInsert   : Fire after the link is committed. Use to trigger Service-layer
 *                                  logic that depends on both ContentDocumentId and LinkedEntityId
 *                                  being persisted (e.g., notify record owners, set permissions).
 *                - beforeDelete  : Fire before a link is removed. Use to prevent deletion when
 *                                  business rules require a document to remain linked.
 *                - afterDelete   : Fire after a link is removed. Use for cleanup logic.
 *
 *              NOT SUPPORTED — do not override these methods for ContentDocumentLink:
 *                - beforeUpdate / afterUpdate : ContentDocumentLink records are immutable.
 *                  The platform does not support updating a ContentDocumentLink after creation.
 *                  To change ShareType or Visibility, you must delete the existing link and
 *                  insert a new one. No update trigger contexts fire for this object.
 *                - afterUndelete : ContentDocumentLink records cannot be undeleted. Once deleted,
 *                  the link is permanently gone and must be re-created. No afterUndelete context
 *                  fires for this object.
 */
public with sharing class ContentDocumentLinkTriggerHandler extends TriggerHandler {

    // ── Before Insert ─────────────────────────────────────────────────────────
    public override void beforeInsert() {
        if (!AutomationControl.isTriggerEnabled('ContentDocumentLinkTrigger')) {
            return;
        }
    }

    // ── After Insert ──────────────────────────────────────────────────────────
   public override void afterInsert() {
        if (!AutomationControl.isTriggerEnabled('ContentDocumentLinkTrigger')) {
            return;
        }
        MobileDevicePictureLinkHandler.completeMobileAppPictureLinks(
            (List<ContentDocumentLink>) Trigger.new
        );
        // GW-3114 - Generate document: email the Repair Center Quote / Work Order PDF to the customer once it is linked.
        RepairCenterDocumentEmailService.handleNewContentDocumentLinks((List<ContentDocumentLink>) Trigger.new);
    }

    // ── Before Delete ─────────────────────────────────────────────────────────
    public override void beforeDelete() {
        if (!AutomationControl.isTriggerEnabled('ContentDocumentLinkTrigger')) { return; }
        // Trigger.old contains the records being deleted; Trigger.new is null in delete contexts.
        ContentDocumentLinks domain = new ContentDocumentLinks((List<ContentDocumentLink>) Trigger.old);
        // domain.validate();
    }

    // ── After Delete ──────────────────────────────────────────────────────────
    public override void afterDelete() {
        if (!AutomationControl.isTriggerEnabled('ContentDocumentLinkTrigger')) { return; }
        // Set<Id> linkedEntityIds = new Set<Id>();
        // for (ContentDocumentLink cdl : (List<ContentDocumentLink>) Trigger.old) {
        //     linkedEntityIds.add(cdl.LinkedEntityId);
        // }
        // ContentDocumentLinksService.handleDeletedContentDocumentLinks(linkedEntityIds);
        
    }
    
  
       

    // ── NOT SUPPORTED — Update and Undelete contexts are intentionally absent ─
    // beforeUpdate(), afterUpdate(), and afterUndelete() are NOT overridden here.
    // ContentDocumentLink records are immutable and cannot be undeleted — see class header.
}