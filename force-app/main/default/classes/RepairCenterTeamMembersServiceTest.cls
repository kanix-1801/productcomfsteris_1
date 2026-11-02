/**
 * @description Tests for RepairCenterTeamMembersService used by Device Evaluation Work Performed.
 */
@IsTest
private class RepairCenterTeamMembersServiceTest {
    @IsTest
    static void testGetSignatures_nullWorkOrder() {
        Test.startTest();
        List<RepairCenterTeamMember__c> signatures =
            RepairCenterTeamMembersService.getWorkOrderLineSignatures(null);
        Test.stopTest();
        System.assertEquals(0, signatures.size());
    }

    @IsTest
    static void testAddSignature_requiresIds() {
        Boolean threw = false;
        Test.startTest();
        try {
            RepairCenterTeamMembersService.addSignature(null, null);
        } catch (RepairCenterTeamMembersService.RepairCenterTeamMembersServiceException e) {
            threw = true;
            System.assert(e.getMessage().contains('required'));
        }
        Test.stopTest();
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testRemoveSignature_requiresIds() {
        Boolean threw = false;
        Test.startTest();
        try {
            RepairCenterTeamMembersService.removeSignature(null, null);
        } catch (RepairCenterTeamMembersService.RepairCenterTeamMembersServiceException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testSignAll_requiresWorkOrder() {
        Boolean threw = false;
        Test.startTest();
        try {
            RepairCenterTeamMembersService.signAll(null, new List<Id>());
        } catch (RepairCenterTeamMembersService.RepairCenterTeamMembersServiceException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testAddSignatureForLineItem_requiresIds() {
        Boolean threw = false;
        Test.startTest();
        try {
            RepairCenterTeamMembersService.addSignatureForLineItem(null, null);
        } catch (RepairCenterTeamMembersService.RepairCenterTeamMembersServiceException e) {
            threw = true;
            System.assert(e.getMessage().contains('required'));
        }
        Test.stopTest();
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testSignAllForLineItems_nullWorkOrder_throws() {
        Boolean threw = false;
        Test.startTest();
        try {
            RepairCenterTeamMembersService.signAllForLineItems(null, new List<Id>());
        } catch (RepairCenterTeamMembersService.RepairCenterTeamMembersServiceException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testRemoveSignature_rejectsOtherUsersSignature() {
        List<User> otherUsers = [
            SELECT Id, Name
            FROM User
            WHERE IsActive = TRUE AND Id != :UserInfo.getUserId()
            LIMIT 1
        ];
        if (otherUsers.isEmpty()) {
            return;
        }
        User otherUser = otherUsers[0];

        Account customer = new Account(
            Name = 'Signature Remove Test Customer',
            SystemID__c = 'LEG-RCTM-REMOVE',
            SourceSystemID__c = 'TEST-ORACLE-RCTM-REMOVE',
            OrgIDs__c = '82'
        );
        insert customer;

        WorkOrder workOrder = new WorkOrder(
            Subject = 'Signature Remove Test WO',
            Status = 'Received',
            AccountId = customer.Id
        );
        insert workOrder;

        Id recordTypeId = Schema.SObjectType.RepairCenterTeamMember__c.getRecordTypeInfosByDeveloperName()
            .get('RepairCenter')
            ?.getRecordTypeId();
        Assert.isNotNull(recordTypeId, 'RepairCenter Team Member record type is required.');

        RepairCenterTeamMember__c otherSignature = new RepairCenterTeamMember__c(
            Name = otherUser.Name,
            Person__c = otherUser.Id,
            WorkOrder__c = workOrder.Id,
            Type__c = 'Work Order Line',
            RecordTypeId = recordTypeId
        );
        insert otherSignature;

        Boolean threw = false;
        Test.startTest();
        try {
            RepairCenterTeamMembersService.removeSignature(workOrder.Id, otherSignature.Id);
        } catch (RepairCenterTeamMembersService.RepairCenterTeamMembersServiceException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('own signature'),
                'Expected ownership validation: ' + e.getMessage()
            );
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Expected remove to fail for another user signature.');
        Assert.isNotNull(
            [SELECT Id FROM RepairCenterTeamMember__c WHERE Id = :otherSignature.Id LIMIT 1]
        );
    }

    @IsTest
    static void testAddSignatureAndSignAll_happyPaths() {
        SignatureFixture fixture = createSignatureFixture('RCTM-ADD');
        Id repairCodeRtId = WorkOrderLineItemsService.getRepairCodeRecordTypeId();
        Assert.isNotNull(repairCodeRtId, 'Repair Code record type is required.');

        Product2 secondCode = new Product2(
            Name = 'RCTM Repair ADD2',
            ProductCode = 'RCTM-ADD-2',
            ProductType__c = 'Category Code',
            IsActive = true
        );
        insert secondCode;
        PricebookEntry secondPbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = secondCode.Id,
            UnitPrice = 1,
            IsActive = true
        );
        insert secondPbe;

        WorkOrderLineItem repairLine = new WorkOrderLineItem(
            WorkOrderId = fixture.workOrder.Id,
            RecordTypeId = repairCodeRtId,
            PricebookEntryId = fixture.pricebookEntry.Id,
            Quantity = 1
        );
        repairLine.put('Product__c', fixture.repairProduct.Id);
        WorkOrderLineItem secondLine = new WorkOrderLineItem(
            WorkOrderId = fixture.workOrder.Id,
            RecordTypeId = repairCodeRtId,
            PricebookEntryId = secondPbe.Id,
            Quantity = 1
        );
        secondLine.put('Product__c', secondCode.Id);
        insert new List<WorkOrderLineItem>{ repairLine, secondLine };

        Test.startTest();
        List<RepairCenterTeamMember__c> afterAdd =
            RepairCenterTeamMembersService.addSignature(
                fixture.workOrder.Id,
                fixture.repairProduct.Id
            );
        List<RepairCenterTeamMember__c> afterRepeat =
            RepairCenterTeamMembersService.addSignature(
                fixture.workOrder.Id,
                fixture.repairProduct.Id
            );
        List<RepairCenterTeamMember__c> emptySignAll =
            RepairCenterTeamMembersService.signAll(fixture.workOrder.Id, new List<Id>());
        List<RepairCenterTeamMember__c> afterSignAll =
            RepairCenterTeamMembersService.signAll(
                fixture.workOrder.Id,
                new List<Id>{ fixture.repairProduct.Id, secondCode.Id }
            );
        Test.stopTest();

        Assert.areEqual(1, afterAdd.size(), 'Expected one signature after add.');
        Assert.areEqual(1, afterRepeat.size(), 'Repeat add should not duplicate.');
        Assert.areEqual(1, emptySignAll.size());
        Assert.areEqual(2, afterSignAll.size(), 'signAll should add the second repair code.');
        WorkOrderLineItem assigned = [
            SELECT AssignedResourceUser__c
            FROM WorkOrderLineItem
            WHERE Id = :secondLine.Id
        ];
        Assert.areEqual(UserInfo.getUserId(), assigned.AssignedResourceUser__c);
    }

    @IsTest
    static void testAddSignatureForLineItemAndSignAllForLineItems_happyPaths() {
        SignatureFixture fixture = createSignatureFixture('RCTM-LI');
        Id repairCodeRtId = WorkOrderLineItemsService.getRepairCodeRecordTypeId();
        Assert.isNotNull(repairCodeRtId, 'Repair Code record type is required.');

        Product2 secondCode = new Product2(
            Name = 'RCTM Repair 2',
            ProductCode = 'RCTM-RC-2',
            ProductType__c = 'Category Code',
            IsActive = true
        );
        insert secondCode;
        PricebookEntry secondPbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = secondCode.Id,
            UnitPrice = 1,
            IsActive = true
        );
        insert secondPbe;

        WorkOrderLineItem lineA = new WorkOrderLineItem(
            WorkOrderId = fixture.workOrder.Id,
            RecordTypeId = repairCodeRtId,
            PricebookEntryId = fixture.pricebookEntry.Id,
            Quantity = 1
        );
        lineA.put('Product__c', fixture.repairProduct.Id);
        WorkOrderLineItem lineB = new WorkOrderLineItem(
            WorkOrderId = fixture.workOrder.Id,
            RecordTypeId = repairCodeRtId,
            PricebookEntryId = secondPbe.Id,
            Quantity = 1
        );
        lineB.put('Product__c', secondCode.Id);
        insert new List<WorkOrderLineItem>{ lineA, lineB };

        Test.startTest();
        List<RepairCenterTeamMember__c> afterAdd =
            RepairCenterTeamMembersService.addSignatureForLineItem(
                fixture.workOrder.Id,
                lineA.Id
            );
        List<RepairCenterTeamMember__c> emptyIds =
            RepairCenterTeamMembersService.signAllForLineItems(
                fixture.workOrder.Id,
                new List<Id>()
            );
        List<RepairCenterTeamMember__c> afterSignAll =
            RepairCenterTeamMembersService.signAllForLineItems(
                fixture.workOrder.Id,
                new List<Id>{ lineA.Id, lineB.Id }
            );
        Id signatureId = afterSignAll[0].Id;
        List<RepairCenterTeamMember__c> afterRemove =
            RepairCenterTeamMembersService.removeSignature(fixture.workOrder.Id, signatureId);
        Test.stopTest();

        Assert.areEqual(1, afterAdd.size());
        Assert.areEqual(1, emptyIds.size());
        Assert.areEqual(2, afterSignAll.size(), 'Expected signatures for both lines.');
        Assert.areEqual(1, afterRemove.size(), 'One signature remains after remove.');
    }

    @IsTest
    static void testAddSignature_missingRepairCodeLine_throws() {
        SignatureFixture fixture = createSignatureFixture('RCTM-MISS');
        Boolean threw = false;
        Test.startTest();
        try {
            RepairCenterTeamMembersService.addSignature(
                fixture.workOrder.Id,
                fixture.repairProduct.Id
            );
        } catch (RepairCenterTeamMembersService.RepairCenterTeamMembersServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('Save the evaluation'));
        }
        Test.stopTest();
        Assert.isTrue(threw);
    }

    @IsTest
    static void testAddSignatureForLineItem_wrongLine_throws() {
        SignatureFixture fixture = createSignatureFixture('RCTM-BAD');
        Id productServicedRtId = Schema.SObjectType.WorkOrderLineItem.getRecordTypeInfosByDeveloperName()
            .get('ProductServiced')
            ?.getRecordTypeId();
        Assert.isNotNull(productServicedRtId);

        WorkOrderLineItem wrongLine = new WorkOrderLineItem(
            WorkOrderId = fixture.workOrder.Id,
            RecordTypeId = productServicedRtId,
            PricebookEntryId = fixture.pricebookEntry.Id,
            Quantity = 1
        );
        insert wrongLine;

        Boolean threw = false;
        Test.startTest();
        try {
            RepairCenterTeamMembersService.addSignatureForLineItem(
                fixture.workOrder.Id,
                wrongLine.Id
            );
        } catch (RepairCenterTeamMembersService.RepairCenterTeamMembersServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('Repair Code line'));
        }
        Test.stopTest();
        Assert.isTrue(threw);
    }

    @IsTest
    static void testRemoveSignature_missingSignature_throws() {
        SignatureFixture fixture = createSignatureFixture('RCTM-NOSIG');
        Id fakeSignatureId = Schema.SObjectType.RepairCenterTeamMember__c.getKeyPrefix() +
            '000000000001';
        Boolean threw = false;
        Test.startTest();
        try {
            RepairCenterTeamMembersService.removeSignature(fixture.workOrder.Id, fakeSignatureId);
        } catch (RepairCenterTeamMembersService.RepairCenterTeamMembersServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('not found'));
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        Assert.isTrue(threw);
    }

    @IsTest
    static void testRequireWorkOrder_missing_throws() {
        Id fakeWoId = Schema.SObjectType.WorkOrder.getKeyPrefix() + '000000000001';
        Boolean threw = false;
        Test.startTest();
        try {
            RepairCenterTeamMembersService.addSignature(fakeWoId, fakeWoId);
        } catch (RepairCenterTeamMembersService.RepairCenterTeamMembersServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('not found'));
        }
        Test.stopTest();
        Assert.isTrue(threw);
    }

    private class SignatureFixture {
        Account customer;
        WorkOrder workOrder;
        Product2 repairProduct;
        PricebookEntry pricebookEntry;
    }

    private static SignatureFixture createSignatureFixture(String key) {
        String suffix = key.right(6);
        SignatureFixture fixture = new SignatureFixture();
        fixture.customer = new Account(
            Name = 'RCTM ' + key,
            SystemID__c = ('LEG-' + suffix).left(15),
            SourceSystemID__c = 'TEST-ORACLE-' + key,
            OrgIDs__c = '82'
        );
        insert fixture.customer;

        fixture.workOrder = new WorkOrder(
            Subject = 'RCTM WO ' + key,
            Status = 'Received',
            AccountId = fixture.customer.Id,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert fixture.workOrder;

        fixture.repairProduct = new Product2(
            Name = 'RCTM Repair ' + key,
            ProductCode = 'RC-' + key,
            ProductType__c = 'Category Code',
            IsActive = true
        );
        insert fixture.repairProduct;

        fixture.pricebookEntry = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = fixture.repairProduct.Id,
            UnitPrice = 1,
            IsActive = true
        );
        insert fixture.pricebookEntry;
        return fixture;
    }
}