/**
* @author PWC Developer
* @date 2026/08/17
*
* @group Free Good Task
*
* @description
* GC-3230 - Unit tests for FreeGoodTaskController, FreeGoodTaskService, the Product2Selector search methods,
* and FreeGoodTaskException. Covers product search, successful creation of the Free Goods Task Product
* records for the Task created by the flow, and every validation path.
*/
@IsTest(SeeAllData=false)
private class FreeGoodTaskControllerTest {

    private static final String ACCOUNT_NAME = 'Free Goods Test Account';
    private static final String OPPORTUNITY_NAME = 'Free Goods Test Opportunity';
    private static final String OPPORTUNITY_RECORD_TYPE = 'Healthcare_Sales';
    private static final String CONTACT_LAST_NAME = 'Free Goods Test Contact';
    private static final String TASK_SUBJECT = 'Free Goods Delivery - Test';
    private static final String ACTIVE_PRODUCT_NAME = 'Sterilizer Sample Kit';
    private static final String ACTIVE_PRODUCT_CODE = 'FGT-1001';
    private static final String SECOND_PRODUCT_NAME = 'Detergent Sample Pack';
    private static final String SECOND_PRODUCT_CODE = 'FGT-1002';
    private static final String INACTIVE_PRODUCT_NAME = 'Retired Sample Kit';
    private static final String INACTIVE_PRODUCT_CODE = 'FGT-9999';

    /**
     * @description
     * GC-3230 - Creates the account, the standard Task, and the product catalogue shared by all tests.
     *
     * @return void
     */
    @TestSetup
    static void setupData() {
        Account testAccount = new Account(
            Name = ACCOUNT_NAME,
            SourceSystemID__c = 'FGT-GC3230-001'
        );
        insert testAccount;

        insert new Task(
            Subject = TASK_SUBJECT,
            Status = 'Not Started',
            WhatId = testAccount.Id
        );

        Contact testContact = new Contact(
            LastName = CONTACT_LAST_NAME,
            AccountId = testAccount.Id
        );
        insert testContact;

        // The record type is pinned and every stage-gated field is populated because the org enforces
        // both a restricted ForecastConfidenceLevel__c picklist and a required field validation rule
        // on Opportunity.
        insert new Opportunity(
            Name = OPPORTUNITY_NAME,
            AccountId = testAccount.Id,
            RecordTypeId = Schema.SObjectType.Opportunity
                .getRecordTypeInfosByDeveloperName()
                .get(OPPORTUNITY_RECORD_TYPE)
                .getRecordTypeId(),
            StageName = 'Discovery',
            ForecastConfidenceLevel__c = 'Pipeline',
            Type = 'New Business',
            Amount = 1000,
            Probability = 10,
            PrimaryContact__c = testContact.Id,
            CloseDate = Date.today().addDays(30)
        );

        insert new List<Product2>{
            new Product2(Name = ACTIVE_PRODUCT_NAME, ProductCode = ACTIVE_PRODUCT_CODE, IsActive = true),
            new Product2(Name = SECOND_PRODUCT_NAME, ProductCode = SECOND_PRODUCT_CODE, IsActive = true),
            new Product2(Name = INACTIVE_PRODUCT_NAME, ProductCode = INACTIVE_PRODUCT_CODE, IsActive = false)
        };
    }

    /**
     * @description Returns the account created in test setup.
     * @return Test Account.
     */
    private static Account getTestAccount() {
        return [SELECT Id, Name FROM Account WHERE Name = :ACCOUNT_NAME LIMIT 1];
    }

    /**
     * @description Returns the standard Task created in test setup.
     * @return Test Task.
     */
    private static Task getTestTask() {
        return [SELECT Id FROM Task WHERE Subject = :TASK_SUBJECT LIMIT 1];
    }

