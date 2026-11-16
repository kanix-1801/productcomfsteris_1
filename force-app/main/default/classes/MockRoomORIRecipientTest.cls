/**
 * @description GC-3483. Covers the recipient row sent from the Submit for Approval screen to the flow.
 */
@IsTest
private class MockRoomORIRecipientTest {

    private static final String EXTERNAL_EMAIL = 'name@company.com';
    private static final String AWARENESS = 'Awareness';

    @IsTest
    static void recipientHoldsExternalAwarenessRow() {
        Test.startTest();
        MockRoomORIRecipient recipient = new MockRoomORIRecipient();
        recipient.email = EXTERNAL_EMAIL;
        recipient.role = AWARENESS;
        recipient.isSalesforceUser = false;
        Test.stopTest();

        Assert.areEqual(EXTERNAL_EMAIL, recipient.email, 'Expected the external email.');
        Assert.areEqual(AWARENESS, recipient.role, 'Expected the awareness role.');
        Assert.isFalse(recipient.isSalesforceUser, 'Expected an external recipient.');
        Assert.isNull(recipient.userId, 'Expected no Salesforce user on an external row.');
    }
}