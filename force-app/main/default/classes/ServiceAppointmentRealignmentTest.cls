/**
 * @author Sagar Anand
 * @date 2026-10-29
 * @description GW-6099 - Tests for the Realignment Analysis business logic: ServiceAppointmentRealignmentInvocable,
 *              ServiceAppointmentRealignmentService, ServiceAppointmentRealignmentBatch and
 *              ServiceAppointmentRealignmentConstants (one test class per feature, as in the org).
 *              The realignment rules are tested in memory with generated Ids: Skill records cannot be
 *              created in Apex and Field Service resources need licensed users, so no FSL data is inserted.
 * @group Field Service
 * @see ServiceAppointmentRealignmentInvocable
 * @see ServiceAppointmentRealignmentService
 * @see ServiceAppointmentRealignmentBatch
 */
@IsTest
private class ServiceAppointmentRealignmentTest {
    private static final Datetime APPOINTMENT_START = Datetime.newInstance(2030, 1, 15, 10, 0, 0);
    /** @description Grants the realignment fields; the service and selector enforce FLS (USER_MODE). */
    private static final String PERMISSION_SET_NAME = 'ManageServiceAppointments';
    private static Integer fakeIdCounter = 0;

    /**
     * @description Gives the running user the permission set for the realignment fields when it is missing
     *              (e.g. the deployment user in QA), so USER_MODE queries and updates can run.
     */
    @TestSetup
    static void setupTestData() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());
        List<PermissionSet> permissionSetList = [
            SELECT Id FROM PermissionSet WHERE Name = :PERMISSION_SET_NAME LIMIT 1
        ];
        if (permissionSetList.isEmpty()) {
            return;
        }
        Integer assignmentCount = [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :contextUser.Id AND PermissionSetId = :permissionSetList[0].Id
        ];
        if (assignmentCount == 0) {
            System.runAs(contextUser) {
                new adb_PermissionSetAssignment()
                    .assigneeId(contextUser.Id)
                    .permissionSetId(permissionSetList[0].Id)
                    .persist();
            }
        }
    }

    /**
     * @description Assigned resource without a membership for the territory: Territory Misalignment,
     *              Auto-reassign eligible, and the preferred-resource check is skipped.
     */
    @IsTest
    static void testEvaluateTerritoryMismatchFlagsTerritoryMisalignment() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId()); // in-memory logic, no record access needed

        System.runAs(contextUser) {
            // GIVEN: the resource only works in another territory; the address prefers someone else
            Id resourceId = fakeId(ServiceResource.SObjectType);
            Id territoryId = fakeId(ServiceTerritory.SObjectType);
            Id accountId = fakeId(Account.SObjectType);
            ServiceAppointmentRealignmentService.RealignmentData data =
                new ServiceAppointmentRealignmentService.RealignmentData();
            addMember(data, resourceId, fakeId(ServiceTerritory.SObjectType), null, null);
            addPreferred(data, accountId, fakeId(ServiceResource.SObjectType));
            ServiceAppointment appointment = buildAppointment(resourceId, territoryId, accountId);

            // WHEN
            Test.startTest();
            ServiceAppointmentRealignmentService.EvaluationResult result =
                ServiceAppointmentRealignmentService.evaluate(
                    new List<ServiceAppointment>{ appointment },
                    data
                );
            Test.stopTest();

            // THEN
            assertFlagged(
                result,
                ServiceAppointmentRealignmentConstants.CATEGORY_TERRITORY_MISALIGNMENT,
                ServiceAppointmentRealignmentConstants.ACTION_AUTO_REASSIGN_ELIGIBLE
            );
            Assert.areEqual(1, result.territoryMisalignmentCount, 'Territory misalignment should be counted');
            Assert.areEqual(0, result.preferredResourceMisalignmentCount, 'Preferred check must be skipped');
        }
    }

    /**
     * @description A membership that ended before the appointment does not count as a working territory.
     */
    @IsTest
    static void testEvaluateExpiredMembershipFlagsTerritoryMisalignment() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: a membership for the right territory that ended a day before the appointment
            Id resourceId = fakeId(ServiceResource.SObjectType);
            Id territoryId = fakeId(ServiceTerritory.SObjectType);
            ServiceAppointmentRealignmentService.RealignmentData data =
                new ServiceAppointmentRealignmentService.RealignmentData();
            addMember(data, resourceId, territoryId, APPOINTMENT_START.addDays(-30), APPOINTMENT_START.addDays(-1));

            // WHEN
            Test.startTest();
            ServiceAppointmentRealignmentService.EvaluationResult result =
                ServiceAppointmentRealignmentService.evaluate(
                    new List<ServiceAppointment>{ buildAppointment(resourceId, territoryId, null) },
                    data
                );
            Test.stopTest();

            // THEN
            assertFlagged(
                result,
                ServiceAppointmentRealignmentConstants.CATEGORY_TERRITORY_MISALIGNMENT,
                ServiceAppointmentRealignmentConstants.ACTION_AUTO_REASSIGN_ELIGIBLE
            );
        }
    }

    /**
     * @description Active membership and no preferred resource for the address: aligned, nothing updated.
     */
    @IsTest
    static void testEvaluateWorkingTerritoryWithoutPreferenceIsAligned() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: an open-ended membership for the appointment's territory, no Address preferences
            Id resourceId = fakeId(ServiceResource.SObjectType);
            Id territoryId = fakeId(ServiceTerritory.SObjectType);
            ServiceAppointmentRealignmentService.RealignmentData data =
                new ServiceAppointmentRealignmentService.RealignmentData();
            addMember(data, resourceId, territoryId, APPOINTMENT_START.addDays(-30), null);

            // WHEN
            Test.startTest();
            ServiceAppointmentRealignmentService.EvaluationResult result =
                ServiceAppointmentRealignmentService.evaluate(
                    new List<ServiceAppointment>{
                        buildAppointment(resourceId, territoryId, fakeId(Account.SObjectType))
                    },
                    data
                );
            Test.stopTest();

            // THEN
            Assert.areEqual(1, result.evaluatedCount, 'Appointment should be evaluated');
            Assert.isTrue(result.appointmentsToUpdate.isEmpty(), 'Aligned appointment must not be updated');
        }
    }

    /**
     * @description Several preferred resources: aligned when the assigned resource is any of them.
     */
    @IsTest
    static void testEvaluateAssignedResourceIsOneOfPreferredIsAligned() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: the address prefers two resources, one of them is the assigned resource
            Id resourceId = fakeId(ServiceResource.SObjectType);
            Id territoryId = fakeId(ServiceTerritory.SObjectType);
            Id accountId = fakeId(Account.SObjectType);
            ServiceAppointmentRealignmentService.RealignmentData data =
                new ServiceAppointmentRealignmentService.RealignmentData();
            addMember(data, resourceId, territoryId, null, null);
            addPreferred(data, accountId, fakeId(ServiceResource.SObjectType));
            addPreferred(data, accountId, resourceId);

            // WHEN
            Test.startTest();
            ServiceAppointmentRealignmentService.EvaluationResult result =
                ServiceAppointmentRealignmentService.evaluate(
                    new List<ServiceAppointment>{ buildAppointment(resourceId, territoryId, accountId) },
                    data
                );
            Test.stopTest();

            // THEN
            Assert.isTrue(result.appointmentsToUpdate.isEmpty(), 'Assigned preferred resource is aligned');
            Assert.areEqual(0, result.preferredResourceMisalignmentCount, 'No misalignment expected');
        }
    }

    /**
     * @description Preferred mismatch where one of several preferred resources has every required skill:
     *              Auto-reassign eligible. Additional (optional) skills are not required.
     */
    @IsTest
    static void testEvaluatePreferredMismatchWithQualifiedResourceIsAutoReassign() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: two preferred resources; only the second has the required skill at level 3 (needs 2)
            Id resourceId = fakeId(ServiceResource.SObjectType);
            Id territoryId = fakeId(ServiceTerritory.SObjectType);
            Id accountId = fakeId(Account.SObjectType);
            Id unqualifiedId = fakeId(ServiceResource.SObjectType);
            Id qualifiedId = fakeId(ServiceResource.SObjectType);
            Id requiredSkillId = fakeId(Skill.SObjectType);
            ServiceAppointmentRealignmentService.RealignmentData data =
                new ServiceAppointmentRealignmentService.RealignmentData();
            addMember(data, resourceId, territoryId, null, null);
            addPreferred(data, accountId, unqualifiedId);
            addPreferred(data, accountId, qualifiedId);
            ServiceAppointment appointment = buildAppointment(resourceId, territoryId, accountId);
            addRequirement(data, appointment.FSSK__FSK_Work_Order__c, requiredSkillId, 2, false);
            addRequirement(data, appointment.FSSK__FSK_Work_Order__c, fakeId(Skill.SObjectType), null, true);
            addSkill(data, qualifiedId, requiredSkillId, 3, APPOINTMENT_START.addDays(-10), null);

            // WHEN
            Test.startTest();
            ServiceAppointmentRealignmentService.EvaluationResult result =
                ServiceAppointmentRealignmentService.evaluate(
                    new List<ServiceAppointment>{ appointment },
                    data
                );
            Test.stopTest();

            // THEN
            assertFlagged(
                result,
                ServiceAppointmentRealignmentConstants.CATEGORY_PREFERRED_RESOURCE_MISALIGNMENT,
                ServiceAppointmentRealignmentConstants.ACTION_AUTO_REASSIGN_ELIGIBLE
            );
            Assert.areEqual(1, result.preferredResourceMisalignmentCount, 'Preferred misalignment expected');
        }
    }

    /**
     * @description Preferred mismatch where no preferred resource qualifies (level too low, skill expired):
     *              Manual Review.
     */
    @IsTest
    static void testEvaluatePreferredMismatchWithoutQualifiedResourceIsManualReview() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: one preferred resource with level 1 (needs 2), another whose skill ended before the visit
            Id resourceId = fakeId(ServiceResource.SObjectType);
            Id territoryId = fakeId(ServiceTerritory.SObjectType);
            Id accountId = fakeId(Account.SObjectType);
            Id lowLevelId = fakeId(ServiceResource.SObjectType);
            Id expiredId = fakeId(ServiceResource.SObjectType);
            Id requiredSkillId = fakeId(Skill.SObjectType);
            ServiceAppointmentRealignmentService.RealignmentData data =
                new ServiceAppointmentRealignmentService.RealignmentData();
            addMember(data, resourceId, territoryId, null, null);
            addPreferred(data, accountId, lowLevelId);
            addPreferred(data, accountId, expiredId);
            ServiceAppointment appointment = buildAppointment(resourceId, territoryId, accountId);
            addRequirement(data, appointment.FSSK__FSK_Work_Order__c, requiredSkillId, 2, false);
            addSkill(data, lowLevelId, requiredSkillId, 1, null, null);
            addSkill(data, expiredId, requiredSkillId, 5, null, APPOINTMENT_START.addDays(-1));

            // WHEN
            Test.startTest();
            ServiceAppointmentRealignmentService.EvaluationResult result =
                ServiceAppointmentRealignmentService.evaluate(
                    new List<ServiceAppointment>{ appointment },
                    data
                );
            Test.stopTest();

            // THEN
            assertFlagged(
                result,
                ServiceAppointmentRealignmentConstants.CATEGORY_PREFERRED_RESOURCE_MISALIGNMENT,
                ServiceAppointmentRealignmentConstants.ACTION_MANUAL_REVIEW
            );
        }
    }

    /**
     * @description Preferred mismatch on a Work Order without skill requirements: Auto-reassign eligible.
     */
    @IsTest
    static void testEvaluatePreferredMismatchWithoutRequirementsIsAutoReassign() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: a preferred resource without skills and a Work Order without requirements
            Id resourceId = fakeId(ServiceResource.SObjectType);
            Id territoryId = fakeId(ServiceTerritory.SObjectType);
            Id accountId = fakeId(Account.SObjectType);
            ServiceAppointmentRealignmentService.RealignmentData data =
                new ServiceAppointmentRealignmentService.RealignmentData();
            addMember(data, resourceId, territoryId, null, null);
            addPreferred(data, accountId, fakeId(ServiceResource.SObjectType));

            // WHEN
            Test.startTest();
            ServiceAppointmentRealignmentService.EvaluationResult result =
                ServiceAppointmentRealignmentService.evaluate(
                    new List<ServiceAppointment>{ buildAppointment(resourceId, territoryId, accountId) },
                    data
                );
            Test.stopTest();

            // THEN
            assertFlagged(
                result,
                ServiceAppointmentRealignmentConstants.CATEGORY_PREFERRED_RESOURCE_MISALIGNMENT,
                ServiceAppointmentRealignmentConstants.ACTION_AUTO_REASSIGN_ELIGIBLE
            );
        }
    }

    /**
     * @description An appointment that already has the same three values is not updated again.
     */
    @IsTest
    static void testEvaluateUnchangedFlagsAreNotUpdated() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: an appointment already flagged as Territory Misalignment / Auto-reassign eligible
            Id resourceId = fakeId(ServiceResource.SObjectType);
            ServiceAppointment appointment = buildAppointment(resourceId, fakeId(ServiceTerritory.SObjectType), null);
            appointment.RealignmentConflict__c = true;
            appointment.RealignmentConflictCategory__c =
                ServiceAppointmentRealignmentConstants.CATEGORY_TERRITORY_MISALIGNMENT;
            appointment.RealignmentConflictAction__c =
                ServiceAppointmentRealignmentConstants.ACTION_AUTO_REASSIGN_ELIGIBLE;

            // WHEN
            Test.startTest();
            ServiceAppointmentRealignmentService.EvaluationResult result =
                ServiceAppointmentRealignmentService.evaluate(
                    new List<ServiceAppointment>{ appointment },
                    new ServiceAppointmentRealignmentService.RealignmentData()
                );
            Test.stopTest();

            // THEN
            Assert.areEqual(1, result.territoryMisalignmentCount, 'Misalignment is still counted');
            Assert.isTrue(result.appointmentsToUpdate.isEmpty(), 'Unchanged values must not be saved again');
        }
    }

    /**
     * @description Appointments without an assigned resource or a territory are skipped.
     */
    @IsTest
    static void testEvaluateSkipsAppointmentsWithoutResourceOrTerritory() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN
            List<ServiceAppointment> appointments = new List<ServiceAppointment>{
                buildAppointment(null, fakeId(ServiceTerritory.SObjectType), null),
                buildAppointment(fakeId(ServiceResource.SObjectType), null, null)
            };

            // WHEN
            Test.startTest();
            ServiceAppointmentRealignmentService.EvaluationResult result =
                ServiceAppointmentRealignmentService.evaluate(
                    appointments,
                    new ServiceAppointmentRealignmentService.RealignmentData()
                );
            Test.stopTest();

            // THEN
            Assert.areEqual(2, result.skippedCount, 'Both appointments should be skipped');
            Assert.areEqual(0, result.evaluatedCount, 'Nothing should be evaluated');
            Assert.isTrue(result.appointmentsToUpdate.isEmpty(), 'Skipped appointments are not updated');
        }
    }

    /**
     * @description Bulk: 200 appointments are evaluated in one call.
     */
    @IsTest
    static void testEvaluateBulkAppointments() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: 100 aligned and 100 misaligned appointments
            Id territoryId = fakeId(ServiceTerritory.SObjectType);
            Id alignedResourceId = fakeId(ServiceResource.SObjectType);
            Id misalignedResourceId = fakeId(ServiceResource.SObjectType);
            ServiceAppointmentRealignmentService.RealignmentData data =
                new ServiceAppointmentRealignmentService.RealignmentData();
            addMember(data, alignedResourceId, territoryId, null, null);
            List<ServiceAppointment> appointments = new List<ServiceAppointment>();
            for (Integer i = 0; i < 100; i++) {
                appointments.add(buildAppointment(alignedResourceId, territoryId, null));
                appointments.add(buildAppointment(misalignedResourceId, territoryId, null));
            }

            // WHEN
            Test.startTest();
            ServiceAppointmentRealignmentService.EvaluationResult result =
                ServiceAppointmentRealignmentService.evaluate(
                    appointments,
                    data
                );
            Test.stopTest();

            // THEN
            Assert.areEqual(200, result.evaluatedCount, 'All appointments should be evaluated');
            Assert.areEqual(100, result.territoryMisalignmentCount, 'Half should be misaligned');
            Assert.areEqual(100, result.appointmentsToUpdate.size(), 'Only misaligned appointments are updated');
        }
    }

    /**
     * @description evaluateRealignment loads the related records through the selectors; with no related
     *              records every appointment is a territory misalignment. Empty input returns an empty result.
     */
    @IsTest
    static void testEvaluateRealignmentLoadsRelatedRecords() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: appointments whose resources, accounts and Work Orders have no related records
            List<ServiceAppointment> appointments = new List<ServiceAppointment>{
                buildAppointment(
                    fakeId(ServiceResource.SObjectType),
                    fakeId(ServiceTerritory.SObjectType),
                    fakeId(Account.SObjectType)
                ),
                buildAppointment(fakeId(ServiceResource.SObjectType), fakeId(ServiceTerritory.SObjectType), null)
            };

            // WHEN
            Test.startTest();
            ServiceAppointmentRealignmentService.EvaluationResult result =
                ServiceAppointmentRealignmentService.evaluateRealignment(
                    appointments
                );
            ServiceAppointmentRealignmentService.EvaluationResult emptyResult =
                ServiceAppointmentRealignmentService.evaluateRealignment(
                    new List<ServiceAppointment>()
                );
            Test.stopTest();

            // THEN
            Assert.areEqual(2, result.territoryMisalignmentCount, 'No memberships means territory misalignment');
            Assert.areEqual(2, result.appointmentsToUpdate.size(), 'Both appointments should be updated');
            Assert.areEqual(0, emptyResult.evaluatedCount, 'Empty input should evaluate nothing');
        }
    }

    /**
     * @description Failed saves are counted (and logged) without stopping the others; empty input saves nothing.
     */
    @IsTest
    static void testUpdateChangedAppointmentsCountsFailures() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: appointments whose Ids do not exist in the org
            List<ServiceAppointment> appointments = new List<ServiceAppointment>{
                new ServiceAppointment(Id = fakeId(ServiceAppointment.SObjectType), RealignmentConflict__c = true),
                new ServiceAppointment(Id = fakeId(ServiceAppointment.SObjectType), RealignmentConflict__c = true)
            };

            // WHEN
            Test.startTest();
            Integer failedCount = ServiceAppointmentRealignmentService.updateChangedAppointments(appointments);
            Integer emptyCount = ServiceAppointmentRealignmentService.updateChangedAppointments(null);
            Test.stopTest();

            // THEN
            Assert.areEqual(2, failedCount, 'Both saves should fail and be counted');
            Assert.areEqual(0, emptyCount, 'Nothing to save returns 0');
        }
    }

    /**
     * @description startAnalysis starts the batch, and reports a run that is still in progress instead of
     *              starting a second one.
     */
    @IsTest
    static void testStartAnalysisStartsBatchOnce() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: a selected territory (no appointments, so the batch has nothing to process)
            Set<Id> territoryIdSet = new Set<Id>{ fakeId(ServiceTerritory.SObjectType), null };

            // WHEN: the analysis is started twice before the first run finishes
            Test.startTest();
            ServiceAppointmentRealignmentService.StartResult first = ServiceAppointmentRealignmentService.startAnalysis(
                territoryIdSet
            );
            ServiceAppointmentRealignmentService.StartResult second =
                ServiceAppointmentRealignmentService.startAnalysis(
                    territoryIdSet
                );
            Test.stopTest();

            // THEN
            Assert.isNotNull(first.jobId, 'First call should start the batch');
            Assert.isFalse(first.isAlreadyRunning, 'First call should not report a running job');
            Assert.isTrue(second.isAlreadyRunning, 'Second call should see the queued run');
            Assert.isNull(second.jobId, 'Second call must not start another batch');
        }
    }

    /**
     * @description startAnalysis without territories throws a clear exception.
     */
    @IsTest
    static void testStartAnalysisWithoutTerritoriesThrows() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN
            String message;

            // WHEN
            Test.startTest();
            try {
                ServiceAppointmentRealignmentService.startAnalysis(new Set<Id>{ null });
            } catch (ServiceAppointmentRealignmentService.ServiceAppointmentRealignmentException e) {
                message = e.getMessage();
            }
            Test.stopTest();

            // THEN
            Assert.areEqual('Select at least one Service Territory.', message, 'Expected a validation message');
        }
    }

    /**
     * @description analysisStartDateTime is the start of tomorrow.
     */
    @IsTest
    static void testAnalysisStartDateTimeIsStartOfTomorrow() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN / WHEN
            Test.startTest();
            Datetime startDateTime = ServiceAppointmentRealignmentService.analysisStartDateTime();
            Test.stopTest();

            // THEN
            Assert.areEqual(Date.today().addDays(1), startDateTime.date(), 'Should be tomorrow');
            Assert.areEqual(Time.newInstance(0, 0, 0, 0), startDateTime.time(), 'Should be midnight');
        }
    }

    // ---- Batch ---------------------------------------------------------------------------------

    /**
     * @description execute evaluates the chunk, tries to save the changes and accumulates the totals;
     *              finish logs them.
     */
    @IsTest
    static void testExecuteAccumulatesTotals() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId()); // no FSL licence needed for generated Ids

        System.runAs(contextUser) {
            // GIVEN: three appointments without territory memberships (so all misaligned) whose Ids do
            //        not exist, plus one without an assigned resource
            ServiceAppointmentRealignmentBatch batch = new ServiceAppointmentRealignmentBatch(
                new Set<Id>{ fakeId(ServiceTerritory.SObjectType) }
            );
            List<ServiceAppointment> scope = new List<ServiceAppointment>();
            for (Integer i = 0; i < 3; i++) {
                scope.add(
                    new ServiceAppointment(
                        Id = fakeId(ServiceAppointment.SObjectType),
                        SchedStartTime = Datetime.now().addDays(2),
                        ServiceTerritoryId = fakeId(ServiceTerritory.SObjectType),
                        FSSK__FSK_Assigned_Service_Resource__c = fakeId(ServiceResource.SObjectType)
                    )
                );
            }
            scope.add(new ServiceAppointment(Id = fakeId(ServiceAppointment.SObjectType)));

            // WHEN
            Test.startTest();
            batch.execute(null, scope);
            batch.finish(null);
            Test.stopTest();

            // THEN
            Assert.areEqual(3, batch.totalEvaluatedCount, 'Three appointments should be evaluated');
            Assert.areEqual(1, batch.totalSkippedCount, 'Appointment without resource should be skipped');
            Assert.areEqual(3, batch.totalTerritoryMisalignmentCount, 'All evaluated appointments are misaligned');
            Assert.areEqual(3, batch.totalFailedCount, 'Saves fail because the Ids do not exist');
            Assert.areEqual(0, batch.totalUpdatedCount, 'Nothing should be saved');
        }
    }

    /**
     * @description The batch runs end to end; with no matching appointments it completes without errors.
     */
    @IsTest
    static void testBatchRunsEndToEnd() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: a territory without appointments, and a batch without territories
            Set<Id> territoryIdSet = new Set<Id>{ fakeId(ServiceTerritory.SObjectType) };

            // WHEN
            Test.startTest();
            Id jobId = Database.executeBatch(
                new ServiceAppointmentRealignmentBatch(territoryIdSet),
                ServiceAppointmentRealignmentBatch.BATCH_SIZE
            );
            Database.QueryLocator noTerritoryLocator = new ServiceAppointmentRealignmentBatch(null).start(null);
            Test.stopTest();

            // THEN
            AsyncApexJob job = [SELECT Status, NumberOfErrors FROM AsyncApexJob WHERE Id = :jobId];
            Assert.areEqual('Completed', job.Status, 'Batch should complete');
            Assert.areEqual(0, job.NumberOfErrors, 'Batch should have no errors');
            Assert.isFalse(noTerritoryLocator.iterator().hasNext(), 'No territories should match nothing');
        }
    }

    /**
     * @description Failures in start are logged and rethrown; failures in execute and finish are logged.
     */
    @IsTest
    static void testForcedFailuresAreHandled() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: the test hook forcing every method into its catch block
            ServiceAppointmentRealignmentBatch batch = new ServiceAppointmentRealignmentBatch(
                new Set<Id>{ fakeId(ServiceTerritory.SObjectType) }
            );
            ServiceAppointmentRealignmentBatch.forceExceptionForTest = true;
            Boolean startThrew = false;

            // WHEN
            Test.startTest();
            try {
                batch.start(null);
            } catch (ServiceAppointmentRealignmentService.ServiceAppointmentRealignmentException e) {
                startThrew = true;
            }
            batch.execute(null, new List<ServiceAppointment>());
            batch.finish(null);
            Test.stopTest();

            // THEN
            Assert.isTrue(startThrew, 'start should rethrow');
            Assert.areEqual(0, batch.totalEvaluatedCount, 'execute should stop before evaluating');
        }
    }

    // ---- Invocable -----------------------------------------------------------------------------

    /**
     * @description The territories of all requests start one batch; every request gets the same job Id.
     */
    @IsTest
    static void testStartRealignmentAnalysisReturnsJobId() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: two requests with selected territories (generated Ids, no appointments)
            String keyPrefix = ServiceTerritory.SObjectType.getDescribe().getKeyPrefix();
            ServiceAppointmentRealignmentInvocable.Request first = new ServiceAppointmentRealignmentInvocable.Request();
            first.serviceTerritories = new List<ServiceTerritory>{
                new ServiceTerritory(Id = keyPrefix + '000000000001'),
                null
            };
            ServiceAppointmentRealignmentInvocable.Request second =
                new ServiceAppointmentRealignmentInvocable.Request();
            second.serviceTerritories = new List<ServiceTerritory>{
                new ServiceTerritory(Id = keyPrefix + '000000000002')
            };

            // WHEN
            Test.startTest();
            List<ServiceAppointmentRealignmentInvocable.Result> results =
                ServiceAppointmentRealignmentInvocable.startRealignmentAnalysis(
                    new List<ServiceAppointmentRealignmentInvocable.Request>{ first, second, null }
                );
            Test.stopTest();

            // THEN
            Assert.areEqual(3, results.size(), 'One result per request');
            Assert.isNotNull(results[0].jobId, 'A batch job should be started');
            Assert.areEqual(results[0].jobId, results[1].jobId, 'All requests share one run');
            Assert.isFalse(results[0].isAlreadyRunning, 'No run was in progress');
        }
    }

    /**
     * @description No requests returns no results; requests without territories throw.
     */
    @IsTest
    static void testStartRealignmentAnalysisWithoutTerritories() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN
            ServiceAppointmentRealignmentInvocable.Request emptyRequest =
                new ServiceAppointmentRealignmentInvocable.Request();
            emptyRequest.serviceTerritories = new List<ServiceTerritory>();
            Boolean threw = false;

            // WHEN
            Test.startTest();
            List<ServiceAppointmentRealignmentInvocable.Result> noResults =
                ServiceAppointmentRealignmentInvocable.startRealignmentAnalysis(
                    null
                );
            try {
                ServiceAppointmentRealignmentInvocable.startRealignmentAnalysis(
                    new List<ServiceAppointmentRealignmentInvocable.Request>{ emptyRequest }
                );
            } catch (ServiceAppointmentRealignmentService.ServiceAppointmentRealignmentException e) {
                threw = true;
            }
            Test.stopTest();

            // THEN
            Assert.isTrue(noResults.isEmpty(), 'No requests should return no results');
            Assert.isTrue(threw, 'Requests without territories should throw');
        }
    }

    private static Id fakeId(Schema.SObjectType sObjectType) {
        fakeIdCounter++;
        String suffix = String.valueOf(fakeIdCounter);
        return Id.valueOf(sObjectType.getDescribe().getKeyPrefix() + '0'.repeat(12 - suffix.length()) + suffix);
    }

    /**
     * @description Builds an in-memory record from field values (JSON avoids read-only field errors).
     */
    private static SObject buildRecord(String objectApiName, Map<String, Object> fieldValues) {
        Map<String, Object> values = new Map<String, Object>(fieldValues);
        values.put('attributes', new Map<String, Object>{ 'type' => objectApiName });
        return (SObject) JSON.deserialize(JSON.serialize(values), Type.forName('Schema.' + objectApiName));
    }

    private static ServiceAppointment buildAppointment(Id resourceId, Id territoryId, Id addressAccountId) {
        Id workOrderId = fakeId(WorkOrder.SObjectType);
        return (ServiceAppointment) buildRecord(
            'ServiceAppointment',
            new Map<String, Object>{
                'Id' => fakeId(ServiceAppointment.SObjectType),
                'SchedStartTime' => APPOINTMENT_START,
                'ServiceTerritoryId' => territoryId,
                'FSSK__FSK_Assigned_Service_Resource__c' => resourceId,
                'FSSK__FSK_Work_Order__c' => workOrderId,
                'FSSK__FSK_Work_Order__r' => new Map<String, Object>{
                    'attributes' => new Map<String, Object>{ 'type' => 'WorkOrder' },
                    'Id' => workOrderId,
                    'ShipToAddressAccount__c' => addressAccountId
                },
                'RealignmentConflict__c' => false
            }
        );
    }

    private static void addMember(
        ServiceAppointmentRealignmentService.RealignmentData data,
        Id resourceId,
        Id territoryId,
        Datetime startDateTime,
        Datetime endDateTime
    ) {
        if (!data.membersByResourceIdMap.containsKey(resourceId)) {
            data.membersByResourceIdMap.put(resourceId, new List<ServiceTerritoryMember>());
        }
        data.membersByResourceIdMap.get(resourceId)
            .add(
                (ServiceTerritoryMember) buildRecord(
                    'ServiceTerritoryMember',
                    new Map<String, Object>{
                        'ServiceResourceId' => resourceId,
                        'ServiceTerritoryId' => territoryId,
                        'TerritoryType' => 'S',
                        'EffectiveStartDate' => startDateTime,
                        'EffectiveEndDate' => endDateTime
                    }
                )
            );
    }

    private static void addPreferred(
        ServiceAppointmentRealignmentService.RealignmentData data,
        Id accountId,
        Id resourceId
    ) {
        if (!data.preferredResourceIdsByAccountIdMap.containsKey(accountId)) {
            data.preferredResourceIdsByAccountIdMap.put(accountId, new Set<Id>());
        }
        data.preferredResourceIdsByAccountIdMap.get(accountId).add(resourceId);
    }

    private static void addRequirement(
        ServiceAppointmentRealignmentService.RealignmentData data,
        Id workOrderId,
        Id skillId,
        Decimal skillLevel,
        Boolean isAdditionalSkill
    ) {
        if (!data.requirementsByWorkOrderIdMap.containsKey(workOrderId)) {
            data.requirementsByWorkOrderIdMap.put(workOrderId, new List<SkillRequirement>());
        }
        data.requirementsByWorkOrderIdMap.get(workOrderId)
            .add(
                (SkillRequirement) buildRecord(
                    'SkillRequirement',
                    new Map<String, Object>{
                        'RelatedRecordId' => workOrderId,
                        'SkillId' => skillId,
                        'SkillLevel' => skillLevel,
                        'IsAdditionalSkill' => isAdditionalSkill
                    }
                )
            );
    }

    private static void addSkill(
        ServiceAppointmentRealignmentService.RealignmentData data,
        Id resourceId,
        Id skillId,
        Decimal skillLevel,
        Datetime startDateTime,
        Datetime endDateTime
    ) {
        if (!data.skillsByResourceIdMap.containsKey(resourceId)) {
            data.skillsByResourceIdMap.put(resourceId, new List<ServiceResourceSkill>());
        }
        data.skillsByResourceIdMap.get(resourceId)
            .add(
                (ServiceResourceSkill) buildRecord(
                    'ServiceResourceSkill',
                    new Map<String, Object>{
                        'ServiceResourceId' => resourceId,
                        'SkillId' => skillId,
                        'SkillLevel' => skillLevel,
                        'EffectiveStartDate' => startDateTime,
                        'EffectiveEndDate' => endDateTime
                    }
                )
            );
    }

    private static void assertFlagged(
        ServiceAppointmentRealignmentService.EvaluationResult result,
        String expectedCategory,
        String expectedAction
    ) {
        Assert.areEqual(1, result.appointmentsToUpdate.size(), 'One appointment should be updated');
        ServiceAppointment updated = result.appointmentsToUpdate[0];
        Assert.isTrue(updated.RealignmentConflict__c, 'Realignment Conflict should be set');
        Assert.areEqual(expectedCategory, updated.RealignmentConflictCategory__c, 'Unexpected category');
        Assert.areEqual(expectedAction, updated.RealignmentConflictAction__c, 'Unexpected action');
    }
}