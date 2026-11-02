/**
 * @author Suraj Thapliyal
 * @date 2026/08/13
 *
 * @group Temporary Access Exception
 *
 * @description
 * GC-3333 - Tests for TAEAssignedRecordSelector dedupe key queries.
 */
@IsTest(SeeAllData=false)
private class TAEAssignedRecordSelectorTest {

    /**
     * @description
     * Creates users, account, opportunity, and requester team memberships via the test data factory.
     *
     * @return void
     */
    @TestSetup
    static void setupData() {
        TestDataFactory.setupBaseScenario();
    }

    /**
     * @description
     * Verifies blank inputs return empty key sets without querying assigned records.
     *
     * @return void
     */
    @IsTest
    static void testBlankInputReturnsEmptySets() {
        Test.startTest();
        System.assertEquals(
            0,
            TAEAssignedRecordSelector.selectExistingAccountKeys(null, null).size(),
            'Null account inputs should return an empty key set'
        );
        System.assertEquals(
            0,
            TAEAssignedRecordSelector.selectExistingAccountKeys(new Set<Id>(), new Set<Id>()).size(),
            'Empty account inputs should return an empty key set'
        );
        System.assertEquals(
            0,
            TAEAssignedRecordSelector.selectExistingOpportunityKeys(null, null).size(),
            'Null opportunity inputs should return an empty key set'
        );
        System.assertEquals(
            0,
            TAEAssignedRecordSelector.selectExistingOpportunityKeys(new Set<Id>(), new Set<Id>()).size(),
            'Empty opportunity inputs should return an empty key set'
        );
        Test.stopTest();
    }

    /**
     * @description
     * Verifies composite key builders use taeId|recordId format.
     *
     * @return void
     */
    @IsTest
    static void testKeyBuilders() {
        Id taeId = TestDataFactory.insertGrantTae(
            TestDataFactory.getRequester().Id,
            TestDataFactory.getCoverageRep().Id
        ).Id;
        Id accountId = TestDataFactory.getTestAccount().Id;

        Test.startTest();
        System.assertEquals(
            String.valueOf(taeId) + '|' + String.valueOf(accountId),
            TAEAssignedRecordSelector.buildAccountKey(taeId, accountId),
            'Account key should use taeId|accountId format'
        );
        Test.stopTest();
    }

    /**
     * @description
     * Verifies selector returns existing account and opportunity keys for seeded assigned records.
     *
     * @return void
     */
    @IsTest
    static void testSelectExistingKeysReturnsSeededRows() {
        TestDataFactory.ScenarioContext ctx = TestDataFactory.getScenarioContext();
        TemporaryAccessException__c tae = TestDataFactory.insertGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );

        insert new TAE_AssignedRecord__c(
            TemporaryAccessException__c = tae.Id,
            Account__c = ctx.accountId
        );
        if (ctx.hasOpportunity && ctx.opportunityId != null) {
            insert new TAE_AssignedRecord__c(
                TemporaryAccessException__c = tae.Id,
                Opportunity__c = ctx.opportunityId
            );
        }

        Set<Id> taeIds = new Set<Id>{ tae.Id };
        Set<Id> accountIds = new Set<Id>{ ctx.accountId };
        Set<Id> opportunityIds = ctx.opportunityId != null
            ? new Set<Id>{ ctx.opportunityId }
            : new Set<Id>();

        Test.startTest();
        Set<String> accountKeys = TAEAssignedRecordSelector.selectExistingAccountKeys(taeIds, accountIds);
        Set<String> opportunityKeys = TAEAssignedRecordSelector.selectExistingOpportunityKeys(
            taeIds,
            opportunityIds
        );
        Test.stopTest();

        System.assertEquals(
            1,
            accountKeys.size(),
            'Expected one existing account key'
        );
        System.assert(
            accountKeys.contains(
                TAEAssignedRecordSelector.buildAccountKey(tae.Id, ctx.accountId)
            ),
            'Expected seeded account key to be returned'
        );
        if (ctx.hasOpportunity && ctx.opportunityId != null) {
            System.assertEquals(
                1,
                opportunityKeys.size(),
                'Expected one existing opportunity key'
            );
            System.assert(
                opportunityKeys.contains(
                    TAEAssignedRecordSelector.buildOpportunityKey(tae.Id, ctx.opportunityId)
                ),
                'Expected seeded opportunity key to be returned'
            );
        } else {
            System.assertEquals(0, opportunityKeys.size(), 'No opportunity keys expected when opp is absent');
        }
    }

    /**
     * @description
     * GC-3333 - Verifies UI count and page queries return seeded Account assignment rows.
     *
     * @return void
     */
    @IsTest
    static void testUiAccountQueriesReturnSeededRows() {
        TestDataFactory.ScenarioContext ctx = TestDataFactory.getScenarioContext();
        TemporaryAccessException__c tae = TestDataFactory.insertGrantTae(
            ctx.requesterId,
            ctx.coverageRepId
        );

        insert new TAE_AssignedRecord__c(
            TemporaryAccessException__c = tae.Id,
            Account__c = ctx.accountId
        );

        Test.startTest();
        Integer totalCount = TAEAssignedRecordSelector.countAccountAssignmentsByTaeId(tae.Id, null);
        List<TAE_AssignedRecord__c> pageRows = TAEAssignedRecordSelector.selectAccountAssignmentsByTaeId(
            tae.Id,
            null,
            10,
            0,
            'ASC'
        );
        Test.stopTest();

        System.assertEquals(1, totalCount, 'Expected one assigned account row');
        System.assertEquals(1, pageRows.size(), 'Expected one assigned account row on page 1');
        System.assertEquals(ctx.accountId, pageRows[0].Account__c, 'Expected assigned Account Id');
    }
}