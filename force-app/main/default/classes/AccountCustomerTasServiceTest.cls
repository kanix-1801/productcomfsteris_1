/**
 * @author Akash Dahinde
 * @date 27-08-2026
 * @description Test class for Customer Account TAS integration.
 *              Covers:
 *              - Account Customer TAS insert processing
 *              - Account Customer TAS update processing
 *              - AccountCustomerTasQueueable
 *              - AccountCustomerTasIntegrationService
 *              - AccountCustomerTasGateway
 *              - TasCustomerAccountRequest
     *              - TasCustomerAccountResponse
 *              - Healthcare Sales User resolution
 *              - AccountTeamMember creation
 *              - Duplicate prevention
 *              - Callout success/failure
 *              - Empty TAS response
 *              - No territory response
 *              - Invalid Employee Number
 *              - Safe return paths
 *              - DML failure logging
 */
@IsTest
public class AccountCustomerTasServiceTest {

    private static final String HEALTHCARE_SALES_PROFILE_NAME = 'Healthcare Sales';
    private static final String TEAM_MEMBER_ROLE = 'Sales';
    private static final String ASSIGNMENT_TYPE = 'Oracle Assigned';
    private static final String ACCOUNT_ACCESS_LEVEL = 'Edit';

    /**
     * @description Creates:
     *              1. Running test User using the current test execution profile.
     *              2. Two active TAS Sales Rep Users using Healthcare Sales profile.
     *
     *              EmployeeNumber__c and FederationIdentifier contain the same
     *              value so TAS response employee numbers resolve to Salesforce Users.
     */
    @testSetup
    static void setupData() {
        Id runningUserProfileId = UserInfo.getProfileId();
        Profile healthcareSalesProfile = [SELECT Id FROM Profile WHERE Name = :HEALTHCARE_SALES_PROFILE_NAME LIMIT 1];

        Long uniqueSeed = System.currentTimeMillis();
        String tasEmployeeNumberOne = 'CTAS' + uniqueSeed + 'A';
        String tasEmployeeNumberTwo = 'CTAS' + uniqueSeed + 'B';

        User runningUser = createUser(
            runningUserProfileId,
            'custrunninguser' + uniqueSeed + '@test.com',
            'CRUN' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );
        
        User tasRepOne = createUser(
            healthcareSalesProfile.Id,
            'custtasrepone' + uniqueSeed + '@test.com',
            tasEmployeeNumberOne
        );

        User tasRepTwo = createUser(
            healthcareSalesProfile.Id,
            'custtasreptwo' + uniqueSeed + '@test.com',
            tasEmployeeNumberTwo
        );

        insert new List<User>{
            runningUser,
            tasRepOne,
            tasRepTwo
        };

        TestDataFactory.assignSalesCustomerOpsPermissionSetGroup(runningUser.Id);
    }

    /**
     * @description AC - Customer Account insert.
     *              Verifies a valid Oracle Customer Account causes TAS processing
     *              and creates Account Team Members.
     */
    @IsTest
    static void testAfterInsertCreatesAccountTeamMembers() {
        User runningUser = getRunningUser();
        Id customerRecordTypeId = getCustomerRecordTypeId();
        String suffix = uniqueSuffix();

        System.runAs(runningUser) {
            registerTasCalloutMock(buildMockTasResponseJson(null));

            Test.startTest();

            Account accountRecord = createCustomerAccount(
                'Customer TAS Insert Test',
                customerRecordTypeId,
                suffix
            );

            insert accountRecord;

            Test.stopTest();

            List<AccountTeamMember> teamMembers = [SELECT Id, AccountId, UserId, TeamMemberRole, AssignmentType__c, AccountAccessLevel FROM AccountTeamMember WHERE AccountId = :accountRecord.Id];

            System.assertEquals(
                2,
                teamMembers.size(),
                'Two TAS Account Team Members should be created.'
            );

            for (AccountTeamMember teamMember : teamMembers) {
                System.assertEquals(
                    TEAM_MEMBER_ROLE,
                    teamMember.TeamMemberRole,
                    'Team Member Role must be Sales.'
                );

                System.assertEquals(
                    ASSIGNMENT_TYPE,
                    teamMember.AssignmentType__c,
                    'Assignment Type must identify TAS/Oracle assignment.'
                );

                System.assertEquals(
                    ACCOUNT_ACCESS_LEVEL,
                    teamMember.AccountAccessLevel,
                    'TAS rep must receive Edit access.'
                );
            }

            System.assertEquals(
                0,
                [SELECT COUNT() FROM OrderLineContact__c],
                'Customer realtime TAS processing must not create OrderLineContact__c records.'
            );
        }
    }

