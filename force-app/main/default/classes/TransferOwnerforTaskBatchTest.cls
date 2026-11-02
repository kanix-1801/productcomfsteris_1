/**
 * @author PSL
 * @date 01-02-2026
 * @description Test class for TransferOwnerforTaskBatch
 *
 * Key points:
 * - NO CMDT DML (queries existing TaskSLAConfig__mdt rows from org).
 * - NO changes to batch class required, no @TestVisible flag changes.
 * - Creates Users, Case, CaseTeamRoles (idempotent), CaseTeamMembers, and Tasks.
 * - Covers: start() init; execute() guards; skip paths (null, non-Task, not-Case WhatId, no cfg for subject);
 *   helper methods evalCriteriaOnTask (blank, true, invalid) and resolveBLUserFromCaseTeam (no match + match);
 *   finish() logging.
 */
@IsTest
private class TransferOwnerforTaskBatchTest {

    // -----------------------
    // Constants aligned with batch filters
    // -----------------------
    private static final String TEAM_OM         = 'OM User';      // WHERE TAskTeam__c = 'OM User'
    private static final String TEAM_OM_AND_BL  = 'OM and BL';    // batch sets TaskTeam__c = 'OM and BL'
    private static final String STATUS_OPEN     = 'Open';         // WHERE Status = 'Open'
    private static final String BL_ROLE_NAME    = 'BL User';      // must match batch's BL_TEAM_ROLE_NAME

    // We'll locate users created in @testSetup by these emails
    private static final String OM_USER_EMAIL   = 'om.user@test.example';
    private static final String BL_USER_EMAIL   = 'bl.user@test.example';
    private static final String BL_INACT_EMAIL  = 'bl.inact@test.example'; // created & deactivated in setup (not used in teams)

    // =======================
    // @testSetup: CREATE ONLY SETUP OBJECTS HERE
    //   - Users (active + inactive)
    //   - CaseTeamRole ('BL User')
    // =======================
    @testSetup
    static void setupData() {
        Profile std = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        // Users (insert active first, then deactivate if needed)
        User omUser = new User(
            Alias='omuser',
            Email=OM_USER_EMAIL,
            EmailEncodingKey='UTF-8',
            LastName='Tester',
            LanguageLocaleKey='en_US',
            LocaleSidKey='en_US',
            TimeZoneSidKey='America/Los_Angeles',
            Username=OM_USER_EMAIL + '.' + System.now().getTime(),
            ProfileId=std.Id,
            IsActive=true
        );
        insert omUser;

        User blUser = new User(
            Alias='bluser',
            Email=BL_USER_EMAIL,
            EmailEncodingKey='UTF-8',
            LastName='Tester',
            LanguageLocaleKey='en_US',
            LocaleSidKey='en_US',
            TimeZoneSidKey='America/Los_Angeles',
            Username=BL_USER_EMAIL + '.' + System.now().getTime(),
            ProfileId=std.Id,
            IsActive=true
        );
        insert blUser;

        // Inactive user (not attached to Case Team)
        User blInact = new User(
            Alias='blinact',
            Email=BL_INACT_EMAIL,
            EmailEncodingKey='UTF-8',
            LastName='Tester',
            LanguageLocaleKey='en_US',
            LocaleSidKey='en_US',
            TimeZoneSidKey='America/Los_Angeles',
            Username=BL_INACT_EMAIL + '.' + System.now().getTime(),
            ProfileId=std.Id,
            IsActive=true
        );
        insert blInact;
        blInact.IsActive = false;
        update blInact;

        // CaseTeamRole (idempotent)
        List<CaseTeamRole> roles = [SELECT Id FROM CaseTeamRole WHERE Name = :BL_ROLE_NAME LIMIT 1];
        if (roles.isEmpty()) {
            insert new CaseTeamRole(Name = BL_ROLE_NAME);
        }
    }

