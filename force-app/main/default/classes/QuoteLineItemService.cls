/**
 * @author Himanshu Chaurasia
 * @date 2026/07/30
 *
 * @group Quote Line Item
 *
 * @description Orchestrates Quote Line Item trigger behavior and Sprint 9 Repair Center queries.
 */
public with sharing class QuoteLineItemService {
    private static final List<String> PRICING_FRAMEWORK_FIELDS = new List<String>{
        'Id',
        'Product2.ProductCode',
        'Product2.PricingSource__c',
        'Quantity'
    };

    private static final List<String> PRICING_FRAMEWORK_HEADLESS_FIELDS = new List<String>{
        'Id',
        'QuoteId',
        'Product2Id',
        'Product2.ProductCode',
        'Product2.PricingSource__c',
        'PricebookEntryId',
        'Quantity',
        'PricebookEntry.Pricebook2Id',
        'Quote.Pricebook2Id',
        'Quote.CurrencyIsoCode',
        'Quote.AccountId'
    };

    @TestVisible
    private static List<AssetAction> testAssetActions;

    @TestVisible
    private static List<AssetActionSource> testAssetActionSources;

    /**
     * @description GW-5102 - Quote Line Items used when processing Repair Center quote email replies.
     *              SYSTEM_MODE retained (builder is USER_MODE only).
     * @param quoteId Quote Id
     * @return Matching Quote Line Item rows
     */
    public static List<QuoteLineItem> getForQuoteEmailReplyByQuoteId(Id quoteId) {
        if (quoteId == null) {
            return new List<QuoteLineItem>();
        }
        return [
            SELECT
                Id,
                QuoteId,
                Quantity,
                Description,
                LineType__c,
                Status__c,
                Product2Id,
                Product2.Name,
                Product2.ProductCode,
                Product2.Description,
                Product2.Model__c,
                Product2.ProductType__c,
                WorkOrderLineItem__c,
                ParentWorkOrderLineItem__c,
                Asset__c,
                SerialNumber__c,
                Item__c,
                ItemCode__c,
                ItemDescription__c,
                ProductDescription__c,
                WorkOrder__c,
                TopLevelWorkOrder__c
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
            WITH SYSTEM_MODE
            ORDER BY LineNumber ASC
        ];
    }

    /**
     * @description GW-5333 - Selects Quote Line Items for Approve/Reject Quote.
     *              SYSTEM_MODE retained (builder is USER_MODE only).
     * @param quoteId Quote Id
     * @return Matching Quote Line Item rows
     */
    public static List<QuoteLineItem> getForApproveRejectByQuoteId(Id quoteId) {
        if (quoteId == null) {
            return new List<QuoteLineItem>();
        }
        return [
            SELECT
                Id,
                QuoteId,
                LineNumber,
                Quantity,
                Description,
                TotalPrice,
                LineType__c,
                Status__c,
                QuoteComments__c,
                ParentQuoteLineItemId,
                Product2Id,
                WorkOrderLineItem__c,
                ParentWorkOrderLineItem__c,
                Asset__c,
                SerialNumber__c,
                Item__c,
                ItemCode__c,
                ItemDescription__c,
                ProductDescription__c,
                WorkOrder__c,
                TopLevelWorkOrder__c
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
            WITH SYSTEM_MODE
            ORDER BY LineNumber ASC
        ];
    }

    /**
     * @description GW-5333 - Selects a Quote Line Item for comment updates.
     *              SYSTEM_MODE retained (builder is USER_MODE only).
     * @param quoteLineItemId Quote Line Item Id
     * @return Matching Quote Line Item, or null
     */
    public static QuoteLineItem getForApproveRejectById(Id quoteLineItemId) {
        if (quoteLineItemId == null) {
            return null;
        }
        List<QuoteLineItem> lineItems = [
            SELECT Id, QuoteId, QuoteComments__c
            FROM QuoteLineItem
            WHERE Id = :quoteLineItemId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return lineItems.isEmpty() ? null : lineItems[0];
    }

    /**
     * @description GW-4585 - Quote lines used when pricing JSON does not include line rows.
     * @param quoteIds Quote header Ids
     * @return Quote line items with product pricing fields
     */
    public static List<QuoteLineItem> getForPricingFrameworkByQuoteIds(Set<Id> quoteIds) {
        if (quoteIds == null || quoteIds.isEmpty()) {
            return new List<QuoteLineItem>();
        }
        return (List<QuoteLineItem>) new QuoteLineItemSelector()
            .selectFields(PRICING_FRAMEWORK_FIELDS)
            .whereIn('QuoteId', new List<Id>(quoteIds))
            .execute();
    }

    /**
     * @description GW-4585 - Quote lines used to build Salesforce Headless Pricing JSON.
     * @param lineIds Quote line item Ids
     * @return Quote line items with header and price book context
     */
    public static Map<Id, QuoteLineItem> getForPricingFrameworkHeadlessByIds(Set<Id> lineIds) {
        if (lineIds == null || lineIds.isEmpty()) {
            return new Map<Id, QuoteLineItem>();
        }
        List<QuoteLineItem> rows = (List<QuoteLineItem>) new QuoteLineItemSelector()
            .selectFields(PRICING_FRAMEWORK_HEADLESS_FIELDS)
            .whereIn('Id', new List<Id>(lineIds))
            .execute();
        return new Map<Id, QuoteLineItem>(rows);
    }

    /**
     * @description Before-insert orchestration: constraint engine node status (GW-5302).
     * @param lineItems Trigger.new rows.
     */
    public static void handleBeforeInsert(List<QuoteLineItem> lineItems) {
        setConstraintEngineNodeStatus(lineItems);
    }

    /**
     * @description Persists Quote Line Item field updates (Repair Center and related flows).
     * @param lineItems Quote Line Items to update.
     */
    public static void updateQuoteLineItems(List<QuoteLineItem> lineItems) {
        if (lineItems == null || lineItems.isEmpty()) {
            return;
        }

        Database.SaveResult[] saveResults = Database.update(lineItems, false, AccessLevel.SYSTEM_MODE);

        for (Database.SaveResult saveResult : saveResults) {
            if (saveResult.isSuccess()) {
                continue;
            }

            List<String> errorMessages = new List<String>();
            for (Database.Error saveError : saveResult.getErrors()) {
                errorMessages.add(saveError.getMessage());
            }

            throw new AuraHandledException(String.join(errorMessages, ' '));
        }
    }

    /**
     * @description After-insert orchestration for Quote Line Item trigger events.
     * @param lineItems Trigger.new rows.
     */
    public static void handleAfterInsert(List<QuoteLineItem> lineItems) {
        recalculateProductSubGroupDetail(lineItems, null);
        syncQuoteTotalWithoutFreight(lineItems, null);
        QuoteForecastChangeNotificationHandler.afterInsertLineItems(lineItems);
    }

    /**
     * @description After-update orchestration for Quote Line Item trigger events.
     * @param lineItems Trigger.new rows.
     * @param oldLineItemMap Trigger.oldMap.
     */
    public static void handleAfterUpdate(
        List<QuoteLineItem> lineItems,
        Map<Id, QuoteLineItem> oldLineItemMap
    ) {
        recalculateProductSubGroupDetail(lineItems, oldLineItemMap);
        syncQuoteTotalWithoutFreight(lineItems, oldLineItemMap);
        QuoteForecastChangeNotificationHandler.afterUpdateLineItems(lineItems, oldLineItemMap);
    }

    /**
     * @description After-delete orchestration for Quote Line Item trigger events.
     * @param lineItems Trigger.old rows.
     */
    public static void handleAfterDelete(List<QuoteLineItem> lineItems) {
        recalculateProductSubGroupDetail(lineItems, null);
        syncQuoteTotalWithoutFreight(lineItems, null);
        QuoteForecastChangeNotificationHandler.afterDeleteLineItems(lineItems);
    }

    /**
     * @description After-undelete orchestration for Quote Line Item trigger events.
     * @param lineItems Trigger.new rows.
     */
    public static void handleAfterUndelete(List<QuoteLineItem> lineItems) {
        recalculateProductSubGroupDetail(lineItems, null);
        syncQuoteTotalWithoutFreight(lineItems, null);
        QuoteForecastChangeNotificationHandler.afterUndeleteLineItems(lineItems);
    }

    /**
     * @description GW-5302 - Stamps ConstraintEngineNodeStatus__c from the latest Asset Action Source on the Quote Action asset.
     */
    @TestVisible
    private static void setConstraintEngineNodeStatus(List<QuoteLineItem> lineItems) {
        if (lineItems == null || lineItems.isEmpty()) {
            return;
        }

        Set<Id> quoteActionIds = new Set<Id>();
        for (QuoteLineItem lineItem : lineItems) {
            if (
                lineItem == null ||
                lineItem.QuoteActionId == null ||
                String.isNotBlank(lineItem.ConstraintEngineNodeStatus__c)
            ) {
                continue;
            }

            quoteActionIds.add(lineItem.QuoteActionId);
        }

        if (quoteActionIds.isEmpty()) {
            return;
        }

        Map<Id, Id> assetIdByQuoteActionId = new Map<Id, Id>();
        for (QuoteAction quoteAction : [
            SELECT Id, SourceAssetId
            FROM QuoteAction
            WHERE Id IN :quoteActionIds
            WITH SYSTEM_MODE
        ]) {
            if (quoteAction.SourceAssetId != null) {
                assetIdByQuoteActionId.put(quoteAction.Id, quoteAction.SourceAssetId);
            }
        }

        if (assetIdByQuoteActionId.isEmpty()) {
            return;
        }

        Map<Id, String> statusByAssetId = resolveConstraintStatusByAssetId(
            new Set<Id>(assetIdByQuoteActionId.values())
        );

        for (QuoteLineItem lineItem : lineItems) {
            if (lineItem == null || String.isNotBlank(lineItem.ConstraintEngineNodeStatus__c)) {
                continue;
            }

            Id assetId = assetIdByQuoteActionId.get(lineItem.QuoteActionId);
            if (assetId == null) {
                continue;
            }

            String constraintStatus = statusByAssetId.get(assetId);
            if (String.isNotBlank(constraintStatus)) {
                lineItem.ConstraintEngineNodeStatus__c = constraintStatus;
            }
        }
    }

    @TestVisible
    private static Map<Id, String> resolveConstraintStatusByAssetId(Set<Id> assetIds) {
        Map<Id, String> statusByAssetId = new Map<Id, String>();

        if (assetIds == null || assetIds.isEmpty()) {
            return statusByAssetId;
        }

        List<AssetAction> assetActions = testAssetActions != null
            ? testAssetActions
            : [
                  SELECT Id, AssetId, ActionDate
                  FROM AssetAction
                  WHERE AssetId IN :assetIds
                  WITH SYSTEM_MODE
              ];

        Map<Id, AssetAction> latestActionByAssetId = new Map<Id, AssetAction>();
        for (AssetAction assetAction : assetActions) {
            if (assetAction == null || assetAction.AssetId == null) {
                continue;
            }

            AssetAction currentLatest = latestActionByAssetId.get(assetAction.AssetId);
            if (
                currentLatest == null ||
                assetAction.ActionDate > currentLatest.ActionDate ||
                (assetAction.ActionDate == currentLatest.ActionDate &&
                assetAction.Id > currentLatest.Id)
            ) {
                latestActionByAssetId.put(assetAction.AssetId, assetAction);
            }
        }

        if (latestActionByAssetId.isEmpty()) {
            return statusByAssetId;
        }

        Set<Id> latestActionIds = new Set<Id>();
        for (AssetAction latestAction : latestActionByAssetId.values()) {
            latestActionIds.add(latestAction.Id);
        }

        List<AssetActionSource> assetActionSources = testAssetActionSources != null
            ? testAssetActionSources
            : [
                  SELECT AssetActionId, ConstraintEngineNodeStatus__c
                  FROM AssetActionSource
                  WHERE AssetActionId IN :latestActionIds
                  WITH SYSTEM_MODE
              ];

        Map<Id, String> statusByActionId = new Map<Id, String>();
        for (AssetActionSource assetActionSource : assetActionSources) {
            if (
                assetActionSource == null ||
                assetActionSource.AssetActionId == null ||
                String.isBlank(assetActionSource.ConstraintEngineNodeStatus__c)
            ) {
                continue;
            }

            statusByActionId.put(
                assetActionSource.AssetActionId,
                assetActionSource.ConstraintEngineNodeStatus__c
            );
        }

        for (Id assetId : latestActionByAssetId.keySet()) {
            AssetAction latestAction = latestActionByAssetId.get(assetId);
            String constraintStatus = statusByActionId.get(latestAction.Id);
            if (String.isNotBlank(constraintStatus)) {
                statusByAssetId.put(assetId, constraintStatus);
            }
        }

        return statusByAssetId;
    }

    private static void syncQuoteTotalWithoutFreight(
        List<QuoteLineItem> lineItems,
        Map<Id, QuoteLineItem> oldLineItemMap
    ) {
        Set<Id> quoteIds = new Set<Id>();

        for (QuoteLineItem lineItem : lineItems) {
            if (lineItem.QuoteId != null) {
                quoteIds.add(lineItem.QuoteId);
            }
        }

        if (oldLineItemMap != null) {
            for (QuoteLineItem oldLineItem : oldLineItemMap.values()) {
                if (oldLineItem.QuoteId != null) {
                    quoteIds.add(oldLineItem.QuoteId);
                }
            }
        }

        QuoteService.syncQuoteTotalWithoutFreightFromLines(quoteIds);
    }

    private static void recalculateProductSubGroupDetail(
        List<QuoteLineItem> lineItems,
        Map<Id, QuoteLineItem> oldLineItemMap
    ) {
        if (lineItems == null || lineItems.isEmpty()) {
            return;
        }

        if (OpportunityLineItemService.isRecalculationDisabled()) {
            return;
        }

        try {
            Logger.info('QuoteLineItemService: started').addTag(OpportunityLineItemService.LOGGER_TAG);

            Set<Id> opportunityIds = collectOpportunityIds(lineItems, oldLineItemMap);
            OpportunityLineItemService.recalculateFromOpportunityIds(opportunityIds);

            Logger.info('QuoteLineItemService: completed').addTag(OpportunityLineItemService.LOGGER_TAG);
        } catch (Exception exceptionValue) {
            Logger.error('QuoteLineItemService: ' + exceptionValue.getMessage()).addTag(
                OpportunityLineItemService.LOGGER_TAG
            );
            throw exceptionValue;
        } finally {
            Logger.saveLog();
        }
    }

    @TestVisible
    private static Set<Id> collectOpportunityIds(
        List<QuoteLineItem> lineItems,
        Map<Id, QuoteLineItem> oldLineItemMap
    ) {
        Set<Id> quoteIds = new Set<Id>();

        for (QuoteLineItem lineItem : lineItems) {
            if (lineItem.QuoteId != null) {
                quoteIds.add(lineItem.QuoteId);
            }
        }

        if (oldLineItemMap != null) {
            for (QuoteLineItem oldLineItem : oldLineItemMap.values()) {
                if (oldLineItem.QuoteId != null) {
                    quoteIds.add(oldLineItem.QuoteId);
                }
            }
        }

        Set<Id> opportunityIds = new Set<Id>();
        for (Id opportunityId : ProductSubGroupDetailQuoteSelector.selectOpportunityIdByQuoteId(quoteIds).values()) {
            opportunityIds.add(opportunityId);
        }

        return opportunityIds;
    }

    /**
     * @description GW-3600 - Loads Quote Line Items for Repair Center document generation.
     * @param quoteId Repair Center Quote Id.
     * @return Line items ordered by CreatedDate, or an empty list when the Id is null.
     */
    public static List<QuoteLineItem> selectForRepairCenterDocumentGeneration(Id quoteId) {
        if (quoteId == null) {
            return new List<QuoteLineItem>();
        }
        return (List<QuoteLineItem>) new QuoteLineItemSelector()
            .selectFields(
                new List<String>{
                    'Id',
                    'LineType__c',
                    'ParentQuoteLineItemId',
                    'ParentWorkOrderLineItem__c',
                    'SerialNumber__c',
                    'ProductCode__c',
                    'ProductDescription__c',
                    'Status__c',
                    'TurnTime__c',
                    'Quantity',
                    'TotalPrice',
                    'NetTotalPrice__c',
                    'UOM__c',
                    'ReturnOrderLineItems__c',
                    'WorkOrderLineItem__c',
                    'WorkOrderLineItem__r.WorkOrderId',
                    'WorkOrderLineItem__r.WorkOrder.EvaluationNotes__c',
                    'Condition__c'
                }
            )
            .whereEquals('QuoteId', quoteId)
            .orderBy('CreatedDate')
            .execute();
    }

    /**
     * @description GW-4117 - Loads Quote Line Items evaluated for Repair Center pre-approval.
     * @param quoteIds Quote Ids whose lines should be loaded.
     * @return Matching line items, or an empty list when no Ids are provided.
     */
    public static List<QuoteLineItem> selectForRepairCenterPreApproval(Set<Id> quoteIds) {
        if (quoteIds == null || quoteIds.isEmpty()) {
            return new List<QuoteLineItem>();
        }
        SoqlQueryBuilder query = new QuoteLineItemSelector()
            .selectFields(
                new List<String>{
                    'Id',
                    'QuoteId',
                    'LineType__c',
                    'Status__c',
                    'TotalPrice',
                    'NetTotalPrice__c',
                    'ProductLine__c',
                    'ParentWorkOrderLineItem__c',
                    'WorkOrderLineItem__c'
                }
            );
        List<String> idFilterNumbers = new List<String>();
        Integer filterNumber = 1;
        for (Id quoteId : quoteIds) {
            if (quoteId == null) {
                continue;
            }
            query.whereEquals('QuoteId', quoteId);
            idFilterNumbers.add(String.valueOf(filterNumber));
            filterNumber++;
        }
        if (idFilterNumbers.isEmpty()) {
            return new List<QuoteLineItem>();
        }
        if (idFilterNumbers.size() > 1) {
            query.withFilterLogic(String.join(idFilterNumbers, ' OR '));
        }
        return (List<QuoteLineItem>) query.execute();
    }

    /**
     * @description GW-5333 - Returns Quote Line Items for Approve/Reject Quote.
     * @param quoteId Quote Id
     * @return Matching Quote Line Item rows
     */
    public static List<QuoteLineItem> getLineItemsForApproveReject(Id quoteId) {
        return getForApproveRejectByQuoteId(quoteId);
    }

    /**
     * @description GW-5333 - Persists Quote Line Item status updates for Approve/Reject Quote.
     * @param lineItems Quote Line Items to update
     */
    public static void updateLineItemsForApproveReject(List<QuoteLineItem> lineItems) {
        if (lineItems == null || lineItems.isEmpty()) {
            return;
        }

        try {
            Logger.info('QuoteLineItemService.updateLineItemsForApproveReject: started')
                .addTag(OpportunityLineItemService.LOGGER_TAG);
            update lineItems;
            Logger.info('QuoteLineItemService.updateLineItemsForApproveReject: completed')
                .addTag(OpportunityLineItemService.LOGGER_TAG);
        } catch (Exception exceptionValue) {
            Logger.error(
                'QuoteLineItemService.updateLineItemsForApproveReject: ' + exceptionValue.getMessage()
            ).addTag(OpportunityLineItemService.LOGGER_TAG);
            throw exceptionValue;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5333 - Saves Quote Comments on a Quote Line Item immediately.
     * @param quoteLineItemId Quote Line Item Id
     * @param comments Quote Comments text
     * @return Updated Quote Line Item
     */
    public static QuoteLineItem saveQuoteComments(Id quoteLineItemId, String comments) {
        QuoteLineItem lineItem = getForApproveRejectById(quoteLineItemId);
        if (lineItem == null) {
            throw new QuoteLineItemServiceException('Quote Line Item was not found.');
        }

        lineItem.QuoteComments__c = comments;
        updateLineItemsForApproveReject(new List<QuoteLineItem>{ lineItem });
        return lineItem;
    }

    /**
     * @description Thrown when a Quote Line Item service operation fails.
     */
    public class QuoteLineItemServiceException extends Exception {}
}