/**
 * @description GCL-79 - Tests for the Life Sciences methods added to TASSelector.
 *              Healthcare TASSelector methods are not exercised here.
 */
@IsTest
private class LSTASSelectorTest {

    private static final Set<String> LIFE_SCIENCES_CLASS_CODES = new Set<String>{ 'SC' };
    private static final Integer ROW_LIMIT = 200;

    @IsTest
    static void lifeSciencesTerritoryMethodsReturnOnlyMatchingClassCodes() {
        insert new List<OrderLineContact__c>{
            territory('LS-TAS-ADDR-1', 'LS-TAS-100', 'Life Sciences East', '100', 'SC'),
            territory('LS-TAS-ADDR-1B', 'LS-TAS-100', 'Life Sciences East Duplicate', '100', 'SC'),
            territory('HC-TAS-ADDR-1', 'HC-TAS-100', 'Healthcare East', '100', 'HC')
        };

        Test.startTest();
        List<OrderLineContact__c> bySearch = TASSelector.selectLifeSciencesTerritoriesBySearch(
            'LS-TAS-100',
            LIFE_SCIENCES_CLASS_CODES,
            ROW_LIMIT
        );
        List<OrderLineContact__c> byId = TASSelector.selectLifeSciencesTerritoriesByIds(
            new Set<String>{ 'LS-TAS-100', 'HC-TAS-100' },
            LIFE_SCIENCES_CLASS_CODES
        );
        Test.stopTest();

        System.assertEquals(2, bySearch.size());
        System.assertEquals(2, byId.size());
        for (OrderLineContact__c row : byId) {
            System.assertEquals('LS-TAS-100', row.TerritoryID__c);
            System.assertNotEquals(null, row.TASAddressId__c);
        }
    }

    @IsTest
    static void lifeSciencesTerritoryMethodsRejectEmptyCriteria() {
        Test.startTest();
        System.assertEquals(0, TASSelector.selectLifeSciencesTerritoriesBySearch(null, LIFE_SCIENCES_CLASS_CODES, ROW_LIMIT).size());
        System.assertEquals(0, TASSelector.selectLifeSciencesTerritoriesBySearch('LS', null, ROW_LIMIT).size());
        System.assertEquals(0, TASSelector.selectLifeSciencesTerritoriesBySearch('LS', LIFE_SCIENCES_CLASS_CODES, 0).size());
        System.assertEquals(0, TASSelector.selectLifeSciencesTerritoriesByIds(null, LIFE_SCIENCES_CLASS_CODES).size());
        System.assertEquals(0, TASSelector.selectLifeSciencesTerritoriesByIds(new Set<String>(), LIFE_SCIENCES_CLASS_CODES).size());
        System.assertEquals(0, TASSelector.selectLifeSciencesTerritoriesByIds(new Set<String>{ 'LS-TAS-100' }, null).size());
        Test.stopTest();
    }

    private static OrderLineContact__c territory(
        String tasAddressId,
        String territoryId,
        String description,
        String territoryNumber,
        String classCode
    ) {
        return new OrderLineContact__c(
            TASAddressId__c = tasAddressId,
            TerritoryID__c = territoryId,
            TerritoryDescription__c = description,
            TerritoryNumber__c = territoryNumber,
            ClassCode__c = classCode,
            BusinessUnit__c = classCode == 'SC' ? 'Life Sciences' : 'Healthcare'
        );
    }
}