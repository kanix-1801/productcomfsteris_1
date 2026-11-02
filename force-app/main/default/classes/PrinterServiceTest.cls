/**
 * @description Tests for PrinterService Zebra bin tag callouts (GW-4637)
 *              and workstation printer lookup (GW-4751).
 */
@IsTest
private class PrinterServiceTest {
    private static final String COUNTRY = 'United States';
    private static final String PRODUCT_LINE = 'INSTRUMENT';
    private static final String SAMPLE_ZPL = '^XA^FO50,50^ADN,36,20^FDTEST^FS^XZ';

    @TestSetup
    static void setupData() {
        adb_Account accountBuilder = new adb_Account().name('Printer Service Account');
        accountBuilder.persist();
        Account account = (Account) accountBuilder.record;

        Schema.Location repairCenter = new Schema.Location(
            Name = 'Printer Service Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        Product2 product = new Product2(
            Name = 'Printer Service Product',
            ProductCode = 'PRT-BIN-001',
            ProductType__c = 'Service Asset',
            ProductLine__c = PRODUCT_LINE,
            Description = 'this can be up to 120 chars',
            Model__c = 'Amsco-400',
            IsActive = true
        );
        insert product;

        Asset asset = new Asset(
            Name = 'Printer Service Asset',
            AccountId = account.Id,
            Product2Id = product.Id,
            SerialNumber = 'SN-PRT-BIN-001'
        );
        insert asset;

        ReturnOrder returnOrder = new ReturnOrder(
            AccountId = account.Id,
            Status = 'Created',
            DestinationLocationId = repairCenter.Id,
            OperatingUnit__c = '82'
        );
        insert returnOrder;

        insert new BinTagPrintQuantity__c(
            RepairCenter__c = repairCenter.Id,
            Country__c = COUNTRY,
            Product_Line__c = PRODUCT_LINE,
            PrintQuantity__c = 2
        );

        Schema.RecordTypeInfo instrumentsRt = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterInstruments');
        Id instrumentsRecordTypeId = instrumentsRt == null ? null : instrumentsRt.getRecordTypeId();
        Schema.RecordTypeInfo devicesRt = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterDevices');
        Id devicesRecordTypeId = devicesRt == null ? null : devicesRt.getRecordTypeId();

        WorkOrder parentWorkOrder = new WorkOrder(
            AccountId = account.Id,
            AssetId = asset.Id,
            RepairCenter__c = repairCenter.Id,
            ReturnOrder__c = returnOrder.Id,
            RecordTypeId = instrumentsRecordTypeId,
            QuantityReceived__c = 20,
            Status = 'New',
            Subject = 'Printer Service Parent WO'
        );
        insert parentWorkOrder;

        WorkOrder childWorkOrder = new WorkOrder(
            AccountId = account.Id,
            AssetId = asset.Id,
            RepairCenter__c = repairCenter.Id,
            ReturnOrder__c = returnOrder.Id,
            ParentWorkOrderId = parentWorkOrder.Id,
            RecordTypeId = instrumentsRecordTypeId,
            QuantityReceived__c = 5,
            RepairCategory__c = 'Laps',
            EstimateRequired__c = 'Estimate Required',
            Status = 'New',
            Subject = 'Printer Service Child WO'
        );
        insert childWorkOrder;

        if (devicesRecordTypeId != null) {
            insert new WorkOrder(
                AccountId = account.Id,
                AssetId = asset.Id,
                RepairCenter__c = repairCenter.Id,
                ReturnOrder__c = returnOrder.Id,
                RecordTypeId = devicesRecordTypeId,
                Status = 'New',
                Subject = 'Printer Service Device WO'
            );
        }
    }

