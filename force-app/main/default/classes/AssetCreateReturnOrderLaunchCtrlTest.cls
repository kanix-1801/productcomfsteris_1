/**
 * @description Test class for AssetCreateReturnOrderLaunchCtrl.
 */
@isTest
private class AssetCreateReturnOrderLaunchCtrlTest {

    @TestSetup
    static void setupTestData() {
        Account testAccount = new Account(
            Name = 'Launch Test Account',
            SystemID__c = 'LEG-LAUNCH',
            SourceSystemID__c = 'TEST-ORACLE-LAUNCH'
        );
        insert testAccount;

        insert new Asset(
            Name = 'Launch Test Asset',
            AccountId = testAccount.Id,
            SerialNumber = 'SN-LAUNCH'
        );
    }

    @isTest
    static void redirect_withNoSelection_returnsNullAndAddsMessage() {
        List<Asset> assets = [SELECT Id FROM Asset];
        ApexPages.StandardSetController controller = new ApexPages.StandardSetController(assets);
        controller.setSelected(new List<Asset>());

        Test.startTest();
        AssetCreateReturnOrderLaunchCtrl launchCtrl = new AssetCreateReturnOrderLaunchCtrl(controller);
        PageReference result = launchCtrl.redirect();
        Test.stopTest();

        System.assertEquals(null, result, 'Expected no redirect when nothing is selected.');
        System.assertEquals(1, ApexPages.getMessages().size(), 'Expected a validation message.');
        System.assert(
            ApexPages.getMessages()[0].getSummary().contains('Select at least one Asset'),
            'Expected the no-selection error message.'
        );
    }

    @isTest
    static void redirect_withSelectedAssets_redirectsToLwcWithRecordIds() {
        Asset asset = [SELECT Id FROM Asset LIMIT 1];
        ApexPages.StandardSetController controller = new ApexPages.StandardSetController([SELECT Id FROM Asset]);
        controller.setSelected(new List<Asset>{ asset });

        Test.startTest();
        AssetCreateReturnOrderLaunchCtrl launchCtrl = new AssetCreateReturnOrderLaunchCtrl(controller);
        PageReference result = launchCtrl.redirect();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Expected a redirect when assets are selected.');
        System.assertEquals(true, result.getRedirect(), 'Expected redirect flag to be set.');
        System.assert(
            result.getUrl().contains('/lightning/cmp/c__createReturnOrder'),
            'Expected LWC component URL.'
        );
        System.assert(
            result.getUrl().contains('c__recordIds=' + asset.Id),
            'Expected selected asset Id in URL state.'
        );
    }

    @isTest
    static void redirect_withMultipleSelectedAssets_includesAllIdsInUrl() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Asset secondAsset = new Asset(
            Name = 'Launch Test Asset 2',
            AccountId = account.Id,
            SerialNumber = 'SN-LAUNCH-2'
        );
        insert secondAsset;

        List<Asset> assets = [SELECT Id FROM Asset ORDER BY SerialNumber ASC];
        ApexPages.StandardSetController controller = new ApexPages.StandardSetController(assets);
        controller.setSelected(assets);

        Test.startTest();
        AssetCreateReturnOrderLaunchCtrl launchCtrl = new AssetCreateReturnOrderLaunchCtrl(controller);
        PageReference result = launchCtrl.redirect();
        Test.stopTest();

        System.assertNotEquals(null, result);
        for (Asset asset : assets) {
            System.assert(
                result.getUrl().contains((String) asset.Id),
                'Expected each selected asset Id in URL: ' + asset.Id
            );
        }
    }
}