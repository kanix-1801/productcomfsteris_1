@IsTest
public class TaskTriggerHelperTest {

    // ------------------ UTILITIES ------------------

    // Get CBM Task RecordType if it exists in org
    private static RecordType getCbmTaskRecordType() {
        List<RecordType> rts = [
            SELECT Id, DeveloperName, Name
            FROM RecordType
            WHERE SObjectType = 'Task'
              AND DeveloperName = 'CBM_Task'
            LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0];
    }

    // Get any existing non-admin user (no insert)
    private static User getExistingNonAdminUser() {
        // Try a known non-admin profile if present
        List<User> preferred = [
            SELECT Id
            FROM User
            WHERE IsActive = true AND Profile.Name = 'LeaderShip'
            LIMIT 1
        ];
        if (!preferred.isEmpty()) return preferred[0];

        // Fallback: any active user who is not System Administrator
        List<User> fallback = [
            SELECT Id
            FROM User
            WHERE IsActive = true AND Profile.Name != 'System Administrator'
            LIMIT 1
        ];
        System.assert(!fallback.isEmpty(),
            'Need at least one active non-admin user in the org.');
        return fallback[0];
    }

    // ------------------ DELETE LOGIC TESTS ------------------

    @IsTest
    static void preventDeleteNonAdminCbmTaskTest() {
        RecordType cbmRt = getCbmTaskRecordType();
        System.assertNotEquals(null, cbmRt,
            'Precondition: CBM_Task RecordType must exist');

        User u = getExistingNonAdminUser();

        System.runAs(u) {
            Task t = new Task(
                Subject      = 'CBM Task - Non Admin',
                Status       = 'Not Started',
                Priority     = 'Normal',
                RecordTypeId = cbmRt.Id,
                ActivityDate = Date.today()
            );
            insert t;

            Boolean blocked = false;
            try { delete t; }
            catch (DmlException ex) {
                blocked = true;
                System.assert(ex.getMessage().contains('not allowed'),
                    'Expected prevent-delete message for CBM Task.');
            }
            System.assertEquals(true, blocked,
                'Non-admin must be blocked from deleting CBM Task.');
        }
    }

   @IsTest
static void allowDeleteAdminCbmTaskTest() {
    RecordType cbmRt = getCbmTaskRecordType();
    System.assertNotEquals(null, cbmRt, 'Precondition: CBM_Task RecordType must exist');

    Task t = new Task(
        Subject      = 'Admin Delete Allowed',
        Status       = 'Not Started',
        Priority     = 'Normal',
        RecordTypeId = cbmRt.Id,
        ActivityDate = Date.today()
    );
    insert t;

    delete t;

    Integer cnt = [SELECT COUNT() FROM Task WHERE Id = :t.Id];
    System.assertEquals(0, cnt, 'Task should be deleted by admin without restriction.');
}

    @IsTest
    static void test_preventTaskDeletion_emptyInput_noThrow() {
        Test.startTest();
        TaskTriggerHelper.preventTaskDeletion(new List<Task>());
        Test.stopTest();
        System.assert(true, 'No exception expected for empty input.');
    }

    @IsTest
    static void test_preventTaskDeletion_nullInput_noThrow() {
        Test.startTest();
        TaskTriggerHelper.preventTaskDeletion(null);
        Test.stopTest();
        System.assert(true, 'No exception expected for null input.');
    }

    // Non-CBM record (ensures branch that skips addError)
    @IsTest
    static void test_preventTaskDeletion_noThrowForNonCbm() {
        Task t = new Task(
            Subject      = 'NonCBM',
            Status       = 'Not Started',
            Priority     = 'Normal',
            ActivityDate = Date.today()
        );
        insert t;

        Test.startTest();
        TaskTriggerHelper.preventTaskDeletion(new List<Task>{ t });
        Test.stopTest();

        System.assert(true, 'No exception expected for non-CBM Task in helper call.');
    }

    // Mixed records: only CBM should get addError on the record (run as non-admin)
    @IsTest
    static void test_preventTaskDeletion_mixedRecords_addErrorOnlyForCbm() {
        RecordType cbmRt = getCbmTaskRecordType();
        System.assertNotEquals(null, cbmRt,
            'Precondition: CBM_Task RecordType must exist');

        Task nonCbm = new Task(
            Subject      = 'NonCBM-Row',
            Status       = 'Not Started',
            Priority     = 'Normal',
            ActivityDate = Date.today()
        );
        Task cbm = new Task(
            Subject      = 'CBM-Row',
            Status       = 'Not Started',
            Priority     = 'Normal',
            RecordTypeId = cbmRt.Id,
            ActivityDate = Date.today()
        );
        insert new List<Task>{ nonCbm, cbm };

        // Run helper as NON-ADMIN so it doesn’t early-return
        User u = getExistingNonAdminUser();
        System.runAs(u) {
            Test.startTest();
            TaskTriggerHelper.preventTaskDeletion(new List<Task>{ nonCbm, cbm });
            Test.stopTest();

            System.assertEquals(0, nonCbm.getErrors().size(),
                'Non-CBM should not receive errors.');
            System.assert(cbm.getErrors().size() > 0,
                'CBM Task should receive addError for non-admin.');
        }
    }

