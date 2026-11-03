/**
 * @description Tests for ContextAttributeSelector.
 */
@IsTest
private class ContextAttributeSelectorTest {

    /**
     * @description The selector builds queries against ContextAttribute.
     */
    @IsTest
    static void testSelectorBuildsContextAttributeQuery() {
        ContextAttributeSelector selector = new ContextAttributeSelector();

        Assert.isNotNull(selector, 'The selector should be created');

        Test.startTest();
        String soql = selector.selectFields(new List<String>{ 'Id', 'Title' }).orderBy('Title').toSoql();
        Test.stopTest();
        Assert.isTrue(soql.contains('FROM ContextAttribute'), 'Query should target ContextAttribute: ' + soql);
    }

    /**
     * @description Titles with no matching context attribute return an empty list.
     */
    @IsTest
    static void testSelectByTitleNoMatch() {
        User contextUser = new User(Id = UserInfo.getUserId());
        List<String> titles = new List<String>{ 'ESPC_Not_A_Context_Attribute__c' };

        Assert.areEqual(0, [SELECT COUNT() FROM ContextAttribute WHERE Title IN :titles],
                        'No context attribute should have this title');

        List<ContextAttribute> results;
        Test.startTest();
        System.runAs(contextUser) {
            results = (List<ContextAttribute>) new ContextAttributeSelector()
                .selectFields(new List<String>{ 'Id', 'Title' })
                .whereField('Title', 'IN', titles)
                .execute();
        }
        Test.stopTest();
        Assert.isTrue(results.isEmpty(), 'Unknown titles should return an empty list');
    }
}