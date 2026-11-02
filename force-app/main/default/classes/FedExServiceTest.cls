/**
 * @description Tests for FedExService (GW-2793).
 */
@IsTest
private class FedExServiceTest {
    @TestSetup
    static void setupData() {
        // Prefer domain builder + RecordType DeveloperName (no org-specific Ids). Same pattern as
        // CustomerPreferencesServiceTest, which creates IMS preferences successfully in CBMQA tests.
        adb_Account accountWithPreference = new adb_Account()
            .name('FedEx Service Account With Preference')
            .systemId('LEG-FEDX-1001')
            .sourceSystemId('TEST-ORACLE-FEDX-001')
            .orgIds('82');

        new adb_CustomerPreference()
            .account(accountWithPreference)
            .name('Carrier Service Level Pref')
            .setRecordType('IMSCustomerPreference')
            .preferenceType('Carrier Service level')
            .preferenceValue('FEDEX_GROUND')
            .startDate(Date.today().addDays(-1))
            .endDate(Date.today().addDays(30))
            .persist();

        // Separate account with no Carrier Service level preference for default-path coverage.
        new adb_Account()
            .name('FedEx Service Account No Preference')
            .systemId('LEG-FEDX-1002')
            .sourceSystemId('TEST-ORACLE-FEDX-002')
            .orgIds('82')
            .persist();
    }

    @IsTest
    static void testGetShippingMethodReturnsPreferenceValue() {
        Account account = [
            SELECT Id
            FROM Account
            WHERE Name = 'FedEx Service Account With Preference'
            LIMIT 1
        ];

        Test.startTest();
        String shippingMethod = FedExService.getShippingMethod(account.Id);
        Test.stopTest();

        Assert.areEqual('FEDEX_GROUND', shippingMethod);
    }

    @IsTest
    static void testGetShippingMethodDefaultsWhenNoPreference() {
        Account account = [
            SELECT Id
            FROM Account
            WHERE Name = 'FedEx Service Account No Preference'
            LIMIT 1
        ];

        Test.startTest();
        String shippingMethod = FedExService.getShippingMethod(account.Id);
        String nullAccountMethod = FedExService.getShippingMethod(null);
        Test.stopTest();

        Assert.areEqual('FEDEX PRIORITY OVERNIGHT', shippingMethod);
        Assert.areEqual('FEDEX PRIORITY OVERNIGHT', nullAccountMethod);
    }

    @IsTest
    static void testRequestShippingLabelCalloutSuccessPath() {
        FedExService.testCalloutResponseMap = FedExService.buildTestSuccessResponse(
            '794900000000',
            Blob.valueOf('MOCK-SHIPPING-LABEL')
        );
        try {
            Test.startTest();
            FedExService.TrackingResponseDTO response =
                FedExService.requestShippingLabel('{"ShippingMethod":"FEDEX_GROUND"}');
            Test.stopTest();

            Assert.areEqual('794900000000', response.trackingNumber);
            Assert.isNotNull(response.shippingLabel);
            Assert.areEqual('MOCK-SHIPPING-LABEL', response.shippingLabel.toString());
        } finally {
            FedExService.testCalloutResponseMap = null;
        }
    }

