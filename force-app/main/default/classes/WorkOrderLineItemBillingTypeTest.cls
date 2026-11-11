/**
 * @description GW-1738 / GW-2001 tests for Billing Type evaluation.
 * @see WorkOrderLineItemsService
 */
@IsTest
private class WorkOrderLineItemBillingTypeTest {
    /**
     * @description Missing product or Work Order defaults to Billable.
     */
    @IsTest
    static void evaluateBillingType_blankInputs_returnsBillable() {
        Test.startTest();
        String result = WorkOrderLineItemsService.evaluateBillingType(null, null);
        Test.stopTest();

        Assert.areEqual(WorkOrderLineItemsService.BILLING_TYPE_BILLABLE, result);
        Assert.areEqual(
            WorkOrderLineItemsService.BILLING_TYPE_BILLABLE,
            WorkOrderLineItemsService.evaluateBillingTypeForProductItem(null, null)
        );
    }

    /**
     * @description Same product on another WO for the same asset within 90 days is SVC Warranty.
     */
    @IsTest
    static void evaluateBillingType_priorPartOnSameAsset_returnsSvcWarranty() {
        Account account = new Account(
            Name = 'Billing Type Service Account',
            SourceSystemID__c = 'ORACLE-BTSVC-' + String.valueOf(Crypto.getRandomInteger())
        );
        insert account;

        Product2 product = new Product2(
            Name = 'Billing Type Service Part',
            ProductCode = 'BT-SVC-001',
            IsActive = true
        );
        insert product;

        Id pricebookId = Test.getStandardPricebookId();
        insert new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );
        Id pricebookEntryId = [
            SELECT Id
            FROM PricebookEntry
            WHERE Product2Id = :product.Id AND Pricebook2Id = :pricebookId
            LIMIT 1
        ]
        .Id;

        Asset asset = new Asset(
            Name = 'Billing Type Service Asset',
            AccountId = account.Id,
            Product2Id = product.Id,
            SerialNumber = 'SN-BT-001'
        );
        insert asset;

        WorkOrder priorWorkOrder = new WorkOrder(
            AccountId = account.Id,
            AssetId = asset.Id,
            Subject = 'Prior Billing Type WO',
            Pricebook2Id = pricebookId
        );
        insert priorWorkOrder;

        Id usageConsumptionRtId = Schema.SObjectType.WorkOrderLineItem
            .getRecordTypeInfosByDeveloperName()
            .get('UsageConsumption')
            ?.getRecordTypeId();

        WorkOrderLineItem priorPart = new WorkOrderLineItem(
            WorkOrderId = priorWorkOrder.Id,
            LineType__c = 'Parts',
            PricebookEntryId = pricebookEntryId
        );
        if (usageConsumptionRtId != null) {
            priorPart.RecordTypeId = usageConsumptionRtId;
        }
        insert priorPart;

        WorkOrder currentWorkOrder = new WorkOrder(
            AccountId = account.Id,
            AssetId = asset.Id,
            Subject = 'Current Billing Type WO'
        );
        insert currentWorkOrder;

        Test.startTest();
        String result = WorkOrderLineItemsService.evaluateBillingType(
            currentWorkOrder.Id,
            product.Id
        );
        Test.stopTest();

        Assert.areEqual(WorkOrderLineItemsService.BILLING_TYPE_SVC_WARRANTY, result);
    }

    /**
     * @description No prior same-product consumption on the asset is Billable.
     */
    @IsTest
    static void evaluateBillingType_noPriorPart_returnsBillable() {
        Account account = new Account(
            Name = 'Billing Type None Account',
            SourceSystemID__c = 'ORACLE-BTNONE-' + String.valueOf(Crypto.getRandomInteger())
        );
        insert account;

        Product2 product = new Product2(
            Name = 'Billing Type None Part',
            ProductCode = 'BT-NONE-001',
            IsActive = true
        );
        insert product;

        Asset asset = new Asset(
            Name = 'Billing Type None Asset',
            AccountId = account.Id,
            Product2Id = product.Id,
            SerialNumber = 'SN-BT-NONE-001'
        );
        insert asset;

        WorkOrder currentWorkOrder = new WorkOrder(
            AccountId = account.Id,
            AssetId = asset.Id,
            Subject = 'Current Billing Type None WO'
        );
        insert currentWorkOrder;

        Test.startTest();
        String result = WorkOrderLineItemsService.evaluateBillingType(
            currentWorkOrder.Id,
            product.Id
        );
        Test.stopTest();

        Assert.areEqual(WorkOrderLineItemsService.BILLING_TYPE_BILLABLE, result);
    }

    /**
     * @description Controller defaults Billing Type to Billable for blank Ids.
     */
    @IsTest
    static void controller_evaluateBillingType_blankIds_returnsBillable() {
        Test.startTest();
        String result = WoDebriefAllowedUnitController.evaluateBillingType(null, null);
        Test.stopTest();

        Assert.areEqual(WorkOrderLineItemsService.BILLING_TYPE_BILLABLE, result);
        Assert.areEqual(
            WorkOrderLineItemsService.BILLING_TYPE_BILLABLE,
            WoDebriefAllowedUnitController.evaluateBillingTypeForProductItem(null, null)
        );
    }

    /**
     * @description Controller surfaces service query failures as AuraHandledException.
     */
    @IsTest
    static void controller_evaluateBillingType_serviceException_throwsAuraHandled() {
        WorkOrderLineItemsService.simulateQueryException = true;
        Id dummyId = UserInfo.getUserId();

        try {
            Test.startTest();
            WoDebriefAllowedUnitController.evaluateBillingType(dummyId, dummyId);
            Test.stopTest();
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(String.isNotBlank(e.getMessage()), 'Expected exception message');
        } finally {
            WorkOrderLineItemsService.simulateQueryException = false;
        }
    }
}