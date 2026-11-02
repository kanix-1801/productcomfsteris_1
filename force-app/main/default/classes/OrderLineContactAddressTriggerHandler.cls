/**
 * @author Akash Dahinde
 * @date 06-03-2026
 * @description Kevin Ohara trigger handler for Address insert/update events.
 *
 *              Responsibilities:
 *              1. Receive Address trigger context from AddressTrigger.
 *              2. Delegate Address change detection to OrderLineContactTeamRealtimeService.
 *              3. Enqueue async realtime ADD processing via the service layer.
 *
 *              This handler does not perform SOQL, DML, or team-member logic directly.
 *              Business rules remain in OrderLineContactTeamRealtimeService.
 *
 *              Realtime trigger flow is ADD-only:
 *              - Active Address linked to Account -> add AccountTeamMember
 *              - No realtime team removal on deactivate/unassign/delete
 */
public with sharing class OrderLineContactAddressTriggerHandler extends TriggerHandler {


}