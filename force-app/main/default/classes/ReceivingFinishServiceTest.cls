/**
 * @description Tests for ReceivingFinishService / finishReceivingItem (GW-5492).
 */
@IsTest
private class ReceivingFinishServiceTest {
    @TestSetup
    static void setupTestData() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW5492 Finish Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        adb_Account accountBuilder = new adb_Account()
            .name('GW5492 Finish Account')
            .systemId('LEG5492FIN1');
        accountBuilder.set(Account.OrgIDs__c, '82');
        accountBuilder.set(Account.AccountNumber, 'FIN5492-001');
        accountBuilder.set(Account.CreditStatusCode__c, 'CREDIT HOLD');

        adb_ReturnOrder returnOrderBuilder = new adb_ReturnOrder()
            .account(accountBuilder)
            .status('Created');
        returnOrderBuilder.recordType('CustomerReturn');
        returnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
        returnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Serialized');
        returnOrderBuilder.set(ReturnOrder.DestinationLocationId, repairCenter.Id);

        adb_Product2 productBuilder = new adb_Product2()
            .name('GW5492 Finish Product')
            .isActive(true);
        productBuilder.set(Product2.ProductCode, 'FIN-PRD-5492');
        Product2 product = (Product2) productBuilder.persist();
        ensureReceivingPricebooksForProduct(product.Id);