    @IsTest
    static void testPrintBinTagsSendsMergedPayloadAndReturnsZpl() {
        WorkOrder parentWorkOrder = [
            SELECT Id, WorkOrderNumber
            FROM WorkOrder
            WHERE Subject = 'Printer Service Parent WO'
            LIMIT 1
        ];
        ReturnOrder returnOrder = [SELECT ReturnOrderNumber FROM ReturnOrder LIMIT 1];

        PrinterService.testCalloutResponseMap = successResponse(SAMPLE_ZPL);
        BinTagPrintQuantitiesService.testPrintQuantity = 2;
        insertDefaultTravelTagPrinter();

        Test.startTest();
        PrinterService.PrintLabelResult result = PrinterService.printBinTags(parentWorkOrder.Id);
        Test.stopTest();

        Assert.isTrue(result.success, 'Callout should succeed');
        Assert.areEqual(SAMPLE_ZPL, result.zplContent);
        Assert.areEqual(2, PrinterService.lastRequestForTest.Copies);
        Assert.areEqual(parentWorkOrder.WorkOrderNumber, PrinterService.lastRequestForTest.SalesOrder);
        Assert.areEqual('', PrinterService.lastRequestForTest.SubWorkOrder);
        Assert.areEqual(returnOrder.ReturnOrderNumber, PrinterService.lastRequestForTest.Srn);
        Assert.areEqual('', PrinterService.lastRequestForTest.WorkOrderType);
        Assert.areEqual(false, PrinterService.lastRequestForTest.Priority);
        Assert.areEqual(PrinterService.PARENT_BIN_TAG_SALES_REP, PrinterService.lastRequestForTest.SalesRep);
        Assert.areEqual('this can be up to 120 chars', PrinterService.lastRequestForTest.Description);
        Assert.areEqual(UserInfo.getName(), PrinterService.lastRequestForTest.User);
        Assert.areEqual(PrinterService.PARENT_BIN_TAG_PRINTER_NAME, PrinterService.lastRequestForTest.PrinterName);
        Assert.areEqual(PrinterService.PARENT_BIN_TAG_PRINTER_IP, PrinterService.lastRequestForTest.PrinterIpAddr);
        Assert.areEqual(PrinterService.PARENT_BIN_TAG_PRINTER_MODEL, PrinterService.lastRequestForTest.PrinterModel);
        Assert.areEqual(PrinterService.PARENT_BIN_TAG_PRINT_TEST_FLAG, PrinterService.lastRequestForTest.PrintTestFlag);
        Assert.areEqual(Datetime.now().format('M/d/yyyy'), PrinterService.lastRequestForTest.labelDate);
        Assert.isTrue(String.isNotBlank(PrinterService.lastRequestForTest.Day));
        String payload = PrinterService.toJson(PrinterService.lastRequestForTest);
        Assert.isTrue(payload.contains('"Field1"'));
        Assert.isTrue(payload.contains('"Field2"'));
        Assert.isTrue(payload.contains('"Field3":"' + PrinterService.PARENT_BIN_TAG_SALES_REP + '"'));
        Assert.isTrue(payload.contains('"Field6":"' + UserInfo.getName() + '"'));
        Assert.isTrue(payload.contains('"Field7":"' + parentWorkOrder.WorkOrderNumber + '"'));
        Assert.isTrue(payload.contains('"Field8":"' + PrinterService.PARENT_BIN_TAG_PRINT_TEST_FLAG + '"'));
        Assert.isTrue(payload.contains('"Field9":"this can be up to 120 chars"'));
        Assert.isTrue(payload.contains('"PrinterName":"' + PrinterService.PARENT_BIN_TAG_PRINTER_NAME + '"'));
        Assert.isTrue(payload.contains('"PrinterIpAddr":"' + PrinterService.PARENT_BIN_TAG_PRINTER_IP + '"'));
        Assert.isTrue(payload.contains('"PrinterModel":"' + PrinterService.PARENT_BIN_TAG_PRINTER_MODEL + '"'));
        Assert.isFalse(payload.contains('"SalesOrder"'));
        Assert.isFalse(payload.contains('"Date"'));
        Assert.isFalse(payload.contains('"InstrumentsInBin"'));
        Assert.areNotEqual(true, PrinterService.lastRequestForTest.isChildTravelTag);

        resetTestHooks();
    }

