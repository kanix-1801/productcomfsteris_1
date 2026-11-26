/**
 * @description GW-4378 - Quotes looked up by Work Order for optional evaluation photos.
 */
@IsTest
private class QuoteSelectorTest {
    @IsTest
    static void selectByWorkOrderIds_nullAndEmptyReturnNoRows() {
        Test.startTest();
        List<Quote> nullResult = QuoteSelector.selectByWorkOrderIds(null);
        List<Quote> emptyResult = QuoteSelector.selectByWorkOrderIds(new Set<Id>());
        Test.stopTest();

        System.assertEquals(0, nullResult.size(), 'Null Work Order Ids return no quotes.');
        System.assertEquals(0, emptyResult.size(), 'An empty Work Order Id set returns no quotes.');
    }

    @IsTest
    static void selectByWorkOrderIds_returnsQuotesForThoseWorkOrders() {
        /********************************************
         * GIVEN
         ********************************************/
        adb_Account accountBuilder = new adb_Account().name('GW4378 Quote Query Account');
        accountBuilder.persist();
        WorkOrder included = new WorkOrder(
            Subject = 'GW4378 Included Work Order',
            Status = 'New',
            Priority = 'Medium',
            AccountId = accountBuilder.Id
        );
        WorkOrder other = new WorkOrder(
            Subject = 'GW4378 Other Work Order',
            Status = 'New',
            Priority = 'Medium',
            AccountId = accountBuilder.Id
        );
        WorkOrder unmatched = new WorkOrder(
            Subject = 'GW4378 Unmatched Work Order',
            Status = 'New',
            Priority = 'Medium',
            AccountId = accountBuilder.Id
        );
        insert new List<WorkOrder>{ included, other, unmatched };

        adb_Opportunity opportunityBuilder = new adb_Opportunity()
            .name('GW4378 Quote Query Opp')
            .account(accountBuilder);
        // Open, the first active stage, does not allow Pipeline. New Service opportunities
        // must be Discovery, which accepts the forecast value the builder already set.
        // Won is valid only for Closed Won.
        opportunityBuilder.record.put(Opportunity.StageName, 'Discovery');
        opportunityBuilder.record.put(Opportunity.Amount, 100);
        opportunityBuilder.record.put(Opportunity.CloseDate, Date.today().addDays(30));
        opportunityBuilder.record.put(Opportunity.BypassValidations__c, true);
        opportunityBuilder.persist();
        Quote includedQuote = new Quote(
            Name = 'GW4378 Included Quote',
            OpportunityId = opportunityBuilder.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            WorkOrder__c = included.Id,
            QuoteType__c = 'Trial Quote'
        );
        Quote otherQuote = new Quote(
            Name = 'GW4378 Other Quote',
            OpportunityId = opportunityBuilder.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            WorkOrder__c = other.Id,
            QuoteType__c = 'Trial Quote'
        );
        TriggerHandler.bypass('QuoteTriggerHandler');
        try {
            insert new List<Quote>{ includedQuote, otherQuote };
        } finally {
            TriggerHandler.clearBypass('QuoteTriggerHandler');
        }

        /********************************************
         * WHEN
         ********************************************/
        Test.startTest();
        List<Quote> matched = QuoteSelector.selectByWorkOrderIds(new Set<Id>{ included.Id });
        List<Quote> both = QuoteSelector.selectByWorkOrderIds(new Set<Id>{ included.Id, other.Id });
        List<Quote> none = QuoteSelector.selectByWorkOrderIds(new Set<Id>{ unmatched.Id });
        Test.stopTest();

        /********************************************
         * THEN
         ********************************************/
        System.assertEquals(1, matched.size(), 'Only quotes for the requested Work Order are returned.');
        System.assertEquals(includedQuote.Id, matched[0].Id);
        System.assertEquals(included.Id, matched[0].WorkOrder__c);
        System.assertEquals(2, both.size(), 'Every Work Order in the set is queried together.');
        System.assertEquals(0, none.size(), 'An Id that is not a related Work Order returns no quotes.');
    }
}