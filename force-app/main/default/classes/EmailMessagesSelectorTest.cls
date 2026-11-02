/**
 * @description Tests for EmailMessagesSelector (selectByIds and GW-3997 sent-count aggregation).
 * @author STERIS
 */
@IsTest
private class EmailMessagesSelectorTest {
    /**
     * @description Verifies null/empty Id guards return an empty list without querying.
     */
    @IsTest
    static void testSelectByIds_WhenNullOrEmpty_ReturnsEmpty() {
        /********************************************
         * WHEN / THEN
         ********************************************/
        Test.startTest();
        Assert.areEqual(0, EmailMessagesSelector.selectByIds(null).size());
        Assert.areEqual(0, EmailMessagesSelector.selectByIds(new Set<Id>()).size());
        Test.stopTest();
    }

    /**
     * @description Verifies selectByIds returns matching EmailMessage rows with BASE_FIELDS.
     */
    @IsTest
    static void testSelectByIds_WhenIdsProvided_ReturnsMatchingRows() {
        /********************************************
         * SETUP
         ********************************************/
        User contextUser = new User(Id = UserInfo.getUserId());
        adb_EmailMessage builder = new adb_EmailMessage()
            .subject('EMS Select By Id')
            .textBody('Body')
            .setFromId(contextUser.Id)
            .toAddress('ems-selector@example.com');
        System.runAs(contextUser) {
            builder.persist();
        }
        Id emailId = builder.record.Id;

        /********************************************
         * WHEN
         ********************************************/
        Test.startTest();
        List<EmailMessage> rows = EmailMessagesSelector.selectByIds(new Set<Id>{ emailId });
        Test.stopTest();

        /********************************************
         * THEN
         ********************************************/
        Assert.areEqual(1, rows.size(), 'Expected one EmailMessage');
        Assert.areEqual(emailId, rows[0].Id);
        Assert.areEqual('EMS Select By Id', rows[0].Subject);
    }

    /**
     * @description Verifies countSentByParentCaseIds guards and counts Status = 3 emails by Case.
     */
    @IsTest
    static void testCountSentByParentCaseIds_WhenGuardsAndSentEmail_ReturnsCounts() {
        /********************************************
         * SETUP
         ********************************************/
        User contextUser = new User(Id = UserInfo.getUserId());
        adb_Case caseBuilder = new adb_Case().subject('EMS Parent').status('New').origin('Phone');
        System.runAs(contextUser) {
            caseBuilder.persist();
        }
        Id caseId = caseBuilder.record.Id;

        adb_EmailMessage sent = new adb_EmailMessage()
            .subject('Sent')
            .textBody('Sent body')
            .setFromId(contextUser.Id)
            .toAddress('ems-sent@example.com')
            .parent(caseId)
            .status('3');
        System.runAs(contextUser) {
            sent.persist();
        }

        /********************************************
         * WHEN / THEN
         ********************************************/
        Test.startTest();
        Assert.areEqual(0, EmailMessagesSelector.countSentByParentCaseIds(null).size());
        Assert.areEqual(0, EmailMessagesSelector.countSentByParentCaseIds(new Set<Id>()).size());
        Map<Id, Integer> counts = EmailMessagesSelector.countSentByParentCaseIds(new Set<Id>{ caseId });
        Test.stopTest();

        Assert.areEqual(1, counts.size(), 'Expected one Case key');
        Assert.areEqual(1, counts.get(caseId), 'Expected one sent email for the Case');
    }

    @IsTest
    static void testSelectByRelatedToIds_WhenGuards() {
        Test.startTest();
        Assert.areEqual(0, EmailMessagesSelector.selectByRelatedToIds(null).size());
        Assert.areEqual(0, EmailMessagesSelector.selectByRelatedToIds(new Set<Id>()).size());
        Assert.areEqual(0, EmailMessagesSelector.selectByMessageIdentifiers(null).size());
        Assert.areEqual(0, EmailMessagesSelector.selectByMessageIdentifiers(new Set<String>()).size());
        Test.stopTest();
    }
}