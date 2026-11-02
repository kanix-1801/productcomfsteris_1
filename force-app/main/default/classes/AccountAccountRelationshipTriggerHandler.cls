/**
 * Trigger handler for AccountAccountRelationship__c IDN/GPO stamping.
 *
 * @author Abhishek Mishra
 * @date 08-11-2026
 * @description #GC-3213 Delegates AAR insert/update/delete to
 *              AccountAccountRelationshipService.processRelationships.
 *              Recursion uses TriggerControl with reset after work so later DML
 *              in the same transaction can stamp again.
 */
public with sharing class AccountAccountRelationshipTriggerHandler extends TriggerHandler {

    /**
     * @description After insert: stamp child Account IDN/GPO from new AAR rows.
     */
    @TestVisible
    protected override void afterInsert() {
        if (TriggerControl.enterAfterInsert(AccountAccountRelationship__c.SObjectType)) {
            try {
                AccountAccountRelationshipService.processRelationships(
                    (List<AccountAccountRelationship__c>) Trigger.new,
                    null
                );
            } finally {
                TriggerControl.resetAfterInsert(AccountAccountRelationship__c.SObjectType);
            }
        }
    }

    /**
     * @description After update: recalculate when RelationshipType / Parent / Child change.
     */
    @TestVisible
    protected override void afterUpdate() {
        if (TriggerControl.enterAfterUpdate(AccountAccountRelationship__c.SObjectType)) {
            try {
                AccountAccountRelationshipService.processRelationships(
                    (List<AccountAccountRelationship__c>) Trigger.new,
                    (Map<Id, AccountAccountRelationship__c>) Trigger.oldMap
                );
            } finally {
                TriggerControl.resetAfterUpdate(AccountAccountRelationship__c.SObjectType);
            }
        }
    }

    /**
     * @description After delete: recalculate/clear child Account IDN/GPO from remaining AARs.
     */
    @TestVisible
    protected override void afterDelete() {
        if (TriggerControl.enterAfterDelete(AccountAccountRelationship__c.SObjectType)) {
            try {
                AccountAccountRelationshipService.processRelationships(
                    (List<AccountAccountRelationship__c>) Trigger.old,
                    null
                );
            } finally {
                TriggerControl.resetAfterDelete(AccountAccountRelationship__c.SObjectType);
            }
        }
    }
}