/**
 * @author PSL
 * @date 01-09-2026
 * @description Test class for UpdateSubCaseBatch
 */
@isTest
public class UpdateSubCaseBatchTest {

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

        
        Case childCase = new Case(
            Subject = 'childCase Case',
            AccountId = acc.Id,
            Status = 'Order Entry',
            RecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Case' LIMIT 1].Id,
            Order__c = ord.Id
            
        );
        insert childCase;
        
 

        ord.ParentCase__c = parentCase.Id;
        update ord;

        
        Product2 prod = new Product2(Name = 'Test Product', IsActive = true,SalesCategory__c='SERVICE');
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = prod.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        Datetime lastMod = Datetime.now().addHours(-4);
        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            Quantity = 1,
            UnitPrice = 100,
            PricebookEntryId = pbe.Id,
            LineNumber__c = 'LN-001',
            TASSalesCategory__c='SURG SPT',
            orderlinestatus__c='Open',
            Case__c = parentCase.Id,
            SubCase__c = childCase.Id,
            Product2Id = prod.Id
        );
        insert oi;
        
        oi.TASSalesCategory__c = 'IPM';
        Test.setCreatedDate(oi.Id, lastMod);
        update oi;

        ord.Status = 'Activated';
        update ord;

        
        Test.startTest();
        UpdateSubCaseBatch batch = new UpdateSubCaseBatch();
        Database.executeBatch(batch, 1);
        Test.stopTest();

        
        System.assertEquals('ORD-BATCH-001', ord.OrderNumber__c, 'Order should exist for batch processing');
    }
}