/**
 * @author Himanshu Chaurasia
 * @date 2026/10/14
 *
 * @description GC-3457 UC3 - Stages and processes quote closure after Capital → EPP conversion.
 */
public with sharing class OppEppConversionQuoteService {
    private static final String CLASS_NAME = 'OppEppConversionQuoteService';
    @TestVisible
    private static final String CONVERTED_TO_EPP_DISPOSITION = 'Converted to EPP';

    public class QuoteRow {
        @AuraEnabled
        public Id id;

        @AuraEnabled
        public String quoteNumber;

        @AuraEnabled
        public String status;

        @AuraEnabled
        public Boolean forecastEligible;
    }

    public class BannerContext {
        @AuraEnabled
        public Boolean showBanner;

        @AuraEnabled
        public String message;

        @AuraEnabled
        public String confirmMessage;

        @AuraEnabled
        public Integer openQuoteCount;

        @AuraEnabled
        public List<QuoteRow> quotes;
    }

    /**
     * @description Sets PendingEppConversionQuoteClosure__c when open SC quotes exist after conversion.
     * @param opportunityId Converted EPP Opportunity Id.
     */
    public static void stageBannerAfterConversion(Id opportunityId) {
        if (opportunityId == null) {
            return;
        }

        Integer openQuoteCount =
            QuoteSelector.countOpenSalesConnectionQuotesByOpportunityIds(new Set<Id>{ opportunityId })
                .get(opportunityId);

        Database.update(
            new Opportunity(
                Id = opportunityId,
                PendingEppConversionQuoteClosure__c = openQuoteCount != null && openQuoteCount > 0
            ),
            false,
            AccessLevel.SYSTEM_MODE
        );
    }

    /**
     * @description Clears stale EPP conversion banner flags when open quotes no longer exist.
     */
    public static void syncBannerStateForOpportunityIds(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return;
        }

        Map<Id, Integer> openQuoteCountsByOpportunityId =
            QuoteSelector.countOpenSalesConnectionQuotesByOpportunityIds(opportunityIds);
        List<Opportunity> opportunitiesToClear = new List<Opportunity>();

        for (Opportunity opportunityRecord : [
            SELECT Id
            FROM Opportunity
            WHERE Id IN :opportunityIds
              AND PendingEppConversionQuoteClosure__c = TRUE
            WITH SYSTEM_MODE
        ]) {
            Integer openQuoteCount = openQuoteCountsByOpportunityId.get(opportunityRecord.Id);
            if (openQuoteCount != null && openQuoteCount > 0) {
                continue;
            }

            opportunitiesToClear.add(
                new Opportunity(
                    Id = opportunityRecord.Id,
                    PendingEppConversionQuoteClosure__c = false
                )
            );
        }

        if (!opportunitiesToClear.isEmpty()) {
            Database.update(opportunitiesToClear, false, AccessLevel.SYSTEM_MODE);
        }
    }

    public static BannerContext getBannerContext(Id opportunityId) {
        BannerContext context = new BannerContext();
        context.showBanner = false;
        context.openQuoteCount = 0;
        context.quotes = new List<QuoteRow>();

        if (opportunityId == null) {
            return context;
        }

        List<Opportunity> opportunityRecords = [
            SELECT Id, PendingEppConversionQuoteClosure__c
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];

        if (opportunityRecords.isEmpty() || opportunityRecords[0].PendingEppConversionQuoteClosure__c != true) {
            return context;
        }

        context.message = System.Label.OpportunityEppConversionQuoteBannerMessage;
        context.confirmMessage = System.Label.OpportunityEppConversionQuoteConfirmMessage;

        for (Quote quoteRecord : QuoteSelector.selectOpenSalesConnectionQuotesByOpportunityId(opportunityId)) {
            QuoteRow quoteRow = new QuoteRow();
            quoteRow.id = quoteRecord.Id;
            quoteRow.quoteNumber = quoteRecord.QuoteNumber__c;
            quoteRow.status = quoteRecord.Status;
            quoteRow.forecastEligible = quoteRecord.Forecast_Eligible__c == true;
            context.quotes.add(quoteRow);
        }

        context.openQuoteCount = context.quotes.size();
        if (context.openQuoteCount == 0) {
            return context;
        }

        context.showBanner = true;
        return context;
    }

    /**
     * @description Clears a stale banner flag when no open SC quotes remain (non-cacheable; may DML).
     */
    public static void reconcileStaleBanner(Id opportunityId) {
        if (opportunityId == null) {
            return;
        }

        List<Opportunity> opportunityRecords = [
            SELECT Id, PendingEppConversionQuoteClosure__c
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];

        if (
            opportunityRecords.isEmpty() ||
            opportunityRecords[0].PendingEppConversionQuoteClosure__c != true
        ) {
            return;
        }

        if (!QuoteSelector.selectOpenSalesConnectionQuotesByOpportunityId(opportunityId).isEmpty()) {
            return;
        }

        clearBannerFlag(opportunityId);
    }

    /**
     * @description Closes only the quotes the user selected during Convert to EPP.
     *              Quotes that are not open Sales Connection quotes on this Opportunity are ignored.
     */
    public static void closeSelectedQuotes(Id opportunityId, Set<Id> quoteIds) {
        if (opportunityId == null || quoteIds == null || quoteIds.isEmpty()) {
            return;
        }

        Set<Id> openQuoteIds = new Map<Id, Quote>(
            QuoteSelector.selectOpenSalesConnectionQuotesByOpportunityId(opportunityId)
        ).keySet();
        quoteIds.retainAll(openQuoteIds);
        if (quoteIds.isEmpty()) {
            return;
        }

        ScOpportunityQuoteEventService.synchronizeEppConversionQuoteClosure(
            opportunityId,
            quoteIds,
            UserInfo.getUserId()
        );
        markQuotesConvertedToEpp(quoteIds);
    }

    public static void closeAllOpenQuotes(Id opportunityId) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity Id is required.');
        }

        Opportunity opportunityRecord = [
            SELECT Id, PendingEppConversionQuoteClosure__c
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];

        if (opportunityRecord.PendingEppConversionQuoteClosure__c != true) {
            throw new AuraHandledException('The EPP conversion quote closure banner is no longer active.');
        }

        Set<Id> quoteIdsToClose = new Set<Id>();
        for (Quote quoteRecord : QuoteSelector.selectOpenSalesConnectionQuotesByOpportunityId(opportunityId)) {
            quoteIdsToClose.add(quoteRecord.Id);
        }

        if (!quoteIdsToClose.isEmpty()) {
            ScOpportunityQuoteEventService.synchronizeEppConversionQuoteClosure(
                opportunityId,
                quoteIdsToClose,
                UserInfo.getUserId()
            );
            markQuotesConvertedToEpp(quoteIdsToClose);
        }

        clearBannerFlag(opportunityId);
    }

    public static void dismissBanner(Id opportunityId) {
        if (opportunityId == null) {
            return;
        }

        clearBannerFlag(opportunityId);
    }

    private static void markQuotesConvertedToEpp(Set<Id> quoteIds) {
        if (quoteIds == null || quoteIds.isEmpty()) {
            return;
        }

        List<Quote> quotesToUpdate = new List<Quote>();
        for (Quote quoteRecord : [
            SELECT Id
            FROM Quote
            WHERE Id IN :quoteIds
              AND Status = :QuoteSelector.CLOSED_STATUS_VALUE
            WITH SYSTEM_MODE
        ]) {
            quotesToUpdate.add(
                new Quote(
                    Id = quoteRecord.Id,
                    ClosureDisposition__c = CONVERTED_TO_EPP_DISPOSITION,
                    Forecast_Eligible__c = false
                )
            );
        }

        if (quotesToUpdate.isEmpty()) {
            return;
        }

        Database.SaveResult[] saveResults = Database.update(
            quotesToUpdate,
            false,
            AccessLevel.SYSTEM_MODE
        );
        for (Database.SaveResult saveResult : saveResults) {
            if (saveResult.isSuccess()) {
                continue;
            }
            String failureDetail = saveResult.getErrors().isEmpty()
                ? 'Unable to record the EPP conversion quote disposition.'
                : saveResult.getErrors()[0].getMessage();
            AuraHandledException dispositionException = new AuraHandledException(failureDetail);
            dispositionException.setMessage(failureDetail);
            throw dispositionException;
        }
    }

    private static void clearBannerFlag(Id opportunityId) {
        try {
            Database.update(
                new Opportunity(
                    Id = opportunityId,
                    PendingEppConversionQuoteClosure__c = false
                ),
                false,
                AccessLevel.SYSTEM_MODE
            );
        } catch (Exception exceptionValue) {
            ErrorLogger.logException(exceptionValue, CLASS_NAME, 'clearBannerFlag');
            throw new AuraHandledException('Unable to update the EPP conversion quote closure banner.');
        }
    }
}