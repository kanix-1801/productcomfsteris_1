/**
 * @description Test class for ConnectCareRestService.
 */
@isTest
private class ConnectCareRestServiceTest {
    private static String getDisinfectedYesValueForTest() {
        for (Schema.PicklistEntry entry : ReturnOrderLineItem.Disinfected__c.getDescribe()
            .getPicklistValues()) {
            if (entry.isActive() && entry.getValue().toLowerCase().startsWith('yes')) {
                return entry.getValue();
            }
        }
        return 'Yes, Item is Disinfected';
    }

    @TestSetup
    static void setupTestData() {
        // Department__c has no adb_ builder, and the Asset below needs its Id, so it is
        // inserted first via plain DML.
        Department__c testDepartment = new Department__c(
            Name = 'ConnectCare Surgery'
        );
        insert testDepartment;

        adb_Account accountBuilder = new adb_Account()
            .name('ConnectCare REST Test Account')
            .accountNumber('CC-1001')
            .systemId('LEG-CC-1001')
            .sourceSystemId('TEST-ORACLE-CC-001')
            .orgIds('82');

        adb_Contact contactBuilder = new adb_Contact()
            .firstName('ConnectCare')
            .lastName('Requester')
            .account(accountBuilder);

        adb_Product2 testProductBuilder = new adb_Product2()
            .name('ConnectCare Test Product')
            .productType('Service Asset')
            .productLine('Surgical')
            .isActive(true);

        new adb_Product2()
            .name('Default Product')
            .productType('Service Asset')
            .productLine('INSTRUMENT')
            .isActive(true)
            .description('Default return order product');

        adb_Asset searchAssetBuilder = new adb_Asset()
            .name('ConnectCare Search Asset')
            .serialNumber('CC-SN-130456')
            .account(accountBuilder)
            .product(testProductBuilder);
        // adb_Asset has no departmentId() setter; Department__c is set directly via the
        // inherited, @TestVisible set() method.
        searchAssetBuilder.set(Asset.Department__c, testDepartment.Id);

        adb_DomainBuilder.save();

        insert new AccountDepartment__c(
            Account__c = accountBuilder.id,
            Department__c = testDepartment.Id
        );
    }

    @isTest
    static void testSearchAssets_success() {
        Account account = [SELECT Id FROM Account WHERE AccountNumber = 'CC-1001' LIMIT 1];

        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/connectcare/v1/assets';
        request.httpMethod = 'GET';
        request.addParameter('accountId', account.Id);
        request.addParameter('serialSearchTerm', '130');

        RestResponse response = new RestResponse();
        RestContext.request = request;
        RestContext.response = response;

        Test.startTest();
        ConnectCareRestService.searchAssets();
        Test.stopTest();

        System.assertEquals(
            200,
            response.statusCode,
            response.responseBody == null ? 'No response body' : response.responseBody.toString()
        );
        Map<String, Object> body = parseResponseBody(response);
        List<Object> assets = (List<Object>) body.get('assets');
        System.assertEquals(1, assets.size());
    }

    @isTest
    static void testSearchAssets_rejectsShortSerialTerm() {
        Account account = [SELECT Id FROM Account WHERE AccountNumber = 'CC-1001' LIMIT 1];

        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/connectcare/v1/assets';
        request.httpMethod = 'GET';
        request.addParameter('accountId', account.Id);
        request.addParameter('serialSearchTerm', '13');

        RestResponse response = new RestResponse();
        RestContext.request = request;
        RestContext.response = response;

        Test.startTest();
        ConnectCareRestService.searchAssets();
        Test.stopTest();

        System.assertEquals(400, response.statusCode);
        Map<String, Object> body = parseResponseBody(response);
        System.assertEquals(false, body.get('success'));
        System.assertEquals('VALIDATION_ERROR', body.get('errorCode'));
    }

