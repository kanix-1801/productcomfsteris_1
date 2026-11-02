/**
 * @description GW-3398: Tests for WorkOrderOverhaulCodeInvocable.
 */
@IsTest
private class WorkOrderOverhaulCodeInvocableTest {
    @IsTest
    static void resolve_ccdCodeWinsOverInsertionCode() {
        String overhaulCode = WorkOrderOverhaulCodeService.resolveOverhaulProductCode(
            'FS.17370',
            new Set<String>{ 'SC.CCD907', 'SC.INT062', 'SC.ELC903' }
        );

        System.assertEquals('SC.FER902', overhaulCode, 'CCD907 should select SC.FER902 before the insertion branch');
    }

    @IsTest
    static void resolve_insertionWithElectricalSelectsLevelThree() {
        String overhaulCode = WorkOrderOverhaulCodeService.resolveOverhaulProductCode(
            'fs.11083',
            new Set<String>{ 'SC.INT062', 'SC.LGT902' }
        );

        System.assertEquals('SC.FER908', overhaulCode, 'FS.11083 with INT062 and an electrical code should select SC.FER908');
    }

    @IsTest
    static void resolve_insertionWithoutElectricalSelectsLevelTwo() {
        String overhaulCode = WorkOrderOverhaulCodeService.resolveOverhaulProductCode(
            'FS.10511',
            new Set<String>{ 'SC.INT061' }
        );

        System.assertEquals('SC.FER900', overhaulCode, 'FS.10511 with only INT061 should select SC.FER900');
    }

    @IsTest
    static void resolve_legacyMatrixUsesUnprefixedElectricalCode() {
        String overhaulCode = WorkOrderOverhaulCodeService.resolveOverhaulProductCode(
            'FS.10433',
            new Set<String>{ 'SC.INT063', 'ELC010' }
        );

        System.assertEquals('SC.FER300', overhaulCode, 'ELC010 should be treated as SC.ELC010');
    }

    @IsTest
    static void resolve_olympus1100SheetTypoReturnsPrefixedCode() {
        String overhaulCode = WorkOrderOverhaulCodeService.resolveOverhaulProductCode(
            'FS.11119',
            new Set<String>{ 'SC.CCD1107' }
        );

        System.assertEquals('SC.FER1102', overhaulCode, 'FER.1102 in the matrix should return SC.FER1102');
    }

    @IsTest
    static void resolve_unknownModelReturnsNull() {
        String overhaulCode = WorkOrderOverhaulCodeService.resolveOverhaulProductCode(
            'FS.17243',
            new Set<String>{ 'SC.CCD907' }
        );

        System.assertEquals(null, overhaulCode, 'A model outside the matrix should not return an overhaul code');
    }

    @IsTest
    static void determine_usesAssetModelAndWorkOrderLineItems() {
        Account account = new Account(
            Name = 'Overhaul Code Account',
            SystemID__c = 'ovhcode1',
            SourceSystemID__c = 'Oracle-ovhcode1'
        );
        insert account;

        Product2 modelProduct = new Product2(Name = 'Model FS.17368', ProductCode = 'FS.17368', IsActive = true);
        Product2 serviceProduct = new Product2(Name = 'Service SC.INT061', ProductCode = 'SC.INT061', IsActive = true);
        insert new List<Product2>{ modelProduct, serviceProduct };

        Asset asset = new Asset(Name = 'Overhaul Asset', AccountId = account.Id, Product2Id = modelProduct.Id);
        insert asset;

        Id pricebookId = Test.getStandardPricebookId();
        PricebookEntry pricebookEntry = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = serviceProduct.Id,
            UnitPrice = 1,
            IsActive = true
        );
        insert pricebookEntry;

