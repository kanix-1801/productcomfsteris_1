/**
 * @description GC-3431 validation applied when an EPP Opportunity leaves Draft.
 *
 *              Responsibilities:
 *              1. Detect Equipment Placement Program Opportunities moving out of Draft.
 *              2. Block the stage change when an elevated consumable is missing its EPP Price.
 * @author      Vinay
 * @date        2026-09-29
 */
public with sharing class EPPStageValidationService {
    private static final String CLASS_NAME = 'EPPStageValidationService';
    private static final String SCENARIO = 'Equipment Placement Program';
    private static final String EPP_RECORD_TYPE = 'HCSalesEquipmentPlacementProgram';
    private static final String DRAFT_STAGE = 'Draft';

    /**
     * @description Adds an error to each EPP Opportunity that is leaving Draft with an elevated consumable and a blank EPP Price.
     * @param newOpportunities Opportunity records from the before-update trigger.
     * @param oldOpportunitiesById Previous Opportunity values, used to detect the stage change.
     * @return None.
     */
    public static void validateBeforeUpdate(
        List<Opportunity> newOpportunities,
        Map<Id, Opportunity> oldOpportunitiesById
    ) {
        Logger.setScenario(SCENARIO);
        try {
            Logger.info(CLASS_NAME + '.validateBeforeUpdate: started').addTag('Opportunity');
            if (
                newOpportunities == null
                || newOpportunities.isEmpty()
                || oldOpportunitiesById == null
            ) {
                Logger.warn(CLASS_NAME + '.validateBeforeUpdate: Opportunity context is missing')
                    .addTag('Opportunity');
                return;
            }

            Id eppRecordTypeId = Schema.SObjectType.Opportunity
                .getRecordTypeInfosByDeveloperName()
                .get(EPP_RECORD_TYPE)
                .getRecordTypeId();

            Map<Id, Opportunity> opportunitiesLeavingDraft = new Map<Id, Opportunity>();
            for (Opportunity opportunityRecord : newOpportunities) {
                Opportunity oldOpportunity = oldOpportunitiesById.get(opportunityRecord.Id);
                if (
                    opportunityRecord.RecordTypeId == eppRecordTypeId
                    && oldOpportunity.StageName == DRAFT_STAGE
                    && opportunityRecord.StageName != DRAFT_STAGE
                ) {
                    opportunitiesLeavingDraft.put(opportunityRecord.Id, opportunityRecord);
                }
            }

            if (opportunitiesLeavingDraft.isEmpty()) {
                Logger.debug(
                    CLASS_NAME + '.validateBeforeUpdate: no EPP Opportunity is leaving Draft'
                ).addTag('Opportunity');
                return;
            }

            Set<Id> opportunitiesWithMissingEppPrice = new Set<Id>();
            for (OpportunityLineItem line : [
                SELECT OpportunityId
                FROM OpportunityLineItem
                WHERE OpportunityId IN :opportunitiesLeavingDraft.keySet()
                  AND Product2.IsConsumable__c = true
                  AND ElevatedEPPPricingApplicable__c = true
                  AND EPPPrice__c = null
                WITH SYSTEM_MODE
            ]) {
                opportunitiesWithMissingEppPrice.add(line.OpportunityId);
            }

            if (!opportunitiesWithMissingEppPrice.isEmpty()) {
                Logger.warn(
                    CLASS_NAME + '.validateBeforeUpdate: blockedCount='
                    + opportunitiesWithMissingEppPrice.size()
                ).addTag('Opportunity').addTag('Opportunity Product');
            }

            for (Id opportunityId : opportunitiesWithMissingEppPrice) {
                opportunitiesLeavingDraft.get(opportunityId).addError(
                    'Enter an EPP Price for every consumable with Elevated / EPP Pricing Applicable before moving the EPP beyond Draft.'
                );
            }
        } catch (Exception exceptionValue) {
            Logger.error(CLASS_NAME + '.validateBeforeUpdate', exceptionValue)
                .addTag('Opportunity');
            throw exceptionValue;
        } finally {
            Logger.saveLog();
        }
    }
}