/**
 * Tests for {@link OraclePricingGateway}.
 *
 * @author STERIS
 */
@IsTest
private class OraclePricingGatewayTest {
    private class GetPricingDetailMock implements HttpCalloutMock {
        private final Integer statusCode;
        private final String responseBody;

        GetPricingDetailMock(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        public HTTPResponse respond(HTTPRequest req) {
            Assert.areEqual('POST', req.getMethod());
            Assert.isTrue(
                req.getEndpoint() != null && req.getEndpoint().contains('Oracle_Pricing_API'),
                'Endpoint should use Oracle_Pricing_API Named Credential'
            );
            Assert.isTrue(String.isNotBlank(req.getBody()), 'Request body should be JSON');

            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(responseBody != null ? responseBody : '');
            return res;
        }
    }

    private static OraclePricingGateway.GetPricingDetailRequestDto newValidRequest() {
        OraclePricingGateway.LineItemRequestDto line = new OraclePricingGateway.LineItemRequestDto();
        line.PARTNUMBER = 'PART-001';
        OraclePricingGateway.ItemsTableBlockDto block = new OraclePricingGateway.ItemsTableBlockDto();
        block.P_ITEMS_TBL_ITEM = new List<OraclePricingGateway.LineItemRequestDto>{ line };
        OraclePricingGateway.GetPricingDetailRequestDto request = new OraclePricingGateway.GetPricingDetailRequestDto();
        request.InputParameters = new OraclePricingGateway.InputParametersDto();
        request.InputParameters.P_OU_NAME = 'STERIS US';
        request.InputParameters.P_ST_ACCT_NUM = '104079';
        request.InputParameters.P_BT_ACCT_NUM = '62694';
        request.InputParameters.P_PRICE_LIST_LEVEL = 'ST_ACCOUNT';
        request.InputParameters.P_DISCOUNT_ACCOUNT = 'BT_ACCOUNT';
        request.InputParameters.P_ITEMS_TBL = new List<OraclePricingGateway.ItemsTableBlockDto>{ block };
        request.InputParameters.P_SOURCE_SYSTEM = 'SALESFORCE';
        return request;
    }

    private static String sampleSuccessJson() {
        return '{'
            + '"OutputParameters":{'
            + '"X_ITEMS_TBL":['
            + '{"PARTNUMBER":"PART-001","LIST_PRICE":100.00,"PRICE":90.50}'
            + ']}}';
    }

    /** ESB success shape: P_ITEMS_TBL { P_ITEMS_TBL_ITEM [ { PARTNUMBER, LIST_PRICE, PRICE, ERRORCODE 0 } ] } */
    private static String sampleSuccessJsonPItemsTable() {
        return '{'
            + '"OutputParameters":{'
            + '"P_ITEMS_TBL":{'
            + '"P_ITEMS_TBL_ITEM":['
            + '{"PARTNUMBER":"PART-001","LIST_PRICE":6515.64,"PRICE":6189.86,"ERRORCODE":"0","MESSAGEKEY":"Success"}'
            + ']'
            + '}}'
            + '}}';
    }

    @IsTest
    static void testSendGetPricingDetailSuccess() {
        Test.setMock(HttpCalloutMock.class, new GetPricingDetailMock(200, sampleSuccessJson()));
        OraclePricingGateway gateway = new OraclePricingGateway();

        OraclePricingGateway.GetPricingDetailResponseDto response;
        Test.startTest();
        response = gateway.sendGetPricingDetail(newValidRequest());
        Test.stopTest();

        Assert.isNotNull(response);
        Assert.isNotNull(response.OutputParameters);
        Assert.isNotNull(response.OutputParameters.X_ITEMS_TBL);
        Assert.areEqual(1, response.OutputParameters.X_ITEMS_TBL.size());
        OraclePricingGateway.LineItemResponseDto row = response.OutputParameters.X_ITEMS_TBL[0];
        Assert.areEqual('PART-001', row.PARTNUMBER);
        Assert.areEqual(100.00, row.LIST_PRICE);
        Assert.areEqual(90.50, row.PRICE);
    }

    @IsTest
    static void testSendGetPricingDetailSuccessPItemsTable() {
        Test.setMock(HttpCalloutMock.class, new GetPricingDetailMock(200, sampleSuccessJsonPItemsTable()));
        OraclePricingGateway gateway = new OraclePricingGateway();

        OraclePricingGateway.GetPricingDetailResponseDto response;
        Test.startTest();
        response = gateway.sendGetPricingDetail(newValidRequest());
        Test.stopTest();

        Assert.isNotNull(response.OutputParameters);
        Assert.isNotNull(response.OutputParameters.X_ITEMS_TBL);
        Assert.areEqual(1, response.OutputParameters.X_ITEMS_TBL.size());
        OraclePricingGateway.LineItemResponseDto row = response.OutputParameters.X_ITEMS_TBL[0];
        Assert.areEqual('PART-001', row.PARTNUMBER);
        Assert.areEqual(6515.64, row.LIST_PRICE);
        Assert.areEqual(6189.86, row.PRICE);
    }

