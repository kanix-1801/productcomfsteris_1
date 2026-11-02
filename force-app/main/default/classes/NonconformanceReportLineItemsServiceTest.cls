/**
 * @description GW-5497 coverage for NonconformanceReportLineItemsService.
 */
@IsTest(SeeAllData=false)
private class NonconformanceReportLineItemsServiceTest {
    private static NonconformanceReport__c createReport() {
        adb_Account accountBuilder = new adb_Account()
            .name('NCRLI Svc Account')
            .systemId('NCRLI1')
            .sourceSystemId('NCRLI1S')
            .orgIds('82');
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .account(accountBuilder)
            .status('QC')
            .subject('NCRLI Svc WO')
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
        return NonconformanceReportsService.createReport(report);
    }

    @IsTest
    static void testCreateUpdateAndQueryLine() {
        NonconformanceReport__c report = createReport();
        NonconformanceReportLineItem__c line = new NonconformanceReportLineItem__c(
            NonconformanceReport__c = report.Id,
            RepairRelated__c = 'Yes',
            NCRDate__c = Date.today(),
            InitiatedBy__c = UserInfo.getUserId(),
            QualityInspector__c = UserInfo.getUserId(),
            NCRStatus__c = 'Open',
            NCROwner__c = 'Internal'
        );
        Schema.RecordTypeInfo lineRt = Schema.SObjectType.NonconformanceReportLineItem__c
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCenter');
        if (lineRt != null) {
            line.RecordTypeId = lineRt.getRecordTypeId();
        }

        // RepairRelated may be restricted; pick first active value when available.
        Schema.DescribeFieldResult repairRelated = NonconformanceReportLineItem__c.RepairRelated__c
            .getDescribe();
        for (Schema.PicklistEntry entry : repairRelated.getPicklistValues()) {
            if (entry.isActive()) {
                line.RepairRelated__c = entry.getValue();
                break;
            }
        }

        Test.startTest();
        NonconformanceReportLineItem__c created =
            NonconformanceReportLineItemsService.createLine(line);
        List<NonconformanceReportLineItem__c> byReport =
            NonconformanceReportLineItemsService.getByReportIds(new Set<Id>{ report.Id });
        NonconformanceReportLineItemsService.updateLine(
            new NonconformanceReportLineItem__c(Id = created.Id, Comments__c = 'Updated comment')
        );
        Test.stopTest();

        Assert.isNotNull(created.Id, 'NCR line should be created');
        Assert.areEqual(1, byReport.size(), 'NCR line should be queryable by report');
        NonconformanceReportLineItem__c refreshed = [
            SELECT Comments__c
            FROM NonconformanceReportLineItem__c
            WHERE Id = :created.Id
        ];
        Assert.areEqual('Updated comment', refreshed.Comments__c, 'NCR line should update');
    }

    @IsTest
    static void testCreateAndUpdateWhenNullThrows() {
        Boolean createThrew = false;
        try {
            NonconformanceReportLineItemsService.createLine(null);
        } catch (NonconformanceReportLineItemsService.NonconformanceReportLineItemsServiceException e) {
            createThrew = e.getMessage().contains('required');
        }

        Boolean updateThrew = false;
        try {
            NonconformanceReportLineItemsService.updateLine(new NonconformanceReportLineItem__c());
        } catch (NonconformanceReportLineItemsService.NonconformanceReportLineItemsServiceException e) {
            updateThrew = e.getMessage().contains('required');
        }

        Assert.isTrue(createThrew, 'Null line should be rejected');
        Assert.isTrue(updateThrew, 'Line without Id should be rejected');
    }

    @IsTest
    static void testCreateAndUpdateWhenDmlFails() {
        Boolean createThrew = false;
        try {
            // Missing required parent lookup should fail DML inside the service.
            NonconformanceReportLineItemsService.createLine(new NonconformanceReportLineItem__c());
        } catch (NonconformanceReportLineItemsService.NonconformanceReportLineItemsServiceException e) {
            createThrew = e.getMessage().contains('Unable to create');
        }

        Boolean updateThrew = false;
        try {
            Id fakeLineId =
                NonconformanceReportLineItem__c.SObjectType.getDescribe().getKeyPrefix() +
                '000000000001';
            NonconformanceReportLineItemsService.updateLine(
                new NonconformanceReportLineItem__c(Id = fakeLineId, Comments__c = 'x')
            );
        } catch (NonconformanceReportLineItemsService.NonconformanceReportLineItemsServiceException e) {
            updateThrew = e.getMessage().contains('Unable to update');
        }

        Assert.isTrue(createThrew, 'Invalid create should surface a service exception');
        Assert.isTrue(updateThrew, 'Invalid update should surface a service exception');
    }

    @IsTest
    static void testGetByReportIdsGroupsByNcrThenNewestFirst() {
        NonconformanceReport__c firstReport = createReport();
        NonconformanceReport__c secondReport = NonconformanceReportsService.createReport(
            new NonconformanceReport__c(
                WorkOrder__c = firstReport.WorkOrder__c,
                NCRStatus__c = 'Open'
            )
        );
        Date olderDate = Date.today().addDays(-1);
        Date newerDate = Date.today();
        NonconformanceReportLineItemsService.createLine(
            buildLine(secondReport.Id, olderDate)
        );
        NonconformanceReportLineItemsService.createLine(
            buildLine(firstReport.Id, olderDate)
        );
        NonconformanceReportLineItemsService.createLine(
            buildLine(secondReport.Id, newerDate)
        );
        NonconformanceReportLineItemsService.createLine(
            buildLine(firstReport.Id, newerDate)
        );

        Test.startTest();
        List<NonconformanceReportLineItem__c> lines =
            NonconformanceReportLineItemsService.getByReportIds(
                new Set<Id>{ firstReport.Id, secondReport.Id }
            );
        Test.stopTest();

        List<NonconformanceReport__c> reportsByName = [
            SELECT Id, Name
            FROM NonconformanceReport__c
            WHERE Id IN :new Set<Id>{ firstReport.Id, secondReport.Id }
            ORDER BY Name ASC
        ];
        Assert.areEqual(4, lines.size(), 'Both NCRs should return their line items');
        Assert.areEqual(reportsByName[0].Id, lines[0].NonconformanceReport__c);
        Assert.areEqual(newerDate, lines[0].NCRDate__c);
        Assert.areEqual(reportsByName[0].Id, lines[1].NonconformanceReport__c);
        Assert.areEqual(olderDate, lines[1].NCRDate__c);
        Assert.areEqual(reportsByName[1].Id, lines[2].NonconformanceReport__c);
        Assert.areEqual(newerDate, lines[2].NCRDate__c);
        Assert.areEqual(reportsByName[1].Id, lines[3].NonconformanceReport__c);
        Assert.areEqual(olderDate, lines[3].NCRDate__c);
    }

    private static NonconformanceReportLineItem__c buildLine(Id reportId, Date ncrDate) {
        NonconformanceReportLineItem__c line = new NonconformanceReportLineItem__c(
            NonconformanceReport__c = reportId,
            RepairRelated__c = 'Yes',
            NCRDate__c = ncrDate,
            InitiatedBy__c = UserInfo.getUserId(),
            QualityInspector__c = UserInfo.getUserId(),
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
        return line;
    }
}