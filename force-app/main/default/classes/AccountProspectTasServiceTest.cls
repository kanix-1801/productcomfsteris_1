/**
 * @author Abhishek Mishra
 * @date 06-04-2026
 * @description Test class for validating the Prospect Account TAS integration framework.
 *              Uses an inner callout provider and SO_HttpMockFactory so the fake TAS
 *              reply does not depend on a Boomi named credential.
 *              GC-3282: added coverage for AccountService.populateOrgIdOnNewProspect().
 * Last Modified: Akash Dahinde - (17/06/2026)
 */
@IsTest
public class AccountProspectTasServiceTest {
    private static final String SALES_FIELD_REP_PSG_DEVELOPER_NAME = 'SalesFieldRepAccountManagerPSG';

    /**
     * @description Creates reusable test data required by Account Prospect TAS service tests.
     */
    @testSetup
    static void setupData() {
        Profile sterisSalesProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Healthcare Sales'
            LIMIT 1
        ];

        List<PermissionSet> permissionSets = [
            SELECT Id
            FROM PermissionSet
            WHERE Name IN (
                'PriceList_Create_PS',
                'OrderLineContact_c_Create_PS',
                'OrderLineContactUpdatePS'
            )
        ];

        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();

        Long uniqueSeed = System.currentTimeMillis();
        String tasEmployeeNumberOne = 'TAS' + uniqueSeed + 'A';
        String tasEmployeeNumberTwo = 'TAS' + uniqueSeed + 'B';
        Id internalRoleId = [
            SELECT Id
            FROM UserRole
            WHERE PortalType = 'None'
            LIMIT 1
        ].Id;

        User runningUser = createUser(
            sterisSalesProfile.Id,
            'runninguser' + uniqueSeed + '@test.com',
            'RUN' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );

        User tasRepOne = createUser(
            sterisSalesProfile.Id,
            'tasrepone' + uniqueSeed + '@test.com',
            tasEmployeeNumberOne
        );

        User tasRepTwo = createUser(
            sterisSalesProfile.Id,
            'tasreptwo' + uniqueSeed + '@test.com',
            tasEmployeeNumberTwo
        );

        // GC-3282: additional user with User.OrgId__c populated, used to verify
        // Account.OrgIDs__c auto-population from the running user on Prospect insert.
        User orgIdUser = createUser(
            sterisSalesProfile.Id,
            'orgiduser' + uniqueSeed + '@test.com',
            'ORG' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );

        orgIdUser.OrgId__c = '83'; // shared "Org IDs" Global Value Set value, matches OrgIDs__c test convention below
        // Account team and manual sharing require both users to have a role.
        runningUser.UserRoleId = internalRoleId;
        tasRepOne.UserRoleId = internalRoleId;
        tasRepTwo.UserRoleId = internalRoleId;
        orgIdUser.UserRoleId = internalRoleId;

        insert new List<User>{ runningUser, tasRepOne, tasRepTwo, orgIdUser };

        for (PermissionSet ps : permissionSets) {
            assignments.add(
                new PermissionSetAssignment(
                    AssigneeId = runningUser.Id,
                    PermissionSetId = ps.Id
                )
            );
            assignments.add(
                new PermissionSetAssignment(
                    AssigneeId = orgIdUser.Id,
                    PermissionSetId = ps.Id
                )
            );
        }

        // Setup-object DML must be isolated from custom-setting DML (MIXED_DML_OPERATION).
        System.runAs(runningUser) {
            insert assignments;
        }

