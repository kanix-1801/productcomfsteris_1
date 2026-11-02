/**
 * @author Sahithi PWC
 * @date 01-07-2026
 * @description #GC-3196 Async queueable job to delete Opportunity Line Items
 * that Oracle Pricing marked as invalid (null price).
 *
 * Responsibilities:
 * - Receives a list of Opportunity Line Item Ids flagged for deletion
 * - Queries the OLIs to confirm they still exist
 * - Deletes them asynchronously to avoid blocking the pricing flow
 *
 * Invoked by OraclePricingIntegrationService after pricing completes.
 */
public with sharing class OraclePricingProductDeletionQueueable implements Queueable {

    private List<Id> oliIds;

    /**
     * Creates a queueable job for the given Opporta]unity Line Item Ids.
     *
     * @param oliIds Ids of Opportunity Line Items to delete.
     */
    public OraclePricingProductDeletionQueueable(List<Id> oliIds) {
        this.oliIds = oliIds;
    }

    /**
     * Executes the deletion job.
     *
     * Queries the OLIs by Id (in case records were removed since enqueue)
     * and deletes any that still exist.
     *
     * @param context Queueable context provided by the platform.
     */
    public void execute(QueueableContext context) {
        List<OpportunityLineItem> productsToDelete = [
            SELECT Id
            FROM OpportunityLineItem
            WHERE Id IN :oliIds
        ];

        if (!productsToDelete.isEmpty()) {
            delete productsToDelete;
        }
    }
}