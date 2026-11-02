/**
 * @description Test class for ProductRequestsService.
 *              Covers create, update, delete, retrieval, and GW-514 Oracle submit
 *              across positive, negative, bulk, and empty-input scenarios.
 */
@IsTest
private class ProductRequestsServiceTest {

    @TestSetup
    static void setupTestData() {
        // Build and persist 251 ProductRequests for bulk coverage
        List<ProductRequest> productRequestList = new List<ProductRequest>();
        for (Integer i = 0; i < 251; i++) {
            productRequestList.add((ProductRequest) new adb_ProductRequest().record);
        }
        insert productRequestList;
    }

    // ── createProductRequests ─────────────────────────────────────────────────

    @IsTest
    static void shouldCreateProductRequests_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            ProductRequest pr1 = (ProductRequest) new adb_ProductRequest().record;
            ProductRequest pr2 = (ProductRequest) new adb_ProductRequest().record;
            ProductRequest pr3 = (ProductRequest) new adb_ProductRequest().record;
            List<ProductRequest> productRequestList = new List<ProductRequest>{ pr1, pr2, pr3 };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductRequestsService.createProductRequests(productRequestList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> insertedIdSet = new Map<Id, ProductRequest>(productRequestList).keySet();
            Integer insertedCount = [SELECT COUNT() FROM ProductRequest WHERE Id IN :insertedIdSet];
            Assert.areEqual(3, insertedCount, 'createProductRequests should insert all 3 ProductRequests');
        }
    }

    @IsTest
    static void shouldCreateProductRequests_WhenBulk251RecordsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN — delete setup records so count assertion is isolated
             ********************************************/
            delete [SELECT Id FROM ProductRequest];

            List<ProductRequest> productRequestList = new List<ProductRequest>();
            for (Integer i = 0; i < 251; i++) {
                productRequestList.add((ProductRequest) new adb_ProductRequest().record);
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductRequestsService.createProductRequests(productRequestList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer insertedCount = [SELECT COUNT() FROM ProductRequest];
            Assert.areEqual(251, insertedCount, 'createProductRequests should bulk-insert all 251 ProductRequests');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenCreateProductRequestsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM ProductRequest];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductRequestsService.createProductRequests(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM ProductRequest];
            Assert.areEqual(countBefore, countAfter, 'createProductRequests with null should not insert any records');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenCreateProductRequestsCalledWithEmptyList() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM ProductRequest];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductRequestsService.createProductRequests(new List<ProductRequest>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM ProductRequest];
            Assert.areEqual(countBefore, countAfter, 'createProductRequests with an empty list should not insert any records');
        }
    }

    // ── updateProductRequests ─────────────────────────────────────────────────

    @IsTest
    static void shouldUpdateProductRequests_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<ProductRequest> productRequestList = [SELECT Id, Description FROM ProductRequest LIMIT 5];
            for (ProductRequest productRequest : productRequestList) {
                productRequest.Description = 'Updated Description';
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductRequestsService.updateProductRequests(productRequestList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> updatedIdSet = new Map<Id, ProductRequest>(productRequestList).keySet();
            List<ProductRequest> updatedList = [SELECT Id, Description FROM ProductRequest WHERE Id IN :updatedIdSet];
            Assert.areEqual(5, updatedList.size(), 'updateProductRequests should update all 5 ProductRequests');
            for (ProductRequest productRequest : updatedList) {
                Assert.areEqual('Updated Description', productRequest.Description, 'Each updated ProductRequest should have the new Description');
            }
        }
    }

    @IsTest
    static void shouldUpdateProductRequests_WhenBulk251RecordsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<ProductRequest> productRequestList = [SELECT Id, Description FROM ProductRequest];
            Assert.areEqual(251, productRequestList.size(), 'Test setup should have inserted 251 ProductRequests');
            for (ProductRequest productRequest : productRequestList) {
                productRequest.Description = 'Bulk Updated';
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductRequestsService.updateProductRequests(productRequestList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> updatedIdSet = new Map<Id, ProductRequest>(productRequestList).keySet();
            List<ProductRequest> updatedList = [SELECT Id, Description FROM ProductRequest WHERE Id IN :updatedIdSet];
            Assert.areEqual(251, updatedList.size(), 'All 251 ProductRequests should be returned after bulk update');
            for (ProductRequest productRequest : updatedList) {
                Assert.areEqual('Bulk Updated', productRequest.Description, 'Each ProductRequest should have Description = Bulk Updated');
            }
        }
    }

    @IsTest
    static void shouldDoNothing_WhenUpdateProductRequestsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductRequestsService.updateProductRequests(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(true, 'updateProductRequests with null should complete without error');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenUpdateProductRequestsCalledWithEmptyList() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductRequestsService.updateProductRequests(new List<ProductRequest>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(true, 'updateProductRequests with an empty list should complete without error');
        }
    }

    // ── deleteProductRequests ─────────────────────────────────────────────────

    @IsTest
    static void shouldDeleteProductRequests_WhenValidIdsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<ProductRequest> productRequestList = new List<ProductRequest>();
            for (Integer i = 0; i < 5; i++) {
                productRequestList.add((ProductRequest) new adb_ProductRequest().record);
            }
            insert productRequestList;
            Set<Id> productRequestIdSet = new Map<Id, ProductRequest>(productRequestList).keySet();
            Assert.areEqual(5, productRequestIdSet.size(), 'Should have 5 ProductRequest Ids to delete');

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductRequestsService.deleteProductRequests(productRequestIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer remainingCount = [SELECT COUNT() FROM ProductRequest WHERE Id IN :productRequestIdSet];
            Assert.areEqual(0, remainingCount, 'deleteProductRequests should delete all 5 ProductRequests with the given Ids');
        }
    }

    @IsTest
    static void shouldDeleteProductRequests_WhenBulk251IdsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            delete [SELECT Id FROM ProductRequest];
            List<ProductRequest> productRequestList = new List<ProductRequest>();
            for (Integer i = 0; i < 251; i++) {
                productRequestList.add((ProductRequest) new adb_ProductRequest().record);
            }
            insert productRequestList;
            Set<Id> productRequestIdSet = new Map<Id, ProductRequest>(productRequestList).keySet();
            Assert.areEqual(251, productRequestIdSet.size(), 'Should have inserted 251 ProductRequests to delete');

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductRequestsService.deleteProductRequests(productRequestIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer remainingCount = [SELECT COUNT() FROM ProductRequest];
            Assert.areEqual(0, remainingCount, 'deleteProductRequests should delete all 251 ProductRequests');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenDeleteProductRequestsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM ProductRequest];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductRequestsService.deleteProductRequests(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM ProductRequest];
            Assert.areEqual(countBefore, countAfter, 'deleteProductRequests with null should not delete any records');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenDeleteProductRequestsCalledWithEmptySet() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM ProductRequest];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductRequestsService.deleteProductRequests(new Set<Id>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM ProductRequest];
            Assert.areEqual(countBefore, countAfter, 'deleteProductRequests with an empty Set should not delete any records');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenDeleteProductRequestsCalledWithNonExistentIds() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<ProductRequest> existingList = new List<ProductRequest>();
            for (Integer i = 0; i < 3; i++) {
                existingList.add((ProductRequest) new adb_ProductRequest().record);
            }
            insert existingList;
            Integer countBefore = [SELECT COUNT() FROM ProductRequest];
            Set<Id> nonExistentIdSet = new Set<Id>{ '0PR000000000001AAA' };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ProductRequestsService.deleteProductRequests(nonExistentIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM ProductRequest];
            Assert.areEqual(countBefore, countAfter, 'deleteProductRequests with non-existent Ids should not delete any records');
        }
    }

    // ── getProductRequestsById ────────────────────────────────────────────────

    @IsTest
    static void shouldReturnProductRequests_WhenGetByIdCalledWithValidIds() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            delete [SELECT Id FROM ProductRequest];
            List<ProductRequest> productRequestList = new List<ProductRequest>();
            for (Integer i = 0; i < 251; i++) {
                productRequestList.add((ProductRequest) new adb_ProductRequest().record);
            }
            insert productRequestList;
            Set<Id> productRequestIdSet = new Map<Id, ProductRequest>(productRequestList).keySet();
            Assert.areEqual(251, productRequestIdSet.size(), 'Should have inserted 251 ProductRequests for retrieval');

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<ProductRequest> resultList = ProductRequestsService.getProductRequestsById(productRequestIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(251, resultList.size(), 'getProductRequestsById should return all 251 ProductRequests matching the given Ids');
        }
    }

    @IsTest
    static void shouldReturnEmpty_WhenGetByIdCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<ProductRequest> resultList = ProductRequestsService.getProductRequestsById(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getProductRequestsById with null should return an empty list');
        }
    }

    @IsTest
    static void shouldReturnEmpty_WhenGetByIdCalledWithEmptySet() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<ProductRequest> resultList = ProductRequestsService.getProductRequestsById(new Set<Id>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getProductRequestsById with an empty Set should return an empty list');
        }
    }

    // ── getProductRequestsWithLineItems ───────────────────────────────────────

    @IsTest
    static void shouldReturnEmpty_WhenGetWithLineItemsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<ProductRequest> resultList = ProductRequestsService.getProductRequestsWithLineItems(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getProductRequestsWithLineItems with null should return an empty list');
        }
    }

    @IsTest
    static void shouldReturnEmpty_WhenGetWithLineItemsCalledWithEmptySet() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<ProductRequest> resultList = ProductRequestsService.getProductRequestsWithLineItems(new Set<Id>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getProductRequestsWithLineItems with an empty Set should return an empty list');
        }
    }

    // ── GW-514 submitOracleSalesOrder ─────────────────────────────────────────

    @IsTest
    static void shouldBuildOracleJson_WhenSrOracleAccountIdAndDescriptionPresent() {
        Account acct = createOracleTechAccount('4269123', 'TEST-ORACLE-4269123');
        insert acct;

        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'prorcl',
            Email = 'pr.oracle.test@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'OracleTest',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/New_York',
            UserName = 'pr.oracle.test.' + System.currentTimeMillis() + '@example.com'
        );
        insert u;

        ServiceResource sr = new ServiceResource(
            Name = 'PR Oracle SR',
            RelatedRecordId = u.Id,
            IsActive = true,
            ResourceType = 'T',
            AccountId = acct.Id,
            OracleAccountId__c = '3370699',
            Description = '4269123'
        );
        insert sr;

        Product2 prod = new Product2(Name = 'Test Part', ProductCode = 'P755718521', IsActive = true);
        insert prod;

        ProductRequest pr;
        System.runAs(u) {
            pr = new ProductRequest(
                Status = 'Draft',
                NeedByDate = Datetime.newInstance(2026, 5, 8, 12, 0, 0),
                AccountId = acct.Id,
                ServiceResource__c = sr.Id
            );
            insert pr;

            insert new ProductRequestLineItem(
                ParentId = pr.Id,
                Product2Id = prod.Id,
                QuantityRequested = 1,
                NeedByDate = Datetime.newInstance(2026, 5, 8, 12, 0, 0)
            );
        }

        ProductRequestsService.OracleSubmitRequest req = new ProductRequestsService.OracleSubmitRequest();
        req.productRequestId = pr.Id;
        req.performCallout = false;

        Test.startTest();
        List<ProductRequestsService.OracleSubmitResult> results = ProductRequestsService.submitOracleSalesOrder(
            new List<ProductRequestsService.OracleSubmitRequest>{ req }
        );
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.areEqual(true, results[0].success, results[0].integrationMessage);
        Assert.isNotNull(results[0].requestJson);
        // Sold-to / ship-to cust from SR.OracleAccountId__c; address ids from SR.Description
        Assert.isTrue(results[0].requestJson.contains('"P_SOLD_TO_ORG_ID":"3370699"'), results[0].requestJson);
        Assert.isTrue(results[0].requestJson.contains('"P_SHIP_TO_CUST_ID":"3370699"'), results[0].requestJson);
        Assert.isTrue(results[0].requestJson.contains('"P_SHIP_TO_ADDR_ID":"4269123"'), results[0].requestJson);
        Assert.isTrue(results[0].requestJson.contains('"P_INV_ADDR_ID":"4269123"'), results[0].requestJson);
        Assert.isTrue(results[0].requestJson.contains('"P_BILL_TO_ADDR":"4269123"'), results[0].requestJson);
        Assert.isTrue(results[0].requestJson.contains('"P_SHIP_TO_ADDR":"4269123"'), results[0].requestJson);
        Assert.isTrue(results[0].requestJson.contains('"P_PRODUCT_NAME":"P755718521"'), results[0].requestJson);
    }

    @IsTest
    static void shouldStampOracleSuccess_WhenCalloutPathRunsInTest() {
        Account acct = createOracleTechAccount('4269123', 'TEST-ORACLE-3370699');
        insert acct;

        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'prcall',
            Email = 'pr.oracle.callout@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'OracleCallout',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/New_York',
            UserName = 'pr.oracle.callout.' + System.currentTimeMillis() + '@example.com'
        );
        insert u;

        ServiceResource sr = new ServiceResource(
            Name = 'PR Oracle Callout SR',
            RelatedRecordId = u.Id,
            IsActive = true,
            ResourceType = 'T',
            AccountId = acct.Id,
            OracleAccountId__c = '3370699',
            Description = '4269123'
        );
        insert sr;

        Product2 prod = new Product2(Name = 'Callout Part', ProductCode = 'P117055344', IsActive = true);
        insert prod;

        ProductRequest pr;
        System.runAs(u) {
            pr = new ProductRequest(
                Status = 'Draft',
                NeedByDate = Datetime.now().addDays(3),
                AccountId = acct.Id,
                ServiceResource__c = sr.Id
            );
            insert pr;
            insert new ProductRequestLineItem(
                ParentId = pr.Id,
                Product2Id = prod.Id,
                QuantityRequested = 1,
                NeedByDate = Datetime.now().addDays(3)
            );
        }

        ProductRequestsService.OracleSubmitRequest req = new ProductRequestsService.OracleSubmitRequest();
        req.productRequestId = pr.Id;
        req.performCallout = true;

        Test.startTest();
        List<ProductRequestsService.OracleSubmitResult> results = ProductRequestsService.submitOracleSalesOrder(
            new List<ProductRequestsService.OracleSubmitRequest>{ req }
        );
        Test.stopTest();

        Assert.areEqual(true, results[0].success, results[0].integrationMessage);
        Assert.areEqual('Success', results[0].integrationStatus);
        Assert.areEqual('TEST-SO-001', results[0].erpOrderNumber);

        ProductRequest stamped = [
            SELECT SubmissionToERP__c, IntegrationStatus__c, ERPOrderNumber__c
            FROM ProductRequest
            WHERE Id = :pr.Id
        ];
        Assert.areEqual('Submitted', stamped.SubmissionToERP__c);
        Assert.areEqual('Success', stamped.IntegrationStatus__c);
        Assert.areEqual('TEST-SO-001', stamped.ERPOrderNumber__c);
    }

    @IsTest
    static void shouldFailOracleSubmit_WhenNoLineItems() {
        ProductRequest pr = new ProductRequest(Status = 'Draft');
        insert pr;

        ProductRequestsService.OracleSubmitRequest req = new ProductRequestsService.OracleSubmitRequest();
        req.productRequestId = pr.Id;
        req.performCallout = false;

        Test.startTest();
        List<ProductRequestsService.OracleSubmitResult> results = ProductRequestsService.submitOracleSalesOrder(
            new List<ProductRequestsService.OracleSubmitRequest>{ req }
        );
        Test.stopTest();

        Assert.areEqual(false, results[0].success);
        Assert.areEqual('Fail', results[0].integrationStatus);
        Assert.isTrue(results[0].integrationMessage.contains('No Product Request Line Items'));
    }

    @IsTest
    static void shouldStampOracleFail_WhenSoSuccessButOracleRetcodeError() {
        Account acct = createOracleTechAccount('4269123', 'TEST-ORACLE-FAIL-RET');
        insert acct;

        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'prfail',
            Email = 'pr.oracle.fail@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'OracleFail',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/New_York',
            UserName = 'pr.oracle.fail.' + System.currentTimeMillis() + '@example.com'
        );
        insert u;

        ServiceResource sr = new ServiceResource(
            Name = 'PR Oracle Fail SR',
            RelatedRecordId = u.Id,
            IsActive = true,
            ResourceType = 'T',
            AccountId = acct.Id,
            OracleAccountId__c = '3370699',
            Description = '4269123'
        );
        insert sr;

        Product2 prod = new Product2(Name = 'Fail Part', ProductCode = 'PFAIL0001', IsActive = true);
        insert prod;

        ProductRequest pr;
        System.runAs(u) {
            pr = new ProductRequest(
                Status = 'Draft',
                NeedByDate = Datetime.now().addDays(3),
                AccountId = acct.Id,
                ServiceResource__c = sr.Id
            );
            insert pr;
            insert new ProductRequestLineItem(
                ParentId = pr.Id,
                Product2Id = prod.Id,
                QuantityRequested = 1,
                NeedByDate = Datetime.now().addDays(3)
            );
        }

        ProductRequestsService.testOracleResponseOverride = new Map<String, Object>{
            'SO_SUCCESS' => true,
            'SERVICE_DATA' => new Map<String, Object>{
                'p_retcode' => 2,
                'p_errbuf' => 'Customer account not found in Oracle.',
                'p_Oracle_Order_Number' => null
            }
        };

        ProductRequestsService.OracleSubmitRequest req = new ProductRequestsService.OracleSubmitRequest();
        req.productRequestId = pr.Id;
        req.performCallout = true;

        Test.startTest();
        List<ProductRequestsService.OracleSubmitResult> results = ProductRequestsService.submitOracleSalesOrder(
            new List<ProductRequestsService.OracleSubmitRequest>{ req }
        );
        Test.stopTest();

        ProductRequestsService.testOracleResponseOverride = null;

        Assert.areEqual(false, results[0].success, results[0].integrationMessage);
        Assert.areEqual('Fail', results[0].integrationStatus);
        Assert.isTrue(
            results[0].integrationMessage.contains('Customer account not found'),
            results[0].integrationMessage
        );

        ProductRequest stamped = [
            SELECT IntegrationStatus__c, ERPOrderNumber__c, IntegrationMessage__c
            FROM ProductRequest
            WHERE Id = :pr.Id
        ];
        Assert.areEqual('Fail', stamped.IntegrationStatus__c);
        Assert.isNull(stamped.ERPOrderNumber__c);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static Account createOracleTechAccount(String systemId, String sourceSystemId) {
        return new Account(
            Name = 'PR Oracle Test Tech ' + systemId,
            SystemID__c = systemId,
            SourceSystemID__c = sourceSystemId
        );
    }

    private static User buildTestUser() {
        adb_User builder = new adb_User();
        builder.persist();
        return (User) builder.record;
    }
}