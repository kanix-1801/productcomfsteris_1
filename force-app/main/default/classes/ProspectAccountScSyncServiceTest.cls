/**
 * @description GC-3441 / GC-3500 - Tests Prospect Account Sales Connection sync
 *              using Boomi endpoint.
 */
@IsTest
private class ProspectAccountScSyncServiceTest {
    private static Integer mockCallCount = 0;
    private static String mockRequestBody;

    private class CapturingHttpMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            mockCallCount++;
            mockRequestBody = request.getBody();

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setStatus('OK');
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"status":"success"}');
            return response;
        }
    }

    @IsTest
    static void mapperBuildsDesignedPayload() {
        Account accountRecord = (Account) JSON.deserialize(
            '{"attributes":{"type":"Account"},'
                + '"Id":"001000000000001AAA",'
                + '"Name":"Cleveland Clinic",'
                + '"OrgIDs__c":"83",'
                + '"CustomerClassCode__c":"Healthcare",'
                + '"BillingStreet":"123 Main Street",'
                + '"BillingCity":"Chicago",'
                + '"BillingState":"Illinois",'
                + '"BillingPostalCode":"60601",'
                + '"BillingCountry":"United States",'
                + '"CreatedDate":"2026-07-16T21:05:02.000+0000",'
                + '"LastModifiedDate":"2026-09-17T10:30:00.000+0000",'
                + '"Price_List__r":{"attributes":{"type":"Price_List__c"},'
                + '"Price_List_ID__c":"4353"},'
                + '"CreatedBy":{"attributes":{"type":"User"},'
                + '"EmployeeNumber__c":"74737537"},'
                + '"LastModifiedBy":{"attributes":{"type":"User"},'
                + '"EmployeeNumber__c":"703447"}}',
            Account.class
        );

        Map<String, Object> payload =
            ProspectAccountScSyncMapper.toRequest(accountRecord).toJsonMap();

        System.assertEquals('001000000000001AAA', payload.get('accountId'));
        System.assertEquals('Cleveland Clinic', payload.get('accountName'));
        System.assertEquals('4353', payload.get('priceListId'));
        System.assertEquals('83', payload.get('orgId'));
        System.assertEquals('123 Main Street', payload.get('billingAddressLine1'));
        System.assertEquals('Chicago', payload.get('billingCity'));
        System.assertEquals('Illinois', payload.get('billingState'));
        System.assertEquals('60601', payload.get('billingPostalCode'));
        System.assertEquals('United States', payload.get('billingCountry'));
        System.assertEquals('Healthcare', payload.get('customerClassCode'));
        System.assertEquals('703447', payload.get('modifiedBy'));
        System.assertEquals('2026-09-17 10:30:00', payload.get('modifiedDate'));
        System.assertEquals('74737537', payload.get('createdBy'));
        System.assertEquals('2026-07-16 21:05:02', payload.get('createdDate'));
        System.assertEquals(14, payload.size());
    }

    @IsTest
    static void serviceIgnoresCustomerAndUnwatchedFieldChanges() {
        Id prospectRtId = getAccountRecordTypeId('Prospect');
        Id customerRtId = getAccountRecordTypeId('Customer');
        Id prospectId = '001000000000001AAA';
        Id customerId = '001000000000002AAA';
        Id unwatchedId = '001000000000003AAA';

        Set<Id> result = ProspectAccountScSyncService.collectProspectsWithWatchedFieldChange(
            new List<Account>{
                new Account(
                    Id = prospectId,
                    RecordTypeId = prospectRtId,
                    Name = 'New Name',
                    BillingCity = 'Cleveland'
                ),
                new Account(
                    Id = customerId,
                    RecordTypeId = customerRtId,
                    Name = 'Customer Changed'
                ),
                new Account(
                    Id = unwatchedId,
                    RecordTypeId = prospectRtId,
                    Name = 'Same Name',
                    BillingCity = 'Cleveland'
                )
            },
            new Map<Id, Account>{
                prospectId => new Account(
                    Id = prospectId,
                    RecordTypeId = prospectRtId,
                    Name = 'Old Name',
                    BillingCity = 'Cleveland'
                ),
                customerId => new Account(
                    Id = customerId,
                    RecordTypeId = customerRtId,
                    Name = 'Old Customer'
                ),
                unwatchedId => new Account(
                    Id = unwatchedId,
                    RecordTypeId = prospectRtId,
                    Name = 'Same Name',
                    BillingCity = 'Cleveland'
                )
            }
        );

        System.assertEquals(new Set<Id>{ prospectId }, result);
    }

    @IsTest
    static void queueableSendsEligibleProspectThroughMockEndpoint() {
        TestData data = createData(true, 'Healthcare_Sales', 'HCSales');
        registerCalloutMock();

        Test.startTest();
        new ProspectAccountScSyncQueueable(new Set<Id>{ data.accountRecord.Id }).execute(null);
        Test.stopTest();

        System.assertEquals(1, ProspectAccountScSyncGateway.testSendCount);
        Map<String, Object> payload =
            (Map<String, Object>) JSON.deserializeUntyped(
                ProspectAccountScSyncGateway.testLastRequestJson
            );
        System.assertEquals(String.valueOf(data.accountRecord.Id), payload.get('accountId'));
        System.assertEquals('GC-3441 Prospect', payload.get('accountName'));
        System.assertEquals('PL-GC-3441', payload.get('priceListId'));
        System.assertEquals('Chicago', payload.get('billingCity'));
        System.assertEquals(true, payload.containsKey('modifiedBy'));
        System.assertNotEquals(null, payload.get('modifiedDate'));
        System.assertEquals(true, payload.containsKey('createdBy'));
        System.assertNotEquals(null, payload.get('createdDate'));
    }

    @IsTest
    static void selectorExcludesProspectWithoutHcSalesQuote() {
        TestData data = createData(false, 'Healthcare_Sales', 'HCSales');

        Set<Id> eligibleIds = ProspectAccountScSyncSelector.selectAccountIdsWithHcSalesQuote(
            new Set<Id>{ data.accountRecord.Id }
        );

        System.assertEquals(true, eligibleIds.isEmpty());
    }

    @IsTest
    static void selectorTreatsAllHcSalesOpportunityTypesAsEligible() {
        System.assertEquals(
            true,
            ProspectAccountScSyncSelector.isHealthcareSalesOpportunity('Healthcare_Sales')
        );
        System.assertEquals(
            true,
            ProspectAccountScSyncSelector.isHealthcareSalesOpportunity('HCSalesConsumables')
        );
        System.assertEquals(
            true,
            ProspectAccountScSyncSelector.isHealthcareSalesOpportunity(
                'HC_Sales_Customer_Goodwill_Support'
            )
        );
        System.assertEquals(
            true,
            ProspectAccountScSyncSelector.isHealthcareSalesOpportunity(
                'EquipmentPlacementProgram'
            )
        );
        System.assertEquals(
            true,
            ProspectAccountScSyncSelector.isHealthcareSalesOpportunity('InstrumentProcessing')
        );
        System.assertEquals(
            false,
            ProspectAccountScSyncSelector.isHealthcareSalesOpportunity('Life_Sciences_Sales')
        );
        System.assertEquals(
            false,
            ProspectAccountScSyncSelector.isHealthcareSalesOpportunity(null)
        );
        System.assertEquals(
            true,
            ProspectAccountScSyncSelector.hasHealthcareSalesQuote(
                new List<Quote>{ new Quote(Name = 'Dummy') }
            ) == false
        );
        Quote hcQuote = new Quote(Name = 'HC Quote');
        hcQuote.RecordType = new RecordType(DeveloperName = 'HCSales');
        System.assertEquals(
            true,
            ProspectAccountScSyncSelector.hasHealthcareSalesQuote(new List<Quote>{ hcQuote })
        );
    }

    @IsTest
    static void gatewayHandlesNullRequest() {
        ProspectAccountScSyncGateway.CalloutResult result =
            ProspectAccountScSyncGateway.sendAccountUpdate(null);

        System.assertEquals(false, result.calloutSuccess);
        System.assertEquals('Request body is null', result.errorDetail);
        System.assertEquals(false, ProspectAccountScSyncGateway.isSuccessful(null));
        System.assertEquals(
            'SO_Callout returned an empty response map',
            ProspectAccountScSyncGateway.extractErrorDetail(null)
        );
    }

    @IsTest
    static void mapperFallsBackToStandardEmployeeNumber() {
        System.assertEquals(
            '8644',
            ProspectAccountScSyncMapper.resolveHrisId(
                new User(EmployeeNumber = '8644')
            )
        );
        System.assertEquals(null, ProspectAccountScSyncMapper.resolveHrisId(null));
        System.assertEquals(
            '11',
            ProspectAccountScSyncMapper.resolveHrisId(
                new User(EmployeeNumber__c = '  11  ')
            )
        );
        System.assertEquals(
            '22',
            ProspectAccountScSyncMapper.resolveHrisId(
                new User(EmployeeNumber__c = '', EmployeeNumber = '  22  ')
            )
        );
        System.assertEquals(
            null,
            ProspectAccountScSyncMapper.resolveHrisId(
                new User(EmployeeNumber__c = '', EmployeeNumber = '')
            )
        );
    }

    @IsTest
    static void mapperHandlesMissingRelatedFieldsAndRejectsNullAccount() {
        Account accountRecord = new Account(
            Id = '001000000000001AAA',
            Name = 'No Related Fields'
        );

        ProspectAccountScSyncRequest request =
            ProspectAccountScSyncMapper.toRequest(accountRecord);
        System.assertEquals(null, request.priceListId);
        System.assertEquals(null, request.modifiedBy);
        System.assertEquals(null, request.modifiedDate);
        System.assertEquals(null, request.createdBy);
        System.assertEquals(null, request.createdDate);

        Boolean threwForNull = false;
        Boolean threwForMissingId = false;
        try {
            ProspectAccountScSyncMapper.toRequest(null);
        } catch (IllegalArgumentException exceptionValue) {
            threwForNull = true;
            System.assertEquals('Account is required.', exceptionValue.getMessage());
        }
        try {
            ProspectAccountScSyncMapper.toRequest(new Account(Name = 'No Id'));
        } catch (IllegalArgumentException exceptionValue) {
            threwForMissingId = true;
        }
        System.assertEquals(true, threwForNull);
        System.assertEquals(true, threwForMissingId);
    }

    @IsTest
    static void serviceEnqueueStopsWhenCandidatesOrQuotesAreMissing() {
        Id prospectRtId = getAccountRecordTypeId('Prospect');
        Id prospectId = '001000000000001AAA';

        ProspectAccountScSyncService.enqueueEligibleAccounts(null, null);
        ProspectAccountScSyncService.enqueueEligibleAccounts(
            new List<Account>(),
            new Map<Id, Account>()
        );
        ProspectAccountScSyncService.enqueueEligibleAccounts(
            new List<Account>{
                new Account(
                    Id = prospectId,
                    RecordTypeId = prospectRtId,
                    Name = 'Changed Name'
                )
            },
            new Map<Id, Account>{
                prospectId => new Account(
                    Id = prospectId,
                    RecordTypeId = prospectRtId,
                    Name = 'Old Name'
                )
            }
        );

        TestData data = createData(false, 'Healthcare_Sales', 'HCSales');
        Account oldAccount = data.accountRecord.clone(true, true, true, true);
        Account newAccount = data.accountRecord.clone(true, true, true, true);
        newAccount.BillingStreet = '999 Changed Street';

        Test.startTest();
        ProspectAccountScSyncService.enqueueEligibleAccounts(
            new List<Account>{ newAccount },
            new Map<Id, Account>{ oldAccount.Id => oldAccount }
        );
        Test.stopTest();

        System.assertEquals(0, mockCallCount);
    }

    @IsTest
    static void serviceEnqueuesEligibleProspectAndQueueableSends() {
        TestData data = createData(true, 'Healthcare_Sales', 'HCSales');
        registerCalloutMock();

        Account oldAccount = data.accountRecord.clone(true, true, true, true);
        Account newAccount = data.accountRecord.clone(true, true, true, true);
        newAccount.BillingStreet = '999 Changed Street';

        Test.startTest();
        ProspectAccountScSyncService.enqueueEligibleAccounts(
            new List<Account>{ newAccount },
            new Map<Id, Account>{ oldAccount.Id => oldAccount }
        );
        Test.stopTest();

        System.assertEquals(1, ProspectAccountScSyncGateway.testSendCount);
        Map<String, Object> payload =
            (Map<String, Object>) JSON.deserializeUntyped(
                ProspectAccountScSyncGateway.testLastRequestJson
            );
        System.assertEquals(String.valueOf(data.accountRecord.Id), payload.get('accountId'));
    }

    @IsTest
    static void serviceCollectsEachWatchedFieldAndSkipsInvalidRows() {
        Id prospectRtId = getAccountRecordTypeId('Prospect');
        Id firstId = '001000000000001AAA';
        Id missingOldId = '001000000000002AAA';
        Id priceListOldId = '001000000000003AAA';
        Id priceListNewId = '001000000000004AAA';

        Set<Id> skipped = ProspectAccountScSyncService.collectProspectsWithWatchedFieldChange(
            new List<Account>{
                null,
                new Account(Name = 'No Id', RecordTypeId = prospectRtId),
                new Account(
                    Id = firstId,
                    RecordTypeId = prospectRtId,
                    Name = 'Still Prospect'
                ),
                new Account(
                    Id = missingOldId,
                    RecordTypeId = prospectRtId,
                    Name = 'Missing Old'
                )
            },
            new Map<Id, Account>{
                firstId => null
            }
        );
        System.assertEquals(true, skipped.isEmpty());

        System.assertEquals(
            true,
            ProspectAccountScSyncService.hasWatchedFieldChanged(
                new Account(Name = 'A', BillingStreet = 'New'),
                new Account(Name = 'A', BillingStreet = 'Old')
            )
        );
        System.assertEquals(
            true,
            ProspectAccountScSyncService.hasWatchedFieldChanged(
                new Account(Name = 'A', BillingCity = 'New'),
                new Account(Name = 'A', BillingCity = 'Old')
            )
        );
        System.assertEquals(
            true,
            ProspectAccountScSyncService.hasWatchedFieldChanged(
                new Account(Name = 'A', BillingState = 'New'),
                new Account(Name = 'A', BillingState = 'Old')
            )
        );
        System.assertEquals(
            true,
            ProspectAccountScSyncService.hasWatchedFieldChanged(
                new Account(Name = 'A', BillingPostalCode = '99999'),
                new Account(Name = 'A', BillingPostalCode = '00000')
            )
        );
        System.assertEquals(
            true,
            ProspectAccountScSyncService.hasWatchedFieldChanged(
                new Account(Name = 'A', BillingCountry = 'Canada'),
                new Account(Name = 'A', BillingCountry = 'United States')
            )
        );
        System.assertEquals(
            true,
            ProspectAccountScSyncService.hasWatchedFieldChanged(
                new Account(Name = 'A', Price_List__c = priceListNewId),
                new Account(Name = 'A', Price_List__c = priceListOldId)
            )
        );
        System.assertEquals(
            true,
            ProspectAccountScSyncService.hasWatchedFieldChanged(
                new Account(Name = 'A', OrgIDs__c = '99'),
                new Account(Name = 'A', OrgIDs__c = '83')
            )
        );
        System.assertEquals(
            true,
            ProspectAccountScSyncService.hasWatchedFieldChanged(
                new Account(Name = 'A', CustomerClassCode__c = 'HC'),
                new Account(Name = 'A', CustomerClassCode__c = 'Other')
            )
        );
        System.assertEquals(
            false,
            ProspectAccountScSyncService.hasWatchedFieldChanged(
                new Account(Name = 'A', BillingCity = 'Same'),
                new Account(Name = 'A', BillingCity = 'Same')
            )
        );
    }

    @IsTest
    static void selectorReturnsEmptyForBlankIdsAndLoadsProspectsForSync() {
        System.assertEquals(
            true,
            ProspectAccountScSyncSelector.selectAccountIdsWithHcSalesQuote(null).isEmpty()
        );
        System.assertEquals(
            true,
            ProspectAccountScSyncSelector.selectAccountIdsWithHcSalesQuote(new Set<Id>())
                .isEmpty()
        );
        System.assertEquals(
            true,
            ProspectAccountScSyncSelector.selectAccountsForSync(null).isEmpty()
        );
        System.assertEquals(
            true,
            ProspectAccountScSyncSelector.selectAccountsForSync(new Set<Id>()).isEmpty()
        );
        System.assertEquals(
            false,
            ProspectAccountScSyncSelector.isHealthcareSalesOpportunity('')
        );

        Quote otherQuote = new Quote(Name = 'Other Quote');
        otherQuote.RecordType = new RecordType(DeveloperName = 'Life_Sciences');
        Quote consumableQuote = new Quote(Name = 'Consumable Quote');
        consumableQuote.RecordType = new RecordType(DeveloperName = 'HCSalesConsumables');
        System.assertEquals(
            false,
            ProspectAccountScSyncSelector.hasHealthcareSalesQuote(
                new List<Quote>{ otherQuote }
            )
        );
        System.assertEquals(
            true,
            ProspectAccountScSyncSelector.hasHealthcareSalesQuote(
                new List<Quote>{ otherQuote, consumableQuote }
            )
        );

        TestData data = createData(true, 'Healthcare_Sales', 'HCSales');
        Set<Id> eligibleIds = ProspectAccountScSyncSelector.selectAccountIdsWithHcSalesQuote(
            new Set<Id>{ data.accountRecord.Id }
        );
        System.assertEquals(true, eligibleIds.contains(data.accountRecord.Id));
        System.assertEquals(
            1,
            ProspectAccountScSyncSelector.selectAccountsForSync(eligibleIds).size()
        );
    }

    @IsTest
    static void gatewayParsesSuccessFailureAndExceptionPaths() {
        System.assertEquals(
            false,
            ProspectAccountScSyncGateway.isSuccessful(new Map<String, Object>())
        );
        System.assertEquals(
            true,
            ProspectAccountScSyncGateway.isSuccessful(
                new Map<String, Object>{ 'SO_SUCCESS' => true }
            )
        );
        System.assertEquals(
            false,
            ProspectAccountScSyncGateway.isSuccessful(
                new Map<String, Object>{ 'SO_SUCCESS' => 'true' }
            )
        );
        System.assertEquals(
            'SO_Callout returned an empty response map',
            ProspectAccountScSyncGateway.extractErrorDetail(new Map<String, Object>())
        );
        System.assertEquals(
            'Boomi rejected the account',
            ProspectAccountScSyncGateway.extractErrorDetail(
                new Map<String, Object>{ 'SO_RETURN' => 'Boomi rejected the account' }
            )
        );
        System.assertEquals(
            'timeout',
            ProspectAccountScSyncGateway.extractErrorDetail(
                new Map<String, Object>{
                    SO_Constants.SERVICERESPONSE => 'timeout'
                }
            )
        );
        System.assertEquals(
            'SO_Callout failed with SO_SUCCESS=false',
            ProspectAccountScSyncGateway.extractErrorDetail(
                new Map<String, Object>{ 'SO_SUCCESS' => false }
            )
        );

        ProspectAccountScSyncRequest request = ProspectAccountScSyncRequest.create(
            '001000000000001AAA',
            'Gateway Exception Prospect',
            'PL-1',
            '83',
            '1 Main',
            'Chicago',
            'Illinois',
            '60601',
            'United States',
            'HC',
            '703447',
            '2026-09-17 10:30:00',
            '74737537',
            '2026-07-16 21:05:02'
        );

        ProspectAccountScSyncGateway.CalloutResult exceptionResult =
            ProspectAccountScSyncGateway.sendAccountUpdate(request);
        System.assertEquals(false, exceptionResult.calloutSuccess);
        System.assertEquals(true, String.isNotBlank(exceptionResult.errorDetail));

        registerCalloutMock();
        Test.startTest();
        ProspectAccountScSyncGateway.CalloutResult mockedResult =
            ProspectAccountScSyncGateway.sendAccountUpdate(request);
        Test.stopTest();
        System.assertNotEquals(null, mockedResult);
        System.assertEquals(true, mockedResult.calloutSuccess);
        System.assertEquals(true, ProspectAccountScSyncGateway.testSendCount >= 1);
    }

    @IsTest
    static void queueableHandlesEmptyIdsAndFailedCallout() {
        new ProspectAccountScSyncQueueable(null).execute(null);
        new ProspectAccountScSyncQueueable(new Set<Id>()).execute(null);

        TestData failedData = createData(true, 'Healthcare_Sales', 'HCSales');
        Test.startTest();
        new ProspectAccountScSyncQueueable(new Set<Id>{ failedData.accountRecord.Id })
            .execute(null);
        Test.stopTest();
        System.assertEquals(0, mockCallCount);
    }

    @IsTest
    static void queueableChainsRemainingAccountsWhenCalloutLimitReached() {
        Price_List__c priceList = new Price_List__c(
            Name = 'GC-3441 Chain Price List',
            Price_List_ID__c = 'PL-GC-3441-CHAIN'
        );
        Database.insert(priceList, AccessLevel.SYSTEM_MODE);

        Account firstAccount = new Account(
            Name = 'GC-3441 Chain One',
            RecordTypeId = getAccountRecordTypeId('Prospect'),
            Price_List__c = priceList.Id,
            OrgIDs__c = '83',
            CustomerClassCode__c = 'Healthcare',
            BillingStreet = '1 Chain Street',
            BillingCity = 'Chicago',
            BillingStateCode = 'IL',
            BillingPostalCode = '60601',
            BillingCountryCode = 'US'
        );
        Account secondAccount = new Account(
            Name = 'GC-3441 Chain Two',
            RecordTypeId = getAccountRecordTypeId('Prospect'),
            Price_List__c = priceList.Id,
            OrgIDs__c = '83',
            CustomerClassCode__c = 'Healthcare',
            BillingStreet = '2 Chain Street',
            BillingCity = 'Chicago',
            BillingStateCode = 'IL',
            BillingPostalCode = '60601',
            BillingCountryCode = 'US'
        );
        Database.insert(new List<Account>{ firstAccount, secondAccount }, AccessLevel.SYSTEM_MODE);

        registerCalloutMock();
        ProspectAccountScSyncQueueable.maxCalloutsForTest = 1;

        Test.startTest();
        new ProspectAccountScSyncQueueable(
            new Set<Id>{ firstAccount.Id, secondAccount.Id }
        ).execute(null);
        Test.stopTest();

        System.assertEquals(2, ProspectAccountScSyncGateway.testSendCount);
    }

    private static void registerCalloutMock() {
        mockCallCount = 0;
        mockRequestBody = null;
        ProspectAccountScSyncGateway.bypassHttpForTest = true;
        ProspectAccountScSyncGateway.testSendCount = 0;
        ProspectAccountScSyncGateway.testLastRequestJson = null;
        SO_Config.inSandboxMock = true;
        SO_Config.SO_ServiceList_mock.clear();
        SO_Config.SO_ServiceList_mock.add(defaultServiceSetting());
        Test.setMock(HttpCalloutMock.class, new CapturingHttpMock());
    }

    private static ShoutOut_Service_Setting__mdt defaultServiceSetting() {
        ShoutOut_Service_Setting__mdt setting = new ShoutOut_Service_Setting__mdt();
        setting.DeveloperName = ProspectAccountScSyncGateway.SERVICE_SETTING_NAME;
        setting.MasterLabel = ProspectAccountScSyncGateway.SERVICE_SETTING_NAME;
        setting.Label = ProspectAccountScSyncGateway.SERVICE_SETTING_NAME;
        setting.Framework_Callout_Name__c = ProspectAccountScSyncGateway.SERVICE_SETTING_NAME;
        setting.Named_Credential__c = 'Boomi_TAS';
        setting.Provider_Class__c = 'SO_Provider_Salesforce';
        setting.Service_Class__c = 'SO_ServiceAdapterBase_REST';
        setting.Error_Handler_Class__c = 'SO_ErrorLogger';
        setting.REST_Verb__c = 'POST';
        setting.REST_Path__c = '/mock/prospect-account-sc-sync';
        setting.REST_query__c = '';
        setting.Timeout__c = 20;
        setting.isActive__c = true;
        return setting;
    }

    private static TestData createData(
        Boolean createQuote,
        String opportunityRecordType,
        String quoteRecordType
    ) {
        TestData data = new TestData();
        Price_List__c priceList = new Price_List__c(
            Name = 'GC-3441 Price List',
            Price_List_ID__c = 'PL-GC-3441'
        );
        Database.insert(priceList, AccessLevel.SYSTEM_MODE);

        Account accountRecord = new Account(
            Name = 'GC-3441 Prospect',
            RecordTypeId = getAccountRecordTypeId('Prospect'),
            Price_List__c = priceList.Id,
            OrgIDs__c = '83',
            CustomerClassCode__c = 'Healthcare',
            BillingStreet = '123 Main Street',
            BillingCity = 'Chicago',
            BillingStateCode = 'IL',
            BillingPostalCode = '60601',
            BillingCountryCode = 'US'
        );
        Database.insert(accountRecord, AccessLevel.SYSTEM_MODE);

        Contact primaryContact = new Contact(
            FirstName = 'GC3441',
            LastName = 'Primary',
            AccountId = accountRecord.Id,
            Email = 'gc3441.primary@example.com'
        );
        Database.insert(primaryContact, AccessLevel.SYSTEM_MODE);

        Opportunity opportunityRecord = new Opportunity(
            Name = 'GC-3441 HC Opportunity',
            AccountId = accountRecord.Id,
            RecordTypeId = getOpportunityRecordTypeId(opportunityRecordType),
            StageName = 'Discovery',
            Type = 'New Business',
            Amount = 1000,
            Probability = 10,
            CloseDate = Date.today().addDays(30),
            PrimaryContact__c = primaryContact.Id,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        Database.insert(opportunityRecord, AccessLevel.SYSTEM_MODE);

        if (createQuote) {
            Quote quoteRecord = new Quote(
                Name = 'GC-3441 Quote',
                OpportunityId = opportunityRecord.Id,
                Pricebook2Id = Test.getStandardPricebookId(),
                RecordTypeId = getQuoteRecordTypeId(quoteRecordType),
                Status = 'Draft',
                ExpirationDate = Date.today().addDays(30),
                QuoteType__c = 'Normal Quote'
            );
            Database.insert(quoteRecord, AccessLevel.SYSTEM_MODE);
        }

        data.accountRecord = accountRecord;
        return data;
    }

    private static Id getAccountRecordTypeId(String developerName) {
        return queryRecordTypeId('Account', developerName);
    }

    private static Id getOpportunityRecordTypeId(String developerName) {
        return queryRecordTypeId('Opportunity', developerName);
    }

    private static Id getQuoteRecordTypeId(String developerName) {
        return queryRecordTypeId('Quote', developerName);
    }

    private static Id queryRecordTypeId(String sobjectType, String developerName) {
        return [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = :sobjectType
              AND DeveloperName = :developerName
            WITH SYSTEM_MODE
            LIMIT 1
        ].Id;
    }

    private class TestData {
        Account accountRecord;
    }
}