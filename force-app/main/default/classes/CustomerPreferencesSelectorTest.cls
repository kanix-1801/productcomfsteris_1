/**
 * @description Tests for CustomerPreferencesSelector (GW-2860).
 */
@IsTest
private class CustomerPreferencesSelectorTest {
    private static final String PRODUCT_LINE = 'Endocam';
    private static final String OTHER_PRODUCT_LINE = 'Instrument';
    private static final String PREFERENCE_TYPE_PHOTOS_REQUIRED = 'Photos required';

    @TestSetup
    static void setupData() {
        adb_Account accountBuilder = new adb_Account()
            .name('Customer Preference Selector Account')
            .systemId('LEG-CP-SEL-1001')
            .sourceSystemId('TEST-ORACLE-CP-SEL-001')
            .orgIds('82');

        new adb_CustomerPreference()
            .account(accountBuilder)
            .setRecordType('IMSCustomerPreference')
            .preferenceType(PREFERENCE_TYPE_PHOTOS_REQUIRED)
            .productLine(null)
            .startDate(Date.today().addDays(-1))
            .endDate(Date.today().addDays(30));

        new adb_CustomerPreference()
            .account(accountBuilder)
            .setRecordType('IMSCustomerPreference')
            .preferenceType(PREFERENCE_TYPE_PHOTOS_REQUIRED)
            .productLine(PRODUCT_LINE)
            .startDate(Date.today().addDays(-1))
            .endDate(Date.today().addDays(30));

        new adb_CustomerPreference()
            .account(accountBuilder)
            .setRecordType('IMSCustomerPreference')
            .preferenceType(PREFERENCE_TYPE_PHOTOS_REQUIRED)
            .productLine(PRODUCT_LINE)
            .startDate(Date.today().addDays(-30))
            .endDate(Date.today().addDays(-1));

        new adb_CustomerPreference()
            .account(accountBuilder)
            .setRecordType('IMSCustomerPreference')
            .preferenceType(PREFERENCE_TYPE_PHOTOS_REQUIRED)
            .productLine(OTHER_PRODUCT_LINE)
            .startDate(Date.today().addDays(-1))
            .endDate(Date.today().addDays(30))
            .persist();
    }

    @IsTest
    static void testSelectActiveImsByAccountAndProductLineMatchesBlankAndExact() {
        // Setup
        Account account = [SELECT Id FROM Account LIMIT 1];
        Id imsRtId = getImsRecordTypeId();

        // Given / When
        Test.startTest();
        List<CustomerPreference__c> results =
            CustomerPreferencesSelector.selectActiveImsByAccountAndProductLine(
                account.Id,
                imsRtId,
                PRODUCT_LINE,
                Date.today()
            );
        Test.stopTest();

        // Then — blank product line + Endocam; not expired; not Instrument-only
        Assert.areEqual(2, results.size(), 'Should return blank + matching product line prefs');
        Set<String> productLines = new Set<String>();
        for (CustomerPreference__c preference : results) {
            productLines.add(preference.ProductLine__c);
        }
        Assert.isTrue(productLines.contains(null), 'Blank product-line preference should match');
        Assert.isTrue(productLines.contains(PRODUCT_LINE), 'Exact product-line preference should match');
    }

    @IsTest
    static void testSelectActiveImsByAccountAndProductLineBlankProductLineOnly() {
        // Setup — no Asset Product Line (parent WO case): only blank ProductLine__c prefs
        Account account = [SELECT Id FROM Account LIMIT 1];
        Id imsRtId = getImsRecordTypeId();

        // Given / When
        Test.startTest();
        List<CustomerPreference__c> results =
            CustomerPreferencesSelector.selectActiveImsByAccountAndProductLine(
                account.Id,
                imsRtId,
                null,
                Date.today()
            );
        Test.stopTest();

        // Then
        Assert.areEqual(1, results.size(), 'Blank product line should return only null ProductLine prefs');
        Assert.isNull(results[0].ProductLine__c);
    }

