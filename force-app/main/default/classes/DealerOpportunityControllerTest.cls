/**
 * @author PWC Developer
 * @date 2026/11/02
 *
 * @group Dealer Portal
 *
 * @description
 * Dealer Portal R1 - Tests for dealer home metrics, workspace filters, and opportunity creation.
 */
@IsTest(SeeAllData=false)
private class DealerOpportunityControllerTest {

    @TestSetup
    static void setupData() {
        bypassOpportunityTrigger();

        Account dealerAccount = new Account(
            Name = 'Authorized Dealer Midwest',
            RecordTypeId = accountRecordTypeId()
        );
        insert dealerAccount;

        User dealerManager = insertUser('Dana', 'Manager', 'dmgr');
        insert new AccountTeamMember(
            AccountId = dealerAccount.Id,
            UserId = dealerManager.Id,
            TeamMemberRole = teamRole(),
            AccountAccessLevel = 'Edit',
            OpportunityAccessLevel = 'Edit',
            CaseAccessLevel = 'Read',
            ContactAccessLevel = 'Read'
        );

        insert new List<Opportunity>{
            buildOpportunity(dealerAccount, 'Recent Hospital Project', 'Evaluation', 15000, Date.today().addDays(10), Date.today().addDays(-3)),
            buildOpportunity(dealerAccount, 'Older Capital Project', 'Proposal', 27500, Date.today().addDays(20), Date.today().addDays(-1)),
            buildOpportunity(dealerAccount, 'Won Sterilizer', 'Closed Won', 23000, Date.today().addDays(-5), Date.today().addDays(-20)),
            buildOpportunity(dealerAccount, 'Future Ship Project', 'Commit', 16450, Date.today().addDays(40), Date.today().addDays(15))
        };
    }

    @IsTest
    static void getHomeReturnsOpenPipelineAndPastDue() {
        Test.startTest();
        DealerOpportunityController.HomeResponse response = DealerOpportunityController.getHome();
        Test.stopTest();

        Assert.areEqual(3, response.summary.openCount, 'Evaluation, Proposal, and Commit are open.');
        Assert.areEqual(58950, response.summary.openPipelineValue.intValue(), 'Open value should be converted USD.');
        Assert.areEqual(1, response.summary.closedWonCount, 'Closed Won should be counted separately.');
        Assert.areEqual(2, response.pastDueOpportunities.size(), 'Only open opportunities with a ship date before today are past due.');
        Assert.isFalse(response.recentOpportunities.isEmpty(), 'Recent opportunities should be returned.');
        Assert.areEqual(0, discoveryCount(response.summary), 'Discovery is not a dealer stage metric.');
    }

    @IsTest
    static void getWorkspaceFiltersByCustomerAndStage() {
        String filterJson = '{"search":"Sterilizer","stageName":"Closed Won","pageNumber":1,"pageSize":25}';

        Test.startTest();
        DealerOpportunityController.WorkspaceResponse response = DealerOpportunityController.getWorkspace(filterJson);
        Test.stopTest();

        Assert.areEqual(1, response.totalCount, 'The customer and stage filter should return one opportunity.');
        Assert.areEqual('Won Sterilizer', response.opportunities[0].name, 'The matching opportunity should be returned.');
        Assert.areEqual(4, response.summary.totalCount, 'Summary counts stay on the full dealer population.');
    }

    @IsTest
    static void createOpportunityAssignsDealerManager() {
        Account dealerAccount = [SELECT Id FROM Account WHERE Name = 'Authorized Dealer Midwest' LIMIT 1];
        AccountTeamMember dealerManager = [
            SELECT UserId
            FROM AccountTeamMember
            WHERE Account.Name = 'Authorized Dealer Midwest'
            AND User.FirstName = 'Dana'
            AND User.LastName = 'Manager'
            LIMIT 1
        ];
        String requestJson = '{' +
            '"name":"New Clinic Opportunity",' +
            '"stageName":"Proposal",' +
            '"endCustomerName":"Cleveland Clinic",' +
            '"description":"Sterile processing expansion",' +
            '"country":"United States",' +
            '"amount":18000,' +
            '"currencyCode":"USD",' +
            '"closeDate":"' + String.valueOf(Date.today().addDays(30)) + '",' +
            '"expectedShipDate":"' + String.valueOf(Date.today().addDays(45)) + '",' +
            '"installationDate":"' + String.valueOf(Date.today().addDays(60)) + '",' +
            '"accountId":"' + dealerAccount.Id + '"' +
        '}';

        Test.startTest();
        Id opportunityId = DealerOpportunityController.createOpportunity(requestJson);
        Test.stopTest();

        Opportunity createdOpportunity = [
            SELECT OwnerId, StageName, CurrencyIsoCode, DealerSubmitter__c, DealerAccountName__c, EndCustomerName__c
            FROM Opportunity
            WHERE Id = :opportunityId
        ];
        Assert.areEqual(dealerManager.UserId, createdOpportunity.OwnerId, 'The Dealer Manager should own the opportunity.');
        Assert.areEqual('Proposal', createdOpportunity.StageName, 'The stage selected on the form should be saved.');
        Assert.areEqual('USD', createdOpportunity.CurrencyIsoCode, 'Currency should default from the request.');
        Assert.areEqual(UserInfo.getUserId(), createdOpportunity.DealerSubmitter__c, 'The creator is stored as the submitter.');
        Assert.areEqual('Authorized Dealer Midwest', createdOpportunity.DealerAccountName__c, 'The dealer name should be stamped.');
        Assert.areEqual('Cleveland Clinic', createdOpportunity.EndCustomerName__c, 'The end customer should be stored.');
    }

