/**
 * @description Tests for QuoteLineItemSelector (QACBM GC-3129 + SoqlQueryBuilder bind).
 *              Quote data comes from FieldServiceQuoteTestData (Field Service quote, its opportunity and one
 *              Parts line on the standard price book).
 */
@IsTest
private class QuoteLineItemSelectorTest {
    @TestSetup
    static void setup() {
        FieldServiceQuoteTestData.Scenario scenario = FieldServiceQuoteTestData.createScenario();
        FieldServiceQuoteTestData.createQuote(scenario);
    }

    /**
     * @description The single Quote Line Item created in setup, with its parent context.
     * @return QuoteLineItem
     */
    private static QuoteLineItem getSetupLine() {
        return [
            SELECT Id, QuoteId, Quote.OpportunityId, Product2Id, Quantity
            FROM QuoteLineItem
            WHERE Product2.ProductCode = :FieldServiceQuoteTestData.PART_CODE
            LIMIT 1
        ];
    }

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
    static void testSelectQuoteLineItemById_WhenBlank_ReturnsEmpty() {
        Test.startTest();
        List<QuoteLineItem> nullId =
            QuoteLineItemSelector.selectQuoteLineItemById(null, new List<String>{ 'Id' });
        List<QuoteLineItem> nullFields =
            QuoteLineItemSelector.selectQuoteLineItemById(UserInfo.getUserId(), null);
        List<QuoteLineItem> emptyFields =
            QuoteLineItemSelector.selectQuoteLineItemById(UserInfo.getUserId(), new List<String>());
        List<QuoteLineItem> unknownId = QuoteLineItemSelector.selectQuoteLineItemById(
            UserInfo.getUserId(),
            new List<String>{ 'Id' }
        );
        Test.stopTest();
        Assert.isTrue(nullId.isEmpty());
        Assert.isTrue(nullFields.isEmpty());
        Assert.isTrue(emptyFields.isEmpty());
        Assert.isTrue(unknownId.isEmpty());
    }

    @IsTest
    static void testQuoteIdSelectors_WhenNull_ReturnEmpty() {
        /********************************************
        * SETUP
        ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            List<QuoteLineItem> emailReply = QuoteLineItemSelector.selectForQuoteEmailReplyByQuoteId(null);
            List<QuoteLineItem> approveReject = QuoteLineItemSelector.selectForApproveRejectByQuoteId(null);
            QuoteLineItem approveRejectLine = QuoteLineItemSelector.selectForApproveRejectById(null);
            List<QuoteLineItem> pricingNull = QuoteLineItemSelector.selectForPricingFrameworkByQuoteIds(null);
            List<QuoteLineItem> pricingEmpty =
                QuoteLineItemSelector.selectForPricingFrameworkByQuoteIds(new Set<Id>());
            Map<Id, QuoteLineItem> headlessNull = QuoteLineItemSelector.selectForPricingFrameworkHeadlessByIds(null);
            Map<Id, QuoteLineItem> headlessEmpty =
                QuoteLineItemSelector.selectForPricingFrameworkHeadlessByIds(new Set<Id>());
            List<QuoteLineItem> editor = QuoteLineItemSelector.selectForFieldServiceEditorByQuoteId(null);
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            Assert.isTrue(emailReply.isEmpty(), 'Null quote Id should return no email reply lines.');
            Assert.isTrue(approveReject.isEmpty(), 'Null quote Id should return no approve/reject lines.');
            Assert.isNull(approveRejectLine, 'Null line Id should return null.');
            Assert.isTrue(pricingNull.isEmpty(), 'Null quote Ids should return no pricing lines.');
            Assert.isTrue(pricingEmpty.isEmpty(), 'Empty quote Ids should return no pricing lines.');
            Assert.isTrue(headlessNull.isEmpty(), 'Null line Ids should return no headless lines.');
            Assert.isTrue(headlessEmpty.isEmpty(), 'Empty line Ids should return no headless lines.');
            Assert.isTrue(editor.isEmpty(), 'Null quote Id should return no editor lines.');
        }
    }

    @IsTest
    static void testSelectByOpportunityIds_WhenQuoteHasLines_ReturnsLines() {
        /********************************************
        * SETUP
        ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        /********************************************
        * GIVEN
        ********************************************/
        QuoteLineItem line = getSetupLine();
        Assert.isNotNull(line.Quote.OpportunityId, 'Setup quote should be linked to an opportunity.');

        System.runAs(testUser) {
            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            List<QuoteLineItem> result = QuoteLineItemSelector.selectByOpportunityIds(
                new Set<Id>{ line.Quote.OpportunityId }
            );
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            Assert.areEqual(1, result.size(), 'The opportunity quote line should be returned.');
            Assert.areEqual(line.Id, result[0].Id);
            Assert.areEqual(line.QuoteId, result[0].QuoteId);
            Assert.areEqual(line.Product2Id, result[0].Product2Id);
            Assert.areEqual(line.Quote.OpportunityId, result[0].Quote.OpportunityId);
        }
    }

    @IsTest
    static void testSelectForQuoteEmailReplyByQuoteId_WhenQuoteHasLines_ReturnsLines() {
        /********************************************
        * SETUP
        ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        /********************************************
        * GIVEN
        ********************************************/
        QuoteLineItem line = getSetupLine();

        System.runAs(testUser) {
            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            List<QuoteLineItem> result = QuoteLineItemSelector.selectForQuoteEmailReplyByQuoteId(line.QuoteId);
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            Assert.areEqual(1, result.size(), 'The quote line should be returned.');
            Assert.areEqual(line.Id, result[0].Id);
            Assert.areEqual(line.QuoteId, result[0].QuoteId);
            Assert.areEqual(line.Quantity, result[0].Quantity);
            Assert.areEqual(FieldServiceQuoteTestData.PART_CODE, result[0].Product2.ProductCode);
        }
    }