    @IsTest
    static void testRequestShippingLabelBlankBodyThrows() {
        Boolean threw = false;
        try {
            FedExService.requestShippingLabel('  ');
        } catch (FedExService.FedExServiceException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('required'),
                'Blank body should require a request body'
            );
        }
        Assert.isTrue(threw, 'Blank restBody should throw FedExServiceException');
    }

    @IsTest
    static void testServiceDataToJsonAndErrorHelpers() {
        Assert.isNull(FedExService.serviceDataToJson(null));
        Assert.areEqual('{"a":1}', FedExService.serviceDataToJson('{"a":1}'));
        Assert.isTrue(FedExService.serviceDataToJson(new Map<String, Object>{ 'a' => 1 }).contains('a'));

        String failure = FedExService.formatCalloutFailure(
            new Map<String, Object>{
                'SERVICE_STATUS' => 500,
                'SO_RETURN' => 'boom'
            },
            '{"errors":[{"errorMessage":"bad request,"}]}'
        );
        Assert.isTrue(failure.contains('HTTP 500'));
        Assert.isTrue(failure.contains('boom'));
        Assert.isTrue(failure.contains('bad request'));

        Assert.areEqual(
            'unknown error',
            FedExService.formatCalloutFailure(null, null)
        );
        Assert.areEqual(
            'unknown error',
            FedExService.formatCalloutFailure(
                new Map<String, Object>{ 'SERVICE_STATUS' => '', 'SO_RETURN' => 'null' },
                null
            )
        );

        Assert.isNull(FedExService.extractErrorMessages(null));
        Assert.isNull(FedExService.extractErrorMessages('not-json'));
        Assert.isNull(FedExService.extractErrorMessages('["array"]'));
        Assert.isNull(FedExService.extractErrorMessages('{"errors":"not-a-list"}'));
        Assert.isNull(
            FedExService.extractErrorMessages('{"errors":["skip-non-map",{"errorMessage":""}]}')
        );
        Assert.areEqual(
            'only error',
            FedExService.extractErrorMessages('{"errors":[{"errorMessage":"only error"}]}')
        );
    }

    @IsTest
    static void testRequestShippingLabelBlankTrackingThrows() {
        FedExService.testCalloutResponseMap = FedExService.buildTestSuccessResponse('', null);
        Boolean threw = false;
        try {
            FedExService.requestShippingLabel('{"ShippingMethod":"FEDEX_GROUND"}');
        } catch (FedExService.FedExServiceException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('tracking number'));
        } finally {
            FedExService.testCalloutResponseMap = null;
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void testRequestShippingLabelCalloutFailurePaths() {
        FedExService.testCalloutResponseMap = new Map<String, Object>{
            'SO_SUCCESS' => false,
            'SERVICE_STATUS' => 502,
            'SO_RETURN' => 'gateway',
            'SERVICE_DATA' => '{"errors":[{"errorMessage":"upstream"}]}'
        };
        Boolean failureThrew = false;
        try {
            FedExService.requestShippingLabel('{"x":1}');
        } catch (FedExService.FedExServiceException e) {
            failureThrew = true;
            Assert.isTrue(e.getMessage().contains('failed'));
        }
        Assert.isTrue(failureThrew);

        FedExService.testCalloutResponseMap = new Map<String, Object>{
            'SO_SUCCESS' => true,
            'SERVICE_DATA' => null
        };
        Boolean nullDataThrew = false;
        try {
            FedExService.requestShippingLabel('{"x":1}');
        } catch (FedExService.FedExServiceException e) {
            nullDataThrew = true;
            Assert.isTrue(e.getMessage().contains('SERVICE_DATA'));
        }
        Assert.isTrue(nullDataThrew);

        FedExService.testCalloutResponseMap = new Map<String, Object>{
            'SO_SUCCESS' => true,
            'SERVICE_DATA' => '{"trackingNumber":"","errors":[{"errorMessage":"missing track"}]}'
        };
        Boolean blankTrackThrew = false;
        try {
            FedExService.requestShippingLabel('{"x":1}');
        } catch (FedExService.FedExServiceException e) {
            blankTrackThrew = true;
            Assert.isTrue(e.getMessage().contains('tracking number'));
            Assert.isTrue(e.getMessage().contains('missing track'));
        } finally {
            FedExService.testCalloutResponseMap = null;
        }
        Assert.isTrue(blankTrackThrew);
    }

    @IsTest
    static void testRequestShippingLabelUnexpectedExceptionWrapped() {
        FedExService.testCalloutResponseMap = null;
        Boolean threw = false;
        try {
            // No injected map forces SO_Callout; missing provider config is wrapped.
            FedExService.requestShippingLabel('{"x":1}');
        } catch (FedExService.FedExServiceException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('unexpected') || e.getMessage().contains('failed'),
                e.getMessage()
            );
        } finally {
            FedExService.testCalloutResponseMap = null;
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void testSanitizeFedExPayloadOmitsShippingLabel() {
        String payload = '{"trackingNumber":"","shippingLabel":"JVBERi0x",' +
            '"errors":[{"errorMessage":"An unexpected error has occured"}]}';

        String sanitized = FedExService.sanitizeFedExPayload(payload);

        Assert.isFalse(sanitized.contains('JVBERi0x'), sanitized);
        Assert.isTrue(sanitized.contains('trackingNumber'), sanitized);
        Assert.isTrue(sanitized.contains('An unexpected error has occured'), sanitized);
        Assert.areEqual('plain', FedExService.sanitizeFedExPayload('plain'));

        String longValue = 'x'.repeat(12001);
        Assert.isTrue(
            FedExService.sanitizeFedExPayload(longValue).endsWith('...[truncated]'),
            'Long non-JSON payloads should be truncated'
        );
    }
}