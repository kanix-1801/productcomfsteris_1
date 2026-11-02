/**
 * @description Temporary copy of the shortened AccountProspectTasServiceTest.
 *              Deployed to measure coverage. Delete this class after review.
 */
@IsTest
public class AccountProspectTasServiceTestTemp {

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
                'SalesFieldRepAccountManager',
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
            Account acc = new Account(
                Name = 'Test Prospect Account',
                RecordTypeId = prospectRtId,
                BillingStreet = '123 Main St',
                BillingCity = 'Cleveland',
                BillingState = 'Ohio',
                BillingCountry = 'United States',
                BillingPostalCode = '44101',
                TAS_Retry__c = false
            );
            insert acc;
            acc.CustomerClassCode__c = 'HC';
            acc.OrgIDs__c = '83';
            acc.Price_List__c = priceList.Id;

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

            System.assertEquals(
                2,
                teamMembers.size(),
                'Two Account Team Members should be created.'
            );

            for (AccountTeamMember atm : teamMembers) {
                System.assertEquals('Sales', atm.TeamMemberRole);
                System.assertEquals('Edit', atm.AccountAccessLevel);
                System.assertEquals('Edit', atm.OpportunityAccessLevel);
                System.assertEquals('None', atm.CaseAccessLevel);
            }

