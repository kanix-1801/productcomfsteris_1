/**
 * @description Tests for VendorRequiredProductRulesSelector.
 */
@IsTest
private class VendorRequiredProductRulesSelectorTest {
    @IsTest
    static void testActiveRulesQuery_builtByCaller_returnsOnlyActiveRules() {
        Test.startTest();
        List<VendorRequiredProductRule__mdt> rules =
            (List<VendorRequiredProductRule__mdt>) new VendorRequiredProductRulesSelector()
                .selectFields(
                    new List<String>{
                        'ProductLine__c',
                        'SubProductLine__c',
                        'DeviceType__c',
                        'IsActive__c'
                    }
                )
                .whereEquals('IsActive__c', true)
                .execute();
        Test.stopTest();

        Assert.isNotNull(rules, 'Active rule query should return a list');
        for (VendorRequiredProductRule__mdt rule : rules) {
            Assert.isTrue(rule.IsActive__c, 'Only active rules should be returned');
        }
    }
}