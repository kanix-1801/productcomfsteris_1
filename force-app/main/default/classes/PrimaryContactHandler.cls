/**
 * @author Akash Dahinde
 * @date 09-25-2026
 * @story GCL-11
 * @description Kevin O'Hara trigger handler for OpportunityContactRole.
 *              Delegates insert and update validation to PrimaryContactService.
 *
 *              TriggerControl is intentionally not used. Its once-per-transaction
 *              flags could allow a later OCR save in the same transaction to skip
 *              validation. PrimaryContactService instead suspends its guard only
 *              around DML owned by the service.
 */
public with sharing class PrimaryContactHandler extends TriggerHandler {

    /**
     * @description Handles OCR before insert and rejects a second Primary role for
     *              an in-scope Opportunity.
     */
    public override void beforeInsert() {
        LSPrimaryContactService.guardPrimaryOnInsert(
            (List<OpportunityContactRole>) Trigger.new
        );
    }

    /**
     * @description Handles OCR before update. Rejects promotion of a second Primary
     *              role and direct demotion of the role selected by the Opportunity.
     */
    public override void beforeUpdate() {
        LSPrimaryContactService.guardPrimaryOnUpdate(
            (List<OpportunityContactRole>) Trigger.new,
            (Map<Id, OpportunityContactRole>) Trigger.oldMap
        );
    }
}