            Account updated = [
                SELECT TAS_Assignment_Status__c, TAS_Retry__c
                FROM Account
                WHERE Id = :acc.Id
            ];
            System.assertEquals(
                AccountProspectTasIntegrationService.TAS_STATUS_ASSIGNED,
                updated.TAS_Assignment_Status__c
            );
            System.assertEquals(true, updated.TAS_Retry__c);
            System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId = :acc.Id]);
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

            System.assertEquals(
                2,
                [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id],
                'Only one additional Account Team Member should be inserted when one already exists.'
            );
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

            Account updated = [SELECT TAS_Assignment_Status__c FROM Account WHERE Id = :acc.Id];
            System.assertEquals(
                AccountProspectTasIntegrationService.TAS_STATUS_TECHNICAL_FAILURE,
                updated.TAS_Assignment_Status__c
            );
            System.assertEquals(0, [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id]);
            System.assertEquals(0, [SELECT COUNT() FROM OrderLineContact__c]);
            System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId = :acc.Id]);
        }
    }

    /**
     * @description Verifies TasAssignmentRequest and TasAssignmentResponse payload mapping.
     */
    @IsTest
    static void testTasAssignmentRequestFromAccount() {
        Account acc = new Account(
            Id = '001000000000001AAA',
            BillingState = 'Ohio',
            BillingPostalCode = '44101',
            BillingCountry = 'United States',
            BillingCity = 'Cleveland',
             OrgIDs__c= '83',
            CustomerClassCode__c = 'HC'
        );

        TasAssignmentRequest request = TasAssignmentRequest.fromAccount(acc);

        System.assertEquals('Ohio', request.state);
        System.assertEquals('44101', request.postalCode);
        System.assertEquals('United States', request.country);
        System.assertEquals('Cleveland', request.city);
        System.assertEquals('83', request.orgId);
        System.assertEquals('HC', request.classCode);
        System.assertEquals(acc.Id, request.prospectId);
        System.assertEquals('GlobalSF', request.sourceSystem);

        Map<String, Object> jsonMap = request.toJsonMap();
        System.assertNotEquals(null, jsonMap.get('date'));
        System.assertEquals('83', jsonMap.get('orgId'));

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
        TasAssignmentRequest leadRequest = TasAssignmentRequest.fromLead(leadRecord);
        System.assertEquals(leadRecord.Id, leadRequest.leadId);
        System.assertEquals(null, leadRequest.prospectId);
        Map<String, Object> leadJson = leadRequest.toJsonMap();
        System.assertEquals('US', leadJson.get('country'));
        System.assertEquals('HC', leadJson.get('classCode'));

        TasAssignmentResponse parsed = TasAssignmentResponse.parse(buildMockTasResponseJson(acc.Id));
        System.assertEquals(2, parsed.territoryData.size());
        System.assertEquals(null, TasAssignmentResponse.parse(null));
        System.assertEquals(null, TasAssignmentResponse.parse(''));
    }

    /**
     * @description Covers null, empty, and logging guard branches that do not create records.
     */
    @IsTest
    static void testGuardPathsCreateNoRecords() {
        AccountService.assignTAStoProspect(null);
        AccountService.assignTAStoProspect(new List<Account>());
        AccountProspectTasIntegrationService.processAccounts(null);
        AccountProspectTasIntegrationService.processAccounts(new List<Account>());
        AccountProspectTasIntegrationService.processAccounts(new List<Account>{ null });
        AccountService.retryTasAssignmentFromFlow(null);
        AccountService.retryTasAssignmentFromFlow(new List<AccountService.FlowRequest>());
        AccountService.FlowRequest blankRequest = new AccountService.FlowRequest();
        AccountService.retryTasAssignmentFromFlow(new List<AccountService.FlowRequest>{ blankRequest });

        TasAssignmentGateway.CalloutResult nullResult = TasAssignmentGateway.sendAssignmentRequest(null);
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
            TasAssignmentGateway.extractResponseBody(new Map<String, Object>{
                'SERVICE_DATA' => new Map<String, Object>{ 'status' => 'ok' }
            }).contains('status')
        );
        TasAssignmentRequest leadOnly = new TasAssignmentRequest();
        leadOnly.leadId = '00Q000000000001AAA';
        System.assertEquals('00Q000000000001AAA', TasAssignmentGateway.resolveRecordIdForLog(leadOnly));

        Database.SaveResult[] saveResults = Database.insert(new List<AccountTeamMember>{ new AccountTeamMember() }, false);
        AccountProspectTasIntegrationService.logSaveResults('AccountTeamMember', saveResults);
        System.assertEquals(false, saveResults[0].isSuccess());

        AccountProspectTasIntegrationService.throwTestExceptionInLogSaveResults = true;
        try {
            AccountProspectTasIntegrationService.logSaveResults('AccountTeamMember', new List<Database.SaveResult>());
        } finally {
            AccountProspectTasIntegrationService.throwTestExceptionInLogSaveResults = false;
        }

        Test.startTest();
        System.enqueueJob(new AccountProspectTasQueueable(null));
        System.enqueueJob(new AccountProspectTasQueueable(new Set<Id>()));
        System.enqueueJob(new AccountProspectTasQueueable(new Set<Id>{ '001000000000009AAA' }));
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM AccountTeamMember]);
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
     * @description Loads the org SF_PROSPECT_TAS ShoutOut setting into the test mock list.
     *              QA uses provider SO_Provider_Simple. A hand-built SO_Provider_Salesforce
     *              record never reaches the HTTP mock.
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
            BillingState = 'Ohio',
            BillingCountry = 'United States',
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
            System.assertEquals(
                2,
                [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :acc.Id],
                'Retry flow should create Account Team Members.'
            );
        }
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
                BillingState = 'Ohio',
                BillingCountry = 'United States',
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
     * @description GC-3282: copies the running user's Org Id onto blank Prospect
     *              accounts, including a bulk insert, and leaves Customer records,
     *              pre-set values, and a user with no Org Id unchanged.
     */
    @IsTest
    static void testPopulateOrgIdOnNewProspect() {
        User orgIdUser = getOrgIdUser();
        User runningUser = getRunningUser();
        Id prospectRtId = getProspectRecordTypeId();
        Id customerRtId = getCustomerRecordTypeId();

        Account customer = new Account(
            Name = 'GC-3282 Customer Type Unaffected',
            RecordTypeId = customerRtId,
            SourceSystemID__c = 'Oracle-GC3282-Test',
            AccountSource = 'Oracle'
        );
        Account preset = prospectShell('GC-3282 Pre-set Org Id Prospect', prospectRtId);
        preset.OrgIDs__c = '82';
        List<Account> bulkProspects = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            bulkProspects.add(prospectShell('GC-3282 Bulk Prospect ' + i, prospectRtId));
        }

        System.runAs(orgIdUser) {
            insert new List<Account>{ customer, preset };
            insert bulkProspects;
        }

        runningUser.OrgId__c = null;
        update runningUser;
        Account blankUserProspect = prospectShell('GC-3282 No Org Id User Prospect', prospectRtId);
        System.runAs(runningUser) {
            insert blankUserProspect;
        }

        System.assertEquals(null, [SELECT OrgIDs__c FROM Account WHERE Id = :customer.Id].OrgIDs__c);
        System.assertEquals('82', [SELECT OrgIDs__c FROM Account WHERE Id = :preset.Id].OrgIDs__c);
        System.assertEquals(null, [SELECT OrgIDs__c FROM Account WHERE Id = :blankUserProspect.Id].OrgIDs__c);
        for (Account acc : [SELECT OrgIDs__c FROM Account WHERE Id IN :bulkProspects]) {
            System.assertEquals('83', acc.OrgIDs__c);
        }
    }

    private static Account prospectShell(String name, Id prospectRecordTypeId) {
        return new Account(
            Name = name,
            RecordTypeId = prospectRecordTypeId,
            BillingCity = 'Cleveland',
            BillingStreet = '123 Main St',
            BillingState = 'Ohio',
            BillingCountry = 'United States',
            BillingPostalCode = '44101'
        );
    }
}