    @IsTest
    static void testSelectForApproveRejectByQuoteId_WhenQuoteHasLines_ReturnsLines() {
        /********************************************
        * SETUP
        ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        /********************************************
        * GIVEN
        ********************************************/
        QuoteLineItem line = getSetupLine();

        System.runAs(testUser) {
            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            List<QuoteLineItem> result = QuoteLineItemSelector.selectForApproveRejectByQuoteId(line.QuoteId);
            List<QuoteLineItem> unknown =
                QuoteLineItemSelector.selectForApproveRejectByQuoteId(UserInfo.getUserId());
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            Assert.areEqual(1, result.size(), 'The quote line should be returned.');
            Assert.areEqual(line.Id, result[0].Id);
            Assert.areEqual(line.QuoteId, result[0].QuoteId);
            Assert.areEqual(line.Quantity, result[0].Quantity);
            Assert.isTrue(unknown.isEmpty(), 'An unknown quote Id should return no lines.');
        }
    }

    @IsTest
    static void testSelectForApproveRejectById_WhenLineExists_ReturnsLine() {
        /********************************************
        * SETUP
        ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        /********************************************
        * GIVEN
        ********************************************/
        QuoteLineItem line = getSetupLine();

        System.runAs(testUser) {
            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            QuoteLineItem result = QuoteLineItemSelector.selectForApproveRejectById(line.Id);
            QuoteLineItem unknown = QuoteLineItemSelector.selectForApproveRejectById(UserInfo.getUserId());
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            Assert.isNotNull(result, 'The quote line should be returned.');
            Assert.areEqual(line.Id, result.Id);
            Assert.areEqual(line.QuoteId, result.QuoteId);
            Assert.isNull(unknown, 'An unknown line Id should return null.');
        }
    }

    @IsTest
    static void testSelectQuoteLineItemById_WhenLineExists_ReturnsRequestedFields() {
        /********************************************
        * SETUP
        ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        /********************************************
        * GIVEN
        ********************************************/
        QuoteLineItem line = getSetupLine();

        System.runAs(testUser) {
            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            List<QuoteLineItem> result = QuoteLineItemSelector.selectQuoteLineItemById(
                line.Id,
                new List<String>{ 'Id', 'QuoteId', 'Quantity' }
            );
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            Assert.areEqual(1, result.size(), 'The quote line should be returned.');
            Assert.areEqual(line.Id, result[0].Id);
            Assert.areEqual(line.QuoteId, result[0].QuoteId);
            Assert.areEqual(line.Quantity, result[0].Quantity);
        }
    }

    @IsTest
    static void testSelectForPricingFrameworkByQuoteIds_WhenQuoteHasLines_ReturnsLines() {
        /********************************************
        * SETUP
        ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        /********************************************
        * GIVEN
        ********************************************/
        QuoteLineItem line = getSetupLine();

        System.runAs(testUser) {
            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            List<QuoteLineItem> result =
                QuoteLineItemSelector.selectForPricingFrameworkByQuoteIds(new Set<Id>{ line.QuoteId });
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            Assert.areEqual(1, result.size(), 'The quote line should be returned.');
            Assert.areEqual(line.Id, result[0].Id);
            Assert.areEqual(line.Quantity, result[0].Quantity);
            Assert.areEqual(FieldServiceQuoteTestData.PART_CODE, result[0].Product2.ProductCode);
        }
    }

    @IsTest
    static void testSelectForPricingFrameworkHeadlessByIds_WhenLineExists_ReturnsLineByIdWithContext() {
        /********************************************
        * SETUP
        ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        /********************************************
        * GIVEN
        ********************************************/
        QuoteLineItem line = getSetupLine();

        System.runAs(testUser) {
            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            Map<Id, QuoteLineItem> result =
                QuoteLineItemSelector.selectForPricingFrameworkHeadlessByIds(new Set<Id>{ line.Id });
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            Assert.areEqual(1, result.size(), 'The quote line should be returned.');
            QuoteLineItem selected = result.get(line.Id);
            Assert.isNotNull(selected, 'The result should be keyed by line Id.');
            Assert.areEqual(line.QuoteId, selected.QuoteId);
            Assert.areEqual(line.Product2Id, selected.Product2Id);
            Assert.areEqual(Test.getStandardPricebookId(), selected.PricebookEntry.Pricebook2Id);
            Assert.areEqual(Test.getStandardPricebookId(), selected.Quote.Pricebook2Id);
            Assert.areEqual(FieldServiceQuoteTestData.CURRENCY_CODE, selected.Quote.CurrencyIsoCode);
        }
    }

    @IsTest
    static void testSelectForFieldServiceEditorByQuoteId_WhenQuoteHasLines_ReturnsLines() {
        /********************************************
        * SETUP
        ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        /********************************************
        * GIVEN
        ********************************************/
        QuoteLineItem line = getSetupLine();

        System.runAs(testUser) {
            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            List<QuoteLineItem> result = QuoteLineItemSelector.selectForFieldServiceEditorByQuoteId(line.QuoteId);
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            Assert.areEqual(1, result.size(), 'The quote line should be returned.');
            Assert.areEqual(line.Id, result[0].Id);
            Assert.areEqual(line.Product2Id, result[0].Product2Id);
            Assert.areEqual(FieldServiceQuoteTestData.PART_CODE, result[0].Product2.ProductCode);
            Assert.areEqual(FieldServiceQuoteService.LINE_TYPE_PARTS, result[0].LineType__c);
            Assert.areEqual(line.Quantity, result[0].Quantity);
        }
    }
}