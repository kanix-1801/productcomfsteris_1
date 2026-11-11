/**
 * @description GC-3587 - Tests for Order Number driven Opportunity Closed Won behavior.
 */
@IsTest
private class QuoteLineItemOrderCloseServiceTest {
    @IsTest
    static void isOrderNumberReceivedOrUpdated_detectsPopulateAndChange() {
        QuoteLineItem newLineItem = new QuoteLineItem(Order_Number__c = 'ORD-100');

        System.assertEquals(
            true,
            QuoteLineItemOrderCloseService.isOrderNumberReceivedOrUpdated(newLineItem, null)
        );

        QuoteLineItem oldLineItem = new QuoteLineItem(Order_Number__c = 'ORD-100');
        System.assertEquals(
            false,
            QuoteLineItemOrderCloseService.isOrderNumberReceivedOrUpdated(newLineItem, oldLineItem)
        );

        oldLineItem.Order_Number__c = null;
        System.assertEquals(
            true,
            QuoteLineItemOrderCloseService.isOrderNumberReceivedOrUpdated(newLineItem, oldLineItem)
        );

        newLineItem.Order_Number__c = 'ORD-200';
        oldLineItem.Order_Number__c = 'ORD-100';
        System.assertEquals(
            true,
            QuoteLineItemOrderCloseService.isOrderNumberReceivedOrUpdated(newLineItem, oldLineItem)
        );

        QuoteLineItem blankOrderLineItem = new QuoteLineItem(Order_Number__c = '   ');
        System.assertEquals(
            false,
            QuoteLineItemOrderCloseService.isOrderNumberReceivedOrUpdated(blankOrderLineItem, null)
        );
    }

    @IsTest
    static void handleAfterSave_skipsWhenOrderNumberUnchanged() {
        QuoteLineItem lineItem = createQuoteLineItem();
        lineItem.Order_Number__c = 'ORD-NO-CHANGE';
        QuoteLineItem oldLineItem = lineItem.clone(true, true, true, true);
        oldLineItem.Order_Number__c = 'ORD-NO-CHANGE';

        Id opportunityId = [
            SELECT OpportunityId
            FROM Quote
            WHERE Id = :lineItem.QuoteId
            LIMIT 1
        ]
        .OpportunityId;

        QuoteLineItemOrderCloseService.handleAfterSave(
            new List<QuoteLineItem>{ lineItem },
            new Map<Id, QuoteLineItem>{ lineItem.Id => oldLineItem }
        );

        System.assertEquals(
            false,
            [SELECT IsClosed FROM Opportunity WHERE Id = :opportunityId LIMIT 1].IsClosed
        );
    }

    @IsTest
    static void handleAfterSave_closesOpenOpportunityOnInsertPath() {
        QuoteLineItem lineItem = createQuoteLineItem();
        lineItem.Order_Number__c = 'ORD-3587-INSERT';

        Id opportunityId = [
            SELECT OpportunityId
            FROM Quote
            WHERE Id = :lineItem.QuoteId
            LIMIT 1
        ]
        .OpportunityId;

        QuoteForecastChangeNotificationHandler.setNotificationDisabled(true);

        Test.startTest();
        QuoteLineItemOrderCloseService.handleAfterSave(new List<QuoteLineItem>{ lineItem }, null);
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT StageName, IsClosed
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];
        System.assertEquals('Closed Won', updatedOpportunity.StageName);
        System.assertEquals(true, updatedOpportunity.IsClosed);
    }

    @IsTest
    static void handleAfterSave_closesOpenOpportunityOnUpdatePath() {
        QuoteLineItem lineItem = createQuoteLineItem();
        QuoteLineItem oldLineItem = lineItem.clone(true, true, true, true);
        lineItem.Order_Number__c = 'ORD-3587-001';

        Id opportunityId = [
            SELECT OpportunityId
            FROM Quote
            WHERE Id = :lineItem.QuoteId
            LIMIT 1
        ]
        .OpportunityId;

        QuoteForecastChangeNotificationHandler.setNotificationDisabled(true);

        Test.startTest();
        QuoteLineItemOrderCloseService.handleAfterSave(
            new List<QuoteLineItem>{ lineItem },
            new Map<Id, QuoteLineItem>{ oldLineItem.Id => oldLineItem }
        );
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT StageName, IsClosed
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];
        System.assertEquals('Closed Won', updatedOpportunity.StageName);
        System.assertEquals(true, updatedOpportunity.IsClosed);
    }

    @IsTest
    static void triggerAfterUpdate_closesOpportunityWhenOrderNumberIsUpdated() {
        QuoteLineItem lineItem = createQuoteLineItem();
        Id opportunityId = [
            SELECT OpportunityId
            FROM Quote
            WHERE Id = :lineItem.QuoteId
            LIMIT 1
        ]
        .OpportunityId;

        QuoteForecastChangeNotificationHandler.setNotificationDisabled(true);

        Test.startTest();
        lineItem.Order_Number__c = 'ORD-TRIGGER-001';
        update lineItem;
        Test.stopTest();

        System.assertEquals(
            'Closed Won',
            [SELECT StageName FROM Opportunity WHERE Id = :opportunityId LIMIT 1].StageName
        );
    }

    private static QuoteLineItem createQuoteLineItem() {
        adb_Product2 product = new adb_Product2().name('QLI Order Close Product');
        new adb_PricebookEntry().product(product).unitPrice(1);
        adb_Account account = new adb_Account()
            .name('QLI Order Close Account')
            .sourceSystemId('QLI-ORD-ACCT');
        adb_Contact contact = new adb_Contact().lastName('QLI Order Close Contact').account(account);
        adb_Opportunity opportunity = new adb_Opportunity()
            .name('QLI Order Close Opportunity')
            .account(account)
            .primaryContact(contact);
        adb_Quote quoteRecord = new adb_Quote().name('QLI Order Close Quote').opportunity(opportunity);
        adb_Asset assetRecord = new adb_Asset()
            .name('QLI Order Close Asset')
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
                AND Product2.Name = 'QLI Order Close Product'
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