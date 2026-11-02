/**
 * Controller and integration coverage for InstallationProjectViewerController.
 * Sequence helper behavior is covered in ProjectItemSequenceUtilTest.
 */
@IsTest
private class InstallationProjectViewerControllerTest {
    private static final String TEST_ACCOUNT_NAME = 'IPM Viewer Test Account';
    private static final String TEST_PROJECT_NAME_PREFIX = 'IPM Viewer Test Proj ';

    @TestSetup
    static void setupTestData() {
        InstallationProjectViewerAccessService.setIgnoreReadOnlyPermissionForTests(true);
        InstallationProjectViewerAccessService.setForceReadOnlyForTests(false);
        if (resolveProjectDescribe() == null) {
            return;
        }
        Account acct = buildTestAccount();
        Database.insert(acct, AccessLevel.SYSTEM_MODE);
        Project__c project = buildTestProject(acct.Id);
        Database.insert(project, AccessLevel.SYSTEM_MODE);
    }

    @IsTest
    static void getProjectItems_nullProject_returnsEmpty() {
        List<InstallationProjectViewerController.ProjectItemRow> rows = InstallationProjectViewerController.getProjectItems(
            null,
            false,
            false
        );
        System.assertEquals(0, rows.size(), 'Null project should return no rows');
    }

    @IsTest
    static void getProjectItems_withProjectId_queriesWithoutError() {
        Id anyId = UserInfo.getUserId();
        List<InstallationProjectViewerController.ProjectItemRow> rows = InstallationProjectViewerController.getProjectItems(
            anyId,
            true,
            true
        );
        System.assertNotEquals(null, rows, 'Result list should not be null');
    }

    @IsTest
    static void getProjectItems_hideFlagsCoerced() {
        Id anyId = UserInfo.getOrganizationId();
        List<InstallationProjectViewerController.ProjectItemRow> r1 = InstallationProjectViewerController.getProjectItems(
            anyId,
            null,
            null
        );
        List<InstallationProjectViewerController.ProjectItemRow> r2 = InstallationProjectViewerController.getProjectItems(
            anyId,
            false,
            false
        );
        System.assertNotEquals(null, r1);
        System.assertNotEquals(null, r2);
    }

    @IsTest
    static void projectItemSequenceComparator_sortsRows() {
        InstallationProjectViewerController.ProjectItemRow a = new InstallationProjectViewerController.ProjectItemRow();
        a.sequence = '2';
        InstallationProjectViewerController.ProjectItemRow b = new InstallationProjectViewerController.ProjectItemRow();
        b.sequence = '10';
        InstallationProjectViewerController.ProjectItemRow c = new InstallationProjectViewerController.ProjectItemRow();
        c.sequence = '2.1';
        List<InstallationProjectViewerController.ProjectItemRow> rows = new List<InstallationProjectViewerController.ProjectItemRow>{
            a,
            b,
            c
        };
        rows.sort(new InstallationProjectViewerController.ProjectItemSequenceComparator());
        System.assertEquals('2', rows[0].sequence);
        System.assertEquals('2.1', rows[1].sequence);
        System.assertEquals('10', rows[2].sequence);
    }

    @IsTest
    static void getStatusPicklistOptions_task_returnsActiveValues() {
        List<InstallationProjectViewerController.PicklistOption> opts = InstallationProjectViewerController.getStatusPicklistOptions(
            'Task'
        );
        System.assertNotEquals(null, opts);
        System.assert(opts.size() > 0, 'Task Status should have at least one active picklist value');
    }

    @IsTest
    static void getStatusPicklistOptions_blank_returnsEmpty() {
        List<InstallationProjectViewerController.PicklistOption> opts = InstallationProjectViewerController.getStatusPicklistOptions(
            ''
        );
        System.assertEquals(0, opts.size());
        opts = InstallationProjectViewerController.getStatusPicklistOptions(null);
        System.assertEquals(0, opts.size());
    }

    @IsTest
    static void getStatusPicklistOptions_unknownObject_returnsEmpty() {
        List<InstallationProjectViewerController.PicklistOption> opts = InstallationProjectViewerController.getStatusPicklistOptions(
            'Account'
        );
        System.assertEquals(0, opts.size());
    }

    @IsTest
    static void getStatusPicklistOptions_event_returnsList() {
        List<InstallationProjectViewerController.PicklistOption> opts = InstallationProjectViewerController.getStatusPicklistOptions(
            'Event'
        );
        System.assertNotEquals(null, opts);
    }

    @IsTest
    static void getInternalUsersPicklist_returnsList() {
        List<InstallationProjectViewerController.PicklistOption> opts = InstallationProjectViewerController.getInternalUsersPicklist();
        System.assertNotEquals(null, opts);
    }

    @IsTest
    static void isReadOnlyInstallationProjectViewer_returnsBoolean() {
        Boolean readOnly = InstallationProjectViewerController.isReadOnlyInstallationProjectViewer();
        System.assertNotEquals(null, readOnly, 'Expected a non-null boolean');
    }

    @IsTest
    static void updateProjectItem_readOnlyUser_throws() {
        InstallationProjectViewerAccessService.setIgnoreReadOnlyPermissionForTests(false);
        InstallationProjectViewerAccessService.setForceReadOnlyForTests(true);
        Boolean threw = false;
        try {
            InstallationProjectViewerController.updateProjectItem(
                UserInfo.getUserId(),
                'Task',
                '',
                null,
                '',
                null
            );
        } catch (AuraHandledException e) {
            threw = true;
            System.assertNotEquals(null, e.getMessage());
        } finally {
            InstallationProjectViewerAccessService.setForceReadOnlyForTests(false);
            InstallationProjectViewerAccessService.setIgnoreReadOnlyPermissionForTests(true);
        }
        System.assert(threw, 'Expected AuraHandledException for read-only user');
    }

    @IsTest
    static void updateProjectItem_invalidRecord_throws() {
        Boolean threw = false;
        try {
            InstallationProjectViewerController.updateProjectItem(null, 'Task', '', null, '', null);
        } catch (AuraHandledException e) {
            threw = true;
            System.assertNotEquals(null, e.getMessage());
        }
        System.assert(threw, 'Expected AuraHandledException for null record');
    }