        adb_ReturnOrderLineItem lineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(returnOrderBuilder)
            .quantityReturned(1);
        lineBuilder.set(ReturnOrderLineItem.Product2Id, product.Id);
        lineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        lineBuilder.set(ReturnOrderLineItem.SerialNumber__c, 'SN5492FIN01');
        lineBuilder.set(ReturnOrderLineItem.Model__c, 'MDL-5492');
        lineBuilder.setParent(
            ReturnOrderLineItem.EstimateContact__c,
            new adb_Contact().lastName('GW5492 Device Estimate')
        );
        lineBuilder.set(ReturnOrderLineItem.RepairWarranty__c, 'Yes');
        lineBuilder.set(ReturnOrderLineItem.WarrantyNotes__c, 'GW5492 device warranty');
        lineBuilder.set(ReturnOrderLineItem.IsPriorityRepair__c, true);
        lineBuilder.persist();
    }

    /**
     * @description Seeds Standard + IMS Service Pricebook entries so finish receiving
     *              can match RepairCenterDefaults.PriceList (IMS Service Pricebook).
     * @param productId Product that will be received onto a Work Order
     */
    private static void ensureReceivingPricebooksForProduct(Id productId) {
        ReceivingFinishService.resetDefaultPricebookCacheForTest();
        Id standardPricebookId = Test.getStandardPricebookId();
        update new Pricebook2(Id = standardPricebookId, IsActive = true);
        Integer standardCount = [
            SELECT COUNT()
            FROM PricebookEntry
            WHERE Pricebook2Id = :standardPricebookId
            AND Product2Id = :productId
        ];
        if (standardCount == 0) {
            insert new PricebookEntry(
                Pricebook2Id = standardPricebookId,
                Product2Id = productId,
                UnitPrice = 1,
                IsActive = true
            );
        }

        List<Pricebook2> servicePricebooks = [
            SELECT Id
            FROM Pricebook2
            WHERE Name = 'IMS Service Pricebook'
            AND IsActive = TRUE
            LIMIT 1
        ];
        Id servicePricebookId;
        if (servicePricebooks.isEmpty()) {
            Pricebook2 servicePricebook = new Pricebook2(
                Name = 'IMS Service Pricebook',
                IsActive = true
            );
            insert servicePricebook;
            servicePricebookId = servicePricebook.Id;
        } else {
            servicePricebookId = servicePricebooks[0].Id;
        }

        Integer serviceCount = [
            SELECT COUNT()
            FROM PricebookEntry
            WHERE Pricebook2Id = :servicePricebookId
            AND Product2Id = :productId
        ];
        if (serviceCount == 0) {
            insert new PricebookEntry(
                Pricebook2Id = servicePricebookId,
                Product2Id = productId,
                UnitPrice = 1,
                IsActive = true
            );
        }
    }

    @IsTest
    static void testFinishReceivingItem_serializedCreatesChildWorkOrder() {
        ReturnOrder returnOrder = [
            SELECT Id
            FROM ReturnOrder
            LIMIT 1
        ];
        ReturnOrderLineItem lineItem = [
            SELECT Id, EstimateContact__c, RepairWarranty__c, WarrantyNotes__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrder.Id
            LIMIT 1
        ];

        update new ReturnOrder(Id = returnOrder.Id, SalesRep__c = UserInfo.getUserId());

        ReceivingService.FinishReceivingRequest request =
            new ReceivingService.FinishReceivingRequest();
        request.returnOrderId = returnOrder.Id;
        request.lineItemId = lineItem.Id;
        request.disinfected = 'Contaminated';
        request.quantityReceived = 1;
        request.resiTestPerformed = true;
        request.visualInspection = true;
        request.bioBag = false;

        Test.startTest();
        ReceivingService.FinishReceivingResult result =
            ReceivingService.finishReceivingItem(request);
        Test.stopTest();

        Assert.isTrue(result.hasWorkOrderCreated);
        Assert.isNotNull(result.workOrderId);
        Assert.isNotNull(result.parentWorkOrderId);

        WorkOrder child = [
            SELECT
                Id,
                ParentWorkOrderId,
                Status,
                SubStatus__c,
                IsVisualInspection__c,
                IsBioBag__c,
                EstimateContact__c,
                RepairWarranty__c,
                WarrantyNotes__c,
                IsPriorityRepair__c,
                AccountManager__c,
                AssignedSalesPerson__c
            FROM WorkOrder
            WHERE Id = :result.workOrderId
        ];
        Assert.areEqual(result.parentWorkOrderId, child.ParentWorkOrderId);
        Assert.areEqual('Contaminated', child.SubStatus__c);
        Assert.isTrue(child.IsVisualInspection__c);
        Assert.isFalse(child.IsBioBag__c);
        Assert.areEqual(lineItem.EstimateContact__c, child.EstimateContact__c);
        Assert.areEqual(lineItem.RepairWarranty__c, child.RepairWarranty__c);
        Assert.areEqual(lineItem.WarrantyNotes__c, child.WarrantyNotes__c);
        Assert.isTrue(child.IsPriorityRepair__c);
        Assert.isNull(child.AccountManager__c);
        Assert.areEqual(UserInfo.getUserId(), child.AssignedSalesPerson__c);

        WorkOrder parentWorkOrder = [
            SELECT IsPriorityRepair__c, AccountManager__c, SubStatus__c, AssignedSalesPerson__c
            FROM WorkOrder
            WHERE Id = :result.parentWorkOrderId
        ];
        Assert.isNull(parentWorkOrder.SubStatus__c);
        Assert.areEqual(UserInfo.getUserId(), parentWorkOrder.AssignedSalesPerson__c);
        Assert.isFalse(parentWorkOrder.IsPriorityRepair__c);
        Assert.isNull(parentWorkOrder.AccountManager__c);

        WorkOrderLineItem productServiced = [
            SELECT IsPriorityRepair__c
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :child.Id
                AND LineType__c = 'Product Serviced'
        ];
        Assert.isTrue(productServiced.IsPriorityRepair__c);

        ReturnOrderLineItem refreshed = [
            SELECT Status__c
            FROM ReturnOrderLineItem
            WHERE Id = :lineItem.Id
        ];
        Assert.areEqual('Received', refreshed.Status__c);

        Integer historyCount = [
            SELECT COUNT()
            FROM ResiTestHistory__c
            WHERE WorkOrder__c = :result.workOrderId
        ];
        Assert.isTrue(historyCount >= 1);
    }

    @IsTest
    static void testFinishReceivingItem_adHocCreatesReturnOrderLine() {
        ReturnOrder returnOrder = [
            SELECT Id
            FROM ReturnOrder
            WHERE ReturnOrderType__c = 'Serialized'
            LIMIT 1
        ];
        ReturnOrderLineItem originalLine = [
            SELECT Id
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrder.Id
            LIMIT 1
        ];
        Product2 product = [
            SELECT Id
            FROM Product2
            WHERE ProductCode = 'FIN-PRD-5492'
            LIMIT 1
        ];

        ReceivingService.FinishReceivingRequest request =
            new ReceivingService.FinishReceivingRequest();
        request.returnOrderId = returnOrder.Id;
        request.isAdHoc = true;
        request.product2Id = product.Id;
        request.serialNumber = 'ADHOC-0731';
        request.model = 'ADHOC-MODEL';
        request.quantityReceived = 1;
        request.disinfected = 'Clean';

        Test.startTest();
        ReceivingService.FinishReceivingResult result =
            ReceivingService.finishReceivingItem(request);
        Test.stopTest();

        Assert.isTrue(result.hasWorkOrderCreated);

        List<ReturnOrderLineItem> lines = [
            SELECT
                Id,
                Status__c,
                SerialNumber__c,
                QuantityReturned,
                QuantityReceived,
                LineType__c,
                RecordType.DeveloperName
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrder.Id
        ];
        Assert.areEqual(2, lines.size());

        ReturnOrderLineItem addedLine;
        for (ReturnOrderLineItem lineItem : lines) {
            if (lineItem.Id == originalLine.Id) {
                Assert.areEqual('Created', lineItem.Status__c);
            } else {
                addedLine = lineItem;
            }
        }
        Assert.isNotNull(addedLine);
        Assert.areEqual('Received', addedLine.Status__c);
        Assert.areEqual('ADHOC-0731', addedLine.SerialNumber__c);
        Assert.areEqual(1, addedLine.QuantityReturned);
        Assert.areEqual(1, addedLine.QuantityReceived);
        Assert.areEqual('Serialized', addedLine.LineType__c);
        Assert.areEqual('Inbound', addedLine.RecordType.DeveloperName);

        WorkOrder child = [
            SELECT ReturnOrderLineItemId
            FROM WorkOrder
            WHERE Id = :result.workOrderId
        ];
        Assert.areEqual(addedLine.Id, child.ReturnOrderLineItemId);

        WorkOrderLineItem productServiced = [
            SELECT ReturnOrderLineItemId
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :child.Id
                AND LineType__c = 'Product Serviced'
        ];
        Assert.areEqual(addedLine.Id, productServiced.ReturnOrderLineItemId);
    }

    @IsTest
    static void testFinishReceivingItem_parentUsesFirstLineAndWoliStatus() {
        ReturnOrder returnOrder = [
            SELECT Id, AccountId
            FROM ReturnOrder
            WHERE ReturnOrderType__c = 'Serialized'
            LIMIT 1
        ];
        ReturnOrderLineItem firstLine = [
            SELECT Id, Product2Id, EstimateContact__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrder.Id
                AND SerialNumber__c = 'SN5492FIN01'
            LIMIT 1
        ];
        Contact lineContact = new Contact(
            LastName = 'GW5492 Parent Contact',
            AccountId = returnOrder.AccountId
        );
        Contact returnOrderContact = new Contact(
            LastName = 'GW5492 RO Contact',
            AccountId = returnOrder.AccountId
        );
        Contact returnOrderEstimateContact = new Contact(
            LastName = 'GW5492 RO Estimate',
            AccountId = returnOrder.AccountId
        );
        insert new List<Contact>{
            lineContact,
            returnOrderContact,
            returnOrderEstimateContact
        };
        Department__c department = new Department__c(Name = 'GW5492 Parent Dept');
        insert department;

        update new ReturnOrderLineItem(
            Id = firstLine.Id,
            CustomerPO__c = 'PO-FIRST',
            CustomerReference__c = 'REF-FIRST',
            Department__c = department.Id,
            Contact__c = lineContact.Id
        );
        update new ReturnOrder(
            Id = returnOrder.Id,
            ContactId = returnOrderContact.Id,
            EstimateContact__c = returnOrderEstimateContact.Id,
            SalesRep__c = UserInfo.getUserId()
        );

        ReturnOrderLineItem secondLine = new ReturnOrderLineItem(
            ReturnOrderId = returnOrder.Id,
            Product2Id = firstLine.Product2Id,
            QuantityReturned = 1,
            Status__c = 'Created',
            SerialNumber__c = 'SN5492FIN02',
            CustomerPO__c = 'PO-SECOND',
            CustomerReference__c = 'REF-SECOND',
            EstimateRequired__c = 'Estimate Required'
        );
        insert secondLine;

        ReceivingService.FinishReceivingRequest request =
            new ReceivingService.FinishReceivingRequest();
        request.returnOrderId = returnOrder.Id;
        request.lineItemId = secondLine.Id;
        request.disinfected = 'Contaminated';
        request.quantityReceived = 1;

        Test.startTest();
        ReceivingService.FinishReceivingResult result =
            ReceivingService.finishReceivingItem(request);
        Test.stopTest();

        WorkOrder parentWorkOrder = [
            SELECT
                ContactId,
                CustomerPO__c,
                CustomerReference__c,
                Department__c,
                EstimateContact__c
            FROM WorkOrder
            WHERE Id = :result.parentWorkOrderId
        ];
        Assert.areEqual('PO-FIRST', parentWorkOrder.CustomerPO__c);
        Assert.areEqual('REF-FIRST', parentWorkOrder.CustomerReference__c);
        Assert.areEqual(department.Id, parentWorkOrder.Department__c);
        Assert.areEqual(lineContact.Id, parentWorkOrder.ContactId);
        Assert.areEqual(firstLine.EstimateContact__c, parentWorkOrder.EstimateContact__c);

        WorkOrderLineItem productServiced = [
            SELECT Status
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :result.workOrderId
                AND LineType__c = 'Product Serviced'
        ];
        Assert.areEqual('Waiting for Approval', productServiced.Status);
    }

    @IsTest
    static void testFinishReceivingItem_customerCareSetsReasonCodes() {
        ReturnOrder returnOrder = [SELECT Id FROM ReturnOrder LIMIT 1];
        ReturnOrderLineItem lineItem = [
            SELECT Id
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrder.Id
            LIMIT 1
        ];

        ReceivingService.FinishReceivingRequest request =
            new ReceivingService.FinishReceivingRequest();
        request.returnOrderId = returnOrder.Id;
        request.lineItemId = lineItem.Id;
        request.disinfected = 'Clean';
        request.quantityReceived = 1;
        request.customerCareReasonCodes = new List<String>{
            'Serial Number Mismatch'
        };
        request.customerCareNotes = 'Needs review';

        Test.startTest();
        ReceivingService.FinishReceivingResult result =
            ReceivingService.finishReceivingItem(request);
        Test.stopTest();

        WorkOrder child = [
            SELECT SubStatus__c, ReasonCode__c, CustomerCareNotes__c
            FROM WorkOrder
            WHERE Id = :result.workOrderId
        ];
        Assert.areEqual('Customer Care', child.SubStatus__c);
        Assert.isTrue(
            child.ReasonCode__c != null &&
            child.ReasonCode__c.contains('Serial Number Mismatch')
        );
        Assert.areEqual('Needs review', child.CustomerCareNotes__c);
    }

    @IsTest
    static void testFinishReceivingItem_redirectCreatesChildReturnOrder() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW5492 Finish Redirect RC',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        ReturnOrder returnOrder = [SELECT Id, AccountId FROM ReturnOrder LIMIT 1];
        Account shipTo = new Account(
            Name = 'GW5492 Redirect Ship To',
            ParentId = returnOrder.AccountId,
            Type = 'Address',
            ShiptoAddressStatus__c = 'Primary',
            BillingStreet = '100 Ship St',
            BillingCity = 'Mentor',
            BillingStateCode = 'OH',
            BillingPostalCode = '44060',
            BillingCountryCode = 'US'
        );
        insert shipTo;
        update new ReturnOrder(
            Id = returnOrder.Id,
            Description = 'Original description',
            ShipToAddressAccount__c = shipTo.Id,
            ShipToAddress__Street__s = '100 Ship St',
            ShipToAddress__City__s = 'Mentor',
            ShipToAddress__StateCode__s = 'OH',
            ShipToAddress__PostalCode__s = '44060',
            ShipToAddress__CountryCode__s = 'US'
        );
        ReturnOrderLineItem lineItem = [
            SELECT Id
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrder.Id
            LIMIT 1
        ];

        ReceivingService.FinishReceivingRequest request =
            new ReceivingService.FinishReceivingRequest();
        request.returnOrderId = returnOrder.Id;
        request.lineItemId = lineItem.Id;
        request.isRedirected = true;
        request.redirectLocationId = repairCenter.Id;
        request.redirectionNotes = 'Send to Birmingham';

        Test.startTest();
        ReceivingService.FinishReceivingResult result =
            ReceivingService.finishReceivingItem(request);
        Test.stopTest();

        Assert.isTrue(result.isRedirected);
        Assert.isNotNull(result.redirectReturnOrderId);

        ReturnOrder redirected = [
            SELECT ParentReturnOrder__c, DestinationLocationId, Status, Description,
                ShipToAddressAccount__c, ShipToAddress__Street__s, ShipToAddress__City__s,
                ShipToAddress__StateCode__s, ShipToAddress__PostalCode__s,
                ShipToAddress__CountryCode__s
            FROM ReturnOrder
            WHERE Id = :result.redirectReturnOrderId
        ];
        Assert.areEqual(returnOrder.Id, redirected.ParentReturnOrder__c);
        Assert.areEqual(
            'Original description\n\nRedirection Notes: Send to Birmingham',
            redirected.Description
        );
        Assert.areEqual(repairCenter.Id, redirected.DestinationLocationId);
        Assert.areEqual(shipTo.Id, redirected.ShipToAddressAccount__c);
        Assert.areEqual('100 Ship St', redirected.ShipToAddress__Street__s);
        Assert.areEqual('Mentor', redirected.ShipToAddress__City__s);
        Assert.areEqual('OH', redirected.ShipToAddress__StateCode__s);
        Assert.areEqual('44060', redirected.ShipToAddress__PostalCode__s);
        Assert.areEqual('US', redirected.ShipToAddress__CountryCode__s);

        ReturnOrderLineItem sourceLine = [
            SELECT Status__c
            FROM ReturnOrderLineItem
            WHERE Id = :lineItem.Id
        ];
        Assert.areEqual('Redirected', sourceLine.Status__c);
    }

    @IsTest
    static void testFinishReceivingItem_instrumentsRedirectsEveryCreatedLine() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW5492 Finish Instrument Redirect RC',
            LocationType = 'Repair Center'
        );
        insert repairCenter;
        Schema.Location redirectCenter = new Schema.Location(
            Name = 'GW5492 Finish Instrument Redirect Dest',
            LocationType = 'Repair Center'
        );
        insert redirectCenter;

        adb_Account accountBuilder = new adb_Account()
            .name('GW5492 Finish Instrument Redirect Account')
            .systemId('LEG5492FINR');
        accountBuilder.set(Account.OrgIDs__c, '82');
        accountBuilder.set(Account.AccountNumber, 'FIN5492-IR');

        adb_ReturnOrder returnOrderBuilder = new adb_ReturnOrder()
            .account(accountBuilder)
            .status('Created');
        returnOrderBuilder.recordType('CustomerReturn');
        returnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
        returnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Instruments');
        returnOrderBuilder.set(ReturnOrder.DestinationLocationId, repairCenter.Id);

        adb_Product2 productBuilder = new adb_Product2()
            .name('GW5492 Finish Instrument Redirect')
            .isActive(true);
        productBuilder.set(Product2.ProductCode, 'FIN-IRED-5492');
        Product2 product = (Product2) productBuilder.persist();

        adb_ReturnOrderLineItem firstLineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(returnOrderBuilder)
            .quantityReturned(1);
        firstLineBuilder.set(ReturnOrderLineItem.Product2Id, product.Id);
        firstLineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        ReturnOrderLineItem firstLine = (ReturnOrderLineItem) firstLineBuilder.persist();
        insert new ReturnOrderLineItem(
            ReturnOrderId = firstLine.ReturnOrderId,
            Product2Id = product.Id,
            QuantityReturned = 3,
            Status__c = 'Created'
        );

        ReceivingService.FinishReceivingRequest request =
            new ReceivingService.FinishReceivingRequest();
        request.returnOrderId = firstLine.ReturnOrderId;
        request.lineItemId = firstLine.Id;
        request.isRedirected = true;
        request.redirectLocationId = redirectCenter.Id;
        request.redirectionNotes = 'Redirect the instrument';

        Test.startTest();
        ReceivingService.FinishReceivingResult result =
            ReceivingService.finishReceivingItem(request);
        Test.stopTest();

        Assert.isTrue(result.isRedirected);
        Assert.isTrue(result.returnOrderFullyReceived);

        List<ReturnOrderLineItem> sourceLines = [
            SELECT Status__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :firstLine.ReturnOrderId
        ];
        Assert.areEqual(2, sourceLines.size());
        for (ReturnOrderLineItem sourceLine : sourceLines) {
            Assert.areEqual('Redirected', sourceLine.Status__c);
        }
        Assert.areEqual(
            2,
            [
                SELECT COUNT()
                FROM ReturnOrderLineItem
                WHERE ReturnOrderId = :result.redirectReturnOrderId
            ]
        );
        ReturnOrder sourceOrder = [
            SELECT Status
            FROM ReturnOrder
            WHERE Id = :firstLine.ReturnOrderId
        ];
        Assert.areEqual('Redirected', sourceOrder.Status);
        ReturnOrder redirectedOrder = [
            SELECT Description
            FROM ReturnOrder
            WHERE Id = :result.redirectReturnOrderId
        ];
        Assert.areEqual(
            'Redirection Notes: Redirect the instrument',
            redirectedOrder.Description
        );
    }

    @IsTest
    static void testFinishReceivingItem_internalRepairSetsAccountAndFlag() {
        adb_Account internalBuilder = new adb_Account()
            .name('GW5492 Finish Internal')
            .systemId('LEG5492FINI');
        internalBuilder.set(Account.Type, 'I');
        internalBuilder.set(Account.OrgIDs__c, '82');
        internalBuilder.set(Account.BillingStreet, '2720 Gunter Park East');
        internalBuilder.set(Account.BillingCity, 'Montgomery');
        internalBuilder.set(Account.BillingStateCode, 'AL');
        internalBuilder.set(Account.BillingPostalCode, '36109');
        internalBuilder.set(Account.BillingCountryCode, 'US');
        Account internalAccount = (Account) internalBuilder.persist();

        ReturnOrder returnOrder = [SELECT Id, AccountId FROM ReturnOrder LIMIT 1];
        ReturnOrderLineItem lineItem = [
            SELECT Id
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrder.Id
            LIMIT 1
        ];

        ReceivingService.FinishReceivingRequest request =
            new ReceivingService.FinishReceivingRequest();
        request.returnOrderId = returnOrder.Id;
        request.lineItemId = lineItem.Id;
        request.disinfected = 'Clean';
        request.quantityReceived = 1;
        request.internalAccountId = internalAccount.Id;
        request.internalRepairNotes = 'Internal notes';

        Test.startTest();
        ReceivingService.FinishReceivingResult result =
            ReceivingService.finishReceivingItem(request);
        Test.stopTest();

        List<WorkOrder> workOrders = [
            SELECT AccountId, BillTo__c, BillToAddressAccount__c, IsInternalRepair__c, Notes__c,
                BillToAddress__Street__s, BillToAddress__City__s, BillToAddress__StateCode__s,
                BillToAddress__PostalCode__s, BillToAddress__CountryCode__s
            FROM WorkOrder
            WHERE Id IN :new Set<Id>{ result.workOrderId, result.parentWorkOrderId }
        ];
        Assert.areEqual(2, workOrders.size());
        for (WorkOrder workOrder : workOrders) {
            Assert.areEqual(returnOrder.AccountId, workOrder.AccountId);
            Assert.areEqual(internalAccount.Id, workOrder.BillTo__c);
            Assert.areEqual(null, workOrder.BillToAddressAccount__c);
            Assert.areEqual('2720 Gunter Park East', workOrder.BillToAddress__Street__s);
            Assert.areEqual('Montgomery', workOrder.BillToAddress__City__s);
            Assert.areEqual('AL', workOrder.BillToAddress__StateCode__s);
            Assert.areEqual('36109', workOrder.BillToAddress__PostalCode__s);
            Assert.areEqual('US', workOrder.BillToAddress__CountryCode__s);
            Assert.isTrue(workOrder.IsInternalRepair__c);
            Assert.areEqual('Internal notes', workOrder.Notes__c);
        }
    }

    @IsTest
    static void testFinishReceivingItem_assignsServicePricebookAndBillToCurrency() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW5492 Finish Pricebook RC',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        adb_Account accountBuilder = new adb_Account()
            .name('GW5492 Finish Pricebook Account')
            .systemId('LEG5492FINP');
        accountBuilder.set(Account.OrgIDs__c, '82');
        accountBuilder.set(Account.AccountNumber, 'FIN5492-PB');

        adb_ReturnOrder returnOrderBuilder = new adb_ReturnOrder()
            .account(accountBuilder)
            .status('Created');
        returnOrderBuilder.recordType('CustomerReturn');
        returnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
        returnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Serialized');
        returnOrderBuilder.set(ReturnOrder.DestinationLocationId, repairCenter.Id);

        adb_Product2 productBuilder = new adb_Product2()
            .name('GW5492 Finish Pricebook Product')
            .isActive(true);
        productBuilder.set(Product2.ProductCode, 'FIN-PB-5492');
        Product2 product = (Product2) productBuilder.persist();
        insert new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );
        
        ensureReceivingPricebooksForProduct(product.Id);
        // Reuse the IMS Service Pricebook seeded above. A second insert with the same
        // name leaves selectActiveByName resolving a different Id than this local variable.
        Pricebook2 servicePricebook = [
            SELECT Id
            FROM Pricebook2
            WHERE Name = 'IMS Service Pricebook'
            AND IsActive = TRUE
            LIMIT 1
        ];

        adb_ReturnOrderLineItem lineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(returnOrderBuilder)
            .quantityReturned(1);
        lineBuilder.set(ReturnOrderLineItem.Product2Id, product.Id);
        lineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        lineBuilder.set(ReturnOrderLineItem.SerialNumber__c, 'SN5492PB01');
        ReturnOrderLineItem lineItem = (ReturnOrderLineItem) lineBuilder.persist();

        Id returnOrderAccountId = [
            SELECT AccountId
            FROM ReturnOrder
            WHERE Id = :lineItem.ReturnOrderId
        ].AccountId;
        insert new Account(
            Name = 'GW5492 Finish Bill To',
            AccountNumber = 'FIN5492-PB',
            ParentId = returnOrderAccountId,
            Type = 'Address',
            BilltoAddressStatus__c = 'Primary',
            CurrencyIsoCode = 'USD',
            BillingStreet = '100 Bill St',
            BillingCity = 'Mentor',
            BillingStateCode = 'OH',
            BillingPostalCode = '44060',
            BillingCountryCode = 'US'
        );
        Account shipTo = new Account(
            Name = 'GW5492 Finish Ship To',
            ParentId = returnOrderAccountId,
            Type = 'Address',
            ShiptoAddressStatus__c = 'Primary',
            BillingStreet = '200 Ship St',
            BillingCity = 'Cleveland',
            BillingStateCode = 'OH',
            BillingPostalCode = '44101',
            BillingCountryCode = 'US'
        );
        insert shipTo;
        update new ReturnOrder(
            Id = lineItem.ReturnOrderId,
            ShipToAddressAccount__c = shipTo.Id
        );

        ReceivingService.FinishReceivingRequest request =
            new ReceivingService.FinishReceivingRequest();
        request.returnOrderId = lineItem.ReturnOrderId;
        request.lineItemId = lineItem.Id;
        request.disinfected = 'Clean';
        request.quantityReceived = 1;

        Test.startTest();
        ReceivingService.FinishReceivingResult result =
            ReceivingService.finishReceivingItem(request);
        Test.stopTest();

        Account billTo = [
            SELECT Id
            FROM Account
            WHERE AccountNumber = 'FIN5492-PB'
            AND Type = 'Address'
            LIMIT 1
        ];
        List<WorkOrder> workOrders = [
            SELECT Pricebook2Id, CurrencyIsoCode, BillTo__c,
                BillToAddress__Street__s, BillToAddress__City__s, BillToAddress__StateCode__s,
                BillToAddress__PostalCode__s, BillToAddress__CountryCode__s,
                Street, City, StateCode, PostalCode, CountryCode
            FROM WorkOrder
            WHERE Id IN :new Set<Id>{ result.workOrderId, result.parentWorkOrderId }
        ];
        Assert.areEqual(2, workOrders.size());
        for (WorkOrder workOrder : workOrders) {
            Assert.areEqual(servicePricebook.Id, workOrder.Pricebook2Id);
            Assert.areEqual('USD', workOrder.CurrencyIsoCode);
            Assert.areEqual(billTo.Id, workOrder.BillTo__c);
            Assert.areEqual('100 Bill St', workOrder.BillToAddress__Street__s);
            Assert.areEqual('Mentor', workOrder.BillToAddress__City__s);
            Assert.areEqual('OH', workOrder.BillToAddress__StateCode__s);
            Assert.areEqual('44060', workOrder.BillToAddress__PostalCode__s);
            Assert.areEqual('US', workOrder.BillToAddress__CountryCode__s);
            Assert.areEqual('200 Ship St', workOrder.Street);
            Assert.areEqual('Cleveland', workOrder.City);
            Assert.areEqual('OH', workOrder.StateCode);
            Assert.areEqual('44101', workOrder.PostalCode);
            Assert.areEqual('US', workOrder.CountryCode);
        }
    }

    @IsTest
    static void testFinishReceivingItem_serializedIgnoresOutsideVendor() {
        ReturnOrder returnOrder = [
            SELECT Id
            FROM ReturnOrder
            WHERE Account.Name = 'GW5492 Finish Account'
            LIMIT 1
        ];
        ReturnOrderLineItem lineItem = [
            SELECT Id
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrder.Id
            LIMIT 1
        ];
        Account vendor = new Account(Name = 'GW5492 Finish Vendor', Type = 'Vendor');
        insert vendor;

        ReceivingService.FinishReceivingRequest request =
            new ReceivingService.FinishReceivingRequest();
        request.returnOrderId = returnOrder.Id;
        request.lineItemId = lineItem.Id;
        request.disinfected = 'Clean';
        request.quantityReceived = 1;
        request.vendorAccountId = vendor.Id;
        request.instructionsToVendor = 'Do not copy';

        Test.startTest();
        ReceivingService.FinishReceivingResult result =
            ReceivingService.finishReceivingItem(request);
        Test.stopTest();

        List<WorkOrder> workOrders = [
            SELECT SubStatus__c, Vendor__c, InstructionsToVendor__c, RecordType.DeveloperName
            FROM WorkOrder
            WHERE Id IN :new Set<Id>{ result.workOrderId, result.parentWorkOrderId }
        ];
        Assert.areEqual(2, workOrders.size());
        for (WorkOrder workOrder : workOrders) {
            Assert.areEqual('RepairCenterDevices', workOrder.RecordType.DeveloperName);
            Assert.areNotEqual('Ship to Vendor', workOrder.SubStatus__c);
            Assert.isNull(workOrder.Vendor__c);
            Assert.isNull(workOrder.InstructionsToVendor__c);
        }
        WorkOrder child = [
            SELECT SubStatus__c
            FROM WorkOrder
            WHERE Id = :result.workOrderId
        ];
        Assert.areEqual('Ready for Eval', child.SubStatus__c);
    }

    @IsTest
    static void testFinishReceivingItem_instrumentsIgnoreOutsideVendor() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW5492 Finish Vendor Instrument RC',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        adb_Account accountBuilder = new adb_Account()
            .name('GW5492 Finish Vendor Instrument Account')
            .systemId('LEG5492FINV');
        accountBuilder.set(Account.OrgIDs__c, '82');
        accountBuilder.set(Account.AccountNumber, 'FIN5492-IV');

        adb_ReturnOrder returnOrderBuilder = new adb_ReturnOrder()
            .account(accountBuilder)
            .status('Created');
        returnOrderBuilder.recordType('CustomerReturn');
        returnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
        returnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Instruments');
        returnOrderBuilder.set(ReturnOrder.DestinationLocationId, repairCenter.Id);

        adb_Product2 productBuilder = new adb_Product2()
            .name('GW5492 Finish Vendor Instrument')
            .isActive(true);
        productBuilder.set(Product2.ProductCode, 'FIN-VINST-5492');
        Product2 product = (Product2) productBuilder.persist();
        ensureReceivingPricebooksForProduct(product.Id);

        adb_ReturnOrderLineItem lineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(returnOrderBuilder)
            .quantityReturned(2);
        lineBuilder.set(ReturnOrderLineItem.Product2Id, product.Id);
        lineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        ReturnOrderLineItem lineItem = (ReturnOrderLineItem) lineBuilder.persist();

        Account vendor = new Account(Name = 'GW5492 Instrument Vendor', Type = 'Vendor');
        insert vendor;

        ReceivingService.FinishReceivingRequest request =
            new ReceivingService.FinishReceivingRequest();
        request.returnOrderId = lineItem.ReturnOrderId;
        request.lineItemId = lineItem.Id;
        request.disinfected = 'Clean';
        request.quantityReceived = 2;
        request.vendorAccountId = vendor.Id;
        request.instructionsToVendor = 'Do not copy';

        Test.startTest();
        ReceivingService.FinishReceivingResult result =
            ReceivingService.finishReceivingItem(request);
        Test.stopTest();

        WorkOrder workOrder = [
            SELECT SubStatus__c, Vendor__c, InstructionsToVendor__c, RecordType.DeveloperName
            FROM WorkOrder
            WHERE Id = :result.workOrderId
        ];
        Assert.areEqual('RepairCenterInstruments', workOrder.RecordType.DeveloperName);
        Assert.areEqual('Ready for Eval', workOrder.SubStatus__c);
        Assert.isNull(workOrder.Vendor__c);
        Assert.isNull(workOrder.InstructionsToVendor__c);
    }

    @IsTest
    static void testFinishReceivingItem_instrumentsReceivesEveryLine() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW5492 Finish Instrument RC',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        adb_Account accountBuilder = new adb_Account()
            .name('GW5492 Finish Instrument Account')
            .systemId('LEG5492FINI');
        accountBuilder.set(Account.OrgIDs__c, '82');
        accountBuilder.set(Account.AccountNumber, 'FIN5492-IN');

        adb_ReturnOrder returnOrderBuilder = new adb_ReturnOrder()
            .account(accountBuilder)
            .status('Created');
        returnOrderBuilder.recordType('CustomerReturn');
        returnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
        returnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Instruments');
        returnOrderBuilder.set(ReturnOrder.DestinationLocationId, repairCenter.Id);
        returnOrderBuilder.set(ReturnOrder.SalesRep__c, UserInfo.getUserId());

        adb_Product2 productBuilder = new adb_Product2()
            .name('GW5492 Finish Instrument')
            .isActive(true);
        productBuilder.set(Product2.ProductCode, 'FIN-INST-5492');
        Product2 product = (Product2) productBuilder.persist();
        insert new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );

        
        ensureReceivingPricebooksForProduct(product.Id);
