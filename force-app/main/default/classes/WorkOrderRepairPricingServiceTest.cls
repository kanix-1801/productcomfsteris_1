/**
 * @description GW-3377 - Tests for Repair Center Execute Pricing and the Repair requote gate.
 */
@IsTest
private class WorkOrderRepairPricingServiceTest {
    private class ValueSelector
        implements CustomerPreferencesService.ICustomerPreferencesSelector {
        private final String preferenceValue;

        ValueSelector(String preferenceValue) {
            this.preferenceValue = preferenceValue;
        }

        public List<CustomerPreference__c> selectActiveImsByAccountAndProductLine(
            Id accountId,
            Id recordTypeId,
            String productLine,
            Date asOfDate
        ) {
            return new List<CustomerPreference__c>();
        }

        public List<CustomerPreference__c> selectActiveImsByAccountProductLineAndType(
            Id accountId,
            Id recordTypeId,
            String productLine,
            String preferenceType,
            Date asOfDate
        ) {
            return new List<CustomerPreference__c>{
                new CustomerPreference__c(PreferenceValue__c = preferenceValue)
            };
        }

        public List<CustomerPreference__c> selectActiveImsByExactProductLineAndType(
            Id accountId,
            Id recordTypeId,
            String productLine,
            String preferenceType,
            Date asOfDate
        ) {
            return new List<CustomerPreference__c>();
        }

        public List<CustomerPreference__c> selectActiveImsByAccountAndType(
            Id accountId,
            Id recordTypeId,
            String preferenceType,
            Date asOfDate
        ) {
            return new List<CustomerPreference__c>();
        }
    }

    @IsTest
    static void testRequiresRequoteGate_WhenRepairAndEstimateOrPo_ReturnsTrue() {
        Assert.isFalse(WorkOrderRepairPricingService.requiresRequoteGate(null));
        Assert.isFalse(
            WorkOrderRepairPricingService.requiresRequoteGate(new WorkOrder(Status = 'Evaluate'))
        );
        Assert.isFalse(
            WorkOrderRepairPricingService.requiresRequoteGate(
                new WorkOrder(Status = 'Repair', EstimateRequired__c = 'Pre-Approved')
            )
        );
        Assert.isTrue(
            WorkOrderRepairPricingService.requiresRequoteGate(
                new WorkOrder(Status = 'Repair', EstimateRequired__c = 'Estimate Required')
            )
        );
        Assert.isTrue(
            WorkOrderRepairPricingService.requiresRequoteGate(
                new WorkOrder(Status = 'Repair', CustomerPORequired__c = true)
            )
        );
    }

    @IsTest
    static void testAssertRequoteAllowed_WhenNewTotalNotGreater_DoesNotThrow() {
        WorkOrder workOrder = new WorkOrder(Status = 'Repair');
        WorkOrderRepairPricingService.testQuoteNetTotalOverride = 100;
        try {
            WorkOrderRepairPricingService.assertRequoteAllowed(workOrder, 100, 100);
            WorkOrderRepairPricingService.assertRequoteAllowed(workOrder, 100, 80);
            WorkOrderRepairPricingService.assertRequoteAllowed(workOrder, null, null);
        } finally {
            WorkOrderRepairPricingService.testQuoteNetTotalOverride = null;
        }
    }

    @IsTest
    static void testAssertRequoteAllowed_WhenIncreaseAndNoLimit_ThrowsExactMessage() {
        Boolean threw = false;
        try {
            WorkOrderRepairPricingService.assertRequoteAllowed(
                new WorkOrder(Status = 'Repair'),
                100,
                150
            );
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            threw = true;
            Assert.areEqual(WorkOrderRepairPricingService.REQUOTE_BLOCKED_MESSAGE, e.getMessage());
        }
        Assert.isTrue(threw, 'Cost increase without Pre-Approval Limit should be blocked');
    }

    @IsTest
    static void testAssertRequoteAllowed_WhenIncreaseUnderLimit_Commits() {
        Account account = (Account) new adb_Account()
            .name('GW-3377 Pre-Approval Account')
            .persist();
        CustomerPreferencesService.selectorOverride = new ValueSelector('500');
        try {
            Test.startTest();
            WorkOrderRepairPricingService.assertRequoteAllowed(
                repairWorkOrder(account.Id, 'Endocam'),
                100,
                200
            );
            Test.stopTest();
        } finally {
            CustomerPreferencesService.selectorOverride = null;
        }
    }

