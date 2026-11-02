/**
 * @description GC-3366
 *              Handler for Strategic Contract supporting documents.
 */
public with sharing class StrategicDocHandler extends TriggerHandler {

    public override void afterInsert() {
        StrategicDocService.handleAfterInsert(
            (List<ContentDocumentLink>) Trigger.new
        );
    }

    public override void afterDelete() {
        StrategicDocService.handleAfterDelete(
            (List<ContentDocumentLink>) Trigger.old
        );
    }
}