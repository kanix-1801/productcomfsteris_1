/**
 * @description Tests for VendorRequiredProductRulesSelector.
 */
@IsTest
private class VendorRequiredProductRulesSelectorTest {
    @IsTest
    static void testSelectActive_returnsOnlyActiveRules() {
        Test.startTest();
        List<VendorRequiredProductRule__mdt> rules = VendorRequiredProductRulesSelector.selectActive();
        Test.stopTest();

        Assert.isNotNull(rules, 'Active rule query should return a list');
        for (VendorRequiredProductRule__mdt rule : rules) {
            Assert.isTrue(rule.IsActive__c, 'Only active rules should be returned');
        }
    }
}