adb_ReturnOrderLineItem firstLineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(returnOrderBuilder)
            .quantityReturned(3);
        firstLineBuilder.set(ReturnOrderLineItem.Product2Id, product.Id);
        firstLineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        firstLineBuilder.set(ReturnOrderLineItem.ModRequest__c, true);
        ReturnOrderLineItem firstLine = (ReturnOrderLineItem) firstLineBuilder.persist();

        Id accountId = [
            SELECT AccountId
            FROM ReturnOrder
            WHERE Id = :firstLine.ReturnOrderId
        ].AccountId;
        Contact headerContact = new Contact(
            LastName = 'Instrument Header',
            AccountId = accountId,
            Email = 'instrument.header@example.com'
        );
        insert headerContact;
        update new ReturnOrder(
            Id = firstLine.ReturnOrderId,
            CustomerPO__c = 'PO-5492',
            CustomerReference__c = 'REF-5492',
            RepairWarranty__c = 'Yes',
            WarrantyNotes__c = 'Covered under warranty',
            PreviousReturnOrder__c = 'RO-PRIOR',
            EstimateContact__c = headerContact.Id,
            ModRequestContact__c = headerContact.Id
        );
        insert new ContentVersion(
            Title = 'Instrument Mod Form',
            PathOnClient = 'InstrumentModForm.jpg',
            VersionData = Blob.valueOf('mod-form'),
            Description = ReceivingService.MOD_FORM_FILE_DESCRIPTION,
            FirstPublishLocationId = firstLine.ReturnOrderId
        );

        insert new ReturnOrderLineItem(
            ReturnOrderId = firstLine.ReturnOrderId,
            Product2Id = product.Id,
            QuantityReturned = 4,
            Status__c = 'Created'
        );

        ReceivingService.FinishReceivingRequest request =
            new ReceivingService.FinishReceivingRequest();
        request.returnOrderId = firstLine.ReturnOrderId;
        request.lineItemId = firstLine.Id;
        request.disinfected = 'Clean';
        request.quantityReceived = 7;

        Test.startTest();
        ReceivingService.FinishReceivingResult result =
            ReceivingService.finishReceivingItem(request);
        Test.stopTest();

        Assert.isTrue(result.returnOrderFullyReceived);
        Assert.isTrue(result.hasWorkOrderCreated);

        List<ReturnOrderLineItem> updatedLines = [
            SELECT Status__c, QuantityReceived
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :firstLine.ReturnOrderId
            ORDER BY QuantityReturned
        ];
        Assert.areEqual(2, updatedLines.size());
        Assert.areEqual('Received', updatedLines[0].Status__c);
        Assert.areEqual(3, updatedLines[0].QuantityReceived);
        Assert.areEqual('Received', updatedLines[1].Status__c);
        Assert.areEqual(4, updatedLines[1].QuantityReceived);

        ReturnOrder updatedOrder = [
            SELECT Status, QuantityReceived__c
            FROM ReturnOrder
            WHERE Id = :firstLine.ReturnOrderId
        ];
        Assert.areEqual('Received', updatedOrder.Status);
        Assert.areEqual(7, updatedOrder.QuantityReceived__c);

        WorkOrder receivedWorkOrder = [
            SELECT
                AccountManager__c,
                CustomerPO__c,
                CustomerReference__c,
                RepairWarranty__c,
                WarrantyNotes__c,
                PreviousReturnOrder__c,
                EstimateContact__c,
                ModRequest__c,
                ModRequestContact__c
            FROM WorkOrder
            WHERE Id = :result.workOrderId
        ];
        Assert.isNull(receivedWorkOrder.AccountManager__c);
        Assert.areEqual('PO-5492', receivedWorkOrder.CustomerPO__c);
        Assert.areEqual('REF-5492', receivedWorkOrder.CustomerReference__c);
        Assert.areEqual('Yes', receivedWorkOrder.RepairWarranty__c);
        Assert.areEqual('Covered under warranty', receivedWorkOrder.WarrantyNotes__c);
        Assert.areEqual('RO-PRIOR', receivedWorkOrder.PreviousReturnOrder__c);
        Assert.areEqual(headerContact.Id, receivedWorkOrder.EstimateContact__c);
        Assert.areEqual(headerContact.Id, receivedWorkOrder.ModRequestContact__c);
        Assert.isTrue(receivedWorkOrder.ModRequest__c);

        Integer modFormLinks = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :result.workOrderId
        ];
        Assert.areEqual(1, modFormLinks);
    }

    @IsTest
    static void testFinishReceivingItem_modFormPhotoSetsModRequest() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW5492 Mod Form Photo RC',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        adb_Account accountBuilder = new adb_Account()
            .name('GW5492 Mod Form Photo Account')
            .systemId('LEG5492MODP');
        accountBuilder.set(Account.OrgIDs__c, '82');
        accountBuilder.set(Account.AccountNumber, 'FIN5492-MP');

        adb_ReturnOrder returnOrderBuilder = new adb_ReturnOrder()
            .account(accountBuilder)
            .status('Created');
        returnOrderBuilder.recordType('CustomerReturn');
        returnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
        returnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Instruments');
        returnOrderBuilder.set(ReturnOrder.DestinationLocationId, repairCenter.Id);

        adb_Product2 productBuilder = new adb_Product2()
            .name('GW5492 Mod Form Photo')
            .isActive(true);
        productBuilder.set(Product2.ProductCode, 'FIN-MODP-5492');
        Product2 product = (Product2) productBuilder.persist();
        insert new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );

        
        ensureReceivingPricebooksForProduct(product.Id);
