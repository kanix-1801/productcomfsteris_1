/**
 * @description GW-134 / GW-6703 - Tests for appending product types onto Device Inspection Summary.
 * @see DeviceInspectionSummaryService
 */
@IsTest
private class DeviceInspectionSummaryServiceTest {
    private static final Id CRSS_RECORD_TYPE_ID = Schema.SObjectType.WorkOrder
        .getRecordTypeInfosByDeveloperName()
        .get('CRSSFieldRepair')
        .getRecordTypeId();
    private static final Id ES_RECORD_TYPE_ID = Schema.SObjectType.WorkOrder
        .getRecordTypeInfosByDeveloperName()
        .get('ESFieldRepair')
        .getRecordTypeId();
    private static final Id PRODUCT_SERVICED_RECORD_TYPE_ID = Schema.SObjectType.WorkOrderLineItem
        .getRecordTypeInfosByDeveloperName()
        .get('ProductServiced')
        .getRecordTypeId();
    private static final Id USAGE_CONSUMPTION_RECORD_TYPE_ID = Schema.SObjectType.WorkOrderLineItem
        .getRecordTypeInfosByDeveloperName()
        .get('UsageConsumption')
        .getRecordTypeId();

    /**
     * @description Account, products, assets, and one CRSS work order. Lines are created per test.
     */
    @TestSetup
    static void setup() {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        Account account = new Account(Name = 'DIS ' + token, SourceSystemID__c = 'ORACLE-DIS-' + token);
        insert account;

        Product2 small = new Product2(
            Name = 'Flexible Small',
            IsActive = true,
            ProductType__c = 'Service Asset',
            ProductLine__c = 'FLEXIBLE SCOPE',
            SubProductLine__c = 'ULTRASOUND'
        );
        Product2 large = new Product2(
            Name = 'Rigid Line',
            IsActive = true,
            ProductType__c = 'Service Asset',
            ProductLine__c = 'RIGID'
        );
        Product2 lineOnly = new Product2(
            Name = 'Flexible Line Only',
            IsActive = true,
            ProductType__c = 'Service Asset',
            ProductLine__c = 'FLEXIBLE SCOPE'
        );
        Product2 blankLine = new Product2(
            Name = 'No Product Line',
            IsActive = true,
            ProductType__c = 'Service Asset'
        );
        insert new List<Product2>{ small, large, lineOnly, blankLine };

        insert new List<Asset>{
            new Asset(Name = 'Small Asset', AccountId = account.Id, Product2Id = small.Id),
            new Asset(Name = 'Rigid Asset', AccountId = account.Id, Product2Id = large.Id),
            new Asset(Name = 'Line Only Asset', AccountId = account.Id, Product2Id = lineOnly.Id),
            new Asset(Name = 'Blank Line Asset', AccountId = account.Id, Product2Id = blankLine.Id)
        };

        insert new WorkOrder(
            AccountId = account.Id,
            Subject = 'CRSS Device Inspection',
            RecordTypeId = CRSS_RECORD_TYPE_ID,
            Status = 'New'
        );
    }

    /**
     * @description Stops the record-triggered flow so the test calls the service itself.
     */
    private static void bypassFlow() {
        insert new Automation_Setting_Flow__c(
            SetupOwnerId = UserInfo.getUserId(),
            WOLI_DeviceInspectionSummary_AfterSave__c = true
        );
    }

    /**
     * @description CRSS work order from setup.
     * @return Work order
     */
    private static WorkOrder crssWorkOrder() {
        return [SELECT Id, DeviceInspectionSummary__c FROM WorkOrder WHERE Subject = 'CRSS Device Inspection' LIMIT 1];
    }

    /**
     * @description Asset created in setup.
     * @param name Asset name
     * @return Asset
     */
    private static Asset assetNamed(String name) {
        return [SELECT Id FROM Asset WHERE Name = :name LIMIT 1];
    }

    /**
     * @description Inserts a Product Serviced line for an asset.
     * @param workOrderId Parent work order
     * @param assetId Asset
     * @param recordTypeId Line record type
     * @return Inserted line
     */
    private static WorkOrderLineItem insertLine(Id workOrderId, Id assetId, Id recordTypeId) {
        WorkOrderLineItem line = new WorkOrderLineItem(
            WorkOrderId = workOrderId,
            AssetId = assetId,
            RecordTypeId = recordTypeId,
            LineType__c = 'Product Serviced'
        );
        insert line;
        return line;
    }

    /**
     * @description Calls the service for one line.
     * @param lineId Work order line item Id
     */
    private static void appendLine(Id lineId) {
        DeviceInspectionSummaryService.Request request = new DeviceInspectionSummaryService.Request();
        request.workOrderLineItemId = lineId;
        DeviceInspectionSummaryService.append(new List<DeviceInspectionSummaryService.Request>{ request });
    }

