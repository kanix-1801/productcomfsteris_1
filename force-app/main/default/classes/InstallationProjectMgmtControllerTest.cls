/**
 * @description Test class for installationProjectMgmtController
 */
@isTest
private class InstallationProjectMgmtControllerTest {

    @TestSetup
    static void setupTestData() {
        Account testAccount = buildTestAccount();
        insert testAccount;

        Id subCaseRtId = resolveSubCaseRecordTypeId();

        List<Case> testCases = new List<Case>();
        for (Integer i = 0; i < 3; i++) {
            Case c = new Case(
                Subject = 'Test Case ' + i,
                Description = 'Test Description ' + i,
                Status = 'New',
                Priority = 'Medium',
                AccountId = testAccount.Id
            );
            if (subCaseRtId != null) {
                c.RecordTypeId = subCaseRtId;
            }
            testCases.add(c);
        }
        insert testCases;

        // Create test Project Template
        ProjectTemplate__c testTemplate = new ProjectTemplate__c(
            Name = 'Test Template',
            TemplateDescription__c = 'Test Template Description',
            Active__c = true
        );
        insert testTemplate;

        // Create test Project Template Items
        List<ProjectTemplateItem__c> templateItems = new List<ProjectTemplateItem__c>();
        templateItems.add(new ProjectTemplateItem__c(
            Name = 'Task Item 1',
            ItemNumber__c = 1,
            Type__c = 'Task',
            Duration__c = 5,
            ProjectTemplate__c = testTemplate.Id
        ));
        templateItems.add(new ProjectTemplateItem__c(
            Name = 'Event Item 1',
            ItemNumber__c = 2,
            Type__c = 'Event',
            Duration__c = 3,
            ProjectTemplate__c = testTemplate.Id
        ));
        templateItems.add(new ProjectTemplateItem__c(
            Name = 'Task Item 2',
            ItemNumber__c = 3,
            Type__c = 'Task',
            Duration__c = 7,
            ProjectTemplate__c = testTemplate.Id
        ));
        insert templateItems;
    }

    @isTest
    static void testGetCaseDetailsSuccess() {
        // Get test case
        Case testCase = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        Case result = installationProjectMgmtController.getCaseDetails(testCase.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.CaseNumber);
    }

    @isTest
    static void testGetAccountDetailsSuccess() {
        // Get test account
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Account result = installationProjectMgmtController.getAccountDetails(testAccount.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals('IPM Test Account', result.Name);
    }

    @isTest
    static void testGetProjectTemplatesSuccess() {
        Test.startTest();
        List<ProjectTemplate__c> results = installationProjectMgmtController.getProjectTemplates();
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assertEquals(1, results.size());
        System.assertEquals('Test Template', results[0].Name);
    }

    @isTest
    static void testGetCasesForAccountSuccess() {
        // Get test account
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<Case> results = installationProjectMgmtController.getCasesForAccount(testAccount.Id, null);
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assert(results.size() >= 1, 'Expected at least one case for the test account');
        for (Case c : results) {
            System.assertNotEquals(null, c.CaseNumber);
            System.assertNotEquals(null, c.Subject);
        }
    }

    @isTest
    static void testGetCasesForAccount_excludesCbmWhenNoRegistration() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Id cbmRtId = resolveCaseRecordTypeId('CBMCase');
        Id capitalLineRtId = resolveCaseRecordTypeId('Capital_Line_Sub_Case');
        if (cbmRtId == null) {
            return;
        }

        Case cbmCase = new Case(
            Subject = 'CBM excluded without registration',
            Status = 'New',
            Priority = 'Medium',
            AccountId = testAccount.Id,
            RecordTypeId = cbmRtId
        );
        Case capitalLine = capitalLineRtId == null
            ? null
            : new Case(
                  Subject = 'Capital Line should be excluded',
                  Status = 'New',
                  Priority = 'Medium',
                  AccountId = testAccount.Id,
                  RecordTypeId = capitalLineRtId
              );
        insert capitalLine == null
            ? new List<Case>{ cbmCase }
            : new List<Case>{ cbmCase, capitalLine };

        Test.startTest();
        List<Case> results = InstallationProjectMgmtController.getCasesForAccount(testAccount.Id, null);
        Test.stopTest();

        Set<Id> resultIds = new Map<Id, Case>(results).keySet();
        System.assert(!resultIds.contains(cbmCase.Id), 'CBM cases should not be included when no registration number is provided');
        if (capitalLine != null) {
            System.assert(!resultIds.contains(capitalLine.Id), 'Capital Line Sub Cases should never be included');
        }
    }

    @isTest
    static void testGetCasesForAccount_filtersCbmByRegistrationAndExcludesCapitalLine() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Id cbmRtId = resolveCaseRecordTypeId('CBMCase');
        Id capitalLineRtId = resolveCaseRecordTypeId('Capital_Line_Sub_Case');
        if (cbmRtId == null) {
            return;
        }

