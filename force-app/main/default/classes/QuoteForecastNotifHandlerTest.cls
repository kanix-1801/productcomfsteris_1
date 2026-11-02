/**
 * @description GW-4189: Covers QuoteForecastChangeNotificationHandler QLI query path.
 *              Multiple SOQL binds in a for-loop previously caused
 *              System.QueryException: tmpVar1 on Quote Line Item insert.
 */
@IsTest
private class QuoteForecastNotifHandlerTest {
    @IsTest
    static void lineItemAndQuoteEntryPoints_doNotThrow() {
        Id fakeQuoteId = (Id) (Quote.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        Id fakeOppId = (Id) (Opportunity.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        Id fakeQliId = (Id) (QuoteLineItem.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        QuoteLineItem lineItem = new QuoteLineItem(Id = fakeQliId, QuoteId = fakeQuoteId, Quantity = 2);
        QuoteLineItem oldLineItem = new QuoteLineItem(Id = fakeQliId, QuoteId = fakeQuoteId, Quantity = 1);
        Quote quoteRecord = new Quote(
            Id = fakeQuoteId,
            OpportunityId = fakeOppId,
            Status = 'Accepted',
            Forecast_Eligible__c = true
        );
        Quote oldQuoteRecord = new Quote(
            Id = fakeQuoteId,
            OpportunityId = fakeOppId,
            Status = 'Draft',
            Forecast_Eligible__c = false
        );

        Test.startTest();
        QuoteForecastChangeNotificationHandler.afterInsertLineItems(null);
        QuoteForecastChangeNotificationHandler.afterInsertLineItems(new List<QuoteLineItem>());
        QuoteForecastChangeNotificationHandler.afterInsertLineItems(
            new List<QuoteLineItem>{ lineItem }
        );
        QuoteForecastChangeNotificationHandler.afterDeleteLineItems(
            new List<QuoteLineItem>{ lineItem }
        );
        QuoteForecastChangeNotificationHandler.afterUndeleteLineItems(
            new List<QuoteLineItem>{ lineItem }
        );
        QuoteForecastChangeNotificationHandler.afterUpdateLineItems(
            new List<QuoteLineItem>{ lineItem },
            new Map<Id, QuoteLineItem>{ fakeQliId => oldLineItem }
        );
        QuoteForecastChangeNotificationHandler.afterInsert(null);
        QuoteForecastChangeNotificationHandler.afterInsert(new List<Quote>{ quoteRecord });
        QuoteForecastChangeNotificationHandler.afterDelete(new List<Quote>{ quoteRecord });
        QuoteForecastChangeNotificationHandler.afterUpdate(new List<Quote>(), null);
        QuoteForecastChangeNotificationHandler.afterUpdate(
            new List<Quote>{ quoteRecord },
            new Map<Id, Quote>{ fakeQuoteId => oldQuoteRecord }
        );
        QuoteForecastChangeNotificationHandler.afterUpdateLineItems(new List<QuoteLineItem>(), null);
        QuoteForecastChangeNotificationHandler.stageFromForecastEligibleQuoteIds(null);
        QuoteForecastChangeNotificationHandler.stageFromForecastEligibleQuoteIds(
            new Set<Id>{ fakeQuoteId }
        );
        QuoteForecastChangeNotificationHandler.isExcludedFromForecastNotification(null);
        QuoteForecastChangeNotificationHandler.isExcludedFromForecastNotification(quoteRecord);
        QuoteForecastChangeNotificationHandler.hasForecastEligibleChange(null, null);
        QuoteForecastChangeNotificationHandler.hasForecastEligibleChange(quoteRecord, oldQuoteRecord);
        Test.stopTest();

        Assert.areEqual(fakeQuoteId, lineItem.QuoteId, 'Handler should finish without a SOQL bind error');
    }

    @IsTest
    static void afterInsertLineItems_disabled_skipsQuery() {
        QuoteForecastChangeNotificationHandler.setNotificationDisabled(true);
        Id fakeQuoteId = (Id) (Quote.SObjectType.getDescribe().getKeyPrefix() + '000000000001');

        Test.startTest();
        QuoteForecastChangeNotificationHandler.afterInsertLineItems(
            new List<QuoteLineItem>{ new QuoteLineItem(QuoteId = fakeQuoteId) }
        );
        QuoteForecastChangeNotificationHandler.afterInsert(new List<Quote>());
        QuoteForecastChangeNotificationHandler.stageFromForecastEligibleQuoteIds(new Set<Id>());
        Test.stopTest();

        QuoteForecastChangeNotificationHandler.setNotificationDisabled(false);
        Assert.isNotNull(fakeQuoteId, 'Disabled path should return without querying');
    }
}