    @IsTest
    static void testChildWorkOrderSendsTravelTagPayload() {
        WorkOrder parentWorkOrder = [
            SELECT Id, WorkOrderNumber
            FROM WorkOrder
            WHERE Subject = 'Printer Service Parent WO'
            LIMIT 1
        ];
        WorkOrder childWorkOrder = [
            SELECT Id, WorkOrderNumber
            FROM WorkOrder
            WHERE Subject = 'Printer Service Child WO'
            LIMIT 1
        ];

        PrinterService.testCalloutResponseMap = successResponse(SAMPLE_ZPL);
        BinTagPrintQuantitiesService.testPrintQuantity = 2;
        insertDefaultTravelTagPrinter();

        Test.startTest();
        PrinterService.printBinTags(childWorkOrder.Id);
        Test.stopTest();

        PrinterService.PrintLabelRequest request = PrinterService.lastRequestForTest;
        Assert.areNotEqual(true, request.isChildTravelTag);
        Assert.areNotEqual(true, request.isDeviceTravelTag);
        Assert.areEqual(parentWorkOrder.WorkOrderNumber, request.SalesOrder);
        Assert.areEqual(childWorkOrder.WorkOrderNumber, request.SubWorkOrder);
        Assert.areEqual(PrinterService.PARENT_BIN_TAG_SALES_REP, request.SalesRep);
        Assert.areEqual(PrinterService.PARENT_BIN_TAG_PRINTER_NAME, request.PrinterName);
        Assert.areEqual(PrinterService.PARENT_BIN_TAG_PRINTER_IP, request.PrinterIpAddr);
        Assert.areEqual(PrinterService.PARENT_BIN_TAG_PRINTER_MODEL, request.PrinterModel);
        Assert.areEqual(PrinterService.PARENT_BIN_TAG_PRINT_TEST_FLAG, request.PrintTestFlag);
        String payload = PrinterService.toJson(request);
        Assert.isTrue(payload.contains('"Field1"'));
        Assert.isTrue(payload.contains('"Field7":"' + parentWorkOrder.WorkOrderNumber + '"'));
        Assert.isTrue(payload.contains('"Field4":"' + childWorkOrder.WorkOrderNumber + '"'));
        Assert.isTrue(payload.contains('"PrinterName":"' + PrinterService.PARENT_BIN_TAG_PRINTER_NAME + '"'));
        Assert.isFalse(payload.contains('"SalesOrder"'));
        Assert.isFalse(payload.contains('"InstrumentsInBin"'));
        Assert.isFalse(payload.contains('"WorkOrderId"'));

        resetTestHooks();
    }

    @IsTest
    static void testDeviceWorkOrderSendsTravelTagPayload() {
        List<WorkOrder> deviceWorkOrders = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Printer Service Device WO'
            LIMIT 1
        ];
        if (deviceWorkOrders.isEmpty()) {
            Assert.isTrue(true, 'Repair Center - Devices record type unavailable in this org.');
            return;
        }
        WorkOrder deviceWorkOrder = deviceWorkOrders[0];

        PrinterService.testCalloutResponseMap = successResponse(SAMPLE_ZPL);
        BinTagPrintQuantitiesService.testPrintQuantity = 2;
        insertDefaultTravelTagPrinter();

        Test.startTest();
        PrinterService.printBinTags(deviceWorkOrder.Id);
        Test.stopTest();

