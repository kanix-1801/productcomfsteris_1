/**
 * @author PWC Developer
 * @date 2026/07/08
 *
 * @group GC-3124 Refresh Quote
 *
 * @description Persists Refresh Quote integration payloads to Quote and QuoteLineItem records.
 */
public with sharing class RefreshQuoteSyncService {
    /**
     * @description Upserts Quote headers and lines from an integration refresh response.
     * @param opportunityId Opportunity Id.
     * @param integrationQuotes Parsed integration quote rows.
     * @return Salesforce Quote Ids that were inserted or updated.
     */
    public static Set<Id> syncIntegrationQuotes(
        Id opportunityId,
        List<GenerateQuoteController.QuoteWrapper> integrationQuotes
    ) {
        Set<Id> syncedQuoteIds = new Set<Id>();

        if (opportunityId == null || integrationQuotes == null || integrationQuotes.isEmpty()) {
            return syncedQuoteIds;
        }

        Opportunity opportunityRecord = OpportunitySelector.selectById(opportunityId);
        if (opportunityRecord == null) {
            throw new GenerateQuoteException('Opportunity record was not found.');
        }

        List<Quote> existingQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(opportunityId);
        Map<Id, Quote> oldQuoteMapById = buildOldQuoteMap(existingQuotes);
        List<PricebookEntry> pricebookEntries = PricebookEntrySelector.selectActiveByPricebookId(
            opportunityRecord.Pricebook2Id,
            50,
            opportunityRecord.CurrencyIsoCode
        );

        Savepoint savepointValue = Database.setSavepoint();
        TriggerHandler.bypass('QuoteTriggerHandler');
        TriggerHandler.bypass('QuoteLineItemTriggerHandler');
        OpportunityLineItemService.setRecalculationDisabled(true);

        try {
            List<QuoteSyncContext> syncContexts = new List<QuoteSyncContext>();
            List<Quote> quotesToInsert = new List<Quote>();
            List<Quote> quotesToUpdate = new List<Quote>();

            demoteOpenQuotesToDraft(existingQuotes, quotesToUpdate);

            for (GenerateQuoteController.QuoteWrapper integrationQuote : integrationQuotes) {
                QuoteSyncContext syncContext = new QuoteSyncContext();
                syncContext.quoteRecord = resolveQuoteRecord(
                    integrationQuote,
                    existingQuotes,
                    opportunityRecord
                );
                applyHeaderFields(
                    syncContext.quoteRecord,
                    integrationQuote,
                    opportunityRecord
                );
                syncContext.integrationLines = collectIntegrationLines(
                    integrationQuote.productSubgroupSummary
                );

                if (syncContext.quoteRecord.Id == null) {
                    quotesToInsert.add(syncContext.quoteRecord);
                } else if (!quotesToUpdate.contains(syncContext.quoteRecord)) {
                    quotesToUpdate.add(syncContext.quoteRecord);
                }

                syncContexts.add(syncContext);
            }

            QuoteService.applyStatusRulesBeforeSave(quotesToInsert, null);
            QuoteService.applyStatusRulesBeforeSave(quotesToUpdate, oldQuoteMapById);

            insertQuotes(quotesToInsert);
            updateQuotes(quotesToUpdate);

            for (QuoteSyncContext syncContext : syncContexts) {
                syncQuoteLines(
                    syncContext.quoteRecord,
                    syncContext.integrationLines,
                    pricebookEntries
                );
                syncedQuoteIds.add(syncContext.quoteRecord.Id);
            }

            QuoteService.syncQuoteTotalWithoutFreightFromLines(syncedQuoteIds);
            runPostSyncAutomation(opportunityId);

            return syncedQuoteIds;
        } catch (Exception exceptionValue) {
            Database.rollback(savepointValue);

            if (exceptionValue instanceof GenerateQuoteException) {
                throw exceptionValue;
            }

            String syncErrorDetail = exceptionValue.getMessage();
            throw new GenerateQuoteException(
                String.isNotBlank(syncErrorDetail)
                    ? 'Unable to sync refreshed quote data. ' + syncErrorDetail
                    : 'Unable to sync refreshed quote data.'
            );
        } finally {
            TriggerHandler.clearBypass('QuoteTriggerHandler');
            TriggerHandler.clearBypass('QuoteLineItemTriggerHandler');
            OpportunityLineItemService.setRecalculationDisabled(false);
        }
    }

    /**
     * @description Build Quote record instance.
     * @param existingQuotes List of Quotes.
     * @param integrationQuotes Parsed integration quote rows.
     * @return Salesforce Quote Record Instance.
     */

    private static Quote resolveQuoteRecord(
        GenerateQuoteController.QuoteWrapper integrationQuote,
        List<Quote> existingQuotes,
        Opportunity opportunityRecord
    ) {
        if (integrationQuote.id != null) {
            for (Quote existingQuote : existingQuotes) {
                if (existingQuote.Id == integrationQuote.id) {
                    return existingQuote;
                }
            }
        }

        String salesConnectionQuoteId = deriveSalesConnectionQuoteId(integrationQuote);
        if (String.isNotBlank(salesConnectionQuoteId)) {
            for (Quote existingQuote : existingQuotes) {
                if (salesConnectionQuoteId.equalsIgnoreCase(existingQuote.SalesConnectionQuoteID__c)) {
                    return existingQuote;
                }

                if (salesConnectionQuoteId.equalsIgnoreCase(existingQuote.Source_System_ID__c)) {
                    return existingQuote;
                }
            }
        }

        if (String.isNotBlank(integrationQuote.quoteNumber)) {
            for (Quote existingQuote : existingQuotes) {
                if (integrationQuote.quoteNumber.equalsIgnoreCase(existingQuote.QuoteNumber__c)) {
                    return existingQuote;
                }
            }
        }

        if (existingQuotes.size() == 1) {
            return existingQuotes[0];
        }

        if (String.isNotBlank(integrationQuote.quoteName)) {
            for (Quote existingQuote : existingQuotes) {
                if (integrationQuote.quoteName.equalsIgnoreCase(existingQuote.Name)) {
                    return existingQuote;
                }
            }
        }

        return buildQuoteForInsert(opportunityRecord, integrationQuote);
    }
    
    /**
     * @description Build Quote record instance.
     * @param opportunityRecord Opportunity Record.
     * @param integrationQuotes Parsed integration quote rows.
     * @return Salesforce Quote Record Instance.
     */

    private static Quote buildQuoteForInsert(
        Opportunity opportunityRecord,
        GenerateQuoteController.QuoteWrapper integrationQuote
    ) {
        if (opportunityRecord.Pricebook2Id == null) {
            throw new GenerateQuoteException(
                'Please add a Price Book to the Opportunity before syncing refreshed quotes.'
            );
        }

        Quote quoteRecord = new Quote();
        quoteRecord.OpportunityId = opportunityRecord.Id;
        quoteRecord.Pricebook2Id = opportunityRecord.Pricebook2Id;
        quoteRecord.Name = String.isNotBlank(integrationQuote.quoteName)
            ? integrationQuote.quoteName
            : 'Quote - ' + opportunityRecord.Name;
        quoteRecord.ExpirationDate = integrationQuote.expirationDate == null
            ? Date.today().addDays(30)
            : integrationQuote.expirationDate;
        quoteRecord.Status = GenerateQuoteService.QUOTE_STATUS_DRAFT;

        Id quoteRecordTypeId = GenerateQuoteService.resolveHcSalesQuoteRecordTypeId();
        if (quoteRecordTypeId != null) {
            quoteRecord.RecordTypeId = quoteRecordTypeId;
        }

        GenerateQuoteService.applyQuoteCurrencyFromOpportunity(quoteRecord, opportunityRecord);
        return quoteRecord;
    }

    /**
     * @description Maps integration quote header values to a Salesforce Quote*record.
     * @param quoteRecord Quote Record.
     * @param integrationQuotes Parsed integration quote rows.
     */

    private static void applyHeaderFields(
        Quote quoteRecord,
        GenerateQuoteController.QuoteWrapper integrationQuote,
        Opportunity opportunityRecord
    ) {
        if (String.isNotBlank(integrationQuote.quoteName)) {
            quoteRecord.Name = integrationQuote.quoteName;
        }

        quoteRecord.Description = integrationQuote.description;
        quoteRecord.Status = resolveRefreshQuoteStatus(integrationQuote.status);
        quoteRecord.Approval_Status__c =
            SalesConnectionQuoteMockService.resolveApprovalStatus(integrationQuote.approvalStatus);

        if (integrationQuote.expirationDate != null) {
            quoteRecord.ExpirationDate = integrationQuote.expirationDate;
        }

        if (String.isNotBlank(integrationQuote.quoteNumber)) {
            quoteRecord.QuoteNumber__c = GenerateQuoteService.normalizeQuoteNumberForStorage(
                integrationQuote.quoteNumber
            );
        }

        String salesConnectionQuoteId = deriveSalesConnectionQuoteId(integrationQuote);
        salesConnectionQuoteId = GenerateQuoteService.normalizeSalesConnectionQuoteIdForStorage(
            salesConnectionQuoteId
        );
        if (String.isNotBlank(salesConnectionQuoteId)) {
            quoteRecord.SalesConnectionQuoteID__c = salesConnectionQuoteId;
        }

        QuoteService.applyOpportunityForecastConfidenceIfBlank(quoteRecord, opportunityRecord);
    }

     /**
     * @description Resolves the Sales Connection quote identifier from an integration payload.
     * @param integrationQuote Parsed integration quote row.
     * @return Sales Connection quote id when present.
     */

    private static String deriveSalesConnectionQuoteId(
        GenerateQuoteController.QuoteWrapper integrationQuote
    ) {
        return integrationQuote.salesConnectionQuoteId;
    }

    /**
     * @description Flattens all quote lines from the product subgroup hierarchy into a single list for processing.
     * @param subgroupSummary Product subgroup summaries from integration response.
     * @return List<GenerateQuoteController.QuoteLineDetailWrapper> Collection of quote linedetail wrappers.
     */

    private static List<GenerateQuoteController.QuoteLineDetailWrapper> collectIntegrationLines(
        List<GenerateQuoteController.ProductSubgroupSummaryWrapper> subgroupSummary
    ) {
        List<GenerateQuoteController.QuoteLineDetailWrapper> integrationLines =
            new List<GenerateQuoteController.QuoteLineDetailWrapper>();

        if (subgroupSummary == null) {
            return integrationLines;
        }

        for (GenerateQuoteController.ProductSubgroupSummaryWrapper subgroup : subgroupSummary) {
            if (subgroup == null || subgroup.quoteLines == null) {
                continue;
            }

            integrationLines.addAll(subgroup.quoteLines);
        }

        return integrationLines;
    }

    /**
     * @description Synchronizes Quote Line Items for a Quote by creating or updating records based on integration line data and exi*ting line mappings
     * @param quoteRecord Record Target Salesforce Quote.
     * @param integrationLines Integration quote lines.
     * @param pricebookEntries Available Pricebook Entries.
     */

    private static void syncQuoteLines(
        Quote quoteRecord,
        List<GenerateQuoteController.QuoteLineDetailWrapper> integrationLines,
        List<PricebookEntry> pricebookEntries
    ) {
        if (quoteRecord == null || quoteRecord.Id == null || integrationLines == null || integrationLines.isEmpty()) {
            return;
        }

        Map<String, QuoteLineItem> existingLinesByExternalId = indexExistingLines(quoteRecord.QuoteLineItems);
        String lineIdPrefix = String.valueOf(quoteRecord.Id);
        List<QuoteLineItem> linesToInsert = new List<QuoteLineItem>();
        List<QuoteLineItem> linesToUpdate = new List<QuoteLineItem>();
        Integer lineIndex = 0;

        for (GenerateQuoteController.QuoteLineDetailWrapper integrationLine : integrationLines) {
            if (integrationLine == null || String.isBlank(integrationLine.quoteLineId)) {
                continue;
            }

            String externalLineId = SalesConnectionQuoteMockService.buildUniqueQuoteLineId(
                integrationLine.quoteLineId,
                lineIdPrefix
            );
            QuoteLineItem lineRecord = findExistingLine(
                existingLinesByExternalId,
                externalLineId,
                integrationLine.quoteLineId
            );

            if (lineRecord == null) {
                SalesConnectionQuoteMockService.PricebookEntryResolution pricebookEntryResolution =
                    SalesConnectionQuoteMockService.resolvePricebookEntryResolution(
                        integrationLine.productFAMCode,
                        integrationLine.productName,
                        lineIndex,
                        pricebookEntries
                    );

                if (pricebookEntryResolution.pricebookEntryId == null) {
                    lineIndex++;
                    continue;
                }

                lineRecord = new QuoteLineItem();
                lineRecord.QuoteId = quoteRecord.Id;
                lineRecord.PricebookEntryId = pricebookEntryResolution.pricebookEntryId;
                lineRecord.SalesConnectionQuoteLineID__c = externalLineId;
                linesToInsert.add(lineRecord);
            } else if (String.isBlank(lineRecord.SalesConnectionQuoteLineID__c)) {
                lineRecord.SalesConnectionQuoteLineID__c = externalLineId;
                linesToUpdate.add(lineRecord);
            } else if (!linesToUpdate.contains(lineRecord)) {
                linesToUpdate.add(lineRecord);
            }

            SalesConnectionQuoteMockService.PricebookEntryResolution linePricebookResolution =
                SalesConnectionQuoteMockService.resolvePricebookEntryResolution(
                    integrationLine.productFAMCode,
                    integrationLine.productName,
                    lineIndex,
                    pricebookEntries
                );
            applyLineFields(lineRecord, integrationLine, pricebookEntries, linePricebookResolution);
            lineIndex++;
        }

        List<QuoteLineItem> linesNeedingPsam = new List<QuoteLineItem>();
        linesNeedingPsam.addAll(linesToInsert);
        linesNeedingPsam.addAll(linesToUpdate);
        PsamQuoteLineGroupingService.applyPsamSubgroupDetailNames(linesNeedingPsam);

        insertQuoteLines(linesToInsert);
        updateQuoteLines(linesToUpdate);
    }

    /**
     * @description Creates a lookup map of existing Quote Line Items
     * @param existingLines Existing Quote Line Items.
     * @return Map<String, QuoteLineItem> Map of external line id to Quote Line Item.
     */
   

    private static Map<String, QuoteLineItem> indexExistingLines(List<QuoteLineItem> existingLines) {
        Map<String, QuoteLineItem> existingLinesByExternalId = new Map<String, QuoteLineItem>();

        if (existingLines == null) {
            return existingLinesByExternalId;
        }

        for (QuoteLineItem existingLine : existingLines) {
            if (String.isBlank(existingLine.SalesConnectionQuoteLineID__c)) {
                continue;
            }

            existingLinesByExternalId.put(
                existingLine.SalesConnectionQuoteLineID__c.toLowerCase(),
                existingLine
            );
        }

        return existingLinesByExternalId;
    }

    /**
     * @description Finds an existing Quote Line Item using the generated external id.
     * @param externalLineId Generated unique external line id.
     * @param templateLineId Original integration line id
     * @return Matching Quote Line Item or null.
     */
   

    private static QuoteLineItem findExistingLine(
        Map<String, QuoteLineItem> existingLinesByExternalId,
        String externalLineId,
        String templateLineId
    ) {
        QuoteLineItem existingLine = existingLinesByExternalId.get(externalLineId.toLowerCase());
        if (existingLine != null) {
            return existingLine;
        }

        String suffix = '-' + templateLineId;
        for (QuoteLineItem candidateLine : existingLinesByExternalId.values()) {
            if (candidateLine.SalesConnectionQuoteLineID__c.endsWithIgnoreCase(suffix)) {
                return candidateLine;
            }
        }

        return null;
    }

    /**
     * @description Maps integration line values to a Salesforce Quote Line Item
     * @param lineRecord Quote Line Item to populate.
     * @param integrationLine Integration quote line payload.
     */

    private static void applyLineFields(
        QuoteLineItem lineRecord,
        GenerateQuoteController.QuoteLineDetailWrapper integrationLine,
        List<PricebookEntry> pricebookEntries,
        SalesConnectionQuoteMockService.PricebookEntryResolution pricebookEntryResolution
    ) {
        lineRecord.Description = SalesConnectionQuoteMockService.resolveQuoteLineDescription(
            integrationLine.productName,
            pricebookEntryResolution,
            pricebookEntries
        );
        lineRecord.Product_FAM_Code__c = integrationLine.productFAMCode;
        lineRecord.Product_Subgroup_Detail_Name__c = integrationLine.productSubgroupDetailName;
        lineRecord.TerritoryID__c = integrationLine.territoryId;
        lineRecord.SalesCategory__c = QuoteLineSalesCategoryService.resolveSalesCategoryFromIntegration(
            integrationLine.tasSalesCategory,
            integrationLine.salesCategoryDescription
        );
        lineRecord.UOM__c = integrationLine.uom;
        lineRecord.Quantity = normalizeQuantity(integrationLine.quantity);
        lineRecord.UnitPrice = integrationLine.unitPrice == null ? 0 : integrationLine.unitPrice;
        lineRecord.Total_Unit_Price__c = integrationLine.lineTotal == null
            ? lineRecord.Quantity * lineRecord.UnitPrice
            : integrationLine.lineTotal;
    }

    /**
     * @description Ensures a valid quantity value is assigned to a Quote Line Item.
     * @param quantity quantity Integration quantity value.
     * @return Normalized quantity
     */

    private static Decimal normalizeQuantity(Decimal quantity) {
        if (quantity == null || quantity <= 0) {
            return 1;
        }

        return quantity;
    }

    /**
     * @description Refresh Quote should move every Open quote on the Opportunity to Draft
     *              before persisting integration updates.
     * @param existingQuotes Current Opportunity quotes.
     * @param quotesToUpdate Mutable list receiving Quote rows to update.
     */
    private static void demoteOpenQuotesToDraft(
        List<Quote> existingQuotes,
        List<Quote> quotesToUpdate
    ) {
        if (existingQuotes == null || existingQuotes.isEmpty()) {
            return;
        }

        for (Quote quoteRecord : existingQuotes) {
            if (!QuoteService.isForecastableStatus(quoteRecord.Status)) {
                continue;
            }

            quoteRecord.Status = GenerateQuoteService.QUOTE_STATUS_DRAFT;

            if (quoteRecord.Id != null && !quotesToUpdate.contains(quoteRecord)) {
                quotesToUpdate.add(quoteRecord);
            }
        }
    }

    /**
     * @description Maps integration status to Salesforce status for Refresh Quote.
     *              Open quotes are stored as Draft per business rules.
     * @param integrationStatus Status value from the integration payload.
     * @return Salesforce Quote Status picklist value.
     */
    private static String resolveRefreshQuoteStatus(String integrationStatus) {
        String resolvedStatus = SalesConnectionQuoteMockService.resolveQuoteStatus(integrationStatus);

        if (QuoteService.isForecastableStatus(resolvedStatus)) {
            return GenerateQuoteService.QUOTE_STATUS_DRAFT;
        }

        return resolvedStatus;
    }

    private static Map<Id, Quote> buildOldQuoteMap(List<Quote> existingQuotes) {
        Map<Id, Quote> oldQuoteMapById = new Map<Id, Quote>();

        if (existingQuotes == null) {
            return oldQuoteMapById;
        }

        for (Quote quoteRecord : existingQuotes) {
            if (quoteRecord.Id != null) {
                oldQuoteMapById.put(quoteRecord.Id, quoteRecord.clone(true, true, true, true));
            }
        }

        return oldQuoteMapById;
    }

    private static void runPostSyncAutomation(Id opportunityId) {
        if (opportunityId == null) {
            return;
        }

        Set<Id> opportunityIds = new Set<Id>{ opportunityId };
        OpportunityLineItemService.recalculateFromOpportunityIds(opportunityIds);
        QuoteService.synchronizeForecastEligibleDesignation(opportunityIds);
    }

    private static void insertQuotes(List<Quote> quoteRecords) {
        persistRecords(quoteRecords, 'Quote', true);
    }

    private static void updateQuotes(List<Quote> quoteRecords) {
        persistRecords(quoteRecords, 'Quote', false);
    }

    private static void insertQuoteLines(List<QuoteLineItem> quoteLineItems) {
        persistRecords(quoteLineItems, 'QuoteLineItem', true);
    }

    private static void updateQuoteLines(List<QuoteLineItem> quoteLineItems) {
        persistRecords(quoteLineItems, 'QuoteLineItem', false);
    }

/* @description Performs DML operations with CRUD validation and centralized
 *              error handling for Quote and Quote Line Item records.
 * @param records Records to persist.
 * @param objectName Target object name.
 * @param isInsert True for insert, false for update.
 */

    private static void persistRecords(List<SObject> records, String objectName, Boolean isInsert) {
        if (records == null || records.isEmpty()) {
            return;
        }

        if (isInsert && !isCreateable(objectName)) {
            throw new GenerateQuoteException('Current user cannot create ' + objectName + ' records.');
        }

        if (!isInsert && !isUpdateable(objectName)) {
            throw new GenerateQuoteException('Current user cannot update ' + objectName + ' records.');
        }

        List<SObject> recordsToPersist = records;
        Database.SaveResult[] saveResults = isInsert
            ? Database.insert(recordsToPersist, false)
            : Database.update(recordsToPersist, false);

        for (Database.SaveResult saveResult : saveResults) {
            if (!saveResult.isSuccess()) {
                throw new GenerateQuoteException(
                    objectName + ' ' + (isInsert ? 'insert' : 'update') + ' failed: ' +
                    saveResult.getErrors()[0].getMessage()
                );
            }
        }
    }

/**
 * @description Checks whether the running user has create access
 *              to the specified object.
 * @param objectName Salesforce object name.
 * @return True when create permission exists.
 */

    private static Boolean isCreateable(String objectName) {
        if (objectName == 'Quote') {
            return Schema.sObjectType.Quote.isCreateable();
        }

        if (objectName == 'QuoteLineItem') {
            return Schema.sObjectType.QuoteLineItem.isCreateable();
        }

        return false;
    }

/**
 * @description Checks whether the running user has update access
 *              to the specified object.
 * @param objectName Salesforce object name.
 * @return True when update permission exists.
 */

    private static Boolean isUpdateable(String objectName) {
        if (objectName == 'Quote') {
            return Schema.sObjectType.Quote.isUpdateable();
        }

        if (objectName == 'QuoteLineItem') {
            return Schema.sObjectType.QuoteLineItem.isUpdateable();
        }

        return false;
    }

/**
* @description Wrapper class used during quote synchronization to maintainthe Quote record
               and its related integration line data.
*/

    private class QuoteSyncContext {
        public Quote quoteRecord;
        public List<GenerateQuoteController.QuoteLineDetailWrapper> integrationLines;
    }
}