/**
 * @author Uptima
 * @date 2026-08-15
 * @group Utilities
 * @description Tests for SObjectIdUtil (GW-2891).
 */
@IsTest
private class SObjectIdUtilTest {
    /**
     * @description GW-2891 - Verifies valid 15/18-char Ids pass and blank/invalid values fail.
     */
    @IsTest
    static void testIsSalesforceId_WhenValidAndInvalidValues() {
        /********************************************
         * SETUP
         ********************************************/
        Account account = new Account(
            Name = 'SObjectIdUtil Test Account',
            SystemID__c = 'LEG-SID-1001',
            SourceSystemID__c = 'TEST-ORACLE-SID-001',
            OrgIDs__c = '82'
        );
        insert account;

        /********************************************
         * WHEN / THEN
         ********************************************/
        Test.startTest();
        Assert.areEqual(true, SObjectIdUtil.isSalesforceId(account.Id), '18-char Id should be valid');
        Assert.areEqual(
            true,
            SObjectIdUtil.isSalesforceId(String.valueOf(account.Id).substring(0, 15)),
            '15-char Id should be valid'
        );
        Assert.areEqual(false, SObjectIdUtil.isSalesforceId(null), 'null should be invalid');
        Assert.areEqual(false, SObjectIdUtil.isSalesforceId(''), 'blank should be invalid');
        Assert.areEqual(false, SObjectIdUtil.isSalesforceId('WO-12345'), 'WO number should be invalid');
        Assert.areEqual(
            false,
            SObjectIdUtil.isSalesforceId('not-an-id-value'),
            'random string should be invalid'
        );
        Assert.areEqual(
            false,
            SObjectIdUtil.isSalesforceId('000000000000000'),
            '15-char non-Id should be invalid'
        );
        Test.stopTest();
    }
}