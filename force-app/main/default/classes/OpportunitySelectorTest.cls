/**
 * @description Tests for OpportunitySelector.
 *
 *              Responsibilities:
 *              1. Verify every selector method returns an empty result for null or empty input.
 *              2. Verify each selector method returns the expected opportunities and fields for valid Ids.
 *              3. Verify open pipeline results exclude closed opportunities and keep the expected order.
 *
 *              Test data is created once in the test setup method.
 * @author      Surya Manindra
 * @date        2026-11-23
 */
@IsTest
private class OpportunitySelectorTest {

    private static final String PIPELINE_ACCOUNT_NUMBER = 'OPPSEL-1';
    private static final String OTHER_ACCOUNT_NUMBER = 'OPPSEL-2';
    private static final String OPEN_EARLY_A = 'Pipeline A Early';
    private static final String OPEN_EARLY_C = 'Pipeline C Early';
    private static final String OPEN_LATER = 'Pipeline B Later';
    private static final String CLOSED_OPP = 'Pipeline Closed Won';
    private static final String OTHER_OPP = 'Other Account Opportunity';

    /**
     * @description Creates two accounts, a primary contact and five opportunities shared by all tests.
     */
    @TestSetup
    static void setup() {
        adb_Account pipelineAccount = new adb_Account()
            .name('Pipeline Selector Account')
            .accountNumber(PIPELINE_ACCOUNT_NUMBER)
            .sourceSystemId(PIPELINE_ACCOUNT_NUMBER);
        pipelineAccount.set(Account.Type, 'Customer');

        adb_Account otherAccount = new adb_Account()
            .name('Other Selector Account')
            .accountNumber(OTHER_ACCOUNT_NUMBER)
            .sourceSystemId(OTHER_ACCOUNT_NUMBER);
        otherAccount.set(Account.Type, 'Customer');

        adb_Contact primaryContact = new adb_Contact()
            .firstName('Pipeline')
            .lastName('Selector Contact')
            .account(pipelineAccount);

        buildOpportunity(OPEN_EARLY_A, pipelineAccount, primaryContact, Date.today().addDays(10), 'Discovery', 'Pipeline', 10, true);
        buildOpportunity(OPEN_EARLY_C, pipelineAccount, primaryContact, Date.today().addDays(10), 'Discovery', 'Pipeline', 10, false);
        buildOpportunity(OPEN_LATER, pipelineAccount, primaryContact, Date.today().addDays(40), 'Discovery', 'Pipeline', 10, false);
        buildOpportunity(CLOSED_OPP, pipelineAccount, primaryContact, Date.today().addDays(5), 'Closed Won', 'Won', 100, false);
        buildOpportunity(OTHER_OPP, otherAccount, primaryContact, Date.today().addDays(15), 'Discovery', 'Pipeline', 10, false);

        adb_DomainBuilder.save();
    }

    /**
     * @description Confirms an empty list is returned for a null or empty set of account Ids.
     */
    @IsTest
    static void selectByAccountIds_nullOrEmptySet_returnsEmptyList() {
        Assert.areEqual(0, OpportunitySelector.selectByAccountIds(null).size());
        Assert.areEqual(0, OpportunitySelector.selectByAccountIds(new Set<Id>()).size());
    }

