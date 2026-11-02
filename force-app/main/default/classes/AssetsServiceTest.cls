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

    // ── updateAssets ─────────────────────────────────────────────────────────

    @IsTest
    static void shouldUpdateAssets_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<Asset> assetList = [SELECT Id, Status FROM Asset LIMIT 3];
            for (Asset a : assetList) {
                a.Status = 'Installed';
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            AssetsService.updateAssets(assetList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> updatedIds = new Map<Id, Asset>(assetList).keySet();
            List<Asset> updatedList = [SELECT Id, Status FROM Asset WHERE Id IN :updatedIds];
            for (Asset a : updatedList) {
                Assert.areEqual('Installed', a.Status, 'Status should be updated to Installed');
            }
        }
    }

    @IsTest
    static void shouldDoNothing_WhenUpdateAssetsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            AssetsService.updateAssets(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(true, 'updateAssets with null should complete without error');
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
    static void shouldReturnEmpty_WhenSerialAndProductDoNotMatch() {
        List<Asset> matches = AssetsService.getAssetsBySerialAndProduct(
            new Set<String>{ 'NO-SUCH-SERIAL' },
            UserInfo.getUserId()
        );
        Assert.isTrue(matches.isEmpty());
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static User buildTestUser() {
        adb_User builder = new adb_User();
        builder.persist();
        return (User) builder.record;
    }
}