    /**
     * @description Returns the Opportunity created in test setup.
     * @return Test Opportunity.
     */
    private static Opportunity getTestOpportunity() {
        return [
            SELECT Id, HasSampleActivity__c
            FROM Opportunity
            WHERE Name = :OPPORTUNITY_NAME
            LIMIT 1
        ];
    }

    /**
     * @description Returns a product by product code.
     * @param productCode Product code to look up.
     * @return Matching Product2.
     */
    private static Product2 getProductByCode(String productCode) {
        return [SELECT Id, Name FROM Product2 WHERE ProductCode = :productCode LIMIT 1];
    }

    /**
     * @description
     * GC-3230 - Builds a product input for the given product code and quantity.
     *
     * @param productCode Product code to select.
     * @param quantity Quantity to record.
     * @return Product input for the save call.
     */
    private static FreeGoodTaskController.TaskProductInput buildProductInput(String productCode, Decimal quantity) {
        return buildProductInput(productCode, quantity, null);
    }

    /**
     * @description
     * GC-3230 - Builds a product input with optional product details.
     *
     * @param productCode Product code to select.
     * @param quantity Quantity to record.
     * @param productDetails Optional product details text.
     * @return Product input for the save call.
     */
    private static FreeGoodTaskController.TaskProductInput buildProductInput(
        String productCode,
        Decimal quantity,
        String productDetails
    ) {
        FreeGoodTaskController.TaskProductInput productInput =
            new FreeGoodTaskController.TaskProductInput();
        productInput.productId = getProductByCode(productCode).Id;
        productInput.quantity = quantity;
        productInput.productDetails = productDetails;
        return productInput;
    }

    /**
     * @description
     * GC-3230 - Confirms products are searchable by name and that inactive products are excluded.
     *
     * @return void
     */
    @IsTest
    static void searchProductsByNameReturnsActiveProductsOnly() {
        Test.startTest();
        List<FreeGoodTaskController.ProductWrapper> productList =
            FreeGoodTaskController.searchProducts('Sample');
        Test.stopTest();

        Assert.areEqual(2, productList.size(), 'Only the two active sample products should be returned.');

        for (FreeGoodTaskController.ProductWrapper productWrapper : productList) {
            Assert.areNotEqual(
                INACTIVE_PRODUCT_NAME,
                productWrapper.productName,
                'Inactive products should not be returned.'
            );
        }
    }

    /**
     * @description
     * GC-3230 - Confirms products are searchable by product code.
     *
     * @return void
     */
    @IsTest
    static void searchProductsByProductCodeReturnsMatch() {
        Test.startTest();
        List<FreeGoodTaskController.ProductWrapper> productList =
            FreeGoodTaskController.searchProducts(ACTIVE_PRODUCT_CODE);
        Test.stopTest();

        Assert.areEqual(1, productList.size(), 'One product should match the product code.');
        Assert.areEqual(ACTIVE_PRODUCT_NAME, productList[0].productName, 'The matching product should be returned.');
        Assert.areEqual(ACTIVE_PRODUCT_CODE, productList[0].productCode, 'The product code should be returned.');
    }

    /**
     * @description
     * GC-3230 - Confirms an unmatched search returns an empty list rather than an error.
     *
     * @return void
     */
    @IsTest
    static void searchProductsWithNoMatchReturnsEmptyList() {
        Test.startTest();
        List<FreeGoodTaskController.ProductWrapper> productList =
            FreeGoodTaskController.searchProducts('NoSuchProductExists');
        Test.stopTest();

        Assert.isTrue(productList.isEmpty(), 'No products should match the search key.');
    }

