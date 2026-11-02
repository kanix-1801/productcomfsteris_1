/**
 * Async queueable processor for Lead TAS assignment.
 *
 * @author Abhishek Mishra
 * @date 06-08-2026
 * @description #GC-3279 Receives eligible Lead Ids from LeadService, queries
 *              Lead fields required for the TAS payload, and delegates the
 *              TAS callout and owner assignment to LeadTasIntegrationService.
 */
public with sharing class LeadTasQueueable
    implements Queueable, Database.AllowsCallouts {

    private Set<Id> leadIds;

    /**
     * @description Stores a copy of the provided Lead Id set for asynchronous
     *              processing. Uses an empty set when the input is null.
     * @param leadIdSet Set of Lead Ids to process asynchronously.
     */
    public LeadTasQueueable(Set<Id> leadIdSet) {
        this.leadIds = leadIdSet == null ? new Set<Id>() : new Set<Id>(leadIdSet);
    }

    /**
     * @description Queries Leads by Id and calls LeadTasIntegrationService when
     *              at least one Lead Id is present.
     * @param context Queueable context provided by the platform.
     */
    public void execute(QueueableContext context) {
        try {
            if (!leadIds.isEmpty()) {
                List<Lead> leads = LeadSelector.selectByIds(leadIds);

                if (!leads.isEmpty()) {
                    LeadTasIntegrationService.processLeads(leads);
                    Logger.info(
                        'LeadTasQueueable.execute: processed leadCount=' + leads.size()
                    );
                }
            }
        } catch (Exception e) {
            Logger.error('LeadTasQueueable.execute', e);
        } finally {
            Logger.saveLog();
        }
    }
}