/**
 * @author Himanshu Chaurasia
 * @date 2026/09/09
 *
 * @description Stages and processes Opportunity Forecast Confidence propagation to associated quotes.
 */
public with sharing class OppForecastConfPropagateService {
    private static final String CLASS_NAME = 'OppForecastConfPropagateService';
    private static final String OPPORTUNITY_FORECAST_CONFIDENCE_WON = 'Won';
    private static final String OPPORTUNITY_FORECAST_CONFIDENCE_LOST = 'Lost';

    public class QuoteRow {
        @AuraEnabled
        public Id id;

        @AuraEnabled
        public String quoteNumber;

        @AuraEnabled
        public String status;

        @AuraEnabled
        public String currentForecastConfidence;

        @AuraEnabled
        public String pendingForecastConfidence;

        @AuraEnabled
        public Boolean selected;
    }

    public class BannerContext {
        @AuraEnabled
        public Boolean showBanner;

        @AuraEnabled
        public String message;

        @AuraEnabled
        public String opportunityForecastConfidence;

        @AuraEnabled
        public String pendingQuoteForecastConfidence;

        @AuraEnabled
        public List<QuoteRow> quotes;
    }

    /**
     * @description Sets banner fields on Opportunity when Forecast Confidence changes and quotes exist.
     * @param newOpportunities Trigger.new Opportunity rows.
     * @param oldOpportunityMap Trigger.oldMap Opportunity rows.
     */
    public static void stagePropagateBanner(
        List<Opportunity> newOpportunities,
        Map<Id, Opportunity> oldOpportunityMap
    ) {
        if (newOpportunities == null || newOpportunities.isEmpty() || oldOpportunityMap == null) {
            return;
        }

        Set<Id> changedOpportunityIds = new Set<Id>();
        Map<Id, String> pendingConfidenceByOpportunityId = new Map<Id, String>();

        for (Opportunity opportunityRecord : newOpportunities) {
            Opportunity oldOpportunityRecord = oldOpportunityMap.get(opportunityRecord.Id);

            if (oldOpportunityRecord == null) {
                continue;
            }

            if (shouldSuppressForecastConfidencePropagateBanner(opportunityRecord, oldOpportunityRecord)) {
                opportunityRecord.ShowForecastConfidencePropagateBanner__c = false;
                opportunityRecord.PendingQuoteForecastConfidence__c = null;
                continue;
            }

            if (
                opportunityRecord.ForecastConfidenceLevel__c ==
                oldOpportunityRecord.ForecastConfidenceLevel__c
            ) {
                continue;
            }

            String pendingQuoteForecastConfidence = QuoteService.mapOpportunityForecastConfidenceToQuote(
                opportunityRecord.ForecastConfidenceLevel__c
            );

            if (String.isBlank(pendingQuoteForecastConfidence)) {
                opportunityRecord.ShowForecastConfidencePropagateBanner__c = false;
                opportunityRecord.PendingQuoteForecastConfidence__c = null;
                continue;
            }

            changedOpportunityIds.add(opportunityRecord.Id);
            pendingConfidenceByOpportunityId.put(
                opportunityRecord.Id,
                pendingQuoteForecastConfidence
            );
        }

        if (changedOpportunityIds.isEmpty()) {
            return;
        }

        Map<Id, String> forecastConfidenceByOpportunityId = new Map<Id, String>();
        for (Opportunity opportunityRecord : newOpportunities) {
            if (changedOpportunityIds.contains(opportunityRecord.Id)) {
                forecastConfidenceByOpportunityId.put(
                    opportunityRecord.Id,
                    opportunityRecord.ForecastConfidenceLevel__c
                );
            }
        }

        Map<Id, Integer> quoteCountsByOpportunityId =
            QuoteSelector.countPropagatableForecastConfidenceQuotesByOpportunityIds(
                changedOpportunityIds,
                forecastConfidenceByOpportunityId
            );

        for (Opportunity opportunityRecord : newOpportunities) {
            if (!pendingConfidenceByOpportunityId.containsKey(opportunityRecord.Id)) {
                continue;
            }

            Integer quoteCount = quoteCountsByOpportunityId.get(opportunityRecord.Id);
            if (quoteCount == null || quoteCount == 0) {
                opportunityRecord.ShowForecastConfidencePropagateBanner__c = false;
                opportunityRecord.PendingQuoteForecastConfidence__c = null;
                continue;
            }

            opportunityRecord.ShowForecastConfidencePropagateBanner__c = true;
            opportunityRecord.PendingQuoteForecastConfidence__c =
                pendingConfidenceByOpportunityId.get(opportunityRecord.Id);
        }
    }

    /**
     * @description Clears stale banner flags when an Opportunity no longer has applicable quotes.
     * @param opportunityIds Opportunity record Ids affected by Quote changes.
     */
    public static void syncBannerStateForOpportunityIds(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return;
        }

        Map<Id, Integer> quoteCountsByOpportunityId =
            QuoteSelector.countPropagatableForecastConfidenceQuotesByOpportunityIds(opportunityIds);
        List<Opportunity> opportunitiesToClear = new List<Opportunity>();

        for (Opportunity opportunityRecord : [
            SELECT Id
            FROM Opportunity
            WHERE Id IN :opportunityIds
              AND ShowForecastConfidencePropagateBanner__c = TRUE
            WITH SYSTEM_MODE
        ]) {
            Integer quoteCount = quoteCountsByOpportunityId.get(opportunityRecord.Id);
            if (quoteCount != null && quoteCount > 0) {
                continue;
            }

            opportunitiesToClear.add(
                new Opportunity(
                    Id = opportunityRecord.Id,
                    ShowForecastConfidencePropagateBanner__c = false,
                    PendingQuoteForecastConfidence__c = null
                )
            );
        }

        if (opportunitiesToClear.isEmpty()) {
            return;
        }

        Database.update(opportunitiesToClear, false, AccessLevel.SYSTEM_MODE);
    }

    /**
     * @description Returns banner context and applicable quotes for the LWC.
     * @param opportunityId Opportunity record Id.
     * @return Banner context for the UI.
     */
    public static BannerContext getBannerContext(Id opportunityId) {
        BannerContext context = new BannerContext();
        context.showBanner = false;
        context.quotes = new List<QuoteRow>();

        if (opportunityId == null) {
            return context;
        }

        List<Opportunity> opportunityRecords = [
            SELECT Id,
                ForecastConfidenceLevel__c,
                ShowForecastConfidencePropagateBanner__c,
                PendingQuoteForecastConfidence__c,
                IsClosed
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];

        if (opportunityRecords.isEmpty()) {
            return context;
        }

        Opportunity opportunityRecord = opportunityRecords[0];
        if (
            opportunityRecord.IsClosed == true ||
            shouldSuppressOpportunityForecastConfidenceForQuotePropagation(
                opportunityRecord.ForecastConfidenceLevel__c
            )
        ) {
            return context;
        }

        if (opportunityRecord.ShowForecastConfidencePropagateBanner__c != true) {
            return context;
        }

        context.opportunityForecastConfidence = opportunityRecord.ForecastConfidenceLevel__c;
        context.pendingQuoteForecastConfidence = opportunityRecord.PendingQuoteForecastConfidence__c;
        context.message = System.Label.OpportunityForecastConfidencePropagateMessage;

        for (Quote quoteRecord :
            QuoteSelector.selectPropagatableForecastConfidenceQuotesByOpportunityId(opportunityId)
        ) {
            QuoteRow quoteRow = new QuoteRow();
            quoteRow.id = quoteRecord.Id;
            quoteRow.quoteNumber = resolveQuoteNumber(quoteRecord);
            quoteRow.status = quoteRecord.Status;
            quoteRow.currentForecastConfidence = quoteRecord.QuoteForecastConfidence__c;
            quoteRow.pendingForecastConfidence = opportunityRecord.PendingQuoteForecastConfidence__c;
            quoteRow.selected = true;
            context.quotes.add(quoteRow);
        }

        if (context.quotes.isEmpty()) {
            return context;
        }

        context.showBanner = true;
        return context;
    }

    /**
     * @description Updates selected quotes and clears the banner fields.
     * @param opportunityId Opportunity record Id.
     * @param quoteIds Selected Quote Ids.
     */
    public static void propagateSelectedQuotes(Id opportunityId, List<Id> quoteIds) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity Id is required.');
        }

        if (quoteIds == null || quoteIds.isEmpty()) {
            throw new AuraHandledException('Select at least one quote to propagate forecast confidence.');
        }

        Opportunity opportunityRecord = [
            SELECT Id,
                PendingQuoteForecastConfidence__c,
                ShowForecastConfidencePropagateBanner__c
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];

        if (opportunityRecord.ShowForecastConfidencePropagateBanner__c != true) {
            throw new AuraHandledException('The forecast confidence propagation banner is no longer active.');
        }

        String pendingQuoteForecastConfidence = opportunityRecord.PendingQuoteForecastConfidence__c;
        if (String.isBlank(pendingQuoteForecastConfidence)) {
            throw new AuraHandledException('No pending Quote Forecast Confidence value is available.');
        }

        Set<Id> selectedQuoteIds = new Set<Id>(quoteIds);
        Set<Id> quoteIdsToUpdate = new Set<Id>();

        for (Quote quoteRecord :
            QuoteSelector.selectPropagatableForecastConfidenceQuotesByOpportunityId(opportunityId)
        ) {
            if (!selectedQuoteIds.contains(quoteRecord.Id)) {
                continue;
            }

            if (pendingQuoteForecastConfidence == quoteRecord.QuoteForecastConfidence__c) {
                continue;
            }

            quoteIdsToUpdate.add(quoteRecord.Id);
        }

        if (!quoteIdsToUpdate.isEmpty()) {
            ScOpportunityQuoteEventService.synchronizeForecastConfidenceUpdate(
                opportunityId,
                pendingQuoteForecastConfidence,
                quoteIdsToUpdate,
                UserInfo.getUserId()
            );
        }

        clearBannerFields(opportunityId);
    }

    private static void clearBannerFields(Id opportunityId) {
        try {
            Database.update(
                new Opportunity(
                    Id = opportunityId,
                    ShowForecastConfidencePropagateBanner__c = false,
                    PendingQuoteForecastConfidence__c = null
                ),
                false,
                AccessLevel.SYSTEM_MODE
            );
        } catch (Exception exceptionValue) {
            ErrorLogger.logException(exceptionValue, CLASS_NAME, 'clearBannerFields');
            throw new AuraHandledException('Unable to update the forecast confidence propagation banner.');
        }
    }

    private static String resolveQuoteNumber(Quote quoteRecord) {
        if (quoteRecord == null) {
            return '';
        }

        return quoteRecord.QuoteNumber__c;
    }

    @TestVisible
    private static Boolean shouldSuppressForecastConfidencePropagateBanner(
        Opportunity opportunityRecord,
        Opportunity oldOpportunityRecord
    ) {
        if (opportunityRecord == null || oldOpportunityRecord == null) {
            return false;
        }

        if (
            shouldSuppressOpportunityForecastConfidenceForQuotePropagation(
                opportunityRecord.ForecastConfidenceLevel__c
            )
        ) {
            return true;
        }

        if (
            isClosedOpportunityStage(resolveStageName(opportunityRecord)) ||
            isOpportunityClosing(opportunityRecord, oldOpportunityRecord)
        ) {
            return true;
        }

        return false;
    }

    private static Boolean isOpportunityClosing(
        Opportunity opportunityRecord,
        Opportunity oldOpportunityRecord
    ) {
        String newStageName = resolveStageName(opportunityRecord);
        String oldStageName = resolveStageName(oldOpportunityRecord);

        if (String.isBlank(newStageName) || newStageName == oldStageName) {
            return false;
        }

        return isClosedOpportunityStage(newStageName);
    }

    private static Boolean isClosedOpportunityStage(String stageName) {
        if (String.isBlank(stageName)) {
            return false;
        }

        String normalizedStageName = stageName.trim();
        return 'Closed Won'.equalsIgnoreCase(normalizedStageName) ||
            'Closed Lost'.equalsIgnoreCase(normalizedStageName);
    }

    private static String resolveStageName(Opportunity opportunityRecord) {
        if (opportunityRecord == null) {
            return null;
        }

        try {
            return opportunityRecord.StageName;
        } catch (System.SObjectException exceptionValue) {
            return null;
        }
    }

    @TestVisible
    private static Boolean isOpportunityForecastConfidenceWon(String opportunityForecastConfidenceLevel) {
        return matchesOpportunityForecastConfidenceLevel(
            opportunityForecastConfidenceLevel,
            OPPORTUNITY_FORECAST_CONFIDENCE_WON
        );
    }

    @TestVisible
    private static Boolean isOpportunityForecastConfidenceLost(String opportunityForecastConfidenceLevel) {
        return matchesOpportunityForecastConfidenceLevel(
            opportunityForecastConfidenceLevel,
            OPPORTUNITY_FORECAST_CONFIDENCE_LOST
        );
    }

    @TestVisible
    private static Boolean shouldSuppressOpportunityForecastConfidenceForQuotePropagation(
        String opportunityForecastConfidenceLevel
    ) {
        return isOpportunityForecastConfidenceWon(opportunityForecastConfidenceLevel) ||
            isOpportunityForecastConfidenceLost(opportunityForecastConfidenceLevel);
    }

    private static Boolean matchesOpportunityForecastConfidenceLevel(
        String opportunityForecastConfidenceLevel,
        String expectedLevel
    ) {
        return String.isNotBlank(opportunityForecastConfidenceLevel) &&
            String.isNotBlank(expectedLevel) &&
            expectedLevel.equalsIgnoreCase(opportunityForecastConfidenceLevel.trim());
    }
}