        PrinterService.PrintLabelRequest request = PrinterService.lastRequestForTest;
        Assert.areNotEqual(true, request.isDeviceTravelTag);
        Assert.areNotEqual(true, request.isChildTravelTag);
        Assert.areEqual(PrinterService.PARENT_BIN_TAG_SALES_REP, request.SalesRep);
        Assert.areEqual(PrinterService.PARENT_BIN_TAG_PRINTER_NAME, request.PrinterName);
        Assert.areEqual(PrinterService.PARENT_BIN_TAG_PRINTER_IP, request.PrinterIpAddr);
        Assert.areEqual(PrinterService.PARENT_BIN_TAG_PRINTER_MODEL, request.PrinterModel);
        Assert.areEqual(PrinterService.PARENT_BIN_TAG_PRINT_TEST_FLAG, request.PrintTestFlag);
        String payload = PrinterService.toJson(request);
        Assert.isTrue(payload.contains('"Field1"'));
        Assert.isTrue(payload.contains('"Field3":"' + PrinterService.PARENT_BIN_TAG_SALES_REP + '"'));
        Assert.isTrue(payload.contains('"PrinterName":"' + PrinterService.PARENT_BIN_TAG_PRINTER_NAME + '"'));
        Assert.isFalse(payload.contains('"SalesOrder"'));
        Assert.isFalse(payload.contains('"SerialNumber"'));
        Assert.isFalse(payload.contains('"WorkOrderId"'));
        Assert.isFalse(payload.contains('"InstrumentsInBin"'));