adb_ReturnOrderLineItem lineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(returnOrderBuilder)
            .quantityReturned(1);
        lineBuilder.set(ReturnOrderLineItem.Product2Id, product.Id);
        lineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        lineBuilder.set(ReturnOrderLineItem.ModRequest__c, false);
        ReturnOrderLineItem lineItem = (ReturnOrderLineItem) lineBuilder.persist();

        insert new ContentVersion(
            Title = 'Unflagged Mod Form',
            PathOnClient = 'UnflaggedModForm.jpg',
            VersionData = Blob.valueOf('mod-form-photo'),
            Description = ReceivingService.MOD_FORM_FILE_DESCRIPTION,
            FirstPublishLocationId = lineItem.ReturnOrderId
        );

        ReceivingService.FinishReceivingRequest request =
            new ReceivingService.FinishReceivingRequest();
        request.returnOrderId = lineItem.ReturnOrderId;
        request.lineItemId = lineItem.Id;
        request.disinfected = 'Clean';
        request.quantityReceived = 1;

        Test.startTest();
        ReceivingService.FinishReceivingResult result =
            ReceivingService.finishReceivingItem(request);
        Test.stopTest();

        WorkOrder workOrder = [
            SELECT ModRequest__c
            FROM WorkOrder
            WHERE Id = :result.workOrderId
        ];
        Assert.isTrue(workOrder.ModRequest__c);
    }

    @IsTest
    static void testFinishReceivingItem_instrumentsMapsContaminationChecks() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW5492 Instrument Checks RC',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        adb_Account accountBuilder = new adb_Account()
            .name('GW5492 Instrument Checks Account')
            .systemId('LEG5492CHK');
        accountBuilder.set(Account.OrgIDs__c, '82');
        accountBuilder.set(Account.AccountNumber, 'FIN5492-CK');

        adb_ReturnOrder returnOrderBuilder = new adb_ReturnOrder()
            .account(accountBuilder)
            .status('Created');
        returnOrderBuilder.recordType('CustomerReturn');
        returnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
        returnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Instruments');
        returnOrderBuilder.set(ReturnOrder.DestinationLocationId, repairCenter.Id);

        adb_Product2 productBuilder = new adb_Product2()
            .name('GW5492 Instrument Checks')
            .isActive(true);
        productBuilder.set(Product2.ProductCode, 'FIN-CHK-5492');
        Product2 product = (Product2) productBuilder.persist();
        insert new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );

        
        ensureReceivingPricebooksForProduct(product.Id);
