/**
 * @description Tests for NonconformanceReportLineItemsSelector (GW-5497 / GW-5845).
 *              Named NcrLineItemsSelectorTest to stay within the 40-character Apex class limit.
 */
@IsTest(SeeAllData=false)
private class NcrLineItemsSelectorTest {
    @IsTest
    static void testConstructor_createsSelector() {
        NonconformanceReportLineItemsSelector selector =
            new NonconformanceReportLineItemsSelector();
        Assert.isNotNull(selector, 'Selector should construct for SoqlQueryBuilder queries');
    }

    @IsTest
    static void testSelectByReportIds_WhenBlank_ReturnsEmpty() {
        Test.startTest();
        List<NonconformanceReportLineItem__c> nullRows =
            NonconformanceReportLineItemsSelector.selectByReportIds(null);
        List<NonconformanceReportLineItem__c> emptyRows =
            NonconformanceReportLineItemsSelector.selectByReportIds(new Set<Id>());
        Test.stopTest();

        Assert.isTrue(nullRows.isEmpty(), 'Null report Ids should return empty');
        Assert.isTrue(emptyRows.isEmpty(), 'Empty report Ids should return empty');
    }

    @IsTest
    static void testSelectByReportIds_WhenLineExists_ReturnsParentRelationship() {
        adb_Account accountBuilder = new adb_Account()
            .name('NCRLI Sel Account')
            .systemId('NCRLISEL1')
            .sourceSystemId('NCRLISEL1S')
            .orgIds('82');
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .account(accountBuilder)
            .status('QC')
            .subject('NCRLI Sel WO')
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
        Schema.RecordTypeInfo reportRt = Schema.SObjectType.NonconformanceReport__c
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCenter');
        if (reportRt != null) {
            report.RecordTypeId = reportRt.getRecordTypeId();
        }
        insert report;

        NonconformanceReportLineItem__c line = new NonconformanceReportLineItem__c(
            NonconformanceReport__c = report.Id,
            NCRDate__c = Date.today(),
            InitiatedBy__c = UserInfo.getUserId(),
            NCRStatus__c = 'Open',
            NCROwner__c = 'Internal'
        );
        Schema.RecordTypeInfo lineRt = Schema.SObjectType.NonconformanceReportLineItem__c
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCenter');
        if (lineRt != null) {
            line.RecordTypeId = lineRt.getRecordTypeId();
        }
        Schema.DescribeFieldResult repairRelated = NonconformanceReportLineItem__c.RepairRelated__c
            .getDescribe();
        for (Schema.PicklistEntry entry : repairRelated.getPicklistValues()) {
            if (entry.isActive()) {
                line.RepairRelated__c = entry.getValue();
                break;
            }
        }
        insert line;

        NonconformanceReport__c refreshedReport = [
            SELECT Name
            FROM NonconformanceReport__c
            WHERE Id = :report.Id
            LIMIT 1
        ];

        Test.startTest();
        List<NonconformanceReportLineItem__c> rows =
            NonconformanceReportLineItemsSelector.selectByReportIds(new Set<Id>{ report.Id });
        Test.stopTest();

        Assert.areEqual(1, rows.size(), 'Should return the NCR line for the report');
        Assert.areEqual(line.Id, rows[0].Id, 'Should return the inserted line');
        Assert.isNotNull(
            rows[0].NonconformanceReport__r,
            'NonconformanceReport relationship should be queried'
        );
        Assert.areEqual(
            refreshedReport.Name,
            rows[0].NonconformanceReport__r.Name,
            'Parent NCR Name should be available for QC mapping'
        );
    }
}