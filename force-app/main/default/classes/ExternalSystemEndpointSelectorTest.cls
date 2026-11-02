/**
 * @author PWC Developer
 * @date 2026/07/28
 *
 * @group Generate Quote
 *
 * @description Test class for ExternalSystemEndpointSelector.
 */
@IsTest
private class ExternalSystemEndpointSelectorTest {
    @IsTest
    static void testSelectSalesConnectionUsesTestOverride() {
        ExternalSystemEndpointSelector.testSalesConnectionOverride = new ExternalSystemEndpoint__mdt(
            SalesConnectionBaseUrl__c = 'https://example.test',
            SalesConnectionCreateQuotePath__c = '#create',
            SalesConnectionViewQuotePath__c = '#view'
        );

        Test.startTest();
        ExternalSystemEndpoint__mdt settings = ExternalSystemEndpointSelector.selectSalesConnection();
        Test.stopTest();

        System.assertEquals('https://example.test', settings.SalesConnectionBaseUrl__c);
        System.assertEquals('#create', settings.SalesConnectionCreateQuotePath__c);
        System.assertEquals('#view', settings.SalesConnectionViewQuotePath__c);
    }

    @IsTest
    static void testSelectRepairCenterQuoteEmailUsesTestOverride() {
        ExternalSystemEndpointSelector.testRepairCenterQuoteEmailOverride =
            new ExternalSystemEndpoint__mdt(
                ConnectCareQuoteApprovalUrl__c = 'https://connectcare.test',
                RepairCenterQuoteInboundEmail__c = 'quotes@example.com'
            );

        Test.startTest();
        ExternalSystemEndpoint__mdt settings =
            ExternalSystemEndpointSelector.selectRepairCenterQuoteEmail();
        String url = ExternalSystemEndpointSelector.connectCareQuoteApprovalUrl();
        String inboundEmail = ExternalSystemEndpointSelector.repairCenterQuoteInboundEmail();
        Test.stopTest();

        System.assertEquals('https://connectcare.test', settings.ConnectCareQuoteApprovalUrl__c);
        System.assertEquals('quotes@example.com', settings.RepairCenterQuoteInboundEmail__c);
        System.assertEquals('https://connectcare.test', url);
        System.assertEquals('quotes@example.com', inboundEmail);
    }
}