    /**
     * @description Confirms open and closed opportunities are returned only for the requested accounts with their
     *              fields populated.
     */
    @IsTest
    static void selectByAccountIds_validIds_returnsOpenAndClosedForThoseAccounts() {
        Id pipelineAccountId = accountId(PIPELINE_ACCOUNT_NUMBER);
        Opportunity closedOpportunity = opportunityNamed(CLOSED_OPP);

        Test.startTest();
        List<Opportunity> results = OpportunitySelector.selectByAccountIds(new Set<Id>{ pipelineAccountId });
        Test.stopTest();

        Map<Id, Opportunity> resultsById = new Map<Id, Opportunity>(results);
        Assert.areEqual(4, results.size());
        Assert.isTrue(resultsById.containsKey(closedOpportunity.Id));
        Assert.isFalse(resultsById.containsKey(opportunityNamed(OTHER_OPP).Id));

        Opportunity closedResult = resultsById.get(closedOpportunity.Id);
        Assert.areEqual(pipelineAccountId, closedResult.AccountId);
        Assert.areEqual('Pipeline Selector Account', closedResult.Account.Name);
        Assert.areEqual('Customer', closedResult.Account.Type);
        Assert.areEqual(2500.00, closedResult.Amount);
        Assert.isTrue(closedResult.IsClosed);
        Assert.isTrue(closedResult.IsWon);
        Assert.areEqual(UserInfo.getUserId(), closedResult.OwnerId);
        Assert.isNotNull(closedResult.Owner.Name);
        Assert.isNotNull(closedResult.LastModifiedDate);

        Assert.isFalse(resultsById.get(opportunityNamed(OPEN_EARLY_A).Id).IsClosed);
    }

    /**
     * @description Confirms an empty list is returned for a null or empty set of opportunity Ids.
     */
    @IsTest
    static void selectByIds_nullOrEmptySet_returnsEmptyList() {
        Assert.areEqual(0, OpportunitySelector.selectByIds(null).size());
        Assert.areEqual(0, OpportunitySelector.selectByIds(new Set<Id>()).size());
    }

    /**
     * @description Confirms only the opportunities that exist for the given Ids are returned.
     */
    @IsTest
    static void selectByIds_validIds_returnsMatchingNames() {
        Opportunity earlyOpportunity = opportunityNamed(OPEN_EARLY_A);
        Id missingOpportunityId = fakeId(Opportunity.SObjectType, 1);

        Test.startTest();
        List<Opportunity> results = OpportunitySelector.selectByIds(
            new Set<Id>{ earlyOpportunity.Id, missingOpportunityId }
        );
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.areEqual(earlyOpportunity.Id, results[0].Id);
        Assert.areEqual(OPEN_EARLY_A, results[0].Name);
    }

    /**
     * @description Confirms an empty list is returned for a null or empty set of owner Ids.
     */
    @IsTest
    static void selectByOwnerIds_nullOrEmptySet_returnsEmptyList() {
        Assert.areEqual(0, OpportunitySelector.selectByOwnerIds(null).size());
        Assert.areEqual(0, OpportunitySelector.selectByOwnerIds(new Set<Id>()).size());
    }

    /**
     * @description Confirms all opportunities of the owner are returned and none for an unknown owner.
     */
    @IsTest
    static void selectByOwnerIds_validIds_returnsOpportunitiesForThatOwner() {
        Test.startTest();
        List<Opportunity> owned = OpportunitySelector.selectByOwnerIds(new Set<Id>{ UserInfo.getUserId() });
        List<Opportunity> unowned = OpportunitySelector.selectByOwnerIds(
            new Set<Id>{ fakeId(User.SObjectType, 99) }
        );
        Test.stopTest();

        Assert.areEqual(5, owned.size());
        for (Opportunity opportunityRecord : owned) {
            Assert.areEqual(UserInfo.getUserId(), opportunityRecord.OwnerId);
        }
        Assert.areEqual(0, unowned.size());
    }

    /**
     * @description Confirms null is returned for a null or missing Id.
     */
    @IsTest
    static void selectById_nullOrMissing_returnsNull() {
        Assert.isNull(OpportunitySelector.selectById(null));
        Assert.isNull(OpportunitySelector.selectById(fakeId(Opportunity.SObjectType, 2)));
    }

    /**
     * @description Confirms the opportunity is returned with its account, owner, pricebook, forecast confidence and
     *              record type.
     */
    @IsTest
    static void selectById_validId_returnsOpportunityDetail() {
        Opportunity earlyOpportunity = opportunityNamed(OPEN_EARLY_A);

        Test.startTest();
        Opportunity result = OpportunitySelector.selectById(earlyOpportunity.Id);
        Test.stopTest();

        Assert.areEqual(earlyOpportunity.Id, result.Id);
        Assert.areEqual(OPEN_EARLY_A, result.Name);
        Assert.areEqual(accountId(PIPELINE_ACCOUNT_NUMBER), result.AccountId);
        Assert.areEqual(UserInfo.getUserId(), result.OwnerId);
        Assert.areEqual(Test.getStandardPricebookId(), result.Pricebook2Id);
        Assert.areEqual('Pipeline', result.ForecastConfidenceLevel__c);
        Assert.areEqual('Healthcare_Sales', result.RecordType.DeveloperName);
        Assert.isNotNull(result.CurrencyIsoCode);
    }

