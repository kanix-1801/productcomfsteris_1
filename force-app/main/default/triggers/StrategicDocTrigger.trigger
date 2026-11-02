/**
 * @description GC-3366
 *              Trigger for Strategic Contract supporting documents.
 */
trigger StrategicDocTrigger on ContentDocumentLink (
    after insert,
    after delete
) {
    new StrategicDocHandler().run();
}