        Case unmatchedCbm = new Case(
            Subject = 'CBM without matching registration',
            Status = 'New',
            Priority = 'Medium',
            AccountId = testAccount.Id,
            RecordTypeId = cbmRtId
        );
        Case capitalLine = capitalLineRtId == null
            ? null
            : new Case(
                  Subject = 'Capital Line should be excluded',
                  Status = 'New',
                  Priority = 'Medium',
                  AccountId = testAccount.Id,
                  RecordTypeId = capitalLineRtId
              );
        insert capitalLine == null
            ? new List<Case>{ unmatchedCbm }
            : new List<Case>{ unmatchedCbm, capitalLine };

        Test.startTest();
        List<Case> results = InstallationProjectMgmtController.getCasesForAccount(testAccount.Id, 'REG-MATCH');
        Test.stopTest();

        Set<Id> resultIds = new Map<Id, Case>(results).keySet();
        System.assert(!resultIds.contains(unmatchedCbm.Id), 'CBM cases with a different registration number should be excluded');
        if (capitalLine != null) {
            System.assert(!resultIds.contains(capitalLine.Id), 'Capital Line Sub Cases should never be included');
        }
        System.assert(
            !results.isEmpty(),
            'Service Installation Sub Cases for the account should still be returned when filtering by registration'
        );
    }

    @isTest
    static void testGetCasesForAccount_excludesCancelledCases() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Id subCaseRtId = resolveSubCaseRecordTypeId();

        Case cancelledCase = new Case(
            Subject = 'Cancelled Service Installation',
            Status = 'Cancelled',
            Priority = 'Medium',
            AccountId = testAccount.Id
        );
        if (subCaseRtId != null) {
            cancelledCase.RecordTypeId = subCaseRtId;
        }
        insert cancelledCase;

        Test.startTest();
        List<Case> results = InstallationProjectMgmtController.getCasesForAccount(testAccount.Id, null);
        Test.stopTest();

        Set<Id> resultIds = new Map<Id, Case>(results).keySet();
        System.assert(!resultIds.contains(cancelledCase.Id), 'Cancelled cases should not be available to add to a project');
    }

    private static Id resolveSubCaseRecordTypeId() {
        return resolveCaseRecordTypeId('Service_Installation_Sub_Case');
    }

    private static Account buildTestAccount() {
        Account testAccount = new Account(Name = 'IPM Test Account');
        Map<String, Schema.SObjectField> accountFields = Schema.sObjectType.Account.fields.getMap();
        if (accountFields.containsKey('SystemID__c')) {
            testAccount.put('SystemID__c', 'LEG-IPM-001');
        }
        if (accountFields.containsKey('SourceSystemID__c')) {
            testAccount.put('SourceSystemID__c', 'TEST-ORACLE-IPM');
        }
        if (accountFields.containsKey('CustomerAddressOperatingUnit__c')) {
            testAccount.put('CustomerAddressOperatingUnit__c', '82');
        }
        return testAccount;
    }

    private static Id resolveCaseRecordTypeId(String developerName) {
        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Case' AND DeveloperName = :developerName
            LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    @isTest
    static void testGetTemplateItemsSuccess() {
        // Get test template
        ProjectTemplate__c testTemplate = [SELECT Id FROM ProjectTemplate__c LIMIT 1];

        Test.startTest();
        List<ProjectTemplateItem__c> results = installationProjectMgmtController.getTemplateItems(testTemplate.Id);
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assertEquals(3, results.size());
    }

    @isTest
    static void testCreateProjectSuccess() {
        // Get test data
        Account testAccount = [SELECT Id, OwnerId FROM Account LIMIT 1];
        ProjectTemplate__c testTemplate = [SELECT Id FROM ProjectTemplate__c LIMIT 1];
        List<Case> testCases = [SELECT Id FROM Case LIMIT 2];

        // Create a contact for the Project Contact field
        Contact projectContact = new Contact(FirstName = 'Proj', LastName = 'Contact', AccountId = testAccount.Id);
        insert projectContact;

        // Build project data JSON
        Map<String, Object> projectDataMap = new Map<String, Object>();
        projectDataMap.put('projectName', 'Test Project');
        projectDataMap.put('projectDescription', 'Test Project Description');
        projectDataMap.put('accountId', testAccount.Id);
        projectDataMap.put('ownerId', testAccount.OwnerId);
        projectDataMap.put('projectStartDate', '2024-01-01');
        projectDataMap.put('projectEndDate', '2024-12-31');
        projectDataMap.put('projectShippedDate', '2023-12-15');
        projectDataMap.put('projectRequestedDate', '2023-12-01');
        projectDataMap.put('projectTemplateId', testTemplate.Id);
        projectDataMap.put('projectContactId', projectContact.Id);

        // Add case IDs
        List<String> caseIds = new List<String>();
        for (Case c : testCases) {
            caseIds.add(c.Id);
        }
        projectDataMap.put('caseIds', caseIds);

        // Add items
        List<Map<String, Object>> items = new List<Map<String, Object>>();

        Map<String, Object> taskItem = new Map<String, Object>();
        taskItem.put('Name', 'Test Task');
        taskItem.put('Type__c', 'Task');
        taskItem.put('ItemNumber__c', 1);
        taskItem.put('calculatedStartDate', '2024-01-15');
        taskItem.put('Duration__c', 5);
        items.add(taskItem);

        Map<String, Object> eventItem = new Map<String, Object>();
        eventItem.put('Name', 'Test Event');
        eventItem.put('Type__c', 'Event');
        eventItem.put('ItemNumber__c', 2);
        eventItem.put('calculatedStartDate', '2024-01-20');
        eventItem.put('calculatedEndDate', '2024-01-20');
        eventItem.put('Duration__c', 3);
        items.add(eventItem);

        projectDataMap.put('items', items);

        String projectDataJson = JSON.serialize(projectDataMap);

        Test.startTest();
        Id projectId = installationProjectMgmtController.createProject(projectDataJson);
        Test.stopTest();

        // Verify project was created
        System.assertNotEquals(null, projectId);

        Project__c createdProject = [
            SELECT Id, Name, Account__c, ProjectContact__c, PrimaryCase__c,
                   ProjectShippedDate__c, ProjectRequestedDate__c
            FROM Project__c WHERE Id = :projectId
        ];
        System.assertEquals('Test Project', createdProject.Name);
        System.assertEquals(testAccount.Id, createdProject.Account__c);
        // Verify new contact field persisted
        System.assertEquals(projectContact.Id, createdProject.ProjectContact__c);
        // Verify dates mapped correctly
        System.assertEquals(Date.valueOf('2023-12-15'), createdProject.ProjectShippedDate__c);
        System.assertEquals(Date.valueOf('2023-12-01'), createdProject.ProjectRequestedDate__c);

        // Verify primary case was linked on the project
        System.assertEquals(caseIds[0], createdProject.PrimaryCase__c);

        if (InstallationProjectMgmtController.resolveProjectCasesJunctionType() != null) {
            List<SObject> junctionRows = Database.query(
                'SELECT Id, Case__c FROM ProjectCases__c WHERE Project__c = :projectId WITH USER_MODE'
            );
            System.assertEquals(
                caseIds.size(),
                junctionRows.size(),
                'Each selected case should have a ProjectCases__c junction row'
            );
            Set<Id> linkedCases = new Set<Id>();
            for (SObject row : junctionRows) {
                linkedCases.add((Id) row.get('Case__c'));
            }
            for (String caseIdStr : caseIds) {
                System.assert(linkedCases.contains((Id) caseIdStr), 'Junction should link case ' + caseIdStr);
            }
        }

        // Verify tasks were created
        List<Task> createdTasks = [
            SELECT Id, Subject, ActivityDate, Project__c, TemplateItemNumber__c, ProjectItemSequence__c
            FROM Task
            WHERE Project__c = :projectId
        ];
        System.assertEquals(1, createdTasks.size());
        System.assertEquals('Test Task', createdTasks[0].Subject);
        System.assertEquals(Date.valueOf('2024-01-15'), createdTasks[0].ActivityDate);
        System.assertEquals(1, createdTasks[0].TemplateItemNumber__c);
        System.assertEquals(1, createdTasks[0].ProjectItemSequence__c);

        // Verify events were created
        List<Event> createdEvents = [
            SELECT Id, Subject, ActivityDate, StartDateTime, EndDateTime, Project__c, TemplateItemNumber__c, ProjectItemSequence__c
            FROM Event
            WHERE Project__c = :projectId
        ];
        System.assertEquals(1, createdEvents.size());
        System.assertEquals('Test Event', createdEvents[0].Subject);
        System.assertEquals(Date.valueOf('2024-01-20'), createdEvents[0].ActivityDate);
        System.assertEquals(2, createdEvents[0].TemplateItemNumber__c);
        System.assertEquals(2, createdEvents[0].ProjectItemSequence__c);
    }

    @isTest
    static void testCreateProject_zeroDurationEventUsesTenAmTwoHourSlot() {
        Account testAccount = [SELECT Id, OwnerId FROM Account LIMIT 1];
        ProjectTemplate__c testTemplate = [SELECT Id FROM ProjectTemplate__c LIMIT 1];

        Map<String, Object> projectDataMap = new Map<String, Object>();
        projectDataMap.put('projectName', 'Zero Duration Event Project');
        projectDataMap.put('accountId', testAccount.Id);
        projectDataMap.put('ownerId', testAccount.OwnerId);
        projectDataMap.put('projectStartDate', '2024-06-01');
        projectDataMap.put('projectTemplateId', testTemplate.Id);
        projectDataMap.put('caseIds', new List<String>());

        Map<String, Object> eventItem = new Map<String, Object>();
        eventItem.put('Name', 'Zero Duration Event');
        eventItem.put('Type__c', 'Event');
        eventItem.put('ItemNumber__c', 1);
        eventItem.put('calculatedStartDate', '2024-06-15');
        eventItem.put('Duration__c', 0);
        projectDataMap.put('items', new List<Map<String, Object>>{ eventItem });

        Test.startTest();
        Id projectId = installationProjectMgmtController.createProject(JSON.serialize(projectDataMap));
        Test.stopTest();

        Event createdEvent = [
            SELECT StartDateTime, EndDateTime, ActivityDate
            FROM Event
            WHERE Project__c = :projectId
            LIMIT 1
        ];
        System.assertEquals(Date.valueOf('2024-06-15'), createdEvent.ActivityDate);
        System.assertEquals(
            DateTime.newInstance(Date.valueOf('2024-06-15'), Time.newInstance(10, 0, 0, 0)),
            createdEvent.StartDateTime
        );
        System.assertEquals(createdEvent.StartDateTime.addHours(2), createdEvent.EndDateTime);
    }

    @isTest
    static void testResolveValidatedCaseIds_rejectsInaccessibleCase() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Case inaccessibleCase = new Case(
            Subject = 'Inaccessible Case',
            Status = 'New',
            Priority = 'Medium',
            AccountId = testAccount.Id
        );
        insert inaccessibleCase;

        User limitedUser = createUserWithStandardProfile();
        Id caseIdToValidate = inaccessibleCase.Id;

        // Private Case sharing: another user's Case is not visible. Public Read/Write sharing:
        // Standard User can read any Case, so use a deleted Case Id to exercise the same path.
        Boolean caseVisibleToLimitedUser = isCaseVisibleToUser(inaccessibleCase.Id, limitedUser);
        if (caseVisibleToLimitedUser) {
            delete inaccessibleCase;
        }

        Boolean threw = false;
        System.runAs(limitedUser) {
            try {
                InstallationProjectMgmtController.resolveValidatedCaseIds(
                    new List<String>{ caseIdToValidate }
                );
            } catch (AuraHandledException e) {
                threw = true;
            }
        }

        System.assertEquals(true, threw, 'Expected inaccessible Case validation to fail');
    }

    private static Boolean isCaseVisibleToUser(Id caseId, User runAsUser) {
        Boolean isVisible = false;
        System.runAs(runAsUser) {
            isVisible = ![SELECT Id FROM Case WHERE Id = :caseId WITH USER_MODE].isEmpty();
        }
        return isVisible;
    }

    private static User createUserWithStandardProfile() {
        Profile standardProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        User limitedUser = new User(
            Alias = 'ipmlim',
            Email = 'ipm.limited.user@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Limited',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'ipm.limited.user.' + System.currentTimeMillis() + '@example.com'
        );
        insert limitedUser;
        return limitedUser;
    }

    @isTest
    static void testCreateProject_stringNumericFieldsFromJson() {
        Account testAccount = [SELECT Id, OwnerId FROM Account LIMIT 1];
        ProjectTemplate__c testTemplate = [SELECT Id FROM ProjectTemplate__c LIMIT 1];

        Map<String, Object> projectDataMap = new Map<String, Object>();
        projectDataMap.put('projectName', 'String Numeric Fields Project');
        projectDataMap.put('accountId', testAccount.Id);
        projectDataMap.put('ownerId', testAccount.OwnerId);
        projectDataMap.put('projectStartDate', '2024-07-01');
        projectDataMap.put('projectTemplateId', testTemplate.Id);
        projectDataMap.put('caseIds', new List<String>());

        Map<String, Object> taskItem = new Map<String, Object>();
        taskItem.put('Name', 'String Duration Task');
        taskItem.put('Type__c', 'Task');
        taskItem.put('ItemNumber__c', '1');
        taskItem.put('calculatedStartDate', '2024-07-10');
        taskItem.put('Duration__c', '2');
        projectDataMap.put('items', new List<Map<String, Object>>{ taskItem });

        Test.startTest();
        Id projectId = installationProjectMgmtController.createProject(JSON.serialize(projectDataMap));
        Test.stopTest();

        Task createdTask = [
            SELECT ProjectItemSequence__c
            FROM Task
            WHERE Project__c = :projectId
            LIMIT 1
        ];
        System.assertEquals(
            1,
            Decimal.valueOf(
                ProjectItemSequenceUtil.sequenceToString(createdTask.ProjectItemSequence__c)
            )
        );
    }
}