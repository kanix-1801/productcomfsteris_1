/**
 * @description GW-5497 coverage for NonconformanceReportsService.
 */
@IsTest(SeeAllData=false)
private class NonconformanceReportsServiceTest {
    @IsTest
    static void testCreateUpdateAndQueryReport() {
        adb_Account accountBuilder = new adb_Account()
            .name('NCR Svc Account')
            .systemId('NCRSVC1')
            .sourceSystemId('NCRSVC1S')
            .orgIds('82');
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .account(accountBuilder)
            .status('QC')
            .subject('NCR Svc WO')
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

        Test.startTest();
        NonconformanceReport__c created = NonconformanceReportsService.createReport(report);
        List<NonconformanceReport__c> byWorkOrder =
            NonconformanceReportsService.getByWorkOrderId(workOrder.Id);
        // Update only editable status; avoid re-sending lookup fields that may be read-only.
        NonconformanceReportsService.updateReports(
            new List<NonconformanceReport__c>{
                new NonconformanceReport__c(Id = created.Id, NCRStatus__c = 'Closed')
            }
        );
        NonconformanceReportsService.updateReports(new List<NonconformanceReport__c>());
        NonconformanceReportsService.updateReports(null);
        Test.stopTest();

        Assert.isNotNull(created.Id, 'NCR should be created');
        Assert.areEqual(1, byWorkOrder.size(), 'NCR should be queryable by Work Order');
        NonconformanceReport__c refreshed = [
            SELECT NCRStatus__c
            FROM NonconformanceReport__c
            WHERE Id = :created.Id
        ];
        Assert.areEqual('Closed', refreshed.NCRStatus__c, 'NCR status should update');
    }

    @IsTest
    static void testCreateReportWhenNullThrows() {
        Boolean threw = false;
        try {
            NonconformanceReportsService.createReport(null);
        } catch (NonconformanceReportsService.NonconformanceReportsServiceException e) {
            threw = e.getMessage().contains('required');
        }
        Assert.isTrue(threw, 'Null NCR should be rejected');
    }

    @IsTest
    static void testGetFilesWhenReportMissingThrows() {
        Boolean threw = false;
        try {
            NonconformanceReportsService.getFiles((Id) null);
        } catch (NonconformanceReportsService.NonconformanceReportsServiceException e) {
            threw = e.getMessage().contains('required');
        }
        Assert.isTrue(threw, 'Null report Id should be rejected');
    }

