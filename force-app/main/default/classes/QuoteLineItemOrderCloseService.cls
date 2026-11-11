/**
 * @author Himanshu Chaurasia
 * @date 2026/11/06
 *
 * @group Quote Line Item
 *
 * @description GC-3587 - Closes the parent Opportunity as Closed Won when Order_Number__c is received on a Quote Line Item.
 */
public with sharing class QuoteLineItemOrderCloseService {
    private static final String CLASS_NAME = 'QuoteLineItemOrderCloseService';
    private static final String CLOSED_WON_STAGE_NAME = 'Closed Won';
    private static final String ORDER_NUMBER_FIELD_NAME = 'Order_Number__c';

    /**
     * @description After-save entry point from QuoteLineItemService.
     * @param lineItems Trigger.new Quote Line Item rows.
     * @param oldLineItemMap Trigger.oldMap, null on insert.
     */
    public static void handleAfterSave(
        List<QuoteLineItem> lineItems,
        Map<Id, QuoteLineItem> oldLineItemMap
    ) {
        closeParentOpportunitiesWhenOrderNumberReceived(lineItems, oldLineItemMap);
    }

    @TestVisible
    private static void closeParentOpportunitiesWhenOrderNumberReceived(
        List<QuoteLineItem> lineItems,
        Map<Id, QuoteLineItem> oldLineItemMap
    ) {
        if (lineItems == null || lineItems.isEmpty() || !isOrderNumberFieldAvailable()) {
            return;
        }

        Set<Id> quoteIds = new Set<Id>();
        for (QuoteLineItem lineItem : lineItems) {
            if (lineItem == null || lineItem.QuoteId == null) {
                continue;
            }

            QuoteLineItem oldLineItem =
                oldLineItemMap == null ? null : oldLineItemMap.get(lineItem.Id);

            if (!isOrderNumberReceivedOrUpdated(lineItem, oldLineItem)) {
                continue;
            }

            quoteIds.add(lineItem.QuoteId);
        }

        if (quoteIds.isEmpty()) {
            return;
        }

        Set<Id> opportunityIds = resolveOpenOpportunityIdsForQuotes(quoteIds);
        if (opportunityIds.isEmpty()) {
            return;
        }

        List<Opportunity> opportunitiesToClose = new List<Opportunity>();
        for (Id opportunityId : opportunityIds) {
            opportunitiesToClose.add(
                new Opportunity(Id = opportunityId, StageName = CLOSED_WON_STAGE_NAME)
            );
        }

        try {
            for (Database.SaveResult saveResult : Database.update(
                opportunitiesToClose,
                false,
                AccessLevel.SYSTEM_MODE
            )) {
                if (saveResult.isSuccess()) {
                    continue;
                }

                for (Database.Error saveError : saveResult.getErrors()) {
                    Logger.error(
                        CLASS_NAME +
                            '.closeParentOpportunitiesWhenOrderNumberReceived: ' +
                            saveError.getMessage()
                    ).addTag(CLASS_NAME);
                }
            }
        } finally {
            Logger.saveLog();
        }
    }

    @TestVisible
    private static Boolean isOrderNumberReceivedOrUpdated(
        QuoteLineItem lineItem,
        QuoteLineItem oldLineItem
    ) {
        if (lineItem == null) {
            return false;
        }

        String newOrderNumber = normalizeOrderNumber(readOrderNumber(lineItem));
        if (String.isBlank(newOrderNumber)) {
            return false;
        }

        if (oldLineItem == null) {
            return true;
        }

        String oldOrderNumber = normalizeOrderNumber(readOrderNumber(oldLineItem));
        return !newOrderNumber.equalsIgnoreCase(oldOrderNumber);
    }

    private static String readOrderNumber(QuoteLineItem lineItem) {
        Object orderNumberValue = lineItem.get(ORDER_NUMBER_FIELD_NAME);
        return orderNumberValue == null ? null : String.valueOf(orderNumberValue);
    }

    private static String normalizeOrderNumber(String orderNumber) {
        return String.isBlank(orderNumber) ? null : orderNumber.trim();
    }

    private static Boolean isOrderNumberFieldAvailable() {
        return Schema.SObjectType.QuoteLineItem.fields.getMap().containsKey(ORDER_NUMBER_FIELD_NAME);
    }

    private static Set<Id> resolveOpenOpportunityIdsForQuotes(Set<Id> quoteIds) {
        Set<Id> opportunityIds = new Set<Id>();

        for (Quote quoteRecord : [
            SELECT Id, OpportunityId
            FROM Quote
            WHERE Id IN :quoteIds
              AND OpportunityId != NULL
            WITH SYSTEM_MODE
        ]) {
            opportunityIds.add(quoteRecord.OpportunityId);
        }

        if (opportunityIds.isEmpty()) {
            return opportunityIds;
        }

        Set<Id> openOpportunityIds = new Set<Id>();
        for (Opportunity opportunityRecord : [
            SELECT Id
            FROM Opportunity
            WHERE Id IN :opportunityIds
              AND IsClosed = FALSE
            WITH SYSTEM_MODE
        ]) {
            openOpportunityIds.add(opportunityRecord.Id);
        }

        return openOpportunityIds;
    }
}