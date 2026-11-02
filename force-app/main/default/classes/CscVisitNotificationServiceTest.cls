/**
 * @author Abhishek Mishra
 * @date 23-10-2026
 * @description #GC-3518 Submit checks, Team Member bell, and email.
 *              #GC-3562 CSC Account Team, manager, queue, and PDM email.
 */
@IsTest(SeeAllData=false)
private class CscVisitNotificationServiceTest {
    @TestSetup
    static void setupData() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<User>{
                testUser('stakeholder', 'stake'),
                testUser('attendee', 'attend')
            };
        }
    }

    @IsTest
    static void requestedConfirmedAndPostponedNotifyOnlyTeamMembers() {
        disableValidationRules();
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

        CscVisitNotificationService.lastNotifiedUserIds.clear();
        CscVisitNotificationService.lastEmailedUserIds.clear();
        notify(visit, CscVisitRequestSelector.STATUS_DRAFT, CscVisitRequestSelector.STATUS_REQUESTED, null, null);

        System.assertEquals(
            new Set<Id>{ stakeholder.Id },
            new Set<Id>(CscVisitNotificationService.lastNotifiedUserIds),
            'Requested bell goes to the Team Member only'
        );
        System.assertEquals(
            new Set<Id>{ stakeholder.Id },
            new Set<Id>(CscVisitNotificationService.lastEmailedUserIds),
            'Requested email goes to the same Team Member'
        );

        CscVisitNotificationService.lastNotifiedUserIds.clear();
        notify(
            visit,
            CscVisitRequestSelector.STATUS_REQUESTED,
            CscVisitRequestSelector.STATUS_CONFIRMED,
            null,
            Date.today().addDays(10)
        );
        System.assertEquals(new Set<Id>{ stakeholder.Id }, notifiedIds());

        CscVisitNotificationService.lastNotifiedUserIds.clear();
        notify(
            visit,
            CscVisitRequestSelector.STATUS_CONFIRMED,
            CscVisitRequestSelector.STATUS_POSTPONED,
            Date.today().addDays(10),
            Date.today().addDays(10)
        );
        System.assertEquals(new Set<Id>{ stakeholder.Id }, notifiedIds());

        CscVisitNotificationService.lastNotifiedUserIds.clear();
        visit.Status__c = CscVisitRequestSelector.STATUS_REQUESTED;
        update visit;
        System.assertEquals(
            new Set<Id>{ stakeholder.Id },
            notifiedIds(),
            'Saving the visit notifies the Team Member'
        );
    }

    @IsTest
    static void severalVisitsEmailAllTeamMembersInOneSend() {
        disableValidationRules();
        User firstMember = testUser('bulkone', 'bulkone');
        User secondMember = testUser('bulktwo', 'bulktwo');
        insert new List<User>{ firstMember, secondMember };

        List<CSC_Visit_Request__c> visits = new List<CSC_Visit_Request__c>{
            new CSC_Visit_Request__c(
                VisitType__c = CscVisitRequestSelector.REQUEST_ORC,
                Status__c = CscVisitRequestSelector.STATUS_DRAFT
            ),
            new CSC_Visit_Request__c(
                VisitType__c = CscVisitRequestSelector.REQUEST_IMS,
                Status__c = CscVisitRequestSelector.STATUS_DRAFT
            )
        };
        insert visits;
        insert new List<TeamMember__c>{
            new TeamMember__c(
                CSCVisitRequest__c = visits[0].Id,
                User__c = firstMember.Id,
                AccessLevel__c = 'Read'
            ),
            new TeamMember__c(
                CSCVisitRequest__c = visits[1].Id,
                User__c = secondMember.Id,
                AccessLevel__c = 'Read'
            )
        };

        List<CSC_Visit_Request__c> currentVisits = new List<CSC_Visit_Request__c>();
        Map<Id, CSC_Visit_Request__c> priorVisits = new Map<Id, CSC_Visit_Request__c>();
        for (CSC_Visit_Request__c visit : visits) {
            CSC_Visit_Request__c currentVisit = visit.clone(true, true, true, true);
            currentVisit.Status__c = CscVisitRequestSelector.STATUS_REQUESTED;
            currentVisits.add(currentVisit);
            CSC_Visit_Request__c priorVisit = visit.clone(true, true, true, true);
            priorVisit.Status__c = CscVisitRequestSelector.STATUS_DRAFT;
            priorVisits.put(visit.Id, priorVisit);
        }

        CscVisitNotificationService.lastEmailedUserIds.clear();
        Integer emailCallsBefore = Limits.getEmailInvocations();
        CscVisitNotificationService.notifyAfterSave(currentVisits, priorVisits);

        System.assertEquals(
            new Set<Id>{ firstMember.Id, secondMember.Id },
            new Set<Id>(CscVisitNotificationService.lastEmailedUserIds),
            'Every Team Member in the batch is emailed'
        );
        System.assertEquals(
            emailCallsBefore + 1,
            Limits.getEmailInvocations(),
            'The batch uses one email send'
        );
    }

    @IsTest
    static void cscVisitDoesNotNotifyTeamMembers() {
        disableValidationRules();
        User stakeholder = userByAlias('stake');
        CSC_Visit_Request__c visit = insertVisit(CscVisitRequestSelector.REQUEST_CSC);
        insert new TeamMember__c(
            CSCVisitRequest__c = visit.Id,
            User__c = stakeholder.Id,
            AccessLevel__c = 'Read'
        );

        CscVisitNotificationService.lastNotifiedUserIds.clear();
        notify(visit, CscVisitRequestSelector.STATUS_DRAFT, CscVisitRequestSelector.STATUS_REQUESTED, null, null);

        System.assertEquals(0, CscVisitNotificationService.lastNotifiedUserIds.size());

        visit.Status__c = CscVisitRequestSelector.STATUS_REQUESTED;
        update visit;
        System.assertEquals(0, CscVisitNotificationService.lastNotifiedUserIds.size());
    }

    @IsTest
    static void confirmedCscVisitEmailsOracleTeamManagerAndQueue() {
        disableValidationRules();
        User manager = testUser('gc3562mgr');
        insert manager;
        User teamMember = testUser('gc3562tm');
        teamMember.ManagerId = manager.Id;
        insert teamMember;

        Account accountRecord = new Account(Name = 'GC3562 Account');
        insert accountRecord;
        Opportunity opportunityRecord = new Opportunity(
            Name = 'GC3562 Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opportunityRecord;
        insert new AccountTeamMember(
            AccountId = accountRecord.Id,
            UserId = teamMember.Id,
            TeamMemberRole = 'Sales',
            AssignmentType__c = Label.CSC_Oracle_Assigned_Assignment_Type,
            AccountAccessLevel = 'Edit',
            OpportunityAccessLevel = 'Edit',
            CaseAccessLevel = 'None'
        );

        CSC_Visit_Request__c visit = new CSC_Visit_Request__c(
            VisitType__c = CscVisitRequestSelector.REQUEST_CSC,
            Status__c = CscVisitRequestSelector.STATUS_APPROVED,
            Opportunity__c = opportunityRecord.Id,
            PlanningDesignRequired__c = 'No',
            Confirmed_Date__c = Date.today().addDays(7)
        );
        insert visit;
        visit.Status__c = CscVisitRequestSelector.STATUS_CONFIRMED;

        CscVisitNotificationService.lastStakeholderIds.clear();
        CscVisitNotificationService.notifyAfterSave(
            new List<CSC_Visit_Request__c>{ visit },
            new Map<Id, CSC_Visit_Request__c>{
                visit.Id => new CSC_Visit_Request__c(
                    Id = visit.Id,
                    Status__c = CscVisitRequestSelector.STATUS_APPROVED,
                    VisitType__c = CscVisitRequestSelector.REQUEST_CSC,
                    Opportunity__c = opportunityRecord.Id,
                    PlanningDesignRequired__c = 'No'
                )
            }
        );

        Set<Id> recipients = new Set<Id>(CscVisitNotificationService.lastStakeholderIds);
        System.assert(recipients.contains(teamMember.Id), 'Oracle Assigned account team user is included.');
        System.assert(recipients.contains(manager.Id), 'Direct manager is included.');
        System.assertEquals(
            0,
            CscVisitNotificationService.lastPdmIds.size(),
            'Planning and Design is not required.'
        );
    }

    @IsTest
    static void planningRequiredEmailsMatchingPdmOnly() {
        disableValidationRules();
        User pdm = testUser('gc3562pdm');
        insert pdm;
        Account accountRecord = new Account(Name = 'GC3562 PDM Account');
        insert accountRecord;
        Opportunity opportunityRecord = new Opportunity(
            Name = 'GC3562 PDM Opportunity',
            AccountId = accountRecord.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opportunityRecord;
        insert new AccountTeamMember(
            AccountId = accountRecord.Id,
            UserId = pdm.Id,
            TeamMemberRole = 'Sales',
            AssignmentType__c = 'Salesforce Assigned',
            TerritoryCode__c = Label.CSC_PDM_Territory_Code,
            SalesCategoryCode__c = 'SURG SPT',
            AccountAccessLevel = 'Edit',
            OpportunityAccessLevel = 'Edit',
            CaseAccessLevel = 'None'
        );

        CSC_Visit_Request__c visit = new CSC_Visit_Request__c(
            VisitType__c = CscVisitRequestSelector.REQUEST_CSC,
            Status__c = CscVisitRequestSelector.STATUS_CONFIRMED,
            Opportunity__c = opportunityRecord.Id,
            PlanningDesignRequired__c = 'Yes',
            Confirmed_Date__c = Date.today().addDays(7)
        );
        insert visit;

        CscVisitNotificationService.lastPdmIds.clear();
        CscVisitNotificationService.notifyAfterSave(
            new List<CSC_Visit_Request__c>{ visit },
            new Map<Id, CSC_Visit_Request__c>{
                visit.Id => new CSC_Visit_Request__c(
                    Id = visit.Id,
                    Status__c = CscVisitRequestSelector.STATUS_APPROVED,
                    VisitType__c = CscVisitRequestSelector.REQUEST_CSC,
                    Opportunity__c = opportunityRecord.Id,
                    PlanningDesignRequired__c = 'No'
                )
            }
        );

        System.assertEquals(
            new Set<Id>{ pdm.Id },
            new Set<Id>(CscVisitNotificationService.lastPdmIds)
        );
    }

    @IsTest
    static void nonCscVisitDoesNotEmailStakeholders() {
        disableValidationRules();
        CSC_Visit_Request__c visit = new CSC_Visit_Request__c(
            VisitType__c = CscVisitRequestSelector.REQUEST_ORC,
            Status__c = CscVisitRequestSelector.STATUS_CONFIRMED,
            PlanningDesignRequired__c = 'Yes'
        );
        insert visit;

        CscVisitNotificationService.lastStakeholderIds.clear();
        CscVisitNotificationService.lastPdmIds.clear();
        CscVisitNotificationService.notifyAfterSave(
            new List<CSC_Visit_Request__c>{ visit },
            new Map<Id, CSC_Visit_Request__c>{
                visit.Id => new CSC_Visit_Request__c(
                    Id = visit.Id,
                    Status__c = CscVisitRequestSelector.STATUS_APPROVED,
                    VisitType__c = CscVisitRequestSelector.REQUEST_ORC
                )
            }
        );

        System.assertEquals(0, CscVisitNotificationService.lastStakeholderIds.size());
        System.assertEquals(0, CscVisitNotificationService.lastPdmIds.size());
    }

    @IsTest
    static void blankPurposeBlocksRequestedStatus() {
        Id visitId = fakeId();
        CSC_Visit_Request__c currentVisit = requestedVisit(visitId);
        currentVisit.Visit_Purpose__c = null;

        CscVisitRequestService.requireFieldsOnSubmit(
            new List<CSC_Visit_Request__c>{ currentVisit },
            priorVisits(visitId)
        );

        System.assert(hasMessage(currentVisit, 'Visit Purpose'));
    }

    @IsTest
    static void otherPurposeRequiresExplanation() {
        Id visitId = fakeId();
        CSC_Visit_Request__c currentVisit = requestedVisit(visitId);
        currentVisit.RecordTypeId = Schema.SObjectType.CSC_Visit_Request__c
            .getRecordTypeInfosByDeveloperName()
            .get('CSCVisitRequest')
            .getRecordTypeId();
        currentVisit.Visit_Purpose__c = 'Other';

        CscVisitRequestService.requireFieldsOnSubmit(
            new List<CSC_Visit_Request__c>{ currentVisit },
            priorVisits(visitId)
        );

        System.assert(hasMessage(currentVisit, 'Other is selected'));
    }

    @IsTest
    static void completeRequestHasNoSubmitError() {
        Id visitId = fakeId();
        CSC_Visit_Request__c currentVisit = requestedVisit(visitId);
        currentVisit.Visit_Purpose__c = 'Product Evaluation';

        CscVisitRequestService.requireFieldsOnSubmit(
            new List<CSC_Visit_Request__c>{ currentVisit },
            priorVisits(visitId)
        );

        System.assertEquals(0, currentVisit.getErrors().size());
    }

    private static void disableValidationRules() {
        insert new Automation_Setting_Validation_Rule__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            disableAll__c = true
        );
    }

    private static CSC_Visit_Request__c requestedVisit(Id visitId) {
        return new CSC_Visit_Request__c(
            Id = visitId,
            Status__c = CscVisitRequestSelector.STATUS_REQUESTED,
            Primary_Requested_Date__c = Date.today().addDays(10),
            Backup_Requested_Date__c = Date.today().addDays(12),
            PrimaryObjective__c = 'Review the installed base'
        );
    }

    private static Map<Id, CSC_Visit_Request__c> priorVisits(Id visitId) {
        return new Map<Id, CSC_Visit_Request__c>{
            visitId => new CSC_Visit_Request__c(
                Id = visitId,
                Status__c = CscVisitRequestSelector.STATUS_DRAFT
            )
        };
    }

    private static Boolean hasMessage(CSC_Visit_Request__c visit, String expectedText) {
        for (Database.Error errorRow : visit.getErrors()) {
            if (errorRow.getMessage().contains(expectedText)) {
                return true;
            }
        }
        return false;
    }

    private static Integer sequence = 1;

    private static Id fakeId() {
        String suffix = String.valueOf(sequence++);
        return (Id) ('a2L' + '0'.repeat(12 - suffix.length()) + suffix);
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
        CscVisitNotificationService.notifyAfterSave(
            new List<CSC_Visit_Request__c>{ currentVisit },
            new Map<Id, CSC_Visit_Request__c>{ visit.Id => priorVisit }
        );
    }

    private static Set<Id> notifiedIds() {
        return new Set<Id>(CscVisitNotificationService.lastNotifiedUserIds);
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
        User recipient = testUser(stem);
        recipient.Alias = aliasValue;
        return recipient;
    }

    private static User testUser(String stem) {
        String uniqueName = stem + DateTime.now().getTime() + '@example.com';
        return new User(
            Alias = stem.right(8),
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