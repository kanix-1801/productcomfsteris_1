/**
 * @description Tests for Sprint 9 QuoteLineItemSelector methods
 *              (GW-3600 / GW-5102 / GW-5333 / GW-4585).
 */
@IsTest
private class QuoteLineItemSelectorTest {
    @IsTest
    static void testConstructor_bindsQuoteLineItemObject() {
        Test.startTest();
        QuoteLineItemSelector selector = new QuoteLineItemSelector();
        Test.stopTest();
        Assert.isNotNull(selector);
    }

    @IsTest
    static void testSelectByOpportunityIds_WhenBlankOrUnknown_ReturnsEmpty() {
        Test.startTest();
        List<QuoteLineItem> nullIds = QuoteLineItemSelector.selectByOpportunityIds(null);
        List<QuoteLineItem> emptyIds =
            QuoteLineItemSelector.selectByOpportunityIds(new Set<Id>());
        List<QuoteLineItem> unknownIds = QuoteLineItemSelector.selectByOpportunityIds(
            new Set<Id>{ UserInfo.getUserId() }
        );
        Test.stopTest();
        Assert.isTrue(nullIds.isEmpty());
        Assert.isTrue(emptyIds.isEmpty());
        Assert.isTrue(unknownIds.isEmpty());
    }

    @IsTest
    static void testSelectForQuoteEmailReplyByQuoteId_WhenNull_ReturnsEmpty() {
        Test.startTest();
        List<QuoteLineItem> results = QuoteLineItemSelector.selectForQuoteEmailReplyByQuoteId(null);
        Test.stopTest();
        Assert.isTrue(results.isEmpty());
    }

    @IsTest
    static void testSelectForApproveRejectByQuoteId_WhenNull_ReturnsEmpty() {
        Test.startTest();
        List<QuoteLineItem> results = QuoteLineItemSelector.selectForApproveRejectByQuoteId(null);
        Test.stopTest();
        Assert.isTrue(results.isEmpty());
    }

    @IsTest
    static void testSelectForApproveRejectById_WhenNull_ReturnsNull() {
        Test.startTest();
        QuoteLineItem result = QuoteLineItemSelector.selectForApproveRejectById(null);
        Test.stopTest();
        Assert.isNull(result);
    }

    @IsTest
    static void testSelectForPricingFrameworkByQuoteIds_WhenBlank_ReturnsEmpty() {
        Test.startTest();
        List<QuoteLineItem> nullIds = QuoteLineItemSelector.selectForPricingFrameworkByQuoteIds(null);
        List<QuoteLineItem> emptyIds =
            QuoteLineItemSelector.selectForPricingFrameworkByQuoteIds(new Set<Id>());
        Test.stopTest();
        Assert.isTrue(nullIds.isEmpty());
        Assert.isTrue(emptyIds.isEmpty());
    }

    @IsTest
    static void testSelectForPricingFrameworkHeadlessByIds_WhenBlank_ReturnsEmpty() {
        Test.startTest();
        Map<Id, QuoteLineItem> nullIds =
            QuoteLineItemSelector.selectForPricingFrameworkHeadlessByIds(null);
        Map<Id, QuoteLineItem> emptyIds =
            QuoteLineItemSelector.selectForPricingFrameworkHeadlessByIds(new Set<Id>());
        Test.stopTest();
        Assert.isTrue(nullIds.isEmpty());
        Assert.isTrue(emptyIds.isEmpty());
    }

    @IsTest
    static void testSprint9Selectors_WhenQuoteLineExists_ReturnsRows() {
        QuoteLineItem lineItem = createQuoteLineItem();

        Test.startTest();
        List<QuoteLineItem> emailRows =
            QuoteLineItemSelector.selectForQuoteEmailReplyByQuoteId(lineItem.QuoteId);
        List<QuoteLineItem> approveRows =
            QuoteLineItemSelector.selectForApproveRejectByQuoteId(lineItem.QuoteId);
        QuoteLineItem approveById =
            QuoteLineItemSelector.selectForApproveRejectById(lineItem.Id);
        List<QuoteLineItem> pricingRows =
            QuoteLineItemSelector.selectForPricingFrameworkByQuoteIds(
                new Set<Id>{ lineItem.QuoteId }
            );
        Map<Id, QuoteLineItem> headlessRows =
            QuoteLineItemSelector.selectForPricingFrameworkHeadlessByIds(
                new Set<Id>{ lineItem.Id }
            );
        Test.stopTest();

        Assert.isFalse(emailRows.isEmpty());
        Assert.areEqual(lineItem.Id, emailRows[0].Id);
        Assert.isFalse(approveRows.isEmpty());
        Assert.areEqual(lineItem.Id, approveRows[0].Id);
        Assert.isNotNull(approveById);
        Assert.areEqual(lineItem.Id, approveById.Id);
        Assert.isFalse(pricingRows.isEmpty());
        Assert.areEqual(lineItem.Id, pricingRows[0].Id);
        Assert.isTrue(headlessRows.containsKey(lineItem.Id));
    }

    private static QuoteLineItem createQuoteLineItem() {
        adb_Product2 product = new adb_Product2().name('QLI Selector Product');
        new adb_PricebookEntry().product(product).unitPrice(1);
        adb_Account account = new adb_Account()
            .name('QLI Selector Account')
            .sourceSystemId('QLI-SEL-ACCT');
        adb_Contact contact = new adb_Contact().lastName('QLI Selector Contact').account(account);
        adb_Opportunity opportunity = new adb_Opportunity()
            .name('QLI Selector Opportunity')
            .account(account)
            .primaryContact(contact);
        adb_Quote quoteRecord = new adb_Quote().name('QLI Selector Quote').opportunity(opportunity);
        adb_Asset assetRecord = new adb_Asset()
            .name('QLI Selector Asset')
            .account(account)
            .product(product);
        adb_QuoteAction quoteAction = new adb_QuoteAction()
            .quote(quoteRecord)
            .sourceAsset(assetRecord)
            .type('Add');
        QuoteAction persistedAction = (QuoteAction) quoteAction.persist();

        PricebookEntry pricebookEntry = [
            SELECT Id
            FROM PricebookEntry
            WHERE Pricebook2Id = :Test.getStandardPricebookId()
                AND Product2.Name = 'QLI Selector Product'
            LIMIT 1
        ];

        QuoteForecastChangeNotificationHandler.setNotificationDisabled(true);
        return (QuoteLineItem) new adb_QuoteLineItem()
            .quoteId(persistedAction.QuoteId)
            .pricebookEntryId(pricebookEntry.Id)
            .quantity(1)
            .unitPrice(1)
            .persist();
    }
}