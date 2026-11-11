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
        System.assertEquals(context.coverageManager.Id, notifications[0].toUserId);
        System.assertEquals(
            LSTemporaryAccessExceptionEmailService.SUBJECT_APPROVAL_NEEDED,
            notifications[0].subject
        );
        System.assert(notifications[0].htmlBody.contains('requires your approval'));
        System.assert(notifications[0].htmlBody.contains('Coverage Duration'));
        assertCc(
            notifications[0].ccAddresses,
            new List<String>{
                context.requester.Email,
                context.coverageRep.Email,
                context.submitter.Email
            }
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
        System.assertEquals(context.coverageManager.Id, notifications[0].toUserId);
        System.assertEquals(LSTemporaryAccessExceptionEmailService.SUBJECT_GRANTED, notifications[0].subject);
        System.assert(notifications[0].htmlBody.contains('has been approved for the following request'));
        assertCc(
            notifications[0].ccAddresses,
            new List<String>{
                context.requester.Email,
                context.coverageRep.Email,
                context.submitter.Email
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
        System.assertEquals(context.coverageManager.Id, notifications[0].toUserId);
        System.assertEquals(LSTemporaryAccessExceptionEmailService.SUBJECT_REJECTED, notifications[0].subject);
        System.assert(notifications[0].htmlBody.contains('has been rejected for the following request'));
        System.assert(notifications[0].htmlBody.contains('reach out to your manager'));
        assertCc(
            notifications[0].ccAddresses,
            new List<String>{
                context.requester.Email,
                context.coverageRep.Email,
                context.submitter.Email
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
        System.assertEquals(context.coverageManager.Id, notifications[0].toUserId);
        System.assertEquals(LSTemporaryAccessExceptionEmailService.SUBJECT_EXPIRED, notifications[0].subject);
        System.assert(notifications[0].htmlBody.contains('has expired and access has been removed'));
        assertCc(
            notifications[0].ccAddresses,
            new List<String>{
                context.requester.Email,
                context.coverageRep.Email,
                context.submitter.Email
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
        System.assertEquals(context.coverageManager.Id, notifications[0].toUserId);
        System.assertEquals(LSTemporaryAccessExceptionEmailService.SUBJECT_EXPIRING, notifications[0].subject);
        System.assert(notifications[0].htmlBody.contains('expiring in 3 days'));
        System.assert(notifications[0].htmlBody.contains('/' + context.request.Id + '"'), 'Request name links to the record');
        assertCc(
            notifications[0].ccAddresses,
            new List<String>{
                context.requester.Email,
                context.coverageRep.Email,
                context.submitter.Email
            }
        );
    }

    @IsTest
    static void activeDelegatedApproverIsCopiedOnce() {
        RequestContext context = lifeScienceRequest();
        User delegate = insertUser(lifeScienceProfile().Id, 'lsDel', null);
        context.coverageManager.DelegatedApproverId = delegate.Id;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update context.coverageManager;
        }

        List<LSTemporaryAccessExceptionEmailService.ComposedNotification> notifications =
            LSTemporaryAccessExceptionEmailService.buildNotifications(
                new List<Id>{ context.request.Id },
                LSTemporaryAccessExceptionEmailService.TYPE_APPROVAL_NEEDED
            );

        System.assertEquals(
            new Set<Id>{ context.coverageManager.Id },
            recipientIds(notifications)
        );
        for (LSTemporaryAccessExceptionEmailService.ComposedNotification notification : notifications) {
            assertCc(
                notification.ccAddresses,
                new List<String>{
                    context.requester.Email,
                    context.coverageRep.Email,
                    context.submitter.Email
                }
            );
        }
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
            new Set<Id>{ context.coverageManager.Id },
            recipientIds(granted)
        );
        System.assertEquals(LSTemporaryAccessExceptionEmailService.SUBJECT_COVERAGE_GRANTED, granted[0].subject);
        System.assert(granted[0].htmlBody.contains('has been granted'));
        assertCc(
            granted[0].ccAddresses,
            new List<String>{
                context.requester.Email,
                context.coverageRep.Email,
                context.submitter.Email
            }
        );
        System.assertEquals(
            new Set<Id>{ context.coverageManager.Id },
            recipientIds(revoked)
        );
        System.assertEquals(LSTemporaryAccessExceptionEmailService.SUBJECT_COVERAGE_REVOKED, revoked[0].subject);
        System.assert(revoked[0].htmlBody.contains('has been revoked'));
        assertCc(
            revoked[0].ccAddresses,
            new List<String>{
                context.requester.Email,
                context.coverageRep.Email,
                context.submitter.Email
            }
        );
    }

    @IsTest
    static void coverageEmailListsRequesterTerritoryNumbers() {
        RequestContext context = lifeScienceRequest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<OrderLineContact__c>{
                new OrderLineContact__c(
                    AssignedSalesRep__c = context.requester.Id,
                    TerritoryNumber__c = 'L11217'
                ),
                new OrderLineContact__c(
                    AssignedSalesRep__c = context.requester.Id,
                    TerritoryNumber__c = 'L66301'
                ),
                new OrderLineContact__c(
                    AssignedSalesRep__c = context.coverageRep.Id,
                    TerritoryNumber__c = 'SHOULD-NOT-SHOW'
                )
            };
        }

        List<LSTemporaryAccessExceptionEmailService.ComposedNotification> granted =
            LSTemporaryAccessExceptionEmailService.buildNotifications(
                new List<Id>{ context.request.Id },
                LSTemporaryAccessExceptionEmailService.TYPE_COVERAGE_GRANTED
            );

        System.assert(granted[0].htmlBody.contains('L66301'));
        System.assert(granted[0].htmlBody.contains('L11217'));
        System.assert(!granted[0].htmlBody.contains('SHOULD-NOT-SHOW'));
        System.assert(!granted[0].htmlBody.contains('{{LS_TERRITORY_ROWS}}'));
        System.assert(
            granted[0].htmlBody.indexOf('L11217') < granted[0].htmlBody.indexOf('L66301'),
            'Territory numbers should be listed in sort order'
        );
    }

    @IsTest
    static void coverageEmailListsTerritoriesOnTheCoveredAccount() {
        RequestContext context = lifeScienceRequest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Account covered = new Account(Name = 'TAE Territory Account');
            insert covered;
            insert new TAE_AssignedRecord__c(
                TemporaryAccessException__c = context.request.Id,
                Account__c = covered.Id
            );
            insert new OrderLineContact__c(
                TASAddressId__c = covered.Id,
                TerritoryNumber__c = 'S11102'
            );
            insert new OrderLineContact__c(
                TASAddressId__c = '001000000000099',
                TerritoryNumber__c = 'NOT-ON-REQUEST'
            );
        }

        List<LSTemporaryAccessExceptionEmailService.ComposedNotification> granted =
            LSTemporaryAccessExceptionEmailService.buildNotifications(
                new List<Id>{ context.request.Id },
                LSTemporaryAccessExceptionEmailService.TYPE_COVERAGE_GRANTED
            );

        System.assert(granted[0].htmlBody.contains('S11102'));
        System.assert(!granted[0].htmlBody.contains('NOT-ON-REQUEST'));
        System.assert(!granted[0].htmlBody.contains('{{LS_TERRITORY_ROWS}}'));
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

    @IsTest
    static void invalidFromAddressIsLoggedAndDoesNotThrow() {
        RequestContext context = lifeScienceRequest();
        LSTemporaryAccessExceptionEmailService.fromAddressLoaded = true;
        LSTemporaryAccessExceptionEmailService.fromAddressId = UserInfo.getUserId();
        LSTemporaryAccessExceptionEmailService.NotificationInput input =
            new LSTemporaryAccessExceptionEmailService.NotificationInput();
        input.temporaryAccessExceptionId = context.request.Id;
        input.notificationType = LSTemporaryAccessExceptionEmailService.TYPE_APPROVED;

        LSTemporaryAccessExceptionEmailService.sendNotification(
            new List<LSTemporaryAccessExceptionEmailService.NotificationInput>{ input }
        );

        System.assertEquals(true, LSTemporaryAccessExceptionEmailService.fromAddressLoaded);
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
            StartDate__c = Date.today().addDays(1),
            EndDate__c = Date.today().addDays(6)
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
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new Automation_Setting_Flow__c(
                SetupOwnerId = userId,
                TemporaryAccessSubmitForApproval__c = true,
                TemporaryAccessApprovalProcess__c = true,
                LSTemporaryAccessApprovalProcess__c = true
            );
        }
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
            grantTemporaryAccessAccess(user.Id);
        }
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