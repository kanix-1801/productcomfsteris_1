/**
 * @author Uptima
 * @date 2026-09-19
 * @group Utilities
 * @description Tests for PlatformUtilities.
 */
@IsTest
private class PlatformUtilitiesTest {
    /**
     * @description Verifies valid 15/18-char Ids pass and blank/invalid values fail.
     */
    @IsTest
    static void testIsSalesforceIdWhenValidAndInvalidValues() {
        Account account = new Account(
            Name = 'PlatformUtilities Test Account',
            SystemID__c = 'LEG-SID-1001',
            SourceSystemID__c = 'TEST-ORACLE-SID-001',
            OrgIDs__c = '82'
        );
        insert account;

        Test.startTest();
        Assert.areEqual(true, PlatformUtilities.isSalesforceId(account.Id), '18-char Id should be valid');
        Assert.areEqual(
            true,
            PlatformUtilities.isSalesforceId(String.valueOf(account.Id).substring(0, 15)),
            '15-char Id should be valid'
        );
        Assert.areEqual(false, PlatformUtilities.isSalesforceId(null), 'null should be invalid');
        Assert.areEqual(false, PlatformUtilities.isSalesforceId(''), 'blank should be invalid');
        Assert.areEqual(false, PlatformUtilities.isSalesforceId('WO-12345'), 'WO number should be invalid');
        Assert.areEqual(
            false,
            PlatformUtilities.isSalesforceId('not-an-id-value'),
            'random string should be invalid'
        );
        Assert.areEqual(
            false,
            PlatformUtilities.isSalesforceId('000000000000000'),
            '15-char non-Id should be invalid'
        );
        Test.stopTest();
    }

    /**
     * @description Verifies Aura exception message is set for the client.
     */
    @IsTest
    static void testBuildAuraExceptionSetsMessage() {
        Test.startTest();
        AuraHandledException ex = PlatformUtilities.buildAuraException('Test aura message');
        Test.stopTest();

        Assert.areEqual('Test aura message', ex.getMessage());
    }

    /**
     * @description Verifies Yes/No option helper.
     */
    @IsTest
    static void testBuildYesNoOptions() {
        Test.startTest();
        List<PlatformUtilities.PicklistOption> options = PlatformUtilities.buildYesNoOptions();
        Test.stopTest();

        Assert.areEqual(2, options.size());
        Assert.areEqual('Yes', options[0].value);
        Assert.areEqual('No', options[1].value);
    }

    /**
     * @description Verifies active picklist options are returned for a field.
     */
    @IsTest
    static void testGetActivePicklistOptions() {
        Test.startTest();
        List<PlatformUtilities.PicklistOption> options =
            PlatformUtilities.getActivePicklistOptions(Account.Type);
        Test.stopTest();

        Assert.isTrue(options != null, 'Expected options list');
    }

    /**
     * @description GW-4585 - Verifies firstNonBlank helper used by pricing framework.
     */
    @IsTest
    static void testFirstNonBlank() {
        Test.startTest();
        Assert.areEqual('first', PlatformUtilities.firstNonBlank('first', 'second'));
        Assert.areEqual('second', PlatformUtilities.firstNonBlank('', 'second'));
        Assert.areEqual('second', PlatformUtilities.firstNonBlank(null, 'second'));
        Test.stopTest();
    }

    /**
     * @description GW-4637 - Verifies toUpperCase / blankToEmpty helpers used by PrinterService.
     */
    @IsTest
    static void testToUpperCaseAndBlankToEmpty() {
        Test.startTest();
        Assert.areEqual('', PlatformUtilities.toUpperCase(null));
        Assert.areEqual('', PlatformUtilities.toUpperCase(''));
        Assert.areEqual('', PlatformUtilities.toUpperCase('   '));
        Assert.areEqual('MON', PlatformUtilities.toUpperCase('mon'));
        Assert.areEqual('', PlatformUtilities.blankToEmpty(null));
        Assert.areEqual('', PlatformUtilities.blankToEmpty(''));
        Assert.areEqual('', PlatformUtilities.blankToEmpty('   '));
        Assert.areEqual('kept', PlatformUtilities.blankToEmpty('kept'));
        Test.stopTest();
    }

    @IsTest
    static void testResolveExceptionMessage() {
        Test.startTest();
        Assert.areEqual(null, PlatformUtilities.resolveExceptionMessage(null));
        Assert.areEqual(
            'root',
            PlatformUtilities.resolveExceptionMessage(new DmlException('root'))
        );
        Exception withCause = new TypeException('wrapper');
        withCause.initCause(new DmlException('cause message'));
        Assert.areEqual('cause message', PlatformUtilities.resolveExceptionMessage(withCause));
        Test.stopTest();
    }

    @IsTest
    static void testGetActivePicklistOptionsNullField() {
        Test.startTest();
        Assert.areEqual(0, PlatformUtilities.getActivePicklistOptions(null).size());
        Test.stopTest();
    }

    @IsTest
    static void testMapAndListValueHelpers() {
        Map<String, Object> source = new Map<String, Object>{
            'mapKey' => new Map<String, Object>{ 'inner' => 'value' },
            'listKey' => new List<Object>{ 'a', 'b' },
            'textKey' => 'plain'
        };

        Test.startTest();
        Assert.areEqual(null, PlatformUtilities.getMapValue(null, 'mapKey'));
        Assert.areEqual(null, PlatformUtilities.getMapValue(source, 'missing'));
        Assert.areEqual(null, PlatformUtilities.getMapValue(source, 'textKey'));
        Assert.areEqual('value', PlatformUtilities.getMapValue(source, 'mapKey').get('inner'));
        Assert.areEqual(null, PlatformUtilities.getListValue(null, 'listKey'));
        Assert.areEqual(null, PlatformUtilities.getListValue(source, 'missing'));
        Assert.areEqual(null, PlatformUtilities.getListValue(source, 'textKey'));
        Assert.areEqual(2, PlatformUtilities.getListValue(source, 'listKey').size());
        Test.stopTest();
    }

    @IsTest
    static void testTrimToNullAndParseId() {
        Account account = new Account(
            Name = 'PlatformUtilities Parse Id',
            SourceSystemID__c = 'PU-PARSE-1',
            OrgIDs__c = '82'
        );
        insert account;

        Test.startTest();
        Assert.areEqual(null, PlatformUtilities.trimToNull(null));
        Assert.areEqual(null, PlatformUtilities.trimToNull('   '));
        Assert.areEqual('abc', PlatformUtilities.trimToNull('  abc '));
        Assert.areEqual(null, PlatformUtilities.parseId(null));
        Assert.areEqual(null, PlatformUtilities.parseId('not-an-id'));
        Assert.areEqual(account.Id, PlatformUtilities.parseId(String.valueOf(account.Id)));
        Test.stopTest();
    }

    @IsTest
    static void testWriteJson() {
        RestResponse response = new RestResponse();

        Test.startTest();
        PlatformUtilities.writeJson(
            response,
            200,
            new Map<String, Object>{ 'ok' => true }
        );
        Test.stopTest();

        Assert.areEqual(200, response.statusCode);
        Assert.areEqual('{"ok":true}', response.responseBody.toString());
    }
}