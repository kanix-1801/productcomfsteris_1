/**
 * @description GW-5892 / GW-6600: Tests for FieldServiceQuoteController.
 * @see FieldServiceQuoteController
 */
@IsTest
private class FieldServiceQuoteControllerTest {
    private static Id createQuote(FieldServiceQuoteTestData.Scenario scenario) {
        return FieldServiceQuoteService.createFromWorkOrder(scenario.workOrder.Id).quoteId;
    }

    private static FieldServiceQuoteController.LineView newLine(String lineType, Decimal quantity) {
        FieldServiceQuoteController.LineView line = new FieldServiceQuoteController.LineView();
        line.lineType = lineType;
        line.quantity = quantity;
        return line;
    }

    @IsTest
    static void getQuote_returnsHeaderLinesAndRateList() {
        FieldServiceQuoteTestData.Scenario scenario = FieldServiceQuoteTestData.createScenario();
        Id quoteId = createQuote(scenario);

        Test.startTest();
        FieldServiceQuoteController.QuoteView view = FieldServiceQuoteController.getQuote(quoteId);
        Test.stopTest();

        System.assertEquals(quoteId, view.header.quoteId);
        System.assertEquals(scenario.workOrder.Id, view.header.workOrderId);
        System.assertEquals('GW5892 Customer', view.header.accountName);
        System.assertEquals(FieldServiceQuoteService.PRICING_NOT_PRICED, view.header.pricingStatus);
        System.assertEquals(1, view.lines.size());
        System.assertEquals(FieldServiceQuoteTestData.PART_CODE, view.lines[0].productCode);
        System.assertEquals(scenario.rateList.Id, view.rateList.rateListId);
        System.assertEquals(150, view.rateList.laborHour);
        System.assert(!view.statusOptions.isEmpty());
        System.assert(!view.expenseTypeOptions.isEmpty());
        System.assertNotEquals(null, view.expenseProduct);
    }

    @IsTest
    static void saveQuote_addsUpdatesAndDeletesLines() {
        FieldServiceQuoteTestData.Scenario scenario = FieldServiceQuoteTestData.createScenario();
        Id quoteId = createQuote(scenario);
        FieldServiceQuoteController.QuoteView view = FieldServiceQuoteController.getQuote(quoteId);
        Id existingPartLineId = view.lines[0].id;

        FieldServiceQuoteController.LineView labor = newLine(FieldServiceQuoteService.LINE_TYPE_LABOR, 3);
        labor.rate = 'Standard';
        labor.description = 'Replace door gasket';

        FieldServiceQuoteController.LineView zoneTravel = newLine(FieldServiceQuoteService.LINE_TYPE_TRAVEL, 5);
        zoneTravel.travelType = 'Travel Zone 1';
        zoneTravel.rate = 'Standard';

        FieldServiceQuoteController.LineView expense = newLine(FieldServiceQuoteService.LINE_TYPE_EXPENSE, 1);
        expense.expenseType = 'Parking';
        expense.unitPrice = 20;

        FieldServiceQuoteController.SavePayload payload = new FieldServiceQuoteController.SavePayload();
        payload.status = 'Draft';
        payload.ownerId = UserInfo.getUserId();
        payload.shipToId = scenario.account.Id;
        payload.lines = new List<FieldServiceQuoteController.LineView>{ labor, zoneTravel, expense };
        payload.deletedLineIds = new List<Id>{ existingPartLineId };

        Test.startTest();
        FieldServiceQuoteController.QuoteView saved = FieldServiceQuoteController.saveQuote(
            quoteId,
            JSON.serialize(payload)
        );
        Test.stopTest();

        System.assertEquals(3, saved.lines.size());
        Map<String, QuoteLineItem> lineByType = new Map<String, QuoteLineItem>();
        for (QuoteLineItem record : [
            SELECT LineType__c, Quantity, Rate__c, TravelType__c, ExpenseType__c, UnitPrice, Description,
                Product2.ProductCode
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
        ]) {
            lineByType.put(record.LineType__c, record);
        }
        System.assertEquals(System.Label.FS_Quote_Labor_Product_Code, lineByType.get('Labor').Product2.ProductCode);
        System.assertEquals('Standard', lineByType.get('Labor').Rate__c);
        System.assertEquals(3, lineByType.get('Labor').Quantity);
        System.assertEquals(1, lineByType.get('Travel').Quantity, 'Zone travel is a flat amount');
        System.assertEquals(null, lineByType.get('Travel').Rate__c, 'Zone travel has no rate');
        System.assertEquals('Parking', lineByType.get('Expense').ExpenseType__c);
        System.assertEquals(20, lineByType.get('Expense').UnitPrice, 'Expense unit price is user entered');
        System.assert(!lineByType.containsKey('Parts'), 'Deleted part line is gone');
    }

