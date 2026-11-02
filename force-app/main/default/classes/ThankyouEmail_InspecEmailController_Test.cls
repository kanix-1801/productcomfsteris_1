@isTest
public class ThankyouEmail_InspecEmailController_Test {

    /**
     * @description Positive Test Case: Verifies controller works when IDs are provided.
     * Fixes naming convention error on Line 64.
     */
    @isTest
    static void testControllerWithBothTargets() {
        // 1. Setup Test Data
        Account testAcc = new Account(Name = 'Test Account');
        insert testAcc;

        Contact testContact = new Contact(
            FirstName = 'Test', 
            LastName = 'Recipient', 
            AccountId = testAcc.Id,
            Email = 'test@example.com'
        );
        insert testContact;

        Project__c testProject = new Project__c(
            Name = 'Test Project'
            // Add other required fields here if necessary
        );
        insert testProject;

        // 2. Start the Test
        Test.startTest();

        // Instantiate the controller
        ThankyouEmail_InspecEmailController controller = new ThankyouEmail_InspecEmailController();
        
        // Simulate Visualforce passing the attributes
        controller.targetId = testProject.Id;
        controller.targetContactId = testContact.Id;

        // 3. Verify 'currentUser' logic
        User currentUser = controller.currentUser;
        System.assertNotEquals(null, currentUser, 'Current User should not be null');

        // 4. Verify 'relatedRec' (Project) logic
        Project__c fetchedProject = controller.relatedRec;
        System.assertNotEquals(null, fetchedProject, 'Project record should not be null');
        System.assertEquals(testProject.Id, fetchedProject.Id, 'Should retrieve the correct Project ID');

        // 5. Verify 'recipientRec' (Contact) logic
        Contact fetchedContact = controller.recipientRec;
        System.assertNotEquals(null, fetchedContact, 'Contact record should not be null');
        System.assertEquals(testContact.Id, fetchedContact.Id, 'Should retrieve the correct Contact ID');

        // 6. Verify Banner URL logic
        String bannerUrl = controller.getSterisBannerURL();
        System.assertNotEquals(null, bannerUrl, 'Banner URL logic should return a string (even if empty)');

        Test.stopTest();
    }

    /**
     * @description Negative Test Case: Verifies controller handles null inputs gracefully.
     * Fixes naming convention error on Line 103.
     */
    @isTest
    static void testControllerWithNullTargets() {
        Test.startTest();

        ThankyouEmail_InspecEmailController controller = new ThankyouEmail_InspecEmailController();
        
        // We do NOT set targetId or targetContactId here (leave them null)

        // Verify Project is null (should not query)
        System.assertEquals(null, controller.relatedRec, 'Project should be null when no ID is passed');

        // Verify Contact is null (should not query)
        System.assertEquals(null, controller.recipientRec, 'Contact should be null when no ID is passed');

        // Verify User is still fetched (does not depend on attributes)
        System.assertNotEquals(null, controller.currentUser, 'Current User should still be fetched');

        Test.stopTest();
    }
}