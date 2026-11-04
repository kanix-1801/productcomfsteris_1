@IsTest
private class LSTemporaryAccessEmailServiceTest {

    @IsTest
    static void lifeScienceRequestIsSeparatedFromHealthcare() {
        Profile lifeScienceProfile = lifeScienceProfile();
        User submitter = insertUser(lifeScienceProfile.Id, 'lsSub', null);
        User requester = insertUser(lifeScienceProfile.Id, 'lsReq', null);
        User coverageRep = insertUser(lifeScienceProfile.Id, 'lsCov', null);
        User healthcareUser = insertUser(nonLifeScienceProfileId(), 'hcUsr', null);
        stopTemporaryAccessFlows(submitter.Id);
        stopTemporaryAccessFlows(healthcareUser.Id);

        TemporaryAccessException__c lifeScienceRequest = newRequest(requester.Id, coverageRep.Id);
        System.runAs(submitter) {
            insert lifeScienceRequest;
        }

        TemporaryAccessException__c healthcareRequest = newRequest(requester.Id, coverageRep.Id);
        System.runAs(healthcareUser) {
            insert healthcareRequest;
        }

        Set<Id> lifeScienceIds = LSTemporaryAccessExceptionEmailService.filterLifeScienceRequestIds(
            new Set<Id>{ lifeScienceRequest.Id, healthcareRequest.Id }
        );

        System.assertEquals(1, lifeScienceIds.size(), 'Only the Life Sciences Sales creator is in scope');
        System.assert(lifeScienceIds.contains(lifeScienceRequest.Id));
        System.assert(!lifeScienceIds.contains(healthcareRequest.Id));
    }

    @IsTest
    static void approvalNeededEmailUsesCoverageManagerAndCopiesTheOtherParties() {
        RequestContext context = lifeScienceRequest();

        List<LSTemporaryAccessExceptionEmailService.ComposedNotification> notifications =
            LSTemporaryAccessExceptionEmailService.buildNotifications(
                new List<Id>{ context.request.Id },
                LSTemporaryAccessExceptionEmailService.TYPE_APPROVAL_NEEDED
            );

        System.assertEquals(1, notifications.size());
        System.assertEquals(context.requesterManager.Id, notifications[0].toUserId);
        System.assertEquals(
            LSTemporaryAccessExceptionEmailService.SUBJECT_APPROVAL_NEEDED,
            notifications[0].subject
        );
        System.assert(notifications[0].htmlBody.contains('needs your review'));
        assertCc(
            notifications[0].ccAddresses,
            new List<String>{ context.requester.Email, context.coverageRep.Email, context.submitter.Email }
        );
    }

    @IsTest
    static void grantedEmailGoesToCreatorAndCopiesTheWordRecipients() {
        RequestContext context = lifeScienceRequest();

        List<LSTemporaryAccessExceptionEmailService.ComposedNotification> notifications =
            LSTemporaryAccessExceptionEmailService.buildNotifications(
                new List<Id>{ context.request.Id },
                LSTemporaryAccessExceptionEmailService.TYPE_APPROVED
            );

        System.assertEquals(1, notifications.size());
        System.assertEquals(context.submitter.Id, notifications[0].toUserId);
        System.assertEquals(LSTemporaryAccessExceptionEmailService.SUBJECT_GRANTED, notifications[0].subject);
        System.assert(notifications[0].htmlBody.contains('has been approved for the following request'));
        assertCc(
            notifications[0].ccAddresses,
            new List<String>{
                context.coverageManager.Email,
                context.requester.Email,
                context.coverageRep.Email
            }
        );
    }

    @IsTest
    static void rejectedEmailGoesToCreatorAndCopiesTheWordRecipients() {
        RequestContext context = lifeScienceRequest();

        List<LSTemporaryAccessExceptionEmailService.ComposedNotification> notifications =
            LSTemporaryAccessExceptionEmailService.buildNotifications(
                new List<Id>{ context.request.Id },
                LSTemporaryAccessExceptionEmailService.TYPE_REJECTED
            );

        System.assertEquals(1, notifications.size());
        System.assertEquals(context.submitter.Id, notifications[0].toUserId);
        System.assertEquals(LSTemporaryAccessExceptionEmailService.SUBJECT_REJECTED, notifications[0].subject);
        System.assert(notifications[0].htmlBody.contains('has been rejected for the following request'));
        System.assert(notifications[0].htmlBody.contains('reach out to your manager'));
        assertCc(
            notifications[0].ccAddresses,
            new List<String>{
                context.coverageManager.Email,
                context.requester.Email,
                context.coverageRep.Email
            }
        );
    }

