/**
 * @description Single entry-point trigger for the ContentDocumentLink SObject.
 *              Delegates all logic to ContentDocumentLinkTriggerHandler via the TriggerHandler framework.
 *
 *              VALID TRIGGER CONTEXTS for ContentDocumentLink:
 *                - before insert  : Set field defaults or validate the link before it is created.
 *                - after insert   : React to a new link (e.g., propagate visibility settings
 *                                   or notify linked record owners after the link is committed).
 *                - before delete  : Validate or prevent a link from being removed.
 *                - after delete   : Perform cleanup after a ContentDocumentLink is deleted.
 *
 *              INVALID TRIGGER CONTEXTS for ContentDocumentLink:
 *                - before update  : ContentDocumentLink records are immutable after creation.
 *                                   The platform does not support updating a ContentDocumentLink;
 *                                   you must delete and re-create it. No before update context fires.
 *                - after update   : Same restriction as before update — no after update context exists.
 *                - after undelete : ContentDocumentLink records cannot be undeleted. Deleting a link
 *                                   is permanent; the platform provides no after undelete context.
 */
trigger ContentDocumentLinkTrigger on ContentDocumentLink (
    before insert,
    after insert,
    before delete,
    after delete
) {
    new ContentDocumentLinkTriggerHandler().run();
}