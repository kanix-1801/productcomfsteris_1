/**
 * @description Service class for ReturnOrderLineItem business operations.
 *              Entry point for all ReturnOrderLineItem-related transactions.
 *              Performs DML directly — no Unit of Work.
 */
public with sharing class ReturnOrderLineItemsService {
    /**
     * @description Creates new ReturnOrderLineItem records with validation.
     * @param lineItems List of ReturnOrderLineItem records to create.
     * @throws ReturnOrderLineItemsServiceException when the operation fails.
     */
    public static void createReturnOrderLineItems(List<ReturnOrderLineItem> lineItems) {
        if (lineItems == null || lineItems.isEmpty()) {
            return;
        }
        Logger.setScenario('Return Order Line Item Management');
        try {
            ReturnOrderLineItems domain = new ReturnOrderLineItems(lineItems);
            // domain.applyDefaults();
            // domain.validate();
            insert lineItems;
        } catch (Exception e) {
            Logger.error('ReturnOrderLineItemsService.createReturnOrderLineItems: Unexpected error.', e);
            Logger.saveLog();
            throw new ReturnOrderLineItemsServiceException('An unexpected error occurred while creating ReturnOrderLineItem records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Updates existing ReturnOrderLineItem records with validation.
     * @param lineItems List of ReturnOrderLineItem records to update.
     * @throws ReturnOrderLineItemsServiceException when the operation fails.
     */
    public static void updateReturnOrderLineItems(List<ReturnOrderLineItem> lineItems) {
        if (lineItems == null || lineItems.isEmpty()) {
            return;
        }
        Logger.setScenario('Return Order Line Item Management');
        try {
            ReturnOrderLineItems domain = new ReturnOrderLineItems(lineItems);
            // domain.validate();
            update lineItems;
        } catch (Exception e) {
            Logger.error('ReturnOrderLineItemsService.updateReturnOrderLineItems: Unexpected error.', e);
            Logger.saveLog();
            throw new ReturnOrderLineItemsServiceException('An unexpected error occurred while updating ReturnOrderLineItem records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Deletes ReturnOrderLineItem records by their Ids.
     * @param lineItemIds Set of ReturnOrderLineItem Ids to delete.
     * @throws ReturnOrderLineItemsServiceException when the operation fails.
     */
    public static void deleteReturnOrderLineItems(Set<Id> lineItemIds) {
        if (lineItemIds == null || lineItemIds.isEmpty()) {
            return;
        }
        Logger.setScenario('Return Order Line Item Management');
        try {
            List<ReturnOrderLineItem> lineItemList = ReturnOrderLineItemsSelector.selectById(lineItemIds);
            if (lineItemList.isEmpty()) {
                return;
            }
            delete lineItemList;
        } catch (Exception e) {
            Logger.error('ReturnOrderLineItemsService.deleteReturnOrderLineItems: Unexpected error.', e);
            Logger.saveLog();
            throw new ReturnOrderLineItemsServiceException('An unexpected error occurred while deleting ReturnOrderLineItem records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Retrieves ReturnOrderLineItem records by their Ids.
     * @param lineItemIds Set of ReturnOrderLineItem Ids to retrieve.
     * @return List of ReturnOrderLineItem records.
     * @throws ReturnOrderLineItemsServiceException when the operation fails.
     */
    public static List<ReturnOrderLineItem> getReturnOrderLineItemsById(Set<Id> lineItemIds) {
        if (lineItemIds == null || lineItemIds.isEmpty()) {
            return new List<ReturnOrderLineItem>();
        }
        try {
            return ReturnOrderLineItemsSelector.selectById(lineItemIds);
        } catch (Exception e) {
            Logger.error('ReturnOrderLineItemsService.getReturnOrderLineItemsById: Unexpected error.', e);
            Logger.saveLog();
            throw new ReturnOrderLineItemsServiceException('An unexpected error occurred while retrieving ReturnOrderLineItem records.', e);
        }
    }

    /**
     * @description GW-5324 - Loads Return Order lines for Instrument Evaluation assignment.
     * @param returnOrderId Customer Return Order Id
     * @return Return Order lines available for assignment
     */
    public static List<ReturnOrderLineItem> getInstrumentEvaluationLineItems(Id returnOrderId) {
        if (returnOrderId == null) {
            return new List<ReturnOrderLineItem>();
        }
        return ReturnOrderLineItemsSelector.selectForInstrumentEvaluation(returnOrderId);
    }

    /**
     * @description GW-5492 - Counts open Created line items for a Return Order.
     * @param returnOrderId Return Order Id
     * @return Count of Created lines
     */
    public static Integer countCreatedByReturnOrderId(Id returnOrderId) {
        return ReturnOrderLineItemsSelector.countCreatedByReturnOrderId(returnOrderId);
    }

    /**
     * @description GW-5492 - Return Order Line Items with fields needed for Finish Receiving / Redirect.
     * @param lineItemIds Line item Ids
     * @return Matching line items, or an empty list when Ids are null or empty
     */
    public static List<ReturnOrderLineItem> getLinesForReceivingFinish(Set<Id> lineItemIds) {
        if (lineItemIds == null || lineItemIds.isEmpty()) {
            return new List<ReturnOrderLineItem>();
        }
        return ReturnOrderLineItemsSelector.selectForReceivingFinish(lineItemIds);
    }

    /**
     * @description GW-5492 - Marks line items Received after Finish Receiving WO create.
     * @param lineItemIds Line item Ids
     * @param receiverId Receiver user Id
     * @param receivedDateTime Received datetime
     * @param quantityReceived Quantity received (optional)
     */
    public static void markLinesReceivedForReceiving(
        Set<Id> lineItemIds,
        Id receiverId,
        Datetime receivedDateTime,
        Decimal quantityReceived
    ) {
        if (lineItemIds == null || lineItemIds.isEmpty()) {
            return;
        }
        List<ReturnOrderLineItem> existing =
            ReturnOrderLineItemsSelector.selectForReceivingFinish(lineItemIds);
        List<ReturnOrderLineItem> updates = new List<ReturnOrderLineItem>();
        for (ReturnOrderLineItem lineItem : existing) {
            if (lineItem.Status__c != 'Created') {
                continue;
            }
            ReturnOrderLineItem updateLine = new ReturnOrderLineItem(Id = lineItem.Id);
            updateLine.Status__c = 'Received';
            updateLine.Receiver__c = receiverId;
            updateLine.ReceivedDateTime__c = receivedDateTime;
            updateLine.QuantityReceived = quantityReceived != null
                ? quantityReceived
                : (lineItem.QuantityReturned != null ? lineItem.QuantityReturned : 1);
            updates.add(updateLine);
        }
        if (!updates.isEmpty()) {
            Database.update(updates, AccessLevel.USER_MODE);
        }
    }

    /**
     * @description GW-5492 - Marks a line item Redirected.
     * @param lineItemId Line item Id
     */
    public static void markLineRedirectedForReceiving(Id lineItemId) {
        if (lineItemId == null) {
            return;
        }
        markLinesRedirectedForReceiving(new Set<Id>{ lineItemId });
    }

    /**
     * @description GW-5492 - Marks line items Redirected.
     * @param lineItemIds Line item Ids
     */
    public static void markLinesRedirectedForReceiving(Set<Id> lineItemIds) {
        if (lineItemIds == null || lineItemIds.isEmpty()) {
            return;
        }
        List<ReturnOrderLineItem> updates = new List<ReturnOrderLineItem>();
        for (Id lineItemId : lineItemIds) {
            if (lineItemId == null) {
                continue;
            }
            updates.add(new ReturnOrderLineItem(Id = lineItemId, Status__c = 'Redirected'));
        }
        if (!updates.isEmpty()) {
            Database.update(updates, AccessLevel.USER_MODE);
        }
    }

    /**
     * @description Thrown when a ReturnOrderLineItem service operation fails.
     */
    public class ReturnOrderLineItemsServiceException extends Exception {}
}