    @IsTest
    static void saveQuote_changedLinesOnPricedQuote_setsRepricingRequired() {
        FieldServiceQuoteTestData.Scenario scenario = FieldServiceQuoteTestData.createScenario();
        Id quoteId = createQuote(scenario);
        update new Quote(Id = quoteId, PricingStatus__c = FieldServiceQuoteService.PRICING_PRICED);
        FieldServiceQuoteController.QuoteView view = FieldServiceQuoteController.getQuote(quoteId);
        view.lines[0].quantity = 5;

        FieldServiceQuoteController.SavePayload payload = new FieldServiceQuoteController.SavePayload();
        payload.status = view.header.status;
        payload.ownerId = view.header.ownerId;
        payload.lines = view.lines;

        Test.startTest();
        FieldServiceQuoteController.QuoteView saved = FieldServiceQuoteController.saveQuote(
            quoteId,
            JSON.serialize(payload)
        );
        Test.stopTest();

        System.assertEquals(FieldServiceQuoteService.PRICING_REPRICING_REQUIRED, saved.header.pricingStatus);
        System.assertEquals(5, saved.lines[0].quantity);
    }

    @IsTest
    static void saveQuote_laborWithoutRate_throwsAndSavesNothing() {
        FieldServiceQuoteTestData.Scenario scenario = FieldServiceQuoteTestData.createScenario();
        Id quoteId = createQuote(scenario);

        FieldServiceQuoteController.SavePayload payload = new FieldServiceQuoteController.SavePayload();
        payload.ownerId = UserInfo.getUserId();
        payload.lines = new List<FieldServiceQuoteController.LineView>{
            newLine(FieldServiceQuoteService.LINE_TYPE_LABOR, 2)
        };

        Test.startTest();
        Boolean failed = false;
        try {
            FieldServiceQuoteController.saveQuote(quoteId, JSON.serialize(payload));
        } catch (AuraHandledException ex) {
            failed = ex.getMessage().contains('Rate');
        }
        Test.stopTest();

        System.assert(failed, 'Labor without a rate must be rejected');
        System.assertEquals(1, [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :quoteId]);
    }

    @IsTest
    static void getProductInfo_pricedAndUnpricedProducts() {
        FieldServiceQuoteTestData.Scenario scenario = FieldServiceQuoteTestData.createScenario();
        Id quoteId = createQuote(scenario);

        Test.startTest();
        FieldServiceQuoteController.ProductView product = FieldServiceQuoteController.getProductInfo(
            quoteId,
            scenario.part.Id
        );
        Boolean unpricedFailed = false;
        try {
            FieldServiceQuoteController.getProductInfo(quoteId, scenario.unpricedPart.Id);
        } catch (AuraHandledException ex) {
            unpricedFailed = true;
        }
        Test.stopTest();

        System.assertEquals(FieldServiceQuoteTestData.PART_CODE, product.productCode);
        System.assertEquals(FieldServiceQuoteTestData.PART_PRICE, product.listPrice);
        System.assert(unpricedFailed);
    }
}