    @IsTest
    static void testAssertRequoteAllowed_WhenIncreaseOverLimit_Throws() {
        Account account = (Account) new adb_Account()
            .name('GW-3377 Over Limit Account')
            .persist();
        CustomerPreferencesService.selectorOverride = new ValueSelector('150');
        Boolean threw = false;
        try {
            Test.startTest();
            try {
                WorkOrderRepairPricingService.assertRequoteAllowed(
                    repairWorkOrder(account.Id, 'Endocam'),
                    100,
                    200
                );
            } catch (WorkOrdersService.WorkOrdersServiceException e) {
                threw = true;
                Assert.areEqual(WorkOrderRepairPricingService.REQUOTE_BLOCKED_MESSAGE, e.getMessage());
            }
            Test.stopTest();
        } finally {
            CustomerPreferencesService.selectorOverride = null;
        }
        Assert.isTrue(threw, 'Increase over Pre-Approval Limit should be blocked');
    }

    @IsTest
    static void testPriceAfterLineChanges_WhenOverrideQueue_StampsTotals() {
        WorkOrderRepairPricingService.testNetTotalQueue = new List<Decimal>{ 75 };
        WorkOrder workOrder = new WorkOrder(Id = fakeWorkOrderId());

        Test.startTest();
        WorkOrderRepairPricingService.PricingTotals totals =
            WorkOrderRepairPricingService.priceAfterLineChanges(workOrder, false, 50);
        Test.stopTest();

        Assert.areEqual(50, totals.originalNetTotal);
        Assert.areEqual(75, totals.newNetTotal);
        Assert.areEqual(workOrder.Id, WorkOrderRepairPricingService.lastTotals.workOrderId);
        WorkOrderRepairPricingService.testNetTotalQueue = null;
        WorkOrderRepairPricingService.lastTotals = null;
    }

    @IsTest
    static void testShouldPriceBeforeStatusChange_WhenQuoteOrReadyForRepair_ReturnsTrue() {
        Assert.isFalse(WorkOrderRepairPricingService.shouldPriceBeforeStatusChange(null));
        Assert.isTrue(
            WorkOrderRepairPricingService.shouldPriceBeforeStatusChange(
                new WorkOrder(EstimateRequired__c = 'Pre-Approved', CustomerPORequired__c = false)
            )
        );
        Assert.isTrue(
            WorkOrderRepairPricingService.shouldPriceBeforeStatusChange(
                new WorkOrder(EstimateRequired__c = 'Estimate Required')
            )
        );
        Assert.isTrue(
            WorkOrderRepairPricingService.shouldPriceBeforeStatusChange(
                new WorkOrder(EstimateRequired__c = 'Order Acknowledgement')
            )
        );
        Assert.isTrue(
            WorkOrderRepairPricingService.shouldPriceBeforeStatusChange(
                new WorkOrder(CustomerPORequired__c = true)
            )
        );
        Assert.isFalse(
            WorkOrderRepairPricingService.shouldPriceBeforeStatusChange(
                new WorkOrder(
                    EstimateRequired__c = 'Pre-Approved',
                    CustomerPORequired__c = true,
                    CustomerPO__c = 'PO-1'
                )
            )
        );
    }

    @IsTest
    static void testPriceAfterLineChanges_WhenSaveExceedsQuote_SetsWarning() {
        WorkOrderRepairPricingService.testNetTotalQueue = new List<Decimal>{ 200 };
        WorkOrderRepairPricingService.PricingTotals totals =
            WorkOrderRepairPricingService.priceAfterLineChanges(
                new WorkOrder(Id = fakeWorkOrderId(), Status = 'Repair'),
                true,
                100,
                false
            );
        Assert.areEqual(200, totals.newNetTotal);
        Assert.areEqual(
            WorkOrderRepairPricingService.REQUOTE_BLOCKED_MESSAGE,
            WorkOrderRepairPricingService.lastRequoteWarning
        );
        WorkOrderRepairPricingService.testNetTotalQueue = null;
        WorkOrderRepairPricingService.lastTotals = null;
        WorkOrderRepairPricingService.lastRequoteWarning = null;
    }

    @IsTest
    static void testPriceAfterLineChanges_WhenNoNewPriceableLine_SkipsRequoteBlock() {
        WorkOrderRepairPricingService.testNetTotalQueue = new List<Decimal>{ 200 };
        WorkOrderRepairPricingService.PricingTotals totals =
            WorkOrderRepairPricingService.priceAfterLineChanges(
                new WorkOrder(Id = fakeWorkOrderId(), Status = 'Repair'),
                true,
                10,
                true,
                new List<Id>()
            );
        Assert.areEqual(200, totals.newNetTotal);
        Assert.isNull(WorkOrderRepairPricingService.lastRequoteWarning);
        WorkOrderRepairPricingService.testNetTotalQueue = null;
        WorkOrderRepairPricingService.lastTotals = null;
    }

