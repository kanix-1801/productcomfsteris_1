/**
 * @description Single entry-point trigger for the ContentVersion SObject.
 *              Delegates all logic to ContentVersionTriggerHandler via the TriggerHandler framework.
 *
 *              VALID TRIGGER CONTEXTS for ContentVersion:
 *                - before insert  : Apply defaults and validate file metadata before a new version
 *                                   is committed. This is the primary extension point for ContentDocument
 *                                   creation because inserting a ContentVersion is what causes the
 *                                   platform to implicitly create the parent ContentDocument.
 *                - after insert   : React after the insert is committed. ContentDocumentId is
 *                                   populated on Trigger.new at this point, making after insert the
 *                                   correct context to create ContentDocumentLink records or fire
 *                                   notifications tied to the new document.
 *                - before update  : Validate changes before a new version is committed to an
 *                                   existing document.
 *                - after update   : React to version updates after they are committed.
 *
 *              INVALID TRIGGER CONTEXTS for ContentVersion:
 *                - before delete  : ContentVersion records that have been published (IsLatest = true,
 *                                   or are the only version) cannot be deleted directly; delete the
 *                                   parent ContentDocument instead. Draft versions (unpublished) can
 *                                   technically be deleted, but the platform does not reliably fire
 *                                   before delete for ContentVersion — avoid relying on this context.
 *                - after delete   : Same restriction as before delete. Use ContentDocument's
 *                                   after delete trigger instead.
 *                - after undelete : ContentVersion records cannot be undeleted independently.
 *                                   Undeleting the parent ContentDocument restores all its versions.
 */
trigger ContentVersionTrigger on ContentVersion (
    before insert,
    after insert,
    before update,
    after update
) {
    new ContentVersionTriggerHandler().run();
}