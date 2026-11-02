/**
 * @description Tests for OraclePricingRequest JSON payload builders (GW-4585).
 */
@IsTest
private class OraclePricingRequestTest {
    @IsTest
    static void toJsonMap_buildsGenericCallAndSkipsBlankParts() {
        OraclePricingRequest request = sampleRequest();
        request.accountType = 'Prospect';
        request.priceListName = 'USA HEALTHCARE';
        request.productPartNumbers.add(new OraclePricingRequest.ProductPartNumber());
        request.productPartNumbers.add(new OraclePricingRequest.ProductPartNumber('10008302', null));

        Test.startTest();
        Map<String, Object> payload = request.toJsonMap();
        Test.stopTest();

        Map<String, Object> inputParameters = (Map<String, Object>) payload.get('InputParameters');
        Assert.areEqual('STERIS US', inputParameters.get('P_OU_NAME'));
        Assert.areEqual('82', inputParameters.get('P_OU_ID'));
        Assert.areEqual('4585001', inputParameters.get('P_ST_ACCT_NUM'));
        Assert.areEqual('62694', inputParameters.get('P_BT_ACCT_NUM'));
        Assert.areEqual('ST_ACCOUNT', inputParameters.get('P_PRICE_LIST_LEVEL'));
        Assert.areEqual('BT_ACCOUNT', inputParameters.get('P_DISCOUNT_ACCOUNT'));
        Assert.areEqual('USA HEALTHCARE', inputParameters.get('P_PRICE_LIST_NAME'));
        Assert.areEqual('SFDC', inputParameters.get('P_SOURCE_SYSTEM'));

        List<Object> itemTable = (List<Object>) inputParameters.get('P_ITEMS_TBL');
        Map<String, Object> itemWrapper = (Map<String, Object>) itemTable[0];
        List<Object> items = (List<Object>) itemWrapper.get('P_ITEMS_TBL_ITEM');
        Assert.areEqual(2, items.size());
        Map<String, Object> firstItem = (Map<String, Object>) items[0];
        Map<String, Object> secondItem = (Map<String, Object>) items[1];
        Assert.areEqual('10008301', firstItem.get('PARTNUMBER'));
        Assert.areEqual('1', firstItem.get('QUANTITY'));
        Assert.areEqual('10008302', secondItem.get('PARTNUMBER'));
        Assert.areEqual('1', secondItem.get('QUANTITY'));
    }

    @IsTest
    static void toJsonMap_whenNoProducts_usesDefaultPriceListLevel() {
        OraclePricingRequest request = new OraclePricingRequest();
        request.productPartNumbers = null;

        Test.startTest();
        Map<String, Object> payload = request.toJsonMap();
        Test.stopTest();

        Map<String, Object> inputParameters = (Map<String, Object>) payload.get('InputParameters');
        Assert.areEqual('ST_ADDRESS', inputParameters.get('P_PRICE_LIST_LEVEL'));
        Assert.areEqual('ST_ACCOUNT', inputParameters.get('P_DISCOUNT_ACCOUNT'));
        Assert.isNull(inputParameters.get('P_PRICE_LIST_NAME'));
    }

    @IsTest
    static void toJsonString_skipsBlankPartsAndEscapesQuotes() {
        OraclePricingRequest request = sampleRequest();
        request.productPartNumbers.add(new OraclePricingRequest.ProductPartNumber('', 2));
        request.productPartNumbers[0].partNumber = 'PART"01';

        Test.startTest();
        String payload = request.toJsonString();
        Test.stopTest();

        Assert.isTrue(payload.contains('"PARTNUMBER":"PART\\"01"'));
        Assert.isFalse(payload.contains('"QUANTITY":"2"'));
        Assert.isTrue(payload.contains('"P_PRICE_LIST_LEVEL":"ST_ACCOUNT"'));
        Assert.isTrue(payload.contains('"P_DISCOUNT_ACCOUNT":"BT_ACCOUNT"'));
    }

    @IsTest
    static void toProspectJsonString_formatsPartNumbersAndPriceList() {
        OraclePricingRequest request = sampleRequest();
        request.sfOpportunityId = '006000000000001';
        request.priceList = '6125';
        request.productPartNumbers.add(new OraclePricingRequest.ProductPartNumber(null, 1));
        request.productPartNumbers.add(new OraclePricingRequest.ProductPartNumber('10008302', 3));

        Test.startTest();
        String validPriceList = request.toProspectJsonString();
        request.priceList = 'not-a-number';
        String invalidPriceList = request.toProspectJsonString();
        request.priceList = '';
        String blankPriceList = request.toProspectJsonString();
        Test.stopTest();

        Assert.isTrue(validPriceList.contains('"priceList":6125'));
        Assert.isTrue(validPriceList.contains('"partNumbers":"10008301,10008302"'));
        Assert.isTrue(validPriceList.contains('"opportunityId":"006000000000001"'));
        Assert.isTrue(invalidPriceList.contains('"priceList":null'));
        Assert.isTrue(blankPriceList.contains('"priceList":null'));
    }

    private static OraclePricingRequest sampleRequest() {
        OraclePricingRequest request = new OraclePricingRequest();
        request.operatingUnit = '82';
        request.operatingUnitName = 'STERIS US';
        request.shipToCustomerNumber = '4585001';
        request.billToCustomerNumber = '62694';
        request.genericPriceListLevel = 'ST_ACCOUNT';
        request.genericDiscountAccount = 'BT_ACCOUNT';
        request.sourceSystem = 'SFDC';
        request.productPartNumbers = new List<OraclePricingRequest.ProductPartNumber>{
            new OraclePricingRequest.ProductPartNumber('10008301', 1)
        };
        return request;
    }
}