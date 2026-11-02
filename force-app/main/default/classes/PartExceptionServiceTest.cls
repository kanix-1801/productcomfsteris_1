/**
 * @description Tests for GW-3329 part exception checks, case creation, and rejection notice.
 * @group Work Order Debrief
 * @see PartExceptionService
 */
@IsTest
private class PartExceptionServiceTest {
    @IsTest
    static void checkProductItemApproval_blankStatus_allowsRequest() {
        ProductItem item = insertProductItem(null);

        Test.startTest();
        PartExceptionService.PartExceptionCheck result =
            PartExceptionService.checkProductItemApproval(item.Id);
        Test.stopTest();

        System.assertEquals(true, result.allowed);
        System.assertEquals(false, result.alreadyApproved);
    }

    @IsTest
    static void checkProductItemApproval_rejected_blocksRequest() {
        ProductItem item = insertProductItem(PartExceptionService.STATUS_REJECTED);

        PartExceptionService.PartExceptionCheck result =
            PartExceptionService.checkProductItemApproval(item.Id);

        System.assertEquals(false, result.allowed);
        System.assertEquals(PartExceptionService.MESSAGE_REJECTED, result.message);
    }

    @IsTest
    static void checkProductItemApproval_inApprovals_blocksRequest() {
        ProductItem item = insertProductItem(PartExceptionService.STATUS_IN_APPROVALS);

        PartExceptionService.PartExceptionCheck result =
            PartExceptionService.checkProductItemApproval(item.Id);

        System.assertEquals(false, result.allowed);
        System.assertEquals(PartExceptionService.MESSAGE_IN_APPROVALS, result.message);
    }

    @IsTest
    static void checkProductItemApproval_approved_skipsNewRequest() {
        ProductItem item = insertProductItem(PartExceptionService.STATUS_APPROVED);

        PartExceptionService.PartExceptionCheck result =
            PartExceptionService.checkProductItemApproval(item.Id);

        System.assertEquals(true, result.allowed);
        System.assertEquals(true, result.alreadyApproved);
    }

    @IsTest
    static void checkProductItemApproval_nullId_allowsRequest() {
        PartExceptionService.PartExceptionCheck result =
            PartExceptionService.checkProductItemApproval(null);

        System.assertEquals(true, result.allowed);
        System.assertEquals(false, result.alreadyApproved);
    }

    @IsTest
    static void checkProductItemApproval_unknownId_allowsRequest() {
        Id missingProductItemId = fakeId(ProductItem.SObjectType);

        PartExceptionService.PartExceptionCheck result =
            PartExceptionService.checkProductItemApproval(missingProductItemId);

        System.assertEquals(true, result.allowed);
        System.assertEquals(null, result.status);
    }

    @IsTest
    static void submitPartException_createsCaseAndMarksProductItem() {
        ProductItem item = insertProductItem(null);
        WorkOrderLineItem line = insertPartLine(item.Id, false);

        Test.startTest();
        Id caseId = PartExceptionService.submitPartException(line.Id);
        Id secondCaseId = PartExceptionService.submitPartException(line.Id);
        Test.stopTest();

        System.assertEquals(caseId, secondCaseId, 'A second submit should reuse the existing case.');

        Case createdCase = [
            SELECT
                Id,
                WorkOrderLineItem__c,
                Description,
                Subject,
                RecordType.DeveloperName
            FROM Case
            WHERE Id = :caseId
        ];
        System.assertEquals(line.Id, createdCase.WorkOrderLineItem__c);
        System.assertEquals('InboxSupport', createdCase.RecordType.DeveloperName);
        System.assert(createdCase.Subject.contains('Part exception'));
        System.assert(createdCase.Description.contains('Work Order Line Item:'));
        System.assert(createdCase.Description.contains('/lightning/r/WorkOrderLineItem/' + line.Id + '/view'));
        System.assert(createdCase.Description.contains('Missing from SBOM'));
        System.assert(createdCase.Description.contains('Needed to finish the repair'));

        ProductItem updatedItem = [
            SELECT ApprovalStatus__c
            FROM ProductItem
            WHERE Id = :item.Id
        ];
        System.assertEquals(PartExceptionService.STATUS_IN_APPROVALS, updatedItem.ApprovalStatus__c);

        Integer caseCount = [
            SELECT COUNT()
            FROM Case
            WHERE WorkOrderLineItem__c = :line.Id
        ];
        System.assertEquals(1, caseCount);
    }

    @IsTest
    static void submitPartException_nullId_throws() {
        Boolean threw = false;
        try {
            PartExceptionService.submitPartException(null);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void submitPartException_unknownId_throws() {
        Boolean threw = false;
        try {
            PartExceptionService.submitPartException(fakeId(WorkOrderLineItem.SObjectType));
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void submitPartException_withoutProductItem_createsCase() {
        WorkOrderLineItem line = insertPartLine(null, false);

        Test.startTest();
        Id caseId = PartExceptionService.submitPartException(line.Id);
        Test.stopTest();

        Case createdCase = [
            SELECT Description
            FROM Case
            WHERE Id = :caseId
        ];
        System.assert(createdCase.Description.contains('Work Order Line Item:'));
        System.assertEquals(
            false,
            createdCase.Description.contains('Product:')
        );
    }

    private static ProductItem insertProductItem(String approvalStatus) {
        Schema.Location trunk = new Schema.Location(
            Name = 'Part Exception Trunk ' + String.valueOf(Crypto.getRandomInteger()),
            LocationType = 'Warehouse',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert trunk;

        Product2 product = new Product2(
            Name = 'Part Exception Product',
            ProductCode = 'PEX-001',
            IsActive = true
        );
        insert product;

        ProductItem item = new ProductItem(
            Product2Id = product.Id,
            LocationId = trunk.Id,
            QuantityOnHand = 1,
            ApprovalStatus__c = approvalStatus
        );
        insert item;
        return item;
    }

    private static Id fakeId(Schema.SObjectType objectType) {
        return (Id) (objectType.getDescribe().getKeyPrefix() + '000000000000');
    }

    private static WorkOrderLineItem insertPartLine(Id productItemId, Boolean inApprovals) {
        Account account = new Account(
            Name = 'Part Exception Account',
            SourceSystemID__c = 'ORACLE-PEX-' + String.valueOf(Crypto.getRandomInteger())
        );
        insert account;

        Asset asset = new Asset(
            Name = 'Part Exception Asset',
            AccountId = account.Id,
            SerialNumber = 'SN-PEX-001'
        );
        insert asset;

        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            AssetId = asset.Id,
            Subject = 'Part Exception WO'
        );
        insert workOrder;

        Id usageConsumptionRtId = Schema.SObjectType.WorkOrderLineItem
            .getRecordTypeInfosByDeveloperName()
            .get('UsageConsumption')
            ?.getRecordTypeId();

        WorkOrderLineItem line = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            LineType__c = 'Parts',
            ProductItem__c = productItemId,
            NonApprovedPartResponse__c = 'Needed to finish the repair',
            PartExceptionReason__c = 'Missing from SBOM'
        );
        if (inApprovals) {
            line.ApprovalStatus__c = PartExceptionService.STATUS_IN_APPROVALS;
        }
        if (usageConsumptionRtId != null) {
            line.RecordTypeId = usageConsumptionRtId;
        }
        insert line;
        return line;
    }
}