    @IsTest
    static void testFileLifecycleAndCompareTo() {
        adb_Account accountBuilder = new adb_Account()
            .name('NCR File Account')
            .systemId('NCRF1')
            .sourceSystemId('NCRF1S')
            .orgIds('82');
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .account(accountBuilder)
            .status('QC')
            .subject('NCR File WO')
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
        report = NonconformanceReportsService.createReport(report);

        String payload =
            'data:image/png;base64,' + EncodingUtil.base64Encode(Blob.valueOf('ncr-bytes'));

        Test.startTest();
        NonconformanceReportsService.NonconformanceReportFile added =
            NonconformanceReportsService.addFile(report.Id, payload, 'photo');
        List<NonconformanceReportsService.NonconformanceReportFile> files =
            NonconformanceReportsService.getFiles(report.Id);
        NonconformanceReportsService.NonconformanceReportFile renamed =
            NonconformanceReportsService.renameFile(
                report.Id,
                added.contentDocumentId,
                'Renamed Photo.jpg'
            );
        NonconformanceReportsService.removeFile(report.Id, added.contentDocumentId);

        NonconformanceReportsService.NonconformanceReportFile newer =
            new NonconformanceReportsService.NonconformanceReportFile();
        newer.lastModifiedDate = Datetime.now();
        NonconformanceReportsService.NonconformanceReportFile older =
            new NonconformanceReportsService.NonconformanceReportFile();
        older.lastModifiedDate = Datetime.now().addMinutes(-5);
        Integer sortOrder = newer.compareTo(older);
        Test.stopTest();

        Assert.isNotNull(added.contentDocumentId, 'File should be linked to the NCR');
        Assert.areEqual(1, files.size(), 'NCR should list the added file');
        Assert.areEqual(report.Id, files[0].reportId, 'File should stamp the NCR Id');
        Assert.isTrue(
            String.isNotBlank(files[0].reportNumber),
            'File should stamp the NCR number'
        );
        Assert.areEqual(
            0,
            NonconformanceReportsService.getFiles(new Set<Id>()).size(),
            'No report Ids should return no files'
        );
        Assert.areEqual('Renamed Photo', renamed.title, 'Rename should strip the extension');
        Assert.areEqual(-1, sortOrder, 'Newer files should sort first');
        Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :report.Id
                AND ContentDocumentId = :added.contentDocumentId
            ],
            'Removed file should no longer be linked'
        );
    }

    @IsTest
    static void testAddFileWhenDataMissingThrows() {
        Boolean threw = false;
        try {
            NonconformanceReportsService.addFile(
                NonconformanceReport__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001',
                null,
                'x.txt'
            );
        } catch (NonconformanceReportsService.NonconformanceReportsServiceException e) {
            threw = e.getMessage().contains('required') || e.getMessage().contains('not found');
        }
        Assert.isTrue(threw, 'Missing file data or report should be rejected');
    }

    @IsTest
    static void testCreateReportAndAddFileValidationPaths() {
        Boolean createThrew = false;
        try {
            NonconformanceReportsService.createReport(new NonconformanceReport__c());
        } catch (NonconformanceReportsService.NonconformanceReportsServiceException e) {
            createThrew = e.getMessage().contains('Unable to create');
        }

        adb_Account accountBuilder = new adb_Account()
            .name('NCR Val Account')
            .systemId('NCRV1')
            .sourceSystemId('NCRV1S')
            .orgIds('82');
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .account(accountBuilder)
            .status('QC')
            .subject('NCR Val WO')
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
        report = NonconformanceReportsService.createReport(report);

        Boolean blankDataThrew = false;
        try {
            NonconformanceReportsService.addFile(report.Id, '   ', 'x.txt');
        } catch (NonconformanceReportsService.NonconformanceReportsServiceException e) {
            blankDataThrew = e.getMessage().contains('File data is required');
        }

        Boolean missingFileThrew = false;
        try {
            NonconformanceReportsService.renameFile(
                report.Id,
                null,
                'Title'
            );
        } catch (NonconformanceReportsService.NonconformanceReportsServiceException e) {
            missingFileThrew = e.getMessage().contains('File is required');
        }

        Boolean updateThrew = false;
        try {
            Id fakeId =
                NonconformanceReport__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
            NonconformanceReportsService.updateReports(
                new List<NonconformanceReport__c>{
                    new NonconformanceReport__c(Id = fakeId, NCRStatus__c = 'Closed')
                }
            );
        } catch (NonconformanceReportsService.NonconformanceReportsServiceException e) {
            updateThrew = e.getMessage().contains('Unable to update');
        }

        Assert.isTrue(createThrew, 'Invalid NCR create should fail');
        Assert.isTrue(blankDataThrew, 'Blank file data should fail');
        Assert.isTrue(missingFileThrew, 'Null file Id should fail');
        Assert.isTrue(updateThrew, 'Invalid NCR update should fail');
    }

    @IsTest
    static void testFileCompareToGroupsByNcrThenNewestFirst() {
        NonconformanceReportsService.NonconformanceReportFile ncrANewer =
            new NonconformanceReportsService.NonconformanceReportFile();
        ncrANewer.reportNumber = 'NCR-0000000001';
        ncrANewer.lastModifiedDate = Datetime.now();
        NonconformanceReportsService.NonconformanceReportFile ncrAOlder =
            new NonconformanceReportsService.NonconformanceReportFile();
        ncrAOlder.reportNumber = 'NCR-0000000001';
        ncrAOlder.lastModifiedDate = Datetime.now().addMinutes(-5);
        NonconformanceReportsService.NonconformanceReportFile ncrB =
            new NonconformanceReportsService.NonconformanceReportFile();
        ncrB.reportNumber = 'NCR-0000000002';
        ncrB.lastModifiedDate = Datetime.now().addMinutes(5);

        List<NonconformanceReportsService.NonconformanceReportFile> files =
            new List<NonconformanceReportsService.NonconformanceReportFile>{
                ncrB,
                ncrAOlder,
                ncrANewer
            };
        files.sort();

        Assert.areEqual(
            'NCR-0000000001',
            files[0].reportNumber,
            'Photos should group by NCR number'
        );
        Assert.areEqual(
            'NCR-0000000001',
            files[1].reportNumber,
            'Photos for the same NCR should stay together'
        );
        Assert.areEqual(
            'NCR-0000000002',
            files[2].reportNumber,
            'The next NCR group should follow'
        );
        Assert.areEqual(
            ncrANewer.lastModifiedDate,
            files[0].lastModifiedDate,
            'Within an NCR, newer photos should sort first'
        );
        Assert.areEqual(
            ncrAOlder.lastModifiedDate,
            files[1].lastModifiedDate,
            'Within an NCR, older photos should sort after newer ones'
        );
    }
}