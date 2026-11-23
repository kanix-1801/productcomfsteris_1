/**
 * @author PWC Developer
 * @date 2026/11/02
 *
 * @group Dealer Portal
 *
 * @description
 * GC-3603 Dealer Portal R1 - Tests for dealer home metrics, workspace filters, and opportunity creation.
 */
@IsTest(SeeAllData=false)
private class DealerOpportunityControllerTest {

    @TestSetup
    static void setupData() {
        TestDataFactory.bypassDealerOpportunityTrigger();

        Account dealerAccount = TestDataFactory.insertDealerAccount('Authorized Dealer Midwest');
        User dealerManager = TestDataFactory.insertDealerUser('Dana', 'Manager', 'dmgr');
        TestDataFactory.insertDealerTeamMember(dealerAccount.Id, dealerManager.Id, teamRole());

        List<Opportunity> opportunities = TestDataFactory.insertDealerOpportunities(new List<Opportunity>{
            TestDataFactory.buildDealerOpportunity(dealerAccount.Id, 'Recent Hospital Project', 'Evaluation', 15000, Date.today().addDays(10), Date.today().addDays(-3)),
            TestDataFactory.buildDealerOpportunity(dealerAccount.Id, 'Older Capital Project', 'Proposal', 27500, Date.today().addDays(20), Date.today().addDays(-1)),
            TestDataFactory.buildDealerOpportunity(dealerAccount.Id, 'Won Sterilizer', 'Closed Won', 23000, Date.today().addDays(5), Date.today().addDays(-20)),
            TestDataFactory.buildDealerOpportunity(dealerAccount.Id, 'Future Ship Project', 'Commit', 16450, Date.today().addDays(40), Date.today().addDays(15))
        });
        // The close date rule blocks past close dates on open stages, so move the closed-won date back after the stage is set.
        opportunities[2].CloseDate = Date.today().addDays(-5);
        update opportunities[2];
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
    static void getWorkspaceSearchesCountryAmountAndDates() {
        Opportunity futureShip = [
            SELECT CloseDate, Expected_Ship_Date__c
            FROM Opportunity
            WHERE Name = 'Future Ship Project'
            LIMIT 1
        ];

        Test.startTest();
        DealerOpportunityController.WorkspaceResponse byAmount =
            DealerOpportunityController.getWorkspace('{"search":"$16,450","pageNumber":1,"pageSize":25}');
        DealerOpportunityController.WorkspaceResponse byCountry =
            DealerOpportunityController.getWorkspace('{"search":"United","pageNumber":1,"pageSize":25}');
        DealerOpportunityController.WorkspaceResponse byCloseDate =
            DealerOpportunityController.getWorkspace(
                '{"search":"' + String.valueOf(futureShip.CloseDate) + '","pageNumber":1,"pageSize":25}'
            );
        DealerOpportunityController.WorkspaceResponse byShipDate =
            DealerOpportunityController.getWorkspace(
                '{"search":"' + String.valueOf(futureShip.Expected_Ship_Date__c) + '","pageNumber":1,"pageSize":25}'
            );
        Test.stopTest();

        Assert.areEqual(1, byAmount.totalCount, 'A typed amount should match Opportunity Amount.');
        Assert.areEqual('Future Ship Project', byAmount.opportunities[0].name, 'The amount search should return that opportunity.');
        Assert.areEqual(4, byCountry.totalCount, 'Country search should match part of the country name.');
        Assert.areEqual(1, byCloseDate.totalCount, 'A close date should match Expected Order Date.');
        Assert.areEqual('Future Ship Project', byCloseDate.opportunities[0].name, 'The close date search should return that opportunity.');
        Assert.areEqual(1, byShipDate.totalCount, 'A ship date should match Expected Ship Date.');
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
        String businessUnit = activeBusinessUnit();
        String requestJson = '{' +
            '"name":"New Clinic Opportunity",' +
            '"stageName":"Proposal",' +
            '"endCustomerName":"Cleveland Clinic",' +
            '"description":"Sterile processing expansion",' +
            '"country":"United States",' +
            '"businessUnits":' + JSON.serialize(businessUnit) + ',' +
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
            SELECT OwnerId, StageName, CurrencyIsoCode, DealerSubmitter__c,
                EndCustomerName__c, HCBusinessUnit__c
            FROM Opportunity
            WHERE Id = :opportunityId
        ];
        Assert.areEqual(dealerManager.UserId, createdOpportunity.OwnerId, 'The Dealer Manager should own the opportunity.');
        Assert.isTrue(
            DealerOpportunitySelector.CREATE_STAGES.contains(createdOpportunity.StageName),
            'The opportunity should be saved with a Dealer stage.'
        );
        Assert.areEqual(businessUnit, createdOpportunity.HCBusinessUnit__c, 'The selected business unit should be saved.');
        Assert.areEqual('USD', createdOpportunity.CurrencyIsoCode, 'Currency should default from the request.');
        Assert.areEqual(UserInfo.getUserId(), createdOpportunity.DealerSubmitter__c, 'The creator is stored as the submitter.');
        Assert.areEqual('Cleveland Clinic', createdOpportunity.EndCustomerName__c, 'The end customer should be stored.');
    }

