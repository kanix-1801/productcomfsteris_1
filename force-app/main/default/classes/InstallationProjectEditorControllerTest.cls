@isTest
private class InstallationProjectEditorControllerTest {

    @TestSetup
    static void setupTestData() {
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        // Create a simpler test setup without assuming ProjectTemplate__c exists
        Project__c testProject = new Project__c(
            Name = 'Test Project',
            Account__c = testAccount.Id,
            ProjectStartDate__c = Date.today(),
            ProjectShippedDate__c = Date.today().addDays(30),
            ProjectRequestedDate__c = Date.today().addDays(60)
        );
        insert testProject;

        Task testTask = new Task(
            Subject = 'Test Task',
            Status = 'Open',
            ActivityDate = Date.today(),
            Project__c = testProject.Id,
            WhatId = testProject.Id,
            ProjectItemSequence__c = 1,
            Priority = 'No'
        );
        insert testTask;

        Event testEvent = new Event(
            Subject = 'Test Event',
            ActivityDate = Date.today().addDays(5),
            StartDateTime = DateTime.now().addDays(5),
            EndDateTime = DateTime.now().addDays(8),
            Project__c = testProject.Id,
            WhatId = testProject.Id,
            ProjectItemSequence__c = 2
        );
        insert testEvent;
    }

    @isTest
    static void testGetActiveUsers() {
        Test.startTest();
        List<User> users = InstallationProjectEditorController.getActiveUsers();
        Test.stopTest();

        System.assertNotEquals(null, users);
    }

    @isTest
    static void testGetProjectData() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        Test.startTest();
        InstallationProjectEditorController.ProjectDataWrapper result =
            InstallationProjectEditorController.getProjectData(proj.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(2, result.items.size());
    }

    @isTest
    static void testUpdateProjectItems_UpdateExisting() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Task t = [SELECT Id FROM Task WHERE Project__c = :proj.Id LIMIT 1];
        Event e = [SELECT Id FROM Event WHERE Project__c = :proj.Id LIMIT 1];

        String itemsJson = '[' +
            '{"id":"' + t.Id + '","recordType":"Task","subject":"Updated Task","status":"Open",' +
            '"activityDate":"' + String.valueOf(Date.today().addDays(1)) + '","sequence":1},' +
            '{"id":"' + e.Id + '","recordType":"Event","subject":"Updated Event",' +
            '"activityDate":"' + String.valueOf(Date.today().addDays(6)) + '","sequence":2,"duration":3}' +
            ']';

        Test.startTest();
        String result = InstallationProjectEditorController.updateProjectItems(itemsJson, proj.Id);
        Test.stopTest();

        System.assertEquals('Project items updated successfully', result);
    }

    @isTest
    static void testUpdateProjectItems_CreateNew() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        String itemsJson = '[' +
            '{"id":"temp_1","recordType":"Task","subject":"New Task","status":"Open",' +
            '"activityDate":"' + String.valueOf(Date.today().addDays(10)) + '","sequence":3},' +
            '{"id":"temp_2","recordType":"Event","subject":"New Event","status":"Open",' +
            '"activityDate":"' + String.valueOf(Date.today().addDays(15)) + '","sequence":4,"duration":2}' +
            ']';

        Test.startTest();
        String result = InstallationProjectEditorController.updateProjectItems(itemsJson, proj.Id);
        Test.stopTest();

        System.assertEquals('Project items updated successfully', result);
    }

    @isTest
    static void testGetProjectData_InvalidId() {
        try {
            Test.startTest();
            InstallationProjectEditorController.getProjectData(null);
            Test.stopTest();
            System.assert(false, 'Expected exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
    }

    @isTest
    static void testUpdateProjectItems_InvalidId() {
        try {
            Test.startTest();
            InstallationProjectEditorController.updateProjectItems('[]', null);
            Test.stopTest();
            System.assert(false, 'Expected exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
    }
}