    @IsTest
    static void getCreateContextDefaultsCurrencyToUsd() {
        Test.startTest();
        DealerOpportunityController.CreateContext context = DealerOpportunityController.getCreateContext();
        Test.stopTest();

        Assert.areEqual('USD', context.defaultCurrency, 'New dealer opportunities default to USD.');
        Assert.areEqual(false, context.partnerUser, 'The running test user is an internal user.');
        Assert.isTrue(context.stages.contains('Evaluation'), 'Dealer stages should be offered on create.');
        Assert.isFalse(context.stages.contains('Discovery'), 'Discovery is not a Dealer record type stage.');
    }

    @IsTest
    static void shareServiceLeavesOwnerWhenNoDealerManagerIsAssigned() {
        Account dealerAccount = new Account(Name = 'Dealer Without Manager');
        insert dealerAccount;
        Opportunity opportunityRecord = new Opportunity(
            Name = 'Unassigned Dealer Opportunity',
            AccountId = dealerAccount.Id,
            RecordTypeId = dealerRecordTypeId(),
            StageName = 'Evaluation',
            CloseDate = Date.today().addDays(12),
            ForecastConfidenceLevel__c = 'Pipeline',
            CurrencyIsoCode = 'USD'
        );
        insert opportunityRecord;

        Test.startTest();
        DealerOpportunityShareService.assignOwnerAndShare(opportunityRecord.Id, UserInfo.getUserId());
        Test.stopTest();

        Opportunity reloaded = [
            SELECT OwnerId
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
        ];
        Assert.areEqual(UserInfo.getUserId(), reloaded.OwnerId, 'The owner stays unchanged when no Dealer Manager is assigned.');
        Assert.isNull(DealerOpportunityShareService.selectAccountName(null), 'A blank account has no name.');
    }

    @IsTest
    static void getWorkspaceRejectsAnInvalidFilter() {
        Test.startTest();
        try {
            DealerOpportunityController.getWorkspace('{');
            Assert.fail('An invalid filter should be rejected.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isNotNull(exceptionValue.getMessage(), 'The filter error should be returned.');
        }
        Test.stopTest();
    }

    @IsTest
    static void createOpportunityRequiresTheEndCustomer() {
        Test.startTest();
        try {
            DealerOpportunityController.createOpportunity('{"name":"Missing customer"}');
            Assert.fail('A validation error was expected.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isTrue(
                exceptionValue.getMessage().contains('End Customer Name'),
                'The missing end customer should be reported.'
            );
        }
        Test.stopTest();
    }

    private static Opportunity buildOpportunity(
        Account dealerAccount,
        String opportunityName,
        String stageName,
        Decimal amount,
        Date closeDate,
        Date expectedShipDate
    ) {
        return new Opportunity(
            Name = opportunityName,
            AccountId = dealerAccount.Id,
            RecordTypeId = dealerRecordTypeId(),
            StageName = stageName,
            Amount = amount,
            CloseDate = closeDate,
            Expected_Ship_Date__c = expectedShipDate,
            EndCustomerName__c = opportunityName + ' Customer',
            DealerAccountName__c = dealerAccount.Name,
            Country__c = 'United States',
            ForecastConfidenceLevel__c = 'Pipeline',
            CurrencyIsoCode = 'USD'
        );
    }

    private static Id dealerRecordTypeId() {
        return Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get(DealerOpportunitySelector.RECORD_TYPE_NAME)
            .getRecordTypeId();
    }

    private static Id accountRecordTypeId() {
        Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Dealer_Account');
        return recordTypeInfo == null ? null : recordTypeInfo.getRecordTypeId();
    }

    private static Integer discoveryCount(DealerOpportunityController.Summary summary) {
        for (DealerOpportunityController.StageMetric stageMetric : summary.stages) {
            if (stageMetric.stageName == 'Discovery') {
                return stageMetric.recordCount;
            }
        }
        return 0;
    }

    private static String teamRole() {
        for (Schema.PicklistEntry picklistEntry : AccountTeamMember.TeamMemberRole.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive() && picklistEntry.getValue().toLowerCase().contains('dealer manager')) {
                return picklistEntry.getValue();
            }
        }
        for (Schema.PicklistEntry picklistEntry : AccountTeamMember.TeamMemberRole.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }
        return 'Dealer Manager';
    }

    private static User insertUser(String firstName, String lastName, String aliasPrefix) {
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User userRecord = new User(
            FirstName = firstName,
            LastName = lastName,
            Alias = (aliasPrefix + suffix).left(8),
            Email = aliasPrefix + '.' + suffix + '@test.com',
            Username = aliasPrefix + '.' + suffix + '@steris.test',
            CommunityNickname = aliasPrefix + suffix,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = adminProfile.Id,
            EmployeeNumber__c = suffix.left(8),
            IsActive = true
        );
        insert userRecord;
        return userRecord;
    }

    private static void bypassOpportunityTrigger() {
        insert new Automation_Setting_Trigger__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            OpportunityTriggerByPass__c = true
        );
    }
}