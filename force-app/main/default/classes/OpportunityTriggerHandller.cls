/**
 * @author Akash Dahinde
 * @date 06-03-2026
 * @description Kevin Ohara trigger handler for Opportunity insert/update events.
 *
 *              beforeInsert/beforeUpdate: populate Duplicate_Match_Key__c for duplicate detection (GC-2643).
 *              GC-3431: block an EPP from leaving Draft when an elevated consumable has no EPP Price.
 */
public with sharing class OpportunityTriggerHandller extends TriggerHandler {
        private static final String CLASS_NAME = 'OpportunityTriggerHandller';
    /**
     * @description Handles Opportunity before-insert trigger context.
     *              Delegates to OpportunityService.populateDuplicateMatchKey
     *              to generate Duplicate_Match_Key__c prior to record creation.
     *              GC-2643 - Duplicate key uses Address, Primary Contact, Type, and Territory.
     *              The duplicate key is used for realtime duplicate Opportunity detection.
     */
    public override void beforeInsert() {
        if (!TriggerControl.enterBeforeInsert(Opportunity.SObjectType)) {
            return;
        }
	    
        OpportunityService.populateDuplicateMatchKey(
            (List<Opportunity>) Trigger.new, null
        );
        // GC-3213 - START
        AccountAccountRelationshipService.stampOpportunitiesFromAccount(
            (List<Opportunity>) Trigger.new,
            null
        );
        // GC-3213 - END
        // GC-3519 - START
        ProjectOpportunityReviewService.applyBeforeSave(
            (List<Opportunity>) Trigger.new,
            null
        );
        // GC-3519 - END
        // GC-3521 - START
        ProjectOpportunityForecastService.applyBeforeSave(
            (List<Opportunity>) Trigger.new,
            null
        );
        ProjectOpportunityCommercialGateService.applyBeforeSave(
            (List<Opportunity>) Trigger.new,
            null
        );
        // GC-3521 - END
        
		// Start GCL -14 Akash Dahinde
        List<Opportunity> opportunities = (List<Opportunity>) Trigger.new;

        LSOpportunityNamingService.applyNames(opportunities);
        // End GCL -14 Akash Dahinde
        // GCL-23
		LSOpportunityCloneService.stampClonedFrom(opportunities);
    }

    /**
     * @description Handles Opportunity before-update trigger context.
     *              Delegates to OpportunityService.populateDuplicateMatchKey
     *              to regenerate Duplicate_Match_Key__c when fields contributing
     *              to duplicate detection are modified.
     *              GC-2643 - Regenerates key when AccountId, PrimaryContact__c, or Type changes.
     *              GC-3431 - blocks an EPP leaving Draft when an elevated consumable has no EPP Price.
     */
    public override void beforeUpdate() {
        if (!TriggerControl.enterBeforeUpdate(Opportunity.SObjectType)) {
            return;
        }
        OpportunityService.populateDuplicateMatchKey(
            (List<Opportunity>) Trigger.new,
            (Map<Id, Opportunity>) Trigger.oldMap
        );
        // GC-3213 - START
        AccountAccountRelationshipService.stampOpportunitiesFromAccount(
            (List<Opportunity>) Trigger.new,
            (Map<Id, Opportunity>) Trigger.oldMap
        );
        // GC-3213 - END
        // For GC 3188
        OpportunityService.validateForecastEligibleQuoteClosure(
        (List<Opportunity>) Trigger.new,
        (Map<Id, Opportunity>) Trigger.oldMap
        );
        //end of GC 3188
        OpportunityService.stageForecastConfidencePropagateBanner(
            (List<Opportunity>) Trigger.new,
            (Map<Id, Opportunity>) Trigger.oldMap
        );
        OpportunityService.stageClosedLostQuoteClosureBanner(
            (List<Opportunity>) Trigger.new,
            (Map<Id, Opportunity>) Trigger.oldMap
        );
        // GC-3431 - START
        EPPStageValidationService.validateBeforeUpdate(
            (List<Opportunity>) Trigger.new,
            (Map<Id, Opportunity>) Trigger.oldMap
        );
        // GC-3431 - END
        // GC-3519 - START
        ProjectOpportunityReviewService.applyBeforeSave(
            (List<Opportunity>) Trigger.new,
            (Map<Id, Opportunity>) Trigger.oldMap
        );
        // GC-3519 - END
        // GC-3521 - START
        ProjectOpportunityForecastService.applyBeforeSave(
            (List<Opportunity>) Trigger.new,
            (Map<Id, Opportunity>) Trigger.oldMap
        );
        ProjectOpportunityCommercialGateService.applyBeforeSave(
            (List<Opportunity>) Trigger.new,
            (Map<Id, Opportunity>) Trigger.oldMap
        );
        // GC-3521 - END
  		// Start GCL -14 Akash Dahinde
        List<Opportunity> opportunities = (List<Opportunity>) Trigger.new;
        Map<Id, Opportunity> oldMap =
            (Map<Id, Opportunity>) Trigger.oldMap;

        LSOpportunityNamingService.applyNames(opportunities);
        // End GCL -14 Akash Dahinde 
    }

    /**
     * @description Handles Opportunity after-insert trigger context.
     */
    public override void afterInsert() {
         if (!TriggerControl.enterAfterInsert(Opportunity.SObjectType)) {
            return;
        }
         // Start GCL -11 Akash Dahinde
        LSPrimaryContactService.syncRolesOnInsert((List<Opportunity>) Trigger.new);
          // END GCL -11 Akash Dahinde
        // GC-3521 - START
        ProjectOpportunityValueRollupService.applyAfterSave((List<Opportunity>) Trigger.new, null);
        // GC-3521 - END
    }

    /**
     * @description Handles Opportunity after-update trigger context.
     */
    public override void afterUpdate() {
         if (!TriggerControl.enterAfterUpdate(Opportunity.SObjectType)) {
            return;
        }
        //GC 2641 vinay
            OpportunityService.addSalesOpsContractTeamMembers(
                (List<Opportunity>) Trigger.new,
                (Map<Id, Opportunity>) Trigger.oldMap
            );
        
	    // Start GCL -11 Akash Dahinde
        LSPrimaryContactService.syncRolesOnUpdate(
        (List<Opportunity>) Trigger.new,
        (Map<Id, Opportunity>) Trigger.oldMap
       );
        // End GCL -11 Akash Dahinde
        // GC-3521 - START
        ProjectOpportunityValueRollupService.applyAfterSave(
            (List<Opportunity>) Trigger.new,
            (Map<Id, Opportunity>) Trigger.oldMap
        );
        // GC-3521 - END
    }	


}