/**
 * @author Himanshu Chaurasia
 * @date 2026/07/29
 *
 * @description Stages forecast change notifications when Quote or Quote Line Item
 *              records change. Invoked from triggers after Generate Quote, Refresh Quote,
 *              and related Quote / QLI DML.
 */
public with sharing class QuoteForecastChangeNotificationHandler {
    @TestVisible
    private static final Set<String> FORECAST_INELIGIBLE_QUOTE_TYPES = new Set<String>{
        GenerateQuoteService.QUOTE_TYPE_TRIAL,
        GenerateQuoteService.QUOTE_TYPE_SAMPLE,
        GenerateQuoteService.QUOTE_TYPE_GOODWILL
    };

    @TestVisible
    private static Boolean notificationDisabled = false;

    /**
     * @description After-insert entry point for Quote.
     * @param quoteRecords Trigger.new rows.
     */
    public static void afterInsert(List<Quote> quoteRecords) {
        stageFromQuotes(quoteRecords);
    }

    /**
     * @description After-update entry point for Quote.
     * @param quoteRecords Trigger.new rows.
     * @param oldQuoteMap Trigger.oldMap.
     */
    public static void afterUpdate(List<Quote> quoteRecords, Map<Id, Quote> oldQuoteMap) {
        if (quoteRecords == null || quoteRecords.isEmpty()) {
            return;
        }

        List<Quote> changedQuotes = new List<Quote>();

        for (Quote quoteRecord : quoteRecords) {
            if (isExcludedFromForecastNotification(quoteRecord)) {
                continue;
            }

            Quote oldQuoteRecord = oldQuoteMap == null ? null : oldQuoteMap.get(quoteRecord.Id);
            if (hasForecastRelevantQuoteChange(quoteRecord, oldQuoteRecord)) {
                changedQuotes.add(quoteRecord);
            }
        }

        stageFromQuotes(changedQuotes);
    }

    /**
     * @description After-delete entry point for Quote.
     * @param quoteRecords Trigger.old rows.
     */
    public static void afterDelete(List<Quote> quoteRecords) {
        stageFromQuotes(quoteRecords);
    }

    /**
     * @description Stages notifications for Quote Ids whose Forecast_Eligible__c changed
     *              outside QuoteTriggerHandler, such as automated redesignation or UI updates.
     * @param quoteIds Quote Ids that changed.
     */
    public static void stageFromForecastEligibleQuoteIds(Set<Id> quoteIds) {
        stageFromQuoteIds(quoteIds);
    }

    private static void stageFromQuoteIds(Set<Id> quoteIds) {
        if (notificationDisabled || quoteIds == null || quoteIds.isEmpty()) {
            return;
        }

        Id salesConnectionRecordTypeId = resolveHcSalesRecordTypeId();
        if (salesConnectionRecordTypeId == null) {
            return;
        }

        Set<Id> opportunityIds = collectForecastOpportunityIds(
            quoteIds,
            salesConnectionRecordTypeId
        );
        QuoteForecastChangeNotificationService.markNotificationsPending(opportunityIds);
    }

    /**
     * @description After-insert entry point for Quote Line Item.
     * @param lineItems Trigger.new rows.
     */
    public static void afterInsertLineItems(List<QuoteLineItem> lineItems) {
        stageFromQuoteLineItems(lineItems);
    }

    /**
     * @description After-update entry point for Quote Line Item.
     * @param lineItems Trigger.new rows.
     * @param oldLineItemMap Trigger.oldMap.
     */
    public static void afterUpdateLineItems(
        List<QuoteLineItem> lineItems,
        Map<Id, QuoteLineItem> oldLineItemMap
    ) {
        if (lineItems == null || lineItems.isEmpty()) {
            return;
        }

        List<QuoteLineItem> changedLineItems = new List<QuoteLineItem>();

        for (QuoteLineItem lineItem : lineItems) {
            QuoteLineItem oldLineItem =
                oldLineItemMap == null ? null : oldLineItemMap.get(lineItem.Id);
            if (hasForecastRelevantLineItemChange(lineItem, oldLineItem)) {
                changedLineItems.add(lineItem);
            }
        }

        stageFromQuoteLineItems(changedLineItems);
    }

    /**
     * @description After-delete entry point for Quote Line Item.
     * @param lineItems Trigger.old rows.
     */
    public static void afterDeleteLineItems(List<QuoteLineItem> lineItems) {
        stageFromQuoteLineItems(lineItems);
    }

    /**
     * @description After-undelete entry point for Quote Line Item.
     * @param lineItems Trigger.new rows.
     */
    public static void afterUndeleteLineItems(List<QuoteLineItem> lineItems) {
        stageFromQuoteLineItems(lineItems);
    }

    @TestVisible
    static void setNotificationDisabled(Boolean disabled) {
        notificationDisabled = disabled == true;
    }

    private static void stageFromQuotes(List<Quote> quoteRecords) {
        if (notificationDisabled || quoteRecords == null || quoteRecords.isEmpty()) {
            return;
        }

        Id salesConnectionRecordTypeId = resolveHcSalesRecordTypeId();
        Set<Id> opportunityIds = new Set<Id>();

        for (Quote quoteRecord : quoteRecords) {
            if (
                quoteRecord.OpportunityId != null &&
                salesConnectionRecordTypeId != null &&
                quoteRecord.RecordTypeId == salesConnectionRecordTypeId &&
                !isExcludedFromForecastNotification(quoteRecord)
            ) {
                opportunityIds.add(quoteRecord.OpportunityId);
            }
        }

        QuoteForecastChangeNotificationService.markNotificationsPending(opportunityIds);
    }

    private static void stageFromQuoteLineItems(List<QuoteLineItem> lineItems) {
        if (notificationDisabled || lineItems == null || lineItems.isEmpty()) {
            return;
        }

        Set<Id> quoteIds = new Set<Id>();

        for (QuoteLineItem lineItem : lineItems) {
            if (lineItem.QuoteId != null) {
                quoteIds.add(lineItem.QuoteId);
            }
        }

        if (quoteIds.isEmpty()) {
            return;
        }

        Id salesConnectionRecordTypeId = resolveHcSalesRecordTypeId();
        if (salesConnectionRecordTypeId == null) {
            return;
        }

        Set<Id> opportunityIds = collectForecastOpportunityIds(
            quoteIds,
            salesConnectionRecordTypeId
        );
        QuoteForecastChangeNotificationService.markNotificationsPending(opportunityIds);
    }

    /**
     * @description Queries forecast-eligible quotes. Uses a list query instead of a
     *              SOQL for-loop so multiple bind variables do not throw tmpVar1.
     * @param quoteIds Quote Ids to evaluate.
     * @param salesConnectionRecordTypeId HC Sales Quote record type Id.
     * @return Opportunity Ids that should receive a forecast change notification.
     */
    private static Set<Id> collectForecastOpportunityIds(
        Set<Id> quoteIds,
        Id salesConnectionRecordTypeId
    ) {
        Set<Id> opportunityIds = new Set<Id>();
        if (quoteIds == null || quoteIds.isEmpty() || salesConnectionRecordTypeId == null) {
            return opportunityIds;
        }

        List<Quote> matchingQuotes = queryQuotesForForecast(quoteIds);

        for (Quote quoteRecord : matchingQuotes) {
            if (quoteRecord.RecordTypeId != salesConnectionRecordTypeId) {
                continue;
            }
            if (isExcludedFromForecastNotification(quoteRecord)) {
                continue;
            }
            opportunityIds.add(quoteRecord.OpportunityId);
        }

        return opportunityIds;
    }

    /**
     * @description Queries Quote rows with only fields the running user can access.
     *              QuoteType__c and IsForecastIneligible__c are omitted when hidden
     *              so QLI insert does not fail with No such column.
     * @param quoteIds Quote Ids to load.
     * @return Matching Quote rows.
     */
    private static List<Quote> queryQuotesForForecast(Set<Id> quoteIds) {
        List<String> selectedFields = new List<String>{ 'OpportunityId', 'RecordTypeId' };
        Map<String, Schema.SObjectField> quoteFields = Schema.SObjectType.Quote.fields.getMap();
        if (isQueryableField(quoteFields, 'QuoteType__c')) {
            selectedFields.add('QuoteType__c');
        }
        if (isQueryableField(quoteFields, 'IsForecastIneligible__c')) {
            selectedFields.add('IsForecastIneligible__c');
        }

        String soql =
            'SELECT ' +
            String.join(selectedFields, ', ') +
            ' FROM Quote WHERE Id IN :quoteIds AND OpportunityId != NULL';
        return Database.query(soql);
    }

    private static Boolean isQueryableField(
        Map<String, Schema.SObjectField> fields,
        String fieldApiName
    ) {
        Schema.SObjectField field = fields.get(fieldApiName);
        if (field == null) {
            return false;
        }
        Schema.DescribeFieldResult describeResult = field.getDescribe();
        return describeResult.isAccessible();
    }

    /**
     * @description Returns true when a quote should not drive forecast change notifications.
     * @param quoteRecord Quote row being evaluated.
     * @return True for Trial/Sample and forecast-ineligible quotes.
     */
    @TestVisible
    private static Boolean isExcludedFromForecastNotification(Quote quoteRecord) {
        if (quoteRecord == null) {
            return true;
        }

        if (quoteRecord.IsForecastIneligible__c == true) {
            return true;
        }

        return FORECAST_INELIGIBLE_QUOTE_TYPES.contains(quoteRecord.QuoteType__c);
    }

    private static Boolean hasForecastRelevantQuoteChange(Quote quoteRecord, Quote oldQuoteRecord) {
        if (quoteRecord == null || oldQuoteRecord == null) {
            return quoteRecord != null;
        }

        return hasForecastEligibleChange(quoteRecord, oldQuoteRecord)
            || quoteRecord.Status != oldQuoteRecord.Status
            || quoteRecord.LastModifiedDate__c != oldQuoteRecord.LastModifiedDate__c
            || quoteRecord.Quote_Total_Without_Freight__c != oldQuoteRecord.Quote_Total_Without_Freight__c
            || quoteRecord.TotalPrice != oldQuoteRecord.TotalPrice;
    }

    /**
     * @description Returns true when Quote.Forecast_Eligible__c changed.
     * @param quoteRecord Updated Quote row.
     * @param oldQuoteRecord Prior Quote row.
     * @return True when Forecast Eligible value changed.
     */
    @TestVisible
    private static Boolean hasForecastEligibleChange(Quote quoteRecord, Quote oldQuoteRecord) {
        if (quoteRecord == null || oldQuoteRecord == null) {
            return false;
        }

        return quoteRecord.Forecast_Eligible__c != oldQuoteRecord.Forecast_Eligible__c;
    }

    private static Boolean hasForecastRelevantLineItemChange(
        QuoteLineItem lineItem,
        QuoteLineItem oldLineItem
    ) {
        if (lineItem == null || oldLineItem == null) {
            return lineItem != null;
        }

        return lineItem.Quantity != oldLineItem.Quantity
            || lineItem.UnitPrice != oldLineItem.UnitPrice
            || lineItem.TotalPrice != oldLineItem.TotalPrice;
    }

    private static Id resolveHcSalesRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypesByDeveloperName =
            Schema.SObjectType.Quote.getRecordTypeInfosByDeveloperName();

        if (!recordTypesByDeveloperName.containsKey(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME)) {
            return null;
        }

        Schema.RecordTypeInfo recordTypeInfo =
            recordTypesByDeveloperName.get(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME);
        return recordTypeInfo.isAvailable() ? recordTypeInfo.getRecordTypeId() : null;
    }
}