    /**
     * @description Confirms an empty map is returned for a null or empty set of Ids.
     */
    @IsTest
    static void selectForecastConfidenceByIds_nullOrEmptySet_returnsEmptyMap() {
        Assert.isTrue(OpportunitySelector.selectForecastConfidenceByIds(null).isEmpty());
        Assert.isTrue(OpportunitySelector.selectForecastConfidenceByIds(new Set<Id>()).isEmpty());
    }

    /**
     * @description Confirms the forecast confidence level is returned for each requested opportunity.
     */
    @IsTest
    static void selectForecastConfidenceByIds_validIds_returnsConfidenceByOpportunity() {
        Opportunity openOpportunity = opportunityNamed(OPEN_LATER);
        Opportunity closedOpportunity = opportunityNamed(CLOSED_OPP);

        Test.startTest();
        Map<Id, Opportunity> results = OpportunitySelector.selectForecastConfidenceByIds(
            new Set<Id>{ openOpportunity.Id, closedOpportunity.Id }
        );
        Test.stopTest();

        Assert.areEqual(2, results.size());
        Assert.areEqual('Pipeline', results.get(openOpportunity.Id).ForecastConfidenceLevel__c);
        Assert.areEqual('Won', results.get(closedOpportunity.Id).ForecastConfidenceLevel__c);
    }

    /**
     * @description Confirms an empty list is returned for a null or empty set of account Ids.
     */
    @IsTest
    static void selectOpenPipelineByAccountIds_nullOrEmptySet_returnsEmptyList() {
        Assert.areEqual(0, OpportunitySelector.selectOpenPipelineByAccountIds(null).size());
        Assert.areEqual(0, OpportunitySelector.selectOpenPipelineByAccountIds(new Set<Id>()).size());
    }

    /**
     * @description Confirms only open opportunities of the account are returned in the expected order.
     */
    @IsTest
    static void selectOpenPipelineByAccountIds_validIds_returnsOpenOpportunitiesInOrder() {
        Test.startTest();
        List<Opportunity> results = OpportunitySelector.selectOpenPipelineByAccountIds(
            new Set<Id>{ accountId(PIPELINE_ACCOUNT_NUMBER) }
        );
        Test.stopTest();

        Assert.areEqual(
            new List<String>{ OPEN_EARLY_A, OPEN_EARLY_C, OPEN_LATER },
            namesOf(results)
        );
        for (Opportunity opportunityRecord : results) {
            Assert.areEqual(accountId(PIPELINE_ACCOUNT_NUMBER), opportunityRecord.AccountId);
            Assert.areEqual('Pipeline Selector Account', opportunityRecord.Account.Name);
            Assert.isNotNull(opportunityRecord.Owner.Name);
        }
    }

    /**
     * @description Confirms an empty map is returned for a null or empty set of Ids.
     */
    @IsTest
    static void selectByIdsForPrimaryContact_nullOrEmptySet_returnsEmptyMap() {
        OpportunitySelector selector = new OpportunitySelector();

        Assert.isTrue(selector.selectByIdsForPrimaryContact(null).isEmpty());
        Assert.isTrue(selector.selectByIdsForPrimaryContact(new Set<Id>()).isEmpty());
    }

