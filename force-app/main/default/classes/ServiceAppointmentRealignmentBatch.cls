/**
 * @author Sagar Anand
 * @date 2026-10-29
 * @description GW-6099 - Realignment Analysis batch. Started on demand from the screen flow
 *              ServiceAppointment_SCR_RealignmentAnalysis (through ServiceAppointmentRealignmentInvocable).
 *              Processes the Service Appointments of the selected Service Territories that start tomorrow
 *              or later and have an eligible status; the rules live in ServiceAppointmentRealignmentService.
 * @group Field Service
 * @see ServiceAppointmentRealignmentService
 * @see ServiceAppointmentRealignmentInvocable
 */
public with sharing class ServiceAppointmentRealignmentBatch implements Database.Batchable<SObject>, Database.Stateful {
    /** @description Chunk size; keeps each transaction well inside governor limits. */
    public static final Integer BATCH_SIZE = 50;

    /** @description When true in tests, forces start/execute/finish into their catch paths. */
    @TestVisible
    private static Boolean forceExceptionForTest = false;

    /** @description Service Territories selected in the screen flow. */
    private final Set<Id> serviceTerritoryIdSet;

    /** @description Nebula Logger transaction Id from start, used to link execute/finish logs. */
    private String originalTransactionId;

    /** @description Appointments checked against the rules across all chunks. */
    @TestVisible
    private Integer totalEvaluatedCount = 0;
    /** @description Appointments skipped (no assigned resource or no territory). */
    @TestVisible
    private Integer totalSkippedCount = 0;
    /** @description Appointments flagged as Territory Misalignment. */
    @TestVisible
    private Integer totalTerritoryMisalignmentCount = 0;
    /** @description Appointments flagged as Preferred Resource Misalignment. */
    @TestVisible
    private Integer totalPreferredResourceMisalignmentCount = 0;
    /** @description Appointments saved because a realignment field changed. */
    @TestVisible
    private Integer totalUpdatedCount = 0;
    /** @description Appointments that failed to save. */
    @TestVisible
    private Integer totalFailedCount = 0;

    /**
     * @description Creates the batch for the selected Service Territories.
     * @param serviceTerritoryIdSet Service Territory Ids (exact territories, no children)
     */
    public ServiceAppointmentRealignmentBatch(Set<Id> serviceTerritoryIdSet) {
        this.serviceTerritoryIdSet = serviceTerritoryIdSet == null ? new Set<Id>() : serviceTerritoryIdSet;
    }

    /**
     * @description Returns the eligible Service Appointments of the selected territories.
     * @param bc Batchable context
     * @return Query locator of Service Appointments
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        this.originalTransactionId = Logger.getTransactionId();
        Logger.setScenario(ServiceAppointmentRealignmentConstants.LOGGER_SCENARIO);
        try {
            if (forceExceptionForTest == true) {
                throw new ServiceAppointmentRealignmentService.ServiceAppointmentRealignmentException(
                    'Forced batch start failure for test'
                );
            }
            Logger.info(
                new LogMessage(
                    'ServiceAppointmentRealignmentBatch.start: {0} Service Territories',
                    this.serviceTerritoryIdSet.size()
                )
            );
            return ServiceAppointmentsSelector.selectForRealignmentQueryLocator(
                this.serviceTerritoryIdSet,
                ServiceAppointmentRealignmentService.analysisStartDateTime(),
                ServiceAppointmentRealignmentConstants.ELIGIBLE_STATUSES
            );
        } catch (Exception e) {
            Logger.error('ServiceAppointmentRealignmentBatch.start', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Evaluates one chunk and saves the appointments whose realignment fields change.
     * @param bc Batchable context
     * @param scope Service Appointments in the current chunk
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        linkLogsToStartTransaction();
        try {
            if (forceExceptionForTest == true) {
                throw new ServiceAppointmentRealignmentService.ServiceAppointmentRealignmentException(
                    'Forced batch execute failure for test'
                );
            }
            ServiceAppointmentRealignmentService.EvaluationResult result =
                ServiceAppointmentRealignmentService.evaluateRealignment(
                    (List<ServiceAppointment>) scope
                );
            Integer failedCount = ServiceAppointmentRealignmentService.updateChangedAppointments(
                result.appointmentsToUpdate
            );

            this.totalEvaluatedCount += result.evaluatedCount;
            this.totalSkippedCount += result.skippedCount;
            this.totalTerritoryMisalignmentCount += result.territoryMisalignmentCount;
            this.totalPreferredResourceMisalignmentCount += result.preferredResourceMisalignmentCount;
            this.totalUpdatedCount += result.appointmentsToUpdate.size() - failedCount;
            this.totalFailedCount += failedCount;
        } catch (Exception e) {
            Logger.error('ServiceAppointmentRealignmentBatch.execute', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Logs the totals of the run.
     * @param bc Batchable context
     */
    public void finish(Database.BatchableContext bc) {
        linkLogsToStartTransaction();
        try {
            if (forceExceptionForTest == true) {
                throw new ServiceAppointmentRealignmentService.ServiceAppointmentRealignmentException(
                    'Forced batch finish failure for test'
                );
            }
            Logger.info(
                'ServiceAppointmentRealignmentBatch.finish: evaluated=' +
                    this.totalEvaluatedCount +
                    ' skipped=' +
                    this.totalSkippedCount +
                    ' territoryMisalignment=' +
                    this.totalTerritoryMisalignmentCount +
                    ' preferredResourceMisalignment=' +
                    this.totalPreferredResourceMisalignmentCount +
                    ' updated=' +
                    this.totalUpdatedCount +
                    ' failed=' +
                    this.totalFailedCount
            );
        } catch (Exception e) {
            Logger.error('ServiceAppointmentRealignmentBatch.finish', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Relates execute/finish log entries to the start transaction and sets the scenario.
     */
    private void linkLogsToStartTransaction() {
        Logger.setParentLogTransactionId(this.originalTransactionId);
        Logger.setScenario(ServiceAppointmentRealignmentConstants.LOGGER_SCENARIO);
    }
}