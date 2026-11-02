/**
 * @description Tests for GW-580 Product Request to DPC launch.
 */
@IsTest
private class ProductRequestsDpcServiceTest {

    @IsTest
    static void shouldReturnCatalogUrl_WhenRequiredKeysArePresent() {
        ProductRequest pr = insertReadyProductRequest('764327358/01', '031171812', '2132');

        ProductRequestsDpcService.DpcLaunchRequest req = new ProductRequestsDpcService.DpcLaunchRequest();
        req.productRequestId = pr.Id;

        Test.startTest();
        List<ProductRequestsDpcService.DpcLaunchResult> results = ProductRequestsDpcService.openDpc(
            new List<ProductRequestsDpcService.DpcLaunchRequest>{ req }
        );
        Test.stopTest();

        Assert.areEqual(true, results[0].success, results[0].message);
        Assert.areEqual('https://dpc.example/topics/IS?filterId=1', results[0].catalogUrl);
        ProductRequest numbered = [SELECT ProductRequestNumber FROM ProductRequest WHERE Id = :pr.Id];
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(results[0].requestJson);
        Assert.areEqual(5, sent.size(), results[0].requestJson);
        Assert.areEqual('2132', sent.get('CustomerPO'));
        Assert.areEqual(numbered.ProductRequestNumber, sent.get('ProductRequestNum'));
        Assert.isTrue(sent.containsKey('AddressID'), results[0].requestJson);
        Assert.isNull(sent.get('AddressID'));
        Assert.areEqual('031171812', sent.get('SerialNum'));
        Assert.areEqual('764327358-01', sent.get('PMCLVersionNum'));

        ProductRequest unchanged = [
            SELECT IntegrationStatus__c, ERPOrderNumber__c, SubmissionToERP__c, DPCOrderNumber__c
            FROM ProductRequest
            WHERE Id = :pr.Id
        ];
        Assert.isNull(unchanged.IntegrationStatus__c);
        Assert.isNull(unchanged.ERPOrderNumber__c);
        Assert.isNull(unchanged.SubmissionToERP__c);
        Assert.areEqual(numbered.ProductRequestNumber, unchanged.DPCOrderNumber__c);
    }

    @IsTest
    static void shouldSendProductRequestPo_WhenBothPosAreSet() {
        ProductRequest pr = insertReadyProductRequest('764327358-01', '031171812', 'WO-PO', 'PR-PO');
        ProductRequestsDpcService.DpcLaunchRequest req = new ProductRequestsDpcService.DpcLaunchRequest();
        req.productRequestId = pr.Id;

        List<ProductRequestsDpcService.DpcLaunchResult> results = ProductRequestsDpcService.openDpc(
            new List<ProductRequestsDpcService.DpcLaunchRequest>{ req }
        );

        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(results[0].requestJson);
        Assert.areEqual(true, results[0].success, results[0].message);
        Assert.areEqual('PR-PO', sent.get('CustomerPO'));
    }

    @IsTest
    static void shouldSendWorkOrderPo_WhenProductRequestPoIsBlank() {
        ProductRequest pr = insertReadyProductRequest('764327358-01', '031171812', 'WO-PO', null);
        ProductRequestsDpcService.DpcLaunchRequest req = new ProductRequestsDpcService.DpcLaunchRequest();
        req.productRequestId = pr.Id;

        List<ProductRequestsDpcService.DpcLaunchResult> results = ProductRequestsDpcService.openDpc(
            new List<ProductRequestsDpcService.DpcLaunchRequest>{ req }
        );

        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(results[0].requestJson);
        Assert.areEqual(true, results[0].success, results[0].message);
        Assert.areEqual('WO-PO', sent.get('CustomerPO'));
    }

    @IsTest
    static void shouldKeepDpcOrderNumber_WhenAlreadySet() {
        ProductRequest pr = insertReadyProductRequest('764327358-01', '031171812', '2132');
        update new ProductRequest(Id = pr.Id, DPCOrderNumber__c = 'DPC-000123');
        ProductRequestsDpcService.DpcLaunchRequest req = new ProductRequestsDpcService.DpcLaunchRequest();
        req.productRequestId = pr.Id;

        List<ProductRequestsDpcService.DpcLaunchResult> results = ProductRequestsDpcService.openDpc(
            new List<ProductRequestsDpcService.DpcLaunchRequest>{ req }
        );

        Assert.areEqual(true, results[0].success, results[0].message);
        Assert.areEqual('DPC-000123', [SELECT DPCOrderNumber__c FROM ProductRequest WHERE Id = :pr.Id].DPCOrderNumber__c);
    }

