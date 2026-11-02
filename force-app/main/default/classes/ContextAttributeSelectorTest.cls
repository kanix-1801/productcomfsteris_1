/**
 * @description Tests for ContextAttributeSelector.
 */
@IsTest
private class ContextAttributeSelectorTest {

    /**
     * @description Null or empty titles return an empty list without querying.
     */
    @IsTest
    static void testSelectByTitlesBlankInput() {
        User contextUser = new User(Id = UserInfo.getUserId());
        Assert.areEqual(0, Limits.getQueries(), 'No queries should have run yet');

        List<ContextAttribute> fromNull;
        List<ContextAttribute> fromEmpty;
        Test.startTest();
        System.runAs(contextUser) {
            fromNull = ContextAttributeSelector.selectByTitles(null);
            fromEmpty = ContextAttributeSelector.selectByTitles(new List<String>());
        }
        Test.stopTest();

        Assert.isTrue(fromNull.isEmpty(), 'Null titles should return an empty list');
        Assert.isTrue(fromEmpty.isEmpty(), 'Empty titles should return an empty list');
    }

    /**
     * @description Titles with no matching context attribute return an empty list.
     */
    @IsTest
    static void testSelectByTitlesNoMatch() {
        User contextUser = new User(Id = UserInfo.getUserId());
        List<String> titles = new List<String>{ 'ESPC_Not_A_Context_Attribute__c' };

        Assert.areEqual(0, [SELECT COUNT() FROM ContextAttribute WHERE Title IN :titles],
                        'No context attribute should have this title');

        List<ContextAttribute> results;
        Test.startTest();
        System.runAs(contextUser) {
            results = ContextAttributeSelector.selectByTitles(titles);
        }
        Test.stopTest();
        Assert.isTrue(results.isEmpty(), 'Unknown titles should return an empty list');
    }
}