    /**
     * @description Product line and sub product line become one token.
     */
    @IsTest
    static void append_productLineAndSubProductLine_setsToken() {
        bypassFlow();
        WorkOrder workOrder = crssWorkOrder();
        WorkOrderLineItem line = insertLine(
            workOrder.Id, assetNamed('Small Asset').Id, PRODUCT_SERVICED_RECORD_TYPE_ID
        );

        Test.startTest();
        appendLine(line.Id);
        Test.stopTest();

        workOrder = crssWorkOrder();
        System.assertEquals('FLEXIBLE SCOPE - ULTRASOUND', workOrder.DeviceInspectionSummary__c);
    }

    /**
     * @description A blank sub product line keeps the product line only.
     */
    @IsTest
    static void append_blankSubProductLine_usesProductLineOnly() {
        bypassFlow();
        WorkOrder workOrder = crssWorkOrder();
        WorkOrderLineItem line = insertLine(
            workOrder.Id, assetNamed('Line Only Asset').Id, PRODUCT_SERVICED_RECORD_TYPE_ID
        );

        Test.startTest();
        appendLine(line.Id);
        Test.stopTest();

        workOrder = crssWorkOrder();
        System.assertEquals('FLEXIBLE SCOPE', workOrder.DeviceInspectionSummary__c);
    }

    /**
     * @description A blank product line does not change the work order.
     */
    @IsTest
    static void append_blankProductLine_skipsAsset() {
        bypassFlow();
        WorkOrder workOrder = crssWorkOrder();
        WorkOrderLineItem line = insertLine(
            workOrder.Id, assetNamed('Blank Line Asset').Id, PRODUCT_SERVICED_RECORD_TYPE_ID
        );

        Test.startTest();
        appendLine(line.Id);
        Test.stopTest();

        workOrder = crssWorkOrder();
        System.assertEquals(null, workOrder.DeviceInspectionSummary__c);
    }

    /**
     * @description The same product type is not written twice.
     */
    @IsTest
    static void append_sameToken_doesNotDuplicate() {
        bypassFlow();
        WorkOrder workOrder = crssWorkOrder();
        workOrder.DeviceInspectionSummary__c = 'FLEXIBLE SCOPE - ULTRASOUND';
        update workOrder;
        WorkOrderLineItem line = insertLine(
            workOrder.Id, assetNamed('Small Asset').Id, PRODUCT_SERVICED_RECORD_TYPE_ID
        );

        Test.startTest();
        appendLine(line.Id);
        Test.stopTest();

        workOrder = crssWorkOrder();
        System.assertEquals('FLEXIBLE SCOPE - ULTRASOUND', workOrder.DeviceInspectionSummary__c);
    }

    /**
     * @description A shorter product line is not treated as the longer product type already stored.
     */
    @IsTest
    static void append_shorterToken_isNotTreatedAsExistingValue() {
        bypassFlow();
        WorkOrder workOrder = crssWorkOrder();
        workOrder.DeviceInspectionSummary__c = 'FLEXIBLE SCOPE - ULTRASOUND';
        update workOrder;
        WorkOrderLineItem line = insertLine(
            workOrder.Id, assetNamed('Line Only Asset').Id, PRODUCT_SERVICED_RECORD_TYPE_ID
        );

        Test.startTest();
        appendLine(line.Id);
        Test.stopTest();

        workOrder = crssWorkOrder();
        System.assertEquals(
            'FLEXIBLE SCOPE - ULTRASOUND; FLEXIBLE SCOPE',
            workOrder.DeviceInspectionSummary__c
        );
    }

    /**
     * @description A second product type is appended after the existing value.
     */
    @IsTest
    static void append_secondToken_appendsWithSeparator() {
        bypassFlow();
        WorkOrder workOrder = crssWorkOrder();
        WorkOrderLineItem smallLine = insertLine(
            workOrder.Id, assetNamed('Small Asset').Id, PRODUCT_SERVICED_RECORD_TYPE_ID
        );
        WorkOrderLineItem largeLine = insertLine(
            workOrder.Id, assetNamed('Rigid Asset').Id, PRODUCT_SERVICED_RECORD_TYPE_ID
        );

        DeviceInspectionSummaryService.Request smallRequest = new DeviceInspectionSummaryService.Request();
        smallRequest.workOrderLineItemId = smallLine.Id;
        DeviceInspectionSummaryService.Request largeRequest = new DeviceInspectionSummaryService.Request();
        largeRequest.workOrderLineItemId = largeLine.Id;

        Test.startTest();
        DeviceInspectionSummaryService.append(new List<DeviceInspectionSummaryService.Request>{
            smallRequest,
            largeRequest
        });
        Test.stopTest();

        workOrder = crssWorkOrder();
        System.assertEquals(
            'FLEXIBLE SCOPE - ULTRASOUND; RIGID',
            workOrder.DeviceInspectionSummary__c
        );
    }