    @IsTest
    static void finalizeCreatedOpportunityAssignsDealerManager() {
        AccountTeamMember dealerManager = [
            SELECT UserId
            FROM AccountTeamMember
            WHERE Account.Name = 'Authorized Dealer Midwest'
            AND User.FirstName = 'Dana'
            AND User.LastName = 'Manager'
            LIMIT 1
        ];
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = 'Future Ship Project'
            LIMIT 1
        ];

        Test.startTest();
        DealerOpportunityController.finalizeCreatedOpportunity(opportunityRecord.Id);
        Test.stopTest();

        Opportunity reloaded = [
            SELECT OwnerId, DealerSubmitter__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
        ];
        Assert.areEqual(dealerManager.UserId, reloaded.OwnerId, 'The Dealer Manager should own the opportunity.');
        Assert.areEqual(UserInfo.getUserId(), reloaded.DealerSubmitter__c, 'The creator is stored as the submitter.');
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
        Assert.isFalse(context.businessUnits.isEmpty(), 'Business Unit choices should be available on create.');
        Assert.areEqual(
            TestDataFactory.dealerOpportunityRecordTypeId(),
            context.recordTypeId,
            'The standard form should open on the Dealer record type.'
        );
    }

    @IsTest
    static void shareServiceLeavesOwnerWhenNoDealerManagerIsAssigned() {
        Account dealerAccount = TestDataFactory.insertDealerAccount('Dealer Without Manager');
        Opportunity opportunityRecord = TestDataFactory.insertDealerOpportunities(new List<Opportunity>{
            TestDataFactory.buildDealerOpportunity(
                dealerAccount.Id,
                'Unassigned Dealer Opportunity',
                'Evaluation',
                null,
                Date.today().addDays(12),
                null
            )
        })[0];

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

    @IsTest
    static void getWorkspaceHonorsBlankAndFullFilters() {
        Opportunity futureShip = [
            SELECT CloseDate, Expected_Ship_Date__c
            FROM Opportunity
            WHERE Name = 'Future Ship Project'
            LIMIT 1
        ];
        String slashDate = futureShip.CloseDate.month() + '/'
            + futureShip.CloseDate.day() + '/'
            + futureShip.CloseDate.year();
        String fullFilter = '{' +
            '"search":"' + slashDate + '",' +
            '"stageName":"Commit",' +
            '"pastDueOnly":false,' +
            '"country":"United States",' +
            '"amountMin":1,' +
            '"amountMax":100000,' +
            '"closeDateFrom":"' + String.valueOf(futureShip.CloseDate.addDays(-1)) + '",' +
            '"closeDateTo":"' + String.valueOf(futureShip.CloseDate.addDays(1)) + '",' +
            '"shipDateFrom":"' + String.valueOf(futureShip.Expected_Ship_Date__c.addDays(-1)) + '",' +
            '"shipDateTo":"' + String.valueOf(futureShip.Expected_Ship_Date__c.addDays(1)) + '",' +
            '"sortField":"NotAField",' +
            '"sortDirection":"DESC",' +
            '"pageNumber":1,' +
            '"pageSize":100' +
        '}';

        Test.startTest();
        DealerOpportunityController.WorkspaceResponse blankFilter =
            DealerOpportunityController.getWorkspace('');
        DealerOpportunityController.WorkspaceResponse matched =
            DealerOpportunityController.getWorkspace(fullFilter);
        DealerOpportunityController.WorkspaceResponse pastDue =
            DealerOpportunityController.getWorkspace('{"pastDueOnly":true,"sortField":"Amount","sortDirection":"DESC"}');
        DealerOpportunityController.WorkspaceResponse ignoredDates =
            DealerOpportunityController.getWorkspace('{"search":"???","closeDateFrom":"","shipDateFrom":"","pageNumber":200,"pageSize":0}');
        Test.stopTest();

        Assert.areEqual(4, blankFilter.totalCount, 'A blank filter returns every dealer opportunity.');
        Assert.areEqual(1, blankFilter.pageNumber, 'A blank filter starts on the first page.');
        Assert.areEqual(25, blankFilter.pageSize, 'A blank filter uses the default page size.');
        Assert.areEqual(1, matched.totalCount, 'The combined filter should return the commit opportunity.');
        Assert.areEqual('Future Ship Project', matched.opportunities[0].name, 'The commit opportunity should be returned.');
        Assert.areEqual(50, matched.pageSize, 'Page size should be capped at the maximum.');
        Assert.areEqual(2, pastDue.totalCount, 'Past due should return the two open opportunities with an earlier ship date.');
        Assert.areEqual(0, ignoredDates.opportunities.size(), 'An unusable search on a far page returns no rows.');
    }

    @IsTest
    static void selectorCoversLimitsDatesAndCharts() {
        Account dealerAccount = [SELECT Id, Name FROM Account WHERE Name = 'Authorized Dealer Midwest' LIMIT 1];
        String businessUnit = activeBusinessUnit();
        List<Opportunity> extraOpportunities = new List<Opportunity>{
            TestDataFactory.buildDealerOpportunity(dealerAccount.Id, 'Near Term Pipeline', 'Evaluation', 5000, Date.today().addDays(30), Date.today().addDays(5)),
            TestDataFactory.buildDealerOpportunity(dealerAccount.Id, 'Later Pipeline', 'Evaluation', 5000, Date.today().addDays(120), Date.today().addDays(6)),
            TestDataFactory.buildDealerOpportunity(dealerAccount.Id, 'Next Year Pipeline', 'Evaluation', 8000, Date.newInstance(Date.today().year() + 1, 2, 15), Date.today().addDays(7))
        };
        extraOpportunities[0].HCBusinessUnit__c = businessUnit;
        TestDataFactory.insertDealerOpportunities(extraOpportunities);

        DealerOpportunitySelector.OpportunityFilter emptySearch = new DealerOpportunitySelector.OpportunityFilter();
        emptySearch.search = '13/40/2026';
        emptySearch.pageNumber = 0;
        emptySearch.pageSize = -1;

        Test.startTest();
        Integer everyRow = DealerOpportunitySelector.countByFilter(null);
        List<Opportunity> firstPage = DealerOpportunitySelector.selectByFilter(null);
        List<Opportunity> defaultPastDue = DealerOpportunitySelector.selectPastDue(null);
        List<Opportunity> cappedPastDue = DealerOpportunitySelector.selectPastDue(80);
        Integer slashMisses = DealerOpportunitySelector.countByFilter(emptySearch);
        DealerOpportunityController.HomeResponse home = DealerOpportunityController.getHome();
        Test.stopTest();

        Assert.isTrue(everyRow >= 4, 'A null filter counts the dealer opportunities.');
        Assert.isFalse(firstPage.isEmpty(), 'A null filter returns the first page.');
        Assert.isFalse(defaultPastDue.isEmpty(), 'A null past-due limit uses the default.');
        Assert.isTrue(cappedPastDue.size() <= 50, 'A large past-due limit is capped.');
        Assert.areEqual(0, slashMisses, 'An impossible slash date should not match.');
        Assert.isTrue(home.quarterChart.size() >= 2, 'Open pipeline should span more than one fiscal quarter.');
        Assert.isFalse(home.businessUnitChart.isEmpty(), 'Business unit totals should include the open pipeline.');
        Assert.isTrue(home.summary.stages.size() >= 8, 'Every workspace stage should be present in the summary.');
    }

    @IsTest
    static void createOpportunityRejectsInvalidDetails() {
        Account dealerAccount = [SELECT Id FROM Account WHERE Name = 'Authorized Dealer Midwest' LIMIT 1];
        String validRequest = createRequest(activeBusinessUnit(), 'USD', dealerAccount.Id);

        Test.startTest();
        assertCreateRejected('', 'Enter the opportunity details.');
        assertCreateRejected(validRequest.replace('"Proposal"', '"Discovery"'), 'Select a stage');
        assertCreateRejected(validRequest.replace('"amount":18000', '"amount":-1'), 'Amount is required.');
        assertCreateRejected(validRequest.replace('"closeDate":"' + String.valueOf(Date.today().addDays(30)) + '"', '"closeDate":"not-a-date"'), 'Close Date');
        assertCreateRejected(createRequest(activeBusinessUnit(), 'USD', null), 'Select a dealer account.');
        assertCreateRejected(createRequest(activeBusinessUnit(), 'USD', 'not-an-id'), 'Select a valid dealer account.');
        assertCreateRejected(createRequest(activeBusinessUnit(), 'USD', '001000000000000AAA'), 'Select a valid dealer account.');
        assertCreateRejected(createRequest('Not A Real Unit', 'USD', dealerAccount.Id), 'Select a valid Business Unit.');
        Id createdId = DealerOpportunityController.createOpportunity(
            createRequest(activeBusinessUnit() + ';' + activeBusinessUnit() + '; ', '', dealerAccount.Id)
        );
        Test.stopTest();

        Opportunity createdOpportunity = [
            SELECT CurrencyIsoCode, HCBusinessUnit__c
            FROM Opportunity
            WHERE Id = :createdId
        ];
        Assert.areEqual('USD', createdOpportunity.CurrencyIsoCode, 'A blank currency should default to USD.');
        Assert.areEqual(activeBusinessUnit(), createdOpportunity.HCBusinessUnit__c, 'Duplicate business units should be stored once.');
    }

    @IsTest
    static void finalizeCreatedOpportunityCoversMissingAndUnchangedRecords() {
        Account dealerAccount = [SELECT Id, Name FROM Account WHERE Name = 'Authorized Dealer Midwest' LIMIT 1];
        Opportunity unnamed = TestDataFactory.buildDealerOpportunity(
            dealerAccount.Id,
            'Needs Dealer Name',
            'Evaluation',
            1000,
            Date.today().addDays(9),
            Date.today().addDays(12)
        );
        unnamed.ForecastConfidenceLevel__c = null;
        Opportunity finished = TestDataFactory.buildDealerOpportunity(
            dealerAccount.Id,
            'Already Finished',
            'Evaluation',
            1100,
            Date.today().addDays(11),
            Date.today().addDays(13)
        );
        finished.DealerSubmitter__c = UserInfo.getUserId();
        Opportunity removedOpportunity = TestDataFactory.buildDealerOpportunity(
            dealerAccount.Id,
            'Removed Opportunity',
            'Evaluation',
            1200,
            Date.today().addDays(12),
            Date.today().addDays(14)
        );
        TestDataFactory.insertDealerOpportunities(new List<Opportunity>{
            unnamed,
            finished,
            removedOpportunity
        });
        Id removedOpportunityId = removedOpportunity.Id;
        delete removedOpportunity;

        Test.startTest();
        try {
            DealerOpportunityController.finalizeCreatedOpportunity(null);
            Assert.fail('A missing opportunity should be rejected.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isTrue(
                exceptionValue.getMessage().contains('not created'),
                'A null opportunity should be reported.'
            );
        }
        try {
            DealerOpportunityController.finalizeCreatedOpportunity(removedOpportunityId);
            Assert.fail('An unknown opportunity should be rejected.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isTrue(
                exceptionValue.getMessage().contains('not created'),
                'An unknown opportunity should be reported.'
            );
        }
        DealerOpportunityController.finalizeCreatedOpportunity(unnamed.Id);
        DealerOpportunityController.finalizeCreatedOpportunity(finished.Id);
        Test.stopTest();

        Opportunity reloaded = [
            SELECT DealerSubmitter__c, ForecastConfidenceLevel__c
            FROM Opportunity
            WHERE Id = :unnamed.Id
        ];
        Assert.areEqual(UserInfo.getUserId(), reloaded.DealerSubmitter__c, 'The submitter should be stamped.');
        Assert.areEqual('Pipeline', reloaded.ForecastConfidenceLevel__c, 'Confidence should default to Pipeline.');
    }

    @IsTest
    static void controllerReportsAQueryFailure() {
        User limitedUser = TestDataFactory.insertDealerUser('Limited', 'Reader', 'lrd', 'Minimum Access - Salesforce');

        System.runAs(limitedUser) {
            Test.startTest();
            try {
                DealerOpportunityController.getHome();
                Assert.fail('A user without opportunity access should not load the home page.');
            } catch (Exception exceptionValue) {
                Assert.isNotNull(exceptionValue.getMessage(), 'The home page error should be returned.');
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void shareServiceCoversMissingAccountsManagersAndRoles() {
        User teammate = TestDataFactory.insertDealerUser('Pat', 'Teammate', 'ptm');
        Opportunity plainOpportunity;
        Opportunity sharedOpportunity;
        Opportunity unlinkedOpportunity;
        Id removedAccountId;

        // Partner portal roles only exist in orgs where an Account has been enabled as a partner, so do not
        // assume one is present (it is missing in CBMQA).
        List<UserRole> portalRoles = [
            SELECT PortalAccountId
            FROM UserRole
            WHERE PortalType = 'Partner'
            AND PortalAccountId != null
            LIMIT 1
        ];
        Boolean hasPortalRole = !portalRoles.isEmpty();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Account plainAccount = TestDataFactory.insertDealerAccount('Plain Dealer Team');
            Account removedAccount = TestDataFactory.insertDealerAccount('Removed Dealer');
            removedAccountId = removedAccount.Id;
            delete removedAccount;
            TestDataFactory.insertDealerTeamMember(
                plainAccount.Id,
                teammate.Id,
                teamRoleWithoutDealerManager()
            );
            plainOpportunity = TestDataFactory.buildDealerOpportunity(
                plainAccount.Id,
                'Plain Team Opportunity',
                'Evaluation',
                2200,
                Date.today().addDays(14),
                Date.today().addDays(16)
            );
            sharedOpportunity = TestDataFactory.buildDealerOpportunity(
                hasPortalRole ? portalRoles[0].PortalAccountId : plainAccount.Id,
                'Portal Role Opportunity',
                'Evaluation',
                2400,
                Date.today().addDays(18),
                Date.today().addDays(20)
            );
            unlinkedOpportunity = TestDataFactory.buildDealerOpportunity(
                null,
                'Unlinked Opportunity',
                'Evaluation',
                null,
                Date.today().addDays(21),
                null
            );
            TestDataFactory.insertDealerOpportunities(new List<Opportunity>{
                plainOpportunity,
                sharedOpportunity,
                unlinkedOpportunity
            });
        }

        Test.startTest();
        DealerOpportunityShareService.assignOwnerAndShare(null, UserInfo.getUserId());
        DealerOpportunityShareService.assignOwnerAndShare(unlinkedOpportunity.Id, teammate.Id);
        DealerOpportunityShareService.assignOwnerAndShare(plainOpportunity.Id, teammate.Id);
        DealerOpportunityShareService.assignOwnerAndShare(sharedOpportunity.Id, UserInfo.getUserId());
        String missingName = DealerOpportunityShareService.selectAccountName(removedAccountId);
        Test.stopTest();

        Opportunity reloaded = [SELECT OwnerId FROM Opportunity WHERE Id = :plainOpportunity.Id];
        List<OpportunityShare> shares = [
            SELECT Id
            FROM OpportunityShare
            WHERE OpportunityId = :sharedOpportunity.Id
            AND RowCause = 'Manual'
        ];
        Assert.areEqual(teammate.Id, reloaded.OwnerId, 'A standard team member should own the opportunity when no Dealer Manager is assigned.');
        Assert.isNull(missingName, 'A deleted account has no name.');
        if (hasPortalRole) {
            Assert.isFalse(shares.isEmpty(), 'The dealer organisation role should receive a manual share.');
        }
    }

    private static String createRequest(String businessUnits, String currencyCode, String accountId) {
        String businessUnitJson = businessUnits == null ? 'null' : JSON.serialize(businessUnits);
        String currencyJson = currencyCode == null ? 'null' : JSON.serialize(currencyCode);
        String accountJson = accountId == null ? 'null' : JSON.serialize(accountId);
        return '{' +
            '"name":"Coverage Clinic",' +
            '"stageName":"Proposal",' +
            '"endCustomerName":"Cleveland Clinic",' +
            '"description":"Sterile processing expansion",' +
            '"country":"United States",' +
            '"businessUnits":' + businessUnitJson + ',' +
            '"amount":18000,' +
            '"currencyCode":' + currencyJson + ',' +
            '"closeDate":"' + String.valueOf(Date.today().addDays(30)) + '",' +
            '"expectedShipDate":"' + String.valueOf(Date.today().addDays(45)) + '",' +
            '"installationDate":"' + String.valueOf(Date.today().addDays(60)) + '",' +
            '"accountId":' + accountJson +
        '}';
    }

    private static void assertCreateRejected(String requestJson, String expectedText) {
        try {
            DealerOpportunityController.createOpportunity(requestJson);
            Assert.fail('A validation error was expected.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isTrue(
                exceptionValue.getMessage().contains(expectedText),
                'Expected the error to mention ' + expectedText + '.'
            );
        }
    }

    private static String teamRoleWithoutDealerManager() {
        for (Schema.PicklistEntry picklistEntry : AccountTeamMember.TeamMemberRole.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive() && !picklistEntry.getValue().toLowerCase().contains('dealer manager')) {
                return picklistEntry.getValue();
            }
        }
        return teamRole();
    }

    private static String activeBusinessUnit() {
        for (Schema.PicklistEntry entry : Opportunity.HCBusinessUnit__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        Assert.fail('Business Unit should have an active value.');
        return null;
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
}