/**
 * @description Tests for PricingFrameworkOracleInvocable.
 * @see PricingFrameworkOracleInvocable
 */
@IsTest
private class PricingFrameworkOracleInvocableTest {
    @IsTest
    static void executePricing_emptyRequestList_returnsEmptyResults() {
        Test.startTest();
        System.assertEquals(
            0,
            PricingFrameworkOracleInvocable.executePricing(null).size()
        );
        System.assertEquals(
            0,
            PricingFrameworkOracleInvocable.executePricing(
                new List<PricingFrameworkOracleInvocable.Request>()
            ).size()
        );
        Test.stopTest();
    }

    @IsTest
    static void executePricing_missingAccount_returnsError() {
        PricingFrameworkOracleInvocable.Request request =
            new PricingFrameworkOracleInvocable.Request();

        Test.startTest();
        List<PricingFrameworkOracleInvocable.Result> results =
            PricingFrameworkOracleInvocable.executePricing(
                new List<PricingFrameworkOracleInvocable.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].isSuccess);
        System.assertEquals('Account Id is required.', results[0].errorMessage);
    }

    @IsTest
    static void executePricing_salesforceSource_skipsOracle() {
        Account account = insertAccount();
        insert new Product2(
            Name = 'GW4585 Labor',
            ProductCode = 'LABOR-4585',
            PricingSource__c = 'Salesforce',
            IsActive = true
        );

        PricingFrameworkOracleInvocable.Request request =
            new PricingFrameworkOracleInvocable.Request();
        request.accountId = account.Id;
        request.workstream = 'FieldService';
        request.pricingLineJson =
            '[{"lineId":"1","productCode":"LABOR-4585","quantity":2}]';

        Test.startTest();
        List<PricingFrameworkOracleInvocable.Result> results =
            PricingFrameworkOracleInvocable.executePricing(
                new List<PricingFrameworkOracleInvocable.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].isSuccess);
        Product2 labor = [SELECT Id FROM Product2 WHERE ProductCode = 'LABOR-4585'];
        System.assert(
            results[0].pricingDataJson.contains(labor.Id),
            'Headless JSON should include the Salesforce-sourced product Id.'
        );
        System.assert(
            results[0].pricingDataJson.contains('"WorkOrder"'),
            'Headless JSON should use the WorkOrder context node.'
        );
        System.assert(
            results[0].pricingDataJson.contains('WorkOrderItem'),
            'Headless JSON should use the WorkOrderItem context node.'
        );
        System.assert(
            results[0].pricingDataJson.contains('"businessObjectType":"WorkOrder"'),
            'Headless JSON should set businessObjectType to WorkOrder.'
        );
        System.assert(
            results[0].pricingDataJson.contains('"businessObjectType":"WorkOrderItem"'),
            'Headless JSON should set line businessObjectType to WorkOrderItem.'
        );
        System.assert(
            results[0].pricingDataJson.contains('SalesTransactionItemSource'),
            'Headless JSON needs SalesTransactionItemSource so Pricing Settings can resolve LineItem.'
        );
        System.assert(
            results[0].pricingDataJson.contains('Pricebook'),
            'Headless JSON needs a Pricebook for Salesforce list price.'
        );
    }

    @IsTest
    static void executePricing_oracleSource_mergesMockPrices() {
        Account account = insertAccount();
        insert new Product2(
            Name = 'GW4585 Part',
            ProductCode = 'PART-4585',
            PricingSource__c = 'Oracle',
            IsActive = true
        );

        PricingFrameworkOracleInvocable.Request request =
            new PricingFrameworkOracleInvocable.Request();
        request.accountId = account.Id;
        request.workstream = 'RepairCenter';
        request.pricingLineJson =
            '[{"lineId":"woli-1","productCode":"PART-4585","quantity":1}]';

        Test.startTest();
        List<PricingFrameworkOracleInvocable.Result> results =
            PricingFrameworkOracleInvocable.executePricing(
                new List<PricingFrameworkOracleInvocable.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].isSuccess);
        System.assertNotEquals(null, results[0].pricingDataJson);
        Product2 part = [SELECT Id FROM Product2 WHERE ProductCode = 'PART-4585'];
        System.assert(
            results[0].pricingDataJson.contains(part.Id),
            'Headless JSON should include the Oracle-sourced product Id.'
        );
        System.assert(
            results[0].pricingDataJson.contains('OracleListPrice__c'),
            'Headless JSON should include Oracle List Price.'
        );
        System.assert(
            results[0].pricingDataJson.contains('OracleDiscountedPrice__c'),
            'Headless JSON should include Oracle Discounted Price.'
        );
    }

    @IsTest
    static void executePricing_oracleSource_persistsListAndDiscountedPrice() {
        Account account = insertAccount();
        Id pricebookId = Test.getStandardPricebookId();
        Product2 product = new Product2(
            Name = 'GW4585 Persist Part',
            ProductCode = 'PART-PERSIST-4585',
            PricingSource__c = 'Oracle',
            IsActive = true
        );
        insert product;
        PricebookEntry entry = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = product.Id,
            UnitPrice = 0,
            IsActive = true
        );
        insert entry;
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Pricebook2Id = pricebookId,
            Subject = 'GW4585 Persist Oracle Prices'
        );
        insert workOrder;
        WorkOrderLineItem lineItem = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            PricebookEntryId = entry.Id,
            Quantity = 1
        );
        insert lineItem;

        OraclePricingResponse oracleResponse = new OraclePricingResponse();
        oracleResponse.messageKey = OraclePricingResponse.MESSAGE_KEY_SUCCESS;
        oracleResponse.errorCode = '0';
        OraclePricingResponse.PriceInfo info = new OraclePricingResponse.PriceInfo();
        info.productPartNumber = 'PART-PERSIST-4585';
        info.messageKey = OraclePricingResponse.MESSAGE_KEY_SUCCESS;
        info.errorCode = '0';
        info.listPrice = 9542.87;
        info.price = 8445.02;
        oracleResponse.priceInfo = new List<OraclePricingResponse.PriceInfo>{ info };
        PricingFrameworkService.testOracleResponse = oracleResponse;

        PricingFrameworkOracleInvocable.Request request =
            new PricingFrameworkOracleInvocable.Request();
        request.accountId = account.Id;
        request.workstream = 'RepairCenter';
        request.recordId = workOrder.Id;
        request.pricingLineJson =
            '[{"lineId":"' + lineItem.Id + '","productCode":"PART-PERSIST-4585","quantity":1}]';

        Test.startTest();
        List<PricingFrameworkOracleInvocable.Result> results =
            PricingFrameworkOracleInvocable.executePricing(
                new List<PricingFrameworkOracleInvocable.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].isSuccess);
        WorkOrderLineItem updated = [
            SELECT OracleListPrice__c, OracleDiscountedPrice__c, UnitPrice
            FROM WorkOrderLineItem
            WHERE Id = :lineItem.Id
        ];
        System.assertEquals(
            9542.87,
            updated.OracleListPrice__c,
            'Oracle List Price should be written to the Work Order Line Item.'
        );
        System.assertEquals(
            8445.02,
            updated.OracleDiscountedPrice__c,
            'Oracle Discounted Price should be written to the Work Order Line Item.'
        );
        System.assertEquals(
            8445.02,
            updated.UnitPrice,
            'Unit Price should equal Oracle Discounted Price from the Apex call.'
        );
    }

    @IsTest
    static void executePricing_serviceSales_usesQuoteObject() {
        String json = PricingFrameworkService.toPricingDataJson(
            'ServiceSales',
            new List<PricingFrameworkOracleInvocable.PricingLine>()
        );
        System.assert(
            json.contains('"businessObjectType":"Quote"'),
            'Service Sales Headless JSON should use Quote as the business object type.'
        );
    }

    @IsTest
    static void executePricing_serviceSales_emitsQuoteLineGraph() {
        Account account = insertAccount();
        insert new Product2(
            Name = 'GW4585 Quote Labor',
            ProductCode = 'QTE-4585',
            PricingSource__c = 'Salesforce',
            IsActive = true
        );

        PricingFrameworkOracleInvocable.Request request =
            new PricingFrameworkOracleInvocable.Request();
        request.accountId = account.Id;
        request.workstream = 'ServiceSales';
        request.pricingLineJson =
            '[{"lineId":"' + UserInfo.getUserId() + '","productCode":"QTE-4585","quantity":1}]';

        Test.startTest();
        List<PricingFrameworkOracleInvocable.Result> results =
            PricingFrameworkOracleInvocable.executePricing(
                new List<PricingFrameworkOracleInvocable.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].isSuccess);
        System.assert(
            results[0].pricingDataJson.contains('QuoteLineItem'),
            'Service Sales Headless JSON should include QuoteLineItem nodes.'
        );
        Product2 product = [SELECT Id FROM Product2 WHERE ProductCode = 'QTE-4585'];
        System.assert(
            results[0].pricingDataJson.contains(product.Id),
            'Service Sales Headless JSON should include the product Id.'
        );
    }

    @IsTest
    static void executePricing_workOrderLine_usesRecordHeader() {
        Account account = insertAccount();
        Id pricebookId = Test.getStandardPricebookId();
        Product2 product = new Product2(
            Name = 'GW4585 WO Labor',
            ProductCode = 'WOL-4585',
            PricingSource__c = 'Salesforce',
            IsActive = true
        );
        insert product;
        PricebookEntry entry = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = product.Id,
            UnitPrice = 25,
            IsActive = true
        );
        insert entry;
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Pricebook2Id = pricebookId,
            Subject = 'GW4585 Headless WO'
        );
        insert workOrder;
        WorkOrderLineItem lineItem = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            PricebookEntryId = entry.Id,
            Quantity = 2
        );
        insert lineItem;

        PricingFrameworkOracleInvocable.Request request =
            new PricingFrameworkOracleInvocable.Request();
        request.accountId = account.Id;
        request.workstream = 'RepairCenter';
        request.pricingLineJson =
            '[{"lineId":"' + lineItem.Id + '","productCode":"WOL-4585","quantity":2}]';

        Test.startTest();
        List<PricingFrameworkOracleInvocable.Result> results =
            PricingFrameworkOracleInvocable.executePricing(
                new List<PricingFrameworkOracleInvocable.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].isSuccess);
        System.assert(
            results[0].pricingDataJson.contains(workOrder.Id),
            'Headless JSON should include the Work Order Id.'
        );
        System.assert(
            results[0].pricingDataJson.contains(lineItem.Id),
            'Headless JSON should include the Work Order Line Item Id as SalesTransactionItemSource.'
        );
        System.assert(
            results[0].pricingDataJson.contains(pricebookId),
            'Headless JSON should include the Work Order pricebook.'
        );
    }

    @IsTest
    static void executePricing_headlessGraph_hydratesWorkOrderLine() {
        Account account = insertAccount();
        Id pricebookId = Test.getStandardPricebookId();
        Product2 product = new Product2(
            Name = 'GW4585 Graph Labor',
            ProductCode = 'GRAPH-4585',
            PricingSource__c = 'Salesforce',
            IsActive = true
        );
        insert product;
        PricebookEntry entry = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = product.Id,
            UnitPrice = 25,
            IsActive = true
        );
        insert entry;
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Pricebook2Id = pricebookId,
            Subject = 'GW4585 Headless Graph WO'
        );
        insert workOrder;
        WorkOrderLineItem lineItem = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            PricebookEntryId = entry.Id,
            Quantity = 3
        );
        insert lineItem;

        PricingFrameworkOracleInvocable.Request request =
            new PricingFrameworkOracleInvocable.Request();
        request.accountId = account.Id;
        request.workstream = 'RepairCenter';
        request.recordId = workOrder.Id;
        request.pricingLineJson =
            '{"WorkOrder":[{"id":"' + workOrder.Id
            + '","businessObjectType":"WorkOrder","WorkOrderLineItem":[{"id":"'
            + lineItem.Id + '","businessObjectType":"WorkOrderLineItem"}]}]}';

        Test.startTest();
        List<PricingFrameworkOracleInvocable.Result> results =
            PricingFrameworkOracleInvocable.executePricing(
                new List<PricingFrameworkOracleInvocable.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].isSuccess);
        System.assert(
            results[0].pricingDataJson.contains(lineItem.Id),
            'Headless Work Order graph should hydrate the Work Order Line Item Id.'
        );
        System.assert(
            results[0].pricingDataJson.contains(product.Id),
            'Headless Work Order graph should hydrate the product Id.'
        );
        System.assert(
            results[0].pricingDataJson.contains('['),
            'Headless JSON should emit the Work Order header as an array.'
        );
    }

    @IsTest
    static void executePricing_quoteRecordId_invokesQuoteLineSelector() {
        Account account = insertAccount();
        Id fakeQuoteId = (Id) (
            String.valueOf(Quote.SObjectType.getDescribe().getKeyPrefix()) + '000000000AAA'
        );

        PricingFrameworkOracleInvocable.Request request =
            new PricingFrameworkOracleInvocable.Request();
        request.accountId = account.Id;
        request.workstream = 'ServiceSales';
        request.recordId = fakeQuoteId;

        Test.startTest();
        List<PricingFrameworkOracleInvocable.Result> results =
            PricingFrameworkOracleInvocable.executePricing(
                new List<PricingFrameworkOracleInvocable.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess);
        System.assertEquals('Pricing lines are required.', results[0].errorMessage);
    }

    @IsTest
    static void parseLines_supportsNestedWorkOrderGraph() {
        Set<Id> headerIds = new Set<Id>();
        Test.startTest();
        List<PricingFrameworkOracleInvocable.PricingLine> lines =
            PricingFrameworkService.parseLines(
                '{"WorkOrder":{"id":"' + UserInfo.getUserId()
                    + '","businessObjectType":"WorkOrder","WorkOrderLineItem":[{"lineId":"1","productCode":"A","quantity":2}]}}',
                headerIds
            );
        Test.stopTest();
        System.assertEquals(1, lines.size());
        System.assertEquals('A', lines[0].productCode);
        System.assertEquals(2, lines[0].quantity);
    }

    @IsTest
    static void executePricing_billToAccountMissing_returnsError() {
        Account account = insertAccount();
        insert new Product2(
            Name = 'GW4585 Bill To Missing',
            ProductCode = 'BILL-MISS',
            PricingSource__c = 'Oracle',
            IsActive = true
        );

        PricingFrameworkOracleInvocable.Request request =
            new PricingFrameworkOracleInvocable.Request();
        request.accountId = account.Id;
        request.billToAccountId = UserInfo.getUserId();
        request.workstream = 'RepairCenter';
        request.pricingLineJson =
            '[{"lineId":"1","productCode":"BILL-MISS","quantity":1}]';

        Test.startTest();
        List<PricingFrameworkOracleInvocable.Result> results =
            PricingFrameworkOracleInvocable.executePricing(
                new List<PricingFrameworkOracleInvocable.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess);
        System.assertEquals(
            'Bill To Account was not found.',
            results[0].errorMessage
        );
    }

    @IsTest
    static void executePricing_hydratesPricingSourceFromProduct() {
        Account account = insertAccount();
        insert new Product2(
            Name = 'GW4585 Hydrate Source',
            ProductCode = 'HYD-SRC',
            PricingSource__c = 'Oracle',
            IsActive = true
        );

        PricingFrameworkOracleInvocable.Request request =
            new PricingFrameworkOracleInvocable.Request();
        request.accountId = account.Id;
        request.workstream = 'RepairCenter';
        request.pricingLineJson = '[{"lineId":"1","productCode":"HYD-SRC","quantity":1}]';

        Test.startTest();
        List<PricingFrameworkOracleInvocable.Result> results =
            PricingFrameworkOracleInvocable.executePricing(
                new List<PricingFrameworkOracleInvocable.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].isSuccess);
        System.assertNotEquals(null, results[0].pricingDataJson);
        System.assert(
            results[0].pricingDataJson.contains('HYD-SRC'),
            'Pricing source should be resolved from Product2 when omitted on the line.'
        );
    }

    @IsTest
    static void executePricing_recordId_loadsWorkOrderLines() {
        Account account = insertAccount();
        Id pricebookId = Test.getStandardPricebookId();
        Product2 product = new Product2(
            Name = 'GW4585 Record Labor',
            ProductCode = 'REC-4585',
            PricingSource__c = 'Salesforce',
            IsActive = true
        );
        insert product;
        PricebookEntry entry = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = product.Id,
            UnitPrice = 25,
            IsActive = true
        );
        insert entry;
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Pricebook2Id = pricebookId,
            Subject = 'GW4585 Record WO'
        );
        insert workOrder;
        WorkOrderLineItem lineItem = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            PricebookEntryId = entry.Id,
            Quantity = 1
        );
        insert lineItem;

        PricingFrameworkOracleInvocable.Request request =
            new PricingFrameworkOracleInvocable.Request();
        request.accountId = account.Id;
        request.workstream = 'RepairCenter';
        request.recordId = workOrder.Id;

        Test.startTest();
        List<PricingFrameworkOracleInvocable.Result> results =
            PricingFrameworkOracleInvocable.executePricing(
                new List<PricingFrameworkOracleInvocable.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].isSuccess);
        System.assert(
            results[0].pricingDataJson.contains(lineItem.Id),
            'Record Id should load Work Order Line Items when line JSON is blank.'
        );
    }

    @IsTest
    static void executePricing_noLines_returnsError() {
        Account account = insertAccount();
        PricingFrameworkOracleInvocable.Request request =
            new PricingFrameworkOracleInvocable.Request();
        request.accountId = account.Id;
        request.workstream = 'RepairCenter';

        Test.startTest();
        List<PricingFrameworkOracleInvocable.Result> results =
            PricingFrameworkOracleInvocable.executePricing(
                new List<PricingFrameworkOracleInvocable.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess);
        System.assertEquals('Pricing lines are required.', results[0].errorMessage);
    }

    @IsTest
    static void buildOracleRequest_usesGenericPricingCallFields() {
        Account shipTo = insertAccount('4585001', '82');
        Account billTo = insertAccount('62694', '82');
        PricingFrameworkOracleInvocable.PricingLine line =
            new PricingFrameworkOracleInvocable.PricingLine();
        line.productCode = '10008301';
        line.quantity = 1;

        Test.startTest();
        OraclePricingRequest request = PricingFrameworkService.buildOracleRequest(
            shipTo,
            billTo,
            new List<PricingFrameworkOracleInvocable.PricingLine>{ line }
        );
        String payload = request.toJsonString();
        Test.stopTest();

        System.assertEquals('STERIS US', request.operatingUnitName);
        System.assertEquals('4585001', request.shipToCustomerNumber);
        System.assertEquals('62694', request.billToCustomerNumber);
        System.assertEquals('ST_ACCOUNT', request.genericPriceListLevel);
        System.assertEquals('BT_ACCOUNT', request.genericDiscountAccount);
        System.assert(
            payload.contains('"P_OU_NAME":"STERIS US"'),
            'Generic pricing call should send the operating unit name.'
        );
        System.assert(
            payload.contains('"P_ST_ACCT_NUM":"4585001"'),
            'Generic pricing call should send the ship-to account number.'
        );
        System.assert(
            payload.contains('"P_BT_ACCT_NUM":"62694"'),
            'Generic pricing call should send the bill-to account number.'
        );
        System.assert(
            payload.contains('"P_PRICE_LIST_LEVEL":"ST_ACCOUNT"'),
            'Service pricing should use ST_ACCOUNT as the price list level.'
        );
        System.assert(
            payload.contains('"P_DISCOUNT_ACCOUNT":"BT_ACCOUNT"'),
            'Service pricing should use BT_ACCOUNT as the discount account.'
        );
        System.assert(
            payload.contains('"PARTNUMBER":"10008301"'),
            'Generic pricing call should include the part number.'
        );
    }

    @IsTest
    static void executePricing_missingOperatingUnit_returnsError() {
        Account account = insertAccount('4585099', null);
        insert new Product2(
            Name = 'GW4585 Part No OU',
            ProductCode = 'PART-NO-OU',
            PricingSource__c = 'Oracle',
            IsActive = true
        );

        PricingFrameworkOracleInvocable.Request request =
            new PricingFrameworkOracleInvocable.Request();
        request.accountId = account.Id;
        request.workstream = 'RepairCenter';
        request.pricingLineJson =
            '[{"lineId":"woli-1","productCode":"PART-NO-OU","quantity":1}]';

        Test.startTest();
        List<PricingFrameworkOracleInvocable.Result> results =
            PricingFrameworkOracleInvocable.executePricing(
                new List<PricingFrameworkOracleInvocable.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess);
        System.assertEquals(
            'Account Org ID is required for Oracle pricing.',
            results[0].errorMessage
        );
    }

    @IsTest
    static void applyWorkOrderAccountOverrides_usesShipToAddressAccount() {
        Account customer = insertAccount('1001', '82');
        Account shipTo = insertAddressAccount(customer.Id, '39675', '82');
        WorkOrder workOrder = new WorkOrder(
            AccountId = customer.Id,
            ShipToAddressAccount__c = shipTo.Id,
            Subject = 'GW4585 Ship-To Override'
        );
        insert workOrder;

        PricingFrameworkOracleInvocable.Request request =
            new PricingFrameworkOracleInvocable.Request();
        request.accountId = customer.Id;
        request.recordId = workOrder.Id;

        Test.startTest();
        PricingFrameworkService.applyWorkOrderAccountOverrides(request);
        Test.stopTest();

        System.assertEquals(
            shipTo.Id,
            request.accountId,
            'Work Order Ship-to Address Account should be used as the Oracle ship-to.'
        );
    }

    @IsTest
    static void preferOracleAddressAccount_usesPrimaryChildAddress() {
        Account customer = insertAccount('1001', '82');
        Account shipTo = insertAddressAccount(customer.Id, '39675', '82');

        Test.startTest();
        Account resolved = PricingFrameworkService.preferOracleAddressAccount(
            [
                SELECT Id,
                    AccountNumber,
                    OrgIDs__c,
                    OracleAddressId__c,
                    Type,
                    RecordType.DeveloperName,
                    Price_List__c,
                    Price_List__r.Price_List_ID__c,
                    Parent.OrgIDs__c,
                    Parent.AccountNumber
                FROM Account
                WHERE Id = :customer.Id
            ]
        );
        Test.stopTest();

        System.assertEquals(
            shipTo.Id,
            resolved.Id,
            'Customer accounts without an Oracle address should resolve to the primary Address child.'
        );
        System.assertEquals('39675', resolved.AccountNumber);
    }

    @IsTest
    static void executePricing_oracleHeaderError_stillReturnsHeadlessJson() {
        Account account = insertAccount('1001', '82');
        insert new Product2(
            Name = 'GW4585 Invalid Ship-To Part',
            ProductCode = 'PART-104',
            PricingSource__c = 'Oracle',
            IsActive = true
        );

        OraclePricingResponse oracleResponse = new OraclePricingResponse();
        oracleResponse.errorCode = '104';
        oracleResponse.messageKey = 'SHIPTO_ACCT_NUM_INVALID';
        PricingFrameworkService.testOracleResponse = oracleResponse;

        PricingFrameworkOracleInvocable.Request request =
            new PricingFrameworkOracleInvocable.Request();
        request.accountId = account.Id;
        request.workstream = 'RepairCenter';
        request.pricingLineJson =
            '[{"lineId":"woli-104","productCode":"PART-104","quantity":1}]';

        Test.startTest();
        List<PricingFrameworkOracleInvocable.Result> results =
            PricingFrameworkOracleInvocable.executePricing(
                new List<PricingFrameworkOracleInvocable.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess);
        System.assertNotEquals(null, results[0].pricingDataJson);
        System.assertEquals(
            'Ship to Account is inactive. (ORA104)',
            results[0].errorMessage,
            'Header error 104 should use the STE_PRICING_ERROR_DESC description.'
        );
        System.assert(
            results[0].pricingDataJson.contains('"WorkOrder"'),
            'Salesforce Headless JSON should still be returned after an Oracle ship-to rejection.'
        );
    }

    @IsTest
    static void executePricing_unknownHeaderError_keepsOracleMessage() {
        Account account = insertAccount('1001', '82');
        insert new Product2(
            Name = 'GW4585 Unknown Header Error',
            ProductCode = 'PART-999',
            PricingSource__c = 'Oracle',
            IsActive = true
        );

        OraclePricingResponse oracleResponse = new OraclePricingResponse();
        oracleResponse.errorCode = '999';
        oracleResponse.messageKey = 'SHIPTO_ACCT_NUM_INVALID';
        PricingFrameworkService.testOracleResponse = oracleResponse;

        PricingFrameworkOracleInvocable.Request request =
            new PricingFrameworkOracleInvocable.Request();
        request.accountId = account.Id;
        request.workstream = 'RepairCenter';
        request.pricingLineJson =
            '[{"lineId":"woli-999","productCode":"PART-999","quantity":1}]';

        Test.startTest();
        List<PricingFrameworkOracleInvocable.Result> results =
            PricingFrameworkOracleInvocable.executePricing(
                new List<PricingFrameworkOracleInvocable.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess);
        System.assert(
            results[0].errorMessage.contains('1001'),
            'Unmapped errors should include the rejected ship-to account number.'
        );
        System.assert(
            results[0].errorMessage.contains('SHIPTO_ACCT_NUM_INVALID'),
            'Unmapped errors should keep the Oracle message key.'
        );
    }

    @IsTest
    static void executePricing_lineError_usesPricingErrorDescription() {
        Account account = insertAccount('1001', '82');
        insert new Product2(
            Name = 'GW4585 Missing Pricelist Part',
            ProductCode = 'PART-705',
            PricingSource__c = 'Oracle',
            IsActive = true
        );

        OraclePricingResponse oracleResponse = new OraclePricingResponse();
        oracleResponse.messageKey = OraclePricingResponse.MESSAGE_KEY_SUCCESS;
        oracleResponse.errorCode = '0';
        OraclePricingResponse.PriceInfo info = new OraclePricingResponse.PriceInfo();
        info.productPartNumber = 'PART-705';
        info.messageKey = 'Item_Notin_Pricelist';
        info.errorCode = '705';
        oracleResponse.priceInfo = new List<OraclePricingResponse.PriceInfo>{ info };
        PricingFrameworkService.testOracleResponse = oracleResponse;

        PricingFrameworkOracleInvocable.Request request =
            new PricingFrameworkOracleInvocable.Request();
        request.accountId = account.Id;
        request.workstream = 'RepairCenter';
        request.pricingLineJson =
            '[{"lineId":"woli-705","productCode":"PART-705","quantity":1}]';

        Test.startTest();
        List<PricingFrameworkOracleInvocable.Result> results =
            PricingFrameworkOracleInvocable.executePricing(
                new List<PricingFrameworkOracleInvocable.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess);
        System.assertEquals(
            'Part is not found on the existing pricelist in Oracle. (ORA705) PART-705',
            results[0].errorMessage
        );
    }

    @IsTest
    static void pricingErrorDescription_mapsOraPrefix() {
        System.assertEquals(
            'Mandatory parameters are not provided. (ORA101)',
            PricingFrameworkService.pricingErrorDescription('ORA101')
        );
        System.assertEquals(
            null,
            PricingFrameworkService.pricingErrorDescription('999')
        );
    }

    @IsTest
    static void executePricing_usesLineProductPricingSource_whenDuplicateProductCodes() {
        Account account = insertAccount();
        Id pricebookId = Test.getStandardPricebookId();
        Product2 oracleProduct = new Product2(
            Name = 'GW4585 Oracle Duplicate Code',
            ProductCode = 'SC.ANG-DUP',
            PricingSource__c = 'Oracle',
            IsActive = true
        );
        insert oracleProduct;
        insert new Product2(
            Name = 'GW4585 Salesforce Duplicate Code',
            ProductCode = 'SC.ANG-DUP',
            PricingSource__c = 'Salesforce',
            IsActive = true
        );
        PricebookEntry entry = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = oracleProduct.Id,
            UnitPrice = 0,
            IsActive = true
        );
        insert entry;
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Pricebook2Id = pricebookId,
            Subject = 'GW4585 Duplicate Product Code'
        );
        insert workOrder;
        WorkOrderLineItem lineItem = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            PricebookEntryId = entry.Id,
            Quantity = 1
        );
        insert lineItem;

        OraclePricingResponse oracleResponse = new OraclePricingResponse();
        oracleResponse.messageKey = OraclePricingResponse.MESSAGE_KEY_SUCCESS;
        oracleResponse.errorCode = '0';
        OraclePricingResponse.PriceInfo info = new OraclePricingResponse.PriceInfo();
        info.productPartNumber = 'SC.ANG-DUP';
        info.messageKey = OraclePricingResponse.MESSAGE_KEY_SUCCESS;
        info.errorCode = '0';
        info.listPrice = 125.50;
        info.price = 125.50;
        oracleResponse.priceInfo = new List<OraclePricingResponse.PriceInfo>{ info };
        PricingFrameworkService.testOracleResponse = oracleResponse;

        PricingFrameworkOracleInvocable.Request request =
            new PricingFrameworkOracleInvocable.Request();
        request.accountId = account.Id;
        request.workstream = 'RepairCenter';
        request.recordId = workOrder.Id;

        Test.startTest();
        List<PricingFrameworkOracleInvocable.Result> results =
            PricingFrameworkOracleInvocable.executePricing(
                new List<PricingFrameworkOracleInvocable.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].isSuccess);
        WorkOrderLineItem updated = [
            SELECT OracleListPrice__c, OracleDiscountedPrice__c, UnitPrice
            FROM WorkOrderLineItem
            WHERE Id = :lineItem.Id
        ];
        System.assertEquals(
            125.50,
            updated.OracleListPrice__c,
            'Should price the WOLI Product2 even when another Product2 shares the code.'
        );
        System.assertEquals(125.50, updated.OracleDiscountedPrice__c);
        System.assertEquals(125.50, updated.UnitPrice);
    }

    private static Account insertAccount() {
        return insertAccount('4585001', '82');
    }

    private static Account insertAccount(String accountNumber, String orgId) {
        Account account = new Account(
            Name = 'GW4585 Pricing Account ' + accountNumber,
            SourceSystemID__c = 'ORACLE-GW4585-' + accountNumber + '-' + String.valueOf(Crypto.getRandomInteger()),
            AccountNumber = accountNumber,
            OrgIDs__c = orgId
        );
        insert account;
        return account;
    }

    private static Account insertAddressAccount(Id parentId, String accountNumber, String orgId) {
        Account addressAccount = new Account(
            Name = 'GW4585 Pricing Address ' + accountNumber,
            ParentId = parentId,
            Type = 'Address',
            SourceSystemID__c = 'ORACLE-GW4585-ADDR-' + accountNumber + '-' + String.valueOf(Crypto.getRandomInteger()),
            AccountNumber = accountNumber,
            OrgIDs__c = orgId,
            OracleAddressId__c = 'SITE-' + accountNumber,
            ShiptoAddressStatus__c = 'Primary'
        );
        insert addressAccount;
        return addressAccount;
    }
}