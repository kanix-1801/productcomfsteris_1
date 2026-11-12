/**
 * @author PWC Developer
 * @date 2026/10/30
 *
 * @group Lost Business Products
 *
 * @description
 * GC-3574 - Unit tests for LostBusinessProductController, LostBusinessProductService, and
 * LostBusinessProductSelector. Covers originating-product retrieval, catalogue search, copying
 * only the selected products, catalogue add, validation, and the duplicate-submit guard.
 */
@IsTest(SeeAllData=false)
private class LostBusinessProductControllerTest {

    /**
     * @description
     * GC-3574 - Creates the shared Lost Business product scenario.
     *
     * @return void
     */
    @TestSetup
    static void setupData() {
        TestDataFactory.setupLostBusinessProductScenario();
    }

    /**
     * @description
     * GC-3574 - Confirms only the originating opportunity's products are returned, with SKU and price.
     *
     * @return void
     */
    @IsTest
    static void getOriginatingProductsReturnsOnlyThatOpportunity() {
        TestDataFactory.LostBusinessProductContext context = data();

        Test.startTest();
        List<LostBusinessProductController.OriginatingProductRow> productRowList =
            LostBusinessProductController.getOriginatingProducts(context.originatingOpportunityId);
        Test.stopTest();

        Assert.areEqual(2, productRowList.size(), 'Both originating products should be returned.');

        Map<String, LostBusinessProductController.OriginatingProductRow> rowByName =
            new Map<String, LostBusinessProductController.OriginatingProductRow>();

        for (LostBusinessProductController.OriginatingProductRow productRow : productRowList) {
            rowByName.put(productRow.productName, productRow);
            Assert.areNotEqual(
                TestDataFactory.LB_PRODUCT_C_NAME,
                productRow.productName,
                'Another opportunity product must not be returned.'
            );
            Assert.isTrue(productRow.copyable, 'An active price book entry should be copyable.');
        }

        Assert.areEqual(
            'SKU-1001',
            rowByName.get(TestDataFactory.LB_PRODUCT_A_NAME).productSku,
            'The stored SKU should be returned.'
        );
        Assert.areEqual(
            TestDataFactory.LB_PRODUCT_B_CODE,	
            rowByName.get(TestDataFactory.LB_PRODUCT_B_NAME).productSku,
            'Product code should fill a blank SKU.'
        );
        Assert.areEqual(
            40,
            rowByName.get(TestDataFactory.LB_PRODUCT_A_NAME).unitPrice.intValue(),
            'Unit price should come from the originating line.'
        );
    }

    /**
     * @description
     * GC-3574 - Confirms a blank originating opportunity is treated as having no products to copy.
     *
     * @return void
     */
    @IsTest
    static void getOriginatingProductsWithBlankIdReturnsEmptyList() {
        Test.startTest();
        List<LostBusinessProductController.OriginatingProductRow> productRowList =
            LostBusinessProductController.getOriginatingProducts(null);
        Test.stopTest();

        Assert.isTrue(productRowList.isEmpty(), 'A blank originating opportunity has no products to copy.');
    }

    /**
     * @description
     * GC-3574 - Confirms an invalid originating opportunity Id is returned to the screen.
     *
     * @return void
     */
    @IsTest
    static void getOriginatingProductsRejectsAnInvalidId() {
        Test.startTest();
        try {
            LostBusinessProductController.getOriginatingProducts('not-an-id');
            Assert.fail('An AuraHandledException was expected.');
        } catch (AuraHandledException expectedException) {
            Assert.isTrue(
                expectedException.getMessage().contains('not valid'),
                'Expected an invalid Id message but it was "' + expectedException.getMessage() + '".'
            );
        }
        Test.stopTest();
    }

    /**
     * @description
     * GC-3574 - Confirms the catalogue screen receives the active Consumption Frequency values.
     *
     * @return void
     */
    @IsTest
    static void getConsumptionFrequencyOptionsReturnsActiveValues() {
        Test.startTest();
        List<LostBusinessProductController.PicklistOption> optionList =
            LostBusinessProductController.getConsumptionFrequencyOptions();
        Test.stopTest();

        Assert.isFalse(optionList.isEmpty(), 'Consumption Frequency should have active values.');
        Assert.isTrue(String.isNotBlank(optionList[0].label), 'Each option should have a label.');
        Assert.isTrue(String.isNotBlank(optionList[0].value), 'Each option should have a value.');
    }