        resetTestHooks();
    }

    @IsTest
    static void testBinTagPrintQueryIncludesRecordTypeId() {
        WorkOrder parentWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Printer Service Parent WO'
            LIMIT 1
        ];

        Test.startTest();
        WorkOrder selected = (WorkOrder) new WorkOrdersSelector()
            .selectFields(new List<String>{ 'Id', 'RecordTypeId' })
            .whereEquals('Id', parentWorkOrder.Id)
            .first();
        Test.stopTest();

        Assert.isNotNull(selected, 'Should return the requested Work Order');
        Assert.isNotNull(
            selected.RecordTypeId,
            'Bin tag print query must include RecordTypeId so Devices routing does not throw'
        );
    }

    @IsTest
    static void testDeviceTravelTagMappingHelpers() {
        Assert.areEqual(
            'Customer Repair Priority',
            PrinterService.resolvePriorityRepair('Customer Repair Priority', null)
        );
        Assert.areEqual('STAT', PrinterService.resolvePriorityRepair('Customer Repair Priority', 'STAT'));
        Assert.areEqual('', PrinterService.resolvePriorityRepair('Priority Loaner', 'Y'));
        Assert.areEqual('', PrinterService.resolvePriorityRepair(null, null));
        Assert.areEqual('Case', PrinterService.resolveCaseAccessoryIndication(false, true));
        Assert.areEqual('Case', PrinterService.resolveCaseAccessoryIndication(true, true));
        Assert.areEqual('Accessory', PrinterService.resolveCaseAccessoryIndication(true, false));
        Assert.areEqual('Case', PrinterService.resolveCaseAccessoryIndication(false, false));
    }

    @IsTest
    static void testEstimateRequirementMapping() {
        Assert.areEqual('Quote Required', PrinterService.resolveEstimateRequirement('Estimate Required'));
        Assert.areEqual('Pre-Approved', PrinterService.resolveEstimateRequirement('Pre-Approved'));
        Assert.areEqual('Pre-Approved', PrinterService.resolveEstimateRequirement('Order Acknowledgement'));
        Assert.areEqual('Pre-Approved', PrinterService.resolveEstimateRequirement(null));
    }

    @IsTest
    static void testPrintBinTagsTruncatesDescriptionTo120Characters() {
        Product2 product = [SELECT Id FROM Product2 WHERE ProductCode = 'PRT-BIN-001' LIMIT 1];
        product.Description = 'A'.repeat(150);
        update product;

        WorkOrder parentWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Printer Service Parent WO'
            LIMIT 1
        ];
        PrinterService.testCalloutResponseMap = successResponse(SAMPLE_ZPL);
        BinTagPrintQuantitiesService.testPrintQuantity = 2;
        insertDefaultTravelTagPrinter();

        Test.startTest();
        PrinterService.printBinTags(parentWorkOrder.Id);
        Test.stopTest();

        Assert.areEqual(120, PrinterService.lastRequestForTest.Description.length());

        resetTestHooks();
    }

    @IsTest
    static void testPrintBinTagsThrowsOnHttp400() {
        WorkOrder parentWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Printer Service Parent WO'
            LIMIT 1
        ];
        PrinterService.testCalloutResponseMap = new Map<String, Object>{
            'SO_SUCCESS' => false,
            'SO_RETURN' => '400 Bad request. set printer name to "Zebra1".',
            'SERVICE_STATUS' => 400
        };
        BinTagPrintQuantitiesService.testPrintQuantity = 2;
        insertDefaultTravelTagPrinter();

        try {
            Test.startTest();
            PrinterService.printBinTags(parentWorkOrder.Id);
            Test.stopTest();
            Assert.fail('Expected 400 callout exception');
        } catch (PrinterService.PrinterServiceException e) {
            Assert.isTrue(e.getMessage().contains('400'));
        }

        resetTestHooks();
    }

    @IsTest
    static void testPrintBinTagsIncludesPrinterNameOnGenericHttp400() {
        WorkOrder parentWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Printer Service Parent WO'
            LIMIT 1
        ];
        PrinterService.testCalloutResponseMap = new Map<String, Object>{
            'SO_SUCCESS' => false,
            'SO_RETURN' => null,
            'SERVICE_STATUS' => 400,
            'SERVICE_DATA' => '"Bad request."'
        };
        insertDefaultTravelTagPrinter();

        try {
            Test.startTest();
            PrinterService.printBinTags(parentWorkOrder.Id);
            Test.stopTest();
            Assert.fail('Expected generic HTTP 400 callout exception');
        } catch (PrinterService.PrinterServiceException e) {
            Assert.isTrue(e.getMessage().contains(PrinterService.PARENT_BIN_TAG_PRINTER_NAME));
            Assert.isTrue(e.getMessage().contains('HTTP 400'));
        }

        resetTestHooks();
    }

    @IsTest
    static void testPrintBinTagsMapsReadTimedOutToUserMessage() {
        WorkOrder parentWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Printer Service Parent WO'
            LIMIT 1
        ];
        PrinterService.testCalloutResponseMap = new Map<String, Object>{
            'SO_SUCCESS' => false,
            'SO_RETURN' => 'Read timed out',
            'SERVICE_STATUS' => null
        };
        insertDefaultTravelTagPrinter();

        try {
            Test.startTest();
            PrinterService.printBinTags(parentWorkOrder.Id);
            Test.stopTest();
            Assert.fail('Expected timeout callout exception');
        } catch (PrinterService.PrinterServiceException e) {
            Assert.areEqual(PrinterService.CALLOUT_TIMEOUT_USER_MESSAGE, e.getMessage());
        }

        resetTestHooks();
    }

    @IsTest
    static void testPrintBinTagsUsesServiceDataWhenSoReturnIsBlank() {
        WorkOrder parentWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Printer Service Parent WO'
            LIMIT 1
        ];
        PrinterService.testCalloutResponseMap = new Map<String, Object>{
            'SO_SUCCESS' => false,
            'SO_RETURN' => null,
            'SERVICE_STATUS' => 400,
            'SERVICE_DATA' => 'Bad request. set printer name to "Zebra2".'
        };
        BinTagPrintQuantitiesService.testPrintQuantity = 2;

        try {
            Test.startTest();
            PrinterService.printBinTags(parentWorkOrder.Id, 'Zebra2');
            Test.stopTest();
            Assert.fail('Expected callout exception with SERVICE_DATA');
        } catch (PrinterService.PrinterServiceException e) {
            Assert.isTrue(e.getMessage().contains('HTTP 400'));
            Assert.isTrue(e.getMessage().contains('Zebra2'));
        }

        resetTestHooks();
    }

    @IsTest
    static void testPrintBinTagsUsesPrinterNameOverride() {
        WorkOrder parentWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Printer Service Parent WO'
            LIMIT 1
        ];
        PrinterService.testCalloutResponseMap = successResponse(SAMPLE_ZPL);
        BinTagPrintQuantitiesService.testPrintQuantity = 2;

        Test.startTest();
        PrinterService.printBinTags(parentWorkOrder.Id, 'Zebra2');
        Test.stopTest();

        Assert.areEqual('Zebra2', PrinterService.lastRequestForTest.PrinterName);

        resetTestHooks();
    }

    @IsTest
    static void testPrintBinTagsSendsEmptyWorkOrderType() {
        WorkOrder parentWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Printer Service Parent WO'
            LIMIT 1
        ];
        PrinterService.testCalloutResponseMap = successResponse(SAMPLE_ZPL);
        BinTagPrintQuantitiesService.testPrintQuantity = 2;

        Test.startTest();
        PrinterService.printBinTags(parentWorkOrder.Id, 'Zebra2');
        Test.stopTest();

        Assert.areEqual('', PrinterService.lastRequestForTest.WorkOrderType);
        Assert.isTrue(PrinterService.toJson(PrinterService.lastRequestForTest).contains('"Field5":""'));
        Assert.isFalse(PrinterService.toJson(PrinterService.lastRequestForTest).contains('"WorkOrderType"'));

        resetTestHooks();
    }

    @IsTest
    static void testPrintBinTagsResolvesCopiesFromRepairCenterAndProductLine() {
        WorkOrder parentWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Printer Service Parent WO'
            LIMIT 1
        ];
        PrinterService.testCalloutResponseMap = successResponse(SAMPLE_ZPL);
        insertDefaultTravelTagPrinter();

        Test.startTest();
        PrinterService.printBinTags(parentWorkOrder.Id);
        Test.stopTest();

        Assert.areEqual(
            2,
            PrinterService.lastRequestForTest.Copies,
            'Copies should match Repair Center + Product Line even when Country is unused'
        );

        resetTestHooks();
    }

    @IsTest
    static void testPrintBinTagsRequiresWorkOrderId() {
        try {
            PrinterService.printBinTags(null);
            Assert.fail('Expected null Work Order exception');
        } catch (PrinterService.PrinterServiceException e) {
            Assert.isTrue(e.getMessage().contains('Work Order Id is required'));
        }
    }

    @IsTest
    static void testSendPrintLabelRequestDefaultsNullCopiesToOne() {
        PrinterService.PrintLabelRequest request = new PrinterService.PrintLabelRequest();
        request.Copies = null;
        request.PrinterName = 'Zebra2';
        PrinterService.testCalloutResponseMap = successResponse(SAMPLE_ZPL);

        Test.startTest();
        PrinterService.PrintLabelResult result = PrinterService.sendPrintLabelRequest(request);
        Test.stopTest();

        Assert.isTrue(result.success);
        Assert.areEqual(BinTagPrintQuantitiesService.DEFAULT_PRINT_QUANTITY, request.Copies);
        Assert.areEqual(BinTagPrintQuantitiesService.DEFAULT_PRINT_QUANTITY, result.request.Copies);

        resetTestHooks();
    }

    @IsTest
    static void testSendPrintLabelRequestRejectsNonPositiveCopies() {
        PrinterService.PrintLabelRequest request = new PrinterService.PrintLabelRequest();
        request.Copies = 0;
        request.PrinterName = 'Zebra2';

        try {
            PrinterService.sendPrintLabelRequest(request);
            Assert.fail('Expected copies validation');
        } catch (PrinterService.PrinterServiceException e) {
            Assert.isTrue(e.getMessage().contains('Copies'));
        }
    }

    @IsTest
    static void testEmptyZplHttp200IsSuccess() {
        WorkOrder parentWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Printer Service Parent WO'
            LIMIT 1
        ];
        PrinterService.testCalloutResponseMap = successResponse('');
        BinTagPrintQuantitiesService.testPrintQuantity = 2;

        Test.startTest();
        PrinterService.PrintLabelResult result = PrinterService.printBinTags(parentWorkOrder.Id, 'Zebra2');
        Test.stopTest();

        Assert.isTrue(result.success, 'HTTP 200 with empty ZPL should succeed in the test mock');
        Assert.isTrue(String.isBlank(result.zplContent));

        resetTestHooks();
    }

    @IsTest
    static void testSendPrintLabelRequestRejectsBlankPrinter() {
        PrinterService.PrintLabelRequest request = new PrinterService.PrintLabelRequest();
        request.Copies = 1;
        request.PrinterName = '';

        try {
            PrinterService.sendPrintLabelRequest(request);
            Assert.fail('Expected printer name validation');
        } catch (PrinterService.PrinterServiceException e) {
            Assert.isTrue(e.getMessage().contains('PrinterName'));
        }
    }

    @IsTest
    static void testEmptyZplDoesNotThrowGovernorCheck() {
        PrinterService.assertResponseWithinGovernorLimits('  ');
        PrinterService.assertResponseWithinGovernorLimits(null);
    }

    @IsTest
    static void testPrintBinTagsRequiresActiveTravelTagPrinter() {
        WorkOrder parentWorkOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Subject = 'Printer Service Parent WO'
            LIMIT 1
        ];

        try {
            PrinterService.printBinTags(parentWorkOrder.Id);
            Assert.fail('Expected missing travel-tag printer exception');
        } catch (PrinterService.PrinterServiceException e) {
            Assert.isTrue(e.getMessage().contains('TRAVEL_TAG'));
        }
    }

    /**
     * @description GW-4751 - Returns null when the running user has no active Workstation Printer.
     */
    @IsTest
    static void testGetActivePrinterForCurrentUserReturnsNullWhenNone() {
        User printerUser = createPrinterUser('wpnull');

        System.runAs(printerUser) {
            Assert.isNull(PrinterService.getActiveTravelTagPrinterForCurrentUser());
            Assert.isNull(PrinterService.getActiveFedExLabelPrinterForCurrentUser());
            Assert.isNull(PrinterService.getActiveDesktopPrinterForCurrentUser());
        }
    }

    /**
     * @description GW-4751 - Logs and throws when the printer query fails.
     */
    @IsTest
    static void testGetActivePrinterForCurrentUserThrowsWhenQueryFails() {
        User printerUser = createUserWithoutPrinterAccess('wpfail');

        System.runAs(printerUser) {
            try {
                PrinterService.getActiveTravelTagPrinterForCurrentUser();
                Assert.fail('Expected PrinterServiceException');
            } catch (PrinterService.PrinterServiceException printerError) {
                Assert.isTrue(
                    printerError.getMessage().contains('Unable to resolve'),
                    printerError.getMessage()
                );
            }
        }
    }

    /**
     * @description GW-4751 - Returns the active printer that matches each printer type.
     */
    @IsTest
    static void testGetActivePrinterForCurrentUserReturnsMatchingType() {
        User printerUser = createPrinterUser('wpmatch');

        System.runAs(printerUser) {
            insert new List<WorkstationPrinter__c>{
                workstationPrinter(printerUser.Id, 'TRAVEL_TAG', '10.0.0.1', true),
                workstationPrinter(printerUser.Id, 'FEDEX_LABEL', '10.0.0.2', true),
                workstationPrinter(printerUser.Id, 'DESKTOP', '10.0.0.3', true)
            };

            WorkstationPrinter__c travelTag = PrinterService.getActiveTravelTagPrinterForCurrentUser();
            WorkstationPrinter__c fedExLabel = PrinterService.getActiveFedExLabelPrinterForCurrentUser();
            WorkstationPrinter__c desktop = PrinterService.getActiveDesktopPrinterForCurrentUser();

            Assert.areEqual('10.0.0.1', travelTag.IPAddress__c);
            Assert.areEqual('TRAVEL_TAG', travelTag.PrinterType__c);
            Assert.areEqual('10.0.0.2', fedExLabel.IPAddress__c);
            Assert.areEqual('FEDEX_LABEL', fedExLabel.PrinterType__c);
            Assert.areEqual('10.0.0.3', desktop.IPAddress__c);
            Assert.areEqual('DESKTOP', desktop.PrinterType__c);
        }
    }

    /**
     * @description GW-4751 - Returns the newest active Travel Tag printer for the running user.
     */
    @IsTest
    static void testGetActiveTravelTagPrinterForCurrentUserReturnsLatestActive() {
        User printerUser = createPrinterUser('wplatest');
        Id otherUserId = [
            SELECT Id
            FROM User
            WHERE Id != :printerUser.Id AND IsActive = true
            LIMIT 1
        ].Id;

        System.runAs(printerUser) {
            WorkstationPrinter__c older = workstationPrinter(printerUser.Id, 'TRAVEL_TAG', '10.1.1.1', true);
            insert older;
            Test.setCreatedDate(older.Id, Datetime.now().addDays(-2));

            WorkstationPrinter__c inactive = workstationPrinter(printerUser.Id, 'TRAVEL_TAG', '10.1.1.9', false);
            insert inactive;
            Test.setCreatedDate(inactive.Id, Datetime.now());

            WorkstationPrinter__c otherUser = workstationPrinter(otherUserId, 'TRAVEL_TAG', '10.1.1.8', true);
            insert otherUser;
            Test.setCreatedDate(otherUser.Id, Datetime.now());

            WorkstationPrinter__c latest = workstationPrinter(printerUser.Id, 'TRAVEL_TAG', '10.1.1.2', true);
            insert latest;
            Test.setCreatedDate(latest.Id, Datetime.now().addDays(-1));

            WorkstationPrinter__c selected = PrinterService.getActiveTravelTagPrinterForCurrentUser();

            Assert.areEqual(latest.Id, selected.Id);
            Assert.areEqual('10.1.1.2', selected.IPAddress__c);
        }
    }

    /**
     * @description GW-4751 - User with Manage Repair Center Operations so printer fields are accessible.
     * @param aliasSeed Unique suffix for the username.
     * @return The inserted user.
     */
    private static User createPrinterUser(String aliasSeed) {
        Profile standardProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        String uniqueKey = String.valueOf(Datetime.now().getTime()) + aliasSeed;
        User printerUser = new User(
            Alias = aliasSeed.left(8),
            Email = uniqueKey + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Printer Test',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = uniqueKey + '@example.com'
        );
        insert printerUser;

        PermissionSet printerAccess = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'ManageRepairCenterOperations'
            LIMIT 1
        ];
        insert new PermissionSetAssignment(
            AssigneeId = printerUser.Id,
            PermissionSetId = printerAccess.Id
        );
        return printerUser;
    }

    /**
     * @description GW-4751 - User without Workstation Printer field access.
     * @param aliasSeed Unique suffix for the username.
     * @return The inserted user.
     */
    private static User createUserWithoutPrinterAccess(String aliasSeed) {
        Profile standardProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        String uniqueKey = String.valueOf(Datetime.now().getTime()) + aliasSeed;
        User printerUser = new User(
            Alias = aliasSeed.left(8),
            Email = uniqueKey + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Printer Test',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = uniqueKey + '@example.com'
        );
        insert printerUser;
        return printerUser;
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

    private static WorkstationPrinter__c workstationPrinter(
        Id userId,
        String printerType,
        String ipAddress,
        Boolean isActive
    ) {
        return new WorkstationPrinter__c(
            Name = printerType + ' ' + ipAddress,
            Active__c = isActive,
            User__c = userId,
            PrinterType__c = printerType,
            IPAddress__c = ipAddress
        );
    }

    private static Map<String, Object> successResponse(String zpl) {
        return new Map<String, Object>{
            'SO_SUCCESS' => true,
            'SERVICE_DATA' => zpl,
            'SERVICE_STATUS' => 200
        };
    }

    private static void resetTestHooks() {
        PrinterService.testCalloutResponseMap = null;
        PrinterService.lastRequestForTest = null;
        BinTagPrintQuantitiesService.testPrintQuantity = null;
    }
}