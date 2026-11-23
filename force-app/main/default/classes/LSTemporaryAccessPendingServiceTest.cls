/**
 * @description Tests for LSTemporaryAccessPendingService.
 *
 *              Responsibilities:
 *              1. Verify the daily job rejects a pending request once its start date arrives.
 *              2. Verify the manager receives a reminder 7 days after submission, unless the start date arrives
 *                 first.
 *              3. Verify a request submitted by the manager is approved immediately.
 *              4. Verify the daily job can be executed and scheduled.
 * @author      Surya Manindra
 * @date        2026-11-23
 */
@IsTest
private class LSTemporaryAccessPendingServiceTest {

    /**
     * @description Confirms the daily job rejects an approval requested request once its start date arrives.
     */
    @IsTest
    static void pendingRequestRejectsWhenStartDateArrives() {
        User submitter = lifeScienceUser('rejSub', null);
        User requester = lifeScienceUser('rejReq', null);
        stopTemporaryAccessFlows(submitter.Id);
        Id coverageId = UserInfo.getUserId();
        TemporaryAccessException__c request;
        System.runAs(submitter) {
            request = newRequest(requester.Id, coverageId, Date.today());
            request.Status__c = LSTemporaryAccessPendingService.STATUS_APPROVAL_REQUESTED;
            insert request;
        }

        Test.startTest();
        runDaily();
        Test.stopTest();

        System.assertEquals(
            LSTemporaryAccessPendingService.STATUS_REJECTED,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :request.Id].Status__c
        );
    }

    /**
     * @description Confirms a request submitted on its start date stays open until the daily job runs and then
     *              rejects it.
     */
    @IsTest
    static void sameDayRequestStaysOpenUntilTheDailyRun() {
        User submitter = lifeScienceUser('daySub', null);
        User requester = lifeScienceUser('dayReq', null);
        stopTemporaryAccessFlows(submitter.Id);
        Id coverageId = UserInfo.getUserId();
        TemporaryAccessException__c request;
        System.runAs(submitter) {
            request = newRequest(requester.Id, coverageId, Date.today());
            request.Status__c = LSTemporaryAccessPendingService.STATUS_PENDING_APPROVAL;
            insert request;
        }

        System.assertEquals(
            LSTemporaryAccessPendingService.STATUS_PENDING_APPROVAL,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :request.Id].Status__c,
            'A request submitted on its Start Date stays open until the daily run'
        );

        runDaily();

        System.assertEquals(
            LSTemporaryAccessPendingService.STATUS_REJECTED,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :request.Id].Status__c
        );
    }

    /**
     * @description Confirms the manager receives a reminder 7 days after submission and the request stays approval
     *              requested.
     */
    @IsTest
    static void reminderGoesOutSevenDaysAfterSubmission() {
        User manager = lifeScienceUser('remMgr', null);
        User coverageRep = lifeScienceUser('remCov', manager.Id);
        User submitter = lifeScienceUser('remSub', null);
        User requester = lifeScienceUser('remReq', null);
        stopTemporaryAccessFlows(submitter.Id);
        TemporaryAccessException__c request = newRequest(requester.Id, coverageRep.Id, Date.today().addDays(10));
        request.Status__c = LSTemporaryAccessPendingService.STATUS_APPROVAL_REQUESTED;
        System.runAs(submitter) {
            insert request;
        }
        Test.setCreatedDate(request.Id, Datetime.now().addDays(-7));

        Integer emailsSent;
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            LSTemporaryAccessPendingService.processDaily();
            emailsSent = Limits.getEmailInvocations();
        }
        Test.stopTest();

        System.assertEquals(
            LSTemporaryAccessPendingService.STATUS_APPROVAL_REQUESTED,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :request.Id].Status__c
        );
        System.assert(emailsSent > 0, 'The manager should receive the 7 day reminder');
    }

    /**
     * @description Confirms no reminder is sent when the start date arrives before the 7 day reminder.
     */
    @IsTest
    static void noReminderWhenStartDateArrivesFirst() {
        User submitter = lifeScienceUser('skpSub', null);
        User requester = lifeScienceUser('skpReq', null);
        stopTemporaryAccessFlows(submitter.Id);
        TemporaryAccessException__c request = newRequest(requester.Id, UserInfo.getUserId(), Date.today().addDays(2));
        request.Status__c = LSTemporaryAccessPendingService.STATUS_APPROVAL_REQUESTED;
        System.runAs(submitter) {
            insert request;
        }
        Test.setCreatedDate(request.Id, Datetime.now().addDays(-3));

        Integer emailsSent;
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            LSTemporaryAccessPendingService.processDaily();
            emailsSent = Limits.getEmailInvocations();
        }
        Test.stopTest();

        System.assertEquals(
            LSTemporaryAccessPendingService.STATUS_APPROVAL_REQUESTED,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :request.Id].Status__c
        );
        System.assertEquals(0, emailsSent, 'No reminder when the Start Date arrives before day 7');
    }

    /**
     * @description Confirms the approval email goes to the coverage rep manager and the request is rejected once the
     *              start date arrives.
     */
    @IsTest
    static void approvalEmailGoesToCoverageManagerUntilStartDateRejects() {
        User approver = lifeScienceUser('aprGcl', null);
        User coverageRep = lifeScienceUser('covGcl', approver.Id);
        User requester = lifeScienceUser('reqGcl', null);
        stopTemporaryAccessFlows(requester.Id);

        TemporaryAccessException__c request = newRequest(requester.Id, coverageRep.Id, Date.today().addDays(10));
        request.Status__c = LSTemporaryAccessPendingService.STATUS_APPROVAL_REQUESTED;
        System.runAs(requester) {
            insert request;
        }
        System.assertEquals(
            LSTemporaryAccessPendingService.STATUS_APPROVAL_REQUESTED,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :request.Id].Status__c,
            'The requester is not his own manager, so the request stays waiting for approval'
        );

        List<LSTemporaryAccessExceptionEmailService.ComposedNotification> approvalEmails =
            LSTemporaryAccessExceptionEmailService.buildNotifications(
                new List<Id>{ request.Id },
                LSTemporaryAccessExceptionEmailService.TYPE_APPROVAL_NEEDED
            );
        System.assertEquals(approver.Id, approvalEmails[0].toUserId);
        String coverageEmail = [SELECT Email FROM User WHERE Id = :coverageRep.Id].Email.toLowerCase();
        Set<String> actualCc = new Set<String>();
        for (String address : approvalEmails[0].ccAddresses) {
            actualCc.add(address.toLowerCase());
        }
        System.assert(
            actualCc.contains(coverageEmail),
            'Expected ' + coverageEmail + ' in ' + String.join(approvalEmails[0].ccAddresses, ',')
        );

        System.runAs(new User(Id = UserInfo.getUserId())) {
            request.StartDate__c = Date.today();
            request.EndDate__c = Date.today().addDays(1);
            update request;
            LSTemporaryAccessPendingService.processDaily();
        }
        System.assertEquals(
            LSTemporaryAccessPendingService.STATUS_REJECTED,
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :request.Id].Status__c
        );
    }

    /**
     * @description Confirms a request submitted by the requester manager is approved immediately.
     */
    @IsTest
    static void managerSubmissionIsApprovedImmediately() {
        User manager = lifeScienceUser('ownMgr', null);
        User requester = lifeScienceUser('ownReq', manager.Id);
        stopTemporaryAccessFlows(manager.Id);
        TemporaryAccessException__c request = newRequest(requester.Id, UserInfo.getUserId(), Date.today().addDays(2));
        request.Status__c = LSTemporaryAccessPendingService.STATUS_APPROVAL_REQUESTED;

        System.runAs(manager) {
            insert request;
        }

        System.assertEquals(
            'Approved',
            [SELECT Status__c FROM TemporaryAccessException__c WHERE Id = :request.Id].Status__c
        );
    }

    /**
     * @description Confirms a request without a submission date is not due a reminder and the schedulable execute
     *              method runs the daily check.
     */
    @IsTest
    static void schedulableExecuteRunsTheDailyCheck() {
        System.assertEquals(
            false,
            LSTemporaryAccessPendingService.isReminderDue(new TemporaryAccessException__c(), Date.today()),
            'A request with no submission date is not due for a reminder'
        );

        Test.startTest();
        new LSTemporaryAccessPendingService().execute(null);
        Test.stopTest();
    }

    /**
     * @description Confirms the daily job can be scheduled and tolerates an already scheduled job.
     */
    @IsTest
    static void dailyJobCanBeScheduled() {
        Test.startTest();
        try {
            LSTemporaryAccessPendingService.scheduleDaily();
        } catch (Exception schedulingError) {
            System.assert(
                schedulingError.getMessage().contains('already scheduled'),
                schedulingError.getMessage()
            );
        }
        Test.stopTest();
    }

    /**
     * @description Builds a PTO temporary access request that ends 5 days after its start date.
     * @param requesterId Id of the user the request is for.
     * @param coverageRepId Id of the user providing coverage.
     * @param startDate Start date of the coverage period.
     * @return Unsaved temporary access request.
     */
    private static TemporaryAccessException__c newRequest(Id requesterId, Id coverageRepId, Date startDate) {
        return new TemporaryAccessException__c(
            Requester__c = requesterId,
            CoverageRep__c = coverageRepId,
            ExceptionCategory__c = 'PTO',
            StartDate__c = startDate,
            EndDate__c = startDate.addDays(5)
        );
    }

    /**
     * @description Inserts a Life Sciences Sales user and grants temporary access permissions.
     * @param aliasSeed Text used to build the alias, last name and username.
     * @param managerId Id of the manager. Null when the user has no manager.
     * @return Inserted user.
     */
    private static User lifeScienceUser(String aliasSeed, Id managerId) {
        Profile lifeScienceProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = :LSTemporaryAccessExceptionEmailService.LIFE_SCIENCE_SALES_PROFILE
            LIMIT 1
        ];
        String token = String.valueOf(DateTime.now().getTime()) + aliasSeed;
        User user = new User(
            Alias = aliasSeed.left(8),
            Email = token + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = aliasSeed,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = lifeScienceProfile.Id,
            TimeZoneSidKey = UserInfo.getTimeZone().getID(),
            Username = token + '@lstae.test',
            ManagerId = managerId
        );
        insert user;
        grantTemporaryAccessAccess(user.Id);
        return user;
    }

    private static void grantTemporaryAccessAccess(Id userId) {
        String name = 'LSTae' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        PermissionSet permissionSet = new PermissionSet(Name = name, Label = name);
        insert permissionSet;
        insert new ObjectPermissions(
            ParentId = permissionSet.Id,
            SobjectType = 'TemporaryAccessException__c',
            PermissionsRead = true,
            PermissionsCreate = true,
            PermissionsEdit = true,
            PermissionsDelete = true
        );
        List<FieldPermissions> fieldPermissions = new List<FieldPermissions>();
        for (Schema.SObjectField field : Schema.SObjectType.TemporaryAccessException__c.fields.getMap().values()) {
            Schema.DescribeFieldResult describe = field.getDescribe();
            if (!describe.isPermissionable() || !describe.isUpdateable()) {
                continue;
            }
            fieldPermissions.add(new FieldPermissions(
                ParentId = permissionSet.Id,
                SobjectType = 'TemporaryAccessException__c',
                Field = 'TemporaryAccessException__c.' + describe.getName(),
                PermissionsRead = true,
                PermissionsEdit = true
            ));
        }
        if (!fieldPermissions.isEmpty()) {
            Database.insert(fieldPermissions, false);
        }
        insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = permissionSet.Id);
    }

    private static void runDaily() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            LSTemporaryAccessPendingService.processDaily();
        }
    }

    /**
     * @description Inserts a flow bypass setting so the temporary access flows do not run for the user.
     * @param userId Id of the user the setting is created for.
     */
    private static void stopTemporaryAccessFlows(Id userId) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new Automation_Setting_Flow__c(
                SetupOwnerId = userId,
                TemporaryAccessSubmitForApproval__c = true,
                TemporaryAccessApprovalProcess__c = true,
                LSTemporaryAccessApprovalProcess__c = true
            );
        }
    }
}