adb_ReturnOrderLineItem lineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(returnOrderBuilder)
            .quantityReturned(1);
        lineBuilder.set(ReturnOrderLineItem.Product2Id, product.Id);
        lineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        ReturnOrderLineItem lineItem = (ReturnOrderLineItem) lineBuilder.persist();

        ReceivingService.FinishReceivingRequest request =
            new ReceivingService.FinishReceivingRequest();
        request.returnOrderId = lineItem.ReturnOrderId;
        request.lineItemId = lineItem.Id;
        request.disinfected = 'Contaminated';
        request.resiTestPerformed = true;
        request.resiTestFailed = true;
        request.visualInspection = true;
        request.bioBag = true;
        request.quantityReceived = 1;

        Test.startTest();
        ReceivingService.FinishReceivingResult result =
            ReceivingService.finishReceivingItem(request);
        Test.stopTest();

        WorkOrder workOrder = [
            SELECT
                Contaminated__c,
                SubStatus__c,
                IsResiTestFailed__c,
                IsVisualInspection__c,
                IsBioBag__c,
                ParentWorkOrderId
            FROM WorkOrder
            WHERE Id = :result.workOrderId
        ];
        Assert.isNull(workOrder.ParentWorkOrderId);
        Assert.isTrue(workOrder.Contaminated__c);
        Assert.areEqual('Contaminated', workOrder.SubStatus__c);
        Assert.isTrue(workOrder.IsResiTestFailed__c);
        Assert.isTrue(workOrder.IsVisualInspection__c);
        Assert.isTrue(workOrder.IsBioBag__c);
    }

    @IsTest
    static void testFinishReceivingItem_stirrupCreatesAccessoryLine() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW5492 Finish Stirrup RC',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        adb_Account accountBuilder = new adb_Account()
            .name('GW5492 Finish Stirrup Account')
            .systemId('LEG5492FINS');
        accountBuilder.set(Account.OrgIDs__c, '82');
        accountBuilder.set(Account.AccountNumber, 'FIN5492-ST');

        adb_ReturnOrder returnOrderBuilder = new adb_ReturnOrder()
            .account(accountBuilder)
            .status('Created');
        returnOrderBuilder.recordType('CustomerReturn');
        returnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
        returnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Other (Serialized)');
        returnOrderBuilder.set(ReturnOrder.DestinationLocationId, repairCenter.Id);

        adb_Product2 productBuilder = new adb_Product2()
            .name('GW5492 Finish Stirrup')
            .isActive(true);
        productBuilder.set(Product2.ProductCode, 'FIN-STIR-5492');
        productBuilder.set(Product2.DeviceType__c, 'STIRRUP');
        Product2 product = (Product2) productBuilder.persist();
        insert new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );

        
        ensureReceivingPricebooksForProduct(product.Id);
