/**
 * @author PWC Developer
 * @date 2026/07/28
 *
 * @group Generate Quote
 *
 * @description GC-2649 Selector for ExternalSystemEndpoint custom metadata records.
 */
public with sharing class ExternalSystemEndpointSelector {
    public static final String SALES_CONNECTION_DEVELOPER_NAME = 'SalesConnection';
    public static final String REPAIR_CENTER_QUOTE_EMAIL_DEVELOPER_NAME = 'RepairCenterQuoteEmail';

    @TestVisible
    private static ExternalSystemEndpoint__mdt testSalesConnectionOverride;
    @TestVisible
    private static ExternalSystemEndpoint__mdt testRepairCenterQuoteEmailOverride;

    /**
     * @description Returns the Sales Connection endpoint configuration record.
     * @return Sales Connection custom metadata record, or null when not deployed.
     */
    public static ExternalSystemEndpoint__mdt selectSalesConnection() {
        if (Test.isRunningTest() && testSalesConnectionOverride != null) {
            return testSalesConnectionOverride;
        }

        return ExternalSystemEndpoint__mdt.getInstance(SALES_CONNECTION_DEVELOPER_NAME);
    }

    /**
     * @description GW-5102 - Returns Repair Center quote email ConnectCare URL and inbound address.
     * @return Repair Center Quote Email custom metadata record, or null when not deployed.
     */
    public static ExternalSystemEndpoint__mdt selectRepairCenterQuoteEmail() {
        if (Test.isRunningTest() && testRepairCenterQuoteEmailOverride != null) {
            return testRepairCenterQuoteEmailOverride;
        }

        return ExternalSystemEndpoint__mdt.getInstance(REPAIR_CENTER_QUOTE_EMAIL_DEVELOPER_NAME);
    }

    /**
     * @description GW-5102 - ConnectCare host for quote approval links in customer emails.
     * @return URL from CMDT, or blank when the record/field is missing.
     */
    public static String connectCareQuoteApprovalUrl() {
        ExternalSystemEndpoint__mdt settings = selectRepairCenterQuoteEmail();
        return settings == null ? null : settings.ConnectCareQuoteApprovalUrl__c;
    }

    /**
     * @description GW-5102 - Inbound Email Service address used as Reply-To on quote emails.
     * @return Email from CMDT, or blank when the record/field is missing.
     */
    public static String repairCenterQuoteInboundEmail() {
        ExternalSystemEndpoint__mdt settings = selectRepairCenterQuoteEmail();
        return settings == null ? null : settings.RepairCenterQuoteInboundEmail__c;
    }
}