    @IsTest
    static void shouldNotStampDpcOrderNumber_WhenDpcFails() {
        ProductRequest pr = insertReadyProductRequest('764327358-01', '031171812', '2132');
        ProductRequestsDpcService.testResponseOverride = new Map<String, Object>{ 'SO_SUCCESS' => false };
        ProductRequestsDpcService.DpcLaunchRequest req = new ProductRequestsDpcService.DpcLaunchRequest();
        req.productRequestId = pr.Id;

        List<ProductRequestsDpcService.DpcLaunchResult> results = ProductRequestsDpcService.openDpc(
            new List<ProductRequestsDpcService.DpcLaunchRequest>{ req }
        );

        Assert.areEqual(false, results[0].success);
        Assert.isNull([SELECT DPCOrderNumber__c FROM ProductRequest WHERE Id = :pr.Id].DPCOrderNumber__c);
    }

    @IsTest
    static void shouldBlock_WhenPfclIsMissing() {
        ProductRequest pr = insertReadyProductRequest(null, '031171812', '2132');
        ProductRequestsDpcService.DpcLaunchRequest req = new ProductRequestsDpcService.DpcLaunchRequest();
        req.productRequestId = pr.Id;

        List<ProductRequestsDpcService.DpcLaunchResult> results = ProductRequestsDpcService.openDpc(
            new List<ProductRequestsDpcService.DpcLaunchRequest>{ req }
        );

        Assert.areEqual(false, results[0].success);
        Assert.areEqual('Asset PFCL is required to open DPC.', results[0].message);
        Assert.isNull(results[0].catalogUrl);
    }

    @IsTest
    static void shouldBlock_WhenSerialNumberIsMissing() {
        ProductRequest pr = insertReadyProductRequest('764327358-01', null, '2132');
        ProductRequestsDpcService.DpcLaunchRequest req = new ProductRequestsDpcService.DpcLaunchRequest();
        req.productRequestId = pr.Id;

        List<ProductRequestsDpcService.DpcLaunchResult> results = ProductRequestsDpcService.openDpc(
            new List<ProductRequestsDpcService.DpcLaunchRequest>{ req }
        );

        Assert.areEqual(false, results[0].success);
        Assert.areEqual('Asset serial number is required to open DPC.', results[0].message);
    }

    @IsTest
    static void shouldReturnCatalogUrl_WhenResponseIsPlainUrl() {
        ProductRequest pr = insertReadyProductRequest('764327009-01', '031171812', '2132');
        String catalogUrl = 'https://partcatalogtst.steris.com/ACD/delivery/?PONumber=2132#/V=2/topics/IS?filterId=1';
        ProductRequestsDpcService.testResponseOverride = new Map<String, Object>{
            'SO_SUCCESS' => true,
            'SERVICE_DATA' => catalogUrl
        };

        ProductRequestsDpcService.DpcLaunchRequest req = new ProductRequestsDpcService.DpcLaunchRequest();
        req.productRequestId = pr.Id;

        List<ProductRequestsDpcService.DpcLaunchResult> results = ProductRequestsDpcService.openDpc(
            new List<ProductRequestsDpcService.DpcLaunchRequest>{ req }
        );

        Assert.areEqual(true, results[0].success, results[0].message);
        Assert.areEqual(catalogUrl, results[0].catalogUrl);
    }

    @IsTest
    static void shouldReportRelativePath_WhenClientUrlIsNotAbsolute() {
        ProductRequest pr = insertReadyProductRequest('764327339-01', '031171812', '2132');
        ProductRequestsDpcService.testResponseOverride = new Map<String, Object>{
            'SO_SUCCESS' => true,
            'SERVICE_DATA' => new Map<String, Object>{
                'clientURL' => new Map<String, Object>{
                    'key' => 'clientURL',
                    'value' => '/topics/IS?filterId=1'
                }
            }
        };

        ProductRequestsDpcService.DpcLaunchRequest req = new ProductRequestsDpcService.DpcLaunchRequest();
        req.productRequestId = pr.Id;

        List<ProductRequestsDpcService.DpcLaunchResult> results = ProductRequestsDpcService.openDpc(
            new List<ProductRequestsDpcService.DpcLaunchRequest>{ req }
        );

        Assert.areEqual(false, results[0].success);
        Assert.isTrue(results[0].message.contains('/topics/IS?filterId=1'), results[0].message);
        Assert.isNull(results[0].catalogUrl);
    }

    @IsTest
    static void shouldBlock_WhenWorkOrderIsMissing() {
        ProductRequest pr = new ProductRequest(Status = 'Draft');
        insert pr;

        ProductRequestsDpcService.DpcLaunchRequest req = new ProductRequestsDpcService.DpcLaunchRequest();
        req.productRequestId = pr.Id;

        List<ProductRequestsDpcService.DpcLaunchResult> results = ProductRequestsDpcService.openDpc(
            new List<ProductRequestsDpcService.DpcLaunchRequest>{ req }
        );

        Assert.areEqual(false, results[0].success);
        Assert.areEqual('Work Order is required to open DPC.', results[0].message);
    }

