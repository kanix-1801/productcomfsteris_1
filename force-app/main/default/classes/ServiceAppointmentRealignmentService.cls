/**
 * @author Sagar Anand
 * @date 2026-10-29
 * @description GW-6099 - Service for the Service Appointment Realignment Analysis. Starts the batch and
 *              holds the realignment rules used by each batch chunk:
 *              1. Territory: the assigned resource must have an active Primary/Secondary Service Territory
 *                 Member for the appointment's exact territory. If not: Territory Misalignment,
 *                 Auto-reassign eligible (the preferred-resource check is skipped).
 *              2. Preferred resource: the Preferred AddressResourcePreference__c rows of the Work Order's
 *                 Ship-To Address account. If there are some and the assigned resource is none of them:
 *                 Preferred Resource Misalignment, Auto-reassign eligible when at least one preferred
 *                 resource has every required skill of the Work Order, otherwise Manual Review.
 *              Aligned appointments are left unchanged; an appointment is only updated when one of the
 *              three realignment fields changes.
 * @group Field Service
 * @see ServiceAppointmentRealignmentBatch
 * @see ServiceAppointmentRealignmentInvocable
 */
public with sharing class ServiceAppointmentRealignmentService {
    /**
     * @description Outcome of a start request from the screen flow.
     */
    public class StartResult {
        /** @description Id of the batch job that was started; null when a run is already in progress. */
        public Id jobId;
        /** @description True when a previous run is still queued or processing, so nothing was started. */
        public Boolean isAlreadyRunning = false;
    }

    /**
     * @description Result of evaluating one chunk of Service Appointments.
     */
    public class EvaluationResult {
        /** @description Appointments whose realignment fields change (only Id and the three fields set). */
        public List<ServiceAppointment> appointmentsToUpdate = new List<ServiceAppointment>();
        /** @description Appointments checked against the rules. */
        public Integer evaluatedCount = 0;
        /** @description Appointments skipped because they have no assigned resource or no territory. */
        public Integer skippedCount = 0;
        /** @description Appointments flagged as Territory Misalignment. */
        public Integer territoryMisalignmentCount = 0;
        /** @description Appointments flagged as Preferred Resource Misalignment. */
        public Integer preferredResourceMisalignmentCount = 0;
    }

    /**
     * @description Related records of one chunk, loaded once and compared in memory.
     */
    @TestVisible
    private class RealignmentData {
        /** @description Primary/Secondary territory memberships by Service Resource Id. */
        public Map<Id, List<ServiceTerritoryMember>> membersByResourceIdMap =
            new Map<Id, List<ServiceTerritoryMember>>();
        /** @description Preferred Service Resource Ids by Address Account Id. */
        public Map<Id, Set<Id>> preferredResourceIdsByAccountIdMap = new Map<Id, Set<Id>>();
        /** @description Skill requirements by Work Order Id. */
        public Map<Id, List<SkillRequirement>> requirementsByWorkOrderIdMap = new Map<Id, List<SkillRequirement>>();
        /** @description Skills by Service Resource Id (preferred resources only). */
        public Map<Id, List<ServiceResourceSkill>> skillsByResourceIdMap = new Map<Id, List<ServiceResourceSkill>>();
    }

    /**
     * @description GW-6099 - Starts the Realignment Analysis batch for the given Service Territories, unless
     *              a previous run is still queued or processing.
     * @param serviceTerritoryIdSet Service Territory Ids selected in the screen flow
     * @return Start result with the batch job Id, or isAlreadyRunning = true
     * @throws ServiceAppointmentRealignmentException when no territory is given or the batch cannot start
     * @example
     * ServiceAppointmentRealignmentService.StartResult result =
     *     ServiceAppointmentRealignmentService.startAnalysis(new Set<Id>{ territoryId });
     */
    public static StartResult startAnalysis(Set<Id> serviceTerritoryIdSet) {
        Set<Id> territoryIdSet = new Set<Id>();
        if (serviceTerritoryIdSet != null) {
            territoryIdSet.addAll(serviceTerritoryIdSet);
            territoryIdSet.remove(null);
        }
        if (territoryIdSet.isEmpty()) {
            throw new ServiceAppointmentRealignmentException('Select at least one Service Territory.');
        }

        Logger.setScenario(ServiceAppointmentRealignmentConstants.LOGGER_SCENARIO);
        try {
            StartResult result = new StartResult();
            List<AsyncApexJob> activeJobs = AsyncApexJobsSelector.selectActiveBatchJobsByClassName(
                ServiceAppointmentRealignmentConstants.BATCH_CLASS_NAME
            );
            if (!activeJobs.isEmpty()) {
                result.isAlreadyRunning = true;
                Logger.info(
                    new LogMessage('Realignment Analysis not started: job {0} is still running', activeJobs[0].Id)
                );
                return result;
            }

            result.jobId = Database.executeBatch(
                new ServiceAppointmentRealignmentBatch(territoryIdSet),
                ServiceAppointmentRealignmentBatch.BATCH_SIZE
            );
            Logger.info(
                new LogMessage(
                    'Realignment Analysis started: job {0} for {1} Service Territories',
                    result.jobId,
                    territoryIdSet.size()
                )
            );
            return result;
        } catch (Exception e) {
            Logger.error('ServiceAppointmentRealignmentService.startAnalysis failed', e);
            throw new ServiceAppointmentRealignmentException(
                'Failed to start the Realignment Analysis: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-6099 - Earliest SchedStartTime included in the analysis: the start of tomorrow in the
     *              running user's time zone.
     * @return Start of tomorrow
     */
    public static Datetime analysisStartDateTime() {
        return Datetime.newInstance(Date.today().addDays(1), Time.newInstance(0, 0, 0, 0));
    }

    /**
     * @description GW-6099 - Evaluates one chunk of Service Appointments: loads the related records once
     *              (territory members, preferred resources, skill requirements, resource skills) and applies
     *              the realignment rules in memory.
     * @param appointmentList Service Appointments queried by ServiceAppointmentsSelector
     * @return Evaluation result with the appointments to update and the counts
     * @example
     * ServiceAppointmentRealignmentService.EvaluationResult result =
     *     ServiceAppointmentRealignmentService.evaluateRealignment(appointments);
     */
    public static EvaluationResult evaluateRealignment(List<ServiceAppointment> appointmentList) {
        if (appointmentList == null || appointmentList.isEmpty()) {
            return new EvaluationResult();
        }
        return evaluate(appointmentList, loadRealignmentData(appointmentList));
    }

    /**
     * @description GW-6099 - Saves the changed appointments with partial success; each failure is logged
     *              against its record and does not stop the others.
     * @param appointmentList Appointments returned in EvaluationResult.appointmentsToUpdate
     * @return Number of appointments that failed to save
     * @example
     * Integer failedCount =
     *     ServiceAppointmentRealignmentService.updateChangedAppointments(result.appointmentsToUpdate);
     */
    public static Integer updateChangedAppointments(List<ServiceAppointment> appointmentList) {
        if (appointmentList == null || appointmentList.isEmpty()) {
            return 0;
        }

        Integer failedCount = 0;
        List<Database.SaveResult> saveResults = Database.update(appointmentList, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < saveResults.size(); i++) {
            if (saveResults[i].isSuccess()) {
                continue;
            }
            failedCount++;
            List<String> errorMessages = new List<String>();
            for (Database.Error error : saveResults[i].getErrors()) {
                errorMessages.add(error.getMessage());
            }
            Logger.error(
                    new LogMessage(
                        'Realignment update failed for Service Appointment {0}: {1}',
                        appointmentList[i].Id,
                        String.join(errorMessages, '; ')
                    )
                )
                .setRecord(appointmentList[i].Id)
                .addTag('Service Appointment');
        }
        return failedCount;
    }

    /**
     * @description Applies the realignment rules to already-loaded data. Pure in-memory logic.
     * @param appointmentList Service Appointments to evaluate
     * @param data Related records of the chunk
     * @return Evaluation result
     */
    @TestVisible
    private static EvaluationResult evaluate(List<ServiceAppointment> appointmentList, RealignmentData data) {
        EvaluationResult result = new EvaluationResult();
        for (ServiceAppointment appointment : appointmentList) {
            Id assignedResourceId = appointment.FSSK__FSK_Assigned_Service_Resource__c;
            if (assignedResourceId == null || appointment.ServiceTerritoryId == null) {
                result.skippedCount++;
                continue;
            }
            result.evaluatedCount++;

            String category;
            String action;
            if (!isWorkingTerritory(assignedResourceId, appointment, data)) {
                category = ServiceAppointmentRealignmentConstants.CATEGORY_TERRITORY_MISALIGNMENT;
                action = ServiceAppointmentRealignmentConstants.ACTION_AUTO_REASSIGN_ELIGIBLE;
                result.territoryMisalignmentCount++;
            } else {
                Id addressAccountId = appointment.FSSK__FSK_Work_Order__r?.ShipToAddressAccount__c;
                Set<Id> preferredResourceIdSet = data.preferredResourceIdsByAccountIdMap.get(addressAccountId);
                if (
                    addressAccountId == null ||
                    preferredResourceIdSet == null ||
                    preferredResourceIdSet.isEmpty() ||
                    preferredResourceIdSet.contains(assignedResourceId)
                ) {
                    continue;
                }
                category = ServiceAppointmentRealignmentConstants.CATEGORY_PREFERRED_RESOURCE_MISALIGNMENT;
                action = hasQualifiedPreferredResource(preferredResourceIdSet, appointment, data)
                    ? ServiceAppointmentRealignmentConstants.ACTION_AUTO_REASSIGN_ELIGIBLE
                    : ServiceAppointmentRealignmentConstants.ACTION_MANUAL_REVIEW;
                result.preferredResourceMisalignmentCount++;
            }

            Boolean isUnchanged =
                appointment.RealignmentConflict__c == true &&
                appointment.RealignmentConflictCategory__c == category &&
                appointment.RealignmentConflictAction__c == action;
            if (!isUnchanged) {
                result.appointmentsToUpdate.add(
                    new ServiceAppointment(
                        Id = appointment.Id,
                        RealignmentConflict__c = true,
                        RealignmentConflictCategory__c = category,
                        RealignmentConflictAction__c = action
                    )
                );
            }
        }
        return result;
    }

    /**
     * @description True when the resource has a Primary/Secondary member for the appointment's exact
     *              territory that is effective at the appointment start.
     */
    private static Boolean isWorkingTerritory(Id resourceId, ServiceAppointment appointment, RealignmentData data) {
        List<ServiceTerritoryMember> members = data.membersByResourceIdMap.get(resourceId);
        if (members == null) {
            return false;
        }
        for (ServiceTerritoryMember member : members) {
            if (
                member.ServiceTerritoryId == appointment.ServiceTerritoryId &&
                isEffective(member.EffectiveStartDate, member.EffectiveEndDate, appointment.SchedStartTime)
            ) {
                return true;
            }
        }
        return false;
    }

    /**
     * @description True when at least one preferred resource has every required skill of the Work Order.
     */
    private static Boolean hasQualifiedPreferredResource(
        Set<Id> preferredResourceIdSet,
        ServiceAppointment appointment,
        RealignmentData data
    ) {
        for (Id preferredResourceId : preferredResourceIdSet) {
            if (hasAllRequiredSkills(preferredResourceId, appointment, data)) {
                return true;
            }
        }
        return false;
    }

    /**
     * @description True when the resource has every required (non-additional) skill of the appointment's
     *              Work Order, at the required level or higher, effective at the appointment start.
     *              A Work Order without required skills is satisfied by any resource.
     */
    private static Boolean hasAllRequiredSkills(Id resourceId, ServiceAppointment appointment, RealignmentData data) {
        List<SkillRequirement> requirements = data.requirementsByWorkOrderIdMap.get(
            appointment.FSSK__FSK_Work_Order__c
        );
        if (requirements == null) {
            return true;
        }
        List<ServiceResourceSkill> resourceSkills = data.skillsByResourceIdMap.get(resourceId);
        for (SkillRequirement requirement : requirements) {
            if (requirement.IsAdditionalSkill == true) {
                continue;
            }
            if (!hasSkill(resourceSkills, requirement, appointment.SchedStartTime)) {
                return false;
            }
        }
        return true;
    }

    private static Boolean hasSkill(
        List<ServiceResourceSkill> resourceSkills,
        SkillRequirement requirement,
        Datetime appointmentStart
    ) {
        if (resourceSkills == null) {
            return false;
        }
        for (ServiceResourceSkill resourceSkill : resourceSkills) {
            Boolean meetsLevel =
                requirement.SkillLevel == null ||
                (resourceSkill.SkillLevel != null &&
                resourceSkill.SkillLevel >= requirement.SkillLevel);
            if (
                resourceSkill.SkillId == requirement.SkillId &&
                meetsLevel &&
                isEffective(resourceSkill.EffectiveStartDate, resourceSkill.EffectiveEndDate, appointmentStart)
            ) {
                return true;
            }
        }
        return false;
    }

    private static Boolean isEffective(Datetime startDateTime, Datetime endDateTime, Datetime atDateTime) {
        if (atDateTime == null) {
            return false;
        }
        return (startDateTime == null || startDateTime <= atDateTime) &&
            (endDateTime == null ||
            endDateTime >= atDateTime);
    }

    /**
     * @description Loads the related records of a chunk with one query per object.
     */
    private static RealignmentData loadRealignmentData(List<ServiceAppointment> appointmentList) {
        RealignmentData data = new RealignmentData();
        Set<Id> assignedResourceIdSet = new Set<Id>();
        Set<Id> addressAccountIdSet = new Set<Id>();
        Set<Id> workOrderIdSet = new Set<Id>();
        for (ServiceAppointment appointment : appointmentList) {
            assignedResourceIdSet.add(appointment.FSSK__FSK_Assigned_Service_Resource__c);
            addressAccountIdSet.add(appointment.FSSK__FSK_Work_Order__r?.ShipToAddressAccount__c);
            workOrderIdSet.add(appointment.FSSK__FSK_Work_Order__c);
        }

        for (
            ServiceTerritoryMember member : ServiceTerritoryMembersSelector.selectByServiceResourceIdsAndTypes(
                assignedResourceIdSet,
                ServiceAppointmentRealignmentConstants.WORKING_TERRITORY_TYPES
            )
        ) {
            if (!data.membersByResourceIdMap.containsKey(member.ServiceResourceId)) {
                data.membersByResourceIdMap.put(member.ServiceResourceId, new List<ServiceTerritoryMember>());
            }
            data.membersByResourceIdMap.get(member.ServiceResourceId).add(member);
        }

        Set<Id> preferredResourceIdSet = new Set<Id>();
        List<AddressResourcePreference__c> preferences =
            AddressResourcePreferencesSelector.selectByAddressAccountIdsAndLevel(
                addressAccountIdSet,
                ServiceAppointmentRealignmentConstants.PREFERENCE_LEVEL_PREFERRED
            );
        for (AddressResourcePreference__c preference : preferences) {
            if (preference.ServiceResource__c == null) {
                continue;
            }
            if (!data.preferredResourceIdsByAccountIdMap.containsKey(preference.AddressAccount__c)) {
                data.preferredResourceIdsByAccountIdMap.put(preference.AddressAccount__c, new Set<Id>());
            }
            data.preferredResourceIdsByAccountIdMap.get(preference.AddressAccount__c)
                .add(preference.ServiceResource__c);
            preferredResourceIdSet.add(preference.ServiceResource__c);
        }

        for (SkillRequirement requirement : SkillRequirementsSelector.selectByRelatedRecordIds(workOrderIdSet)) {
            if (!data.requirementsByWorkOrderIdMap.containsKey(requirement.RelatedRecordId)) {
                data.requirementsByWorkOrderIdMap.put(requirement.RelatedRecordId, new List<SkillRequirement>());
            }
            data.requirementsByWorkOrderIdMap.get(requirement.RelatedRecordId).add(requirement);
        }

        for (
            ServiceResourceSkill resourceSkill : ServiceResourceSkillsSelector.selectByServiceResourceIds(
                preferredResourceIdSet
            )
        ) {
            if (!data.skillsByResourceIdMap.containsKey(resourceSkill.ServiceResourceId)) {
                data.skillsByResourceIdMap.put(resourceSkill.ServiceResourceId, new List<ServiceResourceSkill>());
            }
            data.skillsByResourceIdMap.get(resourceSkill.ServiceResourceId).add(resourceSkill);
        }
        return data;
    }

    /**
     * @description Thrown when the Realignment Analysis cannot be started.
     */
    public class ServiceAppointmentRealignmentException extends Exception {
    }
}