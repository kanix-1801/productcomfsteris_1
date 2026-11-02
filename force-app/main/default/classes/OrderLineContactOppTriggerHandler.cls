/**
 * @author Akash Dahinde
 * @date 06-03-2026
 * @description Kevin Ohara trigger handler for Opportunity insert/update events.
 *
 *              Responsibilities:
 *              1. Receive Opportunity trigger context from OpportunityTrigger.
 *              2. Detect when Address__c is populated or changed.
 *              3. Delegate to OrderLineContactTeamRealtimeService for async ADD processing.
 *
 *              This handler does not perform SOQL, DML, or team-member logic directly.
 *              Business rules remain in OrderLineContactTeamRealtimeService.
 *
 *              Realtime trigger flow is ADD-only:
 *              - Opportunity linked to Address__c -> add OpportunityTeamMember
 *              - No realtime team removal when Address__c is cleared or changed away
 */
public with sharing class OrderLineContactOppTriggerHandler extends TriggerHandler {


}