    @IsTest
    static void expiredEmailGoesToCreatorAndCopiesCoverageManager() {
        RequestContext context = lifeScienceRequest();

        List<LSTemporaryAccessExceptionEmailService.ComposedNotification> notifications =
            LSTemporaryAccessExceptionEmailService.buildNotifications(
                new List<Id>{ context.request.Id },
                LSTemporaryAccessExceptionEmailService.TYPE_EXPIRED
            );

        System.assertEquals(1, notifications.size());
        System.assertEquals(context.submitter.Id, notifications[0].toUserId);
        System.assertEquals(LSTemporaryAccessExceptionEmailService.SUBJECT_EXPIRED, notifications[0].subject);
        System.assert(notifications[0].htmlBody.contains('has expired and access has been removed'));
        assertCc(
            notifications[0].ccAddresses,
            new List<String>{
                context.coverageManager.Email,
                context.requester.Email,
                context.coverageRep.Email
            }
        );
    }

    @IsTest
    static void expiringEmailGoesToCreatorWithRecordLink() {
        RequestContext context = lifeScienceRequest();

        List<LSTemporaryAccessExceptionEmailService.ComposedNotification> notifications =
            LSTemporaryAccessExceptionEmailService.buildNotifications(
                new List<Id>{ context.request.Id },
                LSTemporaryAccessExceptionEmailService.TYPE_EXPIRING
            );

        System.assertEquals(1, notifications.size());
        System.assertEquals(context.submitter.Id, notifications[0].toUserId);
        System.assertEquals(LSTemporaryAccessExceptionEmailService.SUBJECT_EXPIRING, notifications[0].subject);
        System.assert(notifications[0].htmlBody.contains('expiring in 3 days'));
        System.assert(notifications[0].htmlBody.contains('/' + context.request.Id + '"'), 'Request name links to the record');
    }

    @IsTest
    static void activeDelegatedApproverIsCopiedOnce() {
        RequestContext context = lifeScienceRequest();
        User delegate = insertUser(lifeScienceProfile().Id, 'lsDel', null);
        context.requesterManager.DelegatedApproverId = delegate.Id;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update context.requesterManager;
        }

        List<LSTemporaryAccessExceptionEmailService.ComposedNotification> notifications =
            LSTemporaryAccessExceptionEmailService.buildNotifications(
                new List<Id>{ context.request.Id },
                LSTemporaryAccessExceptionEmailService.TYPE_APPROVAL_NEEDED
            );

