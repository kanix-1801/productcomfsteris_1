/**
 * @description Queueable entry point for vendor FedEx label creation after Vendor Return
 *              Orders are inserted. Callouts are allowed because this is a new transaction.
 * @author Uptima Development Team
 * @date 2026-09-03
 * @group Queueable
 */
public with sharing class ReturnOrdersVendorShipmentQueueable implements Queueable, Database.AllowsCallouts {
    private Map<Id, List<Id>> returnOrderIdToWorkOrderIdsMap;

    /**
     * @description Stores Vendor Return Order Id to grouped Work Order Ids for the async job.
     * @param returnOrderIdToWorkOrderIdsMap Vendor Return Order Id to Work Order Ids
     */
    public ReturnOrdersVendorShipmentQueueable(Map<Id, List<Id>> returnOrderIdToWorkOrderIdsMap) {
        this.returnOrderIdToWorkOrderIdsMap = returnOrderIdToWorkOrderIdsMap == null
            ? new Map<Id, List<Id>>()
            : returnOrderIdToWorkOrderIdsMap;
    }

    /**
     * @description Runs vendor FedEx shipment creation and logs failures with Nebula Logger.
     * @param context Queueable context
     */
    public void execute(QueueableContext context) {
        try {
            Logger.info(
                new LogMessage(
                    'ReturnOrdersVendorShipmentQueueable started for {0} Return Order(s)',
                    returnOrderIdToWorkOrderIdsMap.size()
                )
            );
            ReturnOrdersService.createVendorFedExShipments(returnOrderIdToWorkOrderIdsMap);
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'ReturnOrdersVendorShipmentQueueable failed: {0}',
                    e.getMessage()
                ),
                e
            );
            if (e instanceof ReturnOrdersService.ReturnOrdersServiceException) {
                throw e;
            }
            throw new ReturnOrdersService.ReturnOrdersServiceException(
                'FedEx shipment queueable failed: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }
}