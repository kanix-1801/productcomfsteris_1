@IsTest
private class OracleUnitPricingGatewayTest {
    @IsTest
    static void extractErrorDetail_includesHttpStatusAndBody() {
        Map<String, Object> responseMap = new Map<String, Object>{
            'SO_SUCCESS' => false,
            'SO_RETURN' => null,
            'SERVICE_STATUS' => 500,
            'SERVICE_DATA' => '{"message":"401 Unauthorized"}'
        };

        String detail = OracleUnitPricingGateway.extractErrorDetail(responseMap);

        System.assert(
            detail.contains('HTTP 500'),
            'Error should include the HTTP status. Actual: ' + detail
        );
        System.assert(
            detail.contains('401 Unauthorized'),
            'Error should include the response body. Actual: ' + detail
        );
    }

    @IsTest
    static void extractErrorDetail_usesSoReturnWhenPresent() {
        Map<String, Object> responseMap = new Map<String, Object>{
            'SO_SUCCESS' => false,
            'SO_RETURN' => 'Named Credential authentication failed'
        };

        System.assertEquals(
            'Named Credential authentication failed',
            OracleUnitPricingGateway.extractErrorDetail(responseMap)
        );
    }

    @IsTest
    static void extractErrorDetail_emptyMap_returnsClearMessage() {
        System.assertEquals(
            'Oracle pricing callout returned an empty response',
            OracleUnitPricingGateway.extractErrorDetail(new Map<String, Object>())
        );
    }

    @IsTest
    static void extractErrorDetail_leftoverKeys_joinValues() {
        Map<String, Object> responseMap = new Map<String, Object>{
            'SO_SUCCESS' => false,
            'RETRY_ENQUEUED' => true,
            'SERVICE_STATUS' => 'null',
            'TRACE' => 'abc'
        };

        System.assertEquals(
            'TRACE=abc',
            OracleUnitPricingGateway.extractErrorDetail(responseMap)
        );
    }

    @IsTest
    static void extractResponseBody_serializesNonStringPayload() {
        Map<String, Object> responseMap = new Map<String, Object>{
            'SERVICE_DATA' => new Map<String, Object>{ 'message' => 'ok' }
        };

        String body = OracleUnitPricingGateway.extractResponseBody(responseMap);
        System.assert(body.contains('ok'), 'Map payloads should serialize to JSON. Actual: ' + body);
    }

    @IsTest
    static void sendUnitPriceRequest_nullRequest_returnsError() {
        Test.startTest();
        OracleUnitPricingGateway.CalloutResult result =
            OracleUnitPricingGateway.sendUnitPriceRequest(null);
        Test.stopTest();

        System.assertEquals(false, result.calloutSuccess);
        System.assertEquals('Request body is null', result.errorDetail);
    }

    @IsTest
    static void sendProspectPriceRequest_nullRequest_returnsError() {
        Test.startTest();
        OracleUnitPricingGateway.CalloutResult result =
            OracleUnitPricingGateway.sendProspectPriceRequest(null);
        Test.stopTest();

        System.assertEquals(false, result.calloutSuccess);
        System.assertEquals('Request body is null', result.errorDetail);
    }

    @IsTest
    static void sendUnitPriceRequest_failedCallout_usesTestMock() {
        Test.startTest();
        OracleUnitPricingGateway.CalloutResult result =
            OracleUnitPricingGateway.sendUnitPriceRequest(sampleRequest());
        Test.stopTest();

        System.assertEquals(true, result.calloutSuccess);
        System.assertNotEquals(null, result.parsedResponse);
        System.assertEquals(false, result.retryEnqueued);
    }

    @IsTest
    static void sendProspectPriceRequest_failedCallout_usesTestMock() {
        Test.startTest();
        OracleUnitPricingGateway.CalloutResult result =
            OracleUnitPricingGateway.sendProspectPriceRequest(sampleRequest());
        Test.stopTest();

        System.assertEquals(true, result.calloutSuccess);
        System.assertNotEquals(null, result.parsedResponse);
    }

    @IsTest
    static void sendUnitPriceRequest_success_parsesPrices() {
        OracleUnitPricingGateway.testResponseMap = new Map<String, Object>{
            'SO_SUCCESS' => true,
            'RETRY_ENQUEUED' => false,
            'SERVICE_DATA' => unitPriceSuccessBody()
        };

        Test.startTest();
        OracleUnitPricingGateway.CalloutResult result =
            OracleUnitPricingGateway.sendUnitPriceRequest(sampleRequest());
        Test.stopTest();

        System.assertEquals(true, result.calloutSuccess);
        System.assertEquals(1, result.parsedResponse.priceInfo.size());
        System.assertEquals('10008301', result.parsedResponse.priceInfo[0].productPartNumber);
        System.assertEquals(10, result.parsedResponse.priceInfo[0].price);
    }

