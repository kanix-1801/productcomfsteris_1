/**
 * @description Tests for ROLIItemTypeandProductLineSelector (SoqlQueryBuilder shell).
 */
@IsTest(SeeAllData=false)
private class ROLIItemTypeandProductLineSelectorTest {
    @IsTest
    static void testCallerBuiltActiveMappingsQuery_returnsRows() {
        Test.startTest();
        List<ROLIItemTypeandProductLine__mdt> mappings =
            (List<ROLIItemTypeandProductLine__mdt>) new ROLIItemTypeandProductLineSelector()
                .selectFields(new List<String>{ 'ItemType__c', 'ProductLine__c' })
                .whereField('ItemType__c', '!=', null)
                .whereField('ProductLine__c', '!=', null)
                .whereEquals('IsActive__c', true)
                .execute();
        Test.stopTest();

        Assert.isNotNull(mappings);
        Assert.isFalse(mappings.isEmpty(), 'Expected at least one active mapping');
    }

    @IsTest
    static void testCallerBuiltItemTypeQuery_excludesEndocamWhenRequested() {
        Test.startTest();
        List<ROLIItemTypeandProductLine__mdt> rows =
            (List<ROLIItemTypeandProductLine__mdt>) new ROLIItemTypeandProductLineSelector()
                .selectFields(new List<String>{ 'ItemType__c' })
                .whereField('ItemType__c', '!=', null)
                .whereEquals('IsActive__c', true)
                .whereField('ItemType__c', '!=', 'EndoCam')
                .orderBy('ItemType__c')
                .execute();
        Test.stopTest();

        Assert.isNotNull(rows);
        for (ROLIItemTypeandProductLine__mdt row : rows) {
            Assert.areNotEqual('EndoCam', row.ItemType__c);
        }
    }
}