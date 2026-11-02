/**
 * @description Test coverage for OpportunityQuoteContextService REST API.
 */
@IsTest
private class OpportunityQuoteContextServiceTest {

    private static final String EMPLOYEE_WITH_ACCESS = '111111';
    private static final String EMPLOYEE_NO_ACCESS = '333333';

    @TestSetup
    static void setupData() {
        Profile standardProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        Id recordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Customer')
            .getRecordTypeId();

        createUser(standardProfile.Id, EMPLOYEE_WITH_ACCESS, 'Access');
        createUser(standardProfile.Id, EMPLOYEE_NO_ACCESS, 'NoAccess');

        Account account = new Account(
            Name = 'SC Test Account',
            SourceSystemID__c = '1234',
            RecordTypeId = recordTypeId
        );
        insert account;

        Contact contactRecord = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            AccountId = account.Id,
            Email = 'test@test.com'
        );
        insert contactRecord;

        User ownerUser = [
            SELECT Id
            FROM User
            WHERE EmployeeNumber__c = :EMPLOYEE_WITH_ACCESS
            LIMIT 1
        ];

        insert new Opportunity(
            Name = 'SC Test Opportunity',
            StageName = getValidStageName(),
            ForecastConfidenceLevel__c = getValidForecastConfidenceLevel(),
            CloseDate = Date.today().addDays(30),
            AccountId = account.Id,
            OwnerId = ownerUser.Id,
            Type = getValidOpportunityType(),
            Amount = 12455,
            Probability = 10,
            PrimaryContact__c = contactRecord.Id
        );
    }

    @IsTest
    static void testEvaluateAccess_hasReadAccess() {
        Opportunity opportunity = [SELECT Id FROM Opportunity LIMIT 1];

        OpportunityQuoteContextService.testHasReadAccessOverride = true;

        OpportunityQuoteContextService.RequestPayload request =
            new OpportunityQuoteContextService.RequestPayload();
        request.sfOpportunityId = opportunity.Id;
        request.sfQuoteId = '0Q05f00000XYZabCAH';
        request.scEmployeeNumber = EMPLOYEE_WITH_ACCESS;

        Test.startTest();
        OpportunityQuoteContextService.ResponsePayload response =
            OpportunityQuoteContextService.evaluateAccess(request);
        Test.stopTest();

        Assert.isTrue(response.scEmployeeHasAccess);
        Assert.areEqual(opportunity.Id, response.sfOpportunityId);
        Assert.areEqual('0Q05f00000XYZabCAH', response.sfQuoteId);
        Assert.areEqual(EMPLOYEE_WITH_ACCESS, response.scEmployeeNumber);
    }

    @IsTest
    static void testEvaluateAccess_noReadAccess() {
        Opportunity opportunity = [SELECT Id FROM Opportunity LIMIT 1];

        OpportunityQuoteContextService.testHasReadAccessOverride = false;

        OpportunityQuoteContextService.RequestPayload request =
            new OpportunityQuoteContextService.RequestPayload();
        request.sfOpportunityId = opportunity.Id;
        request.sfQuoteId = '0Q05f00000XYZabCAH';
        request.scEmployeeNumber = EMPLOYEE_NO_ACCESS;

        Test.startTest();
        OpportunityQuoteContextService.ResponsePayload response =
            OpportunityQuoteContextService.evaluateAccess(request);
        Test.stopTest();

        Assert.isFalse(response.scEmployeeHasAccess);
    }

    @IsTest
    static void testEvaluateAccess_unknownEmployeeNoAccess() {
        Opportunity opportunity = [SELECT Id FROM Opportunity LIMIT 1];

        OpportunityQuoteContextService.RequestPayload request =
            new OpportunityQuoteContextService.RequestPayload();
        request.sfOpportunityId = opportunity.Id;
        request.scEmployeeNumber = '999999';

        Test.startTest();
        OpportunityQuoteContextService.ResponsePayload response =
            OpportunityQuoteContextService.evaluateAccess(request);
        Test.stopTest();

        Assert.isFalse(response.scEmployeeHasAccess);
    }

    @IsTest
    static void testEvaluateAccess_usesUserRecordAccessForOwner() {
        Opportunity opportunity = [SELECT Id FROM Opportunity LIMIT 1];
        OpportunityQuoteContextService.testHasReadAccessOverride = null;

        OpportunityQuoteContextService.RequestPayload request =
            new OpportunityQuoteContextService.RequestPayload();
        request.sfOpportunityId = opportunity.Id;
        request.scEmployeeNumber = EMPLOYEE_WITH_ACCESS;

        Test.startTest();
        OpportunityQuoteContextService.ResponsePayload response =
            OpportunityQuoteContextService.evaluateAccess(request);
        Test.stopTest();

        Assert.isTrue(response.scEmployeeHasAccess);
    }

    @IsTest
    static void testGetOpportunityQuoteContext_httpPostSuccess() {
        Opportunity opportunity = [SELECT Id FROM Opportunity LIMIT 1];
        OpportunityQuoteContextService.testHasReadAccessOverride = true;

        RestRequest request = new RestRequest();
        RestResponse response = new RestResponse();
        request.requestURI = '/services/apexrest/v1/opportunity-quote-context';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'sfOpportunityId' => opportunity.Id,
            'sfQuoteId' => '0Q05f00000XYZabCAH',
            'scEmployeeNumber' => EMPLOYEE_WITH_ACCESS
        }));

        RestContext.request = request;
        RestContext.response = response;

        Test.startTest();
        OpportunityQuoteContextService.getOpportunityQuoteContext();
        Test.stopTest();

        Assert.areEqual(200, response.statusCode);

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
            response.responseBody.toString()
        );
        Assert.areEqual(true, payload.get('scEmployeeHasAccess'));
        Assert.areEqual('0Q05f00000XYZabCAH', payload.get('sfQuoteId'));
    }

    @IsTest
    static void testGetOpportunityQuoteContext_missingRequiredField() {
        RestRequest request = new RestRequest();
        RestResponse response = new RestResponse();
        request.requestURI = '/services/apexrest/v1/opportunity-quote-context';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf('{"sfQuoteId":"0Q0TEST"}');

        RestContext.request = request;
        RestContext.response = response;

        Test.startTest();
        OpportunityQuoteContextService.getOpportunityQuoteContext();
        Test.stopTest();

        Assert.areEqual(400, response.statusCode);
    }

    private static User createUser(Id profileId, String employeeNumber, String suffix) {
        User userRecord = new User(
            LastName = 'SC Test ' + suffix,
            Email = 'sctest' + suffix + '@example.com',
            Username = 'sctest' + suffix + System.currentTimeMillis() + '@example.com.test',
            Alias = suffix.left(8),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = profileId,
            LanguageLocaleKey = 'en_US',
            EmployeeNumber__c = employeeNumber
        );
        insert userRecord;
        return userRecord;
    }

    private static String getValidStageName() {
        for (Schema.PicklistEntry picklistEntry : Opportunity.StageName.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return 'Discovery';
    }

    private static String getValidForecastConfidenceLevel() {
        Schema.DescribeFieldResult fieldDescribe =
            Opportunity.ForecastConfidenceLevel__c.getDescribe();

        if (!fieldDescribe.isAccessible()) {
            return null;
        }

        for (Schema.PicklistEntry picklistEntry : fieldDescribe.getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return null;
    }

    private static String getValidOpportunityType() {
        for (Schema.PicklistEntry picklistEntry : Opportunity.Type.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return null;
    }
}