    @IsTest
    static void testSelectActiveImsByAccountAndProductLineNullGuards() {
        // When / Then
        Assert.areEqual(
            0,
            CustomerPreferencesSelector.selectActiveImsByAccountAndProductLine(
                    null,
                    getImsRecordTypeId(),
                    PRODUCT_LINE,
                    Date.today()
                )
                .size(),
            'Null account should return empty'
        );
        Assert.areEqual(
            0,
            CustomerPreferencesSelector.selectActiveImsByAccountAndProductLine(
                    [SELECT Id FROM Account LIMIT 1].Id,
                    null,
                    PRODUCT_LINE,
                    Date.today()
                )
                .size(),
            'Null record type should return empty'
        );
    }

    @IsTest
    static void testSelectActiveImsByAccountProductLineAndTypePhotosRequired() {
        // Setup
        Account account = [SELECT Id FROM Account LIMIT 1];
        Id imsRtId = getImsRecordTypeId();

        // Given / When
        Test.startTest();
        List<CustomerPreference__c> results =
            CustomerPreferencesSelector.selectActiveImsByAccountProductLineAndType(
                account.Id,
                imsRtId,
                PRODUCT_LINE,
                PREFERENCE_TYPE_PHOTOS_REQUIRED,
                Date.today()
            );
        Test.stopTest();

        // Then
        Assert.areEqual(1, results.size(), 'LIMIT 1 should return one Photos required match');
    }

    @IsTest
    static void testSelectActiveImsByAccountProductLineAndTypeBlankType() {
        Account account = [SELECT Id FROM Account LIMIT 1];

        Assert.areEqual(
            0,
            CustomerPreferencesSelector.selectActiveImsByAccountProductLineAndType(
                    account.Id,
                    getImsRecordTypeId(),
                    PRODUCT_LINE,
                    null,
                    Date.today()
                )
                .size(),
            'Blank preference type should return empty'
        );
    }

    @IsTest
    static void testSelectActiveImsByExactProductLineAndType() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Id imsRtId = getImsRecordTypeId();

        Test.startTest();
        List<CustomerPreference__c> exactMatches =
            CustomerPreferencesSelector.selectActiveImsByExactProductLineAndType(
                account.Id,
                imsRtId,
                PRODUCT_LINE,
                PREFERENCE_TYPE_PHOTOS_REQUIRED,
                Date.today()
            );
        List<CustomerPreference__c> blankProductLineArg =
            CustomerPreferencesSelector.selectActiveImsByExactProductLineAndType(
                account.Id,
                imsRtId,
                null,
                PREFERENCE_TYPE_PHOTOS_REQUIRED,
                Date.today()
            );
        Test.stopTest();

        Assert.areEqual(1, exactMatches.size(), 'Exact Product Line should match one preference');
        Assert.areEqual(
            0,
            blankProductLineArg.size(),
            'Blank Product Line argument should return empty for exact selector'
        );
    }

    @IsTest
    static void testSelectActiveImsByAccountAndTypeCarrierServiceLevel() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Id imsRtId = getImsRecordTypeId();
        insert new CustomerPreference__c(
            Name = 'Carrier Service Level Pref',
            RecordTypeId = imsRtId,
            Account__c = account.Id,
            PreferenceType__c = 'Carrier Service level',
            PreferenceValue__c = 'FEDEX PRIORITY OVERNIGHT',
            StartDate__c = Date.today().addDays(-1),
            EndDate__c = Date.today().addDays(30)
        );

        Test.startTest();
        List<CustomerPreference__c> results =
            CustomerPreferencesSelector.selectActiveImsByAccountAndType(
                account.Id,
                imsRtId,
                'Carrier Service level',
                Date.today()
            );
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.areEqual('FEDEX PRIORITY OVERNIGHT', results[0].PreferenceValue__c);
    }

    private static Id getImsRecordTypeId() {
        Schema.RecordTypeInfo imsInfo = Schema.SObjectType.CustomerPreference__c
            .getRecordTypeInfosByDeveloperName()
            .get('IMSCustomerPreference');
        return imsInfo == null ? null : imsInfo.getRecordTypeId();
    }
}