    /**
     * @description Confirms the primary contact and record type are returned for the requested opportunity.
     */
    @IsTest
    static void selectByIdsForPrimaryContact_validIds_returnsContactAndRecordType() {
        Opportunity earlyOpportunity = opportunityNamed(OPEN_EARLY_A);
        Id contactId = [SELECT Id FROM Contact WHERE LastName = 'Selector Contact' LIMIT 1].Id;
        Id recordTypeId = Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get('Healthcare_Sales')
            .getRecordTypeId();

        Test.startTest();
        Map<Id, Opportunity> results = new OpportunitySelector()
            .selectByIdsForPrimaryContact(new Set<Id>{ earlyOpportunity.Id });
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.areEqual(contactId, results.get(earlyOpportunity.Id).PrimaryContact__c);
        Assert.areEqual(recordTypeId, results.get(earlyOpportunity.Id).RecordTypeId);
    }

    /**
     * @description GW-6603 - Confirms the Field Service lookups return nothing for a null Id or record type.
     */
    @IsTest
    static void selectFieldService_nullInputs_returnEmptyList() {
        Id fieldServiceRecordTypeId = fieldServiceRecordTypeId();
        Id anyOpportunityId = opportunityNamed(OPEN_EARLY_A).Id;

        Assert.areEqual(0, OpportunitySelector.selectFieldServiceByWorkOrderId(null, fieldServiceRecordTypeId).size());
        Assert.areEqual(0, OpportunitySelector.selectFieldServiceByWorkOrderId(fakeId(WorkOrder.SObjectType, 3), null).size());
        Assert.areEqual(0, OpportunitySelector.selectFieldServiceWithoutWorkOrderById(null, fieldServiceRecordTypeId).size());
        Assert.areEqual(0, OpportunitySelector.selectFieldServiceWithoutWorkOrderById(anyOpportunityId, null).size());
    }

    /**
     * @description GW-6603 - Confirms the Field Service opportunity linked to a Work Order is found, and only for the
     *              Field Service record type.
     */
    @IsTest
    static void selectFieldServiceByWorkOrderId_linkedOpportunity_isReturned() {
        FieldServiceQuoteTestData.Scenario scenario = FieldServiceQuoteTestData.createScenario();
        Opportunity linked = insertFieldServiceOpportunity(scenario, scenario.workOrder.Id);
        Id healthcareSalesRecordTypeId = opportunityRecordTypeId('Healthcare_Sales');

        Test.startTest();
        List<Opportunity> matches = OpportunitySelector.selectFieldServiceByWorkOrderId(
            scenario.workOrder.Id,
            fieldServiceRecordTypeId()
        );
        List<Opportunity> otherRecordType = OpportunitySelector.selectFieldServiceByWorkOrderId(
            scenario.workOrder.Id,
            healthcareSalesRecordTypeId
        );
        Test.stopTest();

        Assert.areEqual(1, matches.size());
        Assert.areEqual(linked.Id, matches[0].Id);
        Assert.areEqual(0, otherRecordType.size());
    }

    /**
     * @description GW-6603 - Confirms an account-only Field Service opportunity is found, and one already linked to a
     *              Work Order is not.
     */
    @IsTest
    static void selectFieldServiceWithoutWorkOrderById_onlyUnlinkedOpportunity_isReturned() {
        FieldServiceQuoteTestData.Scenario scenario = FieldServiceQuoteTestData.createScenario();
        Opportunity accountOnly = insertFieldServiceOpportunity(scenario, null);
        Opportunity linked = insertFieldServiceOpportunity(scenario, scenario.workOrder.Id);

        Test.startTest();
        List<Opportunity> unlinked = OpportunitySelector.selectFieldServiceWithoutWorkOrderById(
            accountOnly.Id,
            fieldServiceRecordTypeId()
        );
        List<Opportunity> alreadyLinked = OpportunitySelector.selectFieldServiceWithoutWorkOrderById(
            linked.Id,
            fieldServiceRecordTypeId()
        );
        Test.stopTest();

        Assert.areEqual(1, unlinked.size());
        Assert.areEqual(accountOnly.Id, unlinked[0].Id);
        Assert.areEqual(0, alreadyLinked.size());
    }

