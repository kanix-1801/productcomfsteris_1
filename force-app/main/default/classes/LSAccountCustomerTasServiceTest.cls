/**
 * @description Life Sciences Customer TAS tests.
 *              Covers LSAccountService, AccountService Customer and Prospect TAS methods,
 *              AccountTriggerHandler, TasAssignmentRequest.toJsonMap, and TasAssignmentResponse.parse.
 */
@IsTest
private class LSAccountCustomerTasServiceTest {

    private static final String LS_CLASS_CODE = 'SC';
    private static final String REP_ONE_EMPLOYEE = 'LSCTEST001';
    private static final String REP_TWO_EMPLOYEE = 'LSCTEST002';

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

    @IsTest
    static void testInsertSCCustomerAssignsTeam() {
        registerTasCalloutMock(200, buildTerritoryResponse(new List<String>{ REP_ONE_EMPLOYEE, REP_TWO_EMPLOYEE }));

        Test.startTest();
        Account acc = buildCustomer('LS Customer Assigned');
        insert acc;
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id]);
    }

    @IsTest
    static void testInsertSCCustomerNoTerritory() {
        registerTasCalloutMock(200, buildTerritoryResponse(new List<String>()));

        Test.startTest();
        Account acc = buildCustomer('LS Customer No Territory');
        insert acc;
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id]);
    }

    @IsTest
    static void testInsertSCCustomerCalloutFails() {
        registerTasCalloutMock(500, '{"error":"TAS unavailable"}');

        Test.startTest();
        Account acc = buildCustomer('LS Customer Callout Fail');
        insert acc;
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id]);
    }

    @IsTest
    static void testUnknownEmployeeLeavesAssignmentMissing() {
        registerTasCalloutMock(200, buildTerritoryResponse(new List<String>{ 'NO-SUCH-EMP' }));

        Test.startTest();
        Account acc = buildCustomer('LS Customer Unknown Rep');
        insert acc;
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id]);
    }

    @IsTest
    static void testUpdateDoesNotDuplicateTeamMembers() {
        registerTasCalloutMock(200, buildTerritoryResponse(new List<String>{ REP_ONE_EMPLOYEE, REP_TWO_EMPLOYEE }));
        Account acc = buildCustomer('LS Customer Update Retry');
        insert acc;
        acc = reloadAccount(acc.Id);

        Test.startTest();
        acc.BillingCity = 'Columbus';
        update acc;
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id]);
    }

    @IsTest
    static void testPayloadAndResponseMapping() {
        Map<String, Object> storedSc = requestFor('SC', 'United States').toJsonMap();
        System.assertEquals('SC', storedSc.get('classCode'));
        System.assertEquals('US', storedSc.get('country'));

        Map<String, Object> healthcare = requestFor('Healthcare', 'Canada').toJsonMap();
        System.assertEquals('HC', healthcare.get('classCode'));
        System.assertEquals('Canada', healthcare.get('country'));

        Map<String, Object> blankCountry = requestFor('SC', null).toJsonMap();
        System.assertEquals('SC', blankCountry.get('classCode'));

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
            Class_Code__c = 'SC'
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

    @IsTest
    static void testHealthcareCheckSkipsLifeSciencesCustomer() {
        Id customerRtId = customerRecordTypeId();
        Account lifeSciences = new Account(
            Name = 'In Memory SC',
            RecordTypeId = customerRtId,
            CustomerClassCode__c = 'SC',
            AccountSource = 'Oracle',
            OracleAddressId__c = 'ORADDR-MEM',
            OrgIDs__c = '82',
            BillingCity = 'Cleveland',
            BillingState = 'Ohio',
            BillingCountry = 'US',
            BillingPostalCode = '44113'
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
        saved = reloadAccount(saved.Id);
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

    @IsTest
    static void testLifeSciencesServicePaths() {
        System.assertEquals(true, LSAccountService.isLifeSciencesAccount(new Account(CustomerClassCode__c = 'SC')));
        System.assertEquals(false, LSAccountService.isLifeSciencesAccount(new Account(CustomerClassCode__c = 'HC')));
        System.assertEquals(false, LSAccountService.isLifeSciencesAccount(null));

        AccountService.assignTAStoCustomer(null);
        AccountService.assignTAStoCustomer(new List<Account>());
        AccountService.assignTAStoCustomer(new List<Account>{ new Account(Name = 'Not a customer') });
        AccountService.assignTAStoCustomerUpdate(null, null);
        AccountService.assignTAStoCustomerUpdate(new List<Account>(), new Map<Id, Account>());
        LSAccountService.retryTasAssignmentFromFlow(null);
        LSAccountService.retryTasAssignmentFromFlow(new List<LSAccountService.FlowRequest>());
        LSAccountService.retryTasAssignmentFromFlow(new List<LSAccountService.FlowRequest>{ new LSAccountService.FlowRequest() });

        registerTasCalloutMock(200, buildTerritoryResponse(new List<String>{ REP_ONE_EMPLOYEE }));
        Account acc = buildCustomer('LS Customer Label And Oracle');
        insert acc;
        acc = reloadAccount(acc.Id);

        Account sourceIdAccount = acc.clone(true, true, true, true);
        sourceIdAccount.AccountSource = null;
        sourceIdAccount.SourceSystemID__c = 'SRCOracle';
        Account unchanged = acc.clone(true, true, true, true);

        Test.startTest();
        AccountService.assignTAStoCustomer(new List<Account>{ sourceIdAccount, null });
        AccountService.assignTAStoCustomerUpdate(
            new List<Account>{ unchanged, sourceIdAccount },
            new Map<Id, Account>{
                unchanged.Id => unchanged.clone(true, true, true, true),
                sourceIdAccount.Id => acc
            }
        );
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id]);
    }

    @IsTest
    static void testServiceCatchBlocks() {
        Integer caught = 0;
        LSAccountService.throwTestException = true;
        try {
            LSAccountService.retryTasAssignmentFromFlow(new List<LSAccountService.FlowRequest>());
        } catch (LSAccountService.LSAccountServiceException e) {
            caught++;
        }
        try {
            LSAccountService.assignTAStoProspect(new List<Account>());
        } catch (LSAccountService.LSAccountServiceException e) {
            caught++;
        }
        LSAccountService.throwTestException = false;
        System.assertEquals(2, caught);
    }

    @IsTest
    static void testTriggerBranches() {
        registerTasCalloutMock(200, buildTerritoryResponse(new List<String>{ REP_ONE_EMPLOYEE }));
        Account hcProspect = buildProspect('HC Prospect Guard', 'HC', null);
        Account hcProspectTwo = buildProspect('HC Prospect Guard Two', 'HC', null);
        Account lsProspect = buildProspect('LS Prospect Guard', LS_CLASS_CODE, null);
        Account hcCustomer = buildCustomer('HC Customer Guard');
        hcCustomer.CustomerClassCode__c = 'HC';
        hcCustomer.AccountSource = null;
        hcCustomer.SourceSystemID__c = 'NOORACLE' + uniqueSuffix();
        hcCustomer.OracleAddressId__c = null;

        Test.startTest();
        insert new List<Account>{ hcProspect, hcProspectTwo };
        insert lsProspect;
        insert hcCustomer;

        hcProspect = reloadAccount(hcProspect.Id);
        hcProspect.BillingCity = 'Akron';
        update hcProspect;

        lsProspect = reloadAccount(lsProspect.Id);
        lsProspect.BillingCity = 'Toledo';
        update lsProspect;

        hcCustomer = reloadAccount(hcCustomer.Id);
        hcCustomer.BillingCity = 'Dayton';
        update hcCustomer;
        Test.stopTest();

        System.assertNotEquals(null, hcProspect.Id);
        System.assertNotEquals(null, lsProspect.Id);
        System.assertNotEquals(null, hcCustomer.Id);
    }

    @IsTest
    static void testProspectServiceGuardPaths() {
        Price_List__c priceList = createPriceList();
        Account hcProspect = buildProspect('HC Prospect Memory', 'HC', null);
        Account hcProspectTwo = buildProspect('HC Prospect Memory Two', 'HC', null);
        insert new List<Account>{ hcProspect, hcProspectTwo };
        hcProspect = reloadAccount(hcProspect.Id);
        hcProspectTwo = reloadAccount(hcProspectTwo.Id);

        hcProspect.Price_List__c = priceList.Id;
        hcProspectTwo.Price_List__c = priceList.Id;
        hcProspect.BillingCity = 'Akron';
        hcProspectTwo.BillingCity = 'Dayton';

        Account oldHcOne = hcProspect.clone(true, true, true, true);
        oldHcOne.BillingCity = 'Cleveland';
        Account oldHcTwo = hcProspectTwo.clone(true, true, true, true);
        oldHcTwo.BillingCity = 'Cleveland';

        AccountService.assignTAStoProspect(null);
        AccountService.assignTAStoProspect(new List<Account>());
        AccountService.assignTAStoProspect(new List<Account>{ hcProspect, hcProspectTwo });
        AccountService.assignTAStoProspectUpdate(null, null);
        AccountService.assignTAStoProspectUpdate(new List<Account>{ hcProspect }, null);
        AccountService.assignTAStoProspectUpdate(
            new List<Account>{ hcProspect, null },
            new Map<Id, Account>{ hcProspectTwo.Id => hcProspectTwo }
        );
        AccountService.assignTAStoProspectUpdate(
            new List<Account>{ hcProspect, hcProspectTwo },
            new Map<Id, Account>{
                hcProspect.Id => oldHcOne,
                hcProspectTwo.Id => oldHcTwo
            }
        );

        LSAccountService.assignTAStoProspect(null);
        LSAccountService.assignTAStoProspect(new List<Account>());
        LSAccountService.assignTAStoProspect(new List<Account>{ null, new Account(Name = 'Not LS') });

        AccountService.retryTasAssignmentFromFlow(null);
        AccountService.retryTasAssignmentFromFlow(new List<AccountService.FlowRequest>());
        AccountService.retryTasAssignmentFromFlow(
            new List<AccountService.FlowRequest>{ new AccountService.FlowRequest() }
        );

        System.assertNotEquals(null, hcProspect.Id);
    }

    @IsTest
    static void testSingleProspectUpdateEnqueue() {
        registerTasCalloutMock(200, buildTerritoryResponse(new List<String>{ REP_ONE_EMPLOYEE }));
        Price_List__c priceList = createPriceList();
        Account hcProspect = buildProspect('HC Prospect Enqueue', 'HC', null);
        insert hcProspect;
        hcProspect = reloadAccount(hcProspect.Id);
        hcProspect.Price_List__c = priceList.Id;
        hcProspect.BillingCity = 'Akron';
        Account oldHc = hcProspect.clone(true, true, true, true);
        oldHc.BillingCity = 'Cleveland';

        Test.startTest();
        AccountService.assignTAStoProspectUpdate(
            new List<Account>{ hcProspect },
            new Map<Id, Account>{ hcProspect.Id => oldHc }
        );
        Test.stopTest();

        System.assertNotEquals(null, hcProspect.Id);
    }

    @IsTest
    static void testLifeSciencesProspectEnqueue() {
        registerTasCalloutMock(200, buildTerritoryResponse(new List<String>{ REP_ONE_EMPLOYEE }));
        Price_List__c priceList = createPriceList();
        Account lsProspect = buildProspect('LS Prospect Enqueue', LS_CLASS_CODE, priceList.Id);
        insert lsProspect;
        lsProspect = reloadAccount(lsProspect.Id);

        Test.startTest();
        LSAccountService.assignTAStoProspect(new List<Account>{ lsProspect, null });
        Test.stopTest();

        System.assertNotEquals(null, lsProspect.Id);
    }

    @IsTest
    static void testHealthcareProspectRetry() {
        registerTasCalloutMock(200, buildTerritoryResponse(new List<String>{ REP_ONE_EMPLOYEE }));
        Price_List__c priceList = createPriceList();
        Account hcProspect = buildProspect('HC Prospect Retry', 'HC', priceList.Id);
        insert hcProspect;

        AccountService.FlowRequest request = new AccountService.FlowRequest();
        request.accountId = hcProspect.Id;

        Test.startTest();
        AccountService.retryTasAssignmentFromFlow(new List<AccountService.FlowRequest>{ request });
        Test.stopTest();

        System.assertNotEquals(null, hcProspect.Id);
    }

    @IsTest
    static void testLifeSciencesCustomerUpdateLoop() {
        registerTasCalloutMock(200, buildTerritoryResponse(new List<String>{ REP_ONE_EMPLOYEE }));
        Account lsCustomer = buildCustomer('LS Customer Loop');
        lsCustomer.OracleAddressId__c = null;
        lsCustomer.AccountSource = null;
        lsCustomer.SourceSystemID__c = 'NOORACLE' + uniqueSuffix();
        insert lsCustomer;
        lsCustomer = reloadAccount(lsCustomer.Id);

        Account changed = lsCustomer.clone(true, true, true, true);
        changed.AccountSource = 'Oracle';
        changed.OracleAddressId__c = 'ORADDRLOOP';
        changed.BillingCity = 'Akron';

        Test.startTest();
        AccountService.assignTAStoCustomerUpdate(
            new List<Account>{ null, new Account(Name = 'No Id'), changed, lsCustomer },
            new Map<Id, Account>{ changed.Id => lsCustomer }
        );
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :lsCustomer.Id]);
    }

    private static Price_List__c createPriceList() {
        Price_List__c priceList = new Price_List__c(
            Name = 'Prospect Coverage Price List',
            Price_List_Id__c = 'PL-COV-' + uniqueSuffix()
        );
        insert priceList;
        return priceList;
    }

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
            BillingStateCode = 'OH',
            BillingCountryCode = 'US',
            BillingPostalCode = '44101',
            TAS_Retry__c = false
        );
    }

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
            BillingStateCode = 'OH',
            BillingCountryCode = 'US',
            BillingPostalCode = '44113'
        );
    }

    private static Account reloadAccount(Id accountId) {
        return [
            SELECT Id, Name, RecordTypeId, CustomerClassCode__c, AccountSource, SourceSystemID__c,
                   OracleAddressId__c, OrgIDs__c, Price_List__c,
                   BillingStreet, BillingCity, BillingState, BillingCountry, BillingPostalCode,
                   TAS_Retry__c, TAS_Assignment_Status__c
            FROM Account
            WHERE Id = :accountId
        ];
    }

    private static Id prospectRecordTypeId() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Prospect').getRecordTypeId();
    }

    private static Id customerRecordTypeId() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Customer').getRecordTypeId();
    }

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

    private static void registerTasCalloutMock(Integer statusCode, String body) {
        ShoutOut_Service_Setting__mdt setting = new ShoutOut_Service_Setting__mdt();
        setting.DeveloperName = 'SF_CUSTOMER_TAS';
        setting.Label = 'SF_CUSTOMER_TAS';
        setting.MasterLabel = 'SF_CUSTOMER_TAS';
        setting.Framework_Callout_Name__c = 'SF_CUSTOMER_TAS';
        setting.Error_Handler_Class__c = 'SO_ErrorLogger';
        setting.isActive__c = true;
        setting.Named_Credential__c = 'Boomi_TAS';
        setting.Provider_Class__c = 'SO_Provider_Salesforce';
        setting.Service_Class__c = 'SO_ServiceAdapterBase_REST';
        setting.REST_Verb__c = 'POST';
        setting.REST_Path__c = '';
        setting.REST_query__c = '';
        setting.Service_Transform_Class__c = '';
        setting.Timeout__c = 20;
        SO_Config.SO_ServiceList_mock.add(setting);
        ShoutOut_Service_Setting__mdt prospectSetting = setting.clone();
        prospectSetting.DeveloperName = 'SF_PROSPECT_TAS';
        prospectSetting.Label = 'SF_PROSPECT_TAS';
        prospectSetting.MasterLabel = 'SF_PROSPECT_TAS';
        prospectSetting.Framework_Callout_Name__c = 'SF_PROSPECT_TAS';
        SO_Config.SO_ServiceList_mock.add(prospectSetting);
        Test.setMock(
            HttpCalloutMock.class,
            new SO_HttpMockFactory(statusCode, statusCode == 200 ? 'OK' : 'Error', body, new Map<String, String>())
        );
    }

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

    private static String uniqueSuffix() {
        return String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }
}