/**
 * Orchestrates Lead TAS assignment after Lead insert.
 *
 * @author Abhishek Mishra
 * @date 06-08-2026
 * @description #GC-3279 Collects eligible Leads from trigger context, applies the
 *              Lead size check and enqueues LeadTasQueueable for the TAS callout and owner update.
 */
public with sharing class LeadService {

    /**
     * Set by LeadCreateController for the same transaction. The product wizard
     * enqueues LeadRoutingQueueable after its products exist, so the Lead trigger
     * must not enqueue a second routing job.
     */
    public static Boolean skipInsertTas = false;

    /**
     * @description Validates required TAS fields, builds the eligible Lead Id set,
     *              and submits LeadTasQueueable only when one eligible Lead
     *              is present.
     * @param newLeads List of newly inserted Lead records from trigger context.
     */
    public static void assignTAStoLead(List<Lead> newLeads) {
        if (skipInsertTas) {
            return;
        }
        try {
            Logger.info('LeadService.assignTAStoLead: started');

            if (newLeads == null || newLeads.isEmpty()) {
                Logger.warn('LeadService.assignTAStoLead: newLeads is null or empty');
            } else {
                Set<Id> eligibleLeadIds = new Set<Id>();

                for (Lead leadRecord : newLeads) {
                    if (isValidLeadForTas(leadRecord)) {
                        eligibleLeadIds.add(leadRecord.Id);
                    }
                }

                if (!eligibleLeadIds.isEmpty() && eligibleLeadIds.size() == 1) {
                    Id jobId = System.enqueueJob(new LeadTasQueueable(eligibleLeadIds));

                    Logger.info(
                        'LeadService.assignTAStoLead: submitted LeadTasQueueable, jobId=' +
                        jobId
                    );
                } else if (eligibleLeadIds.size() > 1) {
                    Logger.warn(
                        'LeadService.assignTAStoLead: more than one eligible Lead found. Queueable not submitted. eligibleLeadCount=' +
                        eligibleLeadIds.size()
                    );
                }
            }

        } catch (Exception e) {
            Logger.error('LeadService.assignTAStoLead', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * Returns true when the Lead came from HubSpot and Postal Code, Country,
     * Org ID, and Class Code are populated. City is optional.
     */
    @TestVisible
    private static Boolean isValidLeadForTas(Lead leadRecord) {
        Boolean isValid = leadRecord != null
            && leadRecord.HubSpot_Lead__c
            && String.isNotBlank(leadRecord.PostalCode)
            && String.isNotBlank(leadRecord.Country)
            && String.isNotBlank(leadRecord.Org_ID__c)
            && String.isNotBlank(leadRecord.Class_Code__c);
        return isValid;
    }
}