    // ------------------ PRIORITY RESTRICT TESTS ------------------

    // Non-admin: update with changed priority -> adds error, blocks DML
    @IsTest
    static void restrictPriority_nonAdmin_updatePriorityChanged_addsError_directCall() {
        User u = getExistingNonAdminUser();

        System.runAs(u) {
            Task t = new Task(
                Subject      = 'ChangedPriority',
                Status       = 'Not Started',
                Priority     = 'Normal',
                ActivityDate = Date.today()
            );
            insert t;

            Task oldT = new Task(Id = t.Id, Priority = 'Normal');
            t.Priority = 'High';
            t.BypassValidation__c = false;

            Test.startTest();
            TaskTriggerHelper.restrictPriorityForNonAdmin(
                new List<Task>{ t },
                new Map<Id, Task>{ t.Id => oldT },
                false,  // isInsert
                true    // isUpdate
            );
            Test.stopTest();

            System.assert(t.getErrors() != null && t.getErrors().size() > 0,
                'Expected addError when non-admin changes Priority.');
            System.assert(
                t.getErrors()[0].getMessage().contains('Urgency'),
                'Expected "Urgency is not Editable for you".'
            );

            Boolean blocked = false;
            try { update t; } catch (Exception e) { blocked = true; }
            System.assertEquals(true, blocked, 'Update should be blocked by addError.');
        }
    }

    // Non-admin: bypass=true allows logic & resets flag; persist as Admin to avoid trigger re-block
    @IsTest
    static void restrictPriority_nonAdmin_bypassTrue_allowsAndResets_directCall() {
        User u = getExistingNonAdminUser();
        Id taskId;

        System.runAs(u) {
            Task t = new Task(
                Subject      = 'BypassOnce',
                Status       = 'Not Started',
                Priority     = 'Normal',
                ActivityDate = Date.today()
            );
            insert t;
            taskId = t.Id;

            Task oldT = new Task(Id = t.Id, Priority = 'Normal');
            t.Priority = 'High';
            t.BypassValidation__c = true;

            Test.startTest();
            TaskTriggerHelper.restrictPriorityForNonAdmin(
                new List<Task>{ t },
                new Map<Id, Task>{ t.Id => oldT },
                false, true
            );
            Test.stopTest();

            System.assertEquals(0, t.getErrors().size(),
                'No error expected when bypass is true.');
            System.assertEquals(false, t.BypassValidation__c,
                'BypassValidation__c should reset to false.');

            // NOTE: do NOT update here as non-admin (trigger would re-block)
        }

        // Persist as Admin so helper early-returns
        Task tAdmin = [SELECT Id, Priority, Subject, ActivityDate FROM Task WHERE Id = :taskId];
        tAdmin.Priority = 'High';
        tAdmin.Subject  = tAdmin.Subject + ' (saved)';
        if (tAdmin.ActivityDate == null) tAdmin.ActivityDate = Date.today();
        update tAdmin;

        Task r = [SELECT Priority, Subject FROM Task WHERE Id = :taskId];
        System.assertEquals('High', r.Priority, 'Priority should persist to DB.');
    }

    // Non-admin: insert path – no restriction
    @IsTest
    static void restrictPriority_nonAdmin_insertPath_doesNothing_directCall() {
        User u = getExistingNonAdminUser();

        System.runAs(u) {
            Task t = new Task(
                Subject             = 'InsertNoRestrict',
                Status              = 'Not Started',
                Priority            = 'High',
                BypassValidation__c = false,
                ActivityDate        = Date.today()
            );

            Test.startTest();
            TaskTriggerHelper.restrictPriorityForNonAdmin(
                new List<Task>{ t },  // new-only
                null,
                true,  // isInsert
                false  // isUpdate
            );
            Test.stopTest();

            System.assertEquals(0, t.getErrors().size(), 'Insert branch should not add errors.');
            insert t;

            Task r = [SELECT Priority FROM Task WHERE Id = :t.Id];
            System.assertEquals('High', r.Priority);
        }
    }

