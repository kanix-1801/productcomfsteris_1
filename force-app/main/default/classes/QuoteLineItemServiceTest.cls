/**
 * @description GW-5302: Tests for QuoteLineItemService.setConstraintEngineNodeStatus.
 */
 @IsTest
 private class QuoteLineItemServiceTest {
     /**
      * @description Happy path: handleBeforeInsert stamps ConstraintEngineNodeStatus__c when the line item status is blank.
      */
     @IsTest
     static void handleBeforeInsert_stampsStatusWhenBlank() {
         QuoteAction quoteAction = createQuoteAction();
         stubAssetActionData(quoteAction.SourceAssetId);
 
         QuoteLineItem lineItem = new QuoteLineItem(
             QuoteActionId = quoteAction.Id,
             ConstraintEngineNodeStatus__c = null
         );
 
         Test.startTest();
         QuoteLineItemService.handleBeforeInsert(
             new List<QuoteLineItem>{ lineItem }
         );
         Test.stopTest();
 
         System.assertEquals(
             'Stamped Status',
             lineItem.ConstraintEngineNodeStatus__c,
             'Blank Constraint Engine Node Status should be stamped from the latest Asset Action Source'
         );
     }
 
     /**
      * @description Negative path: handleBeforeInsert does not overwrite ConstraintEngineNodeStatus__c when it is already populated.
      */
     @IsTest
     static void handleBeforeInsert_doesNotOverwriteExistingStatus() {
         QuoteAction quoteAction = createQuoteAction();
         QuoteLineItem lineItem = new QuoteLineItem(
             QuoteActionId = quoteAction.Id,
             ConstraintEngineNodeStatus__c = 'Existing Status'
         );
 
         Test.startTest();
         QuoteLineItemService.handleBeforeInsert(
             new List<QuoteLineItem>{ lineItem }
         );
         Test.stopTest();
 
         System.assertEquals(
             'Existing Status',
             lineItem.ConstraintEngineNodeStatus__c,
             'Existing Constraint Engine Node Status should not be overwritten'
         );
     }
 
     /**
      * @description handleAfterInsert syncs quote totals and recalculates from the inserted line item.
      */
     @IsTest
     static void handleAfterInsert_syncsQuoteFromInsertedLine() {
         QuoteLineItem lineItem = createQuoteLineItem();
 
         Test.startTest();
         QuoteLineItemService.handleAfterInsert(new List<QuoteLineItem>{ lineItem });
         Test.stopTest();
 
         Quote quoteRecord = [
             SELECT Id, Quote_Total_Without_Freight__c
             FROM Quote
             WHERE Id = :lineItem.QuoteId
         ];
         System.assertEquals(
             lineItem.QuoteId,
             quoteRecord.Id,
             'After insert should keep the Quote Line Item related to its Quote'
         );
         System.assertNotEquals(
             null,
             quoteRecord.Id,
             'Quote should still exist after handleAfterInsert'
         );
     }
 
     /**
      * @description handleAfterUpdate syncs quote totals when line item values change.
      */
     @IsTest
     static void handleAfterUpdate_syncsQuoteFromUpdatedLine() {
         QuoteLineItem lineItem = createQuoteLineItem();
         QuoteLineItem oldLineItem = lineItem.clone(true, true, true, true);
         lineItem.Quantity = 2;
         lineItem.UnitPrice = 2;
 
         Test.startTest();
         QuoteLineItemService.handleAfterUpdate(
             new List<QuoteLineItem>{ lineItem },
             new Map<Id, QuoteLineItem>{ oldLineItem.Id => oldLineItem }
         );
         Test.stopTest();
 
         Quote quoteRecord = [
             SELECT Id
             FROM Quote
             WHERE Id = :lineItem.QuoteId
         ];
         System.assertEquals(
             lineItem.QuoteId,
             quoteRecord.Id,
             'After update should keep the Quote Line Item related to its Quote'
         );
     }
 
     /**
      * @description handleAfterDelete syncs quote totals from the deleted line item Quote Id.
      */
     @IsTest
     static void handleAfterDelete_syncsQuoteFromDeletedLine() {
         QuoteLineItem lineItem = createQuoteLineItem();
         Id quoteId = lineItem.QuoteId;
 
         Test.startTest();
         QuoteLineItemService.handleAfterDelete(new List<QuoteLineItem>{ lineItem });
         Test.stopTest();
 
         Quote quoteRecord = [
             SELECT Id
             FROM Quote
             WHERE Id = :quoteId
         ];
         System.assertEquals(
             quoteId,
             quoteRecord.Id,
             'After delete should still resolve the related Quote from the line item'
         );
     }
 
     /**
      * @description handleAfterUndelete syncs quote totals from the restored line item.
      */
     @IsTest
     static void handleAfterUndelete_syncsQuoteFromRestoredLine() {
         QuoteLineItem lineItem = createQuoteLineItem();
 
         Test.startTest();
         QuoteLineItemService.handleAfterUndelete(new List<QuoteLineItem>{ lineItem });
         Test.stopTest();
 
         QuoteLineItem queriedLineItem = [
             SELECT Id, QuoteId
             FROM QuoteLineItem
             WHERE Id = :lineItem.Id
         ];
         System.assertEquals(
             lineItem.QuoteId,
             queriedLineItem.QuoteId,
             'After undelete should keep the Quote Line Item related to its Quote'
         );
     }

    /**
     * @description AssetActionsSelector targets AssetAction. One method is enough to cover that class.
     */
    @IsTest
    static void assetActionsSelector_queriesAssetAction() {
        String soql = new AssetActionsSelector().selectField('Id').limitTo(1).toSoql();

        System.assert(
            soql.contains('FROM AssetAction') && !soql.contains('FROM AssetActionSource'),
            'AssetActionsSelector should query AssetAction: ' + soql
        );
    }

    /**
     * @description AssetActionSourcesSelector targets AssetActionSource. One method is enough to cover that class.
     */
    @IsTest
    static void assetActionSourcesSelector_queriesAssetActionSource() {
        String soql = new AssetActionSourcesSelector().selectField('Id').limitTo(1).toSoql();

        System.assert(
            soql.contains('FROM AssetActionSource'),
            'AssetActionSourcesSelector should query AssetActionSource: ' + soql
        );
    }
 
     /**
      * @description Builds in-memory Asset Action and Asset Action Source rows for the Quote Action asset.
      * @param assetId Source Asset Id from the Quote Action
      */
     private static void stubAssetActionData(Id assetId) {
         String actionPrefix = AssetAction.SObjectType.getDescribe().getKeyPrefix();
         Id olderActionId = actionPrefix + '000000000001';
         Id newerActionId = actionPrefix + '000000000002';
 
         QuoteLineItemService.testAssetActions = new List<AssetAction>{
             (AssetAction) JSON.deserialize(
                 '{"Id":"' + olderActionId + '","AssetId":"' + assetId + '","ActionDate":"2026-01-01T00:00:00.000Z"}',
                 AssetAction.class
             ),
             (AssetAction) JSON.deserialize(
                 '{"Id":"' + newerActionId + '","AssetId":"' + assetId + '","ActionDate":"2026-01-02T00:00:00.000Z"}',
                 AssetAction.class
             )
         };
         QuoteLineItemService.testAssetActionSources = new List<AssetActionSource>{
             (AssetActionSource) JSON.deserialize(
                 '{"ConstraintEngineNodeStatus__c":null,"AssetActionId":"' +
                     olderActionId +
                     '","AssetAction":{"Id":"' +
                     olderActionId +
                     '","AssetId":"' +
                     assetId +
                     '"}}',
                 AssetActionSource.class
             ),
             (AssetActionSource) JSON.deserialize(
                 '{"ConstraintEngineNodeStatus__c":"Stamped Status","AssetActionId":"' +
                     newerActionId +
                     '","AssetAction":{"Id":"' +
                     newerActionId +
                     '","AssetId":"' +
                     assetId +
                     '"}}',
                 AssetActionSource.class
             )
         };
     }
 
     /**
      * @description Creates a Quote Action with a Source Asset for setConstraintEngineNodeStatus tests.
      * @return Inserted Quote Action
      */
    private static QuoteAction createQuoteAction() {
        adb_Product2 product = new adb_Product2().name('QLI Status Product');
        // Registered with the Quote Action graph so persist inserts the standard pricebook entry.
        new adb_PricebookEntry().product(product).unitPrice(1);
        adb_Account account = new adb_Account()
            .name('QLI Status Account')
            .sourceSystemId('QLI-STATUS-ACCT');
        adb_Contact contact = new adb_Contact().lastName('QLI Status Contact').account(account);
        adb_Opportunity opportunity = new adb_Opportunity()
            .name('QLI Status Opportunity')
            .account(account)
            .primaryContact(contact);
        adb_Quote quoteRecord = new adb_Quote().name('QLI Status Quote').opportunity(opportunity);
        adb_Asset assetRecord = new adb_Asset()
            .name('QLI Status Asset')
            .account(account)
            .product(product);
        adb_QuoteAction quoteAction = new adb_QuoteAction().quote(quoteRecord).sourceAsset(assetRecord).type('Add');
        return (QuoteAction) quoteAction.persist();
    }

    /**
     * @description Creates an inserted Quote Line Item on the Quote Action quote.
     * @return Inserted Quote Line Item
     */
    private static QuoteLineItem createQuoteLineItem() {
        QuoteAction quoteAction = createQuoteAction();
        PricebookEntry pricebookEntry = [
            SELECT Id
            FROM PricebookEntry
            WHERE Pricebook2Id = :Test.getStandardPricebookId() AND Product2.Name = 'QLI Status Product'
            LIMIT 1
        ];

        QuoteForecastChangeNotificationHandler.setNotificationDisabled(true);
        return (QuoteLineItem) new adb_QuoteLineItem()
            .quoteId(quoteAction.QuoteId)
            .pricebookEntryId(pricebookEntry.Id)
            .quantity(1)
            .unitPrice(1)
            .persist();
    }
}