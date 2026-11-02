/**
 * @author Akash Dahinde
 * @date 06-03-2026
 * @description Kevin Ohara trigger handler for Address insert/update events.
 *
 *              Realtime team access is disabled (GC-3112). Use OrderLineContactTeamAccessBatch.
 */
public with sharing class AddressTriggerHandller extends TriggerHandler {

    private static final String CLASS_NAME = 'AddressTriggerHandller';

    public override void afterInsert() {
        if (!TriggerControl.enterAfterInsert(Schema.Address.SObjectType)) {
            return;
        }
    }

    public override void afterUpdate() {
        if (!TriggerControl.enterAfterUpdate(Schema.Address.SObjectType)) {
            return;
        }
    }
}