    /**
     * @description
     * GC-3574 - Confirms catalogue search returns active products and excludes inactive products.
     *
     * @return void
     */
    @IsTest
    static void searchProductsReturnsActiveProductsOnly() {
        Test.startTest();
        List<LostBusinessProductController.ProductWrapper> productList =
            LostBusinessProductController.searchProducts('LB-3574', null);
        Test.stopTest();

        Assert.areEqual(3, productList.size(), 'Only the three active priced products should be returned.');

        for (LostBusinessProductController.ProductWrapper productWrapper : productList) {
            Assert.areNotEqual(
                TestDataFactory.LB_INACTIVE_PRODUCT_NAME,
                productWrapper.productName,
                'Inactive products should not be returned.'
            );
            Assert.isNull(productWrapper.unitPrice, 'Unit price stays blank when no Lost Business opportunity is supplied.');
        }
    }

    /**
     * @description
     * GC-3574 - Confirms search shows the Lost Business price book unit price, and ignores a bad opportunity Id.
     *
     * @return void
     */
    @IsTest
    static void searchProductsReturnsPricebookUnitPrice() {
        TestDataFactory.LostBusinessProductContext context = data();

        Test.startTest();
        List<LostBusinessProductController.ProductWrapper> pricedProducts =
            LostBusinessProductController.searchProducts('LB-3574', context.lostOpportunityId);
        List<LostBusinessProductController.ProductWrapper> unpricedProducts =
            LostBusinessProductController.searchProducts('LB-3574', 'not-an-id');
        List<LostBusinessProductController.ProductWrapper> unknownOpportunityProducts =
            LostBusinessProductController.searchProducts('LB-3574', context.accountId);
        List<LostBusinessProductController.ProductWrapper> noMatch =
            LostBusinessProductController.searchProducts('ZZZ-NO-MATCH-3574', context.unpricedOpportunityId);
        List<LostBusinessProductController.ProductWrapper> standardPriceProducts =
            LostBusinessProductController.searchProducts('LB-3574', context.unpricedOpportunityId);
        Test.stopTest();

        Assert.isTrue(noMatch.isEmpty(), 'An unmatched search should return no products.');

        for (LostBusinessProductController.ProductWrapper productWrapper : standardPriceProducts) {
            Assert.areEqual(
                25,
                productWrapper.unitPrice.intValue(),
                'A Lost Business opportunity without a price book should show the standard price.'
            );
        }

        for (LostBusinessProductController.ProductWrapper productWrapper : pricedProducts) {
            Assert.areEqual(25, productWrapper.unitPrice.intValue(), 'Unit price should come from the price book.');
        }

        for (LostBusinessProductController.ProductWrapper productWrapper : unpricedProducts) {
            Assert.isNull(productWrapper.unitPrice, 'An invalid opportunity Id should leave unit price blank.');
        }

        for (LostBusinessProductController.ProductWrapper productWrapper : unknownOpportunityProducts) {
            Assert.isNull(productWrapper.unitPrice, 'A missing opportunity should leave unit price blank.');
        }
    }

    /**
     * @description
     * GC-3574 - Confirms an unexpected search failure is surfaced to the LWC.
     *
     * @return void
     */
    @IsTest
    static void searchProductsHandlesUnexpectedException() {
        LostBusinessProductService.throwTestException = true;

        Test.startTest();
        try {
            LostBusinessProductController.searchProducts('LB-3574', null);
            Assert.fail('An AuraHandledException was expected.');
        } catch (AuraHandledException expectedException) {
            Assert.isTrue(
                expectedException.getMessage().contains('Unable to search products'),
                'Expected the search failure message but it was "' + expectedException.getMessage() + '".'
            );
        }
        Test.stopTest();

        LostBusinessProductService.throwTestException = false;
    }

