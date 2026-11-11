/**
 * @description Tests for RepairCenterRoutingRulesSelector.
 */
@IsTest
private class RepairCenterRoutingRulesSelectorTest {

    @TestSetup
    static void setup() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'RCRR Sel Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        insert new RepairCenterRoutingRule__c(
            OperatingUnit__c = '82',
            ProductLine__c = 'Surgical',
            RepairCenter__c = repairCenter.Id
        );
    }

    @IsTest
    static void selectById_nullOrEmpty_returnsEmpty() {
        Assert.areEqual(0, RepairCenterRoutingRulesSelector.selectById(null).size());
        Assert.areEqual(0, RepairCenterRoutingRulesSelector.selectById(new Set<Id>()).size());
    }

    @IsTest
    static void selectById_validIds_returnsRows() {
        RepairCenterRoutingRule__c rule = [SELECT Id FROM RepairCenterRoutingRule__c LIMIT 1];

        Test.startTest();
        List<RepairCenterRoutingRule__c> results =
            RepairCenterRoutingRulesSelector.selectById(new Set<Id>{ rule.Id });
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.areEqual(rule.Id, results[0].Id);
    }

    @IsTest
    static void selectAllActive_returnsInsertedRule() {
        RepairCenterRoutingRule__c rule = [SELECT Id FROM RepairCenterRoutingRule__c LIMIT 1];

        Test.startTest();
        List<RepairCenterRoutingRule__c> results =
            RepairCenterRoutingRulesSelector.selectAllActive();
        Test.stopTest();

        Boolean found = false;
        for (RepairCenterRoutingRule__c row : results) {
            if (row.Id == rule.Id) {
                found = true;
                break;
            }
        }
        Assert.isTrue(found, 'selectAllActive should include the inserted routing rule');
    }

    @IsTest
    static void selectByOperatingUnitForCreateReturnOrder_blank_returnsEmpty() {
        Assert.areEqual(
            0,
            RepairCenterRoutingRulesSelector.selectByOperatingUnitForCreateReturnOrder(null)
                .size()
        );
        Assert.areEqual(
            0,
            RepairCenterRoutingRulesSelector.selectByOperatingUnitForCreateReturnOrder('  ')
                .size()
        );
    }

    @IsTest
    static void selectByOperatingUnitForCreateReturnOrder_validUnit_returnsRows() {
        Test.startTest();
        List<RepairCenterRoutingRule__c> results =
            RepairCenterRoutingRulesSelector.selectByOperatingUnitForCreateReturnOrder('82');
        Test.stopTest();

        Assert.isFalse(results.isEmpty());
        Assert.areEqual('82', results[0].OperatingUnit__c);
        Assert.isNotNull(results[0].RepairCenter__c);
    }
}