    @IsTest
    static void testNewPriceableLines_IncludeSpecialPricingAndExcludeObservation() {
        Id specialPricingId = fakeLineId(1);
        Id serviceCodeId = fakeLineId(2);
        Id categoryCodeId = fakeLineId(3);
        Id observationId = fakeLineId(4);
        WorkOrderLineItemsService.beginNewPriceableLineCapture();
        WorkOrderLineItemsService.recordNewPriceableLines(
            new List<WorkOrderLineItem>{
                new WorkOrderLineItem(Id = specialPricingId, LineType__c = 'Special Pricing'),
                new WorkOrderLineItem(Id = serviceCodeId, LineType__c = 'Service Code'),
                new WorkOrderLineItem(Id = categoryCodeId, LineType__c = 'Category Code'),
                new WorkOrderLineItem(Id = observationId, LineType__c = 'Observation Code'),
                new WorkOrderLineItem(LineType__c = 'Special Pricing')
            }
        );
        List<Id> priceableIds = WorkOrderLineItemsService.getNewPriceableLineIds();
        Assert.areEqual(3, priceableIds.size());
        Assert.isTrue(priceableIds.contains(specialPricingId));
        Assert.isTrue(priceableIds.contains(serviceCodeId));
        Assert.isTrue(priceableIds.contains(categoryCodeId));
        Assert.isFalse(priceableIds.contains(observationId));
    }

    @IsTest
    static void testSumRepairCodeNetTotal_WhenNullOrOverride_ReturnsExpected() {
        Assert.areEqual(0, WorkOrderRepairPricingService.sumRepairCodeNetTotal(null));
        Assert.areEqual(0, WorkOrderRepairPricingService.sumRepairCodeNetTotal(new WorkOrder()));
        WorkOrderRepairPricingService.testNetTotalOverride = 42;
        Assert.areEqual(
            42,
            WorkOrderRepairPricingService.sumRepairCodeNetTotal(new WorkOrder(Id = fakeWorkOrderId()))
        );
        WorkOrderRepairPricingService.testNetTotalOverride = null;
    }

    @IsTest
    static void testExecuteRepairCenterPricing_WhenNullOrTests_DoesNotThrow() {
        WorkOrderRepairPricingService.executeRepairCenterPricing(null);
        WorkOrderRepairPricingService.executeRepairCenterPricing(new WorkOrder());
        WorkOrderRepairPricingService.executePricingInTests = false;
        WorkOrder created = (WorkOrder) new adb_WorkOrder()
            .subject('GW-3377 Pricing WO')
            .status('Repair')
            .persist();
        WorkOrderRepairPricingService.executeRepairCenterPricing(created);
    }

    @IsTest
    static void testPriceAfterLineChanges_WhenIncreaseBlocked_DoesNotStampLastTotals() {
        WorkOrderRepairPricingService.testNetTotalQueue = new List<Decimal>{ 200 };
        Boolean threw = false;
        try {
            WorkOrderRepairPricingService.priceAfterLineChanges(
                new WorkOrder(Id = fakeWorkOrderId(), Status = 'Repair'),
                true,
                100
            );
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            threw = true;
            Assert.areEqual(WorkOrderRepairPricingService.REQUOTE_BLOCKED_MESSAGE, e.getMessage());
        }
        Assert.isTrue(threw);
        Assert.isNull(WorkOrderRepairPricingService.lastTotals);
        WorkOrderRepairPricingService.testNetTotalQueue = null;
    }

    private static WorkOrder repairWorkOrder(Id accountId, String productLine) {
        WorkOrder workOrder = new WorkOrder(Status = 'Repair', AccountId = accountId);
        workOrder.Asset = new Asset();
        workOrder.Asset.Product2 = new Product2(ProductLine__c = productLine);
        return workOrder;
    }

    private static Id fakeWorkOrderId() {
        return Id.valueOf(Schema.SObjectType.WorkOrder.getKeyPrefix() + '000000000001');
    }

    private static Id fakeLineId(Integer suffix) {
        return Id.valueOf(
            Schema.SObjectType.WorkOrderLineItem.getKeyPrefix() +
            String.valueOf(suffix).leftPad(12, '0')
        );
    }
}