/**
 * @description Test coverage for AssetsSelector.
 */
@IsTest
private class AssetsSelectorTest {

    @TestSetup
    static void setup() {
        adb_Account acc1Builder = new adb_Account()
            .name('Asset Test Account 1')
            .sourceSystemId('0826487164');
        adb_Account acc2Builder = new adb_Account()
            .name('Asset Test Account 2')
            .sourceSystemId('0-974654514');

        new adb_Asset().name('Zeta Pump').serialNumber('SN-001').account(acc1Builder);
        new adb_Asset().name('Alpha Pump').serialNumber('SN-002').account(acc1Builder);
        new adb_Asset().name('Beta Valve').serialNumber('SN-003').account(acc2Builder);

        adb_DomainBuilder.save();
    }

    private static Id accountId(String name) {
        return [SELECT Id FROM Account WHERE Name = :name LIMIT 1].Id;
    }

    // ---- selectById ----------------------------------------------------------------------

    @IsTest
    static void selectById_nullOrEmptySet_returnsEmptyList() {
        Assert.areEqual(0, AssetsSelector.selectById(null).size());
        Assert.areEqual(0, AssetsSelector.selectById(new Set<Id>()).size());
    }

    @IsTest
    static void selectById_validIds_returnsMatchingAssets() {
        Asset a = [SELECT Id FROM Asset WHERE SerialNumber = 'SN-001' LIMIT 1];

        Test.startTest();
        List<Asset> results = AssetsSelector.selectById(new Set<Id>{ a.Id });
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.areEqual('Zeta Pump', results[0].Name);
        Assert.areEqual('SN-001', results[0].SerialNumber);
    }

    // ---- selectByAccountId -----------------------------------------------------------------

    @IsTest
    static void selectByAccountId_nullOrEmptySet_returnsEmptyList() {
        Assert.areEqual(0, AssetsSelector.selectByAccountId(null).size());
        Assert.areEqual(0, AssetsSelector.selectByAccountId(new Set<Id>()).size());
    }

    @IsTest
    static void selectByAccountId_validIds_returnsAssetsOrderedByNameAscending() {
        Id acc1Id = accountId('Asset Test Account 1');

        Test.startTest();
        List<Asset> results = AssetsSelector.selectByAccountId(new Set<Id>{ acc1Id });
        Test.stopTest();

        Assert.areEqual(2, results.size());
        Assert.areEqual('Alpha Pump', results[0].Name);
        Assert.areEqual('Zeta Pump', results[1].Name);
    }

    @IsTest
    static void selectByAccountId_multipleAccountIds_returnsAssetsForAllAccounts() {
        Id acc1Id = accountId('Asset Test Account 1');
        Id acc2Id = accountId('Asset Test Account 2');

        Test.startTest();
        List<Asset> results = AssetsSelector.selectByAccountId(new Set<Id>{ acc1Id, acc2Id });
        Test.stopTest();

        Assert.areEqual(3, results.size());
    }

    @IsTest
    static void selectByAccountIdWithLimit_nullOrEmptySet_returnsEmptyList() {
        Assert.areEqual(0, AssetsSelector.selectByAccountId(null, 10, 'Name').size());
        Assert.areEqual(0, AssetsSelector.selectByAccountId(new Set<Id>(), 10, 'Name').size());
    }

    @IsTest
    static void selectByAccountIdWithLimit_orderAndLimit_returnsFirstAssetOnly() {
        Id acc1Id = accountId('Asset Test Account 1');

        Test.startTest();
        List<Asset> limited = AssetsSelector.selectByAccountId(new Set<Id>{ acc1Id }, 1, 'Name DESC');
        List<Asset> unlimited = AssetsSelector.selectByAccountId(new Set<Id>{ acc1Id }, null, null);
        Test.stopTest();

        Assert.areEqual(1, limited.size());
        Assert.areEqual('Zeta Pump', limited[0].Name);
        Assert.areEqual(2, unlimited.size());
    }

    // ---- selectByAccountIdAndSearchText ----------------------------------------------------

    @IsTest
    static void selectByAccountIdAndSearchText_blankInput_returnsEmptyList() {
        Id acc1Id = accountId('Asset Test Account 1');
        Assert.areEqual(0, AssetsSelector.selectByAccountIdAndSearchText(null, '%Pump%', 10).size());
        Assert.areEqual(0, AssetsSelector.selectByAccountIdAndSearchText(acc1Id, null, 10).size());
        Assert.areEqual(0, AssetsSelector.selectByAccountIdAndSearchText(acc1Id, ' ', 10).size());
    }

    @IsTest
    static void selectByAccountIdAndSearchText_matchingTerm_returnsAccountAssets() {
        Id acc1Id = accountId('Asset Test Account 1');

        Test.startTest();
        List<Asset> results = AssetsSelector.selectByAccountIdAndSearchText(acc1Id, '%SN-00%', 10);
        Test.stopTest();

        Assert.areEqual(2, results.size());
        Assert.areEqual('Alpha Pump', results[0].Name);
    }

    // ---- selectBySerialNumber --------------------------------------------------------------

    @IsTest
    static void selectBySerialNumber_nullOrEmptySet_returnsEmptyList() {
        Assert.areEqual(0, AssetsSelector.selectBySerialNumber(null).size());
        Assert.areEqual(0, AssetsSelector.selectBySerialNumber(new Set<String>()).size());
    }

    @IsTest
    static void selectBySerialNumber_validSerialNumbers_returnsMatchingAssets() {
        Test.startTest();
        List<Asset> results = AssetsSelector.selectBySerialNumber(new Set<String>{ 'SN-002', 'SN-003' });
        Test.stopTest();

        Assert.areEqual(2, results.size());
        Set<String> serials = new Set<String>();
        for (Asset a : results) {
            serials.add(a.SerialNumber);
        }
        Assert.isTrue(serials.contains('SN-002'));
        Assert.isTrue(serials.contains('SN-003'));
    }

    @IsTest
    static void selectBySerialNumber_unknownSerialNumber_returnsEmptyList() {
        Test.startTest();
        List<Asset> results = AssetsSelector.selectBySerialNumber(new Set<String>{ 'DOES-NOT-EXIST' });
        Test.stopTest();

        Assert.isTrue(results.isEmpty());
    }

    // ---- Inherited SoqlQueryBuilder usage ---------------------------------------------------

    @IsTest
    static void builderUsage_selectFieldsWhereEquals_returnsMatchingAssets() {
        Id acc1Id = accountId('Asset Test Account 1');

        Test.startTest();
        List<Asset> results = (List<Asset>) new AssetsSelector()
            .selectFields(new List<String>{ 'Id', 'Name', 'SerialNumber' })
            .whereEquals('AccountId', acc1Id)
            .orderBy('Name')
            .execute();
        Test.stopTest();

        Assert.areEqual(2, results.size());
        Assert.areEqual('Alpha Pump', results[0].Name);
    }

    @IsTest
    static void builderUsage_limitTo_capsResultCount() {
        Id acc1Id = accountId('Asset Test Account 1');

        Test.startTest();
        List<Asset> results = (List<Asset>) new AssetsSelector()
            .selectField('Id')
            .whereEquals('AccountId', acc1Id)
            .limitTo(1)
            .execute();
        Test.stopTest();

        Assert.areEqual(1, results.size());
    }
}