/**
 * @author Sagar Anand
 * @date 2026-10-29
 * @description GW-6099 - Flow action that starts the Service Appointment Realignment Analysis for the
 *              Service Territories selected in the screen flow ServiceAppointment_SCR_RealignmentAnalysis.
 *              Delegates to ServiceAppointmentRealignmentService.
 * @group Field Service
 * @see ServiceAppointmentRealignmentService
 */
public with sharing class ServiceAppointmentRealignmentInvocable {
    /**
     * @description Flow request: the Service Territories selected in the data table.
     */
    public class Request {
        @InvocableVariable(
            label='Service Territories'
            description='Service Territories to include in the analysis'
            required=true
        )
        public List<ServiceTerritory> serviceTerritories;
    }

    /**
     * @description Flow result.
     */
    public class Result {
        @InvocableVariable(label='Job Id' description='Id of the batch job that was started')
        public Id jobId;

        @InvocableVariable(
            label='Is Already Running'
            description='True when a previous Realignment Analysis is still running, so nothing was started'
        )
        public Boolean isAlreadyRunning;
    }

    /**
     * @description Starts one Realignment Analysis for all territories in the requests.
     * @param requests Flow requests (normally one)
     * @return One result per request, all describing the same run
     * @throws ServiceAppointmentRealignmentService.ServiceAppointmentRealignmentException when the run cannot start
     */
    @InvocableMethod(
        label='Start Realignment Analysis'
        description='GW-6099 - Starts the Realignment Analysis batch for the selected Service Territories.'
        category='Field Service'
    )
    public static List<Result> startRealignmentAnalysis(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        Set<Id> serviceTerritoryIdSet = new Set<Id>();
        for (Request request : requests) {
            if (request?.serviceTerritories == null) {
                continue;
            }
            for (ServiceTerritory serviceTerritory : request.serviceTerritories) {
                if (serviceTerritory?.Id != null) {
                    serviceTerritoryIdSet.add(serviceTerritory.Id);
                }
            }
        }

        ServiceAppointmentRealignmentService.StartResult started = ServiceAppointmentRealignmentService.startAnalysis(
            serviceTerritoryIdSet
        );
        for (Integer i = 0; i < requests.size(); i++) {
            Result result = new Result();
            result.jobId = started.jobId;
            result.isAlreadyRunning = started.isAlreadyRunning;
            results.add(result);
        }
        return results;
    }
}