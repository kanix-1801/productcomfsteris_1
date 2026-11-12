@IsTest
private class LSTemporaryAccessPendingServiceTest {

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

    @IsTest
    static void jordanRequestWithDahindeCoverageFollowsGcl102() {
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

    private static TemporaryAccessException__c newRequest(Id requesterId, Id coverageRepId, Date startDate) {
        return new TemporaryAccessException__c(
            Requester__c = requesterId,
            CoverageRep__c = coverageRepId,
            ExceptionCategory__c = 'PTO',
            StartDate__c = startDate,
            EndDate__c = startDate.addDays(5)
        );
    }

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

    /** Gives the Life Sciences user create and edit on every writable request field. */
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

    /** Runs the daily job outside the permission-set setup transaction. */
    private static void runDaily() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            LSTemporaryAccessPendingService.processDaily();
        }
    }

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