/**
 * @description Tests for WorkOrderBinTagPrintController (GW-4637).
 */
@IsTest
private class WorkOrderBinTagPrintControllerTest {
    private static final String SAMPLE_ZPL = '^XA^FO50,50^ADN,36,20^FDTEST^FS^XZ';

    @TestSetup
    static void setupData() {
        Schema.RecordTypeInfo devicesRt = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterDevices');
        Schema.RecordTypeInfo instrumentsRt = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterInstruments');
        if (
            devicesRt == null ||
            !devicesRt.isAvailable() ||
            instrumentsRt == null ||
            !instrumentsRt.isAvailable()
        ) {
            return;
        }

        adb_Account accountBuilder = new adb_Account().name('Bin Tag Print Account');
        accountBuilder.persist();
        Account account = (Account) accountBuilder.record;

        insert new WorkOrder(
            AccountId = account.Id,
            RecordTypeId = devicesRt.getRecordTypeId(),
            Status = 'New',
            Subject = 'Devices Bin Tag WO'
        );

        WorkOrder parentInstrument = new WorkOrder(
            AccountId = account.Id,
            RecordTypeId = instrumentsRt.getRecordTypeId(),
            Status = 'New',
            Subject = 'Parent Instrument Bin Tag WO'
        );
        insert parentInstrument;

        insert new WorkOrder(
            AccountId = account.Id,
            RecordTypeId = instrumentsRt.getRecordTypeId(),
            ParentWorkOrderId = parentInstrument.Id,
            Status = 'New',
            Subject = 'Child Instrument Bin Tag WO'
        );
    }

    @IsTest
    static void testPrintBinTagSucceedsForDevicesWorkOrder() {
        WorkOrder devicesWorkOrder = queryWorkOrder('Devices Bin Tag WO');
        if (devicesWorkOrder == null) {
            Assert.isTrue(true, 'Repair Center record types unavailable in this org.');
            return;
        }

        stubSuccessfulPrint();
        insertDefaultTravelTagPrinter();
        Test.startTest();
        String message = WorkOrderBinTagPrintController.printBinTag(devicesWorkOrder.Id);
        Test.stopTest();

        Assert.isTrue(message.contains(PrinterService.PARENT_BIN_TAG_PRINTER_NAME));
        Assert.areEqual(
            PrinterService.PARENT_BIN_TAG_PRINTER_NAME,
            PrinterService.lastRequestForTest.PrinterName
        );
        Assert.areNotEqual(true, PrinterService.lastRequestForTest.isDeviceTravelTag);
        clearPrintStubs();
    }

    @IsTest
    static void testPrintBinTagSucceedsForChildInstrumentWorkOrder() {
        WorkOrder childWorkOrder = queryWorkOrder('Child Instrument Bin Tag WO');
        if (childWorkOrder == null) {
            Assert.isTrue(true, 'Repair Center record types unavailable in this org.');
            return;
        }

        stubSuccessfulPrint();
        insertDefaultTravelTagPrinter();
        Test.startTest();
        String message = WorkOrderBinTagPrintController.printBinTag(childWorkOrder.Id);
        Test.stopTest();

        Assert.isTrue(message.contains(PrinterService.PARENT_BIN_TAG_PRINTER_NAME));
        Assert.areEqual(
            PrinterService.PARENT_BIN_TAG_PRINTER_NAME,
            PrinterService.lastRequestForTest.PrinterName
        );
        clearPrintStubs();
    }

    @IsTest
    static void testPrintBinTagSucceedsForParentInstrumentWorkOrder() {
        WorkOrder parentWorkOrder = queryWorkOrder('Parent Instrument Bin Tag WO');
        if (parentWorkOrder == null) {
            Assert.isTrue(true, 'Repair Center record types unavailable in this org.');
            return;
        }

        stubSuccessfulPrint();
        insertDefaultTravelTagPrinter();
        Test.startTest();
        String message = WorkOrderBinTagPrintController.printBinTag(parentWorkOrder.Id);
        Test.stopTest();

        Assert.isTrue(message.contains(PrinterService.PARENT_BIN_TAG_PRINTER_NAME));
        Assert.areEqual(
            PrinterService.PARENT_BIN_TAG_PRINTER_NAME,
            PrinterService.lastRequestForTest.PrinterName
        );
        clearPrintStubs();
    }

    @IsTest
    static void testPrintBinTagRequiresWorkOrderId() {
        try {
            WorkOrderBinTagPrintController.printBinTag(null);
            Assert.fail('Expected null Work Order Id to be rejected');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Work Order Id is required'));
        }
    }

    @IsTest
    static void testPrintBinTagRequiresActiveTravelTagPrinter() {
        WorkOrder parentWorkOrder = queryWorkOrder('Parent Instrument Bin Tag WO');
        if (parentWorkOrder == null) {
            Assert.isTrue(true, 'Repair Center record types unavailable in this org.');
            return;
        }

        try {
            WorkOrderBinTagPrintController.printBinTag(parentWorkOrder.Id);
            Assert.fail('Expected missing travel-tag printer exception');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('TRAVEL_TAG'));
        }
    }

    private static void stubSuccessfulPrint() {
        PrinterService.testCalloutResponseMap = new Map<String, Object>{
            'SO_SUCCESS' => true,
            'SERVICE_DATA' => SAMPLE_ZPL,
            'SERVICE_STATUS' => 200
        };
        BinTagPrintQuantitiesService.testPrintQuantity = 2;
    }

    private static void clearPrintStubs() {
        PrinterService.testCalloutResponseMap = null;
        PrinterService.lastRequestForTest = null;
        BinTagPrintQuantitiesService.testPrintQuantity = null;
    }

    private static void insertDefaultTravelTagPrinter() {
        insert new WorkstationPrinter__c(
            Name = PrinterService.PARENT_BIN_TAG_PRINTER_NAME,
            Active__c = true,
            User__c = UserInfo.getUserId(),
            PrinterType__c = 'TRAVEL_TAG',
            IPAddress__c = PrinterService.PARENT_BIN_TAG_PRINTER_IP,
            PrinterModel__c = PrinterService.PARENT_BIN_TAG_PRINTER_MODEL
        );
    }

    private static WorkOrder queryWorkOrder(String subject) {
        List<WorkOrder> rows = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = :subject
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }
}