    @IsTest
    static void sendUnitPriceRequest_emptySuccess_usesTestMock() {
        OracleUnitPricingGateway.testResponseMap = new Map<String, Object>{
            'SO_SUCCESS' => true,
            'RETRY_ENQUEUED' => true,
            'SERVICE_DATA' => '{"OutputParameters":{"P_MESSAGEKEY":"Success"}}'
        };

        Test.startTest();
        OracleUnitPricingGateway.CalloutResult result =
            OracleUnitPricingGateway.sendUnitPriceRequest(sampleRequest());
        Test.stopTest();

        System.assertEquals(true, result.calloutSuccess);
        System.assertEquals(true, result.retryEnqueued);
        System.assertEquals(
            'Oracle returned empty pricing response',
            result.errorDetail
        );
        System.assertNotEquals(null, result.parsedResponse);
    }

    @IsTest
    static void sendProspectPriceRequest_success_parsesPrices() {
        OracleUnitPricingGateway.testResponseMap = new Map<String, Object>{
            'SO_SUCCESS' => true,
            'SERVICE_DATA' => prospectSuccessBody()
        };

        Test.startTest();
        OracleUnitPricingGateway.CalloutResult result =
            OracleUnitPricingGateway.sendProspectPriceRequest(sampleRequest());
        Test.stopTest();

        System.assertEquals(true, result.calloutSuccess);
        System.assertEquals(1, result.parsedResponse.priceInfo.size());
        System.assertEquals('10008301', result.parsedResponse.priceInfo[0].productPartNumber);
    }

    @IsTest
    static void sendProspectPriceRequest_emptySuccess_usesTestMock() {
        OracleUnitPricingGateway.testResponseMap = new Map<String, Object>{
            'SO_SUCCESS' => true,
            'SERVICE_DATA' => '{"partNumbers":[]}'
        };

        Test.startTest();
        OracleUnitPricingGateway.CalloutResult result =
            OracleUnitPricingGateway.sendProspectPriceRequest(sampleRequest());
        Test.stopTest();

        System.assertEquals(true, result.calloutSuccess);
        System.assertEquals('Boomi returned empty pricing response', result.errorDetail);
        System.assertNotEquals(null, result.parsedResponse);
    }

    @IsTest
    static void sendUnitPriceRequest_invalidJson_returnsCaughtError() {
        OracleUnitPricingGateway.testResponseMap = new Map<String, Object>{
            'SO_SUCCESS' => true,
            'SERVICE_DATA' => 'not-json'
        };

        Test.startTest();
        OracleUnitPricingGateway.CalloutResult result =
            OracleUnitPricingGateway.sendUnitPriceRequest(sampleRequest());
        Test.stopTest();

        System.assertEquals(false, result.calloutSuccess);
        System.assertNotEquals(null, result.errorDetail);
    }

    @IsTest
    static void sendProspectPriceRequest_invalidJson_usesTestMockAfterCatch() {
        OracleUnitPricingGateway.testResponseMap = new Map<String, Object>{
            'SO_SUCCESS' => true,
            'SERVICE_DATA' => 'not-json'
        };

        Test.startTest();
        OracleUnitPricingGateway.CalloutResult result =
            OracleUnitPricingGateway.sendProspectPriceRequest(sampleRequest());
        Test.stopTest();

        System.assertEquals(true, result.calloutSuccess);
        System.assertNotEquals(null, result.parsedResponse);
    }

    @IsTest
    static void isSuccessful_nullOrNonBoolean_returnsFalse() {
        System.assertEquals(false, OracleUnitPricingGateway.isSuccessful(null));
        System.assertEquals(
            false,
            OracleUnitPricingGateway.isSuccessful(
                new Map<String, Object>{ 'SO_SUCCESS' => 'true' }
            )
        );
    }

    private static OraclePricingRequest sampleRequest() {
        OraclePricingRequest request = new OraclePricingRequest();
        request.operatingUnitName = 'STERIS US';
        request.operatingUnit = '82';
        request.shipToCustomerNumber = '4585001';
        request.billToCustomerNumber = '62694';
        request.sourceSystem = 'SFDC';
        request.productPartNumbers = new List<OraclePricingRequest.ProductPartNumber>{
            new OraclePricingRequest.ProductPartNumber('10008301', 1)
        };
        return request;
    }

    private static String unitPriceSuccessBody() {
        return '{"OutputParameters":{"P_MESSAGEKEY":"Success","P_ERRORCODE":"0",' +
            '"P_ITEMS_TBL":[{"P_ITEMS_TBL_ITEM":{"PARTNUMBER":"10008301",' +
            '"PRICE":"10","LIST_PRICE":"12","MESSAGEKEY":"Success"}}]}}';
    }

    private static String prospectSuccessBody() {
        return '{"partNumbers":[{"partNumber":"10008301","listPrice":"10",' +
            '"messageKey":"Success","errorCode":"0"}]}';
    }
}