    /**
     * @description Verifies Customer update processing.
     *
     *              Account is intentionally inserted without OracleAddressId__c
     *              so after-insert Customer TAS processing does not occur.
     *
     *              OracleAddressId__c is then populated to make the Account
     *              eligible through assignTAStoCustomerUpdate().
     */
    @IsTest
    static void testAfterUpdateCreatesAccountTeamMembers() {
        User runningUser = getRunningUser();
        Id customerRecordTypeId = getCustomerRecordTypeId();
        String suffix = uniqueSuffix();

        System.runAs(runningUser) {
            Account accountRecord = createCustomerAccount(
                'Customer TAS Update Test',
                customerRecordTypeId,
                suffix
            );

            accountRecord.OracleAddressId__c = null;

            insert accountRecord;

            System.assertEquals(
                0,
                [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :accountRecord.Id],
                'No TAS team member should exist before Customer becomes eligible.'
            );

            registerTasCalloutMock(
                buildMockTasResponseJson(accountRecord.Id)
            );

            Test.startTest();

            accountRecord.OracleAddressId__c = 'ORADDR' + suffix;

            update accountRecord;

            Test.stopTest();

            List<AccountTeamMember> teamMembers = [SELECT Id, UserId, TeamMemberRole, AssignmentType__c, AccountAccessLevel FROM AccountTeamMember WHERE AccountId = :accountRecord.Id];

            System.assertEquals(
                2,
                teamMembers.size(),
                'Two TAS Account Team Members should be created after relevant Customer update.'
            );
        }
    }

