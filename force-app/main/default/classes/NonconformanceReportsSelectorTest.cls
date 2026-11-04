/**
 * @description Tests for NonconformanceReportsSelector (GW-5497 / GW-5845).
 */
@IsTest(SeeAllData=false)
private class NonconformanceReportsSelectorTest {
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
}