    /**
     * @description
     * GC-3574 - Confirms only the selected originating product is copied, with the edited quantity
     * and frequency, while the originating line keeps its own values.
     *
     * @return void
     */
    @IsTest
    static void createProductsCopiesOnlyTheSelectedLine() {
        TestDataFactory.LostBusinessProductContext context = data();
        OpportunityLineItem sourceLine = [
            SELECT Id, Quantity, UnitPrice, PricebookEntryId
            FROM OpportunityLineItem
            WHERE Id = :context.originatingLineAId
        ];
        String editedFrequency = firstActivePicklistValue(OpportunityLineItem.ConsumptionFrequency__c);
        LostBusinessProductController.ProductInput productInput = copyInput(sourceLine.Id, 3);
        productInput.unitPrice = 999;
        productInput.consumptionFrequency = editedFrequency;

        Test.startTest();
        Integer createdCount = LostBusinessProductController.createLostBusinessProducts(
            context.lostOpportunityId,
            context.originatingOpportunityId,
            JSON.serialize(new List<LostBusinessProductController.ProductInput>{ productInput })
        );
        Test.stopTest();

        Assert.areEqual(1, createdCount, 'Only the selected product should be created.');

        OpportunityLineItem sourceAfter = [
            SELECT Quantity, UnitPrice
            FROM OpportunityLineItem
            WHERE Id = :sourceLine.Id
        ];
        Assert.areEqual(sourceLine.Quantity, sourceAfter.Quantity, 'The originating quantity must stay unchanged.');
        Assert.areEqual(sourceLine.UnitPrice, sourceAfter.UnitPrice, 'The originating unit price must stay unchanged.');

        List<OpportunityLineItem> copiedLineList = [
            SELECT Quantity, UnitPrice, ConsumptionFrequency__c, Product_Number_SKU__c, PricebookEntryId
            FROM OpportunityLineItem
            WHERE OpportunityId = :context.lostOpportunityId
        ];
        Assert.areEqual(1, copiedLineList.size(), 'The deselected product should not be created.');
        Assert.areEqual(3, copiedLineList[0].Quantity.intValue(), 'The edited quantity should be stored on the new line.');
        Assert.areEqual(sourceLine.UnitPrice, copiedLineList[0].UnitPrice, 'Unit price should be copied from the originating line.');
        Assert.areEqual('SKU-1001', copiedLineList[0].Product_Number_SKU__c, 'SKU should be copied.');
        Assert.areEqual(
            editedFrequency,
            copiedLineList[0].ConsumptionFrequency__c,
            'The edited consumption frequency should be stored on the new line.'
        );
        Assert.areEqual(
            sourceLine.PricebookEntryId,
            copiedLineList[0].PricebookEntryId,
            'The originating price book entry should be reused.'
        );
    }

    /**
     * @description
     * GC-3574 - Confirms a copied product uses the Lost Business price book when the originating
     * entry belongs to a different price book, and a blank SKU falls back to the product code.
     *
     * @return void
     */
    @IsTest
    static void createProductsUsesLostBusinessPricebookEntryAndBlankSku() {
        TestDataFactory.LostBusinessProductContext context = data();
        LostBusinessProductController.ProductInput customInput = copyInput(context.customPricebookLineId, 2);
        LostBusinessProductController.ProductInput blankSkuInput = copyInput(context.originatingLineBId, 4);
        blankSkuInput.consumptionFrequency = '   ';

        Test.startTest();
        Integer createdCount = LostBusinessProductController.createLostBusinessProducts(
            context.lostOpportunityId,
            context.customPricebookOpportunityId,
            JSON.serialize(new List<LostBusinessProductController.ProductInput>{ customInput })
        );
        Integer blankSkuCount = LostBusinessProductController.createLostBusinessProducts(
            context.unpricedOpportunityId,
            context.originatingOpportunityId,
            JSON.serialize(new List<LostBusinessProductController.ProductInput>{ blankSkuInput })
        );
        Test.stopTest();

        Assert.areEqual(1, createdCount, 'The custom price book product should be copied onto the standard price book.');
        OpportunityLineItem copiedCustomLine = [
            SELECT PricebookEntryId, UnitPrice, Product_Number_SKU__c
            FROM OpportunityLineItem
            WHERE OpportunityId = :context.lostOpportunityId
        ];
        Assert.areEqual(
            context.standardEntryAId,
            copiedCustomLine.PricebookEntryId,
            'The Lost Business price book entry should be used.'
        );
        Assert.areEqual(55, copiedCustomLine.UnitPrice.intValue(), 'The originating unit price should be copied.');
        Assert.areEqual('SKU-CUSTOM', copiedCustomLine.Product_Number_SKU__c, 'The stored SKU should be copied.');

        Assert.areEqual(1, blankSkuCount, 'The blank-SKU product should be copied.');
        Opportunity updatedOpportunity = [
            SELECT Pricebook2Id
            FROM Opportunity
            WHERE Id = :context.unpricedOpportunityId
        ];
        Assert.areEqual(
            context.standardPricebookId,
            updatedOpportunity.Pricebook2Id,
            'The originating price book should be set on the Lost Business opportunity.'
        );
        OpportunityLineItem blankSkuLine = [
            SELECT Product_Number_SKU__c, ConsumptionFrequency__c
            FROM OpportunityLineItem
            WHERE OpportunityId = :context.unpricedOpportunityId
        ];
        Assert.areEqual(
            TestDataFactory.LB_PRODUCT_B_CODE,
            blankSkuLine.Product_Number_SKU__c,
            'Product code should fill a blank SKU.'
        );
        Assert.isNull(blankSkuLine.ConsumptionFrequency__c, 'A blank frequency should be stored as null.');
    }

