/**
 * GW-5333 tests for Approve/Reject Quote controller, QuoteService, and selectors.
 */
@IsTest
private class QuoteApproveRejectControllerTest {
    private static final String STATUS_WAITING = 'Waiting for Approval';
    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_REJECTED = 'Rejected';
    private static final String PRODUCT_LINE = 'GW-5333 Product Line';
    private static final String QUOTE_RECORD_TYPE = 'RepairCenter';

    /**
     * @description Returns the first active picklist value so tests stay org-configuration safe.
     * @param fieldDescribe Picklist field describe
     * @return First active value, or null
     */
    private static String getFirstActiveValue(Schema.DescribeFieldResult fieldDescribe) {
        for (Schema.PicklistEntry picklistEntry : fieldDescribe.getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }
        return null;
    }

    @TestSetup
    static void setupTestData() {
        adb_Account accountBuilder = new adb_Account().name('GW-5333 Account');
        accountBuilder.persist();

        Id pricebookId = Test.getStandardPricebookId();

        Contact primaryContact = new Contact(
            FirstName = 'GW-5333',
            LastName = 'Primary Contact',
            AccountId = accountBuilder.id
        );
        insert primaryContact;

        Opportunity opportunityRecord = new Opportunity(
            Name = 'GW-5333 Opportunity',
            AccountId = accountBuilder.id,
            StageName = getFirstActiveValue(Opportunity.StageName.getDescribe()),
            ForecastConfidenceLevel__c =
                getFirstActiveValue(Opportunity.ForecastConfidenceLevel__c.getDescribe()),
            Type = getFirstActiveValue(Opportunity.Type.getDescribe()),
            PrimaryContact__c = primaryContact.Id,
            CloseDate = Date.today().addDays(30),
            Amount = 1000,
            Probability = 10,
            Pricebook2Id = pricebookId
        );
        insert opportunityRecord;
        Product2 productServiced = new Product2(
            Name = 'GW-5333 Product Serviced',
            ProductCode = 'PS-5333',
            Description = 'Product serviced description',
            IsActive = true,
            InspectionFeeApplicable__c = false
        );
        Product2 categoryProduct = new Product2(
            Name = 'GW-5333 Category Code',
            ProductCode = 'CC-5333',
            IsActive = true
        );
        Product2 specialPricingProduct = new Product2(
            Name = 'GW-5333 Special Pricing',
            ProductCode = 'SP-5333',
            IsActive = true
        );
        insert new List<Product2>{ productServiced, categoryProduct, specialPricingProduct };

        insert new List<PricebookEntry>{
            new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id = productServiced.Id,
                UnitPrice = 100,
                IsActive = true
            ),
            new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id = categoryProduct.Id,
                UnitPrice = 50,
                IsActive = true
            ),
            new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id = specialPricingProduct.Id,
                UnitPrice = 25,
                IsActive = true
            )
        };

        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .subject('GW-5333 Work Order');
        workOrderBuilder.persist();
        WorkOrder workOrder = [
            SELECT Id, WorkOrderNumber
            FROM WorkOrder
            WHERE Id = :workOrderBuilder.id
        ];
        workOrder.Pricebook2Id = pricebookId;
        workOrder.TurnTime__c = 5;
        workOrder.ScheduledShipDate__c = Date.today().addDays(7);
        update workOrder;

        Quote quoteRecord = new Quote(
            Name = 'GW-5333 Quote',
            OpportunityId = opportunityRecord.Id,
            Pricebook2Id = pricebookId,
            Status = STATUS_WAITING,
            WorkOrder__c = workOrder.Id,
            Version__c = 1
        );
        Map<String, Schema.RecordTypeInfo> quoteRecordTypes =
            Schema.SObjectType.Quote.getRecordTypeInfosByDeveloperName();
        if (quoteRecordTypes.containsKey(QUOTE_RECORD_TYPE)) {
            quoteRecord.RecordTypeId = quoteRecordTypes.get(QUOTE_RECORD_TYPE).getRecordTypeId();
        }
        insert quoteRecord;

        workOrder.ActiveQuote__c = quoteRecord.Id;
        update workOrder;

        PricebookEntry productServicedEntry = [
            SELECT Id
            FROM PricebookEntry
            WHERE Product2Id = :productServiced.Id
            LIMIT 1
        ];
        PricebookEntry categoryEntry = [
            SELECT Id
            FROM PricebookEntry
            WHERE Product2Id = :categoryProduct.Id
            LIMIT 1
        ];
        PricebookEntry specialPricingEntry = [
            SELECT Id
            FROM PricebookEntry
            WHERE Product2Id = :specialPricingProduct.Id
            LIMIT 1
        ];

        WorkOrderLineItem productServicedWoli = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            PricebookEntryId = productServicedEntry.Id,
            Quantity = 1,
            UnitPrice = 100,
            ProductLine__c = PRODUCT_LINE
        );
        insert productServicedWoli;

        QuoteLineItem productServicedLine = new QuoteLineItem(
            QuoteId = quoteRecord.Id,
            PricebookEntryId = productServicedEntry.Id,
            Quantity = 1,
            UnitPrice = 100,
            LineType__c = 'Product Serviced',
            Status__c = STATUS_WAITING,
            WorkOrder__c = workOrder.Id,
            WorkOrderLineItem__c = productServicedWoli.Id
        );
        insert productServicedLine;

        insert new List<QuoteLineItem>{
            new QuoteLineItem(
                QuoteId = quoteRecord.Id,
                PricebookEntryId = categoryEntry.Id,
                Quantity = 1,
                UnitPrice = 50,
                LineType__c = 'Category Code',
                Status__c = STATUS_WAITING,
                ParentWorkOrderLineItem__c = productServicedWoli.Id,
                WorkOrder__c = workOrder.Id
            ),
            new QuoteLineItem(
                QuoteId = quoteRecord.Id,
                PricebookEntryId = specialPricingEntry.Id,
                Quantity = 1,
                UnitPrice = 25,
                LineType__c = 'Special Pricing',
                Status__c = STATUS_WAITING,
                ParentWorkOrderLineItem__c = productServicedWoli.Id,
                WorkOrder__c = workOrder.Id
            )
        };
    }

    @IsTest
    static void testGetWorkspace_WhenWaitingQuoteProvided() {
        WorkOrder workOrder = [SELECT Id, WorkOrderNumber FROM WorkOrder LIMIT 1];

        Test.startTest();
        QuoteService.ApproveRejectWorkspace workspace =
            QuoteApproveRejectController.getWorkspace(workOrder.Id);
        Test.stopTest();

        Assert.areEqual(workOrder.Id, workspace.workOrderId);
        Assert.areEqual(workOrder.WorkOrderNumber, workspace.workOrderNumber);
        Assert.areEqual(1, workspace.lines.size());
        Assert.areEqual('Product serviced description', workspace.lines[0].description);
        Assert.areEqual(75, workspace.lines[0].estimatePrice);
        Assert.areEqual(75, workspace.estimateTotal);
        Assert.areEqual(STATUS_WAITING, workspace.quoteStatus);
        Assert.isNull(workspace.lines[0].selectedDecision);
    }

    @IsTest
    static void testGetWorkspace_WhenWorkOrderIdMissing() {
        Boolean threw = false;
        try {
            QuoteApproveRejectController.getWorkspace(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void testSaveDecisions_WhenPartialApprove() {
        WorkOrder workOrder = [SELECT Id FROM WorkOrder LIMIT 1];
        QuoteLineItem productServicedLine = [
            SELECT Id
            FROM QuoteLineItem
            WHERE LineType__c = 'Product Serviced'
            LIMIT 1
        ];

        QuoteService.ApproveRejectDecision decision = new QuoteService.ApproveRejectDecision();
        decision.quoteLineItemId = productServicedLine.Id;
        decision.status = STATUS_APPROVED;

        Test.startTest();
        QuoteService.ApproveRejectWorkspace workspace =
            QuoteApproveRejectController.saveDecisions(
                workOrder.Id,
                new List<QuoteService.ApproveRejectDecision>{ decision }
            );
        Test.stopTest();

        Assert.areEqual(STATUS_APPROVED, workspace.quoteStatus);
        Assert.areEqual(STATUS_APPROVED, workspace.lines[0].selectedDecision);

        Map<String, QuoteLineItem> childLinesByType = new Map<String, QuoteLineItem>();
        for (QuoteLineItem childLine : [
            SELECT LineType__c, Status__c
            FROM QuoteLineItem
            WHERE LineType__c IN ('Category Code', 'Special Pricing')
        ]) {
            childLinesByType.put(childLine.LineType__c, childLine);
        }
        Assert.areEqual(STATUS_APPROVED, childLinesByType.get('Category Code').Status__c);
        Assert.areEqual(STATUS_APPROVED, childLinesByType.get('Special Pricing').Status__c);
    }

    @IsTest
    static void testSaveDecisions_WhenRejectAll() {
        WorkOrder workOrder = [SELECT Id FROM WorkOrder LIMIT 1];
        QuoteLineItem productServicedLine = [
            SELECT Id
            FROM QuoteLineItem
            WHERE LineType__c = 'Product Serviced'
            LIMIT 1
        ];

        QuoteService.ApproveRejectDecision decision = new QuoteService.ApproveRejectDecision();
        decision.quoteLineItemId = productServicedLine.Id;
        decision.status = STATUS_REJECTED;

        Test.startTest();
        QuoteService.ApproveRejectWorkspace workspace =
            QuoteApproveRejectController.saveDecisions(
                workOrder.Id,
                new List<QuoteService.ApproveRejectDecision>{ decision }
            );
        Test.stopTest();

        Assert.areEqual(STATUS_REJECTED, workspace.quoteStatus);
        Map<String, QuoteLineItem> childLinesByType = new Map<String, QuoteLineItem>();
        for (QuoteLineItem childLine : [
            SELECT LineType__c, Status__c
            FROM QuoteLineItem
            WHERE LineType__c IN ('Category Code', 'Special Pricing')
        ]) {
            childLinesByType.put(childLine.LineType__c, childLine);
        }
        Assert.areEqual(STATUS_REJECTED, childLinesByType.get('Category Code').Status__c);
        Assert.areEqual(STATUS_REJECTED, childLinesByType.get('Special Pricing').Status__c);
    }

    @IsTest
    static void testSaveDecisions_WhenRejectedCreatesInspectionLine() {
        WorkOrder workOrder = [SELECT Id, Pricebook2Id FROM WorkOrder LIMIT 1];
        QuoteLineItem productServicedLine = [
            SELECT Id, Product2Id
            FROM QuoteLineItem
            WHERE LineType__c = 'Product Serviced'
            LIMIT 1
        ];
        Product2 inspectionProduct = new Product2(
            Name = 'GW-5333 Inspection Service',
            ProductCode = 'INSP-5333',
            Description = 'Inspection service description',
            Model__c = 'INSP-MODEL',
            ProductType__c = 'Service Code',
            IsActive = true
        );
        insert inspectionProduct;
        insert new PricebookEntry(
            Pricebook2Id = workOrder.Pricebook2Id,
            Product2Id = inspectionProduct.Id,
            UnitPrice = 15,
            IsActive = true
        );
        update new Product2(
            Id = productServicedLine.Product2Id,
            Model__c = 'SERV-MODEL',
            InspectionFeeApplicable__c = true,
            InspectionServiceCode__c = inspectionProduct.Id
        );
        productServicedLine.Description = 'Serviced item description';
        productServicedLine.ItemDescription__c = 'Do not use this description';
        productServicedLine.ItemCode__c = 'ITEM-5333';
        productServicedLine.SerialNumber__c = 'SN-5333';
        update productServicedLine;

        QuoteService.ApproveRejectDecision decision = new QuoteService.ApproveRejectDecision();
        decision.quoteLineItemId = productServicedLine.Id;
        decision.status = STATUS_REJECTED;

        Test.startTest();
        QuoteApproveRejectController.saveDecisions(
            workOrder.Id,
            new List<QuoteService.ApproveRejectDecision>{ decision }
        );
        Test.stopTest();

        List<WorkOrderLineItem> inspectionLines = [
            SELECT
                LineType__c,
                Model__c,
                Item__c,
                ItemCode__c,
                ItemDescription__c,
                SerialNumber__c,
                ProductCodeWoli__c,
                ProductDescription__c,
                Quantity,
                Status
            FROM WorkOrderLineItem
            WHERE ProductCodeWoli__c = 'INSP-5333'
        ];
        Assert.areEqual(1, inspectionLines.size());
        WorkOrderLineItem inspectionLine = inspectionLines[0];
        Assert.areEqual('Service Code', inspectionLine.LineType__c);
        Assert.areEqual('SERV-MODEL', inspectionLine.Model__c);
        Assert.areEqual(productServicedLine.Product2Id, inspectionLine.Item__c);
        Assert.areEqual('ITEM-5333', inspectionLine.ItemCode__c);
        Assert.areEqual('Serviced item description', inspectionLine.ItemDescription__c);
        Assert.areEqual('SN-5333', inspectionLine.SerialNumber__c);
        Assert.areEqual('INSP-5333', inspectionLine.ProductCodeWoli__c);
        Assert.areEqual('Inspection service description', inspectionLine.ProductDescription__c);
        Assert.areEqual(1, inspectionLine.Quantity);
        Assert.areEqual(STATUS_APPROVED, inspectionLine.Status);
    }

    @IsTest
    static void testSaveComment_WhenCommentsProvided() {
        QuoteLineItem productServicedLine = [
            SELECT Id
            FROM QuoteLineItem
            WHERE LineType__c = 'Product Serviced'
            LIMIT 1
        ];

        Test.startTest();
        String saved = QuoteApproveRejectController.saveComment(
            productServicedLine.Id,
            'Customer approved by phone'
        );
        Test.stopTest();

        Assert.areEqual('Customer approved by phone', saved);
        QuoteLineItem updatedLine = [
            SELECT QuoteComments__c
            FROM QuoteLineItem
            WHERE Id = :productServicedLine.Id
        ];
        Assert.areEqual('Customer approved by phone', updatedLine.QuoteComments__c);
    }

    @IsTest
    static void testSaveComment_WhenLineMissing() {
        Boolean threw = false;
        try {
            QuoteApproveRejectController.saveComment(null, 'x');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void testSelectors_WhenInputMissing() {
        Assert.isNull(QuoteSelector.selectForApproveRejectById(null));
        Assert.isTrue(QuoteLineItemSelector.selectForApproveRejectByQuoteId(null).isEmpty());
        Assert.isNull(QuoteLineItemSelector.selectForApproveRejectById(null));
        Assert.isTrue(WorkOrdersSelector.selectForApproveRejectQuoteByIds(null).isEmpty());
        Assert.isTrue(ProductsSelector.selectForApproveRejectByIds(null).isEmpty());
        Assert.isTrue(QuoteLineItemService.getLineItemsForApproveReject(null).isEmpty());
        QuoteLineItemService.updateLineItemsForApproveReject(null);
        Assert.isTrue(WorkOrdersService.getWorkOrdersForApproveRejectQuote(null).isEmpty());
        Assert.isTrue(ProductsService.getProductsForApproveRejectById(null).isEmpty());
    }
}