        assertCc(
            notifications[0].ccAddresses,
            new List<String>{
                context.requester.Email,
                context.coverageRep.Email,
                context.submitter.Email,
                delegate.Email
            }
        );
    }

    @IsTest
    static void blankTemplateLinkIsMadeAbsolute() {
        RequestContext context = lifeScienceRequest();
        String body = '<a href="' + context.request.Id + '">here</a>';

        String fixedBody = LSTemporaryAccessExceptionEmailService.absoluteRecordLinks(body, context.request.Id);

        System.assert(fixedBody.contains('href="' + URL.getOrgDomainUrl().toExternalForm() + '/' + context.request.Id + '"'));
    }

    @IsTest
    static void coverageEmailsGoToRequesterAndCoverageRep() {
        RequestContext context = lifeScienceRequest();

        List<LSTemporaryAccessExceptionEmailService.ComposedNotification> granted =
            LSTemporaryAccessExceptionEmailService.buildNotifications(
                new List<Id>{ context.request.Id },
                LSTemporaryAccessExceptionEmailService.TYPE_COVERAGE_GRANTED
            );
        List<LSTemporaryAccessExceptionEmailService.ComposedNotification> revoked =
            LSTemporaryAccessExceptionEmailService.buildNotifications(
                new List<Id>{ context.request.Id },
                LSTemporaryAccessExceptionEmailService.TYPE_COVERAGE_REVOKED
            );

        System.assertEquals(
            new Set<Id>{ context.requester.Id, context.coverageRep.Id },
            recipientIds(granted)
        );
        System.assertEquals(LSTemporaryAccessExceptionEmailService.SUBJECT_COVERAGE_GRANTED, granted[0].subject);
        System.assert(granted[0].htmlBody.contains('has been granted'));
        System.assertEquals(
            new Set<Id>{ context.requester.Id, context.coverageRep.Id },
            recipientIds(revoked)
        );
        System.assertEquals(LSTemporaryAccessExceptionEmailService.SUBJECT_COVERAGE_REVOKED, revoked[0].subject);
        System.assert(revoked[0].htmlBody.contains('has been revoked'));
    }

    @IsTest
    static void invocableLogsAndDoesNotThrow() {
        RequestContext context = lifeScienceRequest();
        LSTemporaryAccessExceptionEmailService.NotificationInput input =
            new LSTemporaryAccessExceptionEmailService.NotificationInput();
        input.temporaryAccessExceptionId = context.request.Id;
        input.notificationType = LSTemporaryAccessExceptionEmailService.TYPE_APPROVED;
        LSTemporaryAccessExceptionEmailService.skipSendForTest = true;

        LSTemporaryAccessExceptionEmailService.sendNotification(
            new List<LSTemporaryAccessExceptionEmailService.NotificationInput>{ input }
        );

        System.assertEquals(true, LSTemporaryAccessExceptionEmailService.skipSendForTest);
    }

    private static RequestContext lifeScienceRequest() {
        Profile lifeScienceProfile = lifeScienceProfile();
        User requesterManager = insertUser(lifeScienceProfile.Id, 'lsRmg', null);
        User coverageManager = insertUser(lifeScienceProfile.Id, 'lsMgr', null);
        User requester = insertUser(lifeScienceProfile.Id, 'lsReq', requesterManager.Id);
        User coverageRep = insertUser(lifeScienceProfile.Id, 'lsCov', coverageManager.Id);
        User submitter = insertUser(lifeScienceProfile.Id, 'lsSub', null);
        stopTemporaryAccessFlows(submitter.Id);

        TemporaryAccessException__c request = newRequest(requester.Id, coverageRep.Id);
        System.runAs(submitter) {
            insert request;
        }

        RequestContext context = new RequestContext();
        context.requesterManager = requesterManager;
        context.coverageManager = coverageManager;
        context.requester = requester;
        context.coverageRep = coverageRep;
        context.submitter = submitter;
        context.request = request;
        return context;
    }

    private static TemporaryAccessException__c newRequest(Id requesterId, Id coverageRepId) {
        return new TemporaryAccessException__c(
            Requester__c = requesterId,
            CoverageRep__c = coverageRepId,
            ExceptionCategory__c = 'PTO',
            StartDate__c = Date.today(),
            EndDate__c = Date.today().addDays(5)
        );
    }

    private static Profile lifeScienceProfile() {
        List<Profile> profiles = [
            SELECT Id
            FROM Profile
            WHERE Name = :LSTemporaryAccessExceptionEmailService.LIFE_SCIENCE_SALES_PROFILE
            LIMIT 1
        ];
        System.assertEquals(1, profiles.size(), 'Life Sciences Sales profile must exist in the target org');
        return profiles[0];
    }

    private static void stopTemporaryAccessFlows(Id userId) {
        insert new Automation_Setting_Flow__c(
            SetupOwnerId = userId,
            TemporaryAccessSubmitForApproval__c = true,
            TemporaryAccessApprovalProcess__c = true,
            LSTemporaryAccessApprovalProcess__c = true
        );
    }

    private static Id nonLifeScienceProfileId() {
        Profile runningUserProfile = [
            SELECT Name
            FROM Profile
            WHERE Id = :UserInfo.getProfileId()
        ];
        if (runningUserProfile.Name != LSTemporaryAccessExceptionEmailService.LIFE_SCIENCE_SALES_PROFILE) {
            return runningUserProfile.Id;
        }
        return [
            SELECT Id
            FROM Profile
            WHERE Name != :LSTemporaryAccessExceptionEmailService.LIFE_SCIENCE_SALES_PROFILE
              AND UserType = 'Standard'
            LIMIT 1
        ].Id;
    }

    private static Integer userSequence = 0;

    private static User insertUser(Id profileId, String aliasSeed, Id managerId) {
        userSequence++;
        String token = String.valueOf(DateTime.now().getTime()) + userSequence + aliasSeed;
        User user = new User(
            Alias = aliasSeed.left(8),
            Email = token + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = aliasSeed,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profileId,
            TimeZoneSidKey = 'America/New_York',
            Username = token + '@lstae.test',
            ManagerId = managerId
        );
        insert user;
        if (profileId == lifeScienceProfile().Id) {
            insert new PermissionSetAssignment(AssigneeId = user.Id, PermissionSetGroupId = lifeSciencePermissionSetGroupId());
        }
        return user;
    }

    private static Id lifeSciencePsgId;

    private static Id lifeSciencePermissionSetGroupId() {
        if (lifeSciencePsgId == null) {
            lifeSciencePsgId = [SELECT Id FROM PermissionSetGroup WHERE DeveloperName = 'LSInsideSalesPSG' LIMIT 1].Id;
            Test.calculatePermissionSetGroup(lifeSciencePsgId);
        }
        return lifeSciencePsgId;
    }

    private static void assertCc(List<String> actual, List<String> expected) {
        System.assertEquals(lowerCase(expected), lowerCase(actual));
    }

    private static Set<String> lowerCase(List<String> addresses) {
        Set<String> values = new Set<String>();
        for (String address : addresses) {
            values.add(address.toLowerCase());
        }
        return values;
    }

    private static Set<Id> recipientIds(List<LSTemporaryAccessExceptionEmailService.ComposedNotification> notifications) {
        Set<Id> recipients = new Set<Id>();
        for (LSTemporaryAccessExceptionEmailService.ComposedNotification notification : notifications) {
            recipients.add(notification.toUserId);
        }
        return recipients;
    }

    private class RequestContext {
        User requesterManager;
        User coverageManager;
        User requester;
        User coverageRep;
        User submitter;
        TemporaryAccessException__c request;
    }
}