    /**
     * @description
     * GC-3574 - Confirms submitting the same selection again does not create a second line.
     *
     * @return void
     */
    @IsTest
    static void createProductsSkipsAPricebookEntryAlreadyOnTheOpportunity() {
        TestDataFactory.LostBusinessProductContext context = data();
        String payload = JSON.serialize(new List<LostBusinessProductController.ProductInput>{
            copyInput(context.originatingLineAId, 2)
        });

        Test.startTest();
        LostBusinessProductController.createLostBusinessProducts(
            context.lostOpportunityId,
            context.originatingOpportunityId,
            payload
        );
        Integer secondCount = LostBusinessProductController.createLostBusinessProducts(
            context.lostOpportunityId,
            context.originatingOpportunityId,
            payload
        );
        Test.stopTest();

        Assert.areEqual(0, secondCount, 'The second submit should not create another line.');
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM OpportunityLineItem WHERE OpportunityId = :context.lostOpportunityId],
            'One Opportunity Product should remain.'
        );
    }

    /**
     * @description
     * GC-3574 - Confirms a product from another opportunity cannot be copied onto the Lost Business opportunity.
     *
     * @return void
     */
    @IsTest
    static void createProductsRejectsALineFromAnotherOpportunity() {
        TestDataFactory.LostBusinessProductContext context = data();

        assertSaveFails(
            context.lostOpportunityId,
            context.originatingOpportunityId,
            JSON.serialize(new List<LostBusinessProductController.ProductInput>{
                copyInput(context.otherLineId, 1)
            }),
            'does not belong to the originating opportunity'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM OpportunityLineItem WHERE OpportunityId = :context.lostOpportunityId],
            'A rejected copy should not leave a product behind.'
        );
    }

    /**
     * @description
     * GC-3574 - Confirms copy validation rejects a missing opportunity, a bad reference, and a zero quantity.
     *
     * @return void
     */
    @IsTest
    static void createProductsRejectsInvalidCopySelections() {
        TestDataFactory.LostBusinessProductContext context = data();
        String validLinePayload = JSON.serialize(new List<LostBusinessProductController.ProductInput>{
            copyInput(context.originatingLineAId, 1)
        });

        expectCreateError(null, context.originatingOpportunityId, validLinePayload, 'A Lost Business Opportunity is required');
        expectCreateError(context.lostOpportunityId, context.originatingOpportunityId, '{', 'could not be read');
        expectCreateError('not-an-id', context.originatingOpportunityId, validLinePayload, 'not valid');
        expectCreateError(context.accountId, context.originatingOpportunityId, validLinePayload, 'could not be found');
        expectCreateError(context.lostOpportunityId, 'not-an-id', validLinePayload, 'not valid');
        expectCreateError(
            context.lostOpportunityId,
            null,
            validLinePayload,
            'An originating Opportunity is required'
        );
        expectCreateError(
            context.lostOpportunityId,
            context.originatingOpportunityId,
            JSON.serialize(new List<LostBusinessProductController.ProductInput>{ copyInput(context.originatingLineAId, 0) }),
            'Quantity must be greater than zero'
        );
        expectCreateError(
            context.lostOpportunityId,
            context.originatingOpportunityId,
            JSON.serialize(new List<LostBusinessProductController.ProductInput>{
                copyInput(context.originatingLineAId, null)
            }),
            'Quantity must be greater than zero'
        );

        LostBusinessProductController.ProductInput invalidLine = new LostBusinessProductController.ProductInput();
        invalidLine.sourceLineItemId = 'not-an-id';
        invalidLine.quantity = 1;
        expectCreateError(
            context.lostOpportunityId,
            context.originatingOpportunityId,
            JSON.serialize(new List<LostBusinessProductController.ProductInput>{ invalidLine }),
            'not a valid Opportunity Product'
        );

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM OpportunityLineItem WHERE OpportunityId = :context.lostOpportunityId],
            'Rejected copies should not leave a product behind.'
        );
    }

    /**
     * @description
     * GC-3574 - Confirms finishing with no selection does not create products.
     *
     * @return void
     */
    @IsTest
    static void createProductsWithNoSelectionReturnsZero() {
        TestDataFactory.LostBusinessProductContext context = data();

        Test.startTest();
        Integer emptyCount = LostBusinessProductController.createLostBusinessProducts(
            context.lostOpportunityId,
            context.originatingOpportunityId,
            '[]'
        );
        Integer blankCount = LostBusinessProductController.createLostBusinessProducts(
            context.lostOpportunityId,
            context.originatingOpportunityId,
            '   '
        );
        Integer nullCount = LostBusinessProductController.createLostBusinessProducts(
            context.lostOpportunityId,
            context.originatingOpportunityId,
            null
        );
        Integer nullJsonCount = LostBusinessProductController.createLostBusinessProducts(
            context.lostOpportunityId,
            null,
            'null'
        );
        Test.stopTest();

        Assert.areEqual(0, emptyCount, 'An empty selection should create no products.');
        Assert.areEqual(0, blankCount, 'A blank payload should create no products.');
        Assert.areEqual(0, nullCount, 'A null payload should create no products.');
        Assert.areEqual(0, nullJsonCount, 'A JSON null payload should create no products.');
    }

    /**
     * @description
     * GC-3574 - Confirms a catalogue selection creates an Opportunity Product and sets the price book
     * when the Lost Business opportunity does not have one yet.
     *
     * @return void
     */
    @IsTest
    static void createProductsFromCatalogueSetsPricebookAndLineFields() {
        TestDataFactory.LostBusinessProductContext context = data();
        String consumptionFrequency = firstActivePicklistValue(OpportunityLineItem.ConsumptionFrequency__c);
        String statusValue = firstActivePicklistValue(OpportunityLineItem.Status__c);
        String confidenceValue = firstActivePicklistValue(OpportunityLineItem.ConfidenceLevel__c);
        LostBusinessProductController.ProductInput productInput = catalogueInput(context.productCId, 6, 12.5);
        productInput.consumptionFrequency = consumptionFrequency;
        productInput.status = statusValue;
        productInput.confidenceLevel = confidenceValue;
        productInput.expectedShipDate = Date.today().addDays(10);
        productInput.contractValue = 'CTR-3574';
        productInput.comments = 'Partial loss';

        Test.startTest();
        Integer createdCount = LostBusinessProductController.createLostBusinessProducts(
            context.unpricedOpportunityId,
            null,
            JSON.serialize(new List<LostBusinessProductController.ProductInput>{ productInput })
        );
        Integer secondCount = LostBusinessProductController.createLostBusinessProducts(
            context.unpricedOpportunityId,
            null,
            JSON.serialize(new List<LostBusinessProductController.ProductInput>{ productInput })
        );
        Test.stopTest();

        Assert.areEqual(1, createdCount, 'The catalogue product should be created.');
        Assert.areEqual(0, secondCount, 'Submitting the same catalogue product again should not create another line.');

        Opportunity updatedOpportunity = [
            SELECT Pricebook2Id
            FROM Opportunity
            WHERE Id = :context.unpricedOpportunityId
        ];
        Assert.areEqual(
            Test.getStandardPricebookId(),
            updatedOpportunity.Pricebook2Id,
            'The standard price book should be set before the product is added.'
        );

        OpportunityLineItem createdLine = [
            SELECT Quantity, UnitPrice, ConsumptionFrequency__c, Status__c, ConfidenceLevel__c,
                   ExpectedShipDate_ConsumptionStart__c, Contract__c, Comments__c, Product_Number_SKU__c
            FROM OpportunityLineItem
            WHERE OpportunityId = :updatedOpportunity.Id
        ];
        Assert.areEqual(6, createdLine.Quantity.intValue(), 'Quantity should be stored.');
        Assert.areEqual(12.5, createdLine.UnitPrice, 'The entered unit price should be stored.');
        Assert.areEqual(consumptionFrequency, createdLine.ConsumptionFrequency__c, 'Consumption frequency should be stored.');
        Assert.areEqual(statusValue, createdLine.Status__c, 'Status should be stored.');
        Assert.areEqual(confidenceValue, createdLine.ConfidenceLevel__c, 'Confidence level should be stored.');
        Assert.areEqual(Date.today().addDays(10), createdLine.ExpectedShipDate_ConsumptionStart__c, 'The ship date should be stored.');
        Assert.areEqual('CTR-3574', createdLine.Contract__c, 'Contract should be stored.');
        Assert.areEqual('Partial loss', createdLine.Comments__c, 'Comments should be stored.');
        Assert.areEqual(
            TestDataFactory.LB_PRODUCT_C_CODE,
            createdLine.Product_Number_SKU__c,
            'Product code should be stored as the SKU.'
        );
    }

    /**
     * @description
     * GC-3574 - Confirms a catalogue row with no unit price stores the price book price.
     *
     * @return void
     */
    @IsTest
    static void createProductsFromCatalogueUsesPricebookPriceWhenUnitPriceIsBlank() {
        TestDataFactory.LostBusinessProductContext context = data();
        LostBusinessProductController.ProductInput productInput = catalogueInput(context.productCId, 2, null);

        Test.startTest();
        Integer createdCount = LostBusinessProductController.createLostBusinessProducts(
            context.lostOpportunityId,
            null,
            JSON.serialize(new List<LostBusinessProductController.ProductInput>{ productInput })
        );
        Test.stopTest();

        Assert.areEqual(1, createdCount, 'The catalogue product should be created.');
        OpportunityLineItem createdLine = [
            SELECT UnitPrice
            FROM OpportunityLineItem
            WHERE OpportunityId = :context.lostOpportunityId
        ];
        Assert.areEqual(25, createdLine.UnitPrice.intValue(), 'A blank unit price should use the price book price.');
    }

    /**
     * @description
     * GC-3574 - Confirms catalogue validation rejects inactive products, missing prices, and bad field values.
     *
     * @return void
     */
    @IsTest
    static void createProductsRejectsInvalidCatalogueSelections() {
        TestDataFactory.LostBusinessProductContext context = data();
        String lostOpportunityId = context.lostOpportunityId;

        LostBusinessProductController.ProductInput missingProduct = catalogueInput(null, 1, 10);
        expectCreateError(lostOpportunityId, null, JSON.serialize(new List<LostBusinessProductController.ProductInput>{ missingProduct }), 'missing its product reference');

        LostBusinessProductController.ProductInput invalidProduct = new LostBusinessProductController.ProductInput();
        invalidProduct.productId = 'not-an-id';
        invalidProduct.quantity = 1;
        expectCreateError(lostOpportunityId, null, JSON.serialize(new List<LostBusinessProductController.ProductInput>{ invalidProduct }), 'not a valid product');

        expectCreateError(
            lostOpportunityId,
            null,
            JSON.serialize(new List<LostBusinessProductController.ProductInput>{ catalogueInput(context.productCId, 0, 10) }),
            'Quantity must be greater than zero'
        );
        expectCreateError(
            lostOpportunityId,
            null,
            JSON.serialize(new List<LostBusinessProductController.ProductInput>{ catalogueInput(context.productCId, 1, -1) }),
            'Unit Price cannot be negative'
        );

        LostBusinessProductController.ProductInput longContract = catalogueInput(context.productCId, 1, 10);
        longContract.contractValue = '1234567890123456789';
        expectCreateError(lostOpportunityId, null, JSON.serialize(new List<LostBusinessProductController.ProductInput>{ longContract }), 'Contract cannot be longer than 18');

        LostBusinessProductController.ProductInput longComments = catalogueInput(context.productCId, 1, 10);
        longComments.comments = 'x'.repeat(251);
        expectCreateError(lostOpportunityId, null, JSON.serialize(new List<LostBusinessProductController.ProductInput>{ longComments }), 'Comments cannot be longer than 250');

        expectCreateError(
            lostOpportunityId,
            null,
            JSON.serialize(new List<LostBusinessProductController.ProductInput>{ catalogueInput(context.inactiveProductId, 1, 10) }),
            'no longer active'
        );
        expectCreateError(
            lostOpportunityId,
            null,
            JSON.serialize(new List<LostBusinessProductController.ProductInput>{ catalogueInput(context.productWithoutPriceId, 1, 10) }),
            'is not available on the opportunity price book'
        );

        if (OpportunityLineItem.ConsumptionFrequency__c.getDescribe().isRestrictedPicklist()) {
            LostBusinessProductController.ProductInput invalidFrequency = catalogueInput(context.productCId, 1, 10);
            invalidFrequency.consumptionFrequency = 'NOT_A_REAL_FREQUENCY';
            expectCreateError(
                lostOpportunityId,
                null,
                JSON.serialize(new List<LostBusinessProductController.ProductInput>{ invalidFrequency }),
                'restricted picklist'
            );
        }

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM OpportunityLineItem WHERE OpportunityId = :context.lostOpportunityId],
            'Rejected catalogue rows should not leave a product behind.'
        );
    }

    /**
     * @description
     * GC-3574 - Confirms an unexpected save failure is surfaced to the LWC.
     *
     * @return void
     */
    @IsTest
    static void createProductsHandlesUnexpectedException() {
        TestDataFactory.LostBusinessProductContext context = data();
        LostBusinessProductService.throwTestException = true;

        Test.startTest();
        try {
            LostBusinessProductController.createLostBusinessProducts(
                context.lostOpportunityId,
                context.originatingOpportunityId,
                JSON.serialize(new List<LostBusinessProductController.ProductInput>{
                    copyInput(context.originatingLineAId, 1)
                })
            );
            Assert.fail('An AuraHandledException was expected.');
        } catch (AuraHandledException expectedException) {
            Assert.isTrue(
                expectedException.getMessage().contains('Unable to add products'),
                'Expected the save failure message but it was "' + expectedException.getMessage() + '".'
            );
        }
        Test.stopTest();

        LostBusinessProductService.throwTestException = false;
    }

    /**
     * @description
     * GC-3574 - Confirms an unexpected load failure is surfaced to the LWC.
     *
     * @return void
     */
    @IsTest
    static void getOriginatingProductsHandlesUnexpectedException() {
        TestDataFactory.LostBusinessProductContext context = data();
        LostBusinessProductService.throwTestException = true;

        Test.startTest();
        try {
            LostBusinessProductController.getOriginatingProducts(context.originatingOpportunityId);
            Assert.fail('An AuraHandledException was expected.');
        } catch (AuraHandledException expectedException) {
            Assert.isNotNull(expectedException, 'The exception should be surfaced to the LWC.');
        }
        Test.stopTest();

        LostBusinessProductService.throwTestException = false;
    }

    /**
     * @description
     * GC-3574 - Confirms an inactive originating price book entry is reported and cannot be copied.
     *
     * @return void
     */
    @IsTest
    static void inactivePricebookEntryCannotBeCopied() {
        TestDataFactory.LostBusinessProductContext context = data();
        update new PricebookEntry(Id = context.standardEntryCId, IsActive = false);

        Test.startTest();
        List<LostBusinessProductController.OriginatingProductRow> productRowList =
            LostBusinessProductController.getOriginatingProducts(context.otherOpportunityId);
        Test.stopTest();

        Assert.areEqual(1, productRowList.size(), 'The inactive product should still be shown.');
        Assert.isFalse(productRowList[0].copyable, 'An inactive price book entry should not be copyable.');
        Assert.isTrue(
            productRowList[0].unavailableReason.contains('inactive'),
            'The row should explain why it cannot be copied.'
        );

        expectCreateError(
            context.lostOpportunityId,
            context.otherOpportunityId,
            JSON.serialize(new List<LostBusinessProductController.ProductInput>{
                copyInput(context.otherLineId, 1)
            }),
            'price book entry is inactive'
        );
    }

    /**
     * @description
     * GC-3574 - Confirms the selector ignores a blank request and can read an active price book entry.
     *
     * @return void
     */
    @IsTest
    static void selectorReturnsEmptyCollectionsForBlankInput() {
        TestDataFactory.LostBusinessProductContext context = data();
        String currencyCode = [
            SELECT CurrencyIsoCode
            FROM PricebookEntry
            WHERE Id = :context.standardEntryAId
        ].CurrencyIsoCode;

        Test.startTest();
        Assert.isNull(LostBusinessProductSelector.selectOpportunityById(null), 'A blank Id should not be queried.');
        Assert.isNull(
            LostBusinessProductSelector.selectOpportunityById(context.accountId),
            'An Id that is not an opportunity should return null.'
        );
        Assert.isTrue(
            LostBusinessProductSelector.selectLinesByOpportunityId(null).isEmpty(),
            'A blank opportunity should return no lines.'
        );
        Assert.isTrue(
            LostBusinessProductSelector.selectLinesByIdsAndOpportunity(null, context.originatingOpportunityId).isEmpty(),
            'A null line set should return no lines.'
        );
        Assert.isTrue(
            LostBusinessProductSelector.selectLinesByIdsAndOpportunity(new Set<Id>(), context.originatingOpportunityId).isEmpty(),
            'An empty line set should return no lines.'
        );
        Assert.isTrue(
            LostBusinessProductSelector.selectLinesByIdsAndOpportunity(new Set<Id>{ context.originatingLineAId }, null).isEmpty(),
            'A blank opportunity should return no selected lines.'
        );
        Assert.isTrue(
            LostBusinessProductSelector.selectPricebookEntryIds(null).isEmpty(),
            'A blank opportunity should return no price book entries.'
        );
        Assert.isTrue(
            LostBusinessProductSelector.selectActiveProducts(null).isEmpty(),
            'A null product set should return no products.'
        );
        Assert.isTrue(
            LostBusinessProductSelector.selectActiveProducts(new Set<Id>()).isEmpty(),
            'An empty product set should return no products.'
        );
        Assert.isTrue(
            LostBusinessProductSelector.selectActiveEntries(null, new Set<Id>{ context.productAId }, currencyCode).isEmpty(),
            'A blank price book should return no entries.'
        );
        Assert.isTrue(
            LostBusinessProductSelector.selectActiveEntries(context.standardPricebookId, new Set<Id>(), currencyCode).isEmpty(),
            'An empty product set should return no entries.'
        );
        Assert.isTrue(
            LostBusinessProductSelector.selectActiveEntries(context.standardPricebookId, new Set<Id>{ context.productAId }, null).isEmpty(),
            'A blank currency should return no entries.'
        );
        Assert.areEqual(
            1,
            LostBusinessProductSelector.selectActiveEntries(
                context.standardPricebookId,
                new Set<Id>{ context.productAId },
                currencyCode
            ).size(),
            'The active standard price book entry should be returned.'
        );
        Assert.areEqual(
            Test.getStandardPricebookId(),
            LostBusinessProductSelector.selectStandardPricebookId(),
            'The standard price book Id should be returned.'
        );
        update new Pricebook2(Id = Test.getStandardPricebookId(), IsActive = true);
        Assert.areEqual(
            Test.getStandardPricebookId(),
            LostBusinessProductSelector.selectStandardPricebookId(),
            'The queried standard price book Id should be returned after it is visible.'
        );
        Assert.areEqual(
            1,
            LostBusinessProductSelector.selectActiveProducts(new Set<Id>{ context.productAId }).size(),
            'The active product should be returned.'
        );
        Test.stopTest();
    }

    /**
     * @description
     * GC-3574 - Loads the scenario created by test setup.
     *
     * @return Scenario Ids.
     */
    private static TestDataFactory.LostBusinessProductContext data() {
        return TestDataFactory.loadLostBusinessProductContext();
    }

    /**
     * @description
     * GC-3574 - Builds a copy payload row.
     *
     * @param sourceLineItemId Originating Opportunity Product Id.
     * @param quantity Quantity to send.
     * @return Product input.
     */
    private static LostBusinessProductController.ProductInput copyInput(Id sourceLineItemId, Decimal quantity) {
        LostBusinessProductController.ProductInput productInput = new LostBusinessProductController.ProductInput();
        productInput.sourceLineItemId = sourceLineItemId;
        productInput.quantity = quantity;
        return productInput;
    }

    /**
     * @description
     * GC-3574 - Builds a catalogue payload row.
     *
     * @param productId Product2 Id.
     * @param quantity Quantity to send.
     * @param unitPrice Unit price to send.
     * @return Product input.
     */
    private static LostBusinessProductController.ProductInput catalogueInput(
        Id productId,
        Decimal quantity,
        Decimal unitPrice
    ) {
        LostBusinessProductController.ProductInput productInput = new LostBusinessProductController.ProductInput();
        productInput.productId = productId;
        productInput.quantity = quantity;
        productInput.unitPrice = unitPrice;
        return productInput;
    }

    /**
     * @description
     * GC-3574 - First active picklist value, or null when the field has none.
     *
     * @param picklistField Picklist field.
     * @return Active value, or null.
     */
    private static String firstActivePicklistValue(Schema.SObjectField picklistField) {
        for (Schema.PicklistEntry picklistEntry : picklistField.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return null;
    }

    /**
     * @description
     * GC-3574 - Asserts the save is rejected and the exception message contains the expected text.
     *
     * @param lostOpportunityId Lost Business opportunity Id.
     * @param originatingOpportunityId Originating opportunity Id.
     * @param productInputsJson JSON payload.
     * @param expectedMessage Fragment expected in the exception message.
     */
    private static void assertSaveFails(
        String lostOpportunityId,
        String originatingOpportunityId,
        String productInputsJson,
        String expectedMessage
    ) {
        Test.startTest();
        expectCreateError(lostOpportunityId, originatingOpportunityId, productInputsJson, expectedMessage);
        Test.stopTest();
    }

    /**
     * @description
     * GC-3574 - Asserts one save is rejected. Does not start a new test boundary, so several
     * validations can be checked in one test method.
     *
     * @param lostOpportunityId Lost Business opportunity Id.
     * @param originatingOpportunityId Originating opportunity Id.
     * @param productInputsJson JSON payload.
     * @param expectedMessage Fragment expected in the exception message.
     */
    private static void expectCreateError(
        String lostOpportunityId,
        String originatingOpportunityId,
        String productInputsJson,
        String expectedMessage
    ) {
        try {
            LostBusinessProductController.createLostBusinessProducts(
                lostOpportunityId,
                originatingOpportunityId,
                productInputsJson
            );
            Assert.fail('An AuraHandledException was expected.');
        } catch (AuraHandledException expectedException) {
            Assert.isTrue(
                expectedException.getMessage().contains(expectedMessage),
                'Expected the message to contain "' + expectedMessage + '" but it was "' +
                expectedException.getMessage() + '".'
            );
        }
    }
}