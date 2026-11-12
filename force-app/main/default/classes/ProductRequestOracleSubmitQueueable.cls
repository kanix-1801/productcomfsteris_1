/**
 * @description GW-514: Queues the Oracle Create Sales Order callout after the Product Request save commits.
 *              The record-triggered flow calls enqueue. The queueable performs the callout.
 */
public with sharing class ProductRequestOracleSubmitQueueable implements Queueable, Database.AllowsCallouts {
    public List<Id> productRequestIds;

    /**
     * @description Builds a queueable for one or more Product Requests.
     * @param productRequestIds Product Request Ids to submit.
     */
    public ProductRequestOracleSubmitQueueable(List<Id> productRequestIds) {
        this.productRequestIds = productRequestIds == null
            ? new List<Id>()
            : productRequestIds.clone();
    }

    /**
     * @description Runs the Oracle submit after the triggering transaction has committed.
     * @param context Queueable context.
     */
    public void execute(QueueableContext context) {
        List<ProductRequestsService.OracleSubmitRequest> requests = new List<ProductRequestsService.OracleSubmitRequest>();
        for (Id productRequestId : productRequestIds) {
            ProductRequestsService.OracleSubmitRequest req = new ProductRequestsService.OracleSubmitRequest();
            req.productRequestId = productRequestId;
            req.performCallout = true;
            requests.add(req);
        }
        if (requests.isEmpty()) {
            return;
        }
        List<ProductRequestsService.OracleSubmitResult> results = ProductRequestsService.submitOracleSalesOrder(requests);
        for (Integer i = 0; i < requests.size(); i++) {
            ProductRequestsService.OracleSubmitResult result = i < results.size() ? results[i] : null;
            if (result == null) {
                continue;
            }
            ProductRequest current = [
                SELECT IntegrationStatus__c
                FROM ProductRequest
                WHERE Id = :requests[i].productRequestId
            ];
            if (current.IntegrationStatus__c == null) {
                update new ProductRequest(
                    Id = requests[i].productRequestId,
                    IntegrationStatus__c = result.integrationStatus,
                    IntegrationMessage__c = result.integrationMessage
                );
            }
        }
    }

    /**
     * @description Flow input for one Product Request.
     */
    public class Request {
        @InvocableVariable(required=true label='Product Request Id')
        public Id productRequestId;
    }

    /**
     * @description GW-514: Invocable entry for ProductRequest_AfterSave_SubmitToERP.
     *              Enqueues the callout so it runs after the save commits.
     * @param requests Product Request ids from the record-triggered flow.
     */
    @InvocableMethod(
        label='Product Request - Queue Oracle Sales Order'
        description='GW-514: Queues the Oracle Create Sales Order callout after the Product Request save commits.'
    )
    public static void enqueue(List<Request> requests) {
        List<Id> ids = new List<Id>();
        if (requests != null) {
            for (Request req : requests) {
                if (req != null && req.productRequestId != null) {
                    ids.add(req.productRequestId);
                }
            }
        }
        if (!ids.isEmpty()) {
            System.enqueueJob(new ProductRequestOracleSubmitQueueable(ids));
        }
    }
}