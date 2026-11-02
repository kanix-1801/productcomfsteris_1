/**
 * @description Tests for stamping Asset inspection fields from a Product Serviced save.
 * @see WoDebriefAssetInspection
 */
@IsTest
private class WoDebriefAssetInspectionTest {

    /**
     * @description A saved inspection outcome and today's date are written to the Asset.
     */
    @IsTest
    static void stampAssetInspections_setsOutcomeAndDate() {
        Asset asset = createAsset();
        WoDebriefAssetInspection.InspectionStamp stamp = new WoDebriefAssetInspection.InspectionStamp();
        stamp.assetId = asset.Id;
        stamp.inspectionOutcome = 'Passed';

        Test.startTest();
        WoDebriefAssetInspection.stampAssetInspections(
            new List<WoDebriefAssetInspection.InspectionStamp>{ stamp }
        );
        Test.stopTest();

        Asset updated = [
            SELECT LastInspectionOutcome__c, LastInspectionDate__c, LastServicedDate__c
            FROM Asset
            WHERE Id = :asset.Id
        ];
        System.assertEquals('Passed', updated.LastInspectionOutcome__c);
        System.assertEquals(Date.today(), updated.LastInspectionDate__c);
        System.assertEquals(null, updated.LastServicedDate__c);
    }

    /**
     * @description Completing a Product Serviced line sets Last Serviced Date without clearing it on a later inspection-only save.
     */
    @IsTest
    static void stampAssetInspections_completedLine_setsLastServicedDate() {
        Asset asset = createAsset();
        asset.LastServicedDate__c = Date.today().addDays(-10);
        update asset;

        WoDebriefAssetInspection.InspectionStamp completed = new WoDebriefAssetInspection.InspectionStamp();
        completed.assetId = asset.Id;
        completed.inspectionOutcome = 'Passed';
        completed.markServiced = true;

        Test.startTest();
        WoDebriefAssetInspection.stampAssetInspections(
            new List<WoDebriefAssetInspection.InspectionStamp>{ completed }
        );
        Test.stopTest();

        Asset updated = [
            SELECT LastServicedDate__c
            FROM Asset
            WHERE Id = :asset.Id
        ];
        System.assertEquals(Date.today(), updated.LastServicedDate__c);
    }

    /**
     * @description A blank outcome does not clear an existing inspection.
     */
    @IsTest
    static void stampAssetInspections_blankOutcome_leavesAsset() {
        Asset asset = createAsset();
        asset.LastInspectionOutcome__c = 'Do Not Use';
        asset.LastInspectionDate__c = Date.today().addDays(-3);
        update asset;

        WoDebriefAssetInspection.InspectionStamp stamp = new WoDebriefAssetInspection.InspectionStamp();
        stamp.assetId = asset.Id;
        stamp.inspectionOutcome = '   ';

        Test.startTest();
        WoDebriefAssetInspection.stampAssetInspections(
            new List<WoDebriefAssetInspection.InspectionStamp>{ stamp }
        );
        Test.stopTest();

        Asset unchanged = [
            SELECT LastInspectionOutcome__c, LastInspectionDate__c
            FROM Asset
            WHERE Id = :asset.Id
        ];
        System.assertEquals('Do Not Use', unchanged.LastInspectionOutcome__c);
        System.assertEquals(Date.today().addDays(-3), unchanged.LastInspectionDate__c);
    }

    /**
     * @description Creates an Account and Asset the running user can read.
     * @return Inserted Asset
     */
    private static Asset createAsset() {
        String token = String.valueOf(Crypto.getRandomInteger());
        Account account = new Account(
            Name = 'Inspection Stamp Account ' + token,
            SourceSystemID__c = 'ORACLE-INSP-' + token
        );
        insert account;
        Asset asset = new Asset(
            Name = 'Inspection Stamp Asset ' + token,
            AccountId = account.Id,
            SerialNumber = 'SN-INSP-' + token
        );
        insert asset;
        return asset;
    }
}