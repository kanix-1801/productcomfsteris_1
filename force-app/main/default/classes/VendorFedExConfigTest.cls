/**
 * @description Tests for VendorFedExConfig.
 * @author Uptima Development Team
 * @date 2026-08-13
 */
@IsTest
private class VendorFedExConfigTest {
    @IsTest
    static void testGetters_returnOverrideValues() {
        // Setup
        VendorFedExConfig.configOverride = new VendorFedExConfig__mdt(
            CalloutOperation__c = 'FEDEX_INTERNAL_DEV',
            ShippingMethod__c = 'FEDEX_GROUND',
            FedExAccount__c = '166134293'
        );

        // When
        Test.startTest();
        String calloutOperation = VendorFedExConfig.getCalloutOperation();
        String shippingMethod = VendorFedExConfig.getShippingMethod();
        String fedExAccount = VendorFedExConfig.getFedExAccount();
        Test.stopTest();

        // Then
        Assert.areEqual('FEDEX_INTERNAL_DEV', calloutOperation);
        Assert.areEqual('FEDEX_GROUND', shippingMethod);
        Assert.areEqual('166134293', fedExAccount);
    }
}