/**
 * @description Wrapper for VendorFedExConfig__mdt so FedEx account, shipping method, and
 *              ShoutOut operation are not hardcoded. Tests may set configOverride.
 * @author Uptima Development Team
 * @date 2026-08-13
 * @group Config
 */
public with sharing class VendorFedExConfig {
    private static final String DEFAULT_DEVELOPER_NAME = 'Default';

    /** Test hook so unit tests do not depend on deployed custom metadata. */
    @TestVisible
    private static VendorFedExConfig__mdt configOverride;

    /**
     * @description ShoutOut operation developer name for the FedEx shipping-label call.
     * @return CalloutOperation__c from the Default VendorFedExConfig__mdt record
     */
    public static String getCalloutOperation() {
        return getConfig().CalloutOperation__c;
    }

    /**
     * @description FedEx service type sent on the shipping-label request.
     * @return ShippingMethod__c from the Default VendorFedExConfig__mdt record
     */
    public static String getShippingMethod() {
        return getConfig().ShippingMethod__c;
    }

    /**
     * @description STERIS FedEx account number sent to Boomi.
     * @return FedExAccount__c from the Default VendorFedExConfig__mdt record
     */
    public static String getFedExAccount() {
        return getConfig().FedExAccount__c;
    }

    private static VendorFedExConfig__mdt getConfig() {
        if (configOverride != null) {
            return configOverride;
        }

        VendorFedExConfig__mdt configRecord = VendorFedExConfig__mdt.getInstance(
            DEFAULT_DEVELOPER_NAME
        );
        if (configRecord == null) {
            throw new VendorFedExShipmentException(
                'Vendor FedEx Config custom metadata record Default is missing.'
            );
        }
        return configRecord;
    }
}