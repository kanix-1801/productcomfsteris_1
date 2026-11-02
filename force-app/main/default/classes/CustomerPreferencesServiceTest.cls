/**
 * @description Tests for CustomerPreferencesService (GW-2860).
 */
@IsTest
private class CustomerPreferencesServiceTest {
    private static final String PRODUCT_LINE = 'Endocam';

    private class SelectorException extends Exception {
    }

    private class ThrowingSelector
        implements CustomerPreferencesService.ICustomerPreferencesSelector {
        public List<CustomerPreference__c> selectActiveImsByAccountAndProductLine(
            Id accountId,
            Id recordTypeId,
            String productLine,
            Date asOfDate
        ) {
            throw new SelectorException('active IMS selector failed');
        }

        public List<CustomerPreference__c> selectActiveImsByAccountProductLineAndType(
            Id accountId,
            Id recordTypeId,
            String productLine,
            String preferenceType,
            Date asOfDate
        ) {
            throw new SelectorException('photos required selector failed');
        }

        public List<CustomerPreference__c> selectActiveImsByExactProductLineAndType(
            Id accountId,
            Id recordTypeId,
            String productLine,
            String preferenceType,
            Date asOfDate
        ) {
            throw new SelectorException('exact photos required selector failed');
        }

        public List<CustomerPreference__c> selectActiveImsByAccountAndType(
            Id accountId,
            Id recordTypeId,
            String preferenceType,
            Date asOfDate
        ) {
            throw new SelectorException('carrier service level selector failed');
        }
    }

    @TestSetup
    static void setupData() {
        adb_Account accountBuilder = new adb_Account()
            .name('Customer Preference Service Account')
            .systemId('LEG-CP-SVC-1001')
            .sourceSystemId('TEST-ORACLE-CP-SVC-001')
            .orgIds('82');

        new adb_CustomerPreference()
            .account(accountBuilder)
            .setRecordType('IMSCustomerPreference')
            .preferenceType('Photos required')
            .productLine(null)
            .startDate(Date.today().addDays(-1))
            .endDate(Date.today().addDays(30))
            .persist();
    }

    @IsTest
    static void testGetActiveImsPreferencesReturnsActiveRows() {
        // Setup
        Account account = [SELECT Id FROM Account LIMIT 1];

        // Given / When
        Test.startTest();
        List<CustomerPreference__c> results =
            CustomerPreferencesService.getActiveImsPreferences(account.Id, PRODUCT_LINE);
        Test.stopTest();

        // Then
        Assert.areEqual(1, results.size(), 'Should return active IMS preference via Service');
        Assert.areEqual('Photos required', results[0].PreferenceType__c);
    }

    @IsTest
    static void testGetActiveImsPreferencesNullAccount() {
        // When / Then
        Assert.areEqual(
            0,
            CustomerPreferencesService.getActiveImsPreferences(null, PRODUCT_LINE).size(),
            'Null account should return empty list'
        );
    }

    @IsTest
    static void testIsPhotosRequiredTrueWhenMatch() {
        // Setup
        Account account = [SELECT Id FROM Account LIMIT 1];

        // Given / When
        Test.startTest();
        Boolean photosRequired = CustomerPreferencesService.isPhotosRequired(account.Id, PRODUCT_LINE);
        Test.stopTest();

        // Then
        Assert.isTrue(photosRequired, 'Photos required should be true for matching active preference');
    }

    @IsTest
    static void testIsPhotosRequiredFalseWhenNullAccount() {
        Assert.isFalse(
            CustomerPreferencesService.isPhotosRequired(null, PRODUCT_LINE),
            'Null account should not require photos'
        );
    }

    @IsTest
    static void testIsPhotosRequiredExactProductLine() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Id imsRtId = Schema.SObjectType.CustomerPreference__c.getRecordTypeInfosByDeveloperName()
            .get('IMSCustomerPreference')
            .getRecordTypeId();
        insert new CustomerPreference__c(
            Name = 'Exact Instrument Photos Pref',
            RecordTypeId = imsRtId,
            Account__c = account.Id,
            PreferenceType__c = 'Photos required',
            ProductLine__c = 'Instrument',
            StartDate__c = Date.today().addDays(-1),
            EndDate__c = Date.today().addDays(30)
        );

