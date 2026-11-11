/**
 * @description Test class for AssetsService.
 *              Covers create, update, delete, and retrieval operations
 *              across positive, negative, bulk, and empty-input scenarios.
 */
@IsTest
private class AssetsServiceTest {

    @TestSetup
    static void setupTestData() {
        // Build and persist an Account to parent the Assets
        adb_Account accountBuilder = new adb_Account();
        accountBuilder.persist();

        // Build and persist 10 Assets
        List<Asset> assetList = new List<Asset>();
        for (Integer i = 0; i < 10; i++) {
            Asset a = (Asset) new adb_Asset().name('Test Asset ' + i).record;
            a.AccountId = accountBuilder.id;
            assetList.add(a);
        }
        insert assetList;
    }

    // ── createAssets ─────────────────────────────────────────────────────────

    @IsTest
    static void shouldCreateAssets_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Id accountId = [SELECT Id FROM Account LIMIT 1].Id;
            List<Asset> assetList = new List<Asset>();
            for (Integer i = 0; i < 3; i++) {
                Asset a = (Asset) new adb_Asset().name('New Asset ' + i).record;
                a.AccountId = accountId;
                assetList.add(a);
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            AssetsService.createAssets(assetList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> insertedIds = new Map<Id, Asset>(assetList).keySet();
            List<Asset> insertedList = [SELECT Id FROM Asset WHERE Id IN :insertedIds];
            Assert.areEqual(3, insertedList.size(), 'createAssets should insert all 3 Assets');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenCreateAssetsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM Asset];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            AssetsService.createAssets(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM Asset];
            Assert.areEqual(countBefore, countAfter, 'createAssets with null should not insert any records');
        }
    }

    // ── deleteAssets ─────────────────────────────────────────────────────────

    @IsTest
    static void shouldDeleteAssets_WhenValidIdsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> assetIdSet = new Map<Id, Asset>([SELECT Id FROM Asset LIMIT 3]).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            AssetsService.deleteAssets(assetIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer remainingCount = [SELECT COUNT() FROM Asset WHERE Id IN :assetIdSet];
            Assert.areEqual(0, remainingCount, 'deleteAssets should delete all specified Assets');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenDeleteAssetsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM Asset];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            AssetsService.deleteAssets(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM Asset];
            Assert.areEqual(countBefore, countAfter, 'deleteAssets with null should not delete any records');
        }
    }

    // ── getAssetsById ─────────────────────────────────────────────────────────

    @IsTest
    static void shouldReturnAssets_WhenGetByIdCalledWithValidIds() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Set<Id> assetIdSet = new Map<Id, Asset>([SELECT Id FROM Asset]).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<Asset> resultList = AssetsService.getAssetsById(assetIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(10, resultList.size(), 'getAssetsById should return all 10 Assets');
        }
    }

    @IsTest
    static void shouldReturnEmpty_WhenGetByIdCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<Asset> resultList = AssetsService.getAssetsById(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getAssetsById with null should return an empty list');
        }
    }

    @IsTest
    static void shouldReturnMatchingAsset_WhenElevatedSerialAndProductMatch() {
        Id accountId = [SELECT Id FROM Account LIMIT 1].Id;
        Product2 product = new Product2(
            Name = 'Asset Elevated Match Product',
            ProductCode = 'ASSET-ELEV-1',
            IsActive = true
        );
        insert product;
        Asset matching = new Asset(
            Name = 'Elevated Matching Asset',
            AccountId = accountId,
            Product2Id = product.Id,
            SerialNumber = 'SN-ELEV-6877'
        );
        insert matching;

        Test.startTest();
        List<Asset> matches = AssetsService.getAssetsBySerialAndProductElevated(
            new Set<String>{ 'SN-ELEV-6877' },
            product.Id
        );
        Test.stopTest();

        Assert.areEqual(1, matches.size(), 'Elevated lookup should return the matching Asset');
        Assert.areEqual(matching.Id, matches[0].Id);
        Assert.areEqual('SN-ELEV-6877', matches[0].SerialNumber);
        Assert.areEqual(product.Id, matches[0].Product2Id);
        Assert.areEqual('ASSET-ELEV-1', matches[0].Product2.ProductCode);
    }

    @IsTest
    static void shouldReturnEmpty_WhenElevatedSerialOrProductGuardFails() {
        Product2 product = new Product2(Name = 'Asset Elevated Guard Product', IsActive = true);
        insert product;

        Assert.isTrue(
            AssetsService.getAssetsBySerialAndProductElevated(null, product.Id).isEmpty(),
            'Null serials should return no Assets'
        );
        Assert.isTrue(
            AssetsService.getAssetsBySerialAndProductElevated(new Set<String>(), product.Id).isEmpty(),
            'Empty serials should return no Assets'
        );
        Assert.isTrue(
            AssetsService.getAssetsBySerialAndProductElevated(new Set<String>{ 'SN-1' }, null).isEmpty(),
            'Null product should return no Assets'
        );
    }

    @IsTest
    static void shouldUpdateAssets_WhenUpdateAssetsElevatedCalled() {
        Asset assetRow = [SELECT Id, SerialNumber, Name FROM Asset LIMIT 1];
        assetRow.SerialNumber = 'SN-ELEV-UPD-6877';
        assetRow.Name = 'Elevated Update Asset';

        Test.startTest();
        AssetsService.updateAssetsElevated(new List<Asset>{ assetRow });
        Test.stopTest();

        Asset updated = [
            SELECT Id, SerialNumber, Name
            FROM Asset
            WHERE Id = :assetRow.Id
        ];
        Assert.areEqual('SN-ELEV-UPD-6877', updated.SerialNumber);
        Assert.areEqual('Elevated Update Asset', updated.Name);
    }

    @IsTest
    static void shouldDoNothing_WhenUpdateAssetsElevatedCalledWithEmptyOrNull() {
        Integer countBefore = [SELECT COUNT() FROM Asset];
        AssetsService.updateAssetsElevated(null);
        AssetsService.updateAssetsElevated(new List<Asset>());
        Assert.areEqual(countBefore, [SELECT COUNT() FROM Asset]);
    }

    @IsTest
    static void shouldDoNothing_WhenCreateAssetsCalledWithEmptyList() {
        Integer countBefore = [SELECT COUNT() FROM Asset];
        AssetsService.createAssets(new List<Asset>());
        Assert.areEqual(countBefore, [SELECT COUNT() FROM Asset]);
    }

    @IsTest
    static void shouldReturnEarly_WhenDeleteAssetsFindsNoRows() {
        Set<Id> deletedIds = new Map<Id, Asset>([SELECT Id FROM Asset LIMIT 1]).keySet();
        delete [SELECT Id FROM Asset WHERE Id IN :deletedIds];

        Test.startTest();
        AssetsService.deleteAssets(deletedIds);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Asset WHERE Id IN :deletedIds]);
    }

    @IsTest
    static void shouldThrow_WhenCreateAssetsFailsValidation() {
        Boolean threw = false;
        try {
            AssetsService.createAssets(new List<Asset>{ new Asset() });
        } catch (AssetsService.AssetsServiceException e) {
            threw = true;
            Assert.isTrue(
                String.isNotBlank(e.getMessage()),
                'Create failure should surface a service message'
            );
        }
        Assert.isTrue(threw, 'Invalid Asset insert should throw AssetsServiceException');
    }

    @IsTest
    static void shouldThrow_WhenUpdateAssetsElevatedFailsValidation() {
        Asset assetRow = [SELECT Id, Name FROM Asset LIMIT 1];
        assetRow.Id = null;

        Boolean threw = false;
        try {
            AssetsService.updateAssetsElevated(new List<Asset>{ assetRow });
        } catch (AssetsService.AssetsServiceException e) {
            threw = true;
            Assert.isTrue(
                String.isNotBlank(e.getMessage()),
                'Elevated update failure should surface a service message'
            );
        }
        Assert.isTrue(threw, 'Elevated update without Id should throw AssetsServiceException');
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static User buildTestUser() {
        adb_User builder = new adb_User();
        builder.persist();
        return (User) builder.record;
    }
}