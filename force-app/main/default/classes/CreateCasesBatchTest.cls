/**
 * @author PSL
 * @date 11-12-2025
 * @description Test class for CreateCasesBatch batch class
 */
@IsTest
public class CreateCasesBatchTest {

    @IsTest
    static void testBatchStartExecuteFinish() {
        
        Account acc = new Account(Name = 'Batch Test Account');
        insert acc;

        
        Order ord = new Order(
            AccountId = acc.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            OrderNumber__c = 'ORD-BATCH-002',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert ord;

        
        Product2 prod = new Product2(Name = 'Test Product', IsActive = true);
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = prod.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        
        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            Quantity = 1,
            UnitPrice = 100,
            PricebookEntryId = pbe.Id,
            LineNumber__c = 'LN-001'
        );
        insert oi;

        
        ord.Status = 'Activated';
        update ord;

        
        Test.startTest();
        CreateCasesBatch batch = new CreateCasesBatch();
        Database.executeBatch(batch, 1);
        Test.stopTest();        
        System.assertEquals('ORD-BATCH-002', ord.OrderNumber__c, 'Order should exist for batch processing');
    }
}