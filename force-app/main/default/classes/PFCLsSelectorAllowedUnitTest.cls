/**
 * @description Tests for PFCLsSelector used by Allowed Unit evaluation.
 * @see PFCLsSelector
 */
@IsTest
private class PFCLsSelectorAllowedUnitTest {
    /**
     * @description Verifies null/empty PFCL value sets return an empty list.
     */
    @IsTest
    static void selectByAssetPfclValues_nullOrEmpty_returnsEmpty() {
        Test.startTest();
        List<PFCL__c> nullResult = PFCLsSelector.selectByAssetPfclValues(null);
        List<PFCL__c> emptyResult = PFCLsSelector.selectByAssetPfclValues(new Set<String>());
        Test.stopTest();

        System.assertEquals(0, nullResult.size());
        System.assertEquals(0, emptyResult.size());
    }

    /**
     * @description Verifies PFCL records are matched by Name or PFCL number.
     */
    @IsTest
    static void selectByAssetPfclValues_matchesNameOrPfclNumber() {
        Id esRtId = Schema.SObjectType.PFCL__c.getRecordTypeInfosByDeveloperName()
            .get('ESPFCL')
            .getRecordTypeId();

        String unique = String.valueOf(Crypto.getRandomInteger());
        PFCL__c pfcl = new PFCL__c(
            Name = 'AU-PFCL-' + unique,
            PFCL__c = 'AU-NUM-' + unique,
            RecordTypeId = esRtId
        );
        insert pfcl;

        Test.startTest();
        List<PFCL__c> byName =
            PFCLsSelector.selectByAssetPfclValues(new Set<String>{ pfcl.Name });
        List<PFCL__c> byNumber =
            PFCLsSelector.selectByAssetPfclValues(new Set<String>{ pfcl.PFCL__c });
        List<PFCL__c> noMatch =
            PFCLsSelector.selectByAssetPfclValues(new Set<String>{ 'NO-MATCH-' + unique });
        Test.stopTest();

        System.assertEquals(1, byName.size());
        System.assertEquals(pfcl.Id, byName[0].Id);
        System.assertEquals(1, byNumber.size());
        System.assertEquals(pfcl.Id, byNumber[0].Id);
        System.assertEquals(0, noMatch.size());
    }

    /**
     * @description Covers Dana baseline selector methods so deploy coverage stays above 75%.
     */
    @IsTest
    static void selectByIdAndName_guardsAndMatch() {
        Id esRtId = Schema.SObjectType.PFCL__c.getRecordTypeInfosByDeveloperName()
            .get('ESPFCL')
            .getRecordTypeId();
        String unique = String.valueOf(Crypto.getRandomInteger());
        PFCL__c pfcl = new PFCL__c(
            Name = 'AU-PFCL-BASE-' + unique,
            PFCL__c = 'AU-BASE-NUM-' + unique,
            RecordTypeId = esRtId
        );
        insert pfcl;

        Test.startTest();
        List<PFCL__c> emptyId = PFCLsSelector.selectById(null);
        List<PFCL__c> emptyName = PFCLsSelector.selectByName(new Set<String>());
        List<PFCL__c> byId = PFCLsSelector.selectById(new Set<Id>{ pfcl.Id });
        List<PFCL__c> byName = PFCLsSelector.selectByName(new Set<String>{ pfcl.Name });
        Test.stopTest();

        System.assertEquals(0, emptyId.size());
        System.assertEquals(0, emptyName.size());
        System.assertEquals(1, byId.size());
        System.assertEquals(1, byName.size());
    }
}