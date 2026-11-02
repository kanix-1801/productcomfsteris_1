/**
 * @description Routes a Lead after the create transaction commits, so the Lead and Product Ids exist.
 *              The callout runs before the owner update inside LeadRoutingService.
 *              One Lead is routed per job because a callout cannot follow DML. Further Leads are chained.
 * @author      Vinay
 * @date        2026-10-12
 */
public class LeadRoutingQueueable implements Queueable, Database.AllowsCallouts {

    private final List<Id> leadIds;

    /**
     * @description Stores one Lead to route.
     * @param leadId Lead to route.
     */
    public LeadRoutingQueueable(Id leadId) {
        this.leadIds = new List<Id>();
        if (leadId != null) {
            this.leadIds.add(leadId);
        }
    }

    /**
     * @description Stores Leads to route, first to last.
     * @param leadIds Leads to route.
     */
    public LeadRoutingQueueable(List<Id> leadIds) {
        this.leadIds = leadIds == null ? new List<Id>() : leadIds;
    }

    /**
     * @description Enqueues routing for Leads created outside the New Lead page.
     * @param leadIds Leads to route after the insert transaction commits.
     */
    public static void enqueue(List<Id> leadIds) {
        List<Id> ids = new List<Id>();
        if (leadIds != null) {
            for (Id leadId : leadIds) {
                if (leadId != null) {
                    ids.add(leadId);
                }
            }
        }
        if (!ids.isEmpty()) {
            System.enqueueJob(new LeadRoutingQueueable(ids));
        }
    }

    /**
     * @description Runs matrix, TAS, and queue assignment for the first Lead, then chains the rest.
     * @param context Queueable context. Unused.
     */
    public void execute(QueueableContext context) {
        if (leadIds == null || leadIds.isEmpty() || leadIds[0] == null) {
            enqueueRemainder();
            return;
        }
        try {
            LeadRoutingService.submit(leadIds[0]);
        } catch (Exception ex) {
            Logger.error('LeadRoutingQueueable.execute LeadId=' + leadIds[0], ex);
            Logger.saveLog();
        } finally {
            enqueueRemainder();
        }
    }

    private void enqueueRemainder() {
        if (leadIds == null || leadIds.size() <= 1) {
            return;
        }
        List<Id> remaining = new List<Id>();
        for (Integer index = 1; index < leadIds.size(); index++) {
            if (leadIds[index] != null) {
                remaining.add(leadIds[index]);
            }
        }
        if (!remaining.isEmpty()) {
            System.enqueueJob(new LeadRoutingQueueable(remaining));
        }
    }
}