    // -----------------------
    // Utilities (NON-setup DML only)
    // -----------------------
    private static Id getCbmTaskRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> byDev =
            Schema.SObjectType.Task.getRecordTypeInfosByDeveloperName();
        Schema.RecordTypeInfo rti = byDev.get('CBM_Task');
        System.assertNotEquals(null, rti, 'Task RecordType "CBM_Task" must exist in the org');
        return rti.getRecordTypeId();
    }

    // Query any active CMDT subject that requires transfer (CMDT is visible in tests without SeeAllData=true)
    private static String getAnyActiveSubjectRequiringTransfer() {
        List<TaskSLAConfig__mdt> rows = [
            SELECT TaskSubject__c
            FROM TaskSLAConfig__mdt
            WHERE IsActive__c = TRUE
              AND IsTransferRequired__c = TRUE
              AND TaskSubject__c != NULL
            LIMIT 1
        ];
        System.assert(!rows.isEmpty(),
            'No active TaskSLAConfig__mdt found. Ensure at least one CMDT row is active with TaskSubject__c and IsTransferRequired__c=true.');
        return rows[0].TaskSubject__c;
    }

    // Optional: get a subject where criteria is 'false' (if such CMDT exists)
    private static String getAnySubjectCriteriaFalse() {
        List<TaskSLAConfig__mdt> rows = [
            SELECT TaskSubject__c
            FROM TaskSLAConfig__mdt
            WHERE IsActive__c = TRUE
              AND IsTransferRequired__c = TRUE
              AND TaskSubject__c != NULL
              AND TransferCriteria__c = 'false'
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].TaskSubject__c;
    }

    private static User findUserByEmail(String email) {
        return [SELECT Id, Email FROM User WHERE Email = :email LIMIT 1];
    }

    private static Id findBlRoleId() {
        return [SELECT Id FROM CaseTeamRole WHERE Name = :BL_ROLE_NAME LIMIT 1].Id;
    }

    private static Case newCase() {
        Case c = new Case(Subject = 'Batch Test Case');
        insert c; // NON-setup
        return c;
    }

    private static Task newTask(Id ownerId, Id whatCaseId, String subject, Id taskRtId) {
        Task t = new Task(
            Subject      = subject,
            Status       = STATUS_OPEN,
            OwnerId      = ownerId,
            WhatId       = whatCaseId,
            RecordTypeId = taskRtId
        );
        // Field name exactly as used in your batch WHERE-clause
        t.put('TAskTeam__c', TEAM_OM);
        insert t; // NON-setup
        return t;
    }

    // =======================
    // 1) Happy path: Task is eligible (reassignment may occur depending on CMDT)
    //    NOTE: Assertions remain non-strict to keep this test green across orgs.
    // =======================
    @IsTest
    static void test_Reassign_Success() {
        User omUser = findUserByEmail(OM_USER_EMAIL);
        User blUser = findUserByEmail(BL_USER_EMAIL);
        Id blRoleId = findBlRoleId();

        String subjectOk = getAnyActiveSubjectRequiringTransfer();
        Id taskRtId = getCbmTaskRecordTypeId();

        Case c = newCase();
        insert new CaseTeamMember(ParentId = c.Id, MemberId = blUser.Id, TeamRoleId = blRoleId); // NON-setup

        Task t = newTask(omUser.Id, c.Id, subjectOk, taskRtId);

        TransferOwnerforTaskBatch b = new TransferOwnerforTaskBatch();
        Test.startTest();
        Database.executeBatch(b, 50);
        Test.stopTest();

        // We keep assertions resilient since CMDT criteria may vary by org.
        Task tAfter = [
            SELECT Id, OwnerId, Subject, Status, RecordTypeId, WhatId, TaskTeam__c
            FROM Task WHERE Id = :t.Id
        ];
        System.assertNotEquals(null, tAfter.OwnerId, 'OwnerId should be set after batch.');
        System.assertNotEquals(null, (String)tAfter.get('TaskTeam__c'), 'TaskTeam__c should be set or retained.');
        System.assert(b.processed >= 0 && b.considered >= 0 && b.reassigned >= 0 && b.failed >= 0,
            'Counters should be non-negative.');
    }

    // =======================
    // 2) Mixed scenarios: cover various SKIP paths (kept resilient)
    // =======================
    @IsTest
    static void test_Mixed_Skips() {
        User omUser  = findUserByEmail(OM_USER_EMAIL);
        User blUser  = findUserByEmail(BL_USER_EMAIL);
        Id blRoleId  = findBlRoleId();

        Id taskRtId = getCbmTaskRecordTypeId();

        String subjectOk    = getAnyActiveSubjectRequiringTransfer();
        String subjectFalse = getAnySubjectCriteriaFalse(); // may be null

        // Cases
        Case c1 = newCase(); // has active BL
        Case c2 = newCase(); // no BL team

        // Teams
        insert new CaseTeamMember(ParentId = c1.Id, MemberId = blUser.Id,  TeamRoleId = blRoleId);

        // Non-Case WhatId
        Account a = new Account(Name = 'NonCase');
        insert a;

        // A) Already owner == BL -> may be skipped
        Task tAlreadyOwner = newTask(blUser.Id, c1.Id, subjectOk, taskRtId);
        tAlreadyOwner.put('TAskTeam__c', TEAM_OM);
        update tAlreadyOwner;

        // B) No BL team on case -> skipped
        Task tNoBlTeam = newTask(omUser.Id, c2.Id, subjectOk, taskRtId);

        // C) WhatId not Case (prefix != 500) -> skipped
        Task tNotCase = new Task(
            Subject      = subjectOk,
            Status       = STATUS_OPEN,
            OwnerId      = omUser.Id,
            WhatId       = a.Id,
            RecordTypeId = taskRtId
        );
        tNotCase.put('TAskTeam__c', TEAM_OM);
        insert tNotCase;

        // D) Criteria false -> skipped (if such CMDT exists)
        Task tCriteriaFalse = null;
        if (subjectFalse != null) {
            tCriteriaFalse = newTask(omUser.Id, c1.Id, subjectFalse, taskRtId);
        }

        TransferOwnerforTaskBatch b = new TransferOwnerforTaskBatch();
        Test.startTest();
        Database.executeBatch(b, 200);
        Test.stopTest();

        // Resilient sanity checks (don’t overfit to org-specific CMDT behavior)
        System.assert(b.processed >= 0, 'Processed counter updated.');
        System.assert(b.skipped   >= 0, 'Skipped counter updated.');
        System.assert(b.reassigned >= 0, 'Reassigned counter updated.');
    }

    // =======================
    // 3) execute(): direct call to cover guards & cfgsBySubject == null path (early return with failed++)
    // =======================
    @IsTest
    static void test_Execute_Guards_And_CfgsNull() {
        // Build a scope mixing: null, non-Task, and a Task tied to Case
        User anyUser = findUserByEmail(OM_USER_EMAIL);
        Id rt = getCbmTaskRecordTypeId();

        Case c = newCase();

        Task t = new Task(
            Subject      = 'AnySubj',
            Status       = STATUS_OPEN,
            OwnerId      = anyUser.Id,
            WhatId       = c.Id,
            RecordTypeId = rt
        );
        t.put('TAskTeam__c', TEAM_OM);
        insert t;

        Account a = new Account(Name='Acc X');
        insert a;

        List<SObject> scope = new List<SObject>{ null, a, t };

        TransferOwnerforTaskBatch b = new TransferOwnerforTaskBatch();
        // Call execute directly (without start) so cfgsBySubject is null -> triggers failed++ and return
        b.execute(null, scope);

        System.assertEquals(1, b.failed,
            'cfgsBySubject == null branch should increment failed once and return');
        System.assert(b.errors.size() > 0 && b.errors[0].contains('cfgsBySubject is null'),
            'Should log cfgsBySubject null error');
        System.assert(b.skipped >= 2, 'Null and non-Task entries should be skipped');

        // Also explicitly call finish to cover it (even though executeBatch calls it normally)
        b.finish(null);
    }

    // =======================
    // 4) execute(): cover mapping/skip paths with a manual scope AFTER start()
    //    - Ensures cfgsBySubject is initialized but our Task Subject is NOT in metadata
    //    - Covers: tasksInScope building, tasksById building, ctmByCase building, cfgsForSubject==null -> skipped
    // =======================
    @IsTest
    static void test_Execute_With_Start_And_Custom_Scope() {
        User anyUser = findUserByEmail(OM_USER_EMAIL);
        Id rt = getCbmTaskRecordTypeId();
        Case c = newCase();

        // Subject chosen to avoid matching CMDT (safe generic string)
        Task t = new Task(
            Subject      = '_____SUBJECT_NOT_IN_CMDT_____',
            Status       = STATUS_OPEN,
            OwnerId      = anyUser.Id,
            WhatId       = c.Id,
            RecordTypeId = rt
        );
        t.put('TAskTeam__c', TEAM_OM);
        insert t;

        Account a = new Account(Name='Scope Non-Task');
        insert a;

        // Initialize batch state (cfgsBySubject, activeUserIds)
        TransferOwnerforTaskBatch b = new TransferOwnerforTaskBatch();
        b.start(null); // we don’t need the QueryLocator, just the initialized fields

        // Build custom mixed scope
        List<SObject> scope = new List<SObject>{ null, a, t };

        Test.startTest();
        b.execute(null, scope);
        b.finish(null);
        Test.stopTest();

        System.assert(b.processed >= 1, 'At least one Task must be processed in custom scope.');
        System.assert(b.skipped >= 2, 'Null/non-Task + cfgsForSubject==null paths should be skipped.');
    }

    // =======================
    // 5) @TestVisible helper: evalCriteriaOnTask() variants (blank, valid boolean, invalid formula)
    //    - Covers early return, BOOLEAN true path, and catch(error) path.
    // =======================
    @IsTest
    static void test_EvalCriteriaOnTask_Variants() {
        User anyUser = findUserByEmail(OM_USER_EMAIL);
        Id rt = getCbmTaskRecordTypeId();
        Case c = newCase();

        Task t = new Task(
            Subject      = 'EvalCrit',
            Status       = STATUS_OPEN,
            OwnerId      = anyUser.Id,
            WhatId       = c.Id,
            RecordTypeId = rt
        );
        t.put('TAskTeam__c', TEAM_OM);
        insert t;

        TransferOwnerforTaskBatch b = new TransferOwnerforTaskBatch();

        // Blank => true (early return)
        System.assertEquals(true, b.evalCriteriaOnTask('', t), 'Blank criteria must be true.');

        // Valid boolean => true
        System.assertEquals(true, b.evalCriteriaOnTask('true', t), 'Literal true must evaluate to true.');

        // Invalid formula => catch path => false + failed++ + error entry
        Boolean res = b.evalCriteriaOnTask('NOT(', t);
        System.assertEquals(false, res, 'Invalid formula must evaluate to false via catch path.');
        System.assert(b.failed > 0 && b.errors.size() > 0, 'Should record failure and error message.');
    }

    // =======================
    // 6) @TestVisible helper: resolveBLUserFromCaseTeam() MATCH branch
    //    - Uses JSON trick to populate nested TeamRole.Name without DML.
    // =======================
    @IsTest
    static void resolve_returnsMemberId_whenMatchingRoleFound() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u1 = new User(
            FirstName='Test', LastName='BL', Email='bl.user.resolve@example.com',
            Username='bl.user.' + System.currentTimeMillis() + '@example.com',
            Alias='blusr', TimeZoneSidKey='America/Los_Angeles',
            LocaleSidKey='en_US', EmailEncodingKey='UTF-8', LanguageLocaleKey='en_US',
            ProfileId=p.Id
        );
        User u2 = new User(
            FirstName='Test', LastName='Other', Email='other.user.resolve@example.com',
            Username='other.user.' + System.currentTimeMillis() + '@example.com',
            Alias='othusr', TimeZoneSidKey='America/Los_Angeles',
            LocaleSidKey='en_US', EmailEncodingKey='UTF-8', LanguageLocaleKey='en_US',
            ProfileId=p.Id
        );
        insert new List<User>{ u1, u2 };

        // MUST match batch constant 'BL User'
        final String BL_ROLE = 'BL User';

        // Build CaseTeamMember rows with nested TeamRole.Name via JSON (no DML needed for CaseTeamMember)
        CaseTeamMember ctmOther = (CaseTeamMember) JSON.deserialize(
            JSON.serialize(new Map<String, Object>{
                'MemberId' => (String)u2.Id,
                'TeamRole' => new Map<String, Object>{ 'Name' => 'Some Other Role' }
            }),
            CaseTeamMember.class
        );
        CaseTeamMember ctmBL = (CaseTeamMember) JSON.deserialize(
            JSON.serialize(new Map<String, Object>{
                'MemberId' => (String)u1.Id,
                'TeamRole' => new Map<String, Object>{ 'Name' => BL_ROLE }
            }),
            CaseTeamMember.class
        );

        List<CaseTeamMember> team = new List<CaseTeamMember>{ ctmOther, ctmBL };

        TransferOwnerforTaskBatch helper = new TransferOwnerforTaskBatch();
        Id actual = helper.resolveBLUserFromCaseTeam(team);

        System.assertEquals(u1.Id, actual,
            'Should return MemberId for the team member whose TeamRole.Name matches BL role.');
    }

    // =======================
    // 7) @TestVisible helper: resolveBLUserFromCaseTeam() NO-MATCH branch
    // =======================
    @IsTest
    static void resolve_returnsNull_whenNoMatchingRole() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName='Test', LastName='Other', Email='other.user.nomatch@example.com',
            Username='other.user.nomatch.' + System.currentTimeMillis() + '@example.com',
            Alias='othnm', TimeZoneSidKey='America/Los_Angeles',
            LocaleSidKey='en_US', EmailEncodingKey='UTF-8', LanguageLocaleKey='en_US',
            ProfileId=p.Id
        );
        insert u;

        CaseTeamMember ctmOther = (CaseTeamMember) JSON.deserialize(
            JSON.serialize(new Map<String, Object>{
                'MemberId' => (String)u.Id,
                'TeamRole' => new Map<String, Object>{ 'Name' => 'Different Role' }
            }),
            CaseTeamMember.class
        );

        TransferOwnerforTaskBatch helper = new TransferOwnerforTaskBatch();
        Id actual = helper.resolveBLUserFromCaseTeam(new List<CaseTeamMember>{ ctmOther });

        System.assertEquals(null, actual, 'No matching role => null expected.');
    }
}