adb_ReturnOrderLineItem lineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(returnOrderBuilder)
            .quantityReturned(1);
        lineBuilder.set(ReturnOrderLineItem.Product2Id, product.Id);
        lineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        lineBuilder.set(ReturnOrderLineItem.SerialNumber__c, 'SN5492STIR');
        lineBuilder.setParent(
            ReturnOrderLineItem.EstimateContact__c,
            new adb_Contact().lastName('GW5492 Stirrup Estimate')
        );
        lineBuilder.set(ReturnOrderLineItem.RepairWarranty__c, 'Yes');
        lineBuilder.set(ReturnOrderLineItem.WarrantyNotes__c, 'GW5492 stirrup warranty');
        lineBuilder.set(ReturnOrderLineItem.CustomerPO__c, 'PO-STIR-5492');
        lineBuilder.set(ReturnOrderLineItem.CustomerReference__c, 'REF-STIR-5492');
        lineBuilder.set(ReturnOrderLineItem.PreviousReturnOrder__c, 'RO-STIR-PRIOR');
        ReturnOrderLineItem lineItem = (ReturnOrderLineItem) lineBuilder.persist();
        ReturnOrder returnOrder = [
            SELECT Id, AccountId
            FROM ReturnOrder
            WHERE Id = :lineItem.ReturnOrderId
        ];
        Case cioCase = new Case(
            Subject = 'GW5492 Stirrup CIO',
            Status = 'New',
            Origin = 'Repair Support',
            AccountId = returnOrder.AccountId,
            Category__c = 'Continuous Improvement Opportunity (CIO)'
        );
        insert cioCase;
        update new ReturnOrder(Id = returnOrder.Id, CaseId = cioCase.Id);

        ReceivingService.FinishAccessoryInput accessory =
            new ReceivingService.FinishAccessoryInput();
        accessory.accessoryType = 'Case';
        accessory.storageLocation = 'One';
        accessory.quantity = 4;

        ReceivingService.FinishReceivingRequest request =
            new ReceivingService.FinishReceivingRequest();
        request.returnOrderId = returnOrder.Id;
        request.lineItemId = lineItem.Id;
        request.disinfected = 'Clean';
        request.quantityReceived = 1;
        request.accessories = new List<ReceivingService.FinishAccessoryInput>{ accessory };

        Test.startTest();
        ReceivingService.FinishReceivingResult result =
            ReceivingService.finishReceivingItem(request);
        Test.stopTest();

        WorkOrderLineItem accessoryLine = [
            SELECT Quantity, UnitQty__c, AccessoryType__c, WorkOrderId
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :result.workOrderId
              AND IsAccessory__c = TRUE
        ];
        Assert.areEqual(result.workOrderId, accessoryLine.WorkOrderId);
        Assert.areEqual(4, accessoryLine.Quantity);

        WorkOrder childWorkOrder = [
            SELECT
                CustomerPO__c,
                CustomerReference__c,
                PreviousReturnOrder__c,
                ParentWorkOrderId,
                Status,
                CaseId,
                ContinuousImprovementOpportunity__c
            FROM WorkOrder
            WHERE Id = :result.workOrderId
        ];
        Assert.isNotNull(childWorkOrder.ParentWorkOrderId);
        Assert.areEqual('PO-STIR-5492', childWorkOrder.CustomerPO__c);
        Assert.areEqual('REF-STIR-5492', childWorkOrder.CustomerReference__c);
        Assert.areEqual('RO-STIR-PRIOR', childWorkOrder.PreviousReturnOrder__c);
        Assert.areEqual(cioCase.Id, childWorkOrder.CaseId);
        Assert.areEqual(true, childWorkOrder.ContinuousImprovementOpportunity__c);
        WorkOrder parentWorkOrder = [
            SELECT Status, CaseId, ContinuousImprovementOpportunity__c, SubStatus__c
            FROM WorkOrder
            WHERE Id = :childWorkOrder.ParentWorkOrderId
        ];
        Assert.areEqual(childWorkOrder.Status, parentWorkOrder.Status);
        Assert.isNull(parentWorkOrder.SubStatus__c);
        Assert.areEqual(cioCase.Id, parentWorkOrder.CaseId);
        Assert.areEqual(true, parentWorkOrder.ContinuousImprovementOpportunity__c);
        Assert.areEqual(4, accessoryLine.UnitQty__c);
        Assert.areEqual('Case', accessoryLine.AccessoryType__c);

        ReturnOrderLineItem refreshedLine = [
            SELECT EstimateContact__c, RepairWarranty__c, WarrantyNotes__c
            FROM ReturnOrderLineItem
            WHERE Id = :lineItem.Id
        ];
        WorkOrder child = [
            SELECT EstimateContact__c, RepairWarranty__c, WarrantyNotes__c
            FROM WorkOrder
            WHERE Id = :result.workOrderId
        ];
        Assert.isNotNull(refreshedLine.EstimateContact__c);
        Assert.areEqual(refreshedLine.EstimateContact__c, child.EstimateContact__c);
        Assert.areEqual('Yes', child.RepairWarranty__c);
        Assert.areEqual(refreshedLine.WarrantyNotes__c, child.WarrantyNotes__c);
    }

    @IsTest
    static void testFinishReceivingItem_vendorWorkOrderMapsLineFields() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW5492 Finish Vendor Map RC',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        adb_Account accountBuilder = new adb_Account()
            .name('GW5492 Finish Vendor Map Account')
            .systemId('LEG5492FINM');
        accountBuilder.set(Account.OrgIDs__c, '82');
        accountBuilder.set(Account.AccountNumber, 'FIN5492-VM');

        adb_ReturnOrder returnOrderBuilder = new adb_ReturnOrder()
            .account(accountBuilder)
            .status('Created');
        returnOrderBuilder.recordType('CustomerReturn');
        returnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
        returnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Other (Serialized)');
        returnOrderBuilder.set(ReturnOrder.DestinationLocationId, repairCenter.Id);

        adb_Product2 productBuilder = new adb_Product2()
            .name('GW5492 Finish Vendor Map')
            .isActive(true);
        productBuilder.set(Product2.ProductCode, 'FIN-VEND-5492');
        Product2 product = (Product2) productBuilder.persist();
        insert new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );

        
        ensureReceivingPricebooksForProduct(product.Id);
