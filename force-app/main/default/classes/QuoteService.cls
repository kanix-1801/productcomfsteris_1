/**
 * @author Himanshu Chaurasia
 * @date 2026/07/28
 *
 * @group Quote
 *
 * @description GC-2659 Quote service for QuoteHandler
 */
public with sharing class QuoteService {
    public static final String SCENARIO = 'Quote Forecast Eligible';
    public static final String LOGGER_TAG = 'Quote';
    public static final String FORECAST_ELIGIBLE_STATUS = QuoteSelector.OPEN_STATUS_VALUE;

    private static final String STATUS_WAITING_FOR_APPROVAL = 'Waiting for Approval';
    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_REJECTED = 'Rejected';
    private static final String LINE_TYPE_PRODUCT_SERVICED = 'Product Serviced';
    private static final String LINE_TYPE_CATEGORY_CODE = 'Category Code';
    private static final String LINE_TYPE_SERVICE_CODE = 'Service Code';
    private static final String LINE_TYPE_SPECIAL_PRICING = 'Special Pricing';
    private static final String SERVICE_CODE_TYPE_DISINFECTION = 'Disinfection';
    private static final String WOLI_RECORD_TYPE_REPAIR_CODE = 'RepairCode';
    private static final String LOGGER_TAG_APPROVE_REJECT = 'Quote Approve Reject';
    private static final Set<String> ESTIMATE_PRICE_LINE_TYPES = new Set<String>{
        LINE_TYPE_SPECIAL_PRICING,
        LINE_TYPE_CATEGORY_CODE,
        LINE_TYPE_SERVICE_CODE
    };
    private static final Set<String> CHILD_STATUS_LINE_TYPES = new Set<String>{
        LINE_TYPE_CATEGORY_CODE,
        LINE_TYPE_SERVICE_CODE,
        LINE_TYPE_SPECIAL_PRICING
    };


    private static final String CLASS_NAME = 'QuoteService';
    private static final Set<String> QUOTE_FORECAST_CONFIDENCE_VALUES = new Set<String>{
        'Pipeline',
        'Budget',
        'Upside',
        'Make-It'
    };

    private static Id hcSalesRecordTypeId;

    @TestVisible
    private static Boolean automationDisabled = false;

    /**
     * @description Temporarily disables automation for manual Forecast Eligible updates.
     * @return True when automation is disabled.
     */
    public static Boolean isAutomationDisabled() {
        return automationDisabled;
    }

    /**
     * @description Test hook to enable or disable Quote trigger automation.
     * @param disabled True to bypass automation during tests.
     */
    @TestVisible
    static void setAutomationDisabled(Boolean disabled) {
        automationDisabled = disabled == true;
    }

    /**
     * @description Copies Opportunity Forecast Confidence to HC_Sales Quote rows on insert.
     * @param quoteRecords Trigger.new Quote rows.
     */
    public static void populateQuoteForecastConfidenceOnInsert(List<Quote> quoteRecords) {
        if (quoteRecords == null || quoteRecords.isEmpty() || isAutomationDisabled()) {
            return;
        }

        Set<Id> opportunityIds = new Set<Id>();

        for (Quote quoteRecord : quoteRecords) {
            if (isSalesConnectionQuote(quoteRecord) && quoteRecord.OpportunityId != null) {
                opportunityIds.add(quoteRecord.OpportunityId);
            }
        }

        if (opportunityIds.isEmpty()) {
            return;
        }

        Map<Id, Opportunity> opportunitiesById =
            OpportunitySelector.selectForecastConfidenceByIds(opportunityIds);

        for (Quote quoteRecord : quoteRecords) {
            if (!isSalesConnectionQuote(quoteRecord) || quoteRecord.OpportunityId == null) {
                continue;
            }

            if (shouldSkipOpportunityForecastConfidenceOnQuote(quoteRecord)) {
                continue;
            }

            Opportunity opportunityRecord = opportunitiesById.get(quoteRecord.OpportunityId);
            if (opportunityRecord == null) {
                continue;
            }

            quoteRecord.QuoteForecastConfidence__c = mapOpportunityForecastConfidenceToQuote(
                opportunityRecord.ForecastConfidenceLevel__c
            );
        }
    }

    @TestVisible
    private static Boolean shouldSkipOpportunityForecastConfidenceOnQuote(Quote quoteRecord) {
        if (quoteRecord == null) {
            return true;
        }

        if (quoteRecord.IsForecastIneligible__c == true) {
            return true;
        }

        String quoteType = quoteRecord.QuoteType__c;
        if (String.isBlank(quoteType)) {
            return false;
        }

        return GenerateQuoteService.QUOTE_TYPE_TRIAL.equals(quoteType) ||
            GenerateQuoteService.QUOTE_TYPE_SAMPLE.equals(quoteType) ||
            GenerateQuoteService.QUOTE_TYPE_GOODWILL.equals(quoteType);
    }

    /**
     * @description Maps Opportunity Forecast Confidence values to Quote picklist values.
     * @param opportunityForecastConfidence Opportunity ForecastConfidenceLevel__c value.
     * @return Matching QuoteForecastConfidence__c value, or null when not applicable.
     */
    @TestVisible
    public static String mapOpportunityForecastConfidenceToQuote(String opportunityForecastConfidence) {
        if (String.isBlank(opportunityForecastConfidence)) {
            return null;
        }

        if ('Make It'.equalsIgnoreCase(opportunityForecastConfidence)) {
            return 'Make-It';
        }

        for (String quoteForecastConfidenceValue : QUOTE_FORECAST_CONFIDENCE_VALUES) {
            if (quoteForecastConfidenceValue.equalsIgnoreCase(opportunityForecastConfidence)) {
                return quoteForecastConfidenceValue;
            }
        }

        return null;
    }

    /**
     * @description Sets Quote Forecast Confidence from the Opportunity when the quote field is blank.
     * @param quoteRecord Quote row being saved.
     * @param opportunityRecord Parent Opportunity row.
     */
    public static void applyOpportunityForecastConfidenceIfBlank(
        Quote quoteRecord,
        Opportunity opportunityRecord
    ) {
        if (quoteRecord == null || opportunityRecord == null || isAutomationDisabled()) {
            return;
        }

        if (shouldSkipOpportunityForecastConfidenceOnQuote(quoteRecord)) {
            return;
        }

        if (!isSalesConnectionQuote(quoteRecord)) {
            return;
        }

        if (String.isNotBlank(quoteRecord.QuoteForecastConfidence__c)) {
            return;
        }

        String mappedValue = mapOpportunityForecastConfidenceToQuote(
            opportunityRecord.ForecastConfidenceLevel__c
        );

        if (String.isNotBlank(mappedValue)) {
            quoteRecord.QuoteForecastConfidence__c = mappedValue;
        }
    }

    /**
     * @description Clears Forecast Eligible on non-forecastable quotes before save when not
     *              already true. True values are preserved unless manually cleared.
     *              On insert, only the first eligible Open HC_Sales quote is marked Forecast Eligible
     *              when the Opportunity has no existing Forecast Eligible quote (AC1/AC3).
     * @param quoteRecords Trigger.new Quote rows.
     * @param oldQuoteMap Trigger.oldMap, null on insert.
     */
    public static void applyStatusRulesBeforeSave(
        List<Quote> quoteRecords,
        Map<Id, Quote> oldQuoteMap
    ) {
        if (quoteRecords == null || quoteRecords.isEmpty() || isAutomationDisabled()) {
            return;
        }

        try {
            Logger.setScenario(SCENARIO);
            Logger.debug(CLASS_NAME + '.applyStatusRulesBeforeSave: started').addTag(LOGGER_TAG);

            if (oldQuoteMap == null) {
                applyInsertForecastEligibleRules(quoteRecords);
            } else {
                applyUpdateForecastEligibleRules(quoteRecords, oldQuoteMap);
            }

            Logger.debug(CLASS_NAME + '.applyStatusRulesBeforeSave: completed').addTag(LOGGER_TAG);
        } catch (Exception exceptionValue) {
            Logger.error(CLASS_NAME + '.applyStatusRulesBeforeSave', exceptionValue).addTag(LOGGER_TAG);
            throw exceptionValue;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Applies Forecast Eligible rules for Quote insert.
     * @param quoteRecords Trigger.new Quote rows.
     */
    @TestVisible
    private static void applyInsertForecastEligibleRules(List<Quote> quoteRecords) {
        Map<Id, List<Quote>> insertCandidatesByOpportunityId = new Map<Id, List<Quote>>();
        Set<Id> opportunityIds = new Set<Id>();

        for (Quote quoteRecord : quoteRecords) {
            if (!isSalesConnectionQuote(quoteRecord) || quoteRecord.OpportunityId == null) {
                continue;
            }

            if (quoteRecord.IsForecastIneligible__c == true) {
                quoteRecord.Forecast_Eligible__c = false;
                continue;
            }

            quoteRecord.Forecast_Eligible__c = false;

            if (isForecastableStatus(quoteRecord.Status)) {
                opportunityIds.add(quoteRecord.OpportunityId);
                addQuoteToOpportunityGroup(insertCandidatesByOpportunityId, quoteRecord);
            }
        }

        if (insertCandidatesByOpportunityId.isEmpty()) {
            return;
        }

        Set<Id> opportunityIdsWithForecastEligible =
            QuoteSelector.selectOpportunityIdsWithOpenForecastEligibleQuotes(opportunityIds);

        for (Id opportunityId : insertCandidatesByOpportunityId.keySet()) {
            if (opportunityIdsWithForecastEligible.contains(opportunityId)) {
                continue;
            }

            Quote designatedQuote = selectEarliestEligibleQuote(
                insertCandidatesByOpportunityId.get(opportunityId)
            );
            if (designatedQuote != null) {
                designatedQuote.Forecast_Eligible__c = true;
            }
        }
    }

    /**
     * @description Applies Forecast Eligible rules for Quote update.
     * @param quoteRecords Trigger.new Quote rows.
     * @param oldQuoteMap Trigger.oldMap.
     */
    @TestVisible
    private static void applyUpdateForecastEligibleRules(
        List<Quote> quoteRecords,
        Map<Id, Quote> oldQuoteMap
    ) {
        Map<Id, List<Quote>> openTransitionCandidatesByOpportunityId = new Map<Id, List<Quote>>();
        Set<Id> openTransitionOpportunityIds = new Set<Id>();

        for (Quote quoteRecord : quoteRecords) {
            if (!isSalesConnectionQuote(quoteRecord)) {
                continue;
            }

            Quote oldQuoteRecord = oldQuoteMap.get(quoteRecord.Id);

            if (quoteRecord.IsForecastIneligible__c == true) {
                quoteRecord.Forecast_Eligible__c = false;
                continue;
            }

            if (
                oldQuoteRecord != null &&
                !isForecastableStatus(oldQuoteRecord.Status) &&
                isForecastableStatus(quoteRecord.Status)
            ) {
                quoteRecord.Forecast_Eligible__c = false;
                openTransitionOpportunityIds.add(quoteRecord.OpportunityId);
                addQuoteToOpportunityGroup(openTransitionCandidatesByOpportunityId, quoteRecord);
                continue;
            }

            if (shouldClearForecastEligibleOnOpenStatusChange(quoteRecord, oldQuoteMap)) {
                quoteRecord.Forecast_Eligible__c = false;
                continue;
            }

            if (
                !isForecastableStatus(quoteRecord.Status) &&
                !shouldPreserveForecastEligible(quoteRecord, oldQuoteMap)
            ) {
                quoteRecord.Forecast_Eligible__c = false;
            }
        }

        if (openTransitionCandidatesByOpportunityId.isEmpty()) {
            return;
        }

        Set<Id> opportunityIdsWithForecastEligible =
            QuoteSelector.selectOpportunityIdsWithOpenForecastEligibleQuotes(openTransitionOpportunityIds);

        for (Id opportunityId : openTransitionCandidatesByOpportunityId.keySet()) {
            if (opportunityIdsWithForecastEligible.contains(opportunityId)) {
                continue;
            }

            Quote designatedQuote = selectEarliestEligibleQuote(
                openTransitionCandidatesByOpportunityId.get(opportunityId)
            );
            if (designatedQuote != null) {
                designatedQuote.Forecast_Eligible__c = true;
            }
        }
    }

    /**
     * @description Re-evaluates Forecast Eligible designation for affected Opportunities on
     *              update or delete when driving fields change. Does not run for manual
     *              Forecast_Eligible__c updates from Update Forecast Eligible Quotes.
     * @param opportunityIds Opportunity Ids to process.
     */
    @TestVisible
    public static void synchronizeForecastEligibleDesignation(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty() || isAutomationDisabled()) {
            return;
        }

        try {
            Logger.setScenario(SCENARIO);
            Logger.info(CLASS_NAME + '.synchronizeForecastEligibleDesignation: started')
                .addTag(LOGGER_TAG);

            List<Quote> opportunityQuotes =
                QuoteSelector.selectSalesConnectionQuotesForForecastEligibleByOpportunityIds(opportunityIds);
            Map<Id, List<Quote>> quotesByOpportunityId = groupQuotesByOpportunityId(opportunityQuotes);
            Map<Id, Quote> quotesToUpdateById = new Map<Id, Quote>();

            for (Id opportunityId : opportunityIds) {
                processOpportunityQuotes(
                    quotesByOpportunityId.get(opportunityId),
                    quotesToUpdateById
                );
            }

            if (!quotesToUpdateById.isEmpty()) {
                updateQuotesWithBypass(quotesToUpdateById.values());
            }

            Logger.info(CLASS_NAME + '.synchronizeForecastEligibleDesignation: completed')
                .addTag(LOGGER_TAG);
        } catch (Exception exceptionValue) {
            Logger.error(CLASS_NAME + '.synchronizeForecastEligibleDesignation', exceptionValue)
                .addTag(LOGGER_TAG);
            throw exceptionValue;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description After-insert orchestration for Quote trigger events.
     *              Forecast Eligible designation for the first eligible Open quote runs in before insert.
     * @param quoteRecords Trigger.new rows.
     */
    public static void handleAfterInsert(List<Quote> quoteRecords) {
        QuoteForecastChangeNotificationHandler.afterInsert(quoteRecords);
        Set<Id> opportunityIds = collectOpportunityIds(quoteRecords);
        OppForecastConfPropagateService.syncBannerStateForOpportunityIds(opportunityIds);
        OppClosedLostQuoteService.syncBannerStateForOpportunityIds(opportunityIds);
        OppEppConversionQuoteService.syncBannerStateForOpportunityIds(opportunityIds);
    }

    /**
     * @description After-update orchestration for Quote trigger events.
     * @param quoteRecords Trigger.new rows.
     * @param oldQuoteMap Trigger.oldMap.
     */
    public static void handleAfterUpdate(List<Quote> quoteRecords, Map<Id, Quote> oldQuoteMap) {
        Set<Id> opportunityIds = collectOpportunityIds(quoteRecords);
        synchronizeForecastEligibleDesignation(
            collectOpportunityIdsForForecastEligibleChange(quoteRecords, oldQuoteMap)
        );
        QuoteForecastChangeNotificationHandler.afterUpdate(quoteRecords, oldQuoteMap);
        OppForecastConfPropagateService.syncBannerStateForOpportunityIds(opportunityIds);
        OppClosedLostQuoteService.syncBannerStateForOpportunityIds(opportunityIds);
        OppEppConversionQuoteService.syncBannerStateForOpportunityIds(opportunityIds);
    }

    /**
     * @description After-delete orchestration for Quote trigger events.
     * @param quoteRecords Trigger.old rows.
     */
    public static void handleAfterDelete(List<Quote> quoteRecords) {
        Set<Id> opportunityIds = collectOpportunityIds(quoteRecords);
        synchronizeForecastEligibleDesignation(opportunityIds);
        QuoteForecastChangeNotificationHandler.afterDelete(quoteRecords);
        OppForecastConfPropagateService.syncBannerStateForOpportunityIds(opportunityIds);
        OppClosedLostQuoteService.syncBannerStateForOpportunityIds(opportunityIds);
        OppEppConversionQuoteService.syncBannerStateForOpportunityIds(opportunityIds);
    }

    /**
     * @description Returns true when the quote status is Open.
     * @param statusValue Quote Status picklist value.
     * @return True when the quote qualifies for forecast designation.
     */
    public static Boolean isForecastableStatus(String statusValue) {
        return FORECAST_ELIGIBLE_STATUS.equalsIgnoreCase(statusValue);
    }

    /**
     * @description Applies Forecast Eligible designation rules for one Opportunity on update
     *              or delete. Designates only the earliest eligible Open quote when none are
     *              currently Forecast Eligible (AC3).
     * @param opportunityQuotes Quote rows for a single Opportunity.
     * @param quotesToUpdateById Staged Quote updates keyed by Quote Id.
     */
    @TestVisible
    private static void processOpportunityQuotes(
        List<Quote> opportunityQuotes,
        Map<Id, Quote> quotesToUpdateById
    ) {
        if (opportunityQuotes == null || opportunityQuotes.isEmpty()) {
            return;
        }

        clearForecastEligibleOnIneligibleQuotes(opportunityQuotes, quotesToUpdateById);

        if (hasOpenForecastEligibleQuote(opportunityQuotes)) {
            return;
        }

        Quote designatedQuote = selectEarliestEligibleQuote(collectOpenQuotes(opportunityQuotes));
        if (designatedQuote == null || designatedQuote.Forecast_Eligible__c == true) {
            return;
        }

        stageQuoteUpdate(designatedQuote.Id, true, quotesToUpdateById);
        designatedQuote.Forecast_Eligible__c = true;
    }

    /**
     * @description Returns true when the Opportunity already has an open Forecast Eligible quote.
     * @param opportunityQuotes Quote rows for a single Opportunity.
     * @return True when a Forecast Eligible quote is present.
     */
    @TestVisible
    private static Boolean hasOpenForecastEligibleQuote(List<Quote> opportunityQuotes) {
        for (Quote quoteRecord : opportunityQuotes) {
            if (
                quoteRecord.Forecast_Eligible__c == true &&
                isForecastableStatus(quoteRecord.Status) &&
                !isClosedStatus(quoteRecord.Status)
            ) {
                return true;
            }
        }

        return false;
    }

    /**
     * @description Adds a Quote to an Opportunity-keyed collection.
     * @param quotesByOpportunityId Opportunity Id to Quote list map.
     * @param quoteRecord Quote to add.
     */
    private static void addQuoteToOpportunityGroup(
        Map<Id, List<Quote>> quotesByOpportunityId,
        Quote quoteRecord
    ) {
        if (quoteRecord == null || quoteRecord.OpportunityId == null) {
            return;
        }

        if (!quotesByOpportunityId.containsKey(quoteRecord.OpportunityId)) {
            quotesByOpportunityId.put(quoteRecord.OpportunityId, new List<Quote>());
        }

        quotesByOpportunityId.get(quoteRecord.OpportunityId).add(quoteRecord);
    }

    /**
     * @description Selects the earliest eligible Open quote by Last Modified Date.
     * @param quoteRecords Candidate Quote rows.
     * @return Earliest eligible quote, or null when none qualify.
     */
    @TestVisible
    private static Quote selectEarliestEligibleQuote(List<Quote> quoteRecords) {
        Quote earliestQuote = null;
        Datetime earliestDate;

        for (Quote quoteRecord : quoteRecords) {
            if (
                quoteRecord == null ||
                !isForecastableStatus(quoteRecord.Status) ||
                quoteRecord.IsForecastIneligible__c == true
            ) {
                continue;
            }

            Datetime resolvedDate = resolveLastModifiedDate(quoteRecord);
            if (
                earliestQuote == null ||
                isEarlierEligibleQuote(quoteRecord, resolvedDate, earliestQuote, earliestDate)
            ) {
                earliestQuote = quoteRecord;
                earliestDate = resolvedDate;
            }
        }

        return earliestQuote;
    }

    /**
     * @description Compares two eligible quotes using Last Modified Date and Id tie-break.
     * @param candidateQuote Candidate Quote row.
     * @param candidateDate Resolved Last Modified Date for the candidate.
     * @param currentEarliestQuote Current earliest Quote row.
     * @param currentEarliestDate Resolved Last Modified Date for the current earliest quote.
     * @return True when the candidate is earlier than the current earliest quote.
     */
    @TestVisible
    private static Boolean isEarlierEligibleQuote(
        Quote candidateQuote,
        Datetime candidateDate,
        Quote currentEarliestQuote,
        Datetime currentEarliestDate
    ) {
        if (candidateDate == null && currentEarliestDate == null) {
            return String.valueOf(candidateQuote.Id) < String.valueOf(currentEarliestQuote.Id);
        }

        if (candidateDate == null) {
            return false;
        }

        if (currentEarliestDate == null) {
            return true;
        }

        if (candidateDate != currentEarliestDate) {
            return candidateDate < currentEarliestDate;
        }

        return String.valueOf(candidateQuote.Id) < String.valueOf(currentEarliestQuote.Id);
    }

    private static List<Quote> collectOpenQuotes(List<Quote> opportunityQuotes) {
        List<Quote> openQuotes = new List<Quote>();

        for (Quote quoteRecord : opportunityQuotes) {
            if (
                !isForecastableStatus(quoteRecord.Status) ||
                quoteRecord.IsForecastIneligible__c == true
            ) {
                continue;
            }

            openQuotes.add(quoteRecord);
        }

        return openQuotes;
    }

    /**
     * @description Resolves the Sales Connection Last Modified Date for designation logic.
     * @param quoteRecord Quote being evaluated.
     * @return Custom LastModifiedDate__c when populated, otherwise standard LastModifiedDate.
     */
    @TestVisible
    public static Datetime resolveLastModifiedDate(Quote quoteRecord) {
        if (quoteRecord.LastModifiedDate__c != null) {
            return quoteRecord.LastModifiedDate__c;
        }

        return quoteRecord.LastModifiedDate;
    }

    /**
     * @description Groups queried Quote rows by Opportunity Id.
     * @param quoteRecords Quote rows returned from QuoteSelector.
     * @return Opportunity Id to related Quote list.
     */
    private static Map<Id, List<Quote>> groupQuotesByOpportunityId(List<Quote> quoteRecords) {
        Map<Id, List<Quote>> quotesByOpportunityId = new Map<Id, List<Quote>>();

        for (Quote quoteRecord : quoteRecords) {
            if (quoteRecord.OpportunityId == null) {
                continue;
            }

            if (!quotesByOpportunityId.containsKey(quoteRecord.OpportunityId)) {
                quotesByOpportunityId.put(quoteRecord.OpportunityId, new List<Quote>());
            }

            quotesByOpportunityId.get(quoteRecord.OpportunityId).add(quoteRecord);
        }

        return quotesByOpportunityId;
    }

    /**
     * @description Returns true when the quote status is Closed.
     * @param statusValue Quote Status picklist value.
     * @return True when the quote is closed.
     */
    public static Boolean isClosedStatus(String statusValue) {
        return QuoteSelector.CLOSED_STATUS_VALUE.equalsIgnoreCase(statusValue);
    }

    /**
     * @description Returns true when Forecast Eligible must be cleared because status
     *              changed from Open to a non-Closed, non-Open status.
     * @param quoteRecord Quote being saved.
     * @param oldQuoteMap Trigger.oldMap, null on insert.
     * @return True when Forecast Eligible should be forced to false.
     */
    @TestVisible
    private static Boolean shouldClearForecastEligibleOnOpenStatusChange(
        Quote quoteRecord,
        Map<Id, Quote> oldQuoteMap
    ) {
        if (quoteRecord == null || oldQuoteMap == null) {
            return false;
        }

        Quote oldQuoteRecord = oldQuoteMap.get(quoteRecord.Id);
        if (oldQuoteRecord == null) {
            return false;
        }

        return isForecastableStatus(oldQuoteRecord.Status)
            && !isForecastableStatus(quoteRecord.Status)
            && !isClosedStatus(quoteRecord.Status);
    }

    /**
     * @description Returns true when Forecast Eligible should not be auto-cleared to false.
     *              Preserves true values and explicit user changes from true to false.
     * @param quoteRecord Quote being saved.
     * @param oldQuoteMap Trigger.oldMap, null on insert.
     * @return True when automation must not force Forecast Eligible to false.
     */
    @TestVisible
    private static Boolean shouldPreserveForecastEligible(
        Quote quoteRecord,
        Map<Id, Quote> oldQuoteMap
    ) {
        if (quoteRecord == null) {
            return false;
        }

        if (quoteRecord.Forecast_Eligible__c == true) {
            return true;
        }

        if (oldQuoteMap == null) {
            return false;
        }

        Quote oldQuoteRecord = oldQuoteMap.get(quoteRecord.Id);
        return oldQuoteRecord != null
            && oldQuoteRecord.Forecast_Eligible__c == true
            && quoteRecord.Forecast_Eligible__c == false;
    }

    /**
     * @description Stages a Forecast Eligible update without duplicate Quote Ids.
     * @param quoteId Quote Id to update.
     * @param forecastEligible Target Forecast Eligible value.
     * @param quotesToUpdateById Staged Quote updates keyed by Quote Id.
     */
    private static void stageQuoteUpdate(
        Id quoteId,
        Boolean forecastEligible,
        Map<Id, Quote> quotesToUpdateById
    ) {
        quotesToUpdateById.put(
            quoteId,
            new Quote(
                Id = quoteId,
                Forecast_Eligible__c = forecastEligible
            )
        );
    }

    /**
     * @description Persists staged Forecast Eligible updates while bypassing QuoteTrigger recursion.
     * @param quotesToUpdate Quote rows to update.
     */
    private static void updateQuotesWithBypass(List<Quote> quotesToUpdate) {
        TriggerHandler.bypass('QuoteTriggerHandler');

        try {
            Database.SaveResult[] saveResults = Database.update(quotesToUpdate, false, AccessLevel.SYSTEM_MODE);

            for (Database.SaveResult saveResult : saveResults) {
                if (saveResult.isSuccess()) {
                    continue;
                }

                List<String> errorMessages = new List<String>();
                for (Database.Error saveError : saveResult.getErrors()) {
                    errorMessages.add(saveError.getMessage());
                }

                String errorMessage = String.join(errorMessages, ' ');
                Logger.setScenario(SCENARIO);
                Logger.error(
                    CLASS_NAME + '.updateQuotesWithBypass: ' + errorMessage
                ).addTag(LOGGER_TAG);
                throw new GenerateQuoteException(errorMessage);
            }

            QuoteForecastChangeNotificationHandler.stageFromForecastEligibleQuoteIds(
                new Map<Id, Quote>(quotesToUpdate).keySet()
            );
        } finally {
            TriggerHandler.clearBypass('QuoteTriggerHandler');
        }
    }

    /**
     * @description Returns true when the Quote uses the HC_Sales record type.
     * @param quoteRecord Quote being evaluated.
     * @return True for Sales Connection HC_Sales quotes.
     */
    @TestVisible
    private static Boolean isSalesConnectionQuote(Quote quoteRecord) {
        Id recordTypeId = resolveHcSalesRecordTypeId();
        return recordTypeId != null && quoteRecord.RecordTypeId == recordTypeId;
    }

    /**
     * @description Resolves and caches the HC_Sales Quote record type Id.
     * @return HC_Sales record type Id, or null when unavailable in the org.
     */
    private static Id resolveHcSalesRecordTypeId() {
        if (hcSalesRecordTypeId != null) {
            return hcSalesRecordTypeId;
        }

        Map<String, Schema.RecordTypeInfo> recordTypesByDeveloperName =
            Schema.SObjectType.Quote.getRecordTypeInfosByDeveloperName();

        if (!recordTypesByDeveloperName.containsKey(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME)) {
            return null;
        }

        Schema.RecordTypeInfo recordTypeInfo =
            recordTypesByDeveloperName.get(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME);
        hcSalesRecordTypeId = recordTypeInfo.isAvailable() ? recordTypeInfo.getRecordTypeId() : null;
        return hcSalesRecordTypeId;
    }

    /**
     * @description Collects Opportunity Ids from HC_Sales Quote rows.
     * @param quoteRecords Quote rows from Trigger.new or Trigger.old.
     * @return Opportunity Ids requiring Forecast Eligible re-evaluation.
     */
    @TestVisible
    private static Set<Id> collectOpportunityIds(List<Quote> quoteRecords) {
        Set<Id> opportunityIds = new Set<Id>();

        if (quoteRecords == null) {
            return opportunityIds;
        }

        Id salesConnectionRecordTypeId = resolveHcSalesRecordTypeId();

        for (Quote quoteRecord : quoteRecords) {
            if (
                quoteRecord.OpportunityId != null &&
                salesConnectionRecordTypeId != null &&
                quoteRecord.RecordTypeId == salesConnectionRecordTypeId
            ) {
                opportunityIds.add(quoteRecord.OpportunityId);
            }
        }

        return opportunityIds;
    }

    /**
     * @description Collects Opportunity Ids when Forecast Eligible driving fields change.
     * @param quoteRecords Quote rows from Trigger.new.
     * @param oldQuoteMap Quote rows from Trigger.oldMap.
     * @return Opportunity Ids requiring Forecast Eligible re-evaluation.
     */
    @TestVisible
    private static Set<Id> collectOpportunityIdsForForecastEligibleChange(
        List<Quote> quoteRecords,
        Map<Id, Quote> oldQuoteMap
    ) {
        Set<Id> opportunityIds = new Set<Id>();

        if (quoteRecords == null || oldQuoteMap == null) {
            return opportunityIds;
        }

        Id salesConnectionRecordTypeId = resolveHcSalesRecordTypeId();

        for (Quote quoteRecord : quoteRecords) {
            if (
                quoteRecord.OpportunityId == null ||
                salesConnectionRecordTypeId == null ||
                quoteRecord.RecordTypeId != salesConnectionRecordTypeId
            ) {
                continue;
            }

            Quote oldQuoteRecord = oldQuoteMap.get(quoteRecord.Id);
            if (oldQuoteRecord == null) {
                continue;
            }

            if (!hasForecastEligibleDrivingFieldChange(quoteRecord, oldQuoteRecord)) {
                continue;
            }

            opportunityIds.add(quoteRecord.OpportunityId);
        }

        return opportunityIds;
    }

    /**
     * @description Returns true when a non-manual Quote field changed that can require
     *              Forecast Eligible re-evaluation. Forecast_Eligible__c-only changes are ignored.
     * @param quoteRecord Quote being saved.
     * @param oldQuoteRecord Prior Quote values.
     * @return True when sync should run after update.
     */
    @TestVisible
    private static Boolean hasForecastEligibleDrivingFieldChange(
        Quote quoteRecord,
        Quote oldQuoteRecord
    ) {
        return quoteRecord.Status != oldQuoteRecord.Status ||
            quoteRecord.OpportunityId != oldQuoteRecord.OpportunityId ||
            quoteRecord.RecordTypeId != oldQuoteRecord.RecordTypeId ||
            quoteRecord.IsForecastIneligible__c != oldQuoteRecord.IsForecastIneligible__c;
    }

    /**
     * @description Clears Forecast Eligible on quotes marked forecast ineligible.
     * @param opportunityQuotes Quote rows for a single Opportunity.
     * @param quotesToUpdateById Staged Quote updates keyed by Quote Id.
     */
    @TestVisible
    private static void clearForecastEligibleOnIneligibleQuotes(
        List<Quote> opportunityQuotes,
        Map<Id, Quote> quotesToUpdateById
    ) {
        if (opportunityQuotes == null || opportunityQuotes.isEmpty()) {
            return;
        }

        for (Quote quoteRecord : opportunityQuotes) {
            if (quoteRecord.IsForecastIneligible__c != true || quoteRecord.Forecast_Eligible__c != true) {
                continue;
            }

            stageQuoteUpdate(quoteRecord.Id, false, quotesToUpdateById);
            quoteRecord.Forecast_Eligible__c = false;
        }
    }

    /**
     * @description Resolves Total w/o Freight for UI display from quote line TotalPrice values.
     * @param quoteRecord Quote being displayed.
     * @param quoteLineItems Related quote line items, when available.
     * @return Sum of Quote Line Item TotalPrice values, with field fallback when lines are unavailable.
     */
    public static Decimal resolveQuoteTotalWithoutFreight(
        Quote quoteRecord,
        List<QuoteLineItem> quoteLineItems
    ) {
        if (quoteRecord == null) {
            return null;
        }

        Decimal lineTotal = calculateQuoteLinesTotal(quoteLineItems);
        if (lineTotal != null) {
            return lineTotal;
        }

        return quoteRecord.Quote_Total_Without_Freight__c;
    }

    /**
     * @description Sums Quote Line Item TotalPrice values for Quote_Total_Without_Freight__c.
     * @param quoteLineItems Related quote line items.
     * @return Total amount, or null when lines were not supplied.
     */
    public static Decimal calculateQuoteLinesTotal(List<QuoteLineItem> quoteLineItems) {
        if (quoteLineItems == null) {
            return null;
        }

        if (quoteLineItems.isEmpty()) {
            return 0;
        }

        Decimal calculatedTotal = 0;
        for (QuoteLineItem quoteLineItem : quoteLineItems) {
            calculatedTotal += calculateQuoteLineTotal(quoteLineItem);
        }

        return calculatedTotal;
    }

    /**
     * @description Persists Quote_Total_Without_Freight__c as the sum of related TotalPrice values.
     * @param quoteIds Quote Ids to synchronize.
     */
    public static void syncQuoteTotalWithoutFreightFromLines(Set<Id> quoteIds) {
        if (quoteIds == null || quoteIds.isEmpty()) {
            return;
        }

        List<Quote> quotesToUpdate = new List<Quote>();

        for (Quote quoteRecord : QuoteSelector.selectByIdsWithLineItems(quoteIds)) {
            Decimal lineTotal = calculateQuoteLinesTotal(quoteRecord.QuoteLineItems);
            if (lineTotal == null || quoteRecord.Quote_Total_Without_Freight__c == lineTotal) {
                continue;
            }

            quotesToUpdate.add(
                new Quote(
                    Id = quoteRecord.Id,
                    Quote_Total_Without_Freight__c = lineTotal
                )
            );
        }

        if (quotesToUpdate.isEmpty()) {
            return;
        }

        TriggerHandler.bypass('QuoteTriggerHandler');

        try {
            Database.SaveResult[] saveResults = Database.update(
                quotesToUpdate,
                false,
                AccessLevel.SYSTEM_MODE
            );

            for (Database.SaveResult saveResult : saveResults) {
                if (saveResult.isSuccess()) {
                    continue;
                }

                List<String> errorMessages = new List<String>();
                for (Database.Error saveError : saveResult.getErrors()) {
                    errorMessages.add(saveError.getMessage());
                }

                throw new DmlException(String.join(errorMessages, ', '));
            }
        } finally {
            TriggerHandler.clearBypass('QuoteTriggerHandler');
        }
    }

    /**
     * @description Returns a quote line TotalPrice contribution.
     * @param quoteLineItem Quote line item row.
     * @return TotalPrice, or Quantity x UnitPrice when TotalPrice is unavailable.
     */
    public static Decimal calculateQuoteLineTotal(QuoteLineItem quoteLineItem) {
        if (quoteLineItem == null) {
            return 0;
        }

        if (quoteLineItem.TotalPrice != null) {
            return quoteLineItem.TotalPrice;
        }

        Decimal quantity = quoteLineItem.Quantity == null || quoteLineItem.Quantity <= 0
            ? 1
            : quoteLineItem.Quantity;
        Decimal unitPrice = quoteLineItem.UnitPrice == null ? 0 : quoteLineItem.UnitPrice;
        return quantity * unitPrice;
    }

    /**
     * @description GW-3600 - Loads a Quote header for Repair Center document generation.
     * @param quoteId Repair Center Quote Id.
     * @return Quote header, or null when the Id is null or no row matches.
     */
    public static Quote selectForRepairCenterDocumentGeneration(Id quoteId) {
        if (quoteId == null) {
            return null;
        }
        return (Quote) new QuoteSelector()
            .selectFields(
                new List<String>{
                    'Id',
                    'QuoteNumber',
                    'CurrencyIsoCode',
                    'Version__c',
                    'EstimateType__c',
                    'WorkOrderType__c',
                    'WorkOrderNumber__c',
                    'ReturnOrderNumber__c',
                    'PrintDate__c',
                    'PurchaseOrder__c',
                    'AccountName__c',
                    'AccountManager__c',
                    'DepartmentName__c',
                    'CustomerReference__c',
                    'BillToAddress__c',
                    'ShipToAddress__c',
                    'BillingStreet',
                    'BillingCity',
                    'BillingState',
                    'BillingStateCode',
                    'BillingPostalCode',
                    'BillingCountry',
                    'BillingCountryCode',
                    'ShippingStreet',
                    'ShippingCity',
                    'ShippingState',
                    'ShippingStateCode',
                    'ShippingPostalCode',
                    'ShippingCountry',
                    'ShippingCountryCode',
                    'OperatingUnit__c',
                    'QuoteAccount.AccountNumber',
                    'WorkOrder__c',
                    'WorkOrder__r.EvaluationNotes__c',
                    'WorkOrder__r.SubStatus__c',
                    'WorkOrder__r.CustomerPORequired__c',
                    'WorkOrder__r.Contact.Name',
                    'WorkOrder__r.EstimateContact__r.Name'
                }
            )
            .whereEquals('Id', quoteId)
            .first();
    }

    /**
     * @description GW-4117 - Loads Quote rows evaluated for Repair Center pre-approval.
     * @param quoteIds Quote Ids to load.
     * @return Matching Quotes, or an empty list when no Ids are provided.
     */
    public static List<Quote> selectForRepairCenterPreApproval(Set<Id> quoteIds) {
        if (quoteIds == null || quoteIds.isEmpty()) {
            return new List<Quote>();
        }
        SoqlQueryBuilder query = new QuoteSelector()
            .selectFields(new List<String>{ 'Id', 'AccountId', 'Status' });
        List<String> idFilterNumbers = new List<String>();
        Integer filterNumber = 1;
        for (Id quoteId : quoteIds) {
            if (quoteId == null) {
                continue;
            }
            query.whereEquals('Id', quoteId);
            idFilterNumbers.add(String.valueOf(filterNumber));
            filterNumber++;
        }
        if (idFilterNumbers.isEmpty()) {
            return new List<Quote>();
        }
        if (idFilterNumbers.size() > 1) {
            query.withFilterLogic(String.join(idFilterNumbers, ' OR '));
        }
        return (List<Quote>) query.execute();
    }

    /**
     * @description GW-5102 - Updates Quote header status from Repair Center inbound email replies.
     * @param quotes Quote rows to update
     */
    public static void updateQuotes(List<Quote> quotes) {
        if (quotes == null || quotes.isEmpty()) {
            return;
        }

        Logger.setScenario('Repair Center Quote Email');
        TriggerHandler.bypass('QuoteTriggerHandler');
        try {
            update quotes;
        } catch (Exception exceptionValue) {
            Logger.error(CLASS_NAME + '.updateQuotes: ' + exceptionValue.getMessage()).addTag(LOGGER_TAG);
            throw exceptionValue;
        } finally {
            TriggerHandler.clearBypass('QuoteTriggerHandler');
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5333 - Loads the Approve/Reject Quote workspace for a Work Order.
     * @param workOrderId Work Order Id
     * @return Workspace DTO for the LWC
     */
    public static ApproveRejectWorkspace getApproveRejectWorkspace(Id workOrderId) {
        try {
            return new ApproveRejectWorker().getWorkspace(workOrderId);
        } catch (ApproveRejectException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('QuoteService.getApproveRejectWorkspace', e).addTag(LOGGER_TAG_APPROVE_REJECT);
            throw new ApproveRejectException(
                'Unable to load Approve/Reject Quote: ' + e.getMessage()
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5333 - Saves Approve/Reject decisions for Product Serviced quote lines.
     * @param workOrderId Work Order Id
     * @param decisions Line-level Approve/Reject choices
     * @return Updated workspace DTO
     */
    public static ApproveRejectWorkspace saveApproveRejectDecisions(
        Id workOrderId,
        List<ApproveRejectDecision> decisions
    ) {
        try {
            return new ApproveRejectWorker().saveDecisions(workOrderId, decisions);
        } catch (ApproveRejectException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('QuoteService.saveApproveRejectDecisions', e).addTag(LOGGER_TAG_APPROVE_REJECT);
            throw new ApproveRejectException(
                'Unable to save Approve/Reject Quote: ' + e.getMessage()
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5333 - Saves Quote Comments immediately on a Quote Line Item.
     * @param quoteLineItemId Quote Line Item Id
     * @param comments Quote Comments text
     * @return Saved comments
     */
    public static String saveApproveRejectComment(Id quoteLineItemId, String comments) {
        try {
            QuoteLineItem lineItem = QuoteLineItemService.saveQuoteComments(quoteLineItemId, comments);
            return lineItem.QuoteComments__c;
        } catch (QuoteLineItemService.QuoteLineItemServiceException e) {
            throw new ApproveRejectException(e.getMessage());
        } catch (Exception e) {
            Logger.error('QuoteService.saveApproveRejectComment', e).addTag(LOGGER_TAG_APPROVE_REJECT);
            throw new ApproveRejectException(
                'Unable to save Quote Comments: ' + e.getMessage()
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5333 Approve/Reject Quote workspace.
     */
    public class ApproveRejectWorkspace {
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public Id quoteId;
        @AuraEnabled public Decimal quoteVersion;
        @AuraEnabled public String quoteStatus;
        @AuraEnabled public Decimal estimateTotal;
        @AuraEnabled public List<ApproveRejectLine> lines;
    }

    /**
     * @description GW-5333 Product Serviced row in Approve/Reject Quote.
     */
    public class ApproveRejectLine {
        @AuraEnabled public Id quoteLineItemId;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public String lineItemNumber;
        @AuraEnabled public String description;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal estimatePrice;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal turnTime;
        @AuraEnabled public Date scheduledShipDate;
        @AuraEnabled public String quoteComments;
        @AuraEnabled public Boolean hasComments;
        @AuraEnabled public String selectedDecision;
    }

    /**
     * @description GW-5333 line decision from the LWC.
     */
    public class ApproveRejectDecision {
        @AuraEnabled
        public String quoteLineItemId { get; set; }
        @AuraEnabled
        public String status { get; set; }
    }

    /**
     * @description Thrown when Approve/Reject Quote cannot complete.
     */
    public class ApproveRejectException extends Exception {
    }

    private class ApproveRejectWorker {
        private ApproveRejectWorkspace getWorkspace(Id workOrderId) {
            WorkOrder workOrder = requireWorkOrder(workOrderId);
            Quote quoteRecord = requireActiveQuote(workOrder);
            return buildWorkspace(workOrder, quoteRecord);
        }

        private ApproveRejectWorkspace saveDecisions(
            Id workOrderId,
            List<ApproveRejectDecision> decisions
        ) {
            WorkOrder workOrder = requireWorkOrder(workOrderId);
            Quote quoteRecord = requireActiveQuote(workOrder);
            List<QuoteLineItem> lineItems =
                QuoteLineItemService.getLineItemsForApproveReject(quoteRecord.Id);
            Map<Id, String> decisionsByLineId = mapDecisions(decisions);
            Map<Id, Product2> productsById = loadProducts(lineItems);

            List<QuoteLineItem> linesToUpdate = new List<QuoteLineItem>();
            Set<Id> approvedProductServicedIds = new Set<Id>();
            Set<Id> rejectedProductServicedIds = new Set<Id>();

            for (QuoteLineItem lineItem : lineItems) {
                if (lineItem.LineType__c != LINE_TYPE_PRODUCT_SERVICED) {
                    continue;
                }
                String decision = decisionsByLineId.get(lineItem.Id);
                if (decision != STATUS_APPROVED && decision != STATUS_REJECTED) {
                    continue;
                }
                lineItem.Status__c = decision;
                linesToUpdate.add(lineItem);
                if (decision == STATUS_APPROVED) {
                    approvedProductServicedIds.add(lineItem.Id);
                } else {
                    rejectedProductServicedIds.add(lineItem.Id);
                }
            }

            applyChildLineStatuses(
                lineItems,
                linesToUpdate,
                approvedProductServicedIds,
                rejectedProductServicedIds,
                productsById
            );

            if (linesToUpdate.isEmpty()) {
                throw new ApproveRejectException(
                    'No quote lines matched the submitted decisions. Received ' +
                        (decisions == null ? 0 : decisions.size()) +
                        ' decision(s): ' +
                        JSON.serialize(decisions)
                );
            }

            QuoteLineItemService.updateLineItemsForApproveReject(linesToUpdate);

            quoteRecord.Status = resolveQuoteStatus(lineItems);
            update quoteRecord;

            createInspectionFeeLines(
                workOrder,
                quoteRecord,
                lineItems,
                rejectedProductServicedIds,
                productsById
            );

            return buildWorkspace(
                requireWorkOrder(workOrderId),
                QuoteSelector.selectForApproveRejectById(quoteRecord.Id)
            );
        }

        private WorkOrder requireWorkOrder(Id workOrderId) {
            if (workOrderId == null) {
                throw new ApproveRejectException('Work Order Id is required.');
            }
            List<WorkOrder> workOrders =
                WorkOrdersService.getWorkOrdersForApproveRejectQuote(new Set<Id>{ workOrderId });
            if (workOrders.isEmpty()) {
                throw new ApproveRejectException('Work Order was not found.');
            }
            return workOrders[0];
        }

        private Quote requireActiveQuote(WorkOrder workOrder) {
            if (workOrder.ActiveQuote__c == null) {
                throw new ApproveRejectException('This Work Order does not have an Active Quote.');
            }
            Quote quoteRecord = QuoteSelector.selectForApproveRejectById(workOrder.ActiveQuote__c);
            if (quoteRecord == null) {
                throw new ApproveRejectException('Active Quote was not found.');
            }
            if (quoteRecord.Status != STATUS_WAITING_FOR_APPROVAL) {
                throw new ApproveRejectException(
                    'Approve/Reject Quote is available when the Active Quote status is Waiting for Approval.'
                );
            }
            return quoteRecord;
        }

        private ApproveRejectWorkspace buildWorkspace(WorkOrder workOrder, Quote quoteRecord) {
            List<QuoteLineItem> lineItems =
                QuoteLineItemService.getLineItemsForApproveReject(quoteRecord.Id);
            Map<Id, WorkOrderLineItem> wolisById = loadWorkOrderLineItems(lineItems);
            Map<Id, WorkOrder> workOrdersById = loadLineWorkOrders(workOrder, lineItems);
            Map<Id, Product2> productsById = loadProducts(lineItems);
            Map<Id, Decimal> estimatePriceByParentId = buildEstimatePrices(lineItems);

            List<ApproveRejectLine> rows = new List<ApproveRejectLine>();
            Decimal estimateTotal = 0;
            for (QuoteLineItem lineItem : lineItems) {
                if (lineItem.LineType__c != LINE_TYPE_PRODUCT_SERVICED) {
                    continue;
                }
                ApproveRejectLine row = new ApproveRejectLine();
                row.quoteLineItemId = lineItem.Id;
                WorkOrder lineWorkOrder = workOrdersById.get(lineItem.WorkOrder__c);
                row.workOrderNumber = lineWorkOrder == null ? null : lineWorkOrder.WorkOrderNumber;
                WorkOrderLineItem woli = wolisById.get(lineItem.WorkOrderLineItem__c);
                row.lineItemNumber = woli == null ? null : woli.LineItemNumber;
                Product2 product = productsById.get(lineItem.Product2Id);
                row.description = resolveDescription(lineItem, product);
                row.quantity = lineItem.Quantity;
                Decimal estimatePrice = estimatePriceByParentId.containsKey(lineItem.Id)
                    ? estimatePriceByParentId.get(lineItem.Id)
                    : 0;
                row.estimatePrice = estimatePrice;
                estimateTotal += estimatePrice;
                row.status = lineItem.Status__c;
                row.turnTime = lineWorkOrder == null ? null : lineWorkOrder.TurnTime__c;
                row.scheduledShipDate = lineWorkOrder == null ? null : lineWorkOrder.ScheduledShipDate__c;
                row.quoteComments = lineItem.QuoteComments__c;
                row.hasComments = String.isNotBlank(lineItem.QuoteComments__c);
                row.selectedDecision =
                    lineItem.Status__c == STATUS_APPROVED || lineItem.Status__c == STATUS_REJECTED
                        ? lineItem.Status__c
                        : null;
                rows.add(row);
            }
            rows.sort(new ApproveRejectLineComparator());

            ApproveRejectWorkspace workspace = new ApproveRejectWorkspace();
            workspace.workOrderId = workOrder.Id;
            workspace.workOrderNumber = workOrder.WorkOrderNumber;
            workspace.quoteId = quoteRecord.Id;
            workspace.quoteVersion = quoteRecord.Version__c;
            workspace.quoteStatus = quoteRecord.Status;
            workspace.estimateTotal = estimateTotal;
            workspace.lines = rows;
            return workspace;
        }

        private Map<Id, WorkOrderLineItem> loadWorkOrderLineItems(List<QuoteLineItem> lineItems) {
            Set<Id> woliIds = new Set<Id>();
            for (QuoteLineItem lineItem : lineItems) {
                if (lineItem.WorkOrderLineItem__c != null) {
                    woliIds.add(lineItem.WorkOrderLineItem__c);
                }
                if (lineItem.ParentWorkOrderLineItem__c != null) {
                    woliIds.add(lineItem.ParentWorkOrderLineItem__c);
                }
            }
            Map<Id, WorkOrderLineItem> wolisById = new Map<Id, WorkOrderLineItem>();
            for (WorkOrderLineItem woli : WorkOrderLineItemsService.getLineItemsById(woliIds)) {
                wolisById.put(woli.Id, woli);
            }
            return wolisById;
        }

        private Map<Id, WorkOrder> loadLineWorkOrders(
            WorkOrder headerWorkOrder,
            List<QuoteLineItem> lineItems
        ) {
            Set<Id> workOrderIds = new Set<Id>{ headerWorkOrder.Id };
            for (QuoteLineItem lineItem : lineItems) {
                if (lineItem.WorkOrder__c != null) {
                    workOrderIds.add(lineItem.WorkOrder__c);
                }
            }
            Map<Id, WorkOrder> workOrdersById = new Map<Id, WorkOrder>();
            for (
                WorkOrder workOrder : WorkOrdersService.getWorkOrdersForApproveRejectQuote(workOrderIds)
            ) {
                workOrdersById.put(workOrder.Id, workOrder);
            }
            return workOrdersById;
        }

        private Map<Id, Product2> loadProducts(List<QuoteLineItem> lineItems) {
            Set<Id> productIds = new Set<Id>();
            for (QuoteLineItem lineItem : lineItems) {
                if (lineItem.Product2Id != null) {
                    productIds.add(lineItem.Product2Id);
                }
            }
            Map<Id, Product2> productsById = new Map<Id, Product2>();
            for (Product2 product : ProductsService.getProductsForApproveRejectById(productIds)) {
                productsById.put(product.Id, product);
                if (product.InspectionServiceCode__c != null) {
                    productIds.add(product.InspectionServiceCode__c);
                }
            }
            if (productIds.size() > productsById.size()) {
                for (Product2 product : ProductsService.getProductsForApproveRejectById(productIds)) {
                    productsById.put(product.Id, product);
                }
            }
            return productsById;
        }

        private Map<Id, Decimal> buildEstimatePrices(List<QuoteLineItem> lineItems) {
            Map<Id, Id> productServicedIdByWoliId = mapProductServicedByWorkOrderLineItem(lineItems);
            Map<Id, Decimal> estimatePriceByParentId = new Map<Id, Decimal>();

            for (QuoteLineItem lineItem : lineItems) {
                if (!ESTIMATE_PRICE_LINE_TYPES.contains(lineItem.LineType__c)) {
                    continue;
                }
                Id parentId = resolveParentProductServicedId(lineItem, productServicedIdByWoliId);
                if (parentId == null) {
                    continue;
                }
                Decimal currentTotal = estimatePriceByParentId.containsKey(parentId)
                    ? estimatePriceByParentId.get(parentId)
                    : 0;
                Decimal lineTotal = lineItem.TotalPrice == null ? 0 : lineItem.TotalPrice;
                estimatePriceByParentId.put(parentId, currentTotal + lineTotal);
            }
            return estimatePriceByParentId;
        }

        /**
         * @description GW-5333 - Maps Product Serviced Work Order Line Item Ids to their quote lines.
         *              ParentQuoteLineItemId is read-only in the org, so child lines are matched
         *              through Parent Work Order Line Item when it is not populated.
         */
        private Map<Id, Id> mapProductServicedByWorkOrderLineItem(List<QuoteLineItem> lineItems) {
            Map<Id, Id> productServicedIdByWoliId = new Map<Id, Id>();
            for (QuoteLineItem lineItem : lineItems) {
                if (
                    lineItem.LineType__c == LINE_TYPE_PRODUCT_SERVICED &&
                    lineItem.WorkOrderLineItem__c != null
                ) {
                    productServicedIdByWoliId.put(lineItem.WorkOrderLineItem__c, lineItem.Id);
                }
            }
            return productServicedIdByWoliId;
        }

        private Id resolveParentProductServicedId(
            QuoteLineItem lineItem,
            Map<Id, Id> productServicedIdByWoliId
        ) {
            if (lineItem.ParentQuoteLineItemId != null) {
                return lineItem.ParentQuoteLineItemId;
            }
            if (lineItem.ParentWorkOrderLineItem__c == null) {
                return null;
            }
            return productServicedIdByWoliId.get(lineItem.ParentWorkOrderLineItem__c);
        }

        private String resolveDescription(QuoteLineItem lineItem, Product2 product) {
            if (product != null && String.isNotBlank(product.Description)) {
                return product.Description;
            }
            if (String.isNotBlank(lineItem.ProductDescription__c)) {
                return lineItem.ProductDescription__c;
            }
            return lineItem.Description;
        }

        private Map<Id, String> mapDecisions(List<ApproveRejectDecision> decisions) {
            Map<Id, String> decisionsByLineId = new Map<Id, String>();
            if (decisions == null) {
                return decisionsByLineId;
            }
            for (ApproveRejectDecision decision : decisions) {
                if (decision == null || String.isBlank(decision.quoteLineItemId)) {
                    continue;
                }
                decisionsByLineId.put(Id.valueOf(decision.quoteLineItemId), decision.status);
            }
            return decisionsByLineId;
        }

        private void applyChildLineStatuses(
            List<QuoteLineItem> lineItems,
            List<QuoteLineItem> linesToUpdate,
            Set<Id> approvedProductServicedIds,
            Set<Id> rejectedProductServicedIds,
            Map<Id, Product2> productsById
        ) {
            if (approvedProductServicedIds.isEmpty() && rejectedProductServicedIds.isEmpty()) {
                return;
            }

            Map<Id, WorkOrderLineItem> wolisById = loadWorkOrderLineItems(lineItems);
            Map<Id, String> productLineByProductServicedId = new Map<Id, String>();
            for (QuoteLineItem lineItem : lineItems) {
                if (lineItem.LineType__c != LINE_TYPE_PRODUCT_SERVICED) {
                    continue;
                }
                productLineByProductServicedId.put(
                    lineItem.Id,
                    resolveProductLine(lineItem, wolisById, productsById)
                );
            }

            Set<String> approvedProductLines = new Set<String>();
            Set<String> rejectedProductLines = new Set<String>();
            for (Id lineId : approvedProductServicedIds) {
                String productLine = productLineByProductServicedId.get(lineId);
                if (String.isNotBlank(productLine)) {
                    approvedProductLines.add(productLine);
                }
            }
            for (Id lineId : rejectedProductServicedIds) {
                String productLine = productLineByProductServicedId.get(lineId);
                if (String.isNotBlank(productLine)) {
                    rejectedProductLines.add(productLine);
                }
            }

            Map<Id, Id> productServicedIdByWoliId = mapProductServicedByWorkOrderLineItem(lineItems);
            Set<Id> stagedIds = new Set<Id>(new Map<Id, QuoteLineItem>(linesToUpdate).keySet());
            for (QuoteLineItem lineItem : lineItems) {
                if (!CHILD_STATUS_LINE_TYPES.contains(lineItem.LineType__c)) {
                    continue;
                }
                Id parentLineId = resolveParentProductServicedId(lineItem, productServicedIdByWoliId);
                String parentProductLine = resolveParentProductLine(lineItem, wolisById);
                Boolean matchesApprovedParent =
                    approvedProductServicedIds.contains(parentLineId) ||
                    (String.isNotBlank(parentProductLine) &&
                        approvedProductLines.contains(parentProductLine));
                Boolean matchesRejectedParent =
                    rejectedProductServicedIds.contains(parentLineId) ||
                    (String.isNotBlank(parentProductLine) &&
                        rejectedProductLines.contains(parentProductLine));

                if (matchesApprovedParent) {
                    lineItem.Status__c = STATUS_APPROVED;
                } else if (matchesRejectedParent) {
                    Product2 product = productsById.get(lineItem.Product2Id);
                    lineItem.Status__c =
                        product != null && product.ServiceCodeType__c == SERVICE_CODE_TYPE_DISINFECTION
                            ? STATUS_APPROVED
                            : STATUS_REJECTED;
                } else {
                    continue;
                }

                if (!stagedIds.contains(lineItem.Id)) {
                    linesToUpdate.add(lineItem);
                    stagedIds.add(lineItem.Id);
                }
            }
        }

        private String resolveProductLine(
            QuoteLineItem lineItem,
            Map<Id, WorkOrderLineItem> wolisById,
            Map<Id, Product2> productsById
        ) {
            WorkOrderLineItem woli = wolisById.get(lineItem.WorkOrderLineItem__c);
            if (woli != null && String.isNotBlank(woli.ProductLine__c)) {
                return woli.ProductLine__c;
            }
            Product2 product = productsById.get(lineItem.Product2Id);
            return product == null ? null : product.ProductLine__c;
        }

        private String resolveParentProductLine(
            QuoteLineItem lineItem,
            Map<Id, WorkOrderLineItem> wolisById
        ) {
            WorkOrderLineItem parentWoli = wolisById.get(lineItem.ParentWorkOrderLineItem__c);
            return parentWoli == null ? null : parentWoli.ProductLine__c;
        }

        private String resolveQuoteStatus(List<QuoteLineItem> lineItems) {
            Boolean hasWaiting = false;
            Boolean hasApproved = false;
            Integer productServicedCount = 0;
            Integer rejectedCount = 0;

            for (QuoteLineItem lineItem : lineItems) {
                if (lineItem.LineType__c != LINE_TYPE_PRODUCT_SERVICED) {
                    continue;
                }
                productServicedCount++;
                if (lineItem.Status__c == STATUS_WAITING_FOR_APPROVAL || String.isBlank(lineItem.Status__c)) {
                    hasWaiting = true;
                } else if (lineItem.Status__c == STATUS_APPROVED) {
                    hasApproved = true;
                } else if (lineItem.Status__c == STATUS_REJECTED) {
                    rejectedCount++;
                }
            }

            if (hasWaiting || productServicedCount == 0) {
                return STATUS_WAITING_FOR_APPROVAL;
            }
            if (rejectedCount == productServicedCount && !hasApproved) {
                return STATUS_REJECTED;
            }
            return STATUS_APPROVED;
        }

        private void createInspectionFeeLines(
            WorkOrder workOrder,
            Quote quoteRecord,
            List<QuoteLineItem> lineItems,
            Set<Id> rejectedProductServicedIds,
            Map<Id, Product2> productsById
        ) {
            if (rejectedProductServicedIds.isEmpty()) {
                return;
            }

            Id repairCodeRtId = resolveRepairCodeRecordTypeId();
            List<WorkOrderLineItem> inspectionLines = new List<WorkOrderLineItem>();
            Set<Id> inspectionProductIds = new Set<Id>();
            Map<Id, QuoteLineItem> rejectedLinesById = new Map<Id, QuoteLineItem>();
            for (QuoteLineItem lineItem : lineItems) {
                if (!rejectedProductServicedIds.contains(lineItem.Id)) {
                    continue;
                }
                Product2 product = productsById.get(lineItem.Product2Id);
                if (product == null || product.InspectionFeeApplicable__c != true) {
                    continue;
                }
                if (product.InspectionServiceCode__c == null) {
                    continue;
                }
                rejectedLinesById.put(lineItem.Id, lineItem);
                inspectionProductIds.add(product.InspectionServiceCode__c);
            }

            if (inspectionProductIds.isEmpty()) {
                return;
            }

            Id pricebookId = quoteRecord.Pricebook2Id != null
                ? quoteRecord.Pricebook2Id
                : workOrder.Pricebook2Id;
            Map<Id, Id> pricebookEntryIdsByProductId =
                PricebookEntriesService.getPricebookEntryIdsByProductId(
                    pricebookId,
                    inspectionProductIds,
                    workOrder.CurrencyIsoCode
                );

            for (QuoteLineItem lineItem : rejectedLinesById.values()) {
                Product2 productServiced = productsById.get(lineItem.Product2Id);
                Product2 inspectionProduct = productsById.get(productServiced.InspectionServiceCode__c);
                if (inspectionProduct == null) {
                    continue;
                }
                Id pricebookEntryId = pricebookEntryIdsByProductId.get(inspectionProduct.Id);
                if (pricebookEntryId == null) {
                    throw new ApproveRejectException(
                        'No active Price Book Entry was found for Inspection Service Code ' +
                        inspectionProduct.ProductCode +
                        '.'
                    );
                }

                WorkOrderLineItem inspectionLine = new WorkOrderLineItem();
                inspectionLine.RecordTypeId = repairCodeRtId;
                inspectionLine.LineType__c = String.isBlank(inspectionProduct.ProductType__c)
                    ? LINE_TYPE_SERVICE_CODE
                    : inspectionProduct.ProductType__c;
                inspectionLine.AssetId = lineItem.Asset__c;
                inspectionLine.SerialNumber__c = lineItem.SerialNumber__c;
                inspectionLine.Model__c = productServiced.Model__c;
                inspectionLine.Item__c = lineItem.Product2Id;
                inspectionLine.ItemCode__c = lineItem.ItemCode__c;
                inspectionLine.ItemDescription__c = String.isNotBlank(lineItem.Description)
                    ? lineItem.Description
                    : lineItem.ItemDescription__c;
                inspectionLine.PricebookEntryId = pricebookEntryId;
                inspectionLine.ProductCodeWoli__c = inspectionProduct.ProductCode;
                inspectionLine.ProductDescription__c = inspectionProduct.Description;
                inspectionLine.WorkOrderId = lineItem.WorkOrder__c != null
                    ? lineItem.WorkOrder__c
                    : workOrder.Id;
                inspectionLine.TopLevelWorkOrder__c = lineItem.TopLevelWorkOrder__c != null
                    ? lineItem.TopLevelWorkOrder__c
                    : workOrder.ParentWorkOrderId;
                inspectionLine.ParentWorkOrderLineItemId = lineItem.ParentWorkOrderLineItem__c;
                inspectionLine.Quantity = lineItem.Quantity == null ? 1 : lineItem.Quantity;
                inspectionLine.Status = STATUS_APPROVED;
                inspectionLines.add(inspectionLine);
            }

            if (!inspectionLines.isEmpty()) {
                WorkOrderLineItemsService.createLineItems(inspectionLines);
            }
        }

        private Id resolveRepairCodeRecordTypeId() {
            Map<String, Schema.RecordTypeInfo> recordTypes =
                Schema.SObjectType.WorkOrderLineItem.getRecordTypeInfosByDeveloperName();
            Schema.RecordTypeInfo recordTypeInfo = recordTypes.get(WOLI_RECORD_TYPE_REPAIR_CODE);
            return recordTypeInfo == null ? null : recordTypeInfo.getRecordTypeId();
        }
    }

    private class ApproveRejectLineComparator implements Comparator<ApproveRejectLine> {
        public Integer compare(ApproveRejectLine left, ApproveRejectLine right) {
            String leftWorkOrder = left == null || left.workOrderNumber == null
                ? ''
                : left.workOrderNumber;
            String rightWorkOrder = right == null || right.workOrderNumber == null
                ? ''
                : right.workOrderNumber;
            Integer workOrderCompare = leftWorkOrder.compareTo(rightWorkOrder);
            if (workOrderCompare != 0) {
                return workOrderCompare;
            }
            String leftLine = left == null || left.lineItemNumber == null ? '' : left.lineItemNumber;
            String rightLine = right == null || right.lineItemNumber == null ? '' : right.lineItemNumber;
            return leftLine.compareTo(rightLine);
        }
    }
}