/**
 * @author Abhishek Mishra
 * @date 20-10-2026
 * @description #GC-3518 Tests bell notifications for ORC, IMS, and OSV Team Members.
 */
@IsTest(SeeAllData=false)
private class CscVisitTeamNotificationServiceTest {
    @TestSetup
    static void setupData() {
        insert new Automation_Setting_Validation_Rule__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            disableAll__c = true
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<User>{
                testUser('stakeholder', 'stake'),
                testUser('attendee', 'attend')
            };
        }
    }

    @IsTest
    static void requestedConfirmedAndPostponedNotifyOnlyTeamMembers() {
        User stakeholder = userByAlias('stake');
        User attendee = userByAlias('attend');
        CSC_Visit_Request__c visit = insertVisit(CscVisitRequestSelector.REQUEST_ORC);
        insert new TeamMember__c(
            CSCVisitRequest__c = visit.Id,
            User__c = stakeholder.Id,
            AccessLevel__c = 'Read'
        );
        insert new CSCVisitAttendee__c(
            CSCVisit__c = visit.Id,
            STERISAttendee__c = attendee.Id,
            AttendeeType__c = 'STERIS'
        );

        CscVisitTeamNotificationService.lastNotifiedUserIds.clear();
        notify(visit, CscVisitRequestSelector.STATUS_DRAFT, CscVisitRequestSelector.STATUS_REQUESTED, null, null);

        System.assertEquals(
            new Set<Id>{ stakeholder.Id },
            new Set<Id>(CscVisitTeamNotificationService.lastNotifiedUserIds),
            'Requested bell goes to the Team Member only'
        );

        CscVisitTeamNotificationService.lastNotifiedUserIds.clear();
        notify(
            visit,
            CscVisitRequestSelector.STATUS_REQUESTED,
            CscVisitRequestSelector.STATUS_CONFIRMED,
            null,
            Date.today().addDays(10)
        );
        System.assertEquals(new Set<Id>{ stakeholder.Id }, notifiedIds());

        CscVisitTeamNotificationService.lastNotifiedUserIds.clear();
        notify(
            visit,
            CscVisitRequestSelector.STATUS_CONFIRMED,
            CscVisitRequestSelector.STATUS_POSTPONED,
            Date.today().addDays(10),
            Date.today().addDays(10)
        );
        System.assertEquals(new Set<Id>{ stakeholder.Id }, notifiedIds());

        CscVisitTeamNotificationService.lastNotifiedUserIds.clear();
        visit.Status__c = CscVisitRequestSelector.STATUS_REQUESTED;
        update visit;
        System.assertEquals(
            new Set<Id>{ stakeholder.Id },
            notifiedIds(),
            'Saving the visit notifies the Team Member'
        );
    }

    @IsTest
    static void cscVisitDoesNotUseThisNotification() {
        User stakeholder = userByAlias('stake');
        CSC_Visit_Request__c visit = insertVisit(CscVisitRequestSelector.REQUEST_CSC);
        insert new TeamMember__c(
            CSCVisitRequest__c = visit.Id,
            User__c = stakeholder.Id,
            AccessLevel__c = 'Read'
        );

        CscVisitTeamNotificationService.lastNotifiedUserIds.clear();
        notify(visit, CscVisitRequestSelector.STATUS_DRAFT, CscVisitRequestSelector.STATUS_REQUESTED, null, null);

        System.assertEquals(0, CscVisitTeamNotificationService.lastNotifiedUserIds.size());

        visit.Status__c = CscVisitRequestSelector.STATUS_REQUESTED;
        update visit;
        System.assertEquals(0, CscVisitTeamNotificationService.lastNotifiedUserIds.size());
    }

    private static void notify(
        CSC_Visit_Request__c visit,
        String priorStatus,
        String newStatus,
        Date priorDate,
        Date newDate
    ) {
        CSC_Visit_Request__c currentVisit = visit.clone(true, true, true, true);
        currentVisit.Status__c = newStatus;
        currentVisit.Confirmed_Date__c = newDate;
        CSC_Visit_Request__c priorVisit = visit.clone(true, true, true, true);
        priorVisit.Status__c = priorStatus;
        priorVisit.Confirmed_Date__c = priorDate;
        CscVisitTeamNotificationService.notifyAfterSave(
            new List<CSC_Visit_Request__c>{ currentVisit },
            new Map<Id, CSC_Visit_Request__c>{ visit.Id => priorVisit }
        );
    }

    private static Set<Id> notifiedIds() {
        return new Set<Id>(CscVisitTeamNotificationService.lastNotifiedUserIds);
    }

    private static CSC_Visit_Request__c insertVisit(String requestType) {
        CSC_Visit_Request__c visit = new CSC_Visit_Request__c(
            VisitType__c = requestType,
            Status__c = CscVisitRequestSelector.STATUS_DRAFT
        );
        insert visit;
        return visit;
    }

    private static User userByAlias(String aliasValue) {
        return [
            SELECT Id
            FROM User
            WHERE Alias = :aliasValue
            LIMIT 1
        ];
    }

    private static User testUser(String stem, String aliasValue) {
        String uniqueName = stem + DateTime.now().getTime() + '@example.com';
        return new User(
            Alias = aliasValue,
            Email = uniqueName,
            EmailEncodingKey = 'UTF-8',
            LastName = stem,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'America/New_York',
            Username = uniqueName
        );
    }
}