    /**
     * @description Verifies changing an irrelevant Customer field does not
     *              enqueue Customer TAS processing.
     */
    @IsTest
    static void testIrrelevantCustomerUpdateDoesNotCreateAdditionalTeamMembers() {
        User runningUser = getRunningUser();
        Id customerRecordTypeId = getCustomerRecordTypeId();
        String suffix = uniqueSuffix();

        System.runAs(runningUser) {
            Account accountRecord = createCustomerAccount(
                'Customer Irrelevant Update Test',
                customerRecordTypeId,
                suffix
            );

            accountRecord.OracleAddressId__c = null;

            insert accountRecord;

            Test.startTest();

            accountRecord.Description =
                'Irrelevant field update';

            update accountRecord;

            Test.stopTest();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :accountRecord.Id],
                'Irrelevant Customer field changes must not run TAS processing.'
            );
        }
    }

    /**
     * @description Verifies AccountCustomerTasIntegrationService directly.
     */
    @IsTest
    static void testIntegrationServiceProcessesMockedTasResponse() {
        User runningUser = getRunningUser();
        Id customerRecordTypeId = getCustomerRecordTypeId();
        String suffix = uniqueSuffix();

        System.runAs(runningUser) {
            registerTasCalloutMock(
                buildMockTasResponseJson(null)
            );

            Account accountRecord = createCustomerAccount(
                'Customer Integration Service Test',
                customerRecordTypeId,
                suffix
            );

            insert accountRecord;

            Test.startTest();

            AccountCustomerTasIntegrationService.processAccounts(
                AccountSelector.selectCustomerAccountsForTasByIds(
                    new Set<Id>{ accountRecord.Id }
                )
            );

            Test.stopTest();

            System.assertEquals(
                2,
                [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :accountRecord.Id],
                'Integration service should create two TAS Account Team Members.'
            );
        }
    }

    /**
     * @description Verifies existing TAS Account Team Member records
     *              are not duplicated.
     */
    @IsTest
    static void testDuplicateAccountTeamMembersAreSkipped() {
        User runningUser = getRunningUser();
        User tasRepOne = getTasRepOneUser();
        Id customerRecordTypeId = getCustomerRecordTypeId();
        String suffix = uniqueSuffix();

        System.runAs(runningUser) {
            Account accountRecord = createCustomerAccount(
                'Customer Duplicate Team Test',
                customerRecordTypeId,
                suffix
            );

            accountRecord.OracleAddressId__c = null;

            insert accountRecord;

            insert new AccountTeamMember(
                AccountId = accountRecord.Id,
                UserId = tasRepOne.Id,
                TeamMemberRole = TEAM_MEMBER_ROLE,
                AssignmentType__c = ASSIGNMENT_TYPE,
                AccountAccessLevel = ACCOUNT_ACCESS_LEVEL
            );

            registerTasCalloutMock(
                buildMockTasResponseJson(accountRecord.Id)
            );

            Test.startTest();

            accountRecord.OracleAddressId__c =
                'ORADDR' + suffix;

            update accountRecord;

            Test.stopTest();

            List<AccountTeamMember> teamMembers = [SELECT Id, UserId FROM AccountTeamMember WHERE AccountId = :accountRecord.Id];

            System.assertEquals(
                2,
                teamMembers.size(),
                'Existing TAS Account Team Member should be reused and only missing member inserted.'
            );

            Set<Id> userIds = new Set<Id>();

            for (AccountTeamMember teamMember : teamMembers) {
                userIds.add(teamMember.UserId);
            }

            System.assertEquals(
                2,
                userIds.size(),
                'Duplicate AccountTeamMember records must not be created for the same User.'
            );
        }
    }

    /**
     * @description Verifies active Healthcare Sales Users resolve by EmployeeNumber__c.
     */
    @IsTest
    static void testHealthcareSalesUsersResolveByEmployeeNumber() {
        User tasRepOne = [SELECT Id, EmployeeNumber__c, IsActive, Profile.Name FROM User WHERE Email LIKE 'custtasrepone%' LIMIT 1];

        System.assertEquals(
            true,
            tasRepOne.IsActive,
            'TAS rep must be active.'
        );

        System.assertEquals(
            HEALTHCARE_SALES_PROFILE_NAME,
            tasRepOne.Profile.Name,
            'TAS rep must use Healthcare Sales profile.'
        );

        Map<String, User> resolvedUsers =
            UserSelector.selectActiveUsersByEmployeeNumber(
                new Set<String>{
                    tasRepOne.EmployeeNumber__c
                }
            );

        System.assertEquals(
            1,
            resolvedUsers.size(),
            'One Healthcare Sales User should resolve.'
        );

        System.assertEquals(
            tasRepOne.Id,
            resolvedUsers.get(
                tasRepOne.EmployeeNumber__c
            ).Id,
            'Resolved Employee Number must map to the correct Salesforce User.'
        );
    }

    /**
     * @description Verifies multiple Healthcare Sales Users resolve correctly.
     */
    @IsTest
    static void testMultipleHealthcareSalesUsersResolveByEmployeeNumber() {
        List<User> tasReps = [SELECT Id, EmployeeNumber__c FROM User WHERE Email LIKE 'custtasrep%' ORDER BY Email LIMIT 2];

        Set<String> employeeNumbers =
            new Set<String>();

        for (User tasRep : tasReps) {
            employeeNumbers.add(
                tasRep.EmployeeNumber__c
            );
        }

        Map<String, User> resolvedUsers =
            UserSelector.selectActiveUsersByEmployeeNumber(
                employeeNumbers
            );

        System.assertEquals(
            2,
            resolvedUsers.size(),
            'Both valid Healthcare Sales Users must resolve.'
        );
    }

    /**
     * @description Negative test for invalid TAS Employee Number.
     */
    @IsTest
    static void testUnknownEmployeeNumberReturnsNoUser() {
        Map<String, User> resolvedUsers =
            UserSelector.selectActiveUsersByEmployeeNumber(
                new Set<String>{
                    'INVALID_EMPLOYEE_NUMBER'
                }
            );

        System.assertEquals(
            0,
            resolvedUsers.size(),
            'Invalid Employee Number must not resolve a User.'
        );
    }

    /**
     * @description Covers null and empty employee number selector inputs.
     */
    @IsTest
    static void testUserSelectorSafeReturnPaths() {
        System.assertEquals(
            0,
            UserSelector.selectActiveUsersByEmployeeNumber(null).size(),
            'Null Employee Number input should return empty map.'
        );

        System.assertEquals(
            0,
            UserSelector.selectActiveUsersByEmployeeNumber(new Set<String>()).size(),
            'Empty Employee Number input should return empty map.'
        );
    }

    /**
     * @description Verifies failed TAS callout creates no Account Team Members.
     */
    @IsTest
    static void testFailedCalloutCreatesNoDownstreamRecords() {
        User runningUser = getRunningUser();
        Id customerRecordTypeId = getCustomerRecordTypeId();
        String suffix = uniqueSuffix();

        System.runAs(runningUser) {
            Account accountRecord = createCustomerAccount(
                'Customer Failed Callout Test',
                customerRecordTypeId,
                suffix
            );

            accountRecord.OracleAddressId__c = null;

            insert accountRecord;

            registerFailedTasCalloutMock();

            Test.startTest();

            accountRecord.OracleAddressId__c =
                'ORADDR' + suffix;

            update accountRecord;

            Test.stopTest();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :accountRecord.Id],
                'Failed TAS callout must not create Account Team Members.'
            );
        }
    }

    /**
     * @description Verifies HTTP 200 with empty response body is treated
     *              as TAS processing failure.
     */
    @IsTest
    static void testEmptyCalloutResponseCreatesNoTeamMembers() {
        User runningUser = getRunningUser();
        Id customerRecordTypeId = getCustomerRecordTypeId();
        String suffix = uniqueSuffix();

        System.runAs(runningUser) {
            Account accountRecord = createCustomerAccount(
                'Customer Empty Response Test',
                customerRecordTypeId,
                suffix
            );

            accountRecord.OracleAddressId__c = null;

            insert accountRecord;

            registerEmptyTasCalloutMock();

            Test.startTest();

            accountRecord.OracleAddressId__c =
                'ORADDR' + suffix;

            update accountRecord;

            Test.stopTest();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :accountRecord.Id],
                'Empty TAS response must not create Account Team Members.'
            );
        }
    }

    /**
     * @description Verifies successful TAS callout having no territory assignments
     *              does not create Account Team Members.
     */
    @IsTest
    static void testNoTerritoryCreatesNoAccountTeamMembers() {
        User runningUser = getRunningUser();
        Id customerRecordTypeId = getCustomerRecordTypeId();
        String suffix = uniqueSuffix();

        System.runAs(runningUser) {
            Account accountRecord = createCustomerAccount(
                'Customer No Territory Test',
                customerRecordTypeId,
                suffix
            );

            accountRecord.OracleAddressId__c = null;

            insert accountRecord;

            registerTasCalloutMock(
                buildMockTasResponseJsonNoTerritory(
                    accountRecord.Id
                )
            );

            Test.startTest();

            accountRecord.OracleAddressId__c =
                'ORADDR' + suffix;

            update accountRecord;

            Test.stopTest();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :accountRecord.Id],
                'No TAS territory data must not create Account Team Members.'
            );
        }
    }

    /**
     * @description Verifies TAS response containing invalid Employee Number
     *              does not create Account Team Members for unresolved User.
     */
    @IsTest
    static void testInvalidEmployeeNumberCreatesNoAccountTeamMember() {
        User runningUser = getRunningUser();
        Id customerRecordTypeId = getCustomerRecordTypeId();
        String suffix = uniqueSuffix();

        System.runAs(runningUser) {
            Account accountRecord = createCustomerAccount(
                'Customer Invalid Employee Test',
                customerRecordTypeId,
                suffix
            );

            accountRecord.OracleAddressId__c = null;

            insert accountRecord;

            registerTasCalloutMock(
                buildInvalidEmployeeResponseJson(
                    accountRecord.Id
                )
            );

            Test.startTest();

            accountRecord.OracleAddressId__c =
                'ORADDR' + suffix;

            update accountRecord;

            Test.stopTest();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :accountRecord.Id],
                'Invalid TAS Employee Number must not create Account Team Member.'
            );
        }
    }

    /**
     * @description Verifies TasCustomerAccountResponse parsing.
     *
     * Current response DTO continues using prospectId based on
     * the provided TasCustomerAccountResponse test contract.
     */
    @IsTest
    static void testTasCustomerAccountResponseParse() {
        String responseBody =
            buildMockTasResponseJson(
                '001000000000001AAA'
            );

        TasCustomerAccountResponse parsedResponse = TasCustomerAccountResponse.parse(
                responseBody
            );

        System.assertNotEquals(
            null,
            parsedResponse,
            'Valid TAS response must deserialize.'
        );

        System.assertEquals(
            '001000000000001AAA',
            parsedResponse.prospectId
        );

        System.assertNotEquals(
            null,
            parsedResponse.territoryData
        );

        System.assertEquals(
            2,
            parsedResponse.territoryData.size()
        );

        TasAccountResponseItem firstItem =
            parsedResponse.territoryData[0];

        System.assertEquals(
            'HC',
            firstItem.classCode
        );

        System.assertNotEquals(
            null,
            firstItem.salesRepEmployeeNumber
        );

        System.assertNotEquals(
            null,
            firstItem.territoryId
        );

        System.assertEquals(
            null,
            TasCustomerAccountResponse.parse('')
        );

        System.assertEquals(
            null,
            TasCustomerAccountResponse.parse(null)
        );
    }

    /**
     * @description Covers AccountService null and empty Customer paths.
     */
    @IsTest
    static void testAccountServiceCustomerSafeReturnPaths() {
        Test.startTest();

        AccountService.assignTAStoCustomer(null);
        AccountService.assignTAStoCustomer(new List<Account>());

        AccountService.assignTAStoCustomerUpdate(
            null,
            null
        );

        AccountService.assignTAStoCustomerUpdate(
            new List<Account>(),
            null
        );

        AccountService.assignTAStoCustomerUpdate(
            new List<Account>{
                new Account(
                    Name = 'Safe Return Customer'
                )
            },
            new Map<Id, Account>()
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM AccountTeamMember],
            'Safe return paths must not create Account Team Members.'
        );
    }

    /**
     * @description Verifies a non-Customer Account is not processed
     *              by Customer TAS service.
     */
    @IsTest
    static void testNonCustomerAccountIsNotEligible() {
        Id prospectRecordTypeId =
            Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('Prospect')
                .getRecordTypeId();

        Account prospectAccount =
            new Account(
                Name = 'Not Customer',
                RecordTypeId = prospectRecordTypeId,
                CustomerClassCode__c = 'Healthcare',
                OrgIDs__c = '82',
                BillingStreet = '123 Main St',
                BillingCity = 'Cleveland',
                BillingState = 'Ohio',
                BillingCountry = 'United States',
                BillingPostalCode = '44101'
            );

        Test.startTest();

        AccountService.assignTAStoCustomer(
            new List<Account>{
                prospectAccount
            }
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM AccountTeamMember],
            'Prospect Account must not be processed by Customer TAS logic.'
        );
    }

    /**
     * @description Covers Customer TAS Queueable null and empty inputs.
     */
    @IsTest
    static void testAccountCustomerTasQueueableSafePaths() {
        Test.startTest();

        System.enqueueJob(
            new AccountCustomerTasQueueable(null)
        );

        System.enqueueJob(
            new AccountCustomerTasQueueable(
                new Set<Id>()
            )
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM AccountTeamMember],
            'Queueable null and empty inputs must not create team members.'
        );
    }

    /**
     * @description Covers Integration Service safe return paths.
     */
    @IsTest
    static void testAccountCustomerTasIntegrationServiceSafePaths() {
        Test.startTest();

        AccountCustomerTasIntegrationService.processAccounts(
            null
        );

        AccountCustomerTasIntegrationService.processAccounts(
            new List<Account>()
        );

        AccountCustomerTasIntegrationService.processAccounts(
            new List<Account>{
                null
            }
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM AccountTeamMember],
            'Null and empty Integration Service inputs must not create records.'
        );
    }

    /**
     * @description Covers Database.SaveResult error logging branch.
     */
    @IsTest
    static void testLogSaveResultsErrorBranch() {
        List<AccountTeamMember> invalidTeamMembers =
            new List<AccountTeamMember>{
                new AccountTeamMember()
            };

        Database.SaveResult[] saveResults =
            Database.insert(
                invalidTeamMembers,
                false
            );

        Test.startTest();

        AccountCustomerTasIntegrationService.logSaveResults(
            'AccountTeamMember',
            saveResults
        );

        Test.stopTest();

        System.assertEquals(
            false,
            saveResults[0].isSuccess(),
            'Invalid AccountTeamMember must fail.'
        );

        System.assert(
            saveResults[0].getErrors().size() > 0,
            'Failed SaveResult must contain Database.Error.'
        );
    }

    // =========================================================
    // AccountCustomerTasGateway
    // =========================================================

    /**
     * @description Verifies successful Customer TAS Gateway callout.
     */
    @IsTest
    static void sendCustomerAccountRequestSuccess() {
        String tasResponseBody =
            buildMockTasResponseJson(
                '001000000000001AAA'
            );

        registerTasCalloutMock(
            tasResponseBody
        );

        TasCustomerAccountRequest requestBody =
            buildSampleRequest();

        Test.startTest();

        AccountCustomerTasGateway.CalloutResult result =AccountCustomerTasGateway.sendCustomerAccountRequest(requestBody);

        Test.stopTest();

        System.assertEquals(
            true,
            result.calloutSuccess
        );

        System.assertNotEquals(
            null,
            result.serviceResponseMap
        );

        System.assertEquals(
            200,
            (Integer) result.serviceResponseMap.get(
                'SERVICE_STATUS'
            )
        );

        System.assertEquals(
            true,
            (Boolean) result.serviceResponseMap.get(
                'SO_SUCCESS'
            )
        );

        System.assertEquals(
            tasResponseBody,
            (String) result.serviceResponseMap.get(
                'SERVICE_DATA'
            )
        );

        System.assertNotEquals(
            null,
            result.parsedResponse
        );

        System.assertEquals(
            2,
            result.parsedResponse.territoryData.size()
        );
    }

    /**
     * @description Verifies null request body is safely rejected.
     */
    @IsTest
    static void sendCustomerAccountRequestNullRequestBody() {
        Test.startTest();

        AccountCustomerTasGateway.CalloutResult result = AccountCustomerTasGateway.sendCustomerAccountRequest(null);

        Test.stopTest();

        System.assertEquals(
            false,
            result.calloutSuccess
        );

        System.assertEquals(
            'Request body is null',
            result.errorDetail
        );

        System.assertEquals(
            null,
            result.serviceResponseMap
        );
    }

    /**
     * @description Verifies HTTP 500 callout failure.
     */
    @IsTest
    static void sendCustomerAccountRequestHttpFailure() {
        registerFailedTasCalloutMock();

        TasCustomerAccountRequest requestBody =
            buildSampleRequest();

        Test.startTest();

        AccountCustomerTasGateway.CalloutResult result =AccountCustomerTasGateway.sendCustomerAccountRequest(requestBody);

        Test.stopTest();

        System.assertEquals(
            false,
            result.calloutSuccess
        );

        System.assertNotEquals(
            null,
            result.serviceResponseMap
        );

        System.assertEquals(
            false,
            (Boolean) result.serviceResponseMap.get(
                'SO_SUCCESS'
            )
        );

        System.assertEquals(
            500,
            (Integer) result.serviceResponseMap.get(
                'SERVICE_STATUS'
            )
        );

        System.assertNotEquals(
            null,
            result.errorDetail
        );
    }

    /**
     * @description Covers the exact real-world issue where Boomi
     *              returns HTTP 200 with zero-byte response body.
     */
    @IsTest
    static void sendCustomerAccountRequestEmptyResponseBody() {
        registerEmptyTasCalloutMock();

        TasCustomerAccountRequest requestBody =
            buildSampleRequest();

        Test.startTest();

        AccountCustomerTasGateway.CalloutResult result =
            AccountCustomerTasGateway.sendCustomerAccountRequest( requestBody );

        Test.stopTest();

        System.assertEquals(
            false,
            result.calloutSuccess
        );

        System.assertEquals(
            true,
            (Boolean) result.serviceResponseMap.get(
                'SO_SUCCESS'
            )
        );

        System.assertEquals(
            200,
            (Integer) result.serviceResponseMap.get(
                'SERVICE_STATUS'
            )
        );

        System.assertEquals(
            '',
            (String) result.serviceResponseMap.get(
                'SERVICE_DATA'
            )
        );

        System.assertEquals(
            null,
            result.parsedResponse
        );

        System.assertEquals(
            'TAS response body was empty or could not be parsed',
            result.errorDetail
        );
    }

    /**
     * @description Verifies SERVICE_DATA takes precedence.
     */
    @IsTest
    static void extractResponseBodyPrefersServiceData() {
        Map<String, Object> responseMap =
            new Map<String, Object>{
                'SERVICE_DATA' =>
                    '{"prospectId":"001","territoryData":[]}',
                'SERVICERESPONSE' =>
                    'fallback'
            };

        String responseBody = AccountCustomerTasGateway.extractResponseBody(responseMap);

        System.assertEquals(
            '{"prospectId":"001","territoryData":[]}',
            responseBody
        );
    }

    /**
     * @description Verifies SERVICERESPONSE fallback.
     */
    @IsTest
    static void extractResponseBodyFallsBackToServiceResponse() {
        Map<String, Object> responseMap =
            new Map<String, Object>{
                'SERVICERESPONSE' =>
                    '{"prospectId":"001","territoryData":[]}'
            };

        String responseBody = AccountCustomerTasGateway.extractResponseBody(responseMap);

        System.assertEquals(
            '{"prospectId":"001","territoryData":[]}',
            responseBody
        );
    }

    /**
     * @description Verifies SO_SUCCESS evaluation.
     */
    @IsTest
    static void isSuccessfulEvaluatesSoSuccessFlag() {
        System.assertEquals(
            true,
            AccountCustomerTasGateway.isSuccessful(new Map<String, Object>{
                        'SO_SUCCESS' => true
                    }
                )
        );

        System.assertEquals(
            false,
            AccountCustomerTasGateway.isSuccessful(
                    new Map<String, Object>{
                        'SO_SUCCESS' => false
					}
                )
        );

        System.assertEquals(
            false,
            AccountCustomerTasGateway.isSuccessful( null )
        );
    }

    /**
     * @description Verifies Customer request accountId is used for logging.
     */
    @IsTest
    static void resolveAccountIdForLogUsesAccountId() {
        TasCustomerAccountRequest requestBody =
            buildSampleRequest();

        System.assertEquals(
            '001000000000001AAA',
            AccountCustomerTasGateway.resolveAccountIdForLog(requestBody)
        );
    }

    // =========================================================
    // Test Helpers
    // =========================================================

    /**
     * @description Registers successful TAS HTTP mock.
     */
    private static void registerTasCalloutMock(
        String tasResponseBody
    ) {
        SO_Config.SO_ServiceList_mock.add(
            defaultCustomerTasServiceSetting()
        );

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

    /**
     * @description Registers HTTP 500 TAS mock.
     */
    private static void registerFailedTasCalloutMock() {
        SO_Config.SO_ServiceList_mock.add(
            defaultCustomerTasServiceSetting()
        );

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

    /**
     * @description Registers HTTP 200 with empty response.
     */
    private static void registerEmptyTasCalloutMock() {
        SO_Config.SO_ServiceList_mock.add(
            defaultCustomerTasServiceSetting()
        );

        Test.setMock(
            HttpCalloutMock.class,
            new SO_HttpMockFactory(
                200,
                'OK',
                '',
                new Map<String, String>()
            )
        );
    }

    /**
     * @description Builds successful TAS response with two territory assignments.
     *
     * FederationIdentifier is intentionally identical to EmployeeNumber__c
     * for TAS test Users.
     */
    private static String buildMockTasResponseJson(
        String prospectId
    ) {
        List<User> tasReps = [SELECT Id, FederationIdentifier FROM User WHERE Email LIKE 'custtasrep%' ORDER BY Email LIMIT 2];

        System.assertEquals(
            2,
            tasReps.size(),
            'Expected two TAS rep Users from @testSetup.'
        );

        Map<String, Object> response =
            new Map<String, Object>{
                'prospectId' =>
                    String.isBlank(prospectId)
                        ? '001000000000001AAA'
                        : prospectId,

                'territoryData' =>
                    new List<Object>{
                        new Map<String, Object>{
                            'classCode' => 'HC',
                            'tasSalesCategory' => 'GI REPROC',
                            'tasSalesCategoryDescription' =>
                                'GI Reproc Sales',
                            'territoryId' => '71071',
                            'territoryNumber' => 'G66301',
                            'territoryDescription' =>
                                'CLEVELAND, OH',
                            'salesRepId' => '100704356',
                            'salesRepEmployeeNumber' =>
                                tasReps[0]
                                    .FederationIdentifier,
                            'salesRepName' => 'Ryan Corabi',
                            'regionName' =>
                                'G66300 Great Lakes',
                            'zoneName' =>
                                'GI Reprocessing US',
                            'buName' => 'Reprocessing'
                        },
                        new Map<String, Object>{
                            'classCode' => 'HC',
                            'tasSalesCategory' => 'SURG SPT',
                            'tasSalesCategoryDescription' =>
                                'Procedural Capital Sales',
                            'territoryId' => '74735',
                            'territoryNumber' => 'A11217',
                            'territoryDescription' =>
                                'CLEVELAND/COLUMBUS, OH',
                            'salesRepId' => '101142350',
                            'salesRepEmployeeNumber' =>
                                tasReps[1]
                                    .FederationIdentifier,
                            'salesRepName' => 'Dan Daubner',
                            'regionName' =>
                                'A11200 Mid Atlantic',
                            'zoneName' =>
                                'Procedural Capital East US',
                            'buName' => 'Procedural'
                        }
                    }
            };

        return JSON.serialize(response);
    }

    /**
     * @description Builds successful TAS response with zero territory assignments.
     */
    private static String buildMockTasResponseJsonNoTerritory(
        String prospectId
    ) {
        return JSON.serialize(
            new Map<String, Object>{
                'prospectId' =>
                    String.isBlank(prospectId)
                        ? '001000000000001AAA'
                        : prospectId,

                'territoryData' =>
                    new List<Object>()
            }
        );
    }

    /**
     * @description Builds TAS response with an Employee Number
     *              that does not exist in Salesforce.
     */
    private static String buildInvalidEmployeeResponseJson(
        String prospectId
    ) {
        return JSON.serialize(
            new Map<String, Object>{
                'prospectId' =>
                    String.isBlank(prospectId)
                        ? '001000000000001AAA'
                        : prospectId,

                'territoryData' =>
                    new List<Object>{
                        new Map<String, Object>{
                            'classCode' => 'HC',
                            'tasSalesCategory' => 'GI REPROC',
                            'tasSalesCategoryDescription' =>
                                'GI Reproc Sales',
                            'territoryId' => '71071',
                            'territoryNumber' => 'G66301',
                            'territoryDescription' =>
                                'CLEVELAND, OH',
                            'salesRepId' => '999999999',
                            'salesRepEmployeeNumber' =>
                                'INVALID_EMPLOYEE_NUMBER',
                            'salesRepName' =>
                                'Invalid TAS User',
                            'regionName' =>
                                'Test Region',
                            'zoneName' =>
                                'Test Zone',
                            'buName' =>
                                'Test Business Unit'
                        }
                    }
            }
        );
    }

    /**
     * @description Builds sample outbound Customer TAS request.
     */
    private static TasCustomerAccountRequest buildSampleRequest() {
        TasCustomerAccountRequest requestBody =
            new TasCustomerAccountRequest();

        requestBody.state = 'Ohio';
        requestBody.postalCode = '44101';
        requestBody.country = 'United States';
        requestBody.city = 'Cleveland';
        requestBody.orgId = '82';
        requestBody.classCode = 'Healthcare';
        requestBody.prospectId = '001000000000001AAA';
        requestBody.sourceSystem = 'GlobalSF';

        return requestBody;
    }

    /**
     * @description Builds SF_CUSTOMER_TAS custom metadata mock
     *              matching current production ShoutOut configuration.
     */
    private static ShoutOut_Service_Setting__mdt
        defaultCustomerTasServiceSetting() {

        ShoutOut_Service_Setting__mdt serviceSetting =
            new ShoutOut_Service_Setting__mdt();

        serviceSetting.DeveloperName =
            'SF_CUSTOMER_TAS';

        serviceSetting.MasterLabel =
            'SF_CUSTOMER_TAS';

        serviceSetting.Label =
            'SF_CUSTOMER_TAS';

        serviceSetting.Framework_Callout_Name__c =
            'SF_CUSTOMER_TAS';

        serviceSetting.isActive__c =
            true;

        serviceSetting.Named_Credential__c =
            'Boomi_TAS';

        serviceSetting.Provider_Class__c =
            'SO_Provider_Simple';

        serviceSetting.Service_Class__c =
            'SO_ServiceAdapterBase_REST';

        serviceSetting.Error_Handler_Class__c =
            'SO_ErrorLogger';

        serviceSetting.Service_Transform_Class__c =
            '';

        serviceSetting.REST_Path__c =
            '';

        serviceSetting.REST_query__c =
            '';

        serviceSetting.REST_Verb__c =
            'POST';

        serviceSetting.Timeout__c =
            20;

        serviceSetting.Retry_Max_Attempts__c =
            0;

        serviceSetting.Retry_Base_Delay_Seconds__c =
            5;

        return serviceSetting;
    }

    /**
     * @description Returns running test User.
     */
    private static User getRunningUser() {
        return [SELECT Id FROM User WHERE Email LIKE 'custrunninguser%' LIMIT 1];
    }

    /**
     * @description Returns first TAS Sales Rep.
     */
    private static User getTasRepOneUser() {
        return [SELECT Id, EmployeeNumber__c FROM User WHERE Email LIKE 'custtasrepone%' LIMIT 1];
    }

    /**
     * @description Returns Customer Account Record Type Id.
     */
    private static Id getCustomerRecordTypeId() {
        return Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Customer')
            .getRecordTypeId();
    }

    /**
     * @description Creates valid Oracle-sourced Customer Account.
     *
     *              Customer TAS validation requires:
     *              - Customer Record Type
     *              - Oracle source
     *              - OracleAddressId__c
     *              - CustomerClassCode__c
     *              - OrgIDs__c
     *              - Billing City
     *              - Billing Country
     *              - Billing State
     *              - Billing Postal Code
     */
    private static Account createCustomerAccount(
        String accountName,
        Id customerRecordTypeId,
        String suffix
    ) {
        String systemId =
            'CTAS' + suffix.left(12);

        return new Account(
            Name = accountName,
            RecordTypeId = customerRecordTypeId,
            AccountSource = 'Oracle',
            SystemID__c = systemId,
            SourceSystemID__c =
                systemId + 'Oracle',
            CustomerClassCode__c =
                'Healthcare',
            OrgIDs__c = '82',
            OracleAddressId__c =
                'ORADDR' + suffix,
            BillingStreet =
                '123 Main St',
            BillingCity =
                'Cleveland',
            BillingState =
                'Ohio',
            BillingCountry =
                'United States',
            BillingPostalCode =
                '44101'
        );
    }

    /**
     * @description Creates User.
     */
    private static User createUser(
        Id profileId,
        String username,
        String employeeNumber
    ) {
        String uniqueValue =
            String.valueOf(
                Math.abs(
                    Crypto.getRandomInteger()
                )
            );

        return new User(
            FirstName = 'Test',
            LastName = 'User',
            Alias =
                ('u' + uniqueValue).left(8),
            Email = username,
            Username = username,
            CommunityNickname =
                ('custtas' + uniqueValue).left(40),
            ProfileId = profileId,
            TimeZoneSidKey =
                'America/New_York',
            LocaleSidKey =
                'en_US',
            EmailEncodingKey =
                'UTF-8',
            LanguageLocaleKey =
                'en_US',
            EmployeeNumber__c =
                employeeNumber,
            FederationIdentifier =
                employeeNumber,
            IsActive = true
        );
    }

    /**
     * @description Generates reusable test suffix.
     */
    private static String uniqueSuffix() {
        return String.valueOf(
            Math.abs(
                Crypto.getRandomInteger()
            )
        );
    }
}