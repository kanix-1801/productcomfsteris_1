/**
* @author PSL
* @date 4-07-2026
* @description Test class for class OrderLineRelatedListController
*/

@IsTest
public class OrderLineRelatedListControllerTest {

    @testSetup
    static void setupData() {

        /* Account */
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        /* Standard Pricebook */
        Id stdPricebookId = Test.getStandardPricebookId();

        /* Product */
        Product2 product = new Product2(
            Name = 'Test Product',
            IsActive = true
        );
        insert product;

        /* Pricebook Entry */
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPricebookId,
            Product2Id   = product.Id,
            UnitPrice    = 100,
            IsActive     = true
        );
        insert pbe;

        /* Order */
        Order ord = new Order(
            Name = 'Test Order',
            AccountId = acc.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = stdPricebookId
        );
        insert ord;

        /* Parent Case */
        Case parentCase = new Case(
            Subject = 'Parent Case',
            Status = 'New',
            Origin = 'Phone',
            Order__c = ord.Id
        );
        insert parentCase;

        /* Sub Case */
        Case subCase = new Case(
            Subject = 'Sub Case',
            Status = 'New',
            Origin = 'Phone'
        );
        insert subCase;

        /* OrderItem – Order page */
        OrderItem oiOrder = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 2,
            UnitPrice = 100,
            //OrderLineNumber__c = 1,
            ExtendedPrice__c = 200,
            //OrderLineType__c = 'Standard',
            OrderLineStatus__c = 'Open',
            RequestDate__c = Date.today(),
            ScheduledDate__c = Date.today().addDays(2),
            Subcase__c = subCase.Id
        );
        insert oiOrder;

        /* OrderItem – Case page */
        OrderItem oiCase = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 50,
            //OrderLineNumber__c = 2,
            ExtendedPrice__c = 50,
            Case__c = parentCase.Id,
            //ItemNumber__c = 'IT1',
            //ProductDescription__c = 'Test Desc',
            Warehouse__c = 'WH1',        
            Sales_Rep__c = 'JD',
            ActualShipmentDate__c = Date.today(),
            //OrderLineType__c = 'Return',
            OrderLineStatus__c = 'Closed'
        );
        insert oiCase;
    }

    /* =============================
     * ORDER PAGE
     * ============================= */
    @IsTest
    static void testGetOrderLinesFromOrder() {
        Order ord = [SELECT Id FROM Order LIMIT 1];

        List<OrderLineRelatedListController.OrderLineDTO> result =
            OrderLineRelatedListController.getOrderLines(
                ord.Id, 'Order', 50
            );

        System.assertEquals(2, result.size());
    }

    /* =============================
     * CASE PAGE
     * ============================= */
    @IsTest
    static void testGetOrderLinesFromCase() {
        Case cs = [SELECT Id FROM Case WHERE Order__c != null LIMIT 1];

        List<OrderLineRelatedListController.OrderLineDTO> result =
            OrderLineRelatedListController.getOrderLines(
                cs.Id, 'Case', 50
            );

        System.assertEquals(1, result.size());
       // System.assertEquals('IT1', result[0].itemNumber);
    }

    /* =============================
     * COUNT – ORDER
     * ============================= */
    @IsTest
    static void testGetOrderLineCount_Order() {
        Order ord = [SELECT Id FROM Order LIMIT 1];

        Integer count =
            OrderLineRelatedListController.getOrderLineCount(
                ord.Id, 'Order'
            );

        System.assertEquals(2, count);
    }

    /* =============================
     * COUNT – CASE
     * ============================= */
    @IsTest
    static void testGetOrderLineCount_Case() {
        Case cs = [SELECT Id FROM Case WHERE Order__c != null LIMIT 1];

        Integer count =
            OrderLineRelatedListController.getOrderLineCount(
                cs.Id, 'Case'
            );

        System.assertEquals(1, count);
    }

    /* =============================
     * NO ORDER EDGE CASE
     * ============================= */
    @IsTest
    static void testNoOrderLinkedToCase() {

        Case orphan = new Case(
            Subject = 'No Order',
            Status = 'New',
            Origin = 'Phone'
        );
        insert orphan;

        List<OrderLineRelatedListController.OrderLineDTO> lines =
            OrderLineRelatedListController.getOrderLines(
                orphan.Id, 'Case', 10
            );

        Integer count =
            OrderLineRelatedListController.getOrderLineCount(
                orphan.Id, 'Case'
            );

        System.assertEquals(0, lines.size());
        System.assertEquals(0, count);
    }
}