    /**
     * @description
     * GC-3230 - Confirms a valid request creates one junction record per selected product, linked to the
     * Task through TaskId__c and to the Account through Account__c.
     *
     * @return void
     */
    @IsTest
    static void createTaskProductsCreatesJunctionRecords() {
        Id taskId = getTestTask().Id;
        Id accountId = getTestAccount().Id;
        List<FreeGoodTaskController.TaskProductInput> productInputs =
            new List<FreeGoodTaskController.TaskProductInput>{
                buildProductInput(ACTIVE_PRODUCT_CODE, 5, 'Evaluation sample for OR team'),
                buildProductInput(SECOND_PRODUCT_CODE, 2)
            };
        productInputs[0].salesPrice = 12.50;
        productInputs[0].consumptionFrequency = 'Weekly';
        productInputs[0].status = 'Open';
        productInputs[0].confidenceLevel = 'Pipeline';
        productInputs[0].expectedShipDate = Date.today().addDays(14);
        productInputs[0].contractValue = 'CTR-1001';
        productInputs[0].comments = 'SPD sample';
        productInputs[0].lineDescription = 'OR evaluation line';

        Test.startTest();
        Integer createdCount = FreeGoodTaskController.createTaskProducts(
            taskId,
            accountId,
            null,
            JSON.serialize(productInputs)
        );
        Test.stopTest();

        Assert.areEqual(2, createdCount, 'Two junction records should have been created.');
        Assert.isFalse(
            getTestOpportunity().HasSampleActivity__c,
            'An Account only save should leave the Opportunity untouched.'
        );

        List<Free_Goods_Task_Product__c> taskProductList = [
            SELECT Id, TaskId__c, Account__c, Product__c, Quantity__c, SalesPrice__c,
                   ConsumptionFrequency__c, Status__c, ConfidenceLevel__c,
                   ExpectedShipDateConsumptionStart__c, Contract__c, ProductDetails__c, Comments__c,
                   LineDescription__c
            FROM Free_Goods_Task_Product__c
            WHERE TaskId__c = :String.valueOf(taskId)
        ];

        Assert.areEqual(2, taskProductList.size(), 'One junction record per selected product is expected.');

        Map<Id, Free_Goods_Task_Product__c> taskProductByProductIdMap =
            new Map<Id, Free_Goods_Task_Product__c>();

        for (Free_Goods_Task_Product__c taskProduct : taskProductList) {
            Assert.areEqual(accountId, taskProduct.Account__c, 'Account should be stored on the junction record.');
            Assert.areEqual(String.valueOf(taskId), taskProduct.TaskId__c, 'The 18 digit Task Id should be stored.');
            taskProductByProductIdMap.put(taskProduct.Product__c, taskProduct);
        }

        Free_Goods_Task_Product__c firstProduct =
            taskProductByProductIdMap.get(getProductByCode(ACTIVE_PRODUCT_CODE).Id);
        Free_Goods_Task_Product__c secondProduct =
            taskProductByProductIdMap.get(getProductByCode(SECOND_PRODUCT_CODE).Id);

        Assert.areEqual(5, firstProduct.Quantity__c.intValue(), 'Quantity should be stored per product.');
        Assert.areEqual(12.50, firstProduct.SalesPrice__c, 'Sales price should be stored when provided.');
        Assert.areEqual('Weekly', firstProduct.ConsumptionFrequency__c, 'Consumption frequency should be stored.');
        Assert.areEqual('Open', firstProduct.Status__c, 'Status should be stored.');
        Assert.areEqual('Pipeline', firstProduct.ConfidenceLevel__c, 'Confidence level should be stored.');
        Assert.areEqual(
            Date.today().addDays(14),
            firstProduct.ExpectedShipDateConsumptionStart__c,
            'Expected ship date should be stored.'
        );
        Assert.areEqual('CTR-1001', firstProduct.Contract__c, 'Contract should be stored.');
        Assert.areEqual(
            'Evaluation sample for OR team',
            firstProduct.ProductDetails__c,
            'Product details should be stored when provided.'
        );
        Assert.areEqual('SPD sample', firstProduct.Comments__c, 'Comments should be stored when provided.');
        Assert.areEqual(
            'OR evaluation line',
            firstProduct.LineDescription__c,
            'Line description should be stored when provided.'
        );
        Assert.isNull(
            secondProduct.LineDescription__c,
            'Line description should remain blank when not provided.'
        );
        Assert.areEqual(2, secondProduct.Quantity__c.intValue(), 'Quantity should be stored per product.');
        Assert.isTrue(
            String.isBlank(secondProduct.ProductDetails__c),
            'Product details should remain blank when not provided.'
        );
        Assert.isNull(secondProduct.SalesPrice__c, 'Optional sales price should remain blank when not provided.');
    }

