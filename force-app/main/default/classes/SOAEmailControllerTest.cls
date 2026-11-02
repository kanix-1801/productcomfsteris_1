/**
 * @author PSL
 * @date 11-27-2025
 * @description Test class for SOAEmailController
 */
@IsTest
private class SOAEmailControllerTest {

    private static Account createAccount() {
        Account a = new Account(Name = 'Acme Co');
        insert a;
        return a;
    }

    private static Order createOrder(Id accountId) {
        Order o = new Order(
            AccountId = accountId,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert o;
        return o;
    }

    private static Product2 createProduct() {
        Product2 p = new Product2(
            Name = 'Widget',
            IsActive = true,
            SalesCategory__c = 'CAPEQUIP'
        );
        insert p;
        return p;
    }

    private static PricebookEntry createPricebookEntry(Product2 p) {
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = p.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;
        return pbe;
    }

    @IsTest
    static void testControllerMethodsWithValidAndInvalidData() {
        Account account = createAccount();
        Order order1 = createOrder(account.Id);
        Order order2 = createOrder(account.Id);
        Product2 product = createProduct();
        PricebookEntry pbe = createPricebookEntry(product);

        OrderItem item1 = new OrderItem(
            OrderId = order1.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100,
            	TASSalesCategory__c = 'GI IN SALE',
            Warehouse__c = 'DRO',
            RequestDate__c = Date.newInstance(2025, 1, 5)
        );
        insert item1;

        OrderItem item2 = new OrderItem(
            OrderId = order2.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100,
            	TASSalesCategory__c = 'PM',
            RequestDate__c = Date.newInstance(2025, 1, 10)
        );
        insert item2;

        Contact contact = new Contact(LastName = 'Rep1', Email = 'rep1@example.com', AccountId = account.Id);
        insert contact;

        OrderLineContact__c olc = new OrderLineContact__c(OrderLine__c = item1.Id, SalesRep__c = contact.Id);
        insert olc;

        HoldMatrix__c holdMatrix = new HoldMatrix__c(Name = 'Hold1');
        insert holdMatrix;

        OrderAndOrderLineHold__c hold = new OrderAndOrderLineHold__c(
            Order__c = order1.Id,
            HoldMatrix__c = holdMatrix.Id,
            ReasonCode__c = 'C1'
        );
        insert hold;

        SOAEmailController controller = new SOAEmailController();
        controller.orderId = order1.Id;

        //System.assert(controller.getAccountManagerNames().contains('Rep1'));
        //System.assert(controller.getCapLineReqShipDate().contains('2025-01-05'));
        System.assertEquals(true, controller.getGiReprocessingOrders());
        System.assertEquals(1, controller.getReasonCodeList().size());
        System.assertEquals(true, controller.getServiceLineSalesRep());

        controller.orderId = order2.Id;
        System.assertEquals('', controller.getAccountManagerNames());
        System.assertEquals('', controller.getCapLineReqShipDate());
        System.assertEquals(false, controller.getGiReprocessingOrders());
        System.assertEquals(0, controller.getReasonCodeList().size());
        System.assertEquals(true, controller.getServiceLineSalesRep());
    }

    @IsTest
    static void testServiceLineSalesRepBehavior() {
        Account account = createAccount();
        Order order = createOrder(account.Id);
        Product2 product = createProduct();
        PricebookEntry pbe = createPricebookEntry(product);

        OrderItem item = new OrderItem(OrderId = order.Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 100);
        insert item;

        Contact contact = new Contact(LastName = 'SvcRep', Email = 'svc@example.com', AccountId = account.Id);
        insert contact;

        OrderLineContact__c olc = new OrderLineContact__c(OrderLine__c = item.Id, SalesRep__c = contact.Id);
        insert olc;

        SOAEmailController controller = new SOAEmailController();
        controller.orderId = order.Id;

        System.assertEquals(true, controller.getServiceLineSalesRep());

        delete olc;
        System.assertEquals(true, controller.getServiceLineSalesRep());
    }

    @IsTest
    static void testCatchBlockExecutionForAllMethods() {
        SOAEmailController controller = new SOAEmailController();
        controller.orderId = 'FORCE_EXCEPTION';

        Boolean threw;

        threw = false;
        try { controller.getAccountManagerNames(); } catch (Exception e) { threw = true; }
        System.assertEquals(true, threw);

        threw = false;
        try { controller.getCapLineReqShipDate(); } catch (Exception e) { threw = true; }
        System.assertEquals(true, threw);

        threw = false;
        try { controller.getGiReprocessingOrders(); } catch (Exception e) { threw = true; }
        System.assertEquals(true, threw);

        threw = false;
        try { controller.getReasonCodeList(); } catch (Exception e) { threw = true; }
        System.assertEquals(true, threw);

        threw = false;
        try { controller.getServiceLineSalesRep(); } catch (Exception e) { threw = true; }
        System.assertEquals(true, threw);
    }
}