    /**
     * @description Inserts a Field Service opportunity the way FieldServiceQuoteService creates one.
     * @param scenario Field Service test scenario (account and Work Order).
     * @param workOrderId Work Order to link, or null for an account-only opportunity.
     * @return Inserted opportunity.
     */
    private static Opportunity insertFieldServiceOpportunity(FieldServiceQuoteTestData.Scenario scenario, Id workOrderId) {
        Opportunity opportunityRecord = new Opportunity(
            RecordTypeId = fieldServiceRecordTypeId(),
            Name = 'GW6603 Field Service Opportunity',
            AccountId = scenario.account.Id,
            WorkOrder__c = workOrderId,
            StageName = FieldServiceQuoteService.STAGE_OPEN,
            CloseDate = Date.today().addDays(FieldServiceQuoteService.QUOTE_VALIDITY_DAYS),
            CurrencyIsoCode = FieldServiceQuoteTestData.CURRENCY_CODE,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert opportunityRecord;
        return opportunityRecord;
    }

    /**
     * @description Field Service Quote opportunity record type Id.
     * @return Record type Id.
     */
    private static Id fieldServiceRecordTypeId() {
        return opportunityRecordTypeId(FieldServiceQuoteService.OPPORTUNITY_RECORD_TYPE);
    }

    /**
     * @description Opportunity record type Id by developer name.
     * @param developerName Record type developer name.
     * @return Record type Id.
     */
    private static Id opportunityRecordTypeId(String developerName) {
        return Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get(developerName).getRecordTypeId();
    }

    /**
     * @description Builds a Healthcare Sales opportunity with the given values.
     * @param name Opportunity name.
     * @param account Builder of the parent account.
     * @param primaryContact Builder of the primary contact.
     * @param closeDate Close date.
     * @param stageName Stage name.
     * @param forecastConfidence Forecast confidence level.
     * @param probability Probability.
     * @param onHold Value of the On Hold flag.
     */
    private static void buildOpportunity(
        String name,
        adb_Account account,
        adb_Contact primaryContact,
        Date closeDate,
        String stageName,
        String forecastConfidence,
        Integer probability,
        Boolean onHold
    ) {
        adb_Opportunity opportunityBuilder = new adb_Opportunity()
            .name(name)
            .account(account)
            .primaryContact(primaryContact);
        opportunityBuilder.recordType('Healthcare_Sales');
        opportunityBuilder.set(Opportunity.StageName, stageName);
        opportunityBuilder.set(Opportunity.CloseDate, closeDate);
        opportunityBuilder.set(Opportunity.Amount, 2500.00);
        opportunityBuilder.set(Opportunity.Probability, probability);
        opportunityBuilder.set(Opportunity.ForecastConfidenceLevel__c, forecastConfidence);
        opportunityBuilder.set(Opportunity.BypassValidations__c, true);
        opportunityBuilder.set(Opportunity.OnHold__c, onHold);
    }

    /**
     * @description Finds an account by account number.
     * @param accountNumber Account number to search for.
     * @return Id of the account.
     */
    private static Id accountId(String accountNumber) {
        return [SELECT Id FROM Account WHERE AccountNumber = :accountNumber LIMIT 1].Id;
    }

    /**
     * @description Finds an opportunity by name.
     * @param name Opportunity name to search for.
     * @return Matching opportunity.
     */
    private static Opportunity opportunityNamed(String name) {
        return [SELECT Id FROM Opportunity WHERE Name = :name LIMIT 1];
    }

    /**
     * @description Reads the names of the opportunities.
     * @param opportunities Opportunities to read.
     * @return Names in the same order.
     */
    private static List<String> namesOf(List<Opportunity> opportunities) {
        List<String> names = new List<String>();
        for (Opportunity opportunityRecord : opportunities) {
            names.add(opportunityRecord.Name);
        }
        return names;
    }

    /**
     * @description Builds a well formed Id that does not exist in the org.
     * @param objectType Object type the Id is built for.
     * @param suffix Number that makes the Id unique.
     * @return Fake record Id.
     */
    private static Id fakeId(Schema.SObjectType objectType, Integer suffix) {
        String digits = String.valueOf(suffix);
        return (Id) (
            objectType.getDescribe().getKeyPrefix()
            + '000000000000'.left(12 - digits.length())
            + digits
        );
    }
}