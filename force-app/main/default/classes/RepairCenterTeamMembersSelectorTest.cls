/**
 * @description Tests for RepairCenterTeamMembersSelector.
 */
@IsTest
private class RepairCenterTeamMembersSelectorTest {

    private class Fixture {
        WorkOrder workOrder;
        WorkOrderLineItem lineItem;
        RepairCenterTeamMember__c signature;
    }

    private static Fixture createFixture(String suffix) {
        Account customer = new Account(
            Name = 'RCTM Sel Customer ' + suffix,
            SystemID__c = ('R' + suffix).left(15),
            SourceSystemID__c = 'TEST-ORACLE-RCTM-SEL-' + suffix,
            OrgIDs__c = '82'
        );
        insert customer;

        WorkOrder workOrder = new WorkOrder(
            Subject = 'RCTM Sel WO ' + suffix,
            Status = 'Received',
            AccountId = customer.Id,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert workOrder;

        Product2 product = new Product2(
            Name = 'RCTM Sel Product ' + suffix,
            ProductCode = 'RCTM-SEL-' + suffix,
            IsActive = true
        );
        insert product;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );
        insert pbe;

        WorkOrderLineItem lineItem = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1
        );
        lineItem.put('Product__c', product.Id);
        insert lineItem;

        Id recordTypeId = Schema.SObjectType.RepairCenterTeamMember__c
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCenter')
            ?.getRecordTypeId();

        RepairCenterTeamMember__c signature = new RepairCenterTeamMember__c(
            Name = UserInfo.getName(),
            Person__c = UserInfo.getUserId(),
            WorkOrder__c = workOrder.Id,
            WorkOrderLineItem__c = lineItem.Id,
            Type__c = 'Work Order Line'
        );
        if (recordTypeId != null) {
            signature.RecordTypeId = recordTypeId;
        }
        insert signature;

        Fixture fixture = new Fixture();
        fixture.workOrder = workOrder;
        fixture.lineItem = lineItem;
        fixture.signature = signature;
        return fixture;
    }

    @IsTest
    static void selectWorkOrderLineSignatures_null_returnsEmpty() {
        Assert.areEqual(
            0,
            RepairCenterTeamMembersSelector.selectWorkOrderLineSignatures(null).size()
        );
    }

    @IsTest
    static void selectWorkOrderLineSignatures_validWorkOrder_returnsRows() {
        Fixture fixture = createFixture('SIG');

        Test.startTest();
        List<RepairCenterTeamMember__c> results =
            RepairCenterTeamMembersSelector.selectWorkOrderLineSignatures(fixture.workOrder.Id);
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.areEqual(fixture.signature.Id, results[0].Id);
        Assert.areEqual(fixture.lineItem.Id, results[0].WorkOrderLineItem__c);
    }

    @IsTest
    static void selectByIdForWorkOrder_nullGuards_returnNull() {
        Fixture fixture = createFixture('BYID');

        Assert.isNull(
            RepairCenterTeamMembersSelector.selectByIdForWorkOrder(null, fixture.workOrder.Id)
        );
        Assert.isNull(
            RepairCenterTeamMembersSelector.selectByIdForWorkOrder(fixture.signature.Id, null)
        );
    }

    @IsTest
    static void selectByIdForWorkOrder_matchingIds_returnsRow() {
        Fixture fixture = createFixture('MATCH');

        Test.startTest();
        RepairCenterTeamMember__c result = RepairCenterTeamMembersSelector.selectByIdForWorkOrder(
            fixture.signature.Id,
            fixture.workOrder.Id
        );
        RepairCenterTeamMember__c missing = RepairCenterTeamMembersSelector.selectByIdForWorkOrder(
            fixture.signature.Id,
            UserInfo.getUserId()
        );
        Test.stopTest();

        Assert.isNotNull(result);
        Assert.areEqual(fixture.signature.Id, result.Id);
        Assert.isNull(missing);
    }

    @IsTest
    static void selectIdsByWorkOrderLineItemIds_nullOrEmpty_returnsEmpty() {
        Assert.areEqual(
            0,
            RepairCenterTeamMembersSelector.selectIdsByWorkOrderLineItemIds(null).size()
        );
        Assert.areEqual(
            0,
            RepairCenterTeamMembersSelector.selectIdsByWorkOrderLineItemIds(new Set<Id>()).size()
        );
    }

    @IsTest
    static void selectIdsByWorkOrderLineItemIds_validIds_returnsRows() {
        Fixture fixture = createFixture('WOLI');

        Test.startTest();
        List<RepairCenterTeamMember__c> results =
            RepairCenterTeamMembersSelector.selectIdsByWorkOrderLineItemIds(
                new Set<Id>{ fixture.lineItem.Id }
            );
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.areEqual(fixture.signature.Id, results[0].Id);
    }
}