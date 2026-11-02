/**
 * @author Uptima
 * @date 2026-09-21
 * @description Tests GW-5497 Quality Inspection controller and supporting services.
 */
@IsTest(SeeAllData=false)
private class QualityInspectionControllerTest {
    private static final String SUBJECT_ELIGIBLE = 'GW-5497 Eligible';
    private static final String SUBJECT_INELIGIBLE = 'GW-5497 Ineligible';

    @TestSetup
    static void setupData() {
        adb_Account accountBuilder = new adb_Account()
            .name('GW-5497 Account')
            .systemId('GW5497-ACCOUNT')
            .sourceSystemId('GW5497-SOURCE')
            .orgIds('82');
        adb_Product2 productBuilder = new adb_Product2()
            .name('GW-5497 Product')
            .productCode('GW5497-PRODUCT')
            .productType('Service Asset')
            .productLine('FLEXIBLE SCOPE')
            .manufacturer('STERIS')
            .model('GW5497');
        adb_Asset assetBuilder = new adb_Asset()
            .name('GW-5497 Asset')
            .account(accountBuilder)
            .product(productBuilder)
            .serialNumber('GW5497-SERIAL');

        new adb_WorkOrder()
            .account(accountBuilder)
            .asset(assetBuilder)
            .status('Repair')
            .subject(SUBJECT_ELIGIBLE)
            .setRecordType('RepairCenterDevices')
            .pricebook2Id(Test.getStandardPricebookId());
        new adb_WorkOrder()
            .account(accountBuilder)
            .asset(assetBuilder)
            .status('Closed')
            .subject(SUBJECT_INELIGIBLE)
            .setRecordType('RepairCenterDevices')
            .pricebook2Id(Test.getStandardPricebookId());
        accountBuilder.persist();

        WorkOrder eligible = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :SUBJECT_ELIGIBLE
            LIMIT 1
        ];
        eligible.SubStatus__c = 'Ready for QC';
        eligible.ProductLine__c = 'FLEXIBLE SCOPE';
        update eligible;
    }

    @IsTest
    static void testGetOptionsReturnsActiveValues() {
        Test.startTest();
        Map<String, List<WorkOrdersService.QualityInspectionOption>> result =
            QualityInspectionController.getOptions();
        Test.stopTest();

        WorkOrdersService.QualityInspectionRiskTexts riskTexts =
            QualityInspectionController.getRiskTexts();
        Assert.areEqual(
            'Can happen, not expected to be a regular or frequent occurrence',
            riskTexts.occurrenceTexts.get('Medium'),
            'Medium occurrence text should match the story.'
        );
        Assert.isTrue(result.containsKey('subStatus'), 'Sub Status options should be returned.');
        Assert.isTrue(result.containsKey('ncrStatus'), 'NCR Status options should be returned.');

        List<WorkOrdersService.QualityInspectionOption> reasonOptions =
            QualityInspectionController.getNcrReasonOptions('FLEXIBLE SCOPE');
        Assert.isFalse(reasonOptions.isEmpty(), 'Dependent NCR Reasons should be returned.');

        List<WorkOrdersService.QualityInspectionOption> locationOptions =
            QualityInspectionController.getNcrLocationOptions(reasonOptions[0].value);
        Assert.isNotNull(locationOptions, 'Location options should return a list');
    }

    @IsTest
    static void testInitializeInspectionEligibleWorkOrder() {
        WorkOrder workOrder = [
            SELECT Id, WorkOrderNumber
            FROM WorkOrder
            WHERE Subject = :SUBJECT_ELIGIBLE
            LIMIT 1
        ];
        workOrder.ShipComplete__c = true;
        update workOrder;

        Test.startTest();
        WorkOrdersService.QualityInspectionWorkspace result =
            QualityInspectionController.initializeInspection(workOrder.WorkOrderNumber);
        Test.stopTest();

        Assert.areEqual(workOrder.Id, result.workOrderId, 'The scanned Work Order should load.');
        Assert.isTrue(result.shipComplete, 'Ship Complete should map from the Work Order.');
        Assert.areEqual('QC', result.status, 'Repair Work Orders should move to QC.');
        Assert.areEqual('Inspection', result.subStatus, 'Sub Status should move to Inspection.');

        WorkOrder saved = [
            SELECT OwnerId, QCInspector__c
            FROM WorkOrder
            WHERE Id = :workOrder.Id
        ];
        Assert.areEqual(UserInfo.getUserId(), saved.OwnerId, 'Current user should own the WO.');
        Assert.areEqual(
            UserInfo.getUserId(),
            saved.QCInspector__c,
            'Current user should be the QC Inspector.'
        );
    }

    @IsTest
    static void testInitializeInspectionIneligibleWorkOrder() {
        WorkOrder workOrder = [
            SELECT WorkOrderNumber
            FROM WorkOrder
            WHERE Subject = :SUBJECT_INELIGIBLE
            LIMIT 1
        ];

        Test.startTest();
        try {
            QualityInspectionController.initializeInspection(workOrder.WorkOrderNumber);
            Assert.fail('An ineligible Work Order should fail.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isTrue(
                exceptionValue.getMessage().contains('not eligible'),
                'The eligibility error should be user friendly.'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testSaveInspectionRequiresSubStatus() {
        WorkOrder workOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :SUBJECT_ELIGIBLE
            LIMIT 1
        ];

        Test.startTest();
        try {
            QualityInspectionController.saveInspection(workOrder.Id, null, null, null, null);
            Assert.fail('Sub Status should be required.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isTrue(
                exceptionValue.getMessage().contains('Sub Status'),
                'The required field error should identify Sub Status.'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testSaveInspectionPersistsQcFields() {
        WorkOrder workOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :SUBJECT_ELIGIBLE
            LIMIT 1
        ];
        QualityInspectionController.initializeInspection(String.valueOf(workOrder.Id));

        Test.startTest();
        WorkOrdersService.QualityInspectionWorkspace workspace =
            QualityInspectionController.saveInspection(
                workOrder.Id,
                'Inspection',
                'GAUGE-5497',
                'Controller save notes',
                null
            );
        Test.stopTest();

        Assert.areEqual(
            'GAUGE-5497',
            workspace.pressureGaugeSerialNumber,
            'Pressure gauge should be saved through the controller'
        );
        Assert.areEqual(
            'Controller save notes',
            workspace.inspectionNotes,
            'QC notes should be saved through the controller'
        );
    }

    @IsTest
    static void testGetNcrFilesWhenReportHasNoFiles() {
        // Setup
        NonconformanceReport__c report = createReport();

        // When
        Test.startTest();
        List<NonconformanceReportsService.NonconformanceReportFile> files =
            QualityInspectionController.getNcrFiles(report.Id);
        Test.stopTest();

        // Then
        Assert.areEqual(0, files.size(), 'A new NCR should have no files.');
    }

    @IsTest
    static void testAddNcrFileLinksFileToReport() {
        // Setup
        NonconformanceReport__c report = createReport();
        String payload =
            'data:text/plain;base64,' + EncodingUtil.base64Encode(Blob.valueOf('ncr file'));

        // When
        Test.startTest();
        NonconformanceReportsService.NonconformanceReportFile added =
            QualityInspectionController.addNcrFile(report.Id, payload, 'evidence.txt');
        List<NonconformanceReportsService.NonconformanceReportFile> files =
            QualityInspectionController.getNcrFiles(report.Id);
        Test.stopTest();

        // Then
        Assert.areEqual('evidence', added.title, 'The file title should drop the extension.');
        Assert.areEqual(1, files.size(), 'The added file should be listed on the NCR.');
        Assert.areEqual(added.contentDocumentId, files[0].contentDocumentId, 'The listed file should match.');
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :report.Id
                AND ContentDocumentId = :added.contentDocumentId
            ],
            'The file should be linked to the Nonconformance Report.'
        );
    }

    @IsTest
    static void testRemoveNcrFileDeletesLink() {
        // Setup
        NonconformanceReport__c report = createReport();
        NonconformanceReportsService.NonconformanceReportFile added =
            QualityInspectionController.addNcrFile(
                report.Id,
                EncodingUtil.base64Encode(Blob.valueOf('ncr file')),
                'evidence.txt'
            );

        // When
        Test.startTest();
        QualityInspectionController.removeNcrFile(report.Id, added.contentDocumentId);
        List<NonconformanceReportsService.NonconformanceReportFile> files =
            QualityInspectionController.getNcrFiles(report.Id);
        Test.stopTest();

        // Then
        Assert.areEqual(0, files.size(), 'The removed file should leave the NCR list.');
        Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :report.Id
                AND ContentDocumentId = :added.contentDocumentId
            ],
            'The file link should be removed from the Nonconformance Report.'
        );
    }

    @IsTest
    static void testRenameNcrFileUpdatesTitle() {
        // Setup
        NonconformanceReport__c report = createReport();
        NonconformanceReportsService.NonconformanceReportFile added =
            QualityInspectionController.addNcrFile(
                report.Id,
                EncodingUtil.base64Encode(Blob.valueOf('ncr file')),
                'evidence.txt'
            );

        // When
        Test.startTest();
        NonconformanceReportsService.NonconformanceReportFile renamed =
            QualityInspectionController.renameNcrFile(
                report.Id,
                added.contentDocumentId,
                'Bench photo.txt'
            );
        Test.stopTest();

        // Then
        Assert.areEqual('Bench photo', renamed.title, 'The saved title should drop the file extension.');
        Assert.areEqual(
            'Bench photo',
            [
                SELECT Title
                FROM ContentVersion
                WHERE ContentDocumentId = :added.contentDocumentId
                AND IsLatest = TRUE
            ].Title,
            'The latest file version should store the new title.'
        );
    }

    @IsTest
    static void testRenameNcrFileWhenTitleMissingThrows() {
        // Setup
        NonconformanceReport__c report = createReport();
        NonconformanceReportsService.NonconformanceReportFile added =
            QualityInspectionController.addNcrFile(
                report.Id,
                EncodingUtil.base64Encode(Blob.valueOf('ncr file')),
                'evidence.txt'
            );

        // When
        Test.startTest();
        try {
            QualityInspectionController.renameNcrFile(report.Id, added.contentDocumentId, ' ');
            Assert.fail('A blank title should be rejected.');
        } catch (AuraHandledException exceptionValue) {
            // Then
            Assert.isTrue(
                exceptionValue.getMessage().contains('File title is required'),
                'The error should require a file title.'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testAddNcrFileWhenReportMissingThrows() {
        // Given
        String payload = EncodingUtil.base64Encode(Blob.valueOf('ncr file'));
        Id missingReportId =
            NonconformanceReport__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001';

        // When
        Test.startTest();
        try {
            QualityInspectionController.addNcrFile(missingReportId, payload, 'evidence.txt');
            Assert.fail('A missing Nonconformance Report should be rejected.');
        } catch (AuraHandledException exceptionValue) {
            // Then
            Assert.isTrue(
                exceptionValue.getMessage().contains('not found'),
                'The error should say the Nonconformance Report was not found.'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testAddNcrFileWhenDataMissingThrows() {
        // Setup
        NonconformanceReport__c report = createReport();

        // When
        Test.startTest();
        try {
            QualityInspectionController.addNcrFile(report.Id, ' ', 'evidence.txt');
            Assert.fail('Blank file data should be rejected.');
        } catch (AuraHandledException exceptionValue) {
            // Then
            Assert.isTrue(
                exceptionValue.getMessage().contains('File data is required'),
                'The error should require file data.'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetNcrFilesForReportsReturnsFilesFromAllReports() {
        NonconformanceReport__c firstReport = createReport();
        NonconformanceReport__c secondReport = NonconformanceReportsService.createReport(
            new NonconformanceReport__c(
                WorkOrder__c = firstReport.WorkOrder__c,
                NCRStatus__c = 'Open'
            )
        );
        String payload =
            'data:text/plain;base64,' + EncodingUtil.base64Encode(Blob.valueOf('ncr file'));
        QualityInspectionController.addNcrFile(firstReport.Id, payload, 'one.txt');
        QualityInspectionController.addNcrFile(secondReport.Id, payload, 'two.txt');

        Test.startTest();
        List<NonconformanceReportsService.NonconformanceReportFile> files =
            QualityInspectionController.getNcrFilesForReports(
                new List<Id>{ firstReport.Id, secondReport.Id }
            );
        List<NonconformanceReportsService.NonconformanceReportFile> empty =
            QualityInspectionController.getNcrFilesForReports(new List<Id>());
        Test.stopTest();

        Assert.areEqual(2, files.size(), 'Photos from both NCRs should be returned.');
        Set<Id> reportIds = new Set<Id>();
        String previousReportNumber;
        for (NonconformanceReportsService.NonconformanceReportFile file : files) {
            Assert.isTrue(
                String.isNotBlank(file.reportNumber),
                'Each photo should include the NCR number.'
            );
            if (previousReportNumber != null) {
                Assert.isTrue(
                    file.reportNumber.compareTo(previousReportNumber) >= 0,
                    'Photos should stay grouped by NCR number.'
                );
            }
            previousReportNumber = file.reportNumber;
            reportIds.add(file.reportId);
        }
        Assert.isTrue(reportIds.contains(firstReport.Id), 'First NCR photos should be included.');
        Assert.isTrue(reportIds.contains(secondReport.Id), 'Second NCR photos should be included.');
        Assert.areEqual(0, empty.size(), 'No report Ids should return no photos.');
    }

    private static NonconformanceReport__c createReport() {
        WorkOrder workOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :SUBJECT_ELIGIBLE
            LIMIT 1
        ];
        return NonconformanceReportsService.createReport(
            new NonconformanceReport__c(
                WorkOrder__c = workOrder.Id,
                NCRStatus__c = 'Open'
            )
        );
    }
}