        WorkOrder workOrder = new WorkOrder(
            Subject = 'Overhaul Test',
            Status = 'New',
            AssetId = asset.Id,
            Pricebook2Id = pricebookId
        );
        insert workOrder;
        insert new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            PricebookEntryId = pricebookEntry.Id,
            Quantity = 1,
            Status = 'New'
        );

        WorkOrderOverhaulCodeInvocable.Request request = new WorkOrderOverhaulCodeInvocable.Request();
        request.recordId = workOrder.Id;

        Test.startTest();
        List<WorkOrderOverhaulCodeInvocable.Result> results = WorkOrderOverhaulCodeInvocable.determineOverhaulProductCode(
            new List<WorkOrderOverhaulCodeInvocable.Request>{ request }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One request should return one result');
        System.assertEquals('SC.FER903', results[0].overhaulProductCode, 'FS.17368 with only INT061 should select SC.FER903');
    }

    @IsTest
    static void determine_nullAndEmptyRequestsReturnEmpty() {
        System.assertEquals(
            0,
            WorkOrderOverhaulCodeInvocable.determineOverhaulProductCode(null).size(),
            'A null request list should return no results'
        );
        System.assertEquals(
            0,
            WorkOrderOverhaulCodeService.determineOverhaulProductCodes(new List<Id>()).size(),
            'An empty Id list should return no codes'
        );
    }

    @IsTest
    static void resolve_blankModelOrCodesReturnNull() {
        System.assertEquals(
            null,
            WorkOrderOverhaulCodeService.resolveOverhaulProductCode(null, new Set<String>{ 'SC.INT061' }),
            'A blank model should not return a code'
        );
        System.assertEquals(
            null,
            WorkOrderOverhaulCodeService.resolveOverhaulProductCode('FS.17370', null),
            'Missing service codes should not return a code'
        );
        System.assertEquals(
            null,
            WorkOrderOverhaulCodeService.resolveOverhaulProductCode('FS.17370', new Set<String>{ '  ' }),
            'Blank service codes should not return a code'
        );
    }

    @IsTest
    static void determine_blankRecordIdReturnsBlankCode() {
        WorkOrderOverhaulCodeInvocable.Request request = new WorkOrderOverhaulCodeInvocable.Request();

        List<WorkOrderOverhaulCodeInvocable.Result> results = WorkOrderOverhaulCodeInvocable.determineOverhaulProductCode(
            new List<WorkOrderOverhaulCodeInvocable.Request>{ request, null }
        );

        System.assertEquals(2, results.size(), 'Each request should return a result');
        System.assertEquals(null, results[0].overhaulProductCode, 'A blank record Id should not return a code');
        System.assertEquals(null, results[1].overhaulProductCode, 'A null request should not return a code');
    }

    @IsTest
    static void resolve_sheetMatrixCoversEveryModelFamily() {
        assertFamily(
            new List<String>{ 'FS.17370', 'FS.17377', 'FS.10481', 'FS.10522' },
            'SC.CCD907',
            'SC.INT062',
            'SC.ELC903',
            'SC.FER902',
            'SC.FER904',
            'SC.FER903'
        );
        assertFamily(
            new List<String>{ 'FS.11083' },
            'SC.CCD907',
            'SC.INT062',
            'SC.ELC903',
            'SC.FER902',
            'SC.FER908',
            'SC.FER907'
        );
        assertFamily(
            new List<String>{ 'FS.17368', 'FS.17369', 'FS.10913' },
            'SC.CCD907',
            'SC.INT061',
            'SC.ELC903',
            'SC.FER902',
            'SC.FER904',
            'SC.FER903'
        );
        assertFamily(
            new List<String>{ 'FS.10511' },
            'SC.CCD907',
            'SC.INT061',
            'SC.ELC903',
            'SC.FER902',
            'SC.FER904',
            'SC.FER900'
        );
        assertFamily(
            new List<String>{ 'FS.11073' },
            'SC.CCD907',
            'SC.INT063',
            'SC.ELC903',
            'SC.FER902',
            'SC.FER904',
            'SC.FER903'
        );
        assertFamily(
            new List<String>{ 'FS.11089', 'FS.11137' },
            'SC.CCD1107',
            'SC.INT1162',
            'SC.ELC1103',
            'SC.FER1102',
            'SC.FER1104',
            'SC.FER1103'
        );
        assertFamily(
            new List<String>{ 'FS.11119', 'FS.11152' },
            'SC.CCD1107',
            'SC.INT1161',
            'SC.ELC1103',
            'SC.FER1102',
            'SC.FER1104',
            'SC.FER1103'
        );
        assertFamily(
            new List<String>{
                'FS.10433', 'FS.17350', 'FS.17353', 'FS.10374', 'FS.10299', 'FS.10332',
                'FS.12012', 'FS.17365', 'FS.17366', 'FS.10290', 'FS.10435', 'FS.10358',
                'FS.10454', 'FS.10449', 'FS.10243', 'FS.10903', 'FS.10518', 'FS.11486',
                'FS.10927', 'FS.17337', 'FS.10268', 'FS.10489', 'FS.10246', 'FS.10514'
            },
            'SC.CCD007',
            'SC.INT061',
            'SC.ELC010',
            'SC.FER302',
            'SC.FER300',
            'SC.FER200'
        );
    }

    private static void assertFamily(
        List<String> models,
        String ccdCode,
        String insertionCode,
        String electricalCode,
        String ccdOverhaul,
        String electricalOverhaul,
        String insertionOverhaul
    ) {
        for (String modelCode : models) {
            System.assertEquals(
                ccdOverhaul,
                WorkOrderOverhaulCodeService.resolveOverhaulProductCode(
                    modelCode,
                    new Set<String>{ ccdCode, insertionCode, electricalCode }
                ),
                modelCode + ' with a CCD code should select ' + ccdOverhaul
            );
            System.assertEquals(
                electricalOverhaul,
                WorkOrderOverhaulCodeService.resolveOverhaulProductCode(
                    modelCode,
                    new Set<String>{ insertionCode, electricalCode }
                ),
                modelCode + ' with insertion and electrical should select ' + electricalOverhaul
            );
            System.assertEquals(
                insertionOverhaul,
                WorkOrderOverhaulCodeService.resolveOverhaulProductCode(
                    modelCode,
                    new Set<String>{ insertionCode }
                ),
                modelCode + ' with only the insertion code should select ' + insertionOverhaul
            );
        }
    }
}