/**
 * @description Test coverage for OpportunitySelector.
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

    @IsTest
    static void selectByAccountIds_nullOrEmptySet_returnsEmptyList() {
        Assert.areEqual(0, OpportunitySelector.selectByAccountIds(null).size());
        Assert.areEqual(0, OpportunitySelector.selectByAccountIds(new Set<Id>()).size());
    }

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

    @IsTest
    static void selectByIds_nullOrEmptySet_returnsEmptyList() {
        Assert.areEqual(0, OpportunitySelector.selectByIds(null).size());
        Assert.areEqual(0, OpportunitySelector.selectByIds(new Set<Id>()).size());
    }

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

    @IsTest
    static void selectByOwnerIds_nullOrEmptySet_returnsEmptyList() {
        Assert.areEqual(0, OpportunitySelector.selectByOwnerIds(null).size());
        Assert.areEqual(0, OpportunitySelector.selectByOwnerIds(new Set<Id>()).size());
    }

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

    @IsTest
    static void selectById_nullOrMissing_returnsNull() {
        Assert.isNull(OpportunitySelector.selectById(null));
        Assert.isNull(OpportunitySelector.selectById(fakeId(Opportunity.SObjectType, 2)));
    }

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
        Assert.isTrue(result.OnHold__c);
        Assert.isNotNull(result.CurrencyIsoCode);
    }

    @IsTest
    static void selectForecastConfidenceByIds_nullOrEmptySet_returnsEmptyMap() {
        Assert.isTrue(OpportunitySelector.selectForecastConfidenceByIds(null).isEmpty());
        Assert.isTrue(OpportunitySelector.selectForecastConfidenceByIds(new Set<Id>()).isEmpty());
    }

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

    @IsTest
    static void selectOpenPipelineByAccountIds_nullOrEmptySet_returnsEmptyList() {
        Assert.areEqual(0, OpportunitySelector.selectOpenPipelineByAccountIds(null).size());
        Assert.areEqual(0, OpportunitySelector.selectOpenPipelineByAccountIds(new Set<Id>()).size());
    }

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

    @IsTest
    static void selectByIdsForPrimaryContact_nullOrEmptySet_returnsEmptyMap() {
        OpportunitySelector selector = new OpportunitySelector();

        Assert.isTrue(selector.selectByIdsForPrimaryContact(null).isEmpty());
        Assert.isTrue(selector.selectByIdsForPrimaryContact(new Set<Id>()).isEmpty());
    }

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

    private static Id accountId(String accountNumber) {
        return [SELECT Id FROM Account WHERE AccountNumber = :accountNumber LIMIT 1].Id;
    }

    private static Opportunity opportunityNamed(String name) {
        return [SELECT Id FROM Opportunity WHERE Name = :name LIMIT 1];
    }

    private static List<String> namesOf(List<Opportunity> opportunities) {
        List<String> names = new List<String>();
        for (Opportunity opportunityRecord : opportunities) {
            names.add(opportunityRecord.Name);
        }
        return names;
    }

    private static Id fakeId(Schema.SObjectType objectType, Integer suffix) {
        String digits = String.valueOf(suffix);
        return (Id) (
            objectType.getDescribe().getKeyPrefix()
            + '000000000000'.left(12 - digits.length())
            + digits
        );
    }
}