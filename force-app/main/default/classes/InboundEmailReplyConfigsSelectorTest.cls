/**
 * @description GW-5102 - Coverage for the Repair Center quote reply config selector.
 */
@IsTest
private class InboundEmailReplyConfigsSelectorTest {
    @IsTest
    static void selectRepairCenterQuote_usesOverride() {
        InboundEmailReplyConfigsSelector.configOverride = new InboundEmailReplyConfig__mdt(
            DeveloperName = 'RepairCenterQuote',
            ApproveKeywordList__c = 'Yes',
            RejectKeywordList__c = 'No'
        );

        InboundEmailReplyConfig__mdt config = InboundEmailReplyConfigsSelector.selectRepairCenterQuote();

        Assert.areEqual('RepairCenterQuote', config.DeveloperName);
        Assert.areEqual('Yes', config.ApproveKeywordList__c);
    }

    @IsTest
    static void selectRepairCenterQuote_queriesWithoutOverride() {
        InboundEmailReplyConfig__mdt config = InboundEmailReplyConfigsSelector.selectRepairCenterQuote();

        if (config != null) {
            Assert.areEqual('RepairCenterQuote', config.DeveloperName);
        }
    }
}