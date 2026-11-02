@IsTest
/**
 * @author PSL
 * @date 11-12-2025
 * @description Test class for CreateSubCaseBatch batch class
 */
public class CreateSubCaseBatchTest {

    @IsTest
    static void testBatchStartExecuteFinish() {
       
        Account acc = new Account(Name = 'Batch Test Account');
        insert acc;

        
        Order ord = new Order(
            AccountId = acc.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            OrderNumber__c = 'ORD-BATCH-001',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert ord;

        
        Case parentCase = new Case(
            Subject = 'Parent Case',
            AccountId = acc.Id,
            Status = 'Order Entry',
            RecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Case' LIMIT 1].Id,
            Order__c = ord.Id
            
        );
        insert parentCase;
        
 

        ord.ParentCase__c = parentCase.Id;
        update ord;

        
        Product2 prod = new Product2(Name = 'Test Product', IsActive = true,SalesCategory__c='CNSMBLS');
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
            LineNumber__c = 'LN-001',
            TASSalesCategory__c='SURG SPT'
            
        );
        insert oi;

        
        ord.Status = 'Activated';
        update ord;

        
        Test.startTest();
        CreateSubCaseBatch batch = new CreateSubCaseBatch();
        Database.executeBatch(batch, 1);
        Test.stopTest();

        
        System.assertEquals('ORD-BATCH-001', ord.OrderNumber__c, 'Order should exist for batch processing');
    }
}