    @isTest
    static void testCreateReturnOrders_success() {
        Account account = [SELECT Id FROM Account WHERE AccountNumber = 'CC-1001' LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Asset asset = [SELECT Id, Product2Id, SerialNumber FROM Asset LIMIT 1];
        Department__c department = [SELECT Id FROM Department__c LIMIT 1];

        Schema.Location repairCenter = new Schema.Location(
            Name = 'ConnectCare Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'Surgical',
            RepairCenter__c = repairCenter.Id
        );

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'header' => new Map<String, Object>{
                    'accountNumber' => 'CC-1001',
                    'operatingUnit' => '82',
                    'creationSource' => 'ConnectCare',
                    'connectCareRequestId' => 'cc-req-test-001'
                },
                'lines' => new List<Object>{
                    new Map<String, Object>{
                        'lineType' => 'serialized',
                        'serialized' => true,
                        'assetId' => asset.Id,
                        'product2Id' => asset.Product2Id,
                        'serialNumber' => asset.SerialNumber,
                        'model' => 'Test Model',
                        'productLine' => 'Surgical',
                        'departmentId' => department.Id,
                        'contactId' => contact.Id,
                        'disinfected' => getDisinfectedYesValueForTest(),
                        'reportedProblem' => 'Unit not powering on',
                        'estimateRequired' => 'Pre-Approved',
                        'repairWarranty' => 'No'
                    }
                }
            }
        );

        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/connectcare/v1/return-orders';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(requestBody);

        RestResponse response = new RestResponse();
        RestContext.request = request;
        RestContext.response = response;

        Test.startTest();
        ConnectCareRestService.createReturnOrders();
        Test.stopTest();

        System.assertEquals(200, response.statusCode);
        Map<String, Object> body = parseResponseBody(response);
        System.assertEquals(true, body.get('success'));
        System.assertEquals('cc-req-test-001', body.get('connectCareRequestId'));

        List<Object> returnOrders = (List<Object>) body.get('returnOrders');
        System.assertEquals(1, returnOrders.size());

        Map<String, Object> createdOrder = (Map<String, Object>) returnOrders[0];
        Id returnOrderId = (Id) createdOrder.get('returnOrderId');