    /**
     * @description Two assets with the same product type in one save produce one value.
     */
    @IsTest
    static void append_sameTokenInOneSave_appendsOnce() {
        bypassFlow();
        WorkOrder workOrder = crssWorkOrder();
        Account account = [SELECT Id FROM Account LIMIT 1];
        Product2 small = [SELECT Id FROM Product2 WHERE Name = 'Flexible Small' LIMIT 1];
        Asset second = new Asset(Name = 'Second Small Asset', AccountId = account.Id, Product2Id = small.Id);
        insert second;
        WorkOrderLineItem firstLine = insertLine(
            workOrder.Id, assetNamed('Small Asset').Id, PRODUCT_SERVICED_RECORD_TYPE_ID
        );
        WorkOrderLineItem secondLine = insertLine(
            workOrder.Id, second.Id, PRODUCT_SERVICED_RECORD_TYPE_ID
        );

        DeviceInspectionSummaryService.Request firstRequest = new DeviceInspectionSummaryService.Request();
        firstRequest.workOrderLineItemId = firstLine.Id;
        DeviceInspectionSummaryService.Request secondRequest = new DeviceInspectionSummaryService.Request();
        secondRequest.workOrderLineItemId = secondLine.Id;

        Test.startTest();
        DeviceInspectionSummaryService.append(new List<DeviceInspectionSummaryService.Request>{
            firstRequest,
            secondRequest
        });
        Test.stopTest();

        workOrder = crssWorkOrder();
        System.assertEquals('FLEXIBLE SCOPE - ULTRASOUND', workOrder.DeviceInspectionSummary__c);
    }

    /**
     * @description A work order that is not CRSS is left unchanged.
     */
    @IsTest
    static void append_nonCrssWorkOrder_skipsLine() {
        bypassFlow();
        Account account = [SELECT Id FROM Account LIMIT 1];
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'ES Device Inspection',
            RecordTypeId = ES_RECORD_TYPE_ID,
            Status = 'New'
        );
        insert workOrder;
        WorkOrderLineItem line = insertLine(
            workOrder.Id, assetNamed('Small Asset').Id, PRODUCT_SERVICED_RECORD_TYPE_ID
        );

        Test.startTest();
        appendLine(line.Id);
        Test.stopTest();

        workOrder = [SELECT DeviceInspectionSummary__c FROM WorkOrder WHERE Id = :workOrder.Id];
        System.assertEquals(null, workOrder.DeviceInspectionSummary__c);
    }

    /**
     * @description A line that is not Product Serviced is left unchanged.
     */
    @IsTest
    static void append_nonProductServicedLine_skipsLine() {
        bypassFlow();
        WorkOrder workOrder = crssWorkOrder();
        Product2 product = [SELECT Id FROM Product2 WHERE Name = 'Flexible Small' LIMIT 1];
        WorkOrderLineItem line = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            AssetId = assetNamed('Small Asset').Id,
            Product__c = product.Id,
            RecordTypeId = USAGE_CONSUMPTION_RECORD_TYPE_ID,
            LineType__c = 'Parts'
        );
        insert line;

        Test.startTest();
        appendLine(line.Id);
        Test.stopTest();

        workOrder = crssWorkOrder();
        System.assertEquals(null, workOrder.DeviceInspectionSummary__c);
    }

    /**
     * @description An empty request does nothing.
     */
    @IsTest
    static void append_emptyRequest_doesNothing() {
        Test.startTest();
        DeviceInspectionSummaryService.append(null);
        DeviceInspectionSummaryService.append(new List<DeviceInspectionSummaryService.Request>());
        Test.stopTest();

        WorkOrder workOrder = crssWorkOrder();
        System.assertEquals(null, workOrder.DeviceInspectionSummary__c);
    }

    /**
     * @description Saving a new Product Serviced asset on a CRSS work order fills the field.
     */
    @IsTest
    static void flow_newProductServicedAsset_setsSummary() {
        WorkOrder workOrder = crssWorkOrder();

        Test.startTest();
        insertLine(workOrder.Id, assetNamed('Small Asset').Id, PRODUCT_SERVICED_RECORD_TYPE_ID);
        Test.stopTest();

        workOrder = crssWorkOrder();
        System.assertEquals('FLEXIBLE SCOPE - ULTRASOUND', workOrder.DeviceInspectionSummary__c);
    }

    /**
     * @description Setting an Asset on a line that had none appends the product type.
     */
    @IsTest
    static void flow_assetAddedToExistingLine_appendsToken() {
        WorkOrder workOrder = crssWorkOrder();
        WorkOrderLineItem line = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            RecordTypeId = PRODUCT_SERVICED_RECORD_TYPE_ID,
            LineType__c = 'Product Serviced'
        );
        insert line;

        Test.startTest();
        line.AssetId = assetNamed('Rigid Asset').Id;
        update line;
        Test.stopTest();

        workOrder = crssWorkOrder();
        System.assertEquals('RIGID', workOrder.DeviceInspectionSummary__c);
    }
}