        Test.startTest();
        Boolean instrumentMatch =
            CustomerPreferencesService.isPhotosRequiredExactProductLine(account.Id, 'Instrument');
        Boolean endocamOnly =
            CustomerPreferencesService.isPhotosRequiredExactProductLine(account.Id, PRODUCT_LINE);
        Boolean blankLine =
            CustomerPreferencesService.isPhotosRequiredExactProductLine(account.Id, null);
        Test.stopTest();

        Assert.isTrue(instrumentMatch, 'Exact Instrument Photos required preference should match');
        Assert.isFalse(
            endocamOnly,
            'Endocam exact should not match blank/Instrument preferences'
        );
        Assert.isFalse(blankLine, 'Blank Product Line argument should be false');
    }

    @IsTest
    static void testGetActiveImsPreferencesMissingImsRecordType() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        CustomerPreferencesService.forceMissingImsRecordType = true;
        try {
            Test.startTest();
            List<CustomerPreference__c> results =
                CustomerPreferencesService.getActiveImsPreferences(account.Id, PRODUCT_LINE);
            Test.stopTest();
            Assert.areEqual(0, results.size(), 'Missing IMS RT should return empty');
        } finally {
            CustomerPreferencesService.forceMissingImsRecordType = false;
        }
    }

    @IsTest
    static void testIsPhotosRequiredMissingImsRecordType() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        CustomerPreferencesService.forceMissingImsRecordType = true;
        try {
            Assert.isFalse(
                CustomerPreferencesService.isPhotosRequired(account.Id, PRODUCT_LINE),
                'Missing IMS RT should return false'
            );
        } finally {
            CustomerPreferencesService.forceMissingImsRecordType = false;
        }
    }

    @IsTest
    static void testGetActiveImsPreferences_selectorThrows() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        CustomerPreferencesService.selectorOverride = new ThrowingSelector();
        try {
            Boolean threw = false;
            try {
                CustomerPreferencesService.getActiveImsPreferences(account.Id, PRODUCT_LINE);
            } catch (CustomerPreferencesService.CustomerPreferencesServiceException e) {
                threw = true;
                Assert.isNotNull(e.getCause(), 'Wrapped exception should retain its cause');
            }
            Assert.isTrue(threw, 'Active IMS selector failure should be wrapped');
        } finally {
            CustomerPreferencesService.selectorOverride = null;
        }
    }

    @IsTest
    static void testIsPhotosRequired_selectorThrows() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        CustomerPreferencesService.selectorOverride = new ThrowingSelector();
        try {
            Boolean threw = false;
            try {
                CustomerPreferencesService.isPhotosRequired(account.Id, PRODUCT_LINE);
            } catch (CustomerPreferencesService.CustomerPreferencesServiceException e) {
                threw = true;
                Assert.isNotNull(e.getCause(), 'Wrapped exception should retain its cause');
            }
            Assert.isTrue(threw, 'Photos Required selector failure should be wrapped');
        } finally {
            CustomerPreferencesService.selectorOverride = null;
        }
    }

    @IsTest
    static void testGetCarrierServiceLevelReturnsPreferenceValue() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Id imsRtId = Schema.SObjectType.CustomerPreference__c.getRecordTypeInfosByDeveloperName()
            .get('IMSCustomerPreference')
            .getRecordTypeId();
        insert new CustomerPreference__c(
            Name = 'Carrier Service Level Pref',
            RecordTypeId = imsRtId,
            Account__c = account.Id,
            PreferenceType__c = 'Carrier Service level',
            PreferenceValue__c = 'FEDEX_GROUND',
            StartDate__c = Date.today().addDays(-1),
            EndDate__c = Date.today().addDays(30)
        );

        Test.startTest();
        String shippingMethod = CustomerPreferencesService.getCarrierServiceLevel(account.Id);
        Test.stopTest();

        Assert.areEqual('FEDEX_GROUND', shippingMethod);
    }

    @IsTest
    static void testGetCarrierServiceLevelNullWhenNoMatch() {
        Account account = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        String shippingMethod = CustomerPreferencesService.getCarrierServiceLevel(account.Id);
        Test.stopTest();

        Assert.isNull(shippingMethod, 'No Carrier Service level preference should return null');
        Assert.isNull(
            CustomerPreferencesService.getCarrierServiceLevel(null),
            'Null account should return null'
        );
    }
}