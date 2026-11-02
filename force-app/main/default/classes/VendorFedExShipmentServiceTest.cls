/**
 * @description Tests for VendorFedExShipmentService helpers and error handling.
 * @author Uptima Development Team
 * @date 2026-08-13
 */
@IsTest
private class VendorFedExShipmentServiceTest {
    @IsTest
    static void testExtractErrorMessages_returnsBoomiMessage() {
        // Setup
        String payload =
            '{"trackingNumber":"","errors":[{"errorMessage":"CustomerPo is empty., "}]}';

        // When
        String message = VendorFedExShipmentService.extractErrorMessages(payload);

        // Then
        Assert.isTrue(
            message.contains('CustomerPo is empty'),
            message
        );
    }

    @IsTest
    static void testFormatCalloutFailure_includesHttpAndErrors() {
        // Setup
        Map<String, Object> responseMap = new Map<String, Object>{
            'SERVICE_STATUS' => 400,
            'SO_RETURN' => null
        };
        String payload =
            '{"errors":[{"errorMessage":"CustomerPo is empty."}]}';

        // When
        String message = VendorFedExShipmentService.formatCalloutFailure(
            responseMap,
            payload
        );

        // Then
        Assert.isTrue(message.contains('HTTP 400'), message);
        Assert.isTrue(message.contains('CustomerPo is empty'), message);
    }

    @IsTest
    static void testServiceDataToJson_serializesMap() {
        // Setup
        Map<String, Object> serviceData = new Map<String, Object>{
            'trackingNumber' => '123'
        };

        // When
        String jsonPayload = VendorFedExShipmentService.serviceDataToJson(serviceData);

        // Then
        Assert.isTrue(jsonPayload.contains('123'), jsonPayload);
    }

    @IsTest
    static void testCreateShipments_missingReturnOrder_throws() {
        // Setup
        Map<Id, List<Id>> returnOrderIdToWorkOrderIdsMap = new Map<Id, List<Id>>{
            UserInfo.getUserId() => new List<Id>()
        };

        Boolean threw = false;
        try {
            // When
            Test.startTest();
            VendorFedExShipmentService.createShipments(returnOrderIdToWorkOrderIdsMap);
            Test.stopTest();
        } catch (VendorFedExShipmentException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('was not found'),
                e.getMessage()
            );
        }

        // Then
        Assert.isTrue(threw, 'Missing Return Order should throw VendorFedExShipmentException');
    }

    @IsTest
    static void testRequestShipment_retriesThenSucceeds() {
        // Setup
        VendorFedExShipmentService.testRemainingCalloutFailures = 2;

        // When
        Test.startTest();
        VendorFedExShipmentService.TrackingResponseDTO response =
            VendorFedExShipmentService.requestShipment('{}');
        Test.stopTest();

        // Then
        Assert.areEqual('794900000000', response.trackingNumber);
        Assert.areEqual(0, VendorFedExShipmentService.testRemainingCalloutFailures);
    }

    @IsTest
    static void testRequestShipment_blankTracking_throwsAfterRetries() {
        // Setup
        VendorFedExShipmentService.TrackingResponseDTO blankResponse =
            new VendorFedExShipmentService.TrackingResponseDTO();
        blankResponse.trackingNumber = '';
        VendorFedExShipmentService.testResponse = blankResponse;

        Boolean threw = false;
        try {
            // When
            Test.startTest();
            VendorFedExShipmentService.requestShipment('{}');
            Test.stopTest();
        } catch (VendorFedExShipmentException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('did not return a tracking number'),
                e.getMessage()
            );
        }

        // Then
        Assert.isTrue(threw, 'Blank tracking should throw after retries are exhausted');
    }
}