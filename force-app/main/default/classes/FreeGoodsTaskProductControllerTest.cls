/**
 * @description Tests for FreeGoodsTaskProductController (GC-3230).
 */
@IsTest
private class FreeGoodsTaskProductControllerTest {
    @TestSetup
    static void setupData() {
        Account account = new Account(
            Name = 'Free Goods Product Test Account',
            SystemID__c = 'LEG-FGTP-001',
            SourceSystemID__c = 'TEST-ORACLE-FGTP-001',
            OrgIDs__c = '82'
        );
        insert account;

        Free_Good_Task__c freeGoodTask = new Free_Good_Task__c(
            Name = 'Free Goods Task Test',
            Account__c = account.Id,
            Status__c = 'Not Started',
            Task_Type__c = 'Free Goods'
        );
        insert freeGoodTask;

        insert new List<Product2>{
            new Product2(Name = 'Free Goods Product A', ProductCode = 'FG-A', IsActive = true),
            new Product2(Name = 'Free Goods Product B', ProductCode = 'FG-B', IsActive = true)
        };
    }

    @IsTest
    static void testGetProductsByIdsReturnsMatches() {
        List<Product2> products = [SELECT Id FROM Product2 ORDER BY Name];

        Test.startTest();
        List<FreeGoodsTaskProductController.ProductOption> options =
            FreeGoodsTaskProductController.getProductsByIds(
                new List<Id>{ products[0].Id, products[1].Id }
            );
        Test.stopTest();

        System.assertEquals(2, options.size(), 'Expected both products returned');
    }

    @IsTest
    static void testGetProductsByIdsEmptyInput() {
        Test.startTest();
        List<FreeGoodsTaskProductController.ProductOption> options =
            FreeGoodsTaskProductController.getProductsByIds(new List<Id>());
        Test.stopTest();

        System.assertEquals(0, options.size());
    }

    @IsTest
    static void testSaveTaskProductsSuccess() {
        Free_Good_Task__c freeGoodTask = [SELECT Id FROM Free_Good_Task__c LIMIT 1];
        Account account = [SELECT Id FROM Account LIMIT 1];
        List<Product2> products = [SELECT Id FROM Product2 ORDER BY Name];

        List<FreeGoodsTaskProductController.ProductQuantityInput> inputs =
            new List<FreeGoodsTaskProductController.ProductQuantityInput>();

        FreeGoodsTaskProductController.ProductQuantityInput first =
            new FreeGoodsTaskProductController.ProductQuantityInput();
        first.productId = products[0].Id;
        first.quantity = 2;
        inputs.add(first);

        FreeGoodsTaskProductController.ProductQuantityInput second =
            new FreeGoodsTaskProductController.ProductQuantityInput();
        second.productId = products[1].Id;
        second.quantity = 5;
        inputs.add(second);

        Test.startTest();
        List<Id> insertedIds = FreeGoodsTaskProductController.saveTaskProducts(
            String.valueOf(freeGoodTask.Id),
            String.valueOf(account.Id),
            inputs
        );
        Test.stopTest();

        System.assertEquals(2, insertedIds.size());

        List<Free_Goods_Task_Product__c> rows = [
            SELECT Id, taskId__c, Account__c, Product__c, Quantity__c, Name
            FROM Free_Goods_Task_Product__c
            WHERE Id IN :insertedIds
            ORDER BY Quantity__c
        ];
        System.assertEquals(2, rows.size());
        System.assertEquals(String.valueOf(freeGoodTask.Id), rows[0].taskId__c);
        System.assertEquals(String.valueOf(freeGoodTask.Id), rows[1].taskId__c);
        System.assertEquals(String.valueOf(account.Id), rows[0].Account__c);
        System.assertEquals(String.valueOf(account.Id), rows[1].Account__c);
        System.assertEquals(2, rows[0].Quantity__c);
        System.assertEquals(5, rows[1].Quantity__c);
    }

    @IsTest
    static void testSaveTaskProductsStoresTrimmedTaskIdText() {
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        String taskIdText = '  00T000000000001AAA  ';

        FreeGoodsTaskProductController.ProductQuantityInput input =
            new FreeGoodsTaskProductController.ProductQuantityInput();
        input.productId = product.Id;
        input.quantity = 1;

        Test.startTest();
        List<Id> insertedIds = FreeGoodsTaskProductController.saveTaskProducts(
            taskIdText,
            null,
            new List<FreeGoodsTaskProductController.ProductQuantityInput>{ input }
        );
        Test.stopTest();

        Free_Goods_Task_Product__c row = [
            SELECT taskId__c, Account__c
            FROM Free_Goods_Task_Product__c
            WHERE Id = :insertedIds[0]
        ];
        System.assertEquals('00T000000000001AAA', row.taskId__c);
        System.assertEquals(null, row.Account__c, 'Blank account should stay null');
    }

    @IsTest
    static void testSaveTaskProductsRequiresTaskId() {
        Boolean threw = false;
        try {
            FreeGoodsTaskProductController.saveTaskProducts(
                null,
                null,
                new List<FreeGoodsTaskProductController.ProductQuantityInput>()
            );
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('Task Id is required.'));
        }
        System.assert(threw, 'Expected AuraHandledException for missing task Id');
    }

    @IsTest
    static void testSaveTaskProductsRequiresProducts() {
        Free_Good_Task__c freeGoodTask = [SELECT Id FROM Free_Good_Task__c LIMIT 1];
        Boolean threw = false;
        try {
            FreeGoodsTaskProductController.saveTaskProducts(
                String.valueOf(freeGoodTask.Id),
                null,
                new List<FreeGoodsTaskProductController.ProductQuantityInput>()
            );
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('Select at least one product.'));
        }
        System.assert(threw, 'Expected AuraHandledException for empty product list');
    }

    @IsTest
    static void testSaveTaskProductsRejectsInvalidQuantity() {
        Free_Good_Task__c freeGoodTask = [SELECT Id FROM Free_Good_Task__c LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];

        FreeGoodsTaskProductController.ProductQuantityInput input =
            new FreeGoodsTaskProductController.ProductQuantityInput();
        input.productId = product.Id;
        input.quantity = 0;

        Boolean threw = false;
        try {
            FreeGoodsTaskProductController.saveTaskProducts(
                String.valueOf(freeGoodTask.Id),
                null,
                new List<FreeGoodsTaskProductController.ProductQuantityInput>{ input }
            );
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('Quantity must be greater than zero'));
        }
        System.assert(threw, 'Expected AuraHandledException for invalid quantity');
    }
}