    /**
     * @description
     * GC-3228 - Confirms a save that originates from an Opportunity flags HasSampleActivity__c on that
     * Opportunity alongside the product rows.
     *
     * @return void
     */
    @IsTest
    static void createTaskProductsFlagsOriginatingOpportunity() {
        Id opportunityId = getTestOpportunity().Id;

        Test.startTest();
        Integer createdCount = FreeGoodTaskController.createTaskProducts(
            getTestTask().Id,
            getTestAccount().Id,
            opportunityId,
            JSON.serialize(
                new List<FreeGoodTaskController.TaskProductInput>{ buildProductInput(ACTIVE_PRODUCT_CODE, 3) }
            )
        );
        Test.stopTest();

        Assert.areEqual(1, createdCount, 'One junction record should have been created.');
        Assert.isTrue(
            getTestOpportunity().HasSampleActivity__c,
            'The originating Opportunity should be flagged as having sample activity.'
        );
    }

    /**
     * @description
     * GC-3228 - Confirms an unusable Opportunity Id is rejected and the product rows are rolled back with it.
     *
     * @return void
     */
    @IsTest
    static void createTaskProductsWithInvalidOpportunityIdThrows() {
        Boolean saveFailed = false;
        String actualMessage = '';

        Test.startTest();
        try {
            FreeGoodTaskController.createTaskProducts(
                getTestTask().Id,
                getTestAccount().Id,
                'not-an-opportunity-id',
                JSON.serialize(
                    new List<FreeGoodTaskController.TaskProductInput>{ buildProductInput(ACTIVE_PRODUCT_CODE, 3) }
                )
            );
        } catch (AuraHandledException expectedException) {
            saveFailed = true;
            actualMessage = expectedException.getMessage();
        }
        Test.stopTest();

        Assert.isTrue(saveFailed, 'The save should have been rejected.');
        Assert.isTrue(
            actualMessage.contains('Opportunity Id provided is not valid'),
            'The Opportunity validation message should reach the LWC but found: ' + actualMessage
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Free_Goods_Task_Product__c],
            'Product rows should roll back when the Opportunity update is rejected.'
        );
    }

    /**
     * @description
     * GC-3230 - Confirms the Task record page can load the Free Goods Task Product rows for a Task.
     *
     * @return void
     */
    @IsTest
    static void getTaskProductsReturnsRowsForTask() {
        Id taskId = getTestTask().Id;
        Id accountId = getTestAccount().Id;
        FreeGoodTaskController.TaskProductInput firstProductInput =
            buildProductInput(ACTIVE_PRODUCT_CODE, 5);
        firstProductInput.lineDescription = 'OR evaluation line';
        firstProductInput.salesPrice = 12.50;
        firstProductInput.consumptionFrequency = 'Weekly';
        firstProductInput.status = 'Open';
        firstProductInput.confidenceLevel = 'Pipeline';
        firstProductInput.expectedShipDate = Date.today().addDays(14);
        firstProductInput.contractValue = 'CTR-1001';
        firstProductInput.comments = 'SPD sample';
        FreeGoodTaskController.createTaskProducts(
            taskId,
            accountId,
            null,
            JSON.serialize(
                new List<FreeGoodTaskController.TaskProductInput>{
                    firstProductInput,
                    buildProductInput(SECOND_PRODUCT_CODE, 2)
                }
            )
        );

        Test.startTest();
        List<FreeGoodTaskController.TaskProductRowWrapper> productRows =
            FreeGoodTaskController.getTaskProducts(taskId);
        Test.stopTest();

        Assert.areEqual(2, productRows.size(), 'Both product rows should be returned for the Task.');

        Map<String, FreeGoodTaskController.TaskProductRowWrapper> rowByProductCode =
            new Map<String, FreeGoodTaskController.TaskProductRowWrapper>();

        for (FreeGoodTaskController.TaskProductRowWrapper productRow : productRows) {
            rowByProductCode.put(productRow.productCode, productRow);
        }

        FreeGoodTaskController.TaskProductRowWrapper activeProductRow =
            rowByProductCode.get(ACTIVE_PRODUCT_CODE);
        Assert.isNotNull(activeProductRow, 'The active product row should be returned.');
        Assert.areEqual(ACTIVE_PRODUCT_NAME, activeProductRow.productName, 'Product name should be returned.');
        Assert.areEqual(5, activeProductRow.quantity.intValue(), 'Quantity should be returned.');
        Assert.areEqual('OR evaluation line', activeProductRow.lineDescription, 'Line description should be returned.');
        Assert.areEqual(12.50, activeProductRow.salesPrice, 'Sales price should be returned.');
        Assert.areEqual('Weekly', activeProductRow.consumptionFrequency, 'Consumption frequency should be returned.');
        Assert.areEqual('Open', activeProductRow.status, 'Status should be returned.');
        Assert.areEqual('Pipeline', activeProductRow.confidenceLevel, 'Confidence level should be returned.');
        Assert.areEqual(Date.today().addDays(14), activeProductRow.expectedShipDate, 'Expected ship date should be returned.');
        Assert.areEqual('CTR-1001', activeProductRow.contractValue, 'Contract should be returned.');
        Assert.areEqual('SPD sample', activeProductRow.comments, 'Comments should be returned.');
        Assert.areEqual(accountId, activeProductRow.accountId, 'Account should be returned.');
        Assert.areEqual(ACCOUNT_NAME, activeProductRow.accountName, 'Account name should be returned.');
        Assert.isNotNull(activeProductRow.createdDate, 'Created date should be returned.');
        Assert.areEqual(
            2,
            rowByProductCode.get(SECOND_PRODUCT_CODE).quantity.intValue(),
            'Second product quantity should be returned.'
        );
    }

    /**
     * @description
     * GC-3230 - Confirms an empty Task returns no product rows rather than an error.
     *
     * @return void
     */
    @IsTest
    static void getTaskProductsWithNoRowsReturnsEmptyList() {
        Test.startTest();
        List<FreeGoodTaskController.TaskProductRowWrapper> productRows =
            FreeGoodTaskController.getTaskProducts(getTestTask().Id);
        List<Free_Goods_Task_Product__c> blankTaskRows =
            FreeGoodsTaskProductSelector.selectByTaskId(null);
        Test.stopTest();

        Assert.isTrue(productRows.isEmpty(), 'No rows should be returned when none exist.');
        Assert.isTrue(blankTaskRows.isEmpty(), 'A blank Task Id should short circuit.');
    }

    /**
     * @description
     * GC-3230 - Confirms the getTaskProducts exception path is handled and surfaced to the LWC.
     *
     * @return void
     */
    @IsTest
    static void getTaskProductsHandlesUnexpectedException() {
        FreeGoodTaskService.throwTestException = true;

        Test.startTest();
        try {
            FreeGoodTaskController.getTaskProducts(getTestTask().Id);
            Assert.fail('An AuraHandledException was expected.');
        } catch (AuraHandledException expectedException) {
            Assert.isNotNull(expectedException, 'The exception should be surfaced to the LWC.');
        }
        Test.stopTest();

        FreeGoodTaskService.throwTestException = false;
    }

    /**
     * @description
     * GC-3230 - Confirms a missing Task Id is rejected before any record is created.
     *
     * @return void
     */
    @IsTest
    static void createTaskProductsWithoutTaskIdThrows() {
        assertSaveFails(
            null,
            getTestAccount().Id,
            new List<FreeGoodTaskController.TaskProductInput>{ buildProductInput(ACTIVE_PRODUCT_CODE, 1) },
            'A Task is required'
        );
    }

    /**
     * @description
     * GC-3230 - Confirms a malformed Task Id is rejected.
     *
     * @return void
     */
    @IsTest
    static void createTaskProductsWithInvalidTaskIdThrows() {
        assertSaveFails(
            'not-a-valid-id',
            getTestAccount().Id,
            new List<FreeGoodTaskController.TaskProductInput>{ buildProductInput(ACTIVE_PRODUCT_CODE, 1) },
            'not valid'
        );
    }

    /**
     * @description
     * GC-3230 - Confirms saving without any selected product is rejected.
     *
     * @return void
     */
    @IsTest
    static void createTaskProductsWithoutProductsThrows() {
        assertSaveFails(
            getTestTask().Id,
            getTestAccount().Id,
            new List<FreeGoodTaskController.TaskProductInput>(),
            'At least one product must be selected.'
        );
    }

    /**
     * @description
     * GC-3230 - Confirms an empty payload is rejected.
     *
     * @return void
     */
    @IsTest
    static void createTaskProductsWithBlankPayloadThrows() {
        assertPayloadFails(null, 'At least one product must be selected.');
    }

    /**
     * @description
     * GC-3230 - Confirms a payload that is not valid JSON is rejected rather than failing silently.
     *
     * @return void
     */
    @IsTest
    static void createTaskProductsWithUnreadablePayloadThrows() {
        assertPayloadFails('this is not json', 'could not be read');
    }

    /**
     * @description
     * GC-3230 - Confirms a zero quantity is rejected for a selected product.
     *
     * @return void
     */
    @IsTest
    static void createTaskProductsWithZeroQuantityThrows() {
        assertSaveFails(
            getTestTask().Id,
            getTestAccount().Id,
            new List<FreeGoodTaskController.TaskProductInput>{ buildProductInput(ACTIVE_PRODUCT_CODE, 0) },
            'Quantity must be greater than zero'
        );
    }

    /**
     * @description
     * GC-3230 - Confirms a product row that reaches Apex without a product reference is rejected.
     *
     * @return void
     */
    @IsTest
    static void createTaskProductsWithBlankProductIdThrows() {
        FreeGoodTaskController.TaskProductInput productInput =
            new FreeGoodTaskController.TaskProductInput();
        productInput.quantity = 1;

        assertSaveFails(
            getTestTask().Id,
            getTestAccount().Id,
            new List<FreeGoodTaskController.TaskProductInput>{ productInput },
            'missing its product reference'
        );
    }

    /**
     * @description
     * GC-3230 - Confirms a malformed product reference is rejected.
     *
     * @return void
     */
    @IsTest
    static void createTaskProductsWithInvalidProductIdThrows() {
        FreeGoodTaskController.TaskProductInput productInput =
            new FreeGoodTaskController.TaskProductInput();
        productInput.productId = 'not-a-valid-product';
        productInput.quantity = 1;

        assertSaveFails(
            getTestTask().Id,
            getTestAccount().Id,
            new List<FreeGoodTaskController.TaskProductInput>{ productInput },
            'not a valid product'
        );
    }

    /**
     * @description
     * GC-3230 - Confirms a product deactivated after selection is rejected on save.
     *
     * @return void
     */
    @IsTest
    static void createTaskProductsWithInactiveProductThrows() {
        assertSaveFails(
            getTestTask().Id,
            getTestAccount().Id,
            new List<FreeGoodTaskController.TaskProductInput>{ buildProductInput(INACTIVE_PRODUCT_CODE, 1) },
            'no longer active'
        );
    }

    /**
     * @description
     * GC-3230 - Confirms nothing is committed when validation fails part way through the request.
     *
     * @return void
     */
    @IsTest
    static void createTaskProductsRollsBackWhenValidationFails() {
        Boolean saveFailed = false;

        Test.startTest();
        try {
            FreeGoodTaskController.createTaskProducts(
                getTestTask().Id,
                getTestAccount().Id,
                null,
                JSON.serialize(
                    new List<FreeGoodTaskController.TaskProductInput>{ buildProductInput(ACTIVE_PRODUCT_CODE, 0) }
                )
            );
        } catch (AuraHandledException expectedException) {
            saveFailed = String.isNotBlank(expectedException.getMessage());
        }
        Test.stopTest();

        Assert.isTrue(saveFailed, 'The save should have been rejected.');
        Assert.areEqual(0, [SELECT COUNT() FROM Free_Goods_Task_Product__c], 'No junction record should be committed.');
    }

    /**
     * @description
     * GC-3230 - Confirms the product search exception path is handled and surfaced to the LWC.
     *
     * @return void
     */
    @IsTest
    static void searchProductsHandlesUnexpectedException() {
        FreeGoodTaskService.throwTestException = true;

        Test.startTest();
        try {
            FreeGoodTaskController.searchProducts('Sample');
            Assert.fail('An AuraHandledException was expected.');
        } catch (AuraHandledException expectedException) {
            Assert.isNotNull(expectedException, 'The exception should be surfaced to the LWC.');
        }
        Test.stopTest();

        FreeGoodTaskService.throwTestException = false;
    }

    /**
     * @description
     * GC-3230 - Confirms the save exception path is handled and surfaced to the LWC.
     *
     * @return void
     */
    @IsTest
    static void createTaskProductsHandlesUnexpectedException() {
        FreeGoodTaskService.throwTestException = true;

        Test.startTest();
        try {
            FreeGoodTaskController.createTaskProducts(
                getTestTask().Id,
                getTestAccount().Id,
                null,
                JSON.serialize(
                    new List<FreeGoodTaskController.TaskProductInput>{ buildProductInput(ACTIVE_PRODUCT_CODE, 1) }
                )
            );
            Assert.fail('An AuraHandledException was expected.');
        } catch (AuraHandledException expectedException) {
            Assert.isNotNull(expectedException, 'The exception should be surfaced to the LWC.');
        }
        Test.stopTest();

        FreeGoodTaskService.throwTestException = false;
    }

    /**
     * @description
     * GC-3230 - Confirms the selector returns active products for the given Ids and skips an empty request.
     *
     * @return void
     */
    @IsTest
    static void selectActiveByIdsReturnsActiveProducts() {
        Id activeProductId = getProductByCode(ACTIVE_PRODUCT_CODE).Id;
        Id inactiveProductId = getProductByCode(INACTIVE_PRODUCT_CODE).Id;

        Test.startTest();
        List<Product2> activeProductList = Product2Selector.selectActiveByIds(
            new Set<Id>{ activeProductId, inactiveProductId }
        );
        List<Product2> emptyProductList = Product2Selector.selectActiveByIds(new Set<Id>());
        Test.stopTest();

        Assert.areEqual(1, activeProductList.size(), 'Only the active product should be returned.');
        Assert.areEqual(activeProductId, activeProductList[0].Id, 'The active product should be returned.');
        Assert.isTrue(emptyProductList.isEmpty(), 'An empty request should short circuit.');
    }

    /**
     * @description
     * GC-3230 - Confirms the existing PSAM selector returns matching products and short circuits on an empty set.
     *
     * @return void
     */
    @IsTest
    static void selectPsamByIdsReturnsProducts() {
        Id activeProductId = getProductByCode(ACTIVE_PRODUCT_CODE).Id;

        Test.startTest();
        List<Product2> productList = Product2Selector.selectPsamByIds(new Set<Id>{ activeProductId });
        List<Product2> emptyProductList = Product2Selector.selectPsamByIds(new Set<Id>());
        List<Product2> nullProductList = Product2Selector.selectPsamByIds(null);
        Test.stopTest();

        Assert.areEqual(1, productList.size(), 'The requested product should be returned.');
        Assert.areEqual(activeProductId, productList[0].Id, 'The matching product Id should be returned.');
        Assert.isTrue(emptyProductList.isEmpty(), 'An empty request should short circuit.');
        Assert.isTrue(nullProductList.isEmpty(), 'A null request should short circuit.');
    }

    /**
     * @description
     * GC-3230 - Confirms LIKE wildcards in the search key are escaped and still return matching products.
     *
     * @return void
     */
    @IsTest
    static void searchProductsEscapesLikeWildcards() {
        Test.startTest();
        List<FreeGoodTaskController.ProductWrapper> productList =
            FreeGoodTaskController.searchProducts('FGT_100');
        List<FreeGoodTaskController.ProductWrapper> blankSearchList =
            FreeGoodTaskController.searchProducts('   ');
        Test.stopTest();

        Assert.isTrue(productList.isEmpty(), 'An underscore should be treated literally, not as a wildcard.');
        Assert.isFalse(blankSearchList.isEmpty(), 'A blank search should return active products for browsing.');
    }

    /**
     * @description
     * GC-3230 - Confirms the exception type is constructable, keeping it covered for deployment.
     *
     * @return void
     */
    @IsTest
    static void freeGoodTaskExceptionCarriesMessage() {
        Test.startTest();
        FreeGoodTaskException thrownException = new FreeGoodTaskException('Validation failed.');
        Test.stopTest();

        Assert.areEqual('Validation failed.', thrownException.getMessage(), 'The message should be retained.');
    }

    /**
     * @description
     * GC-3230 - Asserts a raw payload is rejected and that the message reaches the LWC.
     *
     * @param productInputsJson Raw payload under test.
     * @param expectedMessageFragment Fragment expected in the validation message.
     * @return void
     */
    private static void assertPayloadFails(String productInputsJson, String expectedMessageFragment) {
        Boolean saveFailed = false;
        String actualMessage = '';

        Test.startTest();
        try {
            FreeGoodTaskController.createTaskProducts(
                getTestTask().Id,
                getTestAccount().Id,
                null,
                productInputsJson
            );
        } catch (AuraHandledException expectedException) {
            saveFailed = true;
            actualMessage = expectedException.getMessage();
        }
        Test.stopTest();

        Assert.isTrue(saveFailed, 'The save should have been rejected.');
        Assert.isTrue(
            actualMessage.contains(expectedMessageFragment),
            'Expected "' + expectedMessageFragment + '" in the validation message but found: ' + actualMessage
        );
    }

    /**
     * @description
     * GC-3230 - Asserts the save is rejected and that the validation message reaches the LWC.
     *
     * @param taskId Task Id under test.
     * @param accountId Account Id under test.
     * @param productInputs Product selection under test.
     * @param expectedMessageFragment Fragment expected in the validation message.
     * @return void
     */
    private static void assertSaveFails(
        String taskId,
        Id accountId,
        List<FreeGoodTaskController.TaskProductInput> productInputs,
        String expectedMessageFragment
    ) {
        Boolean saveFailed = false;
        String actualMessage = '';

        Test.startTest();
        try {
            FreeGoodTaskController.createTaskProducts(taskId, accountId, null, JSON.serialize(productInputs));
        } catch (AuraHandledException expectedException) {
            saveFailed = true;
            actualMessage = expectedException.getMessage();
        }
        Test.stopTest();

        Assert.isTrue(saveFailed, 'The save should have been rejected.');
        Assert.isTrue(
            actualMessage.contains(expectedMessageFragment),
            'Expected "' + expectedMessageFragment + '" in the validation message but found: ' + actualMessage
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Free_Goods_Task_Product__c],
            'No junction record should be created when validation fails.'
        );
    }
}