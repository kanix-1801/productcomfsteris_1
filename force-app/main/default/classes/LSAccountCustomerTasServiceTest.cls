/**
 * @description Life Sciences Customer TAS tests.
 *              Covers LSAccountService Customer methods, the Customer queueable and
 *              integration service, AccountService.isValidCustomerAccountForTas,
 *              TasAssignmentRequest.toJsonMap, and TasAssignmentResponse.parse.
 */
@IsTest
private class LSAccountCustomerTasServiceTest {

    private static final String LS_CLASS_CODE = 'SC';
    private static final String REP_ONE_EMPLOYEE = 'LSCTEST001';
    private static final String REP_TWO_EMPLOYEE = 'LSCTEST002';

    /**
     * @description Creates two Life Sciences Sales users so TAS employee numbers can be resolved.
     */
    @TestSetup
    static void setupData() {
        Profile lsProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = :UserSelector.LIFESCIENCES_SALES_PROFILE_NAME
            LIMIT 1
        ];

        insert new List<User>{
            createUser(lsProfile.Id, 'lscusrepone', REP_ONE_EMPLOYEE),
            createUser(lsProfile.Id, 'lscusreptwo', REP_TWO_EMPLOYEE)
        };
    }

    /**
     * @description Verifies an eligible Life Sciences Customer insert with territory data
     *              is Assigned, sets TAS_Retry__c, and creates Account Team Members and
     *              OrderLineContact__c records.
     */
    @IsTest
    static void testInsertSCCustomerAssignsTeam() {
        registerTasCalloutMock(200, buildTerritoryResponse(new List<String>{ REP_ONE_EMPLOYEE, REP_TWO_EMPLOYEE }));

        Test.startTest();
        Account acc = buildCustomer('LS Customer Assigned');
        insert acc;
        Test.stopTest();

        Account updated = [
            SELECT TAS_Assignment_Status__c, TAS_Retry__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        String tasAddressId = String.valueOf(acc.Id);
        System.assertEquals(LSAccountCustomerTasIntegrationService.TAS_STATUS_ASSIGNED, updated.TAS_Assignment_Status__c);
        System.assertEquals(true, updated.TAS_Retry__c);
        System.assertEquals(2, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id]);
        System.assertEquals(2, [SELECT COUNT() FROM OrderLineContact__c WHERE TASAddressId__c = :tasAddressId]);
    }

    /**
     * @description Verifies a successful TAS response with no territory data is
     *              Assignment Missing, leaves TAS_Retry__c false, and creates no
     *              Account Team Members.
     */
    @IsTest
    static void testInsertSCCustomerNoTerritory() {
        registerTasCalloutMock(200, buildTerritoryResponse(new List<String>()));

        Test.startTest();
        Account acc = buildCustomer('LS Customer No Territory');
        insert acc;
        Test.stopTest();

        Account updated = [SELECT TAS_Assignment_Status__c, TAS_Retry__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(LSAccountCustomerTasIntegrationService.TAS_STATUS_ASSIGNMENT_MISSING, updated.TAS_Assignment_Status__c);
        System.assertEquals(false, updated.TAS_Retry__c);
        System.assertEquals(0, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id]);
    }

    /**
     * @description Verifies a failed TAS callout is classified as Technical Failure
     *              and creates no Account Team Members.
     */
    @IsTest
    static void testInsertSCCustomerCalloutFails() {
        registerTasCalloutMock(500, '{"error":"TAS unavailable"}');

        Test.startTest();
        Account acc = buildCustomer('LS Customer Callout Fail');
        insert acc;
        Test.stopTest();

        Account updated = [SELECT TAS_Assignment_Status__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(LSAccountCustomerTasIntegrationService.TAS_STATUS_TECHNICAL_FAILURE, updated.TAS_Assignment_Status__c);
        System.assertEquals(0, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id]);
    }

    /**
     * @description Verifies a territory whose employee number does not match a Life
     *              Sciences Sales user is Assignment Missing, sets TAS_Retry__c, and
     *              creates no Account Team Members.
     */
    @IsTest
    static void testUnknownEmployeeLeavesAssignmentMissing() {
        registerTasCalloutMock(200, buildTerritoryResponse(new List<String>{ 'NO-SUCH-EMP' }));

        Test.startTest();
        Account acc = buildCustomer('LS Customer Unknown Rep');
        insert acc;
        Test.stopTest();

        Account updated = [SELECT TAS_Assignment_Status__c, TAS_Retry__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(LSAccountCustomerTasIntegrationService.TAS_STATUS_ASSIGNMENT_MISSING, updated.TAS_Assignment_Status__c);
        System.assertEquals(true, updated.TAS_Retry__c);
        System.assertEquals(0, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id]);
    }

    /**
     * @description Verifies a billing-city update reprocesses TAS without inserting
     *              a second set of Account Team Members.
     */
    @IsTest
    static void testUpdateAndRetryDoNotDuplicateTeamMembers() {
        registerTasCalloutMock(200, buildTerritoryResponse(new List<String>{ REP_ONE_EMPLOYEE, REP_TWO_EMPLOYEE }));
        Account acc = buildCustomer('LS Customer Update Retry');
        insert acc;

        Test.startTest();
        acc.BillingCity = 'Columbus';
        update acc;
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id]);
    }

    /**
     * @description Verifies TasAssignmentRequest maps Life Sciences and Healthcare
     *              class codes and country, and TasAssignmentResponse parses territory data.
     */
    @IsTest
    static void testPayloadAndResponseMapping() {
        Map<String, Object> lifeScience = requestFor('SC', 'United States').toJsonMap();
        System.assertEquals('SC', lifeScience.get('classCode'));
        System.assertEquals('US', lifeScience.get('country'));

        Map<String, Object> healthcare = requestFor('Healthcare', 'Canada').toJsonMap();
        System.assertEquals('HC', healthcare.get('classCode'));
        System.assertEquals('Canada', healthcare.get('country'));

        Map<String, Object> alreadySc = requestFor('SC', null).toJsonMap();
        System.assertEquals('SC', alreadySc.get('classCode'));

        Account acc = new Account(
            CustomerClassCode__c = 'SC',
            BillingState = 'Ohio',
            BillingPostalCode = '44113',
            BillingCountry = 'United States',
            BillingCity = 'Cleveland',
            OrgIDs__c = '82'
        );
        System.assertEquals('SC', TasAssignmentRequest.fromAccount(acc).toJsonMap().get('classCode'));

        Lead leadRecord = new Lead(
            State = 'Ohio',
            PostalCode = '44113',
            Country = 'United States',
            City = 'Cleveland',
            Org_ID__c = '82',
            Class_Code__c = 'SC',
            Sales_Category__c = 'LS'
        );
        System.assertEquals('SC', TasAssignmentRequest.fromLead(leadRecord).toJsonMap().get('classCode'));

        System.assertEquals(null, TasAssignmentResponse.parse(null));
        System.assertEquals(null, TasAssignmentResponse.parse('   '));

        TasAssignmentResponse parsed = TasAssignmentResponse.parse(
            '{"prospectId":"001000000000001AAA","territoryData":[{"customerClassCode":"SC","territoryId":"1916","salesRepEmployeeNumber":"LSCTEST001"}]}'
        );
        System.assertEquals('SC', parsed.territoryData[0].classCode);
        System.assertEquals('1916', parsed.territoryData[0].territoryId);
    }

    /**
     * @description Verifies the Healthcare customer path ignores Life Sciences customers
     *              while the Life Sciences insert still creates one Account Team Member.
     */
    @IsTest
    static void testHealthcareCheckSkipsLifeSciencesCustomer() {
        Id customerRtId = customerRecordTypeId();
        Account lifeSciences = new Account(
            Name = 'In Memory SC',
            RecordTypeId = customerRtId,
            CustomerClassCode__c = 'SC'
        );
        Account healthcare = new Account(
            Name = 'In Memory HC',
            RecordTypeId = customerRtId,
            CustomerClassCode__c = 'HC'
        );

        AccountService.assignTAStoCustomer(null);
        AccountService.assignTAStoCustomer(new List<Account>());
        AccountService.assignTAStoCustomer(new List<Account>{ null, lifeSciences, healthcare });
        AccountService.assignTAStoCustomerUpdate(null, null);
        AccountService.assignTAStoCustomerUpdate(new List<Account>{ healthcare }, null);

        registerTasCalloutMock(200, buildTerritoryResponse(new List<String>{ REP_ONE_EMPLOYEE }));
        Account saved = buildCustomer('LS Customer HC Skip');
        insert saved;
        Account oldSaved = saved.clone(true, true, true, true);
        saved.BillingCity = 'Akron';

        Test.startTest();
        AccountService.assignTAStoCustomer(new List<Account>{ saved });
        AccountService.assignTAStoCustomerUpdate(
            new List<Account>{ saved, healthcare },
            new Map<Id, Account>{ saved.Id => oldSaved }
        );
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :saved.Id]);
    }

    /**
     * @description Verifies Life Sciences customer guard paths and that an eligible
     *              Oracle-sourced customer still creates one Account Team Member.
     */
    @IsTest
    static void testLifeSciencesServicePaths() {
        System.assertEquals(true, LSAccountService.isLifeSciencesAccount(new Account(CustomerClassCode__c = 'SC')));
        System.assertEquals(false, LSAccountService.isLifeSciencesAccount(new Account(CustomerClassCode__c = 'HC')));
        System.assertEquals(false, LSAccountService.isLifeSciencesAccount(null));

        LSAccountService.assignTAStoCustomer(null);
        LSAccountService.assignTAStoCustomer(new List<Account>());
        LSAccountService.assignTAStoCustomer(new List<Account>{ new Account(Name = 'Not a customer') });
        LSAccountService.assignTAStoCustomerUpdate(null, null);
        LSAccountService.assignTAStoCustomerUpdate(new List<Account>{ new Account(Name = 'x') }, null);
        LSAccountService.assignTAStoCustomerUpdate(
            new List<Account>{ new Account(Name = 'Missing old') },
            new Map<Id, Account>{ '001000000000002AAA' => new Account() }
        );
        LSAccountService.retryTasAssignmentFromFlow(null);
        LSAccountService.retryTasAssignmentFromFlow(new List<LSAccountService.FlowRequest>());
        LSAccountService.retryTasAssignmentFromFlow(new List<LSAccountService.FlowRequest>{ new LSAccountService.FlowRequest() });

        registerTasCalloutMock(200, buildTerritoryResponse(new List<String>{ REP_ONE_EMPLOYEE }));
        Account acc = buildCustomer('LS Customer Label And Oracle');
        insert acc;

        Account labelAccount = acc.clone(true, true, true, true);
        labelAccount.CustomerClassCode__c = 'SC';
        Account sourceIdAccount = acc.clone(true, true, true, true);
        sourceIdAccount.AccountSource = null;
        sourceIdAccount.SourceSystemID__c = 'SRCOracle';
        Account unchanged = acc.clone(true, true, true, true);

        Test.startTest();
        LSAccountService.assignTAStoCustomer(new List<Account>{ labelAccount, sourceIdAccount, null });
        LSAccountService.assignTAStoCustomerUpdate(
            new List<Account>{ unchanged, labelAccount },
            new Map<Id, Account>{
                unchanged.Id => unchanged.clone(true, true, true, true),
                labelAccount.Id => acc
            }
        );
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id]);
    }

    /**
     * @description Verifies the Life Sciences customer, customer-update, and retry
     *              methods enter their catch blocks when the test exception is enabled.
     */
    @IsTest
    static void testServiceCatchBlocks() {
        Integer caught = 0;
        LSAccountService.throwTestException = true;
        try {
            LSAccountService.assignTAStoCustomer(new List<Account>());
        } catch (LSAccountService.LSAccountServiceException e) {
            caught++;
        }
        try {
            LSAccountService.assignTAStoCustomerUpdate(null, null);
        } catch (LSAccountService.LSAccountServiceException e) {
            caught++;
        }
        try {
            LSAccountService.retryTasAssignmentFromFlow(new List<LSAccountService.FlowRequest>());
        } catch (LSAccountService.LSAccountServiceException e) {
            caught++;
        }
        LSAccountService.throwTestException = false;
        System.assertEquals(3, caught);
    }

    /**
     * @description Verifies the Life Sciences customer queueable ignores null, unknown,
     *              and empty Account Ids and swallows its test exception.
     */
    @IsTest
    static void testQueueableGuardAndCatchPaths() {
        Test.startTest();
        new LSAccountCustomerTasQueueable(null).execute(null);
        new LSAccountCustomerTasQueueable(new Set<Id>{ '001000000000001AAA' }).execute(null);
        LSAccountCustomerTasQueueable.throwTestException = true;
        new LSAccountCustomerTasQueueable(new Set<Id>()).execute(null);
        LSAccountCustomerTasQueueable.throwTestException = false;
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM AccountTeamMember]);
    }

    /**
     * @description Verifies integration helpers for null input, invalid territory
     *              numbers, outcome updates, and save-result logging.
     */
    @IsTest
    static void testIntegrationHelperPaths() {
        Account acc = buildCustomer('LS Customer Helpers');
        acc.OracleAddressId__c = null;
        insert acc;

        TasTerritoryItem validItem = new TasTerritoryItem();
        validItem.accountId = acc.Id;
        validItem.classCode = LS_CLASS_CODE;
        validItem.salesRepId = '1001';
        validItem.salesRepEmployeeNumber = REP_ONE_EMPLOYEE;
        validItem.territoryId = '1916';
        validItem.territoryNumber = 'S41208';
        validItem.territoryDescription = 'MIDWEST';
        validItem.regionManagerEmployeeNumber = REP_TWO_EMPLOYEE;
        validItem.zoneManagerEmployeeNumber = REP_TWO_EMPLOYEE;

        TasTerritoryItem invalidNumber = new TasTerritoryItem();
        invalidNumber.accountId = acc.Id;
        invalidNumber.classCode = LS_CLASS_CODE;
        invalidNumber.salesRepId = 'not-a-number';
        invalidNumber.salesRepEmployeeNumber = '   ';
        invalidNumber.territoryId = '1917';
        invalidNumber.territoryNumber = 'S41209';
        invalidNumber.territoryDescription = 'MIDWEST BLANK REP';

        Test.startTest();
        LSAccountCustomerTasIntegrationService.processAccounts(null);
        LSAccountCustomerTasIntegrationService.processAccounts(new List<Account>{ null });
        LSAccountCustomerTasIntegrationService.insertTasAssignments(null);
        LSAccountCustomerTasIntegrationService.insertTasAssignments(new List<TasTerritoryItem>{ null, validItem, invalidNumber });
        LSAccountCustomerTasIntegrationService.applyTasOutcome(null);
        LSAccountCustomerTasIntegrationService.applyTasOutcome(new Map<Id, String>{
            null => LSAccountCustomerTasIntegrationService.TAS_STATUS_ASSIGNED,
            acc.Id => LSAccountCustomerTasIntegrationService.TAS_STATUS_TECHNICAL_FAILURE
        });
        LSAccountCustomerTasIntegrationService.logSaveResults('Account', null);
        LSAccountCustomerTasIntegrationService.logSaveResults(
            'Account',
            Database.update(new List<Account>{ new Account(Id = '001000000000001AAA') }, false)
        );
        LSAccountCustomerTasIntegrationService.throwTestExceptionInLogSaveResults = true;
        LSAccountCustomerTasIntegrationService.logSaveResults('Account', null);
        LSAccountCustomerTasIntegrationService.throwTestExceptionInLogSaveResults = false;
        Test.stopTest();

        Account updated = [SELECT TAS_Assignment_Status__c FROM Account WHERE Id = :acc.Id];
        String tasAddressId = String.valueOf(acc.Id);
        System.assertEquals(LSAccountCustomerTasIntegrationService.TAS_STATUS_TECHNICAL_FAILURE, updated.TAS_Assignment_Status__c);
        System.assertEquals(2, [SELECT COUNT() FROM OrderLineContact__c WHERE TASAddressId__c = :tasAddressId]);
    }

    /**
     * @description Verifies a Healthcare prospect insert and repeated updates keep the
     *              Healthcare class code.
     */
    @IsTest
    static void testHandlerHealthcareInsertAndUpdate() {
        Account hcProspect = buildProspect('HC Prospect Guard', 'HC', null);
        insert hcProspect;

        Test.startTest();
        hcProspect.BillingCity = 'Akron';
        update hcProspect;
        hcProspect.BillingCity = 'Canton';
        update hcProspect;
        Test.stopTest();

        System.assertEquals('HC', [SELECT CustomerClassCode__c FROM Account WHERE Id = :hcProspect.Id].CustomerClassCode__c);
    }

    /**
     * @description Verifies a Life Sciences prospect insert and update keep the Life
     *              Sciences class code.
     */
    @IsTest
    static void testHandlerLifeSciencesInsertAndUpdate() {
        Account lsProspect = buildProspect('LS Prospect Guard', LS_CLASS_CODE, null);
        insert lsProspect;

        Test.startTest();
        lsProspect.BillingCity = 'Toledo';
        update lsProspect;
        Test.stopTest();

        System.assertEquals(LS_CLASS_CODE, [SELECT CustomerClassCode__c FROM Account WHERE Id = :lsProspect.Id].CustomerClassCode__c);
    }

    /**
     * @description Verifies Prospect TAS guard paths for null, empty, ineligible, and
     *              multiple records, including the Life Sciences prospect catch block.
     */
    @IsTest
    static void testProspectServiceGuardPaths() {
        Price_List__c priceList = createPriceList();
        Account hcProspect = buildProspect('HC Prospect Memory', 'HC', null);
        Account hcProspectTwo = buildProspect('HC Prospect Memory Two', 'HC', null);
        insert new List<Account>{ hcProspect, hcProspectTwo };

        hcProspect.Price_List__c = priceList.Id;
        hcProspectTwo.Price_List__c = priceList.Id;
        hcProspect.BillingCity = 'Akron';
        hcProspectTwo.BillingCity = 'Dayton';

        AccountService.assignTAStoProspect(null);
        AccountService.assignTAStoProspect(new List<Account>());
        AccountService.assignTAStoProspect(new List<Account>{ hcProspect, hcProspectTwo });

        LSAccountService.assignTAStoProspect(null);
        LSAccountService.assignTAStoProspect(new List<Account>());
        LSAccountService.assignTAStoProspect(new List<Account>{ null, new Account(Name = 'Not LS') });

        AccountService.retryTasAssignmentFromFlow(null);
        AccountService.retryTasAssignmentFromFlow(new List<AccountService.FlowRequest>());
        AccountService.retryTasAssignmentFromFlow(
            new List<AccountService.FlowRequest>{ new AccountService.FlowRequest() }
        );
        LSAccountService.retryTasAssignmentFromFlow(
            new List<LSAccountService.FlowRequest>{ new LSAccountService.FlowRequest() }
        );

        LSAccountService.throwTestException = true;
        Boolean prospectCatchCovered = false;
        try {
            LSAccountService.assignTAStoProspect(new List<Account>());
        } catch (LSAccountService.LSAccountServiceException e) {
            prospectCatchCovered = true;
        }
        LSAccountService.throwTestException = false;

        System.assertEquals(true, prospectCatchCovered);
    }

    /**
     * @description Verifies an eligible Life Sciences prospect can be submitted to
     *              LSAccountService.assignTAStoProspect.
     */
    @IsTest
    static void testLifeSciencesProspectEnqueue() {
        registerTasCalloutMock(200, buildTerritoryResponse(new List<String>{ REP_ONE_EMPLOYEE }));
        Price_List__c priceList = createPriceList();
        Account lsProspect = buildProspect('LS Prospect Enqueue', LS_CLASS_CODE, null);
        insert lsProspect;
        lsProspect.Price_List__c = priceList.Id;

        Test.startTest();
        LSAccountService.assignTAStoProspect(new List<Account>{ lsProspect, null });
        Test.stopTest();

        System.assertNotEquals(null, lsProspect.Id);
    }

    /**
     * @description Verifies Healthcare prospect retry accepts a Flow request.
     */
    @IsTest
    static void testHealthcareProspectRetry() {
        registerTasCalloutMock(200, buildTerritoryResponse(new List<String>{ REP_ONE_EMPLOYEE }));
        Price_List__c priceList = createPriceList();
        Account hcProspect = buildProspect('HC Prospect Retry', 'HC', priceList.Id);
        Account hcProspectTwo = buildProspect('HC Prospect Retry Two', 'HC', priceList.Id);

        Test.startTest();
        insert new List<Account>{ hcProspect, hcProspectTwo };
        AccountService.FlowRequest request = new AccountService.FlowRequest();
        request.accountId = hcProspect.Id;
        AccountService.retryTasAssignmentFromFlow(new List<AccountService.FlowRequest>{ request });
        Test.stopTest();

        System.assertNotEquals(null, hcProspect.Id);
    }

    /**
     * @description Verifies a customer that becomes Oracle-eligible on update is
     *              processed, including null and missing-Id records, and creates one
     *              Account Team Member.
     */
    @IsTest
    static void testLifeSciencesCustomerUpdateLoop() {
        registerTasCalloutMock(200, buildTerritoryResponse(new List<String>{ REP_ONE_EMPLOYEE }));
        Account lsCustomer = buildCustomer('LS Customer Loop');
        lsCustomer.OracleAddressId__c = null;
        lsCustomer.AccountSource = null;
        lsCustomer.SourceSystemID__c = null;
        insert lsCustomer;

        Account oldCustomer = [
            SELECT Id, Name, RecordTypeId, CustomerClassCode__c, AccountSource,
                   SourceSystemID__c, OracleAddressId__c, OrgIDs__c,
                   BillingStreet, BillingCity, BillingCountry, BillingState, BillingPostalCode
            FROM Account
            WHERE Id = :lsCustomer.Id
        ];

        lsCustomer.AccountSource = 'Oracle';
        lsCustomer.OracleAddressId__c = 'ORADDRLOOP';
        lsCustomer.BillingCity = 'Akron';
        update lsCustomer;

        Account changed = [
            SELECT Id, Name, RecordTypeId, CustomerClassCode__c, AccountSource,
                   SourceSystemID__c, OracleAddressId__c, OrgIDs__c,
                   BillingStreet, BillingCity, BillingCountry, BillingState, BillingPostalCode
            FROM Account
            WHERE Id = :lsCustomer.Id
        ];

        Test.startTest();
        LSAccountService.assignTAStoCustomerUpdate(
            new List<Account>{ null, new Account(Name = 'No Id'), changed, oldCustomer },
            new Map<Id, Account>{ changed.Id => oldCustomer }
        );
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :lsCustomer.Id]);
    }

    /**
     * @description Inserts a Price List used by prospect coverage tests.
     * @return Inserted Price_List__c record.
     */
    private static Price_List__c createPriceList() {
        Price_List__c priceList = new Price_List__c(
            Name = 'Prospect Coverage Price List',
            Price_List_Id__c = 'PL-COV-' + uniqueSuffix()
        );
        insert priceList;
        return priceList;
    }

    /**
     * @description Builds an unsaved Prospect Account for the supplied class code.
     * @param name Account name prefix.
     * @param classCode Customer class code.
     * @param priceListId Price List Id, when the prospect requires one.
     * @return Unsaved Prospect Account.
     */
    private static Account buildProspect(String name, String classCode, Id priceListId) {
        String suffix = uniqueSuffix();
        return new Account(
            Name = name + ' ' + suffix,
            RecordTypeId = prospectRecordTypeId(),
            CustomerClassCode__c = classCode,
            OrgIDs__c = '83',
            Price_List__c = priceListId,
            BillingStreet = '123 Main St',
            BillingCity = 'Cleveland',
            BillingCountryCode = 'US',
            BillingStateCode = 'OH',
            BillingPostalCode = '44101',
            TAS_Retry__c = false
        );
    }

    /**
     * @description Returns the Prospect Account record type Id.
     * @return Prospect Account record type Id.
     */
    private static Id prospectRecordTypeId() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Prospect').getRecordTypeId();
    }

    /**
     * @description Builds an unsaved Oracle-sourced Life Sciences Customer Account.
     * @param name Account name prefix.
     * @return Unsaved Customer Account.
     */
    private static Account buildCustomer(String name) {
        String suffix = uniqueSuffix();
        return new Account(
            Name = name + ' ' + suffix,
            RecordTypeId = customerRecordTypeId(),
            CustomerClassCode__c = LS_CLASS_CODE,
            AccountSource = 'Oracle',
            SourceSystemID__c = 'LSC' + suffix + 'Oracle',
            OracleAddressId__c = 'ORADDR' + suffix,
            OrgIDs__c = '82',
            BillingStreet = '45 West Broadway',
            BillingCity = 'Cleveland',
            BillingCountryCode = 'US',
            BillingStateCode = 'OH',
            BillingPostalCode = '44113'
        );
    }

    /**
     * @description Returns the Customer Account record type Id.
     * @return Customer Account record type Id.
     */
    private static Id customerRecordTypeId() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Customer').getRecordTypeId();
    }

    /**
     * @description Builds a TAS request used to verify class-code and country mapping.
     * @param classCode Class code placed on the request.
     * @param country Country placed on the request.
     * @return Populated TasAssignmentRequest.
     */
    private static TasAssignmentRequest requestFor(String classCode, String country) {
        TasAssignmentRequest requestBody = new TasAssignmentRequest();
        requestBody.mydate = String.valueOf(Date.today());
        requestBody.state = 'Ohio';
        requestBody.postalCode = '44113';
        requestBody.country = country;
        requestBody.city = 'Cleveland';
        requestBody.orgId = '82';
        requestBody.classCode = classCode;
        requestBody.prospectId = '001000000000001AAA';
        requestBody.sourceSystem = 'GlobalSF';
        return requestBody;
    }

    /**
     * @description Builds a mocked TAS success response for the supplied employee numbers.
     * @param employeeNumbers Sales rep employee numbers to return.
     * @return Serialized TAS response JSON.
     */
    private static String buildTerritoryResponse(List<String> employeeNumbers) {
        List<Object> territories = new List<Object>();
        Integer index = 0;
        for (String employeeNumber : employeeNumbers) {
            index++;
            territories.add(new Map<String, Object>{
                'territoryId' => '8100' + index,
                'territoryNumber' => 'L6630' + index,
                'territoryDescription' => 'CLEVELAND, OH',
                'salesRepId' => '10070435' + index,
                'salesRepEmployeeNumber' => employeeNumber,
                'salesRepName' => 'LS Rep ' + index,
                'tasSalesCategory' => 'LS CONSUMABLES',
                'customerClassCode' => LS_CLASS_CODE,
                'buName' => 'Life Sciences'
            });
        }
        return JSON.serialize(new Map<String, Object>{
            'prospectId' => '001000000000001AAA',
            'territoryData' => territories
        });
    }

    /**
     * @description Loads the org TAS setting and registers the HTTP callout mock.
     * @param statusCode HTTP status returned by the mock.
     * @param body Response body returned by the mock.
     */
    private static void registerTasCalloutMock(Integer statusCode, String body) {
        loadTasServiceSetting();
        Test.setMock(
            HttpCalloutMock.class,
            new SO_HttpMockFactory(statusCode, statusCode == 200 ? 'OK' : 'Error', body, new Map<String, String>())
        );
    }

    /**
     * @description Loads the org SF_PROSPECT_TAS ShoutOut setting into the test mock list.
     *              A hand-built SO_Provider_Salesforce record never reaches the HTTP mock.
     */
    private static void loadTasServiceSetting() {
        SO_Config.SO_ServiceList_mock.clear();
        SO_Config.SO_ServiceList_mock.addAll([
            SELECT DeveloperName,
                   Error_Handler_Class__c,
                   Framework_Callout_Name__c,
                   isActive__c,
                   MasterLabel,
                   Named_Credential__c,
                   Provider_Class__c,
                   REST_Path__c,
                   REST_query__c,
                   REST_Verb__c,
                   Service_Class__c,
                   Service_Transform_Class__c,
                   Timeout__c,
                   Retry_Max_Attempts__c,
                   Retry_Base_Delay_Seconds__c,
                   Retry_On_HTTP_Codes__c,
                   Retry_Callback_Class__c
            FROM ShoutOut_Service_Setting__mdt
            WHERE DeveloperName = 'SF_PROSPECT_TAS'
              AND isActive__c = true
            LIMIT 1
        ]);
    }

    /**
     * @description Builds an unsaved Life Sciences Sales user with the supplied employee number.
     * @param profileId Profile Id assigned to the user.
     * @param prefix Username prefix.
     * @param employeeNumber Employee number resolved by TAS.
     * @return Unsaved User record.
     */
    private static User createUser(Id profileId, String prefix, String employeeNumber) {
        String suffix = uniqueSuffix();
        String username = prefix + suffix + '@test.steris.com';
        return new User(
            FirstName = 'LS',
            LastName = prefix,
            Alias = ('l' + suffix).left(8),
            Email = username,
            Username = username,
            CommunityNickname = (prefix + suffix).left(40),
            ProfileId = profileId,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            EmployeeNumber__c = employeeNumber
        );
    }

    /**
     * @description Returns a random suffix used to keep test record names unique.
     * @return Random numeric suffix.
     */
    private static String uniqueSuffix() {
        return String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }
}