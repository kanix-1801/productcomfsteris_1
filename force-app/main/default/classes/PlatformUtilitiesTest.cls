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
     * @description Verifies the cause message is preferred and null is handled.
     */
    @IsTest
    static void testResolveExceptionMessage() {
        // GIVEN
        DmlException cause = new DmlException('Cause message');
        DmlException withCause = new DmlException('Outer message', cause);
        DmlException withoutCause = new DmlException('Outer message');

        // WHEN
        Test.startTest();
        String causeMessage = PlatformUtilities.resolveExceptionMessage(withCause);
        String outerMessage = PlatformUtilities.resolveExceptionMessage(withoutCause);
        String nullMessage = PlatformUtilities.resolveExceptionMessage(null);
        Test.stopTest();

        // THEN
        Assert.areEqual('Cause message', causeMessage, 'Cause message is preferred');
        Assert.areEqual('Outer message', outerMessage, 'Own message is used without a cause');
        Assert.isNull(nullMessage, 'Null exception returns null');
    }

    /**
     * @description Verifies typed map and list values are returned only when the type matches.
     */
    @IsTest
    static void testGetMapValueAndGetListValue() {
        // GIVEN
        Map<String, Object> sourceMap = new Map<String, Object>{
            'child' => new Map<String, Object>{ 'key' => 'value' },
            'items' => new List<Object>{ 1, 2 },
            'text' => 'plain'
        };

        // WHEN
        Test.startTest();
        Map<String, Object> childMap = PlatformUtilities.getMapValue(sourceMap, 'child');
        Map<String, Object> wrongTypeMap = PlatformUtilities.getMapValue(sourceMap, 'text');
        Map<String, Object> missingMap = PlatformUtilities.getMapValue(null, 'child');
        List<Object> itemList = PlatformUtilities.getListValue(sourceMap, 'items');
        List<Object> wrongTypeList = PlatformUtilities.getListValue(sourceMap, 'text');
        List<Object> missingList = PlatformUtilities.getListValue(sourceMap, 'absent');
        Test.stopTest();

        // THEN
        Assert.areEqual('value', childMap.get('key'), 'Nested map is returned');
        Assert.isNull(wrongTypeMap, 'Non-map value returns null');
        Assert.isNull(missingMap, 'Null source returns null');
        Assert.areEqual(2, itemList.size(), 'List value is returned');
        Assert.isNull(wrongTypeList, 'Non-list value returns null');
        Assert.isNull(missingList, 'Missing key returns null');
    }

    /**
     * @description Verifies trimToNull and parseId handle blank and invalid values.
     */
    @IsTest
    static void testTrimToNullAndParseId() {
        // GIVEN
        Id userId = UserInfo.getUserId();

        // WHEN
        Test.startTest();
        String trimmedValue = PlatformUtilities.trimToNull('  value  ');
        String blankValue = PlatformUtilities.trimToNull('   ');
        String nullValue = PlatformUtilities.trimToNull(null);
        Id parsedId = PlatformUtilities.parseId(String.valueOf(userId));
        Id invalidId = PlatformUtilities.parseId('not-an-id');
        Id blankId = PlatformUtilities.parseId('');
        Test.stopTest();

        // THEN
        Assert.areEqual('value', trimmedValue, 'Value is trimmed');
        Assert.isNull(blankValue, 'Blank value is null');
        Assert.isNull(nullValue, 'Null stays null');
        Assert.areEqual(userId, parsedId, 'Valid Id is parsed');
        Assert.isNull(invalidId, 'Invalid Id is null');
        Assert.isNull(blankId, 'Blank Id is null');
    }

    /**
     * @description Verifies the status code and JSON body are written to the REST response.
     */
    @IsTest
    static void testWriteJson() {
        // GIVEN
        RestResponse response = new RestResponse();

        // WHEN
        Test.startTest();
        PlatformUtilities.writeJson(response, 201, new Map<String, Object>{ 'status' => 'ok' });
        Test.stopTest();

        // THEN
        Assert.areEqual(201, response.statusCode, 'Status code is set');
        Assert.areEqual('{"status":"ok"}', response.responseBody.toString(), 'Body is serialized to JSON');
    }

    /**
     * @description GW-5874 - Verifies phone numbers are reduced to 10 digits without the +1 country code.
     */
    @IsTest
    static void testNormalizePhone() {
        Test.startTest();
        String internationalPhone = PlatformUtilities.normalizePhone('+1 (555) 123-4567');
        String dottedPhone = PlatformUtilities.normalizePhone('555.123.4567');
        String plainPhone = PlatformUtilities.normalizePhone('5551234567');
        String noDigitPhone = PlatformUtilities.normalizePhone('+-()');
        Test.stopTest();

        Assert.areEqual('5551234567', internationalPhone, 'Strips +1 and formatting');
        Assert.areEqual('5551234567', dottedPhone, 'Strips dots');
        Assert.areEqual('5551234567', plainPhone, 'Leaves 10 digits unchanged');
        Assert.isNull(noDigitPhone, 'A value with no digits is null');
        Assert.isNull(PlatformUtilities.normalizePhone(null), 'Null stays null');
        Assert.isNull(PlatformUtilities.normalizePhone('   '), 'Blank is null');
    }

    /**
     * @description Verifies null-safe uppercase and null-to-empty helpers used by PrinterService.
     */
    @IsTest
    static void testToUpperCaseAndBlankToEmpty() {
        Test.startTest();
        String upper = PlatformUtilities.toUpperCase('monday');
        String blankUpper = PlatformUtilities.toUpperCase('   ');
        String nullUpper = PlatformUtilities.toUpperCase(null);
        String emptyFromNull = PlatformUtilities.blankToEmpty(null);
        String emptyFromValue = PlatformUtilities.blankToEmpty('kept');
        Test.stopTest();

        Assert.areEqual('MONDAY', upper, 'Value is uppercased');
        Assert.areEqual('   ', blankUpper, 'Blank value is unchanged');
        Assert.isNull(nullUpper, 'Null stays null');
        Assert.areEqual('', emptyFromNull, 'Null becomes empty string');
        Assert.areEqual('kept', emptyFromValue, 'Non-null value is unchanged');
    }

    @IsTest
    static void testParseIdList() {
        Account account = new Account(Name = 'PlatformUtilities ParseIdList');
        insert account;

        Test.startTest();
        List<Id> ids = PlatformUtilities.parseIdList(
            new List<Object>{ String.valueOf(account.Id), 'bad', null }
        );
        Test.stopTest();

        Assert.areEqual(1, ids.size());
        Assert.areEqual(account.Id, ids[0]);
    }

    @IsTest
    static void testToBooleanAndParsePositiveDecimal() {
        Test.startTest();
        Assert.isTrue(PlatformUtilities.toBoolean(true));
        Assert.isTrue(PlatformUtilities.toBoolean('Yes'));
        Assert.isFalse(PlatformUtilities.toBoolean('no'));
        Assert.areEqual(5, PlatformUtilities.parsePositiveDecimal(5, 1));
        Assert.areEqual(1, PlatformUtilities.parsePositiveDecimal(0, 1));
        Assert.areEqual(1, PlatformUtilities.parsePositiveDecimal(null, 1));
        Test.stopTest();
    }
}