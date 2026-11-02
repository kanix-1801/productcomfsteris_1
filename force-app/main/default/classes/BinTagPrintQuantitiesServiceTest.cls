/**
 * @description Tests for BinTagPrintQuantitiesSelector and BinTagPrintQuantitiesService (GW-3595 / GW-4637).
 */
@IsTest
private class BinTagPrintQuantitiesServiceTest {
    private static final String PRODUCT_LINE = 'INSTRUMENT';

    @TestSetup
    static void setupData() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'Bin Tag Qty Repair Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        insert new BinTagPrintQuantity__c(
            RepairCenter__c = repairCenter.Id,
            Country__c = 'United States',
            Product_Line__c = PRODUCT_LINE,
            PrintQuantity__c = 3
        );
    }

    @IsTest
    static void testSelectorBuilderReturnsMappingByRepairCenterAndProductLine() {
        Schema.Location repairCenter = [SELECT Id FROM Location WHERE Name = 'Bin Tag Qty Repair Center' LIMIT 1];

        Test.startTest();
        List<BinTagPrintQuantity__c> rows = (List<BinTagPrintQuantity__c>) new BinTagPrintQuantitiesSelector()
            .selectFields(
                new List<String>{ 'Id', 'PrintQuantity__c', 'RepairCenter__c', 'Product_Line__c' }
            )
            .whereEquals('RepairCenter__c', repairCenter.Id)
            .whereEquals('Product_Line__c', PRODUCT_LINE)
            .orderByDesc('LastModifiedDate')
            .limitTo(1)
            .execute();
        Test.stopTest();

        Assert.areEqual(1, rows.size(), 'Should return the mapping without using Country');
        Assert.areEqual(3, Integer.valueOf(rows[0].PrintQuantity__c));
    }

    @IsTest
    static void testServiceReturnsQuantityWithoutCountry() {
        Schema.Location repairCenter = [SELECT Id FROM Location WHERE Name = 'Bin Tag Qty Repair Center' LIMIT 1];

        Test.startTest();
        Integer copies = BinTagPrintQuantitiesService.getPrintQuantity(
            repairCenter.Id,
            PRODUCT_LINE
        );
        Test.stopTest();

        Assert.areEqual(3, copies);
    }

    @IsTest
    static void testServiceDefaultsNullPrintQuantityToOne() {
        Schema.Location repairCenter = [SELECT Id FROM Location WHERE Name = 'Bin Tag Qty Repair Center' LIMIT 1];
        BinTagPrintQuantity__c mapping = [
            SELECT Id
            FROM BinTagPrintQuantity__c
            WHERE RepairCenter__c = :repairCenter.Id
            LIMIT 1
        ];
        mapping.PrintQuantity__c = null;
        update mapping;

        Test.startTest();
        Integer copies = BinTagPrintQuantitiesService.getPrintQuantity(
            repairCenter.Id,
            PRODUCT_LINE
        );
        Test.stopTest();

        Assert.areEqual(BinTagPrintQuantitiesService.DEFAULT_PRINT_QUANTITY, copies);
    }

    @IsTest
    static void testServiceUsesTestOverride() {
        BinTagPrintQuantitiesService.testPrintQuantity = 7;

        Test.startTest();
        Integer copies = BinTagPrintQuantitiesService.getPrintQuantity(
            UserInfo.getUserId(),
            PRODUCT_LINE
        );
        Test.stopTest();

        Assert.areEqual(7, copies);
        BinTagPrintQuantitiesService.testPrintQuantity = null;
    }

    @IsTest
    static void testServiceDefaultsToOneWhenInputsMissing() {
        Test.startTest();
        Integer copies = BinTagPrintQuantitiesService.getPrintQuantity(null, PRODUCT_LINE);
        Integer blankProductLine = BinTagPrintQuantitiesService.getPrintQuantity(
            UserInfo.getUserId(),
            '  '
        );
        Test.stopTest();

        Assert.areEqual(BinTagPrintQuantitiesService.DEFAULT_PRINT_QUANTITY, copies);
        Assert.areEqual(BinTagPrintQuantitiesService.DEFAULT_PRINT_QUANTITY, blankProductLine);
    }

    @IsTest
    static void testServiceDefaultsToOneWhenMappingMissing() {
        Schema.Location repairCenter = [SELECT Id FROM Location WHERE Name = 'Bin Tag Qty Repair Center' LIMIT 1];

        Test.startTest();
        Integer copies = BinTagPrintQuantitiesService.getPrintQuantity(
            repairCenter.Id,
            'UNKNOWN LINE'
        );
        Test.stopTest();

        Assert.areEqual(BinTagPrintQuantitiesService.DEFAULT_PRINT_QUANTITY, copies);
    }

    @IsTest
    static void testSelectorConstructor() {
        Test.startTest();
        BinTagPrintQuantitiesSelector selector = new BinTagPrintQuantitiesSelector();
        Test.stopTest();

        Assert.isNotNull(selector);
    }
}