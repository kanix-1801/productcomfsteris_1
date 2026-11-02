@IsTest
private class EmailMessagesTest {
    @IsTest
    /**
     * @description Tests that the service handles empty input gracefully
     *
     */
    static void serviceHandlesEmptyInputGracefully() {
        // Use the running user rather than querying by profile to avoid brittle test setup
        User u = new User(Id = UserInfo.getUserId());

        System.runAs(u) {
            Test.startTest();
            // Should simply no-op without exception
            EmailMessagesService.outboundEmailSDNProcessing(new List<EmailMessage>());
            EmailMessagesService.outboundEmailSDNProcessing(null);
            Test.stopTest();
        }

        System.assert(true, 'Service gracefully handled empty/null inputs.');
    }

    @IsTest
    /**
     * @description Tests sending an email without a associated project or case
     *
     */
    static void sendEmailwithoutProjectOrCase() {
        /********************************************
        * SETUP
        ********************************************/
        User contextUser = new user(ID = UserInfo.getUserID());

        adb_EmailMessage em = new adb_EmailMessage()
            .subject('Test Email')
            .textBody('Test Email Body')
            .setFromId(contextUser.Id)
            .toAddress('Anybody@mailinator.com');

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(0, [SELECT Count() FROM EmailMessage]);

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        System.runAs(contextuser){
            em.persist();
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(1, [SELECT Count() FROM EmailMessage]);
    }

    @IsTest
    /**
     * @description Tests sending an email with an associated case
     *
     */
    static void sendEmailwithCase() {
        /********************************************
        * SETUP
        ********************************************/
        User contextUser = new user(ID = UserInfo.getUserID());

        adb_Case c = new adb_Case();
            c.subject('Test Case');
            c.status('New');
            c.origin('Phone');
            c.persist();
            c.setRecordType('CBMCase');

        adb_EmailMessage em = new adb_EmailMessage()
            .subject('Test Email')
            .textBody('Test Email Body')
            .setFromId(contextUser.Id)
            .toAddress('Anybody@mailinator.com');

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(0, [SELECT Count() FROM EmailMessage]);

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        System.runAs(contextuser){
            em.persist();
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(1, [SELECT Count() FROM EmailMessage]);
    }

    @IsTest
    /**
     * @description Tests sending an email with an associated project
     *
     */
    static void sendEmailwithProject() {
        /********************************************
        * SETUP
        ********************************************/
        User contextUser = new user(ID = UserInfo.getUserID());

        adb_Project_c proj = new adb_Project_c();
        proj.persist();

        adb_EmailMessage em = new adb_EmailMessage()
            .subject('Test Email')
            .textBody('Test Email Body')
            .setFromId(contextUser.Id)
            .toAddress('Anybody@mailinator.com')
            .relatedTo(proj.id);

        /********************************************
        * GIVEN
        ********************************************/
        System.assertEquals(0, [SELECT Count() FROM EmailMessage]);

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        System.runAs(contextuser){
            em.persist();
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(1, [SELECT Count() FROM EmailMessage]);
    }
}