@IsTest
public class TryClassTest {

    /*@testSetup
    static void setupData() {
        
        Id pricebookId = Test.getStandardPricebookId();
               
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        Order ord = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            OrderNumber__c = 'ORD1234',
            RegistrationNumber__c = 'REG123',
            OrderClassification__c = 'New',
            CurrencyIsoCode = 'USD',
            AllCapitalLinesClosedDate__c = date.Today() - 7,
            FirstScheduledDateNonPreinstall__c = date.Today() + 70,
            Pricebook2Id = pricebookId // Required to add OrderItems
        );
        insert ord;

    }*/
    
    @IsTest
    static void testCreateTasksForOrderLineWithExistingTasks() {
        Id pricebookId = Test.getStandardPricebookId();
               
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        Order ord = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            OrderNumber__c = 'ORD1234',
            RegistrationNumber__c = 'REG123',
            OrderClassification__c = 'New',
            CurrencyIsoCode = 'USD',
            AllCapitalLinesClosedDate__c = date.Today() - 7,
            FirstScheduledDateNonPreinstall__c = date.Today() + 70,
            Pricebook2Id = pricebookId // Required to add OrderItems
        );
        insert ord;
        List<Order> ordList = [SELECT Id, OrderNumber__c, ParentCase__c FROM Order WHERE OrderNumber__c = 'ORD1234' LIMIT 1];

        Test.startTest();
            if(ordList.size()>0)
                CreateTaskHelper.createTasksForOrderLine(ordList[0].OrderNumber__c);
        Test.stopTest();
        Order ord1 = [SELECT Id, OrderNumber__c, ParentCase__c FROM Order WHERE OrderNumber__c = 'ORD1234' LIMIT 1];
    }
}