adb_ReturnOrderLineItem lineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(returnOrderBuilder)
            .quantityReturned(1);
        lineBuilder.set(ReturnOrderLineItem.Product2Id, product.Id);
        lineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        lineBuilder.set(ReturnOrderLineItem.CustomerPO__c, 'PO-VEND-5492');
        lineBuilder.set(ReturnOrderLineItem.CustomerReference__c, 'REF-VEND-5492');
        lineBuilder.set(ReturnOrderLineItem.PreviousReturnOrder__c, 'RO-VEND-PRIOR');
        lineBuilder.set(ReturnOrderLineItem.ReportedProblem__c, 'Vendor reported problem');
        ReturnOrderLineItem lineItem = (ReturnOrderLineItem) lineBuilder.persist();

        ReturnOrder returnOrder = [
            SELECT Id, AccountId
            FROM ReturnOrder
            WHERE Id = :lineItem.ReturnOrderId
        ];
        Case cioCase = new Case(
            Subject = 'GW5492 Vendor CIO',
            Status = 'New',
            Origin = 'Repair Support',
            AccountId = returnOrder.AccountId,
            Category__c = 'Continuous Improvement Opportunity (CIO)'
        );
        insert cioCase;
        update new ReturnOrder(Id = returnOrder.Id, CaseId = cioCase.Id);

        Account vendor = new Account(Name = 'GW5492 Vendor Map Vendor', Type = 'Vendor');
        insert vendor;

        ReceivingService.FinishReceivingRequest request =
            new ReceivingService.FinishReceivingRequest();
        request.returnOrderId = returnOrder.Id;
        request.lineItemId = lineItem.Id;
        request.disinfected = 'Clean';
        request.quantityReceived = 1;
        request.vendorAccountId = vendor.Id;
        request.instructionsToVendor = 'Ship it out';

        Test.startTest();
        ReceivingService.FinishReceivingResult result =
            ReceivingService.finishReceivingItem(request);
        Test.stopTest();

        WorkOrder workOrder = [
            SELECT
                RecordType.DeveloperName,
                SubStatus__c,
                Vendor__c,
                CustomerPO__c,
                CustomerReference__c,
                PreviousReturnOrder__c,
                Description,
                CaseId,
                ContinuousImprovementOpportunity__c,
                ParentWorkOrderId,
                ShippedToVendorDate__c
            FROM WorkOrder
            WHERE Id = :result.workOrderId
        ];
        Assert.isNull(workOrder.ParentWorkOrderId);
        Assert.areEqual('RepairCenterVendor', workOrder.RecordType.DeveloperName);
        Assert.areEqual('Ship to Vendor', workOrder.SubStatus__c);
        Assert.areEqual(Date.today(), workOrder.ShippedToVendorDate__c);
        Assert.areEqual(vendor.Id, workOrder.Vendor__c);
        Assert.areEqual('PO-VEND-5492', workOrder.CustomerPO__c);
        Assert.areEqual('REF-VEND-5492', workOrder.CustomerReference__c);
        Assert.areEqual('RO-VEND-PRIOR', workOrder.PreviousReturnOrder__c);
        Assert.areEqual('Vendor reported problem', workOrder.Description);
        Assert.areEqual(cioCase.Id, workOrder.CaseId);
        Assert.areEqual(true, workOrder.ContinuousImprovementOpportunity__c);
    }

    @IsTest
    static void testFinishReceivingItem_nonSerializedSameVendorSharesWorkOrder() {
        // Setup
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW5492 Shared Vendor RC',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        adb_Account accountBuilder = new adb_Account()
            .name('GW5492 Shared Vendor Account')
            .systemId('LEG5492SHV');
        accountBuilder.set(Account.OrgIDs__c, '82');
        accountBuilder.set(Account.AccountNumber, 'FIN5492-SHV');

        adb_ReturnOrder returnOrderBuilder = new adb_ReturnOrder()
            .account(accountBuilder)
            .status('Created');
        returnOrderBuilder.recordType('CustomerReturn');
        returnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
        returnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Other (Non-Serialized)');
        returnOrderBuilder.set(ReturnOrder.DestinationLocationId, repairCenter.Id);

        adb_Product2 productBuilder = new adb_Product2()
            .name('GW5492 Shared Vendor Product')
            .isActive(true);
        productBuilder.set(Product2.ProductCode, 'FIN-SHV-5492');
        Product2 product = (Product2) productBuilder.persist();
        insert new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );

        
        ensureReceivingPricebooksForProduct(product.Id);
        adb_ReturnOrderLineItem firstLineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(returnOrderBuilder)
            .quantityReturned(1);
        firstLineBuilder.set(ReturnOrderLineItem.Product2Id, product.Id);
        firstLineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        ReturnOrderLineItem firstLine = (ReturnOrderLineItem) firstLineBuilder.persist();
        // Extra lines use plain DML. Re-persisting adb children against an already-saved
        // Return Order builder corrupts the static adb graph and can NPE on sort.
        ReturnOrderLineItem secondLine = new ReturnOrderLineItem(
            ReturnOrderId = firstLine.ReturnOrderId,
            Product2Id = product.Id,
            QuantityReturned = 2,
            Status__c = 'Created'
        );
        ReturnOrderLineItem thirdLine = new ReturnOrderLineItem(
            ReturnOrderId = firstLine.ReturnOrderId,
            Product2Id = product.Id,
            QuantityReturned = 1,
            Status__c = 'Created'
        );
        insert new List<ReturnOrderLineItem>{ secondLine, thirdLine };

        Account sameVendor = new Account(Name = 'GW5492 Shared Vendor A', Type = 'Vendor');
        Account otherVendor = new Account(Name = 'GW5492 Shared Vendor B', Type = 'Vendor');
        insert new List<Account>{ sameVendor, otherVendor };

        // Given
        ReceivingService.FinishReceivingRequest firstRequest = finishRequest(
            firstLine,
            sameVendor.Id,
            'Ship it out'
        );
        firstRequest.disinfected = 'Contaminated';
        firstRequest.bioBag = true;
        ReceivingService.FinishReceivingRequest secondRequest = finishRequest(
            secondLine,
            sameVendor.Id,
            'Ship it out\nRush this one'
        );
        ReceivingService.FinishReceivingRequest thirdRequest = finishRequest(
            thirdLine,
            otherVendor.Id,
            'Send separately'
        );

        // When
        Test.startTest();
        ReceivingService.FinishReceivingResult firstResult =
            ReceivingService.finishReceivingItem(firstRequest);
        ReceivingService.FinishReceivingResult secondResult =
            ReceivingService.finishReceivingItem(secondRequest);
        ReceivingService.FinishReceivingResult thirdResult =
            ReceivingService.finishReceivingItem(thirdRequest);
        Test.stopTest();

        // Then
        Assert.areEqual(firstResult.workOrderId, secondResult.workOrderId);
        Assert.areNotEqual(firstResult.workOrderId, thirdResult.workOrderId);

        Map<Id, WorkOrder> workOrdersById = new Map<Id, WorkOrder>([
            SELECT
                Id,
                Vendor__c,
                InstructionsToVendor__c,
                Contaminated__c,
                IsBioBag__c,
                SubStatus__c
            FROM WorkOrder
            WHERE ReturnOrder__c = :firstLine.ReturnOrderId
        ]);
        Assert.isTrue(workOrdersById.get(firstResult.workOrderId).Contaminated__c);
        Assert.areEqual(
            'Contaminated',
            workOrdersById.get(firstResult.workOrderId).SubStatus__c
        );
        Assert.isTrue(
            workOrdersById.get(firstResult.workOrderId).IsBioBag__c,
            'Bio Bag on the first item stays on the shared Vendor Work Order.'
        );
        Assert.isFalse(workOrdersById.get(thirdResult.workOrderId).IsBioBag__c);
        Assert.areEqual(2, workOrdersById.size());
        Assert.areEqual(sameVendor.Id, workOrdersById.get(firstResult.workOrderId).Vendor__c);
        Assert.areEqual(
            'Ship it out\nRush this one',
            workOrdersById.get(firstResult.workOrderId).InstructionsToVendor__c
        );
        Assert.areEqual(
            'Send separately',
            workOrdersById.get(thirdResult.workOrderId).InstructionsToVendor__c
        );
        Assert.areEqual(
            2,
            [
                SELECT COUNT()
                FROM WorkOrderLineItem
                WHERE WorkOrderId = :firstResult.workOrderId
                    AND LineType__c = 'Product Serviced'
                    AND IsAccessory__c = false
            ]
        );
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM WorkOrderLineItem
                WHERE WorkOrderId = :thirdResult.workOrderId
                    AND LineType__c = 'Product Serviced'
                    AND IsAccessory__c = false
            ]
        );
    }

    @IsTest
    static void testFinishReceivingItem_sharedVendorWorkOrderGetsPriorityAndImages() {
        // Setup
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW5492 Priority Image RC',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        adb_Account accountBuilder = new adb_Account()
            .name('GW5492 Priority Image Account')
            .systemId('LEG5492PRI');
        accountBuilder.set(Account.OrgIDs__c, '82');
        accountBuilder.set(Account.AccountNumber, 'FIN5492-PRI');

        adb_ReturnOrder returnOrderBuilder = new adb_ReturnOrder()
            .account(accountBuilder)
            .status('Created');
        returnOrderBuilder.recordType('CustomerReturn');
        returnOrderBuilder.set(ReturnOrder.OperatingUnit__c, '82');
        returnOrderBuilder.set(ReturnOrder.ReturnOrderType__c, 'Other (Non-Serialized)');
        returnOrderBuilder.set(ReturnOrder.DestinationLocationId, repairCenter.Id);

        adb_Product2 productBuilder = new adb_Product2()
            .name('GW5492 Priority Image Product')
            .isActive(true);
        productBuilder.set(Product2.ProductCode, 'FIN-PRI-5492');
        Product2 product = (Product2) productBuilder.persist();
        insert new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );

        
        ensureReceivingPricebooksForProduct(product.Id);
        adb_ReturnOrderLineItem firstLineBuilder = new adb_ReturnOrderLineItem()
            .returnOrder(returnOrderBuilder)
            .quantityReturned(1);
        firstLineBuilder.set(ReturnOrderLineItem.Product2Id, product.Id);
        firstLineBuilder.set(ReturnOrderLineItem.Status__c, 'Created');
        ReturnOrderLineItem firstLine = (ReturnOrderLineItem) firstLineBuilder.persist();
        ReturnOrderLineItem secondLine = new ReturnOrderLineItem(
            ReturnOrderId = firstLine.ReturnOrderId,
            Product2Id = product.Id,
            QuantityReturned = 1,
            Status__c = 'Created',
            IsPriorityRepair__c = true
        );
        insert secondLine;

        Account vendor = new Account(Name = 'GW5492 Priority Vendor', Type = 'Vendor');
        insert vendor;

        ContentVersion firstImage = new ContentVersion(
            Title = 'First item image',
            PathOnClient = 'first-item.jpg',
            VersionData = Blob.valueOf('first-image'),
            FirstPublishLocationId = firstLine.Id
        );
        ContentVersion secondImage = new ContentVersion(
            Title = 'Second item image',
            PathOnClient = 'second-item.jpg',
            VersionData = Blob.valueOf('second-image'),
            FirstPublishLocationId = secondLine.Id
        );
        insert new List<ContentVersion>{ firstImage, secondImage };
        Map<Id, ContentVersion> versionsById = new Map<Id, ContentVersion>([
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id IN :new Set<Id>{ firstImage.Id, secondImage.Id }
        ]);
        Id firstDocumentId = versionsById.get(firstImage.Id).ContentDocumentId;
        Id secondDocumentId = versionsById.get(secondImage.Id).ContentDocumentId;

        // Given
        ReceivingService.FinishReceivingRequest firstRequest = finishRequest(
            firstLine,
            vendor.Id,
            'Ship it out'
        );
        ReceivingService.FinishReceivingRequest secondRequest = finishRequest(
            secondLine,
            vendor.Id,
            'Ship it out'
        );
        secondRequest.contentDocumentIds = new List<Id>{ firstDocumentId, secondDocumentId };

        // When
        Test.startTest();
        ReceivingService.FinishReceivingResult firstResult =
            ReceivingService.finishReceivingItem(firstRequest);
        WorkOrder afterFirst = [
            SELECT IsPriorityRepair__c
            FROM WorkOrder
            WHERE Id = :firstResult.workOrderId
        ];
        ReceivingService.FinishReceivingResult secondResult =
            ReceivingService.finishReceivingItem(secondRequest);
        Test.stopTest();

        // Then
        Assert.isFalse(afterFirst.IsPriorityRepair__c, 'The first item does not flag the Vendor Work Order.');
        Assert.areEqual(firstResult.workOrderId, secondResult.workOrderId);
        WorkOrder sharedWorkOrder = [
            SELECT IsPriorityRepair__c
            FROM WorkOrder
            WHERE Id = :secondResult.workOrderId
        ];
        Assert.isTrue(
            sharedWorkOrder.IsPriorityRepair__c,
            'A later priority item flags the shared Vendor Work Order.'
        );
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :sharedWorkOrder.Id
                    AND ContentDocumentId = :firstDocumentId
            ],
            'The first item image is on the Vendor Work Order once.'
        );
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :sharedWorkOrder.Id
                    AND ContentDocumentId = :secondDocumentId
            ],
            'The second item image is on the Vendor Work Order once, including a duplicate request id.'
        );
    }

    private static ReceivingService.FinishReceivingRequest finishRequest(
        ReturnOrderLineItem lineItem,
        Id vendorAccountId,
        String instructionsToVendor
    ) {
        ReceivingService.FinishReceivingRequest request =
            new ReceivingService.FinishReceivingRequest();
        request.returnOrderId = lineItem.ReturnOrderId;
        request.lineItemId = lineItem.Id;
        request.disinfected = 'Clean';
        request.quantityReceived = lineItem.QuantityReturned;
        request.vendorAccountId = vendorAccountId;
        request.instructionsToVendor = instructionsToVendor;
        return request;
    }

    @IsTest
    static void testFinishReceivingItem_blankRequestThrows() {
        Boolean threw = false;
        try {
            ReceivingService.finishReceivingItem(null);
        } catch (Exception e) {
            threw = true;
        }
        Assert.isTrue(threw);
    }
}