    private static String sampleBusinessErrorJson() {
        return '{'
            + '"OutputParameters":{'
            + '"P_MESSAGEKEY":"MISSING_MANDATORY_PARAMETER",'
            + '"P_ERRORCODE":"101",'
            + '"P_ERRORMESSAGE":"Missing Mandatory parameters"'
            + '}}';
    }

    @IsTest
    static void testSendGetPricingDetailOracleBusinessError() {
        Test.setMock(HttpCalloutMock.class, new GetPricingDetailMock(200, sampleBusinessErrorJson()));
        OraclePricingGateway gateway = new OraclePricingGateway();
        try {
            Test.startTest();
            gateway.sendGetPricingDetail(newValidRequest());
            Test.stopTest();
            Assert.fail('Expected OraclePricingGatewayException');
        } catch (OraclePricingGateway.OraclePricingGatewayException e) {
            Assert.isTrue(
                e.getMessage().contains('Missing Mandatory'),
                'Message should include Oracle P_ERRORMESSAGE: ' + e.getMessage()
            );
            Assert.isTrue(e.getMessage().contains('101'), 'Message should include error code: ' + e.getMessage());
        }
    }

    @IsTest
    static void testSendGetPricingDetailHttpError() {
        Test.setMock(HttpCalloutMock.class, new GetPricingDetailMock(500, '{"error":"server"}'));
        OraclePricingGateway gateway = new OraclePricingGateway();

        try {
            Test.startTest();
            gateway.sendGetPricingDetail(newValidRequest());
            Test.stopTest();
            Assert.fail('Expected OraclePricingGatewayException');
        } catch (OraclePricingGateway.OraclePricingGatewayException e) {
            Assert.isTrue(e.getMessage().contains('HTTP status 500'));
        }
    }

    @IsTest
    static void testSendGetPricingDetailInvalidJson() {
        Test.setMock(HttpCalloutMock.class, new GetPricingDetailMock(200, 'not-json'));
        OraclePricingGateway gateway = new OraclePricingGateway();

        try {
            Test.startTest();
            gateway.sendGetPricingDetail(newValidRequest());
            Test.stopTest();
            Assert.fail('Expected OraclePricingGatewayException');
        } catch (OraclePricingGateway.OraclePricingGatewayException e) {
            Assert.isTrue(e.getMessage().contains('could not be parsed'));
        }
    }

    @IsTest
    static void testSendGetPricingDetailEmptyBody() {
        Test.setMock(HttpCalloutMock.class, new GetPricingDetailMock(200, '   '));
        OraclePricingGateway gateway = new OraclePricingGateway();

        try {
            Test.startTest();
            gateway.sendGetPricingDetail(newValidRequest());
            Test.stopTest();
            Assert.fail('Expected OraclePricingGatewayException');
        } catch (OraclePricingGateway.OraclePricingGatewayException e) {
            Assert.isTrue(e.getMessage().contains('empty response'));
        }
    }

    @IsTest
    static void testSendGetPricingDetailNullRequest() {
        OraclePricingGateway gateway = new OraclePricingGateway();
        try {
            gateway.sendGetPricingDetail(null);
            Assert.fail('Expected OraclePricingGatewayException');
        } catch (OraclePricingGateway.OraclePricingGatewayException e) {
            Assert.isTrue(e.getMessage().contains('Request is required'));
        }
    }

    @IsTest
    static void testSendGetPricingDetailNullInputParameters() {
        OraclePricingGateway.GetPricingDetailRequestDto request = new OraclePricingGateway.GetPricingDetailRequestDto();
        OraclePricingGateway gateway = new OraclePricingGateway();
        try {
            gateway.sendGetPricingDetail(request);
            Assert.fail('Expected OraclePricingGatewayException');
        } catch (OraclePricingGateway.OraclePricingGatewayException e) {
            Assert.isTrue(e.getMessage().contains('InputParameters is required'));
        }
    }

    @IsTest
    static void testSendGetPricingDetailNullItemsTable() {
        OraclePricingGateway.GetPricingDetailRequestDto request = new OraclePricingGateway.GetPricingDetailRequestDto();
        request.InputParameters = new OraclePricingGateway.InputParametersDto();
        request.InputParameters.P_OU_NAME = 'OU';
        request.InputParameters.P_ST_ACCT_NUM = '1';
        request.InputParameters.P_BT_ACCT_NUM = '1';
        request.InputParameters.P_PRICE_LIST_LEVEL = 'L';
        request.InputParameters.P_DISCOUNT_ACCOUNT = 'D';
        request.InputParameters.P_SOURCE_SYSTEM = 'S';
        // P_ITEMS_TBL intentionally null
        OraclePricingGateway gateway = new OraclePricingGateway();
        try {
            gateway.sendGetPricingDetail(request);
            Assert.fail('Expected OraclePricingGatewayException');
        } catch (OraclePricingGateway.OraclePricingGatewayException e) {
            Assert.isTrue(e.getMessage().contains('P_ITEMS_TBL is required'));
        }
    }
}