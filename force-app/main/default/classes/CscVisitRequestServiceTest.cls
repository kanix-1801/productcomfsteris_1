/**
 * @author Abhishek Mishra
 * @date 27-08-2026
 * @description #GC-3302 Tests visit-location Pending and Unavailable dates.
 */
@IsTest(SeeAllData=false)
private class CscVisitRequestServiceTest {
    private static final String LOCATION = 'Customer Solution Center (Mentor, OH)';
    private static Id cachedOpportunityId;

    @TestSetup
    static void disableUnrelatedValidationRules() {
        insert new List<SObject>{
            new Automation_Setting_Validation_Rule__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                disableAll__c = true
            ),
            new Automation_Setting_Trigger__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                disableAll__c = false
            )
        };
        System.runAs(new User(Id = UserInfo.getUserId())) {
            User salesRep = new User(
                Alias = 'cscrep',
                Email = 'cscrep@csc.example.test',
                EmailEncodingKey = 'UTF-8',
                LastName = 'VisitSalesRep',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = healthcareSalesProfileId(),
                UserRoleId = internalRoleId(),
                TimeZoneSidKey = 'America/New_York',
                Username = 'cscrep' + DateTime.now().getTime() + '@csc.example.test'
            );
            insert salesRep;
            assignPermissionSetGroup(salesRep.Id, 'SalesFieldRepAccountManagerPSG');
        }
    }

    private static User salesRep() {
        return [SELECT Id FROM User WHERE LastName = 'VisitSalesRep' LIMIT 1];
    }

    private static Id healthcareSalesProfileId() {
        return [SELECT Id FROM Profile WHERE Name = 'Healthcare Sales' LIMIT 1].Id;
    }

    private static Id internalRoleId() {
        return [SELECT Id FROM UserRole WHERE PortalType = 'None' LIMIT 1].Id;
    }

    private static void assignPermissionSetGroup(Id userId, String developerName) {
        PermissionSetGroup permissionSetGroupRecord = [
            SELECT Id, Status
            FROM PermissionSetGroup
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];
        if (permissionSetGroupRecord.Status != 'Updated') {
            Test.calculatePermissionSetGroup(permissionSetGroupRecord.Id);
        }
        insert new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetGroupId = permissionSetGroupRecord.Id
        );
    }

    private static Id testOpportunityId() {
        if (cachedOpportunityId == null) {
            List<Opportunity> existingOpportunities = [SELECT Id FROM Opportunity LIMIT 1];
            if (!existingOpportunities.isEmpty()) {
                cachedOpportunityId = existingOpportunities[0].Id;
            } else {
                Opportunity opportunityRecord = new Opportunity(
                    Name = 'CSC Visit Test Opportunity',
                    StageName = 'Discovery',
                    CloseDate = Date.today().addDays(30),
                    ForecastConfidenceLevel__c = 'Budget'
                );
                insert opportunityRecord;
                cachedOpportunityId = opportunityRecord.Id;
            }
        }
        return cachedOpportunityId;
    }

    private static Date nextWeekday(Integer extraDays) {
        Date value = Date.today().addDays(1);
        Integer skipped = 0;
        while (value < Date.today().addYears(1)) {
            if (!CscVisitRequestService.isWeekend(value)) {
                if (skipped == extraDays) {
                    return value;
                }
                skipped++;
            }
            value = value.addDays(1);
        }
        return null;
    }

    private static Id blockDateRecordTypeId() {
        return [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'CSC_Visit_Request__c'
              AND DeveloperName = 'Block_Date'
            LIMIT 1
        ].Id;
    }

    @IsTest
    static void confirmedDateIsReturnedAsUnavailable() {
        System.runAs(salesRep()) {
        Date confirmedDate = nextWeekday(0);
        Date backupDate = nextWeekday(1);

        insert new CSC_Visit_Request__c(
            VisitLocation__c = LOCATION,
            Opportunity__c = testOpportunityId(),
            Status__c = CscVisitRequestSelector.STATUS_CONFIRMED,
            Primary_Requested_Date__c = confirmedDate,
            Backup_Requested_Date__c = backupDate,
            Confirmed_Date__c = confirmedDate
        );

        Test.startTest();
        List<CscVisitRequestService.UnavailableDate> rows =
            CscAvailabilityController.getUnavailableDates(null, LOCATION, confirmedDate, backupDate);
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'Confirmed date should be unavailable');
        System.assertEquals(String.valueOf(confirmedDate), rows[0].dateValue);
        System.assertEquals(CscVisitRequestSelector.UNAVAILABLE_CONFIRMED, rows[0].reason);
        }
    }

    @IsTest
    static void draftDoesNotBlockTheCalendar() {
        System.runAs(salesRep()) {
        Date primaryDate = nextWeekday(0);
        Date backupDate = nextWeekday(1);

        insert new CSC_Visit_Request__c(
            VisitLocation__c = LOCATION,
            Opportunity__c = testOpportunityId(),
            Status__c = CscVisitRequestSelector.STATUS_DRAFT,
            Primary_Requested_Date__c = primaryDate,
            Backup_Requested_Date__c = backupDate
        );

        Test.startTest();
        List<CscVisitRequestService.UnavailableDate> rows =
            CscVisitRequestService.getUnavailableDates(LOCATION, primaryDate, backupDate);
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'Draft must not grey the calendar');
        }
    }

    @IsTest
    static void isWeekendRecognizesSaturdayAndSunday() {
        System.runAs(salesRep()) {
        System.assertEquals(true, CscVisitRequestService.isWeekend(Date.newInstance(2026, 8, 29)));
        System.assertEquals(true, CscVisitRequestService.isWeekend(Date.newInstance(2026, 8, 30)));
        System.assertEquals(false, CscVisitRequestService.isWeekend(Date.newInstance(2026, 8, 31)));
        System.assertEquals(false, CscVisitRequestService.isWeekend(null));
        System.assertEquals(
            0,
            CscVisitRequestService.getUnavailableDates(LOCATION, null, Date.today()).size()
        );
        }
    }

    @IsTest
    static void requestedPrimaryAndBackupArePending() {
        System.runAs(salesRep()) {
        Date primaryDate = nextWeekday(0);
        Date backupDate = nextWeekday(1);
        insert new CSC_Visit_Request__c(
            VisitLocation__c = LOCATION,
            Opportunity__c = testOpportunityId(),
            Status__c = CscVisitRequestSelector.STATUS_REQUESTED,
            Primary_Requested_Date__c = primaryDate,
            Backup_Requested_Date__c = backupDate
        );

        Test.startTest();
        List<CscVisitRequestService.UnavailableDate> rows =
            CscVisitRequestService.getUnavailableDates(LOCATION, primaryDate, backupDate);
        Test.stopTest();

        Map<String, String> reasonByDate = new Map<String, String>();
        for (CscVisitRequestService.UnavailableDate row : rows) {
            reasonByDate.put(row.dateValue, row.reason);
        }
        System.assertEquals(2, reasonByDate.size());
        System.assertEquals(
            CscVisitRequestSelector.UNAVAILABLE_PENDING,
            reasonByDate.get(String.valueOf(primaryDate))
        );
        System.assertEquals(
            CscVisitRequestSelector.UNAVAILABLE_PENDING,
            reasonByDate.get(String.valueOf(backupDate))
        );
        }
    }

    @IsTest
    static void confirmationReleasesUnusedRequestedDate() {
        System.runAs(salesRep()) {
        Date primaryDate = nextWeekday(0);
        Date backupDate = nextWeekday(1);
        CSC_Visit_Request__c request = new CSC_Visit_Request__c(
            VisitLocation__c = LOCATION,
            Opportunity__c = testOpportunityId(),
            Status__c = CscVisitRequestSelector.STATUS_REQUESTED,
            Primary_Requested_Date__c = primaryDate,
            Backup_Requested_Date__c = backupDate
        );
        insert request;
        request.Status__c = CscVisitRequestSelector.STATUS_CONFIRMED;
        request.Confirmed_Date__c = primaryDate;
        update request;

        List<CscVisitRequestService.UnavailableDate> rows =
            CscVisitRequestService.getUnavailableDates(LOCATION, primaryDate, backupDate);

        System.assertEquals(1, rows.size(), 'Only the confirmed date remains occupied');
        System.assertEquals(String.valueOf(primaryDate), rows[0].dateValue);
        System.assertEquals(CscVisitRequestSelector.UNAVAILABLE_CONFIRMED, rows[0].reason);
        }
    }

    @IsTest
    static void approvedVisitHoldsBothRequestedDates() {
        System.runAs(salesRep()) {
        Date primaryDate = nextWeekday(0);
        Date backupDate = nextWeekday(1);
        insert new CSC_Visit_Request__c(
            VisitLocation__c = LOCATION,
            Opportunity__c = testOpportunityId(),
            Status__c = CscVisitRequestSelector.STATUS_APPROVED,
            Primary_Requested_Date__c = primaryDate,
            Backup_Requested_Date__c = backupDate,
            Hold_Expiry_Date__c = System.now().addDays(10)
        );

        List<CscVisitRequestService.UnavailableDate> rows =
            CscVisitRequestService.getUnavailableDates(LOCATION, primaryDate, backupDate);

        System.assertEquals(2, rows.size(), 'Approved holds both requested dates');
        }
    }

    @IsTest
    static void approvedConfirmedDateDoesNotReleaseTheOtherDate() {
        System.runAs(salesRep()) {
        Date primaryDate = nextWeekday(0);
        Date backupDate = nextWeekday(1);
        insert new CSC_Visit_Request__c(
            VisitLocation__c = LOCATION,
            Opportunity__c = testOpportunityId(),
            Status__c = CscVisitRequestSelector.STATUS_APPROVED,
            Primary_Requested_Date__c = primaryDate,
            Backup_Requested_Date__c = backupDate,
            Confirmed_Date__c = primaryDate,
            Hold_Expiry_Date__c = System.now().addDays(10)
        );

        List<CscVisitRequestService.UnavailableDate> rows =
            CscVisitRequestService.getUnavailableDates(LOCATION, primaryDate, backupDate);

        System.assertEquals(2, rows.size(), 'The backup date stays held until Status is Confirmed');
        }
    }

    @IsTest
    static void expiredApprovedHoldReleasesBothDates() {
        System.runAs(salesRep()) {
        Date primaryDate = nextWeekday(0);
        Date backupDate = nextWeekday(1);
        CSC_Visit_Request__c request = new CSC_Visit_Request__c(
            VisitLocation__c = LOCATION,
            Opportunity__c = testOpportunityId(),
            Status__c = CscVisitRequestSelector.STATUS_APPROVED,
            Primary_Requested_Date__c = primaryDate,
            Backup_Requested_Date__c = backupDate
        );
        insert request;
        // The 10-day hold flow sets a future expiry when Status becomes Approved.
        // Set the past expiry after that so this test covers a released hold.
        request.Hold_Expiry_Date__c = System.now().addMinutes(-1);
        update request;

        List<CscVisitRequestService.UnavailableDate> rows =
            CscVisitRequestService.getUnavailableDates(LOCATION, primaryDate, backupDate);

        System.assertEquals(0, rows.size(), 'An expired Approved hold releases both requested dates');
        }
    }

    @IsTest
    static void blockedDateIsUnavailable() {
        System.runAs(salesRep()) {
        Date blockedDate = nextWeekday(0);
        insert new CSC_Visit_Request__c(
            RecordTypeId = blockDateRecordTypeId(),
            VisitLocation__c = LOCATION,
            Opportunity__c = testOpportunityId(),
            Status__c = CscVisitRequestSelector.STATUS_DRAFT,
            Blocked_Date__c = blockedDate
        );

        List<CscVisitRequestService.UnavailableDate> rows =
            CscVisitRequestService.getUnavailableDates(LOCATION, blockedDate, blockedDate);

        System.assertEquals(1, rows.size(), 'Admin blocked date is unavailable');
        System.assertEquals(String.valueOf(blockedDate), rows[0].dateValue);
        System.assertEquals(CscVisitRequestSelector.UNAVAILABLE_BLOCKED, rows[0].reason);
        }
    }

    @IsTest
    static void postponedVisitReleasesDates() {
        System.runAs(salesRep()) {
        Date primaryDate = nextWeekday(0);
        Date backupDate = nextWeekday(1);
        insert new CSC_Visit_Request__c(
            VisitLocation__c = LOCATION,
            Opportunity__c = testOpportunityId(),
            Status__c = CscVisitRequestSelector.STATUS_POSTPONED,
            Primary_Requested_Date__c = primaryDate,
            Backup_Requested_Date__c = backupDate
        );

        List<CscVisitRequestService.UnavailableDate> rows =
            CscVisitRequestService.getUnavailableDates(LOCATION, primaryDate, backupDate);

        System.assertEquals(0, rows.size(), 'Postponed releases both dates');
        }
    }

    @IsTest
    static void orcDateDoesNotBlockTheCscLocationCalendar() {
        System.runAs(salesRep()) {
        Date visitDate = nextWeekday(0);
        insert new CSC_Visit_Request__c(
            VisitType__c = CscVisitRequestSelector.REQUEST_ORC,
            VisitLocation__c = LOCATION,
            Opportunity__c = testOpportunityId(),
            Status__c = CscVisitRequestSelector.STATUS_CONFIRMED,
            Confirmed_Date__c = visitDate
        );

        List<CscVisitRequestService.UnavailableDate> rows =
            CscVisitRequestService.getUnavailableDates(
                CscVisitRequestSelector.REQUEST_CSC,
                LOCATION,
                visitDate,
                visitDate
            );

        System.assertEquals(0, rows.size(), 'An ORC date stays off the CSC location calendar');
        }
    }

    @IsTest
    static void eachNonCscRequestTypeHasItsOwnCalendar() {
        System.runAs(salesRep()) {
        Date visitDate = nextWeekday(0);
        insert new CSC_Visit_Request__c(
            VisitType__c = CscVisitRequestSelector.REQUEST_ORC,
            VisitLocation__c = LOCATION,
            Opportunity__c = testOpportunityId(),
            Status__c = CscVisitRequestSelector.STATUS_CONFIRMED,
            Confirmed_Date__c = visitDate
        );

        List<CscVisitRequestService.UnavailableDate> orcRows =
            CscVisitRequestService.getUnavailableDates(
                CscVisitRequestSelector.REQUEST_ORC,
                null,
                visitDate,
                visitDate
            );
        List<CscVisitRequestService.UnavailableDate> imsRows =
            CscVisitRequestService.getUnavailableDates(
                CscVisitRequestSelector.REQUEST_IMS,
                null,
                visitDate,
                visitDate
            );

        System.assertEquals(1, orcRows.size(), 'The ORC calendar shows the ORC date');
        System.assertEquals(CscVisitRequestSelector.UNAVAILABLE_CONFIRMED, orcRows[0].reason);
        System.assertEquals(0, imsRows.size(), 'The IMS calendar does not show the ORC date');
        }
    }

    @IsTest
    static void nonCscCalendarIgnoresLocationBlockDates() {
        System.runAs(salesRep()) {
        Date blockedDate = nextWeekday(0);
        insert new CSC_Visit_Request__c(
            RecordTypeId = blockDateRecordTypeId(),
            VisitLocation__c = LOCATION,
            Opportunity__c = testOpportunityId(),
            Blocked_Date__c = blockedDate
        );

        List<CscVisitRequestService.UnavailableDate> rows =
            CscVisitRequestService.getUnavailableDates(
                CscVisitRequestSelector.REQUEST_OSV,
                null,
                blockedDate,
                blockedDate
            );

        System.assertEquals(0, rows.size(), 'A CSC location block does not block the OSV calendar');
        }
    }

    @IsTest
    static void approvalWithoutConfirmedDateAddsError() {
        System.runAs(salesRep()) {
        CSC_Visit_Request__c visit = new CSC_Visit_Request__c(
            VisitLocation__c = LOCATION,
            Opportunity__c = testOpportunityId(),
            Status__c = CscVisitRequestSelector.STATUS_REQUESTED
        );
        insert visit;
        CSC_Visit_Request__c updatedVisit = visit.clone(true, true, true, true);
        updatedVisit.Status__c = CscVisitRequestSelector.STATUS_APPROVED;
        updatedVisit.Confirmed_Date__c = null;

        CscVisitRequestService.requireConfirmedDateForApproval(
            new List<CSC_Visit_Request__c>{ updatedVisit },
            new Map<Id, CSC_Visit_Request__c>{ visit.Id => visit }
        );

        System.assertEquals(true, updatedVisit.hasErrors(), 'Approval without a confirmed date is blocked');
        }
    }

    @IsTest
    static void approvalWithConfirmedDateHasNoError() {
        System.runAs(salesRep()) {
        CscVisitRequestService.requireConfirmedDateForApproval(null, null);
        CscVisitRequestService.requireConfirmedDateForApproval(
            new List<CSC_Visit_Request__c>(),
            null
        );

        CSC_Visit_Request__c visit = new CSC_Visit_Request__c(
            VisitLocation__c = LOCATION,
            Opportunity__c = testOpportunityId(),
            Status__c = CscVisitRequestSelector.STATUS_REQUESTED
        );
        insert visit;
        CSC_Visit_Request__c updatedVisit = visit.clone(true, true, true, true);
        updatedVisit.Status__c = CscVisitRequestSelector.STATUS_APPROVED;
        updatedVisit.Confirmed_Date__c = nextWeekday(0);

        CscVisitRequestService.requireConfirmedDateForApproval(
            new List<CSC_Visit_Request__c>{ updatedVisit },
            new Map<Id, CSC_Visit_Request__c>{ visit.Id => visit }
        );

        System.assertEquals(false, updatedVisit.hasErrors(), 'A confirmed date lets approval through');
        }
    }

    @IsTest
    static void emailRecipientPathsCoverEmptyAndNonCscVisits() {
        System.runAs(salesRep()) {
        CscVisitEmailService.notifyAfterSave(null, null);
        System.assertEquals(
            0,
            CscVisitEmailService.additionalConfirmationRecipients(null, null, null).size()
        );

        Id opportunityId = testOpportunityId();
        CSC_Visit_Request__c orcVisit = new CSC_Visit_Request__c(
            VisitLocation__c = LOCATION,
            Opportunity__c = opportunityId,
            Status__c = CscVisitRequestSelector.STATUS_DRAFT,
            VisitType__c = CscVisitRequestSelector.REQUEST_ORC
        );
        CSC_Visit_Request__c cscVisit = new CSC_Visit_Request__c(
            VisitLocation__c = LOCATION,
            Opportunity__c = opportunityId,
            Status__c = CscVisitRequestSelector.STATUS_DRAFT,
            VisitType__c = CscVisitRequestSelector.REQUEST_CSC
        );
        insert new List<CSC_Visit_Request__c>{ orcVisit, cscVisit };
        cscVisit.PlanningDesignRequired__c = 'Yes';

        Map<Id, List<String>> addresses = CscVisitEmailService.additionalConfirmationRecipients(
            new List<CSC_Visit_Request__c>{ orcVisit, cscVisit },
            null,
            null
        );
        System.assertNotEquals(null, addresses);
        }
    }

    @IsTest
    static void teamGetsStatusEmail() {
        User managerUser;
        User oracleUser;
        User pdmUser;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id salesProfileId = healthcareSalesProfileId();
            Id roleId = internalRoleId();
            managerUser = emailUser('mailmgr', salesProfileId, roleId);
            insert managerUser;
            oracleUser = emailUser('mailorc', salesProfileId, roleId);
            oracleUser.ManagerId = managerUser.Id;
            pdmUser = emailUser('mailpdm', salesProfileId, roleId);
            insert new List<User>{ oracleUser, pdmUser };
        }

        System.runAs(salesRep()) {
            Account facility = new Account(
                Name = 'CSC Email Facility',
                SourceSystemID__c = 'CSCMAIL' + String.valueOf(DateTime.now().getTime())
            );
            insert facility;
            Opportunity opportunityRecord = new Opportunity(
                Name = 'CSC Email Opportunity',
                AccountId = facility.Id,
                StageName = 'Discovery',
                CloseDate = Date.today().addDays(30),
                ForecastConfidenceLevel__c = 'Budget'
            );
            insert opportunityRecord;
            String teamRole = activeTeamRole();
            String accountAccess = teamAccess('Account', 'Edit');
            String opportunityAccess = teamAccess('Opportunity', 'Edit');
            String caseAccess = teamAccess('Case', 'None');
            String contactAccess = teamAccess('Contact', 'Read');
            String memberAccess = visitShareAccess();
            insert new List<AccountTeamMember>{
                new AccountTeamMember(
                    AccountId = facility.Id,
                    UserId = oracleUser.Id,
                    TeamMemberRole = teamRole,
                    AssignmentType__c = Label.CSC_Oracle_Assigned_Assignment_Type,
                    AccountAccessLevel = accountAccess,
                    OpportunityAccessLevel = opportunityAccess,
                    CaseAccessLevel = caseAccess,
                    ContactAccessLevel = contactAccess
                ),
                new AccountTeamMember(
                    AccountId = facility.Id,
                    UserId = pdmUser.Id,
                    TeamMemberRole = teamRole,
                    AssignmentType__c = 'Salesforce Assigned',
                    TerritoryCode__c = Label.CSC_PDM_Territory_Code,
                    SalesCategoryCode__c = 'SURG SPT',
                    AccountAccessLevel = accountAccess,
                    OpportunityAccessLevel = opportunityAccess,
                    CaseAccessLevel = caseAccess,
                    ContactAccessLevel = contactAccess
                )
            };

            CSC_Visit_Request__c orcVisit = emailVisit(
                CscVisitRequestSelector.REQUEST_ORC, facility.Id, opportunityRecord.Id
            );
            CSC_Visit_Request__c imsVisit = emailVisit(
                CscVisitRequestSelector.REQUEST_IMS, facility.Id, opportunityRecord.Id
            );
            CSC_Visit_Request__c osvVisit = emailVisit(
                CscVisitRequestSelector.REQUEST_OSV, facility.Id, opportunityRecord.Id
            );
            CSC_Visit_Request__c cscVisit = emailVisit(
                CscVisitRequestSelector.REQUEST_CSC, facility.Id, opportunityRecord.Id
            );
            cscVisit.PlanningDesignRequired__c = 'Yes';
            insert new List<CSC_Visit_Request__c>{ orcVisit, imsVisit, osvVisit, cscVisit };
            insert new List<TeamMember__c>{
                new TeamMember__c(
                    CSCVisitRequest__c = orcVisit.Id, User__c = oracleUser.Id, AccessLevel__c = memberAccess
                ),
                new TeamMember__c(
                    CSCVisitRequest__c = imsVisit.Id, User__c = oracleUser.Id, AccessLevel__c = memberAccess
                ),
                new TeamMember__c(
                    CSCVisitRequest__c = osvVisit.Id, User__c = oracleUser.Id, AccessLevel__c = memberAccess
                )
            };

            CscVisitEmailService.lastTeamRecipientIds.clear();
            orcVisit.Status__c = CscVisitRequestSelector.STATUS_REQUESTED;
            imsVisit.Status__c = CscVisitRequestSelector.STATUS_REQUESTED;
            osvVisit.Status__c = CscVisitRequestSelector.STATUS_REQUESTED;
            update new List<CSC_Visit_Request__c>{ orcVisit, imsVisit, osvVisit };
            orcVisit.Status__c = CscVisitRequestSelector.STATUS_POSTPONED;
            update orcVisit;
            orcVisit.Status__c = CscVisitRequestSelector.STATUS_CANCELLED;
            update orcVisit;
            CscVisitEmailService.notifyAfterSave(
                new List<CSC_Visit_Request__c>{
                    new CSC_Visit_Request__c(
                        Id = orcVisit.Id,
                        Status__c = CscVisitRequestSelector.STATUS_REQUESTED,
                        VisitType__c = CscVisitRequestSelector.REQUEST_ORC,
                        RecordTypeId = orcVisit.RecordTypeId
                    ),
                    new CSC_Visit_Request__c(
                        Id = imsVisit.Id,
                        Status__c = CscVisitRequestSelector.STATUS_REQUESTED,
                        VisitType__c = CscVisitRequestSelector.REQUEST_IMS,
                        RecordTypeId = imsVisit.RecordTypeId
                    ),
                    new CSC_Visit_Request__c(
                        Id = osvVisit.Id,
                        Status__c = CscVisitRequestSelector.STATUS_REQUESTED,
                        VisitType__c = CscVisitRequestSelector.REQUEST_OSV,
                        RecordTypeId = osvVisit.RecordTypeId
                    )
                },
                new Map<Id, CSC_Visit_Request__c>{
                    orcVisit.Id => new CSC_Visit_Request__c(
                        Id = orcVisit.Id,
                        Status__c = CscVisitRequestSelector.STATUS_DRAFT,
                        VisitType__c = CscVisitRequestSelector.REQUEST_ORC
                    ),
                    imsVisit.Id => new CSC_Visit_Request__c(
                        Id = imsVisit.Id,
                        Status__c = CscVisitRequestSelector.STATUS_DRAFT,
                        VisitType__c = CscVisitRequestSelector.REQUEST_IMS
                    ),
                    osvVisit.Id => new CSC_Visit_Request__c(
                        Id = osvVisit.Id,
                        Status__c = CscVisitRequestSelector.STATUS_DRAFT,
                        VisitType__c = CscVisitRequestSelector.REQUEST_OSV
                    )
                }
            );

            cscVisit.Status__c = CscVisitRequestSelector.STATUS_CONFIRMED;
            cscVisit.Confirmed_Date__c = Date.today().addDays(8);
            CscVisitEmailService.notifyAfterSave(
                new List<CSC_Visit_Request__c>{ null, cscVisit },
                new Map<Id, CSC_Visit_Request__c>{
                    cscVisit.Id => new CSC_Visit_Request__c(
                        Id = cscVisit.Id,
                        Status__c = CscVisitRequestSelector.STATUS_APPROVED,
                        VisitType__c = CscVisitRequestSelector.REQUEST_CSC,
                        PlanningDesignRequired__c = 'No'
                    )
                }
            );

            CSC_Visit_Request__c loadedCscVisit = [
                SELECT Id, VisitType__c, RecordTypeId, PlanningDesignRequired__c,
                    AccountFacility__c, Opportunity__c, Opportunity__r.AccountId
                FROM CSC_Visit_Request__c
                WHERE Id = :cscVisit.Id
            ];
            CscVisitEmailService.lastStakeholderRecipientIds.clear();
            CscVisitEmailService.lastPdmRecipientIds.clear();
            CscVisitEmailService.additionalConfirmationRecipients(
                new List<CSC_Visit_Request__c>{ loadedCscVisit },
                null,
                null
            );

            System.assert(CscVisitEmailService.lastTeamRecipientIds.contains(oracleUser.Id));
            System.assert(CscVisitEmailService.lastStakeholderRecipientIds.contains(oracleUser.Id));
            System.assert(CscVisitEmailService.lastPdmRecipientIds.contains(pdmUser.Id));
        }
    }

    private static String teamAccess(String objectName, String privateAccess) {
        String sharingModel = sharingModel(objectName);
        if (sharingModel == 'ReadWrite' || sharingModel == 'FullAccess') {
            return 'Edit';
        }
        if (sharingModel == 'Read') {
            return 'Read';
        }
        return privateAccess;
    }

    private static String visitShareAccess() {
        return sharingModel('CSC_Visit_Request__c') == 'Read' ? 'Edit' : 'Read';
    }

    private static String sharingModel(String objectName) {
        return [
            SELECT InternalSharingModel
            FROM EntityDefinition
            WHERE QualifiedApiName = :objectName
            LIMIT 1
        ].InternalSharingModel;
    }

    private static User emailUser(String aliasValue, Id profileId, Id roleId) {
        String uniqueName = aliasValue + DateTime.now().getTime() + '@csc.example.test';
        return new User(
            Alias = aliasValue.left(8),
            Email = uniqueName,
            EmailEncodingKey = 'UTF-8',
            LastName = aliasValue,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profileId,
            UserRoleId = roleId,
            TimeZoneSidKey = 'America/New_York',
            Username = uniqueName
        );
    }

    private static CSC_Visit_Request__c emailVisit(String visitType, Id accountId, Id opportunityId) {
        return new CSC_Visit_Request__c(
            RecordTypeId = Schema.SObjectType.CSC_Visit_Request__c
                .getRecordTypeInfosByDeveloperName()
                .get('CSCVisitRequest')
                .getRecordTypeId(),
            VisitType__c = visitType,
            VisitLocation__c = LOCATION,
            AccountFacility__c = accountId,
            Opportunity__c = opportunityId,
            Status__c = CscVisitRequestSelector.STATUS_DRAFT
        );
    }

    private static String activeTeamRole() {
        for (Schema.PicklistEntry entry : AccountTeamMember.TeamMemberRole.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return 'Sales Rep';
    }
}