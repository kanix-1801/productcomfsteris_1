/**
 * @author Himanshu Chaurasia
 * @date 2026/09/09
 *
 * @description Stages and processes Closed Lost quote closure prompts for Opportunities.
 */
public with sharing class OppClosedLostQuoteService {
    private static final String CLASS_NAME = 'OppClosedLostQuoteService';
    private static final String CLOSED_LOST_STAGE = 'Closed Lost';

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
     * @description Sets IsOpportunityClosed__c when an Opportunity moves to Closed Lost with open quotes.
     * @param newOpportunities Trigger.new Opportunity rows.
     * @param oldOpportunityMap Trigger.oldMap Opportunity rows.
     */
    public static void stageClosedLostQuoteBanner(
        List<Opportunity> newOpportunities,
        Map<Id, Opportunity> oldOpportunityMap
    ) {
        if (newOpportunities == null || newOpportunities.isEmpty() || oldOpportunityMap == null) {
            return;
        }

        Set<Id> closedLostOpportunityIds = new Set<Id>();

        for (Opportunity opportunityRecord : newOpportunities) {
            Opportunity oldOpportunityRecord = oldOpportunityMap.get(opportunityRecord.Id);

            if (oldOpportunityRecord == null) {
                continue;
            }

            if (!isTransitionToClosedLost(opportunityRecord, oldOpportunityRecord)) {
                continue;
            }

            closedLostOpportunityIds.add(opportunityRecord.Id);
        }

        if (closedLostOpportunityIds.isEmpty()) {
            return;
        }

        Map<Id, Integer> openQuoteCountsByOpportunityId =
            QuoteSelector.countOpenSalesConnectionQuotesByOpportunityIds(closedLostOpportunityIds);

        for (Opportunity opportunityRecord : newOpportunities) {
            if (!closedLostOpportunityIds.contains(opportunityRecord.Id)) {
                continue;
            }

            Integer openQuoteCount = openQuoteCountsByOpportunityId.get(opportunityRecord.Id);
            if (openQuoteCount == null || openQuoteCount == 0) {
                opportunityRecord.IsOpportunityClosed__c = false;
                continue;
            }

            opportunityRecord.IsOpportunityClosed__c = true;
        }
    }

    /**
     * @description Clears stale Closed Lost banner flags when open quotes no longer exist.
     * @param opportunityIds Opportunity record Ids affected by Quote changes.
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
              AND IsOpportunityClosed__c = TRUE
            WITH SYSTEM_MODE
        ]) {
            Integer openQuoteCount = openQuoteCountsByOpportunityId.get(opportunityRecord.Id);
            if (openQuoteCount != null && openQuoteCount > 0) {
                continue;
            }

            opportunitiesToClear.add(
                new Opportunity(
                    Id = opportunityRecord.Id,
                    IsOpportunityClosed__c = false
                )
            );
        }

        if (opportunitiesToClear.isEmpty()) {
            return;
        }

        Database.update(opportunitiesToClear, false, AccessLevel.SYSTEM_MODE);
    }

    /**
     * @description Returns banner context for the Closed Lost quote closure LWC.
     * @param opportunityId Opportunity record Id.
     * @return Banner context for the UI.
     */
    public static BannerContext getBannerContext(Id opportunityId) {
        BannerContext context = new BannerContext();
        context.showBanner = false;
        context.openQuoteCount = 0;
        context.quotes = new List<QuoteRow>();

        if (opportunityId == null) {
            return context;
        }

        List<Opportunity> opportunityRecords = [
            SELECT Id, IsOpportunityClosed__c, StageName
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];

        if (opportunityRecords.isEmpty()) {
            return context;
        }

        Opportunity opportunityRecord = opportunityRecords[0];
        if (opportunityRecord.IsOpportunityClosed__c != true) {
            return context;
        }

        context.message = System.Label.OpportunityClosedLostQuoteBannerMessage;
        context.confirmMessage = System.Label.OpportunityClosedLostQuoteConfirmMessage;

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
     * @description Clears a stale Closed Lost banner flag when no open SC quotes remain (non-cacheable; may DML).
     */
    public static void reconcileStaleBanner(Id opportunityId) {
        if (opportunityId == null) {
            return;
        }

        List<Opportunity> opportunityRecords = [
            SELECT Id, IsOpportunityClosed__c
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];

        if (opportunityRecords.isEmpty() || opportunityRecords[0].IsOpportunityClosed__c != true) {
            return;
        }

        if (!QuoteSelector.selectOpenSalesConnectionQuotesByOpportunityId(opportunityId).isEmpty()) {
            return;
        }

        clearBannerFlag(opportunityId);
    }

    /**
     * @description Closes all open Sales Connection quotes for an Opportunity.
     * @param opportunityId Opportunity record Id.
     */
    public static void closeAllOpenQuotes(Id opportunityId) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity Id is required.');
        }

        Opportunity opportunityRecord = [
            SELECT Id, IsOpportunityClosed__c
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];

        if (opportunityRecord.IsOpportunityClosed__c != true) {
            throw new AuraHandledException('The Closed Lost quote closure banner is no longer active.');
        }

        Set<Id> quoteIdsToClose = new Set<Id>();

        for (Quote quoteRecord : QuoteSelector.selectOpenSalesConnectionQuotesByOpportunityId(opportunityId)) {
            quoteIdsToClose.add(quoteRecord.Id);
        }

        if (!quoteIdsToClose.isEmpty()) {
            ScOpportunityQuoteEventService.synchronizeClosedLostQuoteClosure(
                opportunityId,
                quoteIdsToClose,
                UserInfo.getUserId()
            );
        }

        clearBannerFlag(opportunityId);
    }

    /**
     * @description Dismisses the banner without closing quotes.
     * @param opportunityId Opportunity record Id.
     */
    public static void dismissBanner(Id opportunityId) {
        if (opportunityId == null) {
            return;
        }

        clearBannerFlag(opportunityId);
    }

    private static void clearBannerFlag(Id opportunityId) {
        try {
            Database.update(
                new Opportunity(
                    Id = opportunityId,
                    IsOpportunityClosed__c = false
                ),
                false,
                AccessLevel.SYSTEM_MODE
            );
        } catch (Exception exceptionValue) {
            ErrorLogger.logException(exceptionValue, CLASS_NAME, 'clearBannerFlag');
            throw new AuraHandledException('Unable to update the Closed Lost quote closure banner.');
        }
    }

    private static Boolean isTransitionToClosedLost(
        Opportunity opportunityRecord,
        Opportunity oldOpportunityRecord
    ) {
        return CLOSED_LOST_STAGE.equalsIgnoreCase(opportunityRecord.StageName) &&
            !CLOSED_LOST_STAGE.equalsIgnoreCase(oldOpportunityRecord.StageName);
    }
}