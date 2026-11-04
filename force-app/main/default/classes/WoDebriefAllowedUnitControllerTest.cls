/**
 * @author Uptima Development Team
 * @date 2026-07-15
 * @description Tests for WoDebriefAllowedUnitController LWC entry point.
 * @group Work Order Debrief
 * @see WoDebriefAllowedUnitController
 */
@IsTest
private class WoDebriefAllowedUnitControllerTest {
    /**
     * @description Verifies controller delegates and returns unevaluated when WO has no Asset.
     */
    @IsTest
    static void testEvaluateAllowedUnitNoAsset() {
        Account account = new Account(
            Name = 'Allowed Unit Controller Account',
            SourceSystemID__c = 'ORACLE-AUCTRL-' + String.valueOf(Crypto.getRandomInteger())
        );
        insert account;

        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'Allowed Unit Controller WO'
        );
        insert workOrder;

        Product2 product = new Product2(Name = 'Allowed Unit Controller Part', IsActive = true);
        insert product;

        Test.startTest();
        AllowedUnitEvaluationDTO result =
            WoDebriefAllowedUnitController.evaluateAllowedUnit(workOrder.Id, product.Id);
        Test.stopTest();

        System.assertEquals(false, result.hasAsset, 'Expected no asset on Work Order');
        System.assertEquals(false, result.evaluated, 'Evaluation should be skipped without an Asset');
        System.assertEquals(null, result.allowedUnit, 'Allowed Unit should remain unset');
    }

    /**
     * @description GW-4311 - Verifies Product2 Allowed Unit evaluation for blank Ids.
     */
    @IsTest
    static void testEvaluateAllowedUnitByProductBlankIds() {
        Test.startTest();
        AllowedUnitEvaluationDTO result =
            WoDebriefAllowedUnitController.evaluateAllowedUnitByProduct(null, null);
        Test.stopTest();

        System.assertEquals(false, result.hasAsset);
        System.assertEquals(false, result.evaluated);
    }

    /**
     * @description Verifies controller returns unevaluated DTO for blank Ids.
     */
    @IsTest
    static void testEvaluateAllowedUnitBlankIds() {
        Test.startTest();
        AllowedUnitEvaluationDTO result =
            WoDebriefAllowedUnitController.evaluateAllowedUnit(null, null);
        Test.stopTest();

        System.assertEquals(false, result.hasAsset);
        System.assertEquals(false, result.evaluated);
        System.assertEquals(null, result.allowedUnit);
    }

    /**
     * @description Verifies WorkOrderLineItemsServiceException is surfaced as AuraHandledException.
     */
    @IsTest
    static void testEvaluateAllowedUnit_serviceException_throwsAuraHandled() {
        WorkOrderLineItemsService.simulateQueryException = true;
        Id dummyId = UserInfo.getUserId();

        try {
            Test.startTest();
            WoDebriefAllowedUnitController.evaluateAllowedUnit(dummyId, dummyId);
            Test.stopTest();
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(String.isNotBlank(e.getMessage()), 'Expected exception message');
        } finally {
            WorkOrderLineItemsService.simulateQueryException = false;
        }
    }

    /**
     * @description Verifies generic service failures (wrapped as WorkOrderLineItemsServiceException)
     *              are also surfaced as AuraHandledException.
     */
    @IsTest
    static void testEvaluateAllowedUnit_wrappedGenericException_throwsAuraHandled() {
        WorkOrderLineItemsService.simulateGenericException = true;
        Id dummyId = UserInfo.getUserId();

        try {
            Test.startTest();
            WoDebriefAllowedUnitController.evaluateAllowedUnit(dummyId, dummyId);
            Test.stopTest();
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(String.isNotBlank(e.getMessage()), 'Expected exception message');
        } finally {
            WorkOrderLineItemsService.simulateGenericException = false;
        }
    }

    /**
     * @description Verifies repair-code lookup delegates for a null product Id.
     */
    @IsTest
    static void getRepairCodesForProduct_nullProduct_returnsEmpty() {
        Test.startTest();
        WoDebriefIMSchildWOController.RepairCodesForProductResult result =
            WoDebriefAllowedUnitController.getRepairCodesForProduct(null);
        Test.stopTest();

        System.assertEquals('', result.baseServiceCode);
        System.assertEquals(0, result.options.size());
    }

    /**
     * @description Verifies pricebook-entry resolve returns null for blank Ids.
     */
    @IsTest
    static void resolvePricebookEntryId_blankInputs_returnsNull() {
        Test.startTest();
        Id result = WoDebriefAllowedUnitController.resolvePricebookEntryId(null, null);
        Test.stopTest();

        System.assertEquals(null, result);
    }

    /**
     * @description GW-6095 - Verifies the pricebook entry of the Work Order price book and currency is returned.
     */
    @IsTest
    static void resolvePricebookEntryId_matchingEntry_returnsEntryId() {
        // GIVEN: a Work Order on the standard price book and an active entry for the product
        Id pricebookId = Test.getStandardPricebookId();
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .account(new adb_Account().name('Pricebook Entry Controller Account'))
            .status('Evaluate & Quote')
            .subject('Pricebook Entry Controller WO')
            .setRecordType('RepairCenterInstruments')
            .pricebook2Id(pricebookId);
        workOrderBuilder.persist();
        WorkOrder workOrder = [
            SELECT Id, CurrencyIsoCode
            FROM WorkOrder
            WHERE Id = :workOrderBuilder.record.Id
        ];
        Product2 product = new Product2(Name = 'Pricebook Entry Controller Product', IsActive = true);
        insert product;
        PricebookEntry pricebookEntry = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );
        if (String.isNotBlank(workOrder.CurrencyIsoCode)) {
            pricebookEntry.CurrencyIsoCode = workOrder.CurrencyIsoCode;
        }
        insert pricebookEntry;

        // WHEN
        Test.startTest();
        Id result = WoDebriefAllowedUnitController.resolvePricebookEntryId(workOrder.Id, product.Id);
        Test.stopTest();

        // THEN
        System.assertEquals(pricebookEntry.Id, result, 'The matching pricebook entry should be returned');
    }

    /**
     * @description GW-6095 - Verifies a Product2 Allowed Unit service failure is surfaced as AuraHandledException.
     */
    @IsTest
    static void testEvaluateAllowedUnitByProduct_serviceException_throwsAuraHandled() {
        WorkOrderLineItemsService.simulateQueryException = true;
        Id dummyId = UserInfo.getUserId();

        try {
            Test.startTest();
            WoDebriefAllowedUnitController.evaluateAllowedUnitByProduct(dummyId, dummyId);
            Test.stopTest();
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(String.isNotBlank(e.getMessage()), 'Expected exception message');
        } finally {
            WorkOrderLineItemsService.simulateQueryException = false;
        }
    }

    /**
     * @description GW-6095 - Verifies Billing Type defaults to Billable for blank inputs.
     */
    @IsTest
    static void testEvaluateBillingType_blankInputs_returnsBillable() {
        Test.startTest();
        String byProduct = WoDebriefAllowedUnitController.evaluateBillingType(null, null);
        String byProductItem = WoDebriefAllowedUnitController.evaluateBillingTypeForProductItem(null, null);
        Test.stopTest();

        System.assertEquals('Billable', byProduct, 'Blank inputs should be Billable');
        System.assertEquals('Billable', byProductItem, 'Blank inputs should be Billable');
    }

    /**
     * @description GW-6095 - Verifies a Billing Type service failure is surfaced as AuraHandledException.
     */
    @IsTest
    static void testEvaluateBillingType_serviceException_throwsAuraHandled() {
        WorkOrderLineItemsService.simulateQueryException = true;
        Id dummyId = UserInfo.getUserId();

        try {
            Test.startTest();
            WoDebriefAllowedUnitController.evaluateBillingType(dummyId, dummyId);
            Test.stopTest();
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(String.isNotBlank(e.getMessage()), 'Expected exception message');
        } finally {
            WorkOrderLineItemsService.simulateQueryException = false;
        }
    }
}