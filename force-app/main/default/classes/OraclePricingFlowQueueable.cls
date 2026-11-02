/**
 * @author Sahithi PWC
 * @date 01-07-2026
 * @description #GC-3294 Runs Oracle pricing asynchronously from Flow, button, or trigger.
 *              #GC-3317 Prospect pricing routed inside processOpportunity.
 *              Deletion of unpriced OLIs is handled inline (no second Queueable).
 */
public class OraclePricingFlowQueueable implements Queueable, Database.AllowsCallouts {

    private Id opportunityId;

    public OraclePricingFlowQueueable(Id opportunityId) {
        this.opportunityId = opportunityId;
    }

    public void execute(QueueableContext context) {
        OraclePricingIntegrationService.processOpportunity(opportunityId);
    }
}