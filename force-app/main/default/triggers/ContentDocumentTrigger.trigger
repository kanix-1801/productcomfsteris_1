/**
 * @description Single entry-point trigger for the ContentDocument SObject.
 *              Delegates all logic to ContentDocumentTriggerHandler via the TriggerHandler framework.
 *
 *              VALID TRIGGER CONTEXTS for ContentDocument:
 *                - before update  : Modify field values before an update is committed.
 *                - before delete  : Validate or prevent deletion before it occurs.
 *                - after update   : React to changes after they are committed.
 *                - after delete   : Perform cleanup logic after a ContentDocument is deleted.
 *                - after undelete : Restore related data when a ContentDocument is recovered from the Recycle Bin.
 *
 *              INVALID TRIGGER CONTEXTS for ContentDocument:
 *                - before insert  : ContentDocument records cannot be inserted directly via DML.
 *                                   They are created implicitly by the platform when inserting a
 *                                   ContentVersion. There is no before insert trigger context.
 *                - after insert   : Same restriction as before insert — no after insert context exists
 *                                   for ContentDocument. Use ContentVersion's after insert trigger
 *                                   (where ContentDocumentId is available) to react to new documents.
 */
trigger ContentDocumentTrigger on ContentDocument (
    before update,
    before delete,
    after update,
    after delete,
    after undelete
) {
    new ContentDocumentTriggerHandler().run();
}