    @IsTest
    static void shouldReturnDpcError_WhenCalloutHasNoUrl() {
        ProductRequest pr = insertReadyProductRequest('764327358-01', '031171812', '2132');
        ProductRequestsDpcService.testResponseOverride = new Map<String, Object>{
            'SO_SUCCESS' => true,
            'SERVICE_DATA' => new Map<String, Object>{
                'success' => false,
                'message' => 'No PFCL match.'
            }
        };

        ProductRequestsDpcService.DpcLaunchRequest req = new ProductRequestsDpcService.DpcLaunchRequest();
        req.productRequestId = pr.Id;

        List<ProductRequestsDpcService.DpcLaunchResult> results = ProductRequestsDpcService.openDpc(
            new List<ProductRequestsDpcService.DpcLaunchRequest>{ req }
        );

        Assert.areEqual(false, results[0].success);
        Assert.areEqual('No PFCL match.', results[0].message);
        Assert.isNull(results[0].catalogUrl);
    }

    @IsTest
    static void shouldReturnEmpty_WhenRequestListIsNull() {
        Assert.areEqual(0, ProductRequestsDpcService.openDpc(null).size());
    }

    @IsTest
    static void shouldSelectProductRequests_WhenSelectorMethodsAreCalled() {
        ProductRequest pr = insertReadyProductRequest('764327358-01', '031171812', '2132');
        Set<Id> ids = new Set<Id>{ pr.Id };
        Assert.areEqual(1, ProductRequestsSelector.selectById(ids).size());
        Assert.areEqual(0, ProductRequestsSelector.selectById(new Set<Id>()).size());
        Assert.isTrue(ProductRequestsSelector.selectByStatus(new Set<String>{ 'Draft' }).size() > 0);
        Assert.areEqual(0, ProductRequestsSelector.selectByStatus(new Set<String>()).size());
        Assert.areEqual(1, ProductRequestsSelector.selectByWorkOrderId(new Set<Id>{ pr.WorkOrderId }).size());
        Assert.areEqual(0, ProductRequestsSelector.selectByWorkOrderId(new Set<Id>()).size());
        Assert.areEqual(1, ProductRequestsSelector.selectByIdWithLineItems(ids).size());
        Assert.areEqual(0, ProductRequestsSelector.selectByIdWithLineItems(new Set<Id>()).size());
        Assert.areEqual(0, ProductRequestsSelector.selectForDpcLaunch(new Set<Id>()).size());
    }

    private static ProductRequest insertReadyProductRequest(
        String pfcl,
        String serialNumber,
        String customerPo
    ) {
        return insertReadyProductRequest(pfcl, serialNumber, customerPo, null);
    }

    private static ProductRequest insertReadyProductRequest(
        String pfcl,
        String serialNumber,
        String workOrderPo,
        String productRequestPo
    ) {
        Account acct = insertAccount();
        Asset asset = insertAsset(acct.Id, serialNumber, pfcl);
        WorkOrder wo = insertWorkOrder(acct.Id, asset.Id, workOrderPo);
        ProductRequest pr = new ProductRequest(
            Status = 'Draft',
            WorkOrderId = wo.Id,
            AccountId = acct.Id,
            PONumber__c = productRequestPo
        );
        insert pr;
        return pr;
    }

    private static Account insertAccount() {
        Account acct = new Account(Name = 'DPC Launch ' + String.valueOf(Crypto.getRandomInteger()));
        insert acct;
        return acct;
    }

    private static Asset insertAsset(Id accountId, String serialNumber, String pfclValue) {
        Product2 product = new Product2(Name = 'DPC Product', IsActive = true);
        if (String.isNotBlank(pfclValue)) {
            PFCL__c pfcl = new PFCL__c(PFCL__c = pfclValue);
            insert pfcl;
            product.PFCL__c = pfcl.Id;
        }
        insert product;
        Asset asset = new Asset(
            Name = 'DPC Asset',
            AccountId = accountId,
            SerialNumber = serialNumber,
            Product2Id = product.Id
        );
        insert asset;
        return asset;
    }

    private static WorkOrder insertWorkOrder(Id accountId, Id assetId, String customerPo) {
        WorkOrder wo = new WorkOrder(
            AccountId = accountId,
            AssetId = assetId,
            Status = 'New',
            CustomerPO__c = customerPo
        );
        insert wo;
        return wo;
    }
}