    @IsTest
    static void updateProjectItem_invalidAssignableOwner_throws() {
        assertTaskHasProjectLookup();
        Id projectId = requireTestProjectId();
        Task t = newTaskOnProject(projectId, '99', 'Owner test', Date.today());
        insertTestTasks(new List<Task>{ t });
        Boolean threw = false;
        try {
            InstallationProjectViewerController.updateProjectItem(
                t.Id,
                'Task',
                null,
                UserInfo.getOrganizationId(),
                String.valueOf(Date.today()),
                null
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Non-user owner Id should fail assignable-user validation');
    }

    @IsTest
    static void updateProjectItem_unsupportedObject_throws() {
        Boolean threw = false;
        try {
            InstallationProjectViewerController.updateProjectItem(
                UserInfo.getUserId(),
                'Contact',
                '',
                null,
                '',
                null
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Expected AuraHandledException for unsupported type');
    }

    @IsTest
    static void createProjectSubline_missingParams_throws() {
        Boolean threw = false;
        try {
            InstallationProjectViewerController.createProjectSubline(null, '1', UserInfo.getUserId(), 'Task');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Expected AuraHandledException');
    }

    @IsTest
    static void insertProjectRootLineAfterAndShift_missingParams_throws() {
        Boolean threw = false;
        try {
            InstallationProjectViewerController.insertProjectRootLineAfterAndShift(
                null,
                '1',
                UserInfo.getUserId(),
                'Task'
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Expected AuraHandledException');
    }

    /**
     * When Project__c and related fields exist, exercise getProjectItems, updateProjectItem, and line-creation APIs.
     * Skips gracefully when org metadata or permissions prevent inserts.
     */
    @IsTest
    static void integration_projectLines_whenProjectAvailable() {
        assertTaskHasProjectLookup();
        Id projectId = requireTestProjectId();

        Task t = newTaskOnProject(projectId, '1', 'Int Task', Date.today().addDays(7));
        insertTestTasks(new List<Task>{ t });
        t = [SELECT Id, Status, ActivityDate FROM Task WHERE Id = :t.Id];

        List<InstallationProjectViewerController.ProjectItemRow> rows = InstallationProjectViewerController.getProjectItems(
            projectId,
            false,
            false
        );
        System.assert(rows.size() >= 1, 'Should load inserted task');

        Test.startTest();
        InstallationProjectViewerController.updateProjectItem(
            t.Id,
            'Task',
            t.Status != null ? t.Status : 'Not Started',
            UserInfo.getUserId(),
            String.valueOf(t.ActivityDate),
            'Updated title'
        );
        Test.stopTest();

        Task afterT = [
            SELECT Subject, ActivityDate
            FROM Task
            WHERE Id = :t.Id
        ];
        System.assertEquals('Updated title', afterT.Subject);

        if (Schema.sObjectType.Event.isCreateable() && eventHasProjectLookup()) {
            try {
                Id evtId = InstallationProjectViewerController.createProjectSubline(
                    projectId,
                    '1',
                    t.Id,
                    'Task'
                );
                System.assertNotEquals(null, evtId);
            } catch (AuraHandledException e) {
                assertTestFailure('createProjectSubline should succeed when Event is createable', e);
            }
        }
    }

    @IsTest
    static void insertNewFirstRootLineAndShift_missingParams_throws() {
        Boolean threw = false;
        try {
            InstallationProjectViewerController.insertNewFirstRootLineAndShift(
                null,
                '1',
                UserInfo.getUserId(),
                'Task'
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Expected AuraHandledException');
    }

    @IsTest
    static void insertNewFirstRootLineAndShift_notLineOne_throws() {
        Id projectId = requireTestProjectId();
        assertTaskHasProjectLookup();
        Task anchor = newTaskOnProject(projectId, '2', 'Line 2', Date.today());
        insertTestTasks(new List<Task>{ anchor });
        Boolean threw = false;
        try {
            InstallationProjectViewerController.insertNewFirstRootLineAndShift(
                projectId,
                '2',
                anchor.Id,
                'Task'
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Only line 1 should be allowed');
    }

    @IsTest
    static void integration_insertNewFirstRootLine_renumbersAndInsertsEvent() {
        Id projectId = requireTestProjectId();
        assertTaskHasProjectLookup();
        assertEventProjectLineSupport();
        Task t1 = newTaskOnProject(projectId, '1', 'First', Date.today());
        Task t2 = newTaskOnProject(projectId, '2', 'Second', Date.today());
        insertTestTasks(new List<Task>{ t1, t2 });

        Id newId;
        try {
            newId = InstallationProjectViewerController.insertNewFirstRootLineAndShift(
                projectId,
                '1',
                t1.Id,
                'Task'
            );
        } catch (AuraHandledException e) {
            assertTestFailure('Controller call should succeed in test org', e);
        }
        System.assertNotEquals(null, newId);
        Task t1After = [SELECT ProjectItemSequence__c FROM Task WHERE Id = :t1.Id];
        Task t2After = [SELECT ProjectItemSequence__c FROM Task WHERE Id = :t2.Id];
        System.assertEquals(Decimal.valueOf(2), firstSegmentAsDecimal(t1After.get('ProjectItemSequence__c')), 'Old line 1 becomes 2');
        System.assertEquals(Decimal.valueOf(3), firstSegmentAsDecimal(t2After.get('ProjectItemSequence__c')), 'Old line 2 becomes 3');
        Event inserted = [
            SELECT ProjectItemSequence__c, StartDateTime, EndDateTime
            FROM Event
            WHERE Id = :newId
        ];
        System.assertEquals(Decimal.valueOf(1), firstSegmentAsDecimal(inserted.get('ProjectItemSequence__c')), 'New row is root 1');
        System.assertEquals(inserted.StartDateTime.addHours(2), inserted.EndDateTime, 'New event is 2 hours');
        System.assertEquals(10, inserted.StartDateTime.hour(), 'New event starts at 10:00');
    }

    @IsTest
    static void insertProjectRootLineAfterAndShift_invalidAnchorSequence_throws() {
        Id projectId = requireTestProjectId();
        assertTaskHasProjectLookup();
        Task anchor = newTaskOnProject(projectId, '2', 'Anchor', Date.today());
        insertTestTasks(new List<Task>{ anchor });
        Boolean threw = false;
        try {
            InstallationProjectViewerController.insertProjectRootLineAfterAndShift(
                projectId,
                'not-a-number',
                anchor.Id,
                'Task'
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Invalid root segment should throw');
    }

    @IsTest
    static void createProjectSubline_blankParentSequence_throws() {
        Id projectId = requireTestProjectId();
        assertTaskHasProjectLookup();
        Task anchor = newTaskOnProject(projectId, '1', 'Anchor', Date.today());
        insertTestTasks(new List<Task>{ anchor });
        Boolean threw = false;
        try {
            InstallationProjectViewerController.createProjectSubline(projectId, '   ', anchor.Id, 'Task');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Blank parent sequence should throw');
    }

    @IsTest
    static void integration_getProjectItems_hideCompletedAndPastDue_tasks() {
        Id projectId = requireTestProjectId();
        assertTaskHasProjectLookup();
        Task openFuture = newTaskOnProject(projectId, '10', 'Open future', Date.today().addDays(14));
        Task pastOpen = newTaskOnProject(projectId, '11', 'Past open', Date.today().addDays(-10));
        insertTestTasks(new List<Task>{ openFuture, pastOpen });

        String closedSt = firstClosedLikeTaskStatusValue();
        Task completedLike;
        if (String.isNotBlank(closedSt)) {
            completedLike = newTaskOnProject(projectId, '12', 'Done row', Date.today().addDays(3));
            completedLike.Status = closedSt;
            insertTestTasks(new List<Task>{ completedLike });
        }

        List<InstallationProjectViewerController.ProjectItemRow> allRows = InstallationProjectViewerController.getProjectItems(
            projectId,
            false,
            false
        );
        System.assert(allRows.size() >= 2, 'Inserted tasks should load');

        List<InstallationProjectViewerController.ProjectItemRow> hidePast = InstallationProjectViewerController.getProjectItems(
            projectId,
            false,
            true
        );
        Set<Id> hidePastIds = rowIds(hidePast);
        System.assert(!hidePastIds.contains(pastOpen.Id), 'Past-due task should be hidden');
        System.assert(hidePastIds.contains(openFuture.Id), 'Future task should remain');

        if (completedLike != null) {
            System.assert(allRows.size() >= 3, 'Completed row should appear without hideCompleted');
            List<InstallationProjectViewerController.ProjectItemRow> hideDone = InstallationProjectViewerController.getProjectItems(
                projectId,
                true,
                false
            );
            Set<Id> hideDoneIds = rowIds(hideDone);
            System.assert(!hideDoneIds.contains(completedLike.Id), 'Completed/closed task should be hidden');
            System.assert(hideDoneIds.contains(openFuture.Id), 'Open future should remain');
            System.assert(hideDoneIds.contains(pastOpen.Id), 'Past but open should remain when only hiding completed');

            List<InstallationProjectViewerController.ProjectItemRow> both = InstallationProjectViewerController.getProjectItems(
                projectId,
                true,
                true
            );
            Set<Id> bothIds = rowIds(both);
            System.assert(!bothIds.contains(completedLike.Id), 'Completed hidden');
            System.assert(!bothIds.contains(pastOpen.Id), 'Past due hidden');
            System.assert(bothIds.contains(openFuture.Id), 'Future open remains');
        }
    }

    @IsTest
    static void integration_taskDueDateCascade_updatesDescendantTasks() {
        Id projectId = requireTestProjectId();
        assertTaskHasProjectLookup();
        Date parentDate = Date.today().addDays(5);
        Date childDate = Date.today().addDays(20);
        Date newParentDate = Date.today().addDays(30);
        Task parentT = newTaskOnProject(projectId, '1', 'Parent line', parentDate);
        Task childT = newTaskOnProject(projectId, '1.1', 'Child line', childDate);
        insertTestTasks(new List<Task>{ parentT, childT });

        InstallationProjectViewerController.updateProjectItem(
            parentT.Id,
            'Task',
            null,
            null,
            String.valueOf(newParentDate),
            null
        );
        Task childAfter = [SELECT ActivityDate FROM Task WHERE Id = :childT.Id];
        System.assertEquals(newParentDate, childAfter.ActivityDate, 'Descendant task due date should cascade');
    }

    /**
     * Main-line Task due date moves shift later open lines; sub-line edits do not shift later roots.
     */
    @IsTest
    static void integration_updateMainTask_dueDateShiftsLaterLines_notSubline() {
        Id projectId = requireTestProjectId();
        assertTaskHasProjectLookup();
        Date base = Date.today().addDays(15);
        Task line2 = newTaskOnProject(projectId, '2', 'Main line 2', base);
        Task line21 = newTaskOnProject(projectId, '2.1', 'Sub 2.1', base.addDays(1));
        Task line3 = newTaskOnProject(projectId, '3', 'Main line 3', base.addDays(5));
        insertTestTasks(new List<Task>{ line2, line21, line3 });

        InstallationProjectViewerController.updateProjectItem(
            line2.Id,
            'Task',
            null,
            null,
            String.valueOf(base.addDays(2)),
            null
        );
        Task line3After = [SELECT ActivityDate FROM Task WHERE Id = :line3.Id];
        System.assertEquals(
            base.addDays(7),
            line3After.ActivityDate,
            'Later main line shifts when an earlier main Task line moves'
        );

        Date subBase = Date.today().addDays(25);
        Task sub2 = newTaskOnProject(projectId, '4', 'Main 4', subBase);
        Task sub41 = newTaskOnProject(projectId, '4.1', 'Sub 4.1', subBase);
        Task sub5 = newTaskOnProject(projectId, '5', 'Main 5', subBase.addDays(4));
        insertTestTasks(new List<Task>{ sub2, sub41, sub5 });

        InstallationProjectViewerController.updateProjectItem(
            sub41.Id,
            'Task',
            null,
            null,
            String.valueOf(subBase.addDays(3)),
            null
        );
        Task sub5After = [SELECT ActivityDate FROM Task WHERE Id = :sub5.Id];
        System.assertEquals(
            subBase.addDays(4),
            sub5After.ActivityDate,
            'Later main line must not shift when only a sub-line Task date changes'
        );
    }

    @IsTest
    static void integration_createSubline_nextSuffixAndQueryEvents() {
        Id projectId = requireTestProjectId();
        assertTaskHasProjectLookup();
        assertEventProjectLineSupport();
        Task parentRow = newTaskOnProject(projectId, '5', 'Parent five', Date.today().addDays(2));
        Task existingChild = newTaskOnProject(projectId, '5.1', 'Existing child', Date.today().addDays(2));
        insertTestTasks(new List<Task>{ parentRow, existingChild });

        Id newSubId;
        try {
            newSubId = InstallationProjectViewerController.createProjectSubline(
                projectId,
                '5',
                parentRow.Id,
                'Task'
            );
        } catch (AuraHandledException e) {
            assertTestFailure('Controller call should succeed in test org', e);
        }
        System.assertNotEquals(null, newSubId);
        Task created = [
            SELECT ProjectItemSequence__c
            FROM Task
            WHERE Id = :newSubId
        ];
        System.assertEquals(Decimal.valueOf(5), firstSegmentAsDecimal(created.get('ProjectItemSequence__c')), 'Same parent root');
        System.assertEquals(
            Decimal.valueOf(2),
            secondSegmentAsDecimal(created.get('ProjectItemSequence__c')),
            'Next direct child suffix after 5.1 should be 5.2'
        );
    }

    @IsTest
    static void integration_insertRootLineAfter_shiftsSequencesAndInserts() {
        Id projectId = requireTestProjectId();
        assertTaskHasProjectLookup();
        assertEventProjectLineSupport();
        Task t2 = newTaskOnProject(projectId, '2', 'Line 2', Date.today());
        Task t3 = newTaskOnProject(projectId, '3', 'Line 3', Date.today());
        Task t4 = newTaskOnProject(projectId, '4', 'Line 4', Date.today());
        insertTestTasks(new List<Task>{ t2, t3, t4 });

        Id newId;
        try {
            newId = InstallationProjectViewerController.insertProjectRootLineAfterAndShift(
                projectId,
                '2',
                t2.Id,
                'Task'
            );
        } catch (AuraHandledException e) {
            assertTestFailure('Controller call should succeed in test org', e);
        }
        System.assertNotEquals(null, newId);
        Task t3After = [SELECT ProjectItemSequence__c FROM Task WHERE Id = :t3.Id];
        Task t4After = [SELECT ProjectItemSequence__c FROM Task WHERE Id = :t4.Id];
        System.assertEquals(Decimal.valueOf(4), firstSegmentAsDecimal(t3After.get('ProjectItemSequence__c')), 'Root 3 becomes 4');
        System.assertEquals(Decimal.valueOf(5), firstSegmentAsDecimal(t4After.get('ProjectItemSequence__c')), 'Root 4 becomes 5');
        Event inserted = [SELECT ProjectItemSequence__c FROM Event WHERE Id = :newId];
        System.assertEquals(Decimal.valueOf(3), firstSegmentAsDecimal(inserted.get('ProjectItemSequence__c')), 'New root fills gap at 3');
    }

    @IsTest
    static void integration_insertRootLineAfter_preservesTemplateItemNumber() {
        System.assert(
            ProjectItemSequenceUtil.hasTemplateItemNumberField(Task.SObjectType),
            'Task.TemplateItemNumber__c is required for template preservation tests'
        );
        Id projectId = requireTestProjectId();
        assertTaskHasProjectLookup();
        assertEventProjectLineSupport();
        Task t2 = newTaskOnProject(projectId, '2', 'Line 2', Date.today());
        ProjectItemSequenceUtil.putTemplateItemNumber(t2, 2);
        Task t3 = newTaskOnProject(projectId, '3', 'Line 3', Date.today());
        ProjectItemSequenceUtil.putTemplateItemNumber(t3, 3);
        insertTestTasks(new List<Task>{ t2, t3 });

        try {
            InstallationProjectViewerController.insertProjectRootLineAfterAndShift(
                projectId,
                '2',
                t2.Id,
                'Task'
            );
        } catch (AuraHandledException e) {
            assertTestFailure('Controller call should succeed in test org', e);
        }

        Task t3After = [
            SELECT ProjectItemSequence__c, TemplateItemNumber__c
            FROM Task
            WHERE Id = :t3.Id
        ];
        System.assertEquals(
            Decimal.valueOf(4),
            firstSegmentAsDecimal(t3After.get('ProjectItemSequence__c')),
            'Display sequence shifts'
        );
        System.assertEquals(3, t3After.TemplateItemNumber__c, 'Template item number stays frozen');
    }

    @IsTest
    static void integration_getProjectItems_events_hidePastDue() {
        Id projectId = requireTestProjectId();
        assertEventProjectLineSupport();
        Datetime pastEnd = Datetime.now().addDays(-3);
        Datetime futureEnd = Datetime.now().addDays(10);
        Event evPast = newEventOnProject(projectId, '20', 'Past evt', pastEnd.addHours(-2), pastEnd);
        Event evFuture = newEventOnProject(projectId, '21', 'Future evt', futureEnd.addHours(-3), futureEnd);
        try {
            insertTestEvents(new List<Event>{ evPast, evFuture });
        } catch (Exception e) {
            assertTestFailure('Test data insert should succeed in test org', e);
        }

        List<InstallationProjectViewerController.ProjectItemRow> noFilter = InstallationProjectViewerController.getProjectItems(
            projectId,
            false,
            false
        );
        Set<Id> allIds = rowIds(noFilter);
        System.assert(allIds.contains(evPast.Id) && allIds.contains(evFuture.Id), 'Both events visible without filter');

        List<InstallationProjectViewerController.ProjectItemRow> hidePast = InstallationProjectViewerController.getProjectItems(
            projectId,
            false,
            true
        );
        Set<Id> hp = rowIds(hidePast);
        System.assert(!hp.contains(evPast.Id), 'Past end should hide event');
        System.assert(hp.contains(evFuture.Id), 'Future event remains');
    }

    @IsTest
    static void integration_updateEvent_dueDateTriggersCascade() {
        Id projectId = requireTestProjectId();
        assertTaskHasProjectLookup();
        assertEventProjectLineSupport();
        Datetime anchorEnd = Datetime.newInstance(Date.today().addDays(1), Time.newInstance(14, 0, 0, 0));
        Event parentEv = newEventOnProject(projectId, '7', 'Parent evt', anchorEnd.addHours(-2), anchorEnd);
        Task childT = newTaskOnProject(projectId, '7.1', 'Under event parent', Date.today().addDays(50));
        try {
            insertTestEvents(new List<Event>{ parentEv });
            insertTestTasks(new List<Task>{ childT });
        } catch (Exception e) {
            assertTestFailure('Test data insert should succeed in test org', e);
        }
        Date newEndDate = Date.today().addDays(8);
        InstallationProjectViewerController.updateProjectItem(
            parentEv.Id,
            'Event',
            null,
            null,
            String.valueOf(newEndDate),
            'Renamed evt'
        );
        Event pe = [SELECT Subject, EndDateTime FROM Event WHERE Id = :parentEv.Id];
        System.assertEquals('Renamed evt', pe.Subject);
        Task childAfter = [SELECT ActivityDate FROM Task WHERE Id = :childT.Id];
        System.assertEquals(newEndDate, childAfter.ActivityDate, 'Task descendant of Event parent should cascade');
    }

    /**
     * Ad-hoc date edits shift later ad-hoc lines only; template-backed rows (TemplateItemNumber__c) are left unchanged.
     */
    @IsTest
    static void integration_updateEvent_dueDateDoesNotShiftTemplateBackedLines() {
        System.assert(
            ProjectItemSequenceUtil.hasTemplateItemNumberField(Event.SObjectType),
            'Event.TemplateItemNumber__c is required for template cascade tests'
        );
        Id projectId = requireTestProjectId();
        assertEventProjectLineSupport();
        Date base = Date.today().addDays(30);
        Datetime adHocEnd = Datetime.newInstance(base, Time.newInstance(10, 0, 0, 0));
        Event adHoc = newEventOnProject(projectId, '2', 'Ad hoc evt', adHocEnd, adHocEnd.addHours(2));
        Datetime templateEnd = Datetime.newInstance(base.addDays(5), Time.newInstance(10, 0, 0, 0));
        Event templateEvt = newEventOnProject(
            projectId,
            '3',
            'Template evt',
            templateEnd,
            templateEnd.addHours(2)
        );
        ProjectItemSequenceUtil.putTemplateItemNumber(templateEvt, 3);
        try {
            insertTestSObjects(new List<SObject>{ adHoc, templateEvt });
        } catch (Exception e) {
            assertTestFailure('Test data insert should succeed in test org', e);
        }
        Date originalTemplateDue = templateEnd.date();
        Date newAdHocDue = base.addDays(2);
        try {
            InstallationProjectViewerController.updateProjectItem(
                adHoc.Id,
                'Event',
                null,
                null,
                String.valueOf(newAdHocDue),
                null
            );
        } catch (AuraHandledException e) {
            assertTestFailure('Controller call should succeed in test org', e);
        }
        Event templateAfter = [SELECT EndDateTime FROM Event WHERE Id = :templateEvt.Id];
        System.assertEquals(
            originalTemplateDue,
            templateAfter.EndDateTime.date(),
            'Template-backed event must not shift when an earlier ad-hoc line is edited'
        );
    }

    /**
     * Template-backed anchor edits shift only later template-backed lines; ad-hoc lines stay put.
     */
    @IsTest
    static void integration_updateTemplateEvent_shiftsOnlyTemplateBackedLaterLines() {
        System.assert(
            ProjectItemSequenceUtil.hasTemplateItemNumberField(Event.SObjectType),
            'Event.TemplateItemNumber__c is required for template cascade tests'
        );
        Id projectId = requireTestProjectId();
        assertEventProjectLineSupport();
        Date base = Date.today().addDays(40);
        Datetime anchorEnd = Datetime.newInstance(base, Time.newInstance(10, 0, 0, 0));
        Event templateAnchor = newEventOnProject(
            projectId,
            '5',
            'Template line 5',
            anchorEnd,
            anchorEnd.addHours(2)
        );
        ProjectItemSequenceUtil.putTemplateItemNumber(templateAnchor, 5);
        Datetime adHocEnd = Datetime.newInstance(base.addDays(3), Time.newInstance(10, 0, 0, 0));
        Event adHocLater = newEventOnProject(
            projectId,
            '6',
            'Ad hoc between',
            adHocEnd,
            adHocEnd.addHours(2)
        );
        Datetime laterTemplateEnd = Datetime.newInstance(base.addDays(10), Time.newInstance(10, 0, 0, 0));
        Event templateLater = newEventOnProject(
            projectId,
            '7',
            'Template line 7',
            laterTemplateEnd,
            laterTemplateEnd.addHours(2)
        );
        ProjectItemSequenceUtil.putTemplateItemNumber(templateLater, 7);
        try {
            insertTestSObjects(new List<SObject>{ templateAnchor, adHocLater, templateLater });
        } catch (Exception e) {
            assertTestFailure('Test data insert should succeed in test org', e);
        }
        Date originalAdHocDue = adHocEnd.date();
        Date newAnchorDue = base.addDays(2);
        try {
            InstallationProjectViewerController.updateProjectItem(
                templateAnchor.Id,
                'Event',
                null,
                null,
                String.valueOf(newAnchorDue),
                null
            );
        } catch (AuraHandledException e) {
            assertTestFailure('Controller call should succeed in test org', e);
        }
        Event adHocAfter = [SELECT EndDateTime FROM Event WHERE Id = :adHocLater.Id];
        Event templateLaterAfter = [SELECT EndDateTime FROM Event WHERE Id = :templateLater.Id];
        System.assertEquals(
            originalAdHocDue,
            adHocAfter.EndDateTime.date(),
            'Ad-hoc line must not shift when a template-backed anchor is edited'
        );
        System.assertEquals(
            base.addDays(12),
            templateLaterAfter.EndDateTime.date(),
            'Later template-backed line shifts by same delta as anchor'
        );
    }

    /**
     * Moving an Event due date forward by N days shifts every open Task/Event with a later sequence by N days.
     * Descendants of the edited line are excluded (handled by cascade to the anchor date).
     */
    @IsTest
    static void integration_updateEvent_dueDateShiftsLaterSequences() {
        Id projectId = requireTestProjectId();
        assertTaskHasProjectLookup();
        assertEventProjectLineSupport();
        Date base = Date.today().addDays(20);
        Datetime ev2End = Datetime.newInstance(base, Time.newInstance(15, 0, 0, 0));
        Event ev2 = newEventOnProject(projectId, '2', 'Line 2 evt', ev2End.addHours(-2), ev2End);
        Datetime ev3End = Datetime.newInstance(base.addDays(5), Time.newInstance(16, 0, 0, 0));
        Event ev3 = newEventOnProject(projectId, '3', 'Line 3 evt', ev3End.addHours(-2), ev3End);
        Task t31 = newTaskOnProject(projectId, '3.1', 'Under line 3', base.addDays(6));
        try {
            insertTestSObjects(new List<SObject>{ ev2, ev3 });
            insertTestTasks(new List<Task>{ t31 });
        } catch (Exception e) {
            assertTestFailure('Test data insert should succeed in test org', e);
        }
        Date newLine2Date = base.addDays(2);
        InstallationProjectViewerController.updateProjectItem(
            ev2.Id,
            'Event',
            null,
            null,
            String.valueOf(newLine2Date),
            null
        );
        Event ev2After = [SELECT EndDateTime FROM Event WHERE Id = :ev2.Id];
        System.assertEquals(newLine2Date, ev2After.EndDateTime.date());
        Event ev3After = [SELECT EndDateTime FROM Event WHERE Id = :ev3.Id];
        System.assertEquals(base.addDays(7), ev3After.EndDateTime.date(), 'Later root event shifts by same delta');
        Task t31After = [SELECT ActivityDate FROM Task WHERE Id = :t31.Id];
        System.assertEquals(
            base.addDays(8),
            t31After.ActivityDate,
            'Open task under later line shifts by same delta'
        );
    }

    @IsTest
    static void integration_eventCompleted_hiddenWhenCustomFields() {
        Id projectId = requireTestProjectId();
        assertEventProjectLineSupport();
        Map<String, Schema.SObjectField> efm = Schema.SObjectType.Event.fields.getMap();
        Datetime endDt = Datetime.now().addDays(4);
        Event ev = newEventOnProject(projectId, '30', 'Status evt', endDt.addHours(-1), endDt);
        if (efm.containsKey('completed__c')) {
            Schema.DisplayType dt = efm.get('completed__c').getDescribe().getType();
            if (dt == Schema.DisplayType.BOOLEAN) {
                ev.put('Completed__c', true);
            } else if (dt == Schema.DisplayType.STRING || dt == Schema.DisplayType.TEXTAREA) {
                ev.put('Completed__c', 'true');
            }
        } else if (efm.containsKey('status__c')) {
            String st = firstEventStatusPicklistThatLooksCompleted();
            System.assert(
                String.isNotBlank(st),
                'Event.Status__c needs a completed-like picklist value for hide-completed coverage'
            );
            ev.put('Status__c', st);
        }
        try {
            insertTestEvents(new List<Event>{ ev });
        } catch (Exception e) {
            assertTestFailure('Test data insert should succeed in test org', e);
        }
        Boolean canTreatComplete =
            efm.containsKey('completed__c') ||
            (efm.containsKey('status__c') && String.isNotBlank((String) ev.get('Status__c')));
        System.assert(
            canTreatComplete,
            'Event needs Completed__c or Status__c to test hide-completed filtering'
        );
        List<InstallationProjectViewerController.ProjectItemRow> rows = InstallationProjectViewerController.getProjectItems(
            projectId,
            true,
            false
        );
        Set<Id> ids = rowIds(rows);
        System.assert(!ids.contains(ev.Id), 'Completed event should be filtered when hideCompleted');
    }

    /**
     * All-day Event descendant: exercises applyCascadeTargetDateToEvent all-day branch (ActivityDate).
     */
    @IsTest
    static void integration_allDayEventCascade_updatesActivityDate() {
        assertTaskHasProjectLookup();
        assertEventProjectLineSupport();
        Id projectId = requireTestProjectId();
        Task parentLine = newTaskOnProject(projectId, '8', 'All-day parent', Date.today().addDays(2));
        insertTestTasks(new List<Task>{ parentLine });
        Date childDay = Date.today().addDays(9);
        Datetime allDayStart = Datetime.newInstanceGmt(childDay.year(), childDay.month(), childDay.day(), 0, 0, 0);
        Datetime allDayEnd = allDayStart.addDays(1);
        Event allDayChild = new Event();
        allDayChild.Subject = 'All-day child';
        allDayChild.OwnerId = UserInfo.getUserId();
        allDayChild.IsAllDayEvent = true;
        allDayChild.ActivityDate = childDay;
        allDayChild.StartDateTime = allDayStart;
        allDayChild.EndDateTime = allDayEnd;
        allDayChild.put('Project__c', projectId);
        applyIpmEventRecordTypeIfAvailable(allDayChild);
        applyDefaultEventTypeIfRequired(allDayChild);
        putProjectItemSequenceField(allDayChild, '8.1');
        insertTestEvents(new List<Event>{ allDayChild });
        Date newParent = Date.today().addDays(20);
        InstallationProjectViewerController.updateProjectItem(
            parentLine.Id,
            'Task',
            null,
            null,
            String.valueOf(newParent),
            null
        );
        Event childReload = [SELECT ActivityDate FROM Event WHERE Id = :allDayChild.Id];
        System.assertEquals(newParent, childReload.ActivityDate, 'All-day descendant should cascade ActivityDate');
    }

    @IsTest
    static void integration_taskCascade_timedEventDescendant_movesEndDate() {
        assertTaskHasProjectLookup();
        assertEventProjectLineSupport();
        Id projectId = requireTestProjectId();
        Task parentLine = newTaskOnProject(projectId, '9', 'Cascade parent nine', Date.today().addDays(4));
        insertTestTasks(new List<Task>{ parentLine });
        Datetime childStart = Datetime.newInstance(Date.today().addDays(9), Time.newInstance(10, 0, 0, 0));
        Datetime childEnd = Datetime.newInstance(Date.today().addDays(9), Time.newInstance(11, 30, 0, 0));
        Event timedChild = newEventOnProject(projectId, '9.1', 'Timed child', childStart, childEnd);
        insertTestEvents(new List<Event>{ timedChild });
        Date newParent = Date.today().addDays(15);
        InstallationProjectViewerController.updateProjectItem(
            parentLine.Id,
            'Task',
            null,
            null,
            String.valueOf(newParent),
            null
        );
        Event childReload = [SELECT EndDateTime FROM Event WHERE Id = :timedChild.Id];
        System.assertEquals(newParent, childReload.EndDateTime.date(), 'Timed descendant end date should cascade to parent calendar day');
    }

    private static void prepareEditableIntegrationTest() {
        InstallationProjectViewerAccessService.setIgnoreReadOnlyPermissionForTests(true);
        InstallationProjectViewerAccessService.setForceReadOnlyForTests(false);
    }

    private static void assertTestFailure(String message, Exception e) {
        String detail = e != null && String.isNotBlank(e.getMessage()) ? e.getMessage() : String.valueOf(e);
        System.assert(false, message + (String.isNotBlank(detail) ? ': ' + detail : ''));
    }

    /**
     * Project__c from @TestSetup, created on demand if missing (deployment orgs may skip or roll back setup).
     */
    private static Id requireTestProjectId() {
        prepareEditableIntegrationTest();
        System.assert(resolveProjectDescribe() != null, 'Project__c must exist in this org');
        List<Account> testAccounts = [
            SELECT Id
            FROM Account
            WHERE Name = :TEST_ACCOUNT_NAME
            LIMIT 1
        ];
        if (testAccounts.isEmpty()) {
            Account acct = buildTestAccount();
            Database.insert(acct, AccessLevel.SYSTEM_MODE);
            testAccounts = new List<Account>{ acct };
        }
        List<Project__c> projects = [
            SELECT Id
            FROM Project__c
            WHERE Account__c = :testAccounts[0].Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (projects.isEmpty()) {
            Project__c project = buildTestProject(testAccounts[0].Id);
            Database.insert(project, AccessLevel.SYSTEM_MODE);
            return project.Id;
        }
        return projects[0].Id;
    }

    private static Schema.DescribeSObjectResult resolveProjectDescribe() {
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        if (gd.containsKey('Project__c')) {
            return gd.get('Project__c').getDescribe();
        }
        for (String key : gd.keySet()) {
            if (key != null && key.endsWithIgnoreCase('Project__c')) {
                return gd.get(key).getDescribe();
            }
        }
        return null;
    }

    private static void insertTestTasks(List<Task> tasks) {
        Database.insert(tasks, AccessLevel.SYSTEM_MODE);
    }

    private static void insertTestEvents(List<Event> events) {
        Database.insert(events, AccessLevel.SYSTEM_MODE);
    }

    private static void insertTestSObjects(List<SObject> records) {
        Database.insert(records, AccessLevel.SYSTEM_MODE);
    }

    private static void assertTaskHasProjectLookup() {
        System.assert(
            Schema.SObjectType.Task.fields.getMap().containsKey('project__c'),
            'Task.Project__c is required for Installation Project Viewer tests'
        );
    }

    private static void assertEventProjectLineSupport() {
        System.assert(eventHasProjectLookup(), 'Event.Project__c is required for Installation Project Viewer tests');
        System.assert(Schema.sObjectType.Event.isCreateable(), 'Event create permission is required for viewer tests');
    }

    private static Account buildTestAccount() {
        Account acct = new Account(
            Name = TEST_ACCOUNT_NAME,
            SystemID__c = 'LEG-IPV-001',
            CustomerAddressOperatingUnit__c = '82',
            SourceSystemID__c = 'TEST-ORACLE-IPV'
        );
        populateRequiredCreateableFields(acct, Schema.SObjectType.Account.fields.getMap());
        return acct;
    }

    private static Project__c buildTestProject(Id accountId) {
        Project__c project = new Project__c(
            Name = TEST_PROJECT_NAME_PREFIX + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            Account__c = accountId,
            OwnerId = UserInfo.getUserId(),
            ProjectStartDate__c = Date.today(),
            ProjectEndDate__c = Date.today().addDays(30)
        );
        populateRequiredCreateableFields(project, Schema.SObjectType.Project__c.fields.getMap());
        return project;
    }

    /** Fills non-nillable createable fields so Project__c / Account inserts succeed across environments. */
    private static void populateRequiredCreateableFields(SObject rec, Map<String, Schema.SObjectField> fieldMap) {
        for (Schema.SObjectField fieldToken : fieldMap.values()) {
            Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
            if (!fieldDescribe.isCreateable() || fieldDescribe.isCalculated()) {
                continue;
            }
            if (fieldDescribe.isNillable() || fieldDescribe.isDefaultedOnCreate()) {
                continue;
            }
            if (rec.get(fieldDescribe.getName()) != null) {
                continue;
            }
            Object defaultValue = defaultValueForRequiredField(fieldDescribe);
            if (defaultValue != null) {
                rec.put(fieldDescribe.getName(), defaultValue);
            }
        }
    }

    private static Object defaultValueForRequiredField(Schema.DescribeFieldResult fieldDescribe) {
        switch on fieldDescribe.getType() {
            when PICKLIST, MULTIPICKLIST {
                for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
                    if (entry.isActive()) {
                        return entry.getValue();
                    }
                }
                return null;
            }
            when BOOLEAN {
                return false;
            }
            when DATE {
                return Date.today();
            }
            when DATETIME {
                return Datetime.now();
            }
            when CURRENCY, DOUBLE, INTEGER, LONG, PERCENT {
                return 1;
            }
            when STRING, TEXTAREA, EMAIL, PHONE, URL, ENCRYPTEDSTRING {
                return 'Test';
            }
            when REFERENCE {
                return null;
            }
            when else {
                return null;
            }
        }
    }

    private static Task newTaskOnProject(Id projectId, String sequenceKey, String subject, Date activityDate) {
        Task t = new Task();
        t.Subject = subject;
        t.ActivityDate = activityDate;
        t.OwnerId = UserInfo.getUserId();
        t.Status = 'Not Started';
        t.Priority = 'Normal';
        t.put('Project__c', projectId);
        putProjectItemSequenceField(t, sequenceKey);
        return t;
    }

    private static void putProjectItemSequenceField(SObject sob, String seqString) {
        Map<String, Schema.SObjectField> fm = sob.getSObjectType().getDescribe().fields.getMap();
        Schema.SObjectField f = fm.get('projectitemsequence__c');
        if (f == null) {
            return;
        }
        Schema.DisplayType ft = f.getDescribe().getType();
        if (
            ft == Schema.DisplayType.DOUBLE ||
            ft == Schema.DisplayType.INTEGER ||
            ft == Schema.DisplayType.CURRENCY ||
            ft == Schema.DisplayType.PERCENT
        ) {
            sob.put('ProjectItemSequence__c', Decimal.valueOf(seqString));
        } else {
            sob.put('ProjectItemSequence__c', seqString);
        }
    }

    private static Boolean eventHasProjectLookup() {
        return Schema.SObjectType.Event.fields.getMap().containsKey('project__c');
    }

    private static String firstClosedLikeTaskStatusValue() {
        Set<String> terminal = new Set<String>{ 'completed', 'cancelled', 'canceled', 'done', 'closed' };
        for (Schema.PicklistEntry pe : Task.Status.getDescribe().getPicklistValues()) {
            if (!pe.isActive()) {
                continue;
            }
            String val = pe.getValue() != null ? pe.getValue().trim().toLowerCase() : '';
            if (terminal.contains(val)) {
                return pe.getValue();
            }
        }
        return null;
    }

    /** API value must satisfy controller eventStatusLooksCompleted (value, not label, is what is stored). */
    private static String firstEventStatusPicklistThatLooksCompleted() {
        Map<String, Schema.SObjectField> fm = Schema.SObjectType.Event.fields.getMap();
        if (!fm.containsKey('status__c')) {
            return null;
        }
        for (Schema.PicklistEntry pe : fm.get('status__c').getDescribe().getPicklistValues()) {
            if (!pe.isActive()) {
                continue;
            }
            String label = pe.getLabel() != null ? pe.getLabel().trim().toLowerCase() : '';
            String val = pe.getValue() != null ? pe.getValue().trim().toLowerCase() : '';
            if (
                label.contains('complet') ||
                val.contains('complet') ||
                label.contains('cancel') ||
                val.contains('cancel') ||
                label == 'done' ||
                val == 'done' ||
                label == 'closed' ||
                val == 'closed' ||
                label == 'completed' ||
                val == 'completed'
            ) {
                return pe.getValue();
            }
        }
        return null;
    }

    private static Set<Id> rowIds(List<InstallationProjectViewerController.ProjectItemRow> rows) {
        Set<Id> out = new Set<Id>();
        if (rows == null) {
            return out;
        }
        for (InstallationProjectViewerController.ProjectItemRow r : rows) {
            if (r.recordId != null) {
                out.add(r.recordId);
            }
        }
        return out;
    }

    private static Event newEventOnProject(Id projectId, String sequenceKey, String subject, Datetime startDt, Datetime endDt) {
        Event e = new Event();
        e.Subject = subject;
        e.OwnerId = UserInfo.getUserId();
        e.StartDateTime = startDt;
        e.EndDateTime = endDt;
        e.IsAllDayEvent = false;
        e.put('Project__c', projectId);
        applyIpmEventRecordTypeIfAvailable(e);
        applyDefaultEventTypeIfRequired(e);
        putProjectItemSequenceField(e, sequenceKey);
        return e;
    }

    private static void applyIpmEventRecordTypeIfAvailable(Event e) {
        Map<String, Schema.RecordTypeInfo> byDev = Schema.SObjectType.Event.getRecordTypeInfosByDeveloperName();
        if (byDev.containsKey('IPMEvent')) {
            Schema.RecordTypeInfo rti = byDev.get('IPMEvent');
            if (rti != null && rti.isAvailable()) {
                e.RecordTypeId = rti.getRecordTypeId();
            }
        }
    }

    private static void applyDefaultEventTypeIfRequired(Event e) {
        Schema.DescribeFieldResult typeDescribe = Event.Type.getDescribe();
        if (!typeDescribe.isCreateable() || typeDescribe.isNillable() || typeDescribe.isDefaultedOnCreate()) {
            return;
        }
        if (String.isNotBlank(e.Type)) {
            return;
        }
        for (Schema.PicklistEntry entry : typeDescribe.getPicklistValues()) {
            if (entry.isActive()) {
                e.Type = entry.getValue();
                return;
            }
        }
    }

    private static String sequenceFieldToString(Object raw) {
        if (raw == null) {
            return null;
        }
        if (raw instanceof String) {
            return (String) raw;
        }
        return String.valueOf(raw);
    }

    private static Decimal firstSegmentAsDecimal(Object raw) {
        String s = sequenceFieldToString(raw);
        if (String.isBlank(s)) {
            return null;
        }
        List<String> parts = s.trim().split('\\.');
        try {
            return Decimal.valueOf(parts[0].trim());
        } catch (Exception e) {
            return null;
        }
    }

    private static Decimal secondSegmentAsDecimal(Object raw) {
        String s = sequenceFieldToString(raw);
        if (String.isBlank(s)) {
            return null;
        }
        List<String> parts = s.trim().split('\\.');
        if (parts.size() < 2) {
            return null;
        }
        try {
            return Decimal.valueOf(parts[1].trim());
        } catch (Exception e) {
            return null;
        }
    }
}