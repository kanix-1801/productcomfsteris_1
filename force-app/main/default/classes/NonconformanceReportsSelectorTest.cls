/**
 * @description Tests for NonconformanceReportsSelector (GW-5497 / GW-5845).
 */
@IsTest(SeeAllData=false)
private class NonconformanceReportsSelectorTest {
    @IsTest
    static void testConstructor_createsSelector() {
        NonconformanceReportsSelector selector = new NonconformanceReportsSelector();
        Assert.isNotNull(selector, 'Selector should construct for SoqlQueryBuilder queries');
    }

    private static NonconformanceReport__c createReport() {
        adb_Account accountBuilder = new adb_Account()
            .name('NCR Sel Account')
            .systemId('NCRSEL1')
            .sourceSystemId('NCRSEL1S')
            .orgIds('82');
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .account(accountBuilder)
            .status('QC')
            .subject('NCR Sel WO')
            .setRecordType('RepairCenterDevices')
            .pricebook2Id(Test.getStandardPricebookId());
        accountBuilder.persist();
        WorkOrder workOrder = (WorkOrder) workOrderBuilder.record;

        NonconformanceReport__c report = new NonconformanceReport__c(
            WorkOrder__c = workOrder.Id,
            Account__c = workOrder.AccountId,
            NCRType__c = 'Customer Equipment',
            NCRStatus__c = 'Open'
        );
        Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.NonconformanceReport__c
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCenter');
        if (recordTypeInfo != null) {
            report.RecordTypeId = recordTypeInfo.getRecordTypeId();
        }
        insert report;
        return report;
    }

    private static NonconformanceReport__c createReportWithLineItemAndProduct() {
        adb_Account accountBuilder = new adb_Account()
            .name('NCR Sel Rel Account')
            .systemId('NCRSEL2')
            .sourceSystemId('NCRSEL2S')
            .orgIds('82');
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .account(accountBuilder)
            .status('QC')
            .subject('NCR Sel Rel WO')
            .setRecordType('RepairCenterDevices')
            .pricebook2Id(Test.getStandardPricebookId());
        accountBuilder.persist();
        WorkOrder workOrder = (WorkOrder) workOrderBuilder.record;

        Product2 product = new Product2(Name = 'NCR Sel Product', IsActive = true);
        insert product;

        Id standardPricebookId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );
        insert pbe;

        WorkOrderLineItem woli = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1
        );
        insert woli;

        NonconformanceReport__c report = new NonconformanceReport__c(
            WorkOrder__c = workOrder.Id,
            WorkOrderLineItem__c = woli.Id,
            Account__c = workOrder.AccountId,
            Product__c = product.Id,
            NCRType__c = 'Customer Equipment',
            NCRStatus__c = 'Open'
        );
        Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.NonconformanceReport__c
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCenter');
        if (recordTypeInfo != null) {
            report.RecordTypeId = recordTypeInfo.getRecordTypeId();
        }
        insert report;
        return report;
    }

    @IsTest
    static void testSelectByWorkOrderId_WhenNull_ReturnsEmpty() {
        Test.startTest();
        List<NonconformanceReport__c> rows = NonconformanceReportsSelector.selectByWorkOrderId(null);
        Test.stopTest();

        Assert.isTrue(rows.isEmpty(), 'Null Work Order Id should return empty');
    }

    @IsTest
    static void testSelectById_WhenBlank_ReturnsEmpty() {
        Test.startTest();
        List<NonconformanceReport__c> nullRows = NonconformanceReportsSelector.selectById(null);
        List<NonconformanceReport__c> emptyRows = NonconformanceReportsSelector.selectById(new Set<Id>());
        Test.stopTest();

        Assert.isTrue(nullRows.isEmpty(), 'Null Ids should return empty');
        Assert.isTrue(emptyRows.isEmpty(), 'Empty Ids should return empty');
    }

    @IsTest
    static void testSelectByWorkOrderId_WhenReportExists_ReturnsRows() {
        NonconformanceReport__c report = createReport();

        Test.startTest();
        List<NonconformanceReport__c> rows =
            NonconformanceReportsSelector.selectByWorkOrderId(report.WorkOrder__c);
        Test.stopTest();

        Assert.areEqual(1, rows.size(), 'Should return the NCR for the Work Order');
        Assert.areEqual(report.Id, rows[0].Id);
        Assert.areEqual(report.WorkOrder__c, rows[0].WorkOrder__c);
    }

    @IsTest
    static void testSelectById_WhenReportExists_ReturnsRows() {
        NonconformanceReport__c report = createReport();

        Test.startTest();
        List<NonconformanceReport__c> rows =
            NonconformanceReportsSelector.selectById(new Set<Id>{ report.Id });
        Test.stopTest();

        Assert.areEqual(1, rows.size(), 'Should return the NCR by Id');
        Assert.areEqual(report.Id, rows[0].Id);
    }

    @IsTest
    static void testSelectByWorkOrderId_WhenLineItemSet_ReturnsRelationshipFields() {
        NonconformanceReport__c report = createReportWithLineItemAndProduct();
        Product2 product = [
            SELECT Name
            FROM Product2
            WHERE Id = :report.Product__c
            LIMIT 1
        ];

        Test.startTest();
        List<NonconformanceReport__c> rows =
            NonconformanceReportsSelector.selectByWorkOrderId(report.WorkOrder__c);
        Test.stopTest();

        Assert.areEqual(1, rows.size(), 'Should return the NCR for the Work Order');
        Assert.isNotNull(
            rows[0].WorkOrderLineItem__r,
            'WorkOrderLineItem relationship should be queried'
        );
        Assert.isNotNull(
            rows[0].WorkOrderLineItem__r.LineItemNumber,
            'LineItemNumber should be available for QC mapping'
        );
        Assert.areEqual(
            product.Name,
            rows[0].Product__r.Name,
            'Product name should be available for QC mapping'
        );
    }
}