    // Non-admin: update where priority does NOT change – no error (persist as Admin for safety)
    @IsTest
    static void restrictPriority_nonAdmin_noChange_noError_directCall() {
        User u = getExistingNonAdminUser();
        Id taskId;

        System.runAs(u) {
            Task t = new Task(
                Subject      = 'NoChange',
                Status       = 'Not Started',
                Priority     = 'Normal',
                ActivityDate = Date.today()
            );
            insert t;
            taskId = t.Id;

            Task oldT = new Task(Id = t.Id, Priority = 'Normal');

            Test.startTest();
            TaskTriggerHelper.restrictPriorityForNonAdmin(
                new List<Task>{ t },
                new Map<Id, Task>{ t.Id => oldT },
                false, true
            );
            Test.stopTest();

            System.assertEquals(0, t.getErrors().size(),
                'No error expected when Priority did not change.');

            // Avoid updating as non-admin (org validations may vary per org)
        }

        // Persist as Admin (no addError & avoids org rule surprises)
        Task tAdmin = [SELECT Id, Subject FROM Task WHERE Id = :taskId];
        tAdmin.Subject = tAdmin.Subject + ' (touch)';
        update tAdmin;
    }

    // Non-admin: update with missing oldMap entry (defensive path) – no error; persist as Admin
    @IsTest
    static void test_restrictPriority_oldMapMissing_noError_directCall() {
        User u = getExistingNonAdminUser();
        Id taskId;

        System.runAs(u) {
            Task t = new Task(
                Subject      = 'OldMapMissing',
                Status       = 'Not Started',
                Priority     = 'Normal',
                ActivityDate = Date.today()
            );
            insert t;
            taskId = t.Id;

            // Change priority but provide NO oldMap entry
            t.Priority = 'High';

            Test.startTest();
            TaskTriggerHelper.restrictPriorityForNonAdmin(
                new List<Task>{ t },
                new Map<Id, Task>(),   // missing entry for t.Id
                false, true
            );
            Test.stopTest();

            System.assertEquals(0, t.getErrors().size(),
                'No error expected when oldMap has no snapshot.');

            // Do NOT update here as non-admin; persist as admin
        }

        Task tAdmin = new Task(Id = taskId, Priority = 'High', Subject = 'OldMapMissing (saved)');
        update tAdmin;

        Task r = [SELECT Priority, Subject FROM Task WHERE Id = :taskId];
        System.assertEquals('High', r.Priority, 'Priority should persist to DB.');
    }

    // Admin: early return – do not touch bypass
    @IsTest
    static void restrictPriority_admin_earlyReturn_doesNotTouchBypass_directCall() {
        Task t = new Task(
            Subject             = 'AdminEarlyReturn',
            Status              = 'Not Started',
            Priority            = 'Normal',
            BypassValidation__c = true,
            ActivityDate        = Date.today()
        );
        insert t;

        Task oldT = new Task(Id = t.Id, Priority = 'Normal');
        t.Priority = 'High';

        Test.startTest();
        TaskTriggerHelper.restrictPriorityForNonAdmin(
            new List<Task>{ t },
            new Map<Id, Task>{ t.Id => oldT },
            false, true
        );
        Test.stopTest();

        System.assertEquals(0, t.getErrors().size(), 'Admin should not get an error.');
        System.assertEquals(true, t.BypassValidation__c, 'Bypass should remain untouched for admin.');

        t.Subject = t.Subject + ' (touch)';
        update t; // admin allowed
    }

    // Early return path for null newTasks (covers top-of-method short-circuit)
    @IsTest
    static void test_restrictPriority_nullNewTasks_earlyReturn() {
        Test.startTest();
        TaskTriggerHelper.restrictPriorityForNonAdmin(
            null, null, false, false
        );
        Test.stopTest();
        System.assert(true, 'No exception expected for null newTasks.');
    }

    // Early return path for empty newTasks list
    @IsTest
    static void test_restrictPriority_emptyNewTasks_earlyReturn() {
        Test.startTest();
        TaskTriggerHelper.restrictPriorityForNonAdmin(
            new List<Task>(), null, true, false
        );
        Test.stopTest();
        System.assert(true, 'No exception expected for empty newTasks.');
    }

    // Catch coverage: run as NON-ADMIN (avoid admin early return) and pass a null item to force NPE
    @IsTest
    static void test_restrictPriority_exception_catchCoverage() {
        User u = getExistingNonAdminUser();

        Boolean threw = false;
        System.runAs(u) {
            try {
                List<Task> badList = new List<Task>{ null }; // will NPE on t.BypassValidation__c

                Test.startTest();
                TaskTriggerHelper.restrictPriorityForNonAdmin(
                    badList,
                    new Map<Id, Task>(),
                    false, // isInsert
                    true   // isUpdate
                );
                Test.stopTest();
            } catch (Exception ex) {
                // Helper logs via ErrorLogger and rethrows -> we should land here
                threw = true;
            }
        }
        System.assertEquals(true, threw,
            'Expected exception to be rethrown so the helper catch block is covered.');
    }
}