        ReturnOrder returnOrder = [
            SELECT Id, CreationSource__c, DestinationLocationId
            FROM ReturnOrder
            WHERE Id = :returnOrderId
            LIMIT 1
        ];
        System.assertEquals('ConnectCare', returnOrder.CreationSource__c);
        System.assertEquals(repairCenter.Id, returnOrder.DestinationLocationId);
    }

    @isTest
    static void testCreateReturnOrders_validationError() {
        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'header' => new Map<String, Object>{
                    'accountNumber' => 'CC-1001',
                    'creationSource' => 'ConnectCare',
                    'connectCareRequestId' => 'cc-req-test-002'
                },
                'lines' => new List<Object>{
                    new Map<String, Object>{
                        'lineType' => 'serialized',
                        'assetId' => '02i000000000000AAA'
                    }
                }
            }
        );

        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/connectcare/v1/return-orders';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(requestBody);

        RestResponse response = new RestResponse();
        RestContext.request = request;
        RestContext.response = response;

        Test.startTest();
        ConnectCareRestService.createReturnOrders();
        Test.stopTest();

        System.assertEquals(400, response.statusCode);
        Map<String, Object> body = parseResponseBody(response);
        System.assertEquals(false, body.get('success'));
        System.assertEquals('VALIDATION_ERROR', body.get('errorCode'));
    }

    @isTest
    static void testCreateReturnOrders_routingError() {
        Account account = [SELECT Id FROM Account WHERE AccountNumber = 'CC-1001' LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Asset asset = [SELECT Id, Product2Id, SerialNumber FROM Asset LIMIT 1];
        Department__c department = [SELECT Id FROM Department__c LIMIT 1];

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'header' => new Map<String, Object>{
                    'accountId' => account.Id,
                    'operatingUnit' => '82',
                    'creationSource' => 'ConnectCare',
                    'connectCareRequestId' => 'cc-req-test-003'
                },
                'lines' => new List<Object>{
                    new Map<String, Object>{
                        'lineType' => 'serialized',
                        'serialized' => true,
                        'assetId' => asset.Id,
                        'product2Id' => asset.Product2Id,
                        'serialNumber' => asset.SerialNumber,
                        'model' => 'Unrouted Model',
                        'productLine' => 'Unknown Line',
                        'departmentId' => department.Id,
                        'contactId' => contact.Id,
                        'disinfected' => getDisinfectedYesValueForTest(),
                        'reportedProblem' => 'No routing rule available',
                        'estimateRequired' => 'Pre-Approved',
                        'repairWarranty' => 'No'
                    }
                }
            }
        );

        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/connectcare/v1/return-orders';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(requestBody);

        RestResponse response = new RestResponse();
        RestContext.request = request;
        RestContext.response = response;

        Test.startTest();
        ConnectCareRestService.createReturnOrders();
        Test.stopTest();

        System.assertEquals(422, response.statusCode);
        Map<String, Object> body = parseResponseBody(response);
        System.assertEquals(false, body.get('success'));
        System.assertEquals('ROUTING_ERROR', body.get('errorCode'));
    }

    @isTest
    static void testCreateReturnOrders_resolvesAccountNumber() {
        Account account = [SELECT Id FROM Account WHERE AccountNumber = 'CC-1001' LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Asset asset = [SELECT Id, Product2Id, SerialNumber FROM Asset LIMIT 1];
        Department__c department = [SELECT Id FROM Department__c LIMIT 1];

        Schema.Location repairCenter = new Schema.Location(
            Name = 'Account Number Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'Surgical',
            RepairCenter__c = repairCenter.Id
        );

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'header' => new Map<String, Object>{
                    'accountNumber' => 'CC-1001',
                    'creationSource' => 'ConnectCare'
                },
                'lines' => new List<Object>{
                    new Map<String, Object>{
                        'lineType' => 'serialized',
                        'assetId' => asset.Id,
                        'product2Id' => asset.Product2Id,
                        'serialNumber' => asset.SerialNumber,
                        'model' => 'Resolved Account Model',
                        'productLine' => 'Surgical',
                        'departmentId' => department.Id,
                        'contactId' => contact.Id,
                        'disinfected' => getDisinfectedYesValueForTest(),
                        'reportedProblem' => 'Resolved by account number',
                        'estimateRequired' => 'Pre-Approved',
                        'repairWarranty' => 'No'
                    }
                }
            }
        );

        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/connectcare/v1/return-orders';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(requestBody);

        RestResponse response = new RestResponse();
        RestContext.request = request;
        RestContext.response = response;

        Test.startTest();
        ConnectCareRestService.createReturnOrders();
        Test.stopTest();

        System.assertEquals(200, response.statusCode);

        ReturnOrder createdOrder = [
            SELECT Id, AccountId
            FROM ReturnOrder
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(account.Id, createdOrder.AccountId);
    }

    @isTest
    static void testSearchAssets_unsupportedResource() {
        RestResponse response = invokeGet('/services/apexrest/connectcare/v1/unknown', null, '130');

        Test.startTest();
        ConnectCareRestService.searchAssets();
        Test.stopTest();

        System.assertEquals(404, response.statusCode);
        Map<String, Object> body = parseResponseBody(response);
        System.assertEquals('NOT_FOUND', body.get('errorCode'));
    }

    @isTest
    static void testSearchAssets_missingAccount() {
        RestResponse response = invokeGet(
            '/services/apexrest/connectcare/v1/assets',
            null,
            '130'
        );

        Test.startTest();
        ConnectCareRestService.searchAssets();
        Test.stopTest();

        System.assertEquals(400, response.statusCode);
        Map<String, Object> body = parseResponseBody(response);
        System.assertEquals('VALIDATION_ERROR', body.get('errorCode'));
    }

    @isTest
    static void testSearchAssets_byAccountNumber() {
        RestResponse response = invokeGet(
            '/services/apexrest/connectcare/v1/assets',
            new Map<String, String>{
                'accountNumber' => 'CC-1001',
                'serialSearchTerm' => '130'
            }
        );

        Test.startTest();
        ConnectCareRestService.searchAssets();
        Test.stopTest();

        System.assertEquals(200, response.statusCode);
        Map<String, Object> body = parseResponseBody(response);
        List<Object> assets = (List<Object>) body.get('assets');
        System.assertEquals(1, assets.size());
        Map<String, Object> assetRow = (Map<String, Object>) assets[0];
        System.assertEquals('CC-SN-130456', assetRow.get('serialNumber'));
        System.assertEquals('CC-1001', assetRow.get('accountNumber'));
    }

    @isTest
    static void testSearchAssets_blankSerialTerm() {
        Account account = [SELECT Id FROM Account WHERE AccountNumber = 'CC-1001' LIMIT 1];
        RestResponse response = invokeGet(
            '/services/apexrest/connectcare/v1/assets',
            new Map<String, String>{
                'accountId' => account.Id,
                'serialSearchTerm' => '   '
            }
        );

        Test.startTest();
        ConnectCareRestService.searchAssets();
        Test.stopTest();

        System.assertEquals(400, response.statusCode);
    }

    @isTest
    static void testSearchAssets_unknownAccountNumber() {
        RestResponse response = invokeGet(
            '/services/apexrest/connectcare/v1/assets',
            new Map<String, String>{
                'accountNumber' => 'NO-SUCH-ACCOUNT',
                'serialSearchTerm' => '130'
            }
        );

        Test.startTest();
        ConnectCareRestService.searchAssets();
        Test.stopTest();

        System.assertEquals(400, response.statusCode);
    }

    @isTest
    static void testSearchAssets_pathWithoutApexRestPrefix() {
        RestResponse response = invokeGet('/assets', new Map<String, String>{
            'accountNumber' => 'CC-1001',
            'serialSearchTerm' => '130'
        });

        Test.startTest();
        ConnectCareRestService.searchAssets();
        Test.stopTest();

        System.assertEquals(200, response.statusCode);
    }

    @isTest
    static void testCreateReturnOrders_unsupportedResource() {
        RestResponse response = invokePost('/services/apexrest/connectcare/v1/other', '{}');

        Test.startTest();
        ConnectCareRestService.createReturnOrders();
        Test.stopTest();

        System.assertEquals(404, response.statusCode);
        Map<String, Object> body = parseResponseBody(response);
        System.assertEquals('NOT_FOUND', body.get('errorCode'));
    }

    @isTest
    static void testCreateReturnOrders_missingHeader() {
        RestResponse response = invokePost(
            '/services/apexrest/connectcare/v1/return-orders',
            JSON.serialize(new Map<String, Object>{ 'lines' => new List<Object>() })
        );

        Test.startTest();
        ConnectCareRestService.createReturnOrders();
        Test.stopTest();

        System.assertEquals(400, response.statusCode);
        Map<String, Object> body = parseResponseBody(response);
        System.assertEquals('header is required.', body.get('message'));
    }

    @isTest
    static void testCreateReturnOrders_emptyBody() {
        RestResponse response = invokePost('/services/apexrest/connectcare/v1/return-orders', '');

        Test.startTest();
        ConnectCareRestService.createReturnOrders();
        Test.stopTest();

        System.assertEquals(400, response.statusCode);
        Map<String, Object> body = parseResponseBody(response);
        System.assertEquals('header is required.', body.get('message'));
    }

    @isTest
    static void testCreateReturnOrders_bodyNotObject() {
        RestResponse response = invokePost(
            '/services/apexrest/connectcare/v1/return-orders',
            '[1,2]'
        );

        Test.startTest();
        ConnectCareRestService.createReturnOrders();
        Test.stopTest();

        System.assertEquals(400, response.statusCode);
        Map<String, Object> body = parseResponseBody(response);
        System.assertEquals('VALIDATION_ERROR', body.get('errorCode'));
    }

    @isTest
    static void testCreateReturnOrders_invalidJson() {
        RestResponse response = invokePost(
            '/services/apexrest/connectcare/v1/return-orders',
            '{not-json'
        );

        Test.startTest();
        ConnectCareRestService.createReturnOrders();
        Test.stopTest();

        System.assertEquals(400, response.statusCode);
        Map<String, Object> body = parseResponseBody(response);
        System.assertEquals('VALIDATION_ERROR', body.get('errorCode'));
    }

    @isTest
    static void testCreateReturnOrders_missingAccountAndSource() {
        RestResponse response = invokePost(
            '/services/apexrest/connectcare/v1/return-orders',
            JSON.serialize(
                new Map<String, Object>{
                    'header' => new Map<String, Object>{
                        'connectCareRequestId' => 'cc-req-missing-account'
                    },
                    'lines' => new List<Object>()
                }
            )
        );

        Test.startTest();
        ConnectCareRestService.createReturnOrders();
        Test.stopTest();

        System.assertEquals(400, response.statusCode);
        Map<String, Object> body = parseResponseBody(response);
        List<Object> details = (List<Object>) body.get('details');
        System.assert(details.size() >= 2);
    }

    @isTest
    static void testCreateReturnOrders_wrongCreationSource() {
        RestResponse response = invokePost(
            '/services/apexrest/connectcare/v1/return-orders',
            JSON.serialize(
                new Map<String, Object>{
                    'header' => new Map<String, Object>{
                        'accountNumber' => 'CC-1001',
                        'creationSource' => 'Salesforce'
                    },
                    'lines' => new List<Object>{
                        new Map<String, Object>{ 'lineType' => 'serialized' }
                    }
                }
            )
        );

        Test.startTest();
        ConnectCareRestService.createReturnOrders();
        Test.stopTest();

        System.assertEquals(400, response.statusCode);
        Map<String, Object> body = parseResponseBody(response);
        System.assert(((String) body.get('message')).contains('ConnectCare'));
    }

    @isTest
    static void testCreateReturnOrders_nonObjectLineAndNonSerialized() {
        RestResponse response = invokePost(
            '/services/apexrest/connectcare/v1/return-orders',
            JSON.serialize(
                new Map<String, Object>{
                    'header' => new Map<String, Object>{
                        'accountNumber' => 'CC-1001',
                        'creationSource' => 'ConnectCare'
                    },
                    'lines' => new List<Object>{
                        'not-an-object',
                        new Map<String, Object>{ 'lineType' => 'instruments' }
                    }
                }
            )
        );

        Test.startTest();
        ConnectCareRestService.createReturnOrders();
        Test.stopTest();

        System.assertEquals(400, response.statusCode);
        Map<String, Object> body = parseResponseBody(response);
        List<Object> details = (List<Object>) body.get('details');
        System.assertEquals(2, details.size());
    }

    @isTest
    static void testCreateReturnOrders_headerAndLinesWrongTypes() {
        RestResponse response = invokePost(
            '/services/apexrest/connectcare/v1/return-orders',
            JSON.serialize(new Map<String, Object>{ 'header' => 'bad', 'lines' => 'bad' })
        );

        Test.startTest();
        ConnectCareRestService.createReturnOrders();
        Test.stopTest();

        System.assertEquals(400, response.statusCode);
        Map<String, Object> body = parseResponseBody(response);
        System.assertEquals('header is required.', body.get('message'));
    }

    @isTest
    static void testCreateReturnOrders_estimateAndWarrantyRules() {
        RestResponse response = invokePost(
            '/services/apexrest/connectcare/v1/return-orders',
            JSON.serialize(
                new Map<String, Object>{
                    'header' => new Map<String, Object>{
                        'accountNumber' => 'CC-1001',
                        'creationSource' => 'ConnectCare'
                    },
                    'lines' => new List<Object>{
                        new Map<String, Object>{
                            'lineType' => 'serialized',
                            'assetId' => 'not-an-id',
                            'serialNumber' => '',
                            'model' => '',
                            'productLine' => '',
                            'departmentId' => 'bad',
                            'contactId' => 'bad',
                            'disinfected' => '',
                            'reportedProblem' => '',
                            'estimateRequired' => 'Estimate Required',
                            'repairWarranty' => 'Yes'
                        }
                    }
                }
            )
        );

        Test.startTest();
        ConnectCareRestService.createReturnOrders();
        Test.stopTest();

        System.assertEquals(400, response.statusCode);
        Map<String, Object> body = parseResponseBody(response);
        List<Object> details = (List<Object>) body.get('details');
        System.assert(details.size() >= 6, 'Expected multiple serialized-line validation errors.');
    }

    @isTest
    static void testCreateReturnOrders_unknownAccountNumber() {
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Asset asset = [SELECT Id, Product2Id, SerialNumber FROM Asset LIMIT 1];
        Department__c department = [SELECT Id FROM Department__c LIMIT 1];

        RestResponse response = invokePost(
            '/services/apexrest/connectcare/v1/return-orders',
            JSON.serialize(
                new Map<String, Object>{
                    'header' => new Map<String, Object>{
                        'accountNumber' => 'UNKNOWN-999',
                        'creationSource' => 'ConnectCare',
                        'connectCareRequestId' => 'cc-req-unknown-account'
                    },
                    'lines' => new List<Object>{
                        buildValidSerializedLine(asset, contact.Id, department.Id)
                    }
                }
            )
        );

        Test.startTest();
        ConnectCareRestService.createReturnOrders();
        Test.stopTest();

        System.assertEquals(400, response.statusCode);
        Map<String, Object> body = parseResponseBody(response);
        System.assert(((String) body.get('message')).contains('Account could not be resolved'));
    }

    @isTest
    static void testCreateReturnOrders_duplicateAccountNumber() {
        new adb_Account()
            .name('ConnectCare Duplicate Account')
            .accountNumber('CC-1001')
            .systemId('LEG-CC-1001-DUP')
            .sourceSystemId('TEST-ORACLE-CC-DUP')
            .orgIds('82')
            .persist();

        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Asset asset = [SELECT Id, Product2Id, SerialNumber FROM Asset LIMIT 1];
        Department__c department = [SELECT Id FROM Department__c LIMIT 1];

        RestResponse response = invokePost(
            '/services/apexrest/connectcare/v1/return-orders',
            JSON.serialize(
                new Map<String, Object>{
                    'header' => new Map<String, Object>{
                        'accountNumber' => 'CC-1001',
                        'creationSource' => 'ConnectCare',
                        'connectCareRequestId' => 'cc-req-dup-account'
                    },
                    'lines' => new List<Object>{
                        buildValidSerializedLine(asset, contact.Id, department.Id)
                    }
                }
            )
        );

        Test.startTest();
        ConnectCareRestService.createReturnOrders();
        Test.stopTest();

        System.assertEquals(400, response.statusCode);
        Map<String, Object> body = parseResponseBody(response);
        System.assertEquals('VALIDATION_ERROR', body.get('errorCode'));
    }

    @isTest
    static void testCreateReturnOrders_missingOperatingUnit() {
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Asset asset = [SELECT Id, Product2Id, SerialNumber FROM Asset LIMIT 1];
        Department__c department = [SELECT Id FROM Department__c LIMIT 1];

        RestResponse response = invokePost(
            '/services/apexrest/connectcare/v1/return-orders',
            JSON.serialize(
                new Map<String, Object>{
                    'header' => new Map<String, Object>{
                        'accountNumber' => 'CC-1001',
                        'creationSource' => 'ConnectCare',
                        'connectCareRequestId' => 'cc-req-no-ou'
                    },
                    'lines' => new List<Object>{
                        buildValidSerializedLine(asset, contact.Id, department.Id)
                    }
                }
            )
        );

        Test.startTest();
        ConnectCareRestService.createReturnOrders();
        Test.stopTest();

        System.assert(
            response.statusCode == 400 || response.statusCode == 422,
            'Expected account OU fallback to fail validation or routing, got ' +
                response.statusCode
        );
    }

    @isTest
    static void testCreateReturnOrders_enrichesMissingProduct2Id() {
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Asset asset = [SELECT Id, Product2Id, SerialNumber FROM Asset LIMIT 1];
        Department__c department = [SELECT Id FROM Department__c LIMIT 1];

        Schema.Location repairCenter = new Schema.Location(
            Name = 'Enrich Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;
        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'Surgical',
            RepairCenter__c = repairCenter.Id
        );

        Map<String, Object> line = buildValidSerializedLine(asset, contact.Id, department.Id);
        line.remove('product2Id');
        line.put('customerPo', 'PO-1');
        line.put('customerReference', 'REF-1');
        line.put('isLoanerAsset', false);
        line.put('loanerRequested', false);

        RestResponse response = invokePost(
            '/services/apexrest/connectcare/v1/return-orders',
            JSON.serialize(
                new Map<String, Object>{
                    'header' => new Map<String, Object>{
                        'accountNumber' => 'CC-1001',
                        'operatingUnit' => '82',
                        'creationSource' => 'ConnectCare',
                        'salesRepId' => UserInfo.getUserId(),
                        'connectCareRequestId' => 'cc-req-enrich'
                    },
                    'lines' => new List<Object>{ line }
                }
            )
        );

        Test.startTest();
        ConnectCareRestService.createReturnOrders();
        Test.stopTest();

        System.assertEquals(
            200,
            response.statusCode,
            response.responseBody == null ? 'No response body' : response.responseBody.toString()
        );
    }

    @isTest
    static void testCreateReturnOrders_nullRequestBody() {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/connectcare/v1/return-orders';
        request.httpMethod = 'POST';
        request.requestBody = null;

        RestResponse response = new RestResponse();
        RestContext.request = request;
        RestContext.response = response;

        Test.startTest();
        ConnectCareRestService.createReturnOrders();
        Test.stopTest();

        System.assertEquals(400, response.statusCode);
    }

    private static Map<String, Object> buildValidSerializedLine(
        Asset asset,
        Id contactId,
        Id departmentId
    ) {
        return new Map<String, Object>{
            'lineType' => 'serialized',
            'serialized' => true,
            'assetId' => asset.Id,
            'product2Id' => asset.Product2Id,
            'serialNumber' => asset.SerialNumber,
            'model' => 'Test Model',
            'productLine' => 'Surgical',
            'departmentId' => departmentId,
            'contactId' => contactId,
            'disinfected' => getDisinfectedYesValueForTest(),
            'reportedProblem' => 'Unit not powering on',
            'estimateRequired' => 'Pre-Approved',
            'repairWarranty' => 'No'
        };
    }

    private static RestResponse invokeGet(String requestUri, Map<String, String> params) {
        return invokeGet(requestUri, params, null);
    }

    private static RestResponse invokeGet(
        String requestUri,
        Map<String, String> params,
        String serialSearchTerm
    ) {
        RestRequest request = new RestRequest();
        request.requestURI = requestUri;
        request.httpMethod = 'GET';
        if (params != null) {
            for (String key : params.keySet()) {
                request.addParameter(key, params.get(key));
            }
        }
        if (serialSearchTerm != null && (params == null || !params.containsKey('serialSearchTerm'))) {
            request.addParameter('serialSearchTerm', serialSearchTerm);
        }

        RestResponse response = new RestResponse();
        RestContext.request = request;
        RestContext.response = response;
        return response;
    }

    private static RestResponse invokePost(String requestUri, String body) {
        RestRequest request = new RestRequest();
        request.requestURI = requestUri;
        request.httpMethod = 'POST';
        if (body != null) {
            request.requestBody = Blob.valueOf(body);
        }

        RestResponse response = new RestResponse();
        RestContext.request = request;
        RestContext.response = response;
        return response;
    }

    private static Map<String, Object> parseResponseBody(RestResponse response) {
        return (Map<String, Object>) JSON.deserializeUntyped(response.responseBody.toString());
    }
}