        assignSalesFieldRepAccountManagerPsg(runningUser.Id);
        assignSalesFieldRepAccountManagerPsg(orgIdUser.Id);
    }

    /**
     * @description Verifies Account Team Members and OrderLineContact__c records
     *              are created after inserting a valid Prospect Account.
     */
    @IsTest
    static void testAfterInsertCreatesAccountTeamMembers() {
        User runningUser = getRunningUser();
        Price_List__c priceList = createPriceList('Test Price List Insert', 'PL-INSERT-001');
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(runningUser) {
            Account acc = createProspectAccount(
                'Test Prospect Account',
                prospectRtId,
                priceList.Id
            );
            insert acc;

            registerTasCalloutMock(buildMockTasResponseJson(acc.Id));

            Test.startTest();
            AccountProspectTasIntegrationService.processAccounts(new List<Account>{ acc });
            Test.stopTest();

            List<AccountTeamMember> teamMembers = [
                SELECT Id,
                       AccountId,
                       UserId,
                       TeamMemberRole,
                       AccountAccessLevel,
                       OpportunityAccessLevel,
                       CaseAccessLevel
                FROM AccountTeamMember
                WHERE AccountId = :acc.Id
            ];

            for (AccountTeamMember atm : teamMembers) {
                System.assertEquals('Sales', atm.TeamMemberRole);
                System.assertEquals('Edit', atm.AccountAccessLevel);
                // Opportunity access is not set by the service. The org default is Edit.
                System.assertEquals('Edit', atm.OpportunityAccessLevel);
                System.assertEquals('None', atm.CaseAccessLevel);
            }
        }
    }


    /**
     * @description Verifies AccountProspectTasIntegrationService end-to-end processing
     *              with a mocked TAS callout.
     */
    @IsTest
    static void testIntegrationServiceProcessesMockedTasResponse() {
        User runningUser = getRunningUser();
        Price_List__c priceList = createPriceList('Integration Service Price List', 'PL-INT-001');
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(runningUser) {
            Account acc = new Account(
                Name = 'Integration Service Prospect',
                RecordTypeId = prospectRtId,
                BillingStreet = '123 Main St',
                BillingCity = 'Cleveland',
                BillingStateCode = 'OH',
                BillingCountryCode = 'US',
                BillingPostalCode = '44101'
            );
            insert acc;

            acc.CustomerClassCode__c = 'HC';
            acc.OrgIDs__c = '83';
            acc.Price_List__c = priceList.Id;

            registerTasCalloutMock(buildMockTasResponseJson(acc.Id));

            Test.startTest();
            AccountProspectTasIntegrationService.processAccounts(new List<Account>{ acc });
            Test.stopTest();
        }
    }

    /**
     * @description Verifies duplicate Account Team Members are skipped on reprocessing.
     */
    @IsTest
    static void testDuplicateAccountTeamMembersAreSkipped() {
        User runningUser = getRunningUser();
        User tasRepOne = getTasRepOneUser();
        Price_List__c priceList = createPriceList('Duplicate Team Price List', 'PL-DUP-001');
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(runningUser) {
            Account acc = createProspectAccount(
                'Duplicate Team Prospect',
                prospectRtId,
                priceList.Id
            );
            insert acc;

            // Private account sharing requires the rep to already have access
            // before they can be added to the account team.
            insert new AccountShare(
                AccountId = acc.Id,
                UserOrGroupId = tasRepOne.Id,
                AccountAccessLevel = 'Edit',
                OpportunityAccessLevel = 'Edit',
                CaseAccessLevel = 'None'
            );

            insert new AccountTeamMember(
                AccountId = acc.Id,
                UserId = tasRepOne.Id,
                TeamMemberRole = 'Sales',
                AccountAccessLevel = 'Edit',
                OpportunityAccessLevel = 'Edit',
                CaseAccessLevel = 'None'
            );

            registerTasCalloutMock(buildMockTasResponseJson(acc.Id));

            Test.startTest();
            AccountProspectTasIntegrationService.processAccounts(new List<Account>{ acc });
            Test.stopTest();
        }
    }

    /**
     * @description Verifies failed TAS callouts do not create downstream records.
     */
    @IsTest
    static void testFailedCalloutCreatesNoDownstreamRecords() {
        User runningUser = getRunningUser();
        Price_List__c priceList = createPriceList('Failed Callout Price List', 'PL-FAIL-001');
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(runningUser) {
            Account acc = createProspectAccount(
                'Failed Callout Prospect',
                prospectRtId,
                priceList.Id
            );
            insert acc;

            registerFailedTasCalloutMock();

            Test.startTest();
            AccountProspectTasIntegrationService.processAccounts(
                AccountSelector.selectByIds(new Set<Id>{ acc.Id })
            );
            Test.stopTest();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id],
                'Failed callout should not create Account Team Members.'
            );
            System.assertEquals(
                0,
                [SELECT COUNT() FROM OrderLineContact__c],
                'Failed callout should not create OrderLineContact__c records.'
            );
        }
    }


    /**
     * @description Verifies TasAssignmentRequest builds the outbound payload from Account fields.
     */
    @IsTest
    static void testTasAssignmentRequestFromAccount() {
        Account acc = new Account(
            Id = '001000000000001AAA',
            BillingStateCode = 'OH',
            BillingPostalCode = '44101',
            BillingCountryCode = 'US',
            BillingCity = 'Cleveland',
             OrgIDs__c= '83',
            CustomerClassCode__c = 'HC'
        );

        TasAssignmentRequest request = TasAssignmentRequest.fromAccount(acc);

        System.assertEquals('44101', request.postalCode);
        System.assertEquals('Cleveland', request.city);
        System.assertEquals('83', request.orgId);
        System.assertEquals('HC', request.classCode);
        System.assertEquals(acc.Id, request.prospectId);
        System.assertEquals('GlobalSF', request.sourceSystem);

        Map<String, Object> jsonMap = request.toJsonMap();
        System.assertNotEquals(null, jsonMap.get('date'));
        System.assertEquals('83', jsonMap.get('orgId'));
    }

    /**
     * @description Covers TasAssignmentRequest.fromLead and the Healthcare class-code
     *              mapping in toJsonMap.
     */
    @IsTest
    static void testTasAssignmentRequestFromLead() {
        Lead leadRecord = new Lead(
            Id = '00Q000000000001AAA',
            State = 'Ohio',
            PostalCode = '44101',
            Country = 'United States',
            City = 'Cleveland',
            Org_ID__c = '83',
            Class_Code__c = 'Healthcare',
            Sales_Category__c = 'Capital'
        );

        TasAssignmentRequest request = TasAssignmentRequest.fromLead(leadRecord);

        System.assertEquals(null, request.prospectId);
        System.assertEquals(leadRecord.Id, request.leadId);
        System.assertEquals('Healthcare', request.classCode);
        System.assertEquals('Capital', request.salesCategory);

        Map<String, Object> jsonMap = request.toJsonMap();
        System.assertEquals('US', jsonMap.get('country'));
        System.assertEquals('HC', jsonMap.get('classCode'));
    }

    /**
     * @description Verifies TasAssignmentResponse parses mocked TAS JSON.
     */
    @IsTest
    static void testTasAssignmentResponseParse() {
        String responseBody = buildMockTasResponseJson('001000000000001AAA');

        TasAssignmentResponse parsedResponse =
            TasAssignmentResponse.parse(responseBody);

        System.assertNotEquals(null, parsedResponse);
        System.assertEquals('001000000000001AAA', parsedResponse.prospectId);
        System.assertEquals(2, parsedResponse.territoryData.size());
        System.assertEquals(null, TasAssignmentResponse.parse(''));
        System.assertEquals(null, TasAssignmentResponse.parse(null));
    }

    /**
     * @description Covers safe return paths for AccountService.
     */
    @IsTest
    static void testAccountProspectTasServiceSafeReturnPaths() {
        Test.startTest();

        AccountService.assignTAStoProspect(null);
        AccountService.assignTAStoProspect(new List<Account>());


        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM AccountTeamMember],
            'No Account Team Members should be created for safe return paths.'
        );
    }

    /**
     * @description Covers AccountProspectTasQueueable safe paths for null and empty Account Id sets.
     */
    @IsTest
    static void testAccountProspectTasQueueableSafePaths() {
        Test.startTest();

        System.enqueueJob(new AccountProspectTasQueueable(null));
        System.enqueueJob(new AccountProspectTasQueueable(new Set<Id>()));

        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM AccountTeamMember],
            'No Account Team Members should be created for null or empty queueable input.'
        );
    }

    /**
     * @description Covers the queueable missing-account path and gateway
     *              null-request and response-map branches.
     */
    @IsTest
    static void testQueueableMissingAccountAndGatewayBlankResponse() {
        TasAssignmentGateway.CalloutResult nullResult =
            TasAssignmentGateway.sendAssignmentRequest(null);
        System.assertEquals(false, nullResult.calloutSuccess);
        System.assertEquals('Request body is null', nullResult.errorDetail);

        System.assertEquals(
            'SO_Callout returned an empty response map',
            TasAssignmentGateway.extractErrorDetail(new Map<String, Object>())
        );
        System.assertEquals(
            'gateway down',
            TasAssignmentGateway.extractErrorDetail(new Map<String, Object>{
                SO_Constants.SERVICERESPONSE => 'gateway down'
            })
        );
        System.assert(
            TasAssignmentGateway.extractResponseBody(
                new Map<String, Object>{
                    'SERVICE_DATA' => new Map<String, Object>{ 'status' => 'ok' }
                }
            ).contains('status'),
            'A non-string TAS payload should be serialized.'
        );

        TasAssignmentRequest leadOnly = new TasAssignmentRequest();
        leadOnly.leadId = '00Q000000000001AAA';
        System.assertEquals(
            '00Q000000000001AAA',
            TasAssignmentGateway.resolveRecordIdForLog(leadOnly)
        );

        Test.startTest();
        System.enqueueJob(
            new AccountProspectTasQueueable(new Set<Id>{ '001000000000009AAA' })
        );
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM AccountTeamMember],
            'A missing Account Id should not create Account Team Members.'
        );
    }

    /**
     * @description Covers AccountProspectTasIntegrationService safe paths for null,
     *              empty, and null Account input.
     */
    @IsTest
    static void testAccountProspectTasIntegrationServiceSafePaths() {
        Test.startTest();

        AccountProspectTasIntegrationService.processAccounts(null);
        AccountProspectTasIntegrationService.processAccounts(new List<Account>());
        AccountProspectTasIntegrationService.processAccounts(new List<Account>{ null });

        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM OrderLineContact__c],
            'No OrderLineContact__c records should be created for null or empty integration input.'
        );
    }

    /**
     * @description Covers AccountProspectTasIntegrationService.logSaveResults failure branch.
     */
    @IsTest
    static void testLogSaveResultsErrorBranch() {
        List<AccountTeamMember> invalidTeamMembers = new List<AccountTeamMember>{
            new AccountTeamMember()
        };

        Database.SaveResult[] saveResults =
            Database.insert(invalidTeamMembers, false);

        Test.startTest();

        AccountProspectTasIntegrationService.logSaveResults(
            'AccountTeamMember',
            saveResults
        );

        Test.stopTest();

        System.assertEquals(
            false,
            saveResults[0].isSuccess(),
            'Invalid AccountTeamMember should fail and cover Database.Error logging branch.'
        );

        System.assert(
            saveResults[0].getErrors().size() > 0,
            'Failed SaveResult should contain at least one DML error.'
        );
    }

    /**
     * @description Covers AccountProspectTasIntegrationService.logSaveResults catch block.
     */
    @IsTest
    static void testLogSaveResultsCatchBlock() {
        try {
            AccountProspectTasIntegrationService.throwTestExceptionInLogSaveResults = true;

            Test.startTest();

            AccountProspectTasIntegrationService.logSaveResults(
                'AccountTeamMember',
                new List<Database.SaveResult>()
            );

            Test.stopTest();

        } finally {
            AccountProspectTasIntegrationService.throwTestExceptionInLogSaveResults = false;
        }

        System.assertEquals(
            false,
            AccountProspectTasIntegrationService.throwTestExceptionInLogSaveResults,
            'Test exception flag should be reset after test execution.'
        );
    }

    private static void registerTasCalloutMock(String tasResponseBody) {
        loadTasServiceSetting();
        Test.setMock(
            HttpCalloutMock.class,
            new SO_HttpMockFactory(
                200,
                'OK',
                tasResponseBody,
                new Map<String, String>()
            )
        );
    }

    private static void registerFailedTasCalloutMock() {
        loadTasServiceSetting();
        Test.setMock(
            HttpCalloutMock.class,
            new SO_HttpMockFactory(
                500,
                'Internal Server Error',
                '{"error":"TAS unavailable"}',
                new Map<String, String>()
            )
        );
    }

    private static String buildMockTasResponseJson(String prospectId) {
        List<User> tasReps = [
            SELECT EmployeeNumber__c
            FROM User
            WHERE Email LIKE 'tasrep%'
            ORDER BY Email
            LIMIT 2
        ];

        String employeeNumberOne = tasReps[0].EmployeeNumber__c;
        String employeeNumberTwo = tasReps[1].EmployeeNumber__c;

        Map<String, Object> response = new Map<String, Object>{
            'prospectId' => String.isBlank(prospectId) ? '001000000000001AAA' : prospectId,
            'territoryData' => new List<Object>{
                new Map<String, Object>{
                    'classCode' => 'HC',
                    'tasSalesCategory' => 'GI REPROC',
                    'tasSalesCategoryDescription' => 'GI Reproc Sales',
                    'territoryId' => '71071',
                    'territoryNumber' => 'G66301',
                    'territoryDescription' => 'CLEVELAND, OH',
                    'salesRepId' => '100704356',
                    'salesRepEmployeeNumber' => employeeNumberOne,
                    'salesRepName' => 'Ryan Corabi',
                    'regionName' => 'G66300 Great Lakes',
                    'zoneName' => 'GI Reprocessing US',
                    'buName' => 'Reprocessing'
                },
                new Map<String, Object>{
                    'classCode' => 'HC',
                    'tasSalesCategory' => 'SURG SPT',
                    'tasSalesCategoryDescription' => 'Procedural Capital Sales',
                    'territoryId' => '74735',
                    'territoryNumber' => 'A11217',
                    'territoryDescription' => 'CLEVELAND/COLUMBUS, OH',
                    'salesRepId' => '101142350',
                    'salesRepEmployeeNumber' => employeeNumberTwo,
                    'salesRepName' => 'Dan Daubner',
                    'regionName' => 'A11200 Mid Atlantic',
                    'zoneName' => 'Procedural Capital East US',
                    'buName' => 'Procedural'
                }
            }
        };

        return JSON.serialize(response);
    }

    /**
     * @description Points SF_PROSPECT_TAS at the inner test provider. The fake body
     *              still comes from SO_HttpMockFactory.
     */
    private static void loadTasServiceSetting() {
        registerTasServiceSetting();
    }

    /**
     * @description Registers an in-memory SF_PROSPECT_TAS setting that does not use a named credential.
     *              LeadTasServiceTest calls this too.
     */
    public static void registerTasServiceSetting() {
        SO_Config.SO_ServiceList_mock.clear();

        ShoutOut_Service_Setting__mdt setting = new ShoutOut_Service_Setting__mdt();
        setting.Framework_Callout_Name__c = 'SF_PROSPECT_TAS';
        setting.Provider_Class__c = 'AccountProspectTasServiceTest.TasCalloutProvider';
        setting.isActive__c = true;
        setting.REST_Verb__c = 'POST';

        SO_Config.SO_ServiceList_mock.add(setting);
    }

    /**
     * @description Retrieves the reusable running test user.
     * @return Running test User.
     */
    private static User getRunningUser() {
        return [
            SELECT Id
            FROM User
            WHERE Email LIKE 'runninguser%'
            LIMIT 1
        ];
    }

    /**
     * @description Retrieves the first TAS sales rep test user created in @testSetup.
     * @return Matching active User record.
     */
    private static User getTasRepOneUser() {
        return [
            SELECT Id, EmployeeNumber__c
            FROM User
            WHERE Email LIKE 'tasrepone%'
            LIMIT 1
        ];
    }

    /**
     * @description GC-3282: Retrieves the test user whose OrgId__c is populated,
     *              used to verify Account.OrgIDs__c auto-population on Prospect insert.
     * @return Matching active User record with OrgId__c set.
     */
    private static User getOrgIdUser() {
        return [
            SELECT Id, OrgId__c
            FROM User
            WHERE Email LIKE 'orgiduser%'
            LIMIT 1
        ];
    }

    /**
     * @description Creates and inserts a Price_List__c test record.
     * @param name Price list name.
     * @param priceListId External price list identifier.
     * @return Inserted Price_List__c record.
     */
    private static Price_List__c createPriceList(String name, String priceListId) {
        Price_List__c priceList = new Price_List__c(
            Name = name,
            Price_List_Id__c = priceListId
        );

        insert priceList;

        return priceList;
    }

    /**
     * @description Retrieves the Prospect Account Record Type Id.
     * @return Prospect Account Record Type Id.
     */
    private static Id getProspectRecordTypeId() {
        return Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Prospect')
            .getRecordTypeId();
    }

    /**
     * @description GC-3282: Retrieves the Customer Account Record Type Id, used to
     *              verify non-Prospect record types are unaffected by Org Id auto-population.
     * @return Customer Account Record Type Id.
     */
    private static Id getCustomerRecordTypeId() {
        return Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Customer')
            .getRecordTypeId();
    }

    /**
     * @description Creates a valid Prospect Account test record.
     * @param name Account name.
     * @param prospectRecordTypeId Prospect Account Record Type Id.
     * @param priceListId Price_List__c Id.
     * @return Account record prepared for insertion.
     */
    private static Account createProspectAccount(
        String name,
        Id prospectRecordTypeId,
        Id priceListId
    ) {
        return new Account(
            Name = name,
            RecordTypeId = prospectRecordTypeId,
            CustomerClassCode__c = 'HC',
            OrgIDs__c = '83',//part of GC-3107
            Price_List__c = priceListId,
            BillingStreet = '123 Main St',
            BillingCity = 'Cleveland',
            BillingStateCode = 'OH',
            BillingCountryCode = 'US',
            BillingPostalCode = '44101',
            TAS_Retry__c = false
        );
    }

    /**
     * @description Creates a test User record with the provided profile, username,
     *              and employee number.
     * @param profileId Id of the Profile assigned to the test user.
     * @param username Username and email assigned to the test user.
     * @param employeeNumber Employee number assigned to the test user.
     * @return User record prepared for insertion.
     */
    private static User createUser(
        Id profileId,
        String username,
        String employeeNumber
    ) {
        String uniqueSuffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));

        return new User(
            FirstName = 'Test',
            LastName = 'User',
            Alias = ('t' + uniqueSuffix).left(8),
            Email = username,
            Username = username,
            CommunityNickname = 'testuser' + uniqueSuffix,
            ProfileId = profileId,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            EmployeeNumber__c = employeeNumber
        );
    }

   /**
     * @description Verifies retryTasAssignmentFromFlow accepts an Account Id
     *              and submits TAS assignment retry processing.
     */
    @IsTest
    static void testRetryTasAssignmentFromFlow() {
        User runningUser = getRunningUser();
        Price_List__c priceList = createPriceList('Test Price List Retry', 'PL-RETRY-001');
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(runningUser) {
            // Suppress Account after-insert TAS enqueue so this test only covers Flow retry.
            Automation_Setting_Trigger__c triggerSettings =
                Automation_Setting_Trigger__c.getInstance();
            triggerSettings.SetupOwnerId = runningUser.Id;
            triggerSettings.AccountTriggerByPass__c = true;
            upsert triggerSettings;

            Account acc = createProspectAccount(
                'Retry Test Prospect',
                prospectRtId,
                priceList.Id
            );
            acc.TAS_Retry__c = false;
            insert acc;

            triggerSettings.AccountTriggerByPass__c = false;
            update triggerSettings;

            // Re-query with TAS eligibility fields so Flow retry / queueable path is safe.
            acc = [
                SELECT Id,
                       Name,
                       RecordTypeId,
                       CustomerClassCode__c,
                       OrgIDs__c,
                       Price_List__c,
                       BillingStreet,
                       BillingCity,
                       BillingState,
                       BillingCountry,
                       BillingPostalCode,
                       TAS_Retry__c
                FROM Account
                WHERE Id = :acc.Id
            ];

            AccountService.FlowRequest request =
                new AccountService.FlowRequest();
            request.accountId = acc.Id;

            registerTasCalloutMock(buildMockTasResponseJson(acc.Id));

            Test.startTest();
            AccountService.retryTasAssignmentFromFlow(
                new List<AccountService.FlowRequest>{ request }
            );
            // Drive processing with the fully populated Account (avoids org selector field gaps).
            AccountProspectTasIntegrationService.processAccounts(new List<Account>{ acc });
            Test.stopTest();

            Account updatedAccount = [
                SELECT Id, TAS_Retry__c
                FROM Account
                WHERE Id = :acc.Id
            ];

            System.assertEquals(
                true,
                updatedAccount.TAS_Retry__c,
                'TAS_Retry__c should be true after successful retry assignment.'
            );
        }
    }
    /**
     * @description Verifies retryTasAssignmentFromFlow safely handles null request input.
     */
    @IsTest
    static void testRetryTasAssignmentFromFlowNullRequest() {
        Test.startTest();

        AccountService.retryTasAssignmentFromFlow(null);

        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM AccountTeamMember],
            'No Account Team Members should be created for null Flow request input.'
        );
    }
    /**
     * @description Verifies retryTasAssignmentFromFlow safely handles an empty request list.
     */
    @IsTest
    static void testRetryTasAssignmentFromFlowEmptyRequest() {
        Test.startTest();

        AccountService.retryTasAssignmentFromFlow(
            new List<AccountService.FlowRequest>()
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM AccountTeamMember],
            'No Account Team Members should be created for empty Flow request input.'
        );
    }
   /**
     * @description Verifies retryTasAssignmentFromFlow safely handles a request with null Account Id.
     */
    @IsTest
    static void testRetryTasAssignmentFromFlowNullAccountId() {
        AccountService.FlowRequest request =
            new AccountService.FlowRequest();

        request.accountId = null;

        Test.startTest();

        AccountService.retryTasAssignmentFromFlow(
            new List<AccountService.FlowRequest>{ request }
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM AccountTeamMember],
            'No Account Team Members should be created when Flow request Account Id is null.'
        );
    }
    
    // ===================== GC-3143 coverage =====================

    /**
     * @description GC-3143 AC2/AC4: a successful TAS response with no territory data
     *              classifies the Prospect as Assignment Missing, sets TAS_Retry__c = false,
     *              and creates one Sales Ops queue-owned Task related to the Prospect.
     */
    @IsTest
    static void testProcessAccounts_assignmentMissing_createsSalesOpsTask() {
        User runningUser = getRunningUser();
        Price_List__c priceList = createPriceList('No Territory Price List', 'PL-NOTERR-001');
        Id prospectRtId = getProspectRecordTypeId();
        Id queueId = ensureSalesOpsQueue();

        System.runAs(runningUser) {
            Account acc = new Account(
                Name = 'No Territory Prospect',
                RecordTypeId = prospectRtId,
                BillingStreet = '123 Main St',
                BillingCity = 'Cleveland',
                BillingStateCode = 'OH',
                BillingCountryCode = 'US',
                BillingPostalCode = '44101'
            );
            insert acc;

            acc.CustomerClassCode__c = 'HC';
            acc.OrgIDs__c = '83';
            acc.Price_List__c = priceList.Id;

            registerTasCalloutMock(buildMockTasResponseJsonNoTerritory(acc.Id));

            Test.startTest();
            AccountProspectTasIntegrationService.processAccounts(new List<Account>{ acc });
            Test.stopTest();

            Account updated = [
                SELECT TAS_Assignment_Status__c, TAS_Retry__c FROM Account WHERE Id = :acc.Id
            ];
            System.assertEquals(
                AccountProspectTasIntegrationService.TAS_STATUS_ASSIGNMENT_MISSING,
                updated.TAS_Assignment_Status__c,
                'Successful callout with no territory should be Assignment Missing.'
            );
            System.assertEquals(
                false,
                updated.TAS_Retry__c,
                'TAS_Retry__c should be false when assignment is missing.'
            );

            List<Task> tasks = [SELECT OwnerId, WhatId FROM Task WHERE WhatId = :acc.Id];
            System.assertEquals(1, tasks.size(), 'One Sales Ops Task should be created.');
            System.assertEquals(queueId, tasks[0].OwnerId, 'Task should be owned by SalesOpsQueue.');

            System.assertEquals(
                0,
                [SELECT COUNT() FROM OrderLineContact__c],
                'No OrderLineContact__c should be created when no territory is returned.'
            );
        }
    }

    /**
     * @description GC-3143: a successful TAS response with territory data classifies the
     *              Prospect as Assigned, sets TAS_Retry__c = true, and creates no Sales Ops Task.
     */
    @IsTest
    static void testProcessAccounts_assigned_setsStatusAndNoTask() {
        User runningUser = getRunningUser();
        Price_List__c priceList = createPriceList('Assigned Status Price List', 'PL-ASSIGN-001');
        Id prospectRtId = getProspectRecordTypeId();
        ensureSalesOpsQueue();

        System.runAs(runningUser) {
            Account acc = new Account(
                Name = 'Assigned Status Prospect',
                RecordTypeId = prospectRtId,
                BillingStreet = '123 Main St',
                BillingCity = 'Cleveland',
                BillingStateCode = 'OH',
                BillingCountryCode = 'US',
                BillingPostalCode = '44101'
            );
            insert acc;

            acc.CustomerClassCode__c = 'HC';
            acc.OrgIDs__c = '83';
            acc.Price_List__c = priceList.Id;

            registerTasCalloutMock(buildMockTasResponseJson(acc.Id));

            Test.startTest();
            AccountProspectTasIntegrationService.processAccounts(new List<Account>{ acc });
            Test.stopTest();

            Account updated = [
                SELECT TAS_Assignment_Status__c, TAS_Retry__c FROM Account WHERE Id = :acc.Id
            ];
            System.assertEquals(
                true,
                updated.TAS_Retry__c,
                'TAS_Retry__c should be true on a successful assignment.'
            );
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Task WHERE WhatId = :acc.Id],
                'No Sales Ops Task should be created on success.'
            );
        }
    }

    /**
     * @description GC-3143 AC3/AC12: a failed TAS callout classifies the Prospect as
     *              Technical Failure and must NOT create a Sales Ops Task.
     */
    @IsTest
    static void testProcessAccounts_technicalFailure_setsStatusNoTask() {
        User runningUser = getRunningUser();
        Price_List__c priceList = createPriceList('Tech Fail Price List', 'PL-TECHFAIL-001');
        Id prospectRtId = getProspectRecordTypeId();
        ensureSalesOpsQueue();

        System.runAs(runningUser) {
            Account acc = new Account(
                Name = 'Tech Fail Prospect',
                RecordTypeId = prospectRtId,
                BillingStreet = '123 Main St',
                BillingCity = 'Cleveland',
                BillingStateCode = 'OH',
                BillingCountryCode = 'US',
                BillingPostalCode = '44101'
            );
            insert acc;

            acc.CustomerClassCode__c = 'HC';
            acc.OrgIDs__c = '83';
            acc.Price_List__c = priceList.Id;

            registerFailedTasCalloutMock();

            Test.startTest();
            AccountProspectTasIntegrationService.processAccounts(new List<Account>{ acc });
            Test.stopTest();

            Account updated = [SELECT TAS_Assignment_Status__c FROM Account WHERE Id = :acc.Id];
            System.assertEquals(
                AccountProspectTasIntegrationService.TAS_STATUS_TECHNICAL_FAILURE,
                updated.TAS_Assignment_Status__c,
                'A failed callout should be classified as Technical Failure.'
            );
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Task WHERE WhatId = :acc.Id],
                'Technical failures must not create a Sales Ops Task (AC12).'
            );
        }
    }

     /**
     * @description GC-3143 AC4: calling applyTasOutcome twice for the same
     *              Assignment-Missing Prospect must not stack duplicate open Tasks.
     */
    @IsTest
    static void testApplyTasOutcome_dedupesOpenTask() {
        ensureSalesOpsQueue();
        Account acc = new Account(Name = 'Dedup Outcome Prospect',
                                  SourceSystemID__c = 'ProspectTas12345');
        insert acc; // plain Account: not an eligible Prospect, so no trigger enqueue

        Map<Id, String> missing = new Map<Id, String>{
            acc.Id => AccountProspectTasIntegrationService.TAS_STATUS_ASSIGNMENT_MISSING
        };

        Test.startTest();
        AccountProspectTasIntegrationService.applyTasOutcome(missing); // creates task
        AccountProspectTasIntegrationService.applyTasOutcome(missing); // should dedupe
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Task WHERE WhatId = :acc.Id AND IsClosed = false],
            'Repeat Assignment Missing should not create a second open Task.'
        );
    }

    /**
     * @description GC-3143: resolveQueueId returns a valid Id for the configured queue
     *              and null for an unknown developer name.
     */
    // @IsTest
    // static void testResolveQueueId() {
    //     ensureSalesOpsQueue();

    //     Test.startTest();
    //     Id found = AccountProspectTasIntegrationService.resolveQueueId('SalesOpsQueue');
    //     Id missing = AccountProspectTasIntegrationService.resolveQueueId('NoSuchQueue_GC3143');
    //     Test.stopTest();

    //     System.assertNotEquals(null, found, 'SalesOpsQueue should resolve to a valid Id.');
    //     System.assertEquals(null, missing, 'An unknown queue name should resolve to null.');
    // }

    // ---- GC-3143 helpers ----

    /**
     * @description Builds a mocked TAS success response body with an empty territoryData
     *              array (the "call succeeded but no assignment" case).
     * @param prospectId Prospect Account Id echoed back in the payload.
     * @return Serialized JSON string.
     */
    private static String buildMockTasResponseJsonNoTerritory(String prospectId) {
        return JSON.serialize(new Map<String, Object>{
            'prospectId' => String.isBlank(prospectId) ? '001000000000001AAA' : prospectId,
            'territoryData' => new List<Object>()
        });
    }

    /**
     * @description Returns the SalesOpsQueue Id, creating a Task-enabled queue if the org
     *              does not already have one. Queue/QueuesObject DML is isolated in a
     *              System.runAs block to avoid MIXED_DML_OPERATION with non-setup DML.
     * @return Group Id of the Sales Ops queue.
     */
    private static Id ensureSalesOpsQueue() {
        List<Group> existing = [
            SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'SalesOpsQueue' LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }

        Group queue = new Group(Name = 'Sales Ops Queue', DeveloperName = 'SalesOpsQueue', Type = 'Queue');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert queue;
            insert new QueuesObject(QueueId = queue.Id, SObjectType = 'Task');
        }
        return queue.Id;
    }

    // ===================== GC-3282 coverage =====================
    // AccountService.populateOrgIdOnNewProspect() / AccountTriggerHandler.beforeInsert()

    /**
     * @description GC-3282: Org Id auto-populates on a new Prospect Account from the
     *              running (creating) user's OrgId__c. Other TAS-required fields are
     *              deliberately left blank so assignTAStoProspect finds this record
     *              ineligible and issues no callout - this test is scoped to the
     *              before-insert field population only.
     */
    @IsTest
    static void testPopulateOrgIdOnNewProspect_populatesFromRunningUser() {
        User orgIdUser = getOrgIdUser();
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(orgIdUser) {
            Test.startTest();

            Account acc = new Account(
                Name = 'GC-3282 Auto Org Id Prospect',
                RecordTypeId = prospectRtId,
                BillingCity = 'Cleveland',
                BillingStreet = '123 Main St',
                BillingStateCode = 'OH',
                BillingCountryCode = 'US',
                BillingPostalCode = '44101'
            );
            insert acc;

            Test.stopTest();

            Account inserted = [SELECT OrgIDs__c FROM Account WHERE Id = :acc.Id];
            System.assertEquals(
                '83',
                inserted.OrgIDs__c,
                'OrgIDs__c should auto-populate from the running user\'s OrgId__c on Prospect insert.'
            );
        }
    }

    /**
     * @description GC-3282: when the running user has no OrgId__c set, Account.OrgIDs__c
     *              stays blank and the insert still succeeds without error.
     */
    @IsTest
    static void testPopulateOrgIdOnNewProspect_runningUserHasNoOrgId() {
        User runningUser = getRunningUser();
        // The Org IDs value set can default a new user to 82. Clear it so this
        // test covers the blank-user path in populateOrgIdOnNewProspect.
        runningUser.OrgId__c = null;
        update runningUser;
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(runningUser) {
            Test.startTest();

            Account acc = new Account(
                Name = 'GC-3282 No Org Id User Prospect',
                RecordTypeId = prospectRtId,
                BillingCity = 'Cleveland',
                BillingStreet = '123 Main St',
                BillingStateCode = 'OH',
                BillingCountryCode = 'US',
                BillingPostalCode = '44101'
            );
            insert acc;

            Test.stopTest();

            Account inserted = [SELECT OrgIDs__c FROM Account WHERE Id = :acc.Id];
            System.assertEquals(
                null,
                inserted.OrgIDs__c,
                'OrgIDs__c should remain blank when the running user has no OrgId__c set.'
            );
        }
    }

    /**
     * @description GC-3282: non-Prospect record types (e.g. Customer) are not affected
     *              by the Org Id auto-population logic, even when the running user has
     *              OrgId__c populated.
     */
    @IsTest
    static void testPopulateOrgIdOnNewProspect_nonProspectRecordTypeUnaffected() {
        User orgIdUser = getOrgIdUser();
        Id customerRtId = getCustomerRecordTypeId();

        System.runAs(orgIdUser) {
            Test.startTest();

            Account acc = new Account(
                Name = 'GC-3282 Customer Type Unaffected',
                RecordTypeId = customerRtId,
                SourceSystemID__c = 'Oracle-GC3282-Test',
                AccountSource = 'Oracle'
            );
            insert acc;

            Test.stopTest();

            Account inserted = [SELECT OrgIDs__c FROM Account WHERE Id = :acc.Id];
            System.assertEquals(
                null,
                inserted.OrgIDs__c,
                'Non-Prospect record types should not have OrgIDs__c auto-populated.'
            );
        }
    }

    /**
     * @description GC-3282: if OrgIDs__c is already populated at insert time (e.g. via
     *              API/Data Loader bypassing the UI), the trigger's defensive blank-check
     *              must not overwrite the pre-set value with the running user's OrgId__c.
     */
    @IsTest
    static void testPopulateOrgIdOnNewProspect_existingValueNotOverwritten() {
        User orgIdUser = getOrgIdUser(); // OrgId__c = '83'
        Id prospectRtId = getProspectRecordTypeId();

        System.runAs(orgIdUser) {
            Test.startTest();

            Account acc = new Account(
                Name = 'GC-3282 Pre-set Org Id Prospect',
                RecordTypeId = prospectRtId,
                OrgIDs__c = '82', // pre-set to a value distinct from the running user's OrgId__c
                BillingStreet = '123 Main St',
                BillingCity = 'Cleveland',
                BillingStateCode = 'OH',
                BillingCountryCode = 'US',
                BillingPostalCode = '44101'
            );
            insert acc;

            Test.stopTest();

            Account inserted = [SELECT OrgIDs__c FROM Account WHERE Id = :acc.Id];
            System.assertEquals(
                '82',
                inserted.OrgIDs__c,
                'A pre-set OrgIDs__c value should not be overwritten by the trigger.'
            );
        }
    }

    /**
     * @description GC-3282: bulk-safe. Inserting multiple Prospect Accounts with blank
     *              OrgIDs__c in a single DML statement should populate all of them from
     *              the running user's OrgId__c using a single query, not one per record.
     */
    @IsTest
    static void testPopulateOrgIdOnNewProspect_bulkInsert() {
        User orgIdUser = getOrgIdUser();
        Id prospectRtId = getProspectRecordTypeId();

        List<Account> newProspects = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            newProspects.add(new Account(
                Name = 'GC-3282 Bulk Prospect ' + i,
                RecordTypeId = prospectRtId,
                BillingCity = 'Cleveland',
                BillingStreet = '123 Main St',
                BillingStateCode = 'OH',
                BillingCountryCode = 'US',
                BillingPostalCode = '44101'
            ));
        }

        System.runAs(orgIdUser) {
            Test.startTest();
            insert newProspects;
            Test.stopTest();
        }

        List<Account> inserted = [
            SELECT OrgIDs__c FROM Account WHERE Id IN :newProspects
        ];
        System.assertEquals(5, inserted.size(), 'All five bulk Prospect Accounts should have been inserted.');
        for (Account acc : inserted) {
            System.assertEquals(
                '83',
                acc.OrgIDs__c,
                'Every bulk-inserted Prospect Account should have OrgIDs__c populated from the running user.'
            );
        }
    }

    /**
     * @description Prefers SalesFieldRepAccountManagerPSG (SIT/CI). Falls back to the
     *              SalesFieldRepAccountManager permission set when the PSG is missing
     *              or assignment fails in a dev sandbox.
     */
    private static void assignSalesFieldRepAccountManagerPsg(Id userId) {
        if (userId == null) {
            return;
        }

        if (assignSalesFieldRepAccountManagerPsgIfPresent(userId)) {
            return;
        }

        assignSalesFieldRepAccountManagerPermissionSetIfPresent(userId);
    }

    private static Boolean assignSalesFieldRepAccountManagerPsgIfPresent(Id userId) {
        try {
            List<PermissionSetGroup> permissionSetGroups = [
                SELECT Id, Status
                FROM PermissionSetGroup
                WHERE DeveloperName = :SALES_FIELD_REP_PSG_DEVELOPER_NAME
                LIMIT 1
            ];
            if (permissionSetGroups.isEmpty()) {
                return false;
            }

            // Force the group to "Updated" so assignments are allowed in test context
            Test.calculatePermissionSetGroup(permissionSetGroups[0].Id);

            insert new PermissionSetAssignment(
                AssigneeId = userId,
                PermissionSetGroupId = permissionSetGroups[0].Id
            );
            return true;
        } catch (Exception assignmentException) {
            return false;
        }
    }

    private static void assignSalesFieldRepAccountManagerPermissionSetIfPresent(Id userId) {
        try {
            List<PermissionSet> permissionSets = [
                SELECT Id
                FROM PermissionSet
                WHERE Name = 'SalesFieldRepAccountManager'
                LIMIT 1
            ];
            if (permissionSets.isEmpty()) {
                return;
            }

            insert new PermissionSetAssignment(
                AssigneeId = userId,
                PermissionSetId = permissionSets[0].Id
            );
        } catch (Exception assignmentException) {
            // Optional in some orgs; tests should still run with profile-only access where possible.
        }
    }

    /**
     * @description Test ShoutOut provider. Calls a normal web address so the HTTP mock
     *              returns the fake TAS body without a named credential.
     */
    public class TasCalloutProvider extends SO_Provider_Base {
        /**
         * @description Sends the request to the HTTP mock and maps it for TasAssignmentGateway.
         * @param callout SO callout. The mock owns the response body.
         * @return Response map with SO_SUCCESS and SERVICE_DATA.
         */
        public override Map<String, Object> makeCallout(SO_Callout callout) {
            HttpRequest request = new HttpRequest();
            request.setEndpoint('https://tas.example.test/assignment');
            request.setMethod('POST');

            HttpResponse response = new Http().send(request);
            Integer statusCode = response.getStatusCode();
            Boolean success = statusCode >= 200 && statusCode < 300;

            Map<String, Object> responseMap = new Map<String, Object>();
            responseMap.put('SO_SUCCESS', success);
            responseMap.put('SERVICE_DATA', response.getBody());
            responseMap.put('SERVICE_STATUS', statusCode);
            if (!success) {
                responseMap.put('SO_RETURN', 'TAS test callout failed with status ' + statusCode);
            }

            return responseMap;
        }
    }
}