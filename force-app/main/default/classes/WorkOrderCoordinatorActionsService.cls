/**
 * GW-5231 Work Order orchestration for Repair Coordinator Actions.
 *
 * @author Uptima
 * @date 2026-09-21
 * @group Repair Center
 * @description GW-5231 orchestration for scanning Work Orders, Racks, and Service Teams.
 */
public with sharing class WorkOrderCoordinatorActionsService {
    private static final String TYPE_RACK = 'RACK';
    private static final String TYPE_SERVICE_TEAM = 'SERVICE_TEAM';
    private static final String HISTORY_TYPE_RACK = 'Rack';
    private static final Set<String> BLOCKED_WORK_ORDER_STATUSES = new Set<String>{
        'Received',
        'Evaluate',
        'Quote',
        'Divide',
        'Evaluate & Quote'
    };
    private static final String BLOCKED_STATUS_MESSAGE =
        'The selected Work Order is not Ready for Repair and cannot be assigned.';
    private static final String INVALID_FIRST_SCAN_MESSAGE =
        'You must first scan in a valid Work Order before you can proceed with assignments.';
    private static final String INVALID_ASSIGNMENT_SCAN_MESSAGE =
        'The scanned barcode does not represent a valid record Id.';
    private static final String SERVICE_TEAM_REPAIR_CENTER_MESSAGE =
        'The Service Team is not tied to this Work Order\'s Repair Center.';

    /**
     * @description GW-5231 - Processes a barcode as a Work Order, Rack, or Service Team.
     * @param currentWorkOrderId Current Work Order Id, or null before the first Work Order scan
     * @param scanValue Barcode value
     * @return Current assignment state, optional success message, and any ambiguous choices
     * @throws CoordinatorActionsException when the scan or selected Work Order is invalid
     */
    public static ScanResult processScan(Id currentWorkOrderId, String scanValue) {
        Logger.setScenario('Repair Coordinator Actions');
        try {
            return new CoordinatorActionsWorker().processScan(currentWorkOrderId, scanValue);
        } catch (CoordinatorActionsException e) {
            throw e;
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'GW-5231 processScan failed for Work Order {0}, scan {1}: {2}',
                    currentWorkOrderId,
                    scanValue,
                    e.getMessage()
                ),
                e
            );
            throw new CoordinatorActionsException('Unable to process the barcode: ' + e.getMessage(), e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5231 - Assigns the Rack or Service Team chosen from an ambiguous scan.
     * @param workOrderId Current Work Order Id
     * @param assignmentType RACK or SERVICE_TEAM
     * @param assignmentId Selected Rack or Service Team Id
     * @return Updated assignment state and success message
     * @throws CoordinatorActionsException when the selection is invalid
     */
    public static ScanResult assignCandidate(
        Id workOrderId,
        String assignmentType,
        Id assignmentId
    ) {
        Logger.setScenario('Repair Coordinator Actions');
        try {
            return new CoordinatorActionsWorker().assignCandidate(
                workOrderId,
                assignmentType,
                assignmentId
            );
        } catch (CoordinatorActionsException e) {
            throw e;
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'GW-5231 assignCandidate failed for Work Order {0}, assignment {1}: {2}',
                    workOrderId,
                    assignmentId,
                    e.getMessage()
                ),
                e
            );
            throw new CoordinatorActionsException('Unable to assign the selection: ' + e.getMessage(), e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5231 - Clears Rack__c and closes open Rack assignment history.
     *              RepairCategory__c is intentionally retained pending business confirmation.
     * @param workOrderId Current Work Order Id
     * @return Updated assignment state and success message
     * @throws CoordinatorActionsException when the Work Order is invalid
     */
    public static ScanResult removeRack(Id workOrderId) {
        Logger.setScenario('Repair Coordinator Actions');
        try {
            return new CoordinatorActionsWorker().removeRack(workOrderId);
        } catch (CoordinatorActionsException e) {
            throw e;
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'GW-5231 removeRack failed for Work Order {0}: {1}',
                    workOrderId,
                    e.getMessage()
                ),
                e
            );
            throw new CoordinatorActionsException('Unable to remove the Rack: ' + e.getMessage(), e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5231 - Clears ServiceTeam__c from the current Work Order.
     * @param workOrderId Current Work Order Id
     * @return Updated assignment state and success message
     * @throws CoordinatorActionsException when the Work Order is invalid
     */
    public static ScanResult removeServiceTeam(Id workOrderId) {
        Logger.setScenario('Repair Coordinator Actions');
        try {
            return new CoordinatorActionsWorker().removeServiceTeam(workOrderId);
        } catch (CoordinatorActionsException e) {
            throw e;
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'GW-5231 removeServiceTeam failed for Work Order {0}: {1}',
                    workOrderId,
                    e.getMessage()
                ),
                e
            );
            throw new CoordinatorActionsException(
                'Unable to remove the Service Team: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5231 - Result returned to the Repair Coordinator Actions LWC.
     */
    public class ScanResult {
        /** GW-5231 - Current Work Order Id. */
        @AuraEnabled public Id workOrderId { get; set; }
        /** GW-5231 - Current Work Order Number. */
        @AuraEnabled public String workOrderNumber { get; set; }
        /** GW-5231 - Current Work Order Status. */
        @AuraEnabled public String workOrderStatus { get; set; }
        /** GW-5231 - Assigned Rack Id. */
        @AuraEnabled public Id rackId { get; set; }
        /** GW-5231 - Assigned Rack Name. */
        @AuraEnabled public String rackName { get; set; }
        /** GW-5231 - Assigned Service Team Id. */
        @AuraEnabled public Id serviceTeamId { get; set; }
        /** GW-5231 - Assigned Service Team Name. */
        @AuraEnabled public String serviceTeamName { get; set; }
        /** GW-5231 - User-facing operation result. */
        @AuraEnabled public String message { get; set; }
        /** GW-5231 - Rack and Service Team choices for an ambiguous scan. */
        @AuraEnabled public List<AssignmentCandidate> candidates { get; set; }
    }

    /**
     * @description GW-5231 - One Rack or Service Team choice for an ambiguous barcode.
     */
    public class AssignmentCandidate {
        /** GW-5231 - Candidate record Id. */
        @AuraEnabled public Id recordId { get; set; }
        /** GW-5231 - Candidate type (RACK or SERVICE_TEAM). */
        @AuraEnabled public String assignmentType { get; set; }
        /** GW-5231 - Primary candidate label. */
        @AuraEnabled public String label { get; set; }
        /** GW-5231 - Optional candidate context. */
        @AuraEnabled public String detail { get; set; }
    }

    /**
     * @description GW-5231 - Business-friendly exception for coordinator scan operations.
     */
    public class CoordinatorActionsException extends Exception {
    }

    /**
     * @description GW-5231 - Shop-floor scans run without sharing so permitted users can
     *              resolve assignment records regardless of record-level sharing.
     */
    private without sharing class CoordinatorActionsWorker {
        /**
         * @description GW-5231 - Resolves and processes one barcode scan.
         * @param currentWorkOrderId Current Work Order Id
         * @param scanValue Barcode value
         * @return Current assignment state or ambiguous choices
         */
        public ScanResult processScan(Id currentWorkOrderId, String scanValue) {
            if (String.isBlank(scanValue)) {
                throw new CoordinatorActionsException('Scan Barcode is required.');
            }

            String trimmedScan = scanValue.trim();
            if (currentWorkOrderId == null) {
                WorkOrder firstWorkOrder =
                    WorkOrdersSelector.selectForCoordinatorActionsByIdOrNumber(trimmedScan);
                if (firstWorkOrder == null) {
                    throw new CoordinatorActionsException(INVALID_FIRST_SCAN_MESSAGE);
                }
                validateWorkOrderStatus(firstWorkOrder);
                return buildResult(firstWorkOrder, null);
            }

            WorkOrder scannedWorkOrder =
                WorkOrdersSelector.selectForCoordinatorActionsByIdOrNumber(trimmedScan);
            if (scannedWorkOrder != null) {
                validateWorkOrderStatus(scannedWorkOrder);
                return buildResult(scannedWorkOrder, null);
            }

            WorkOrder currentWorkOrder =
                WorkOrdersSelector.selectForCoordinatorActionsById(currentWorkOrderId);
            validateCurrentWorkOrder(currentWorkOrder);

            Schema.Location rack = LocationsService.getRackByIdOrName(trimmedScan);
            List<ServiceTeam__c> serviceTeams = resolveServiceTeamsForAssignment(
                trimmedScan,
                currentWorkOrder.RepairCenter__c,
                rack == null
            );
            List<AssignmentCandidate> candidates = buildCandidates(rack, serviceTeams);

            if (candidates.isEmpty()) {
                throw new CoordinatorActionsException(INVALID_ASSIGNMENT_SCAN_MESSAGE);
            }
            if (candidates.size() > 1) {
                ScanResult ambiguousResult = buildResult(currentWorkOrder, null);
                ambiguousResult.candidates = candidates;
                return ambiguousResult;
            }

            AssignmentCandidate candidate = candidates[0];
            return assignCandidate(
                currentWorkOrder.Id,
                candidate.assignmentType,
                candidate.recordId
            );
        }

        /**
         * @description GW-5231 - Assigns one explicit Rack or Service Team candidate.
         * @param workOrderId Current Work Order Id
         * @param assignmentType RACK or SERVICE_TEAM
         * @param assignmentId Candidate record Id
         * @return Updated assignment state
         */
        public ScanResult assignCandidate(
            Id workOrderId,
            String assignmentType,
            Id assignmentId
        ) {
            WorkOrder workOrder = WorkOrdersSelector.selectForCoordinatorActionsById(workOrderId);
            validateCurrentWorkOrder(workOrder);
            if (assignmentId == null) {
                throw new CoordinatorActionsException('An assignment selection is required.');
            }

            if (assignmentType == TYPE_RACK) {
                Schema.Location rack = LocationsService.getRackByIdOrName(String.valueOf(assignmentId));
                if (rack == null) {
                    throw new CoordinatorActionsException('The selected Rack is no longer available.');
                }
                return assignRack(workOrder, rack);
            }
            if (assignmentType == TYPE_SERVICE_TEAM) {
                List<ServiceTeam__c> serviceTeams = resolveServiceTeamsForAssignment(
                    String.valueOf(assignmentId),
                    workOrder.RepairCenter__c,
                    true
                );
                if (serviceTeams.size() != 1) {
                    throw new CoordinatorActionsException(
                        'The selected Service Team is no longer available.'
                    );
                }
                return assignServiceTeam(workOrder, serviceTeams[0]);
            }
            throw new CoordinatorActionsException('The assignment type is invalid.');
        }

        /**
         * @description GW-5231 - Clears the Rack while retaining Repair Category.
         * @param workOrderId Current Work Order Id
         * @return Updated assignment state
         */
        public ScanResult removeRack(Id workOrderId) {
            WorkOrder workOrder = WorkOrdersSelector.selectForCoordinatorActionsById(workOrderId);
            validateCurrentWorkOrder(workOrder);
            if (workOrder.Rack__c != null) {
                Datetime now = Datetime.now();
                workOrder.Rack__c = null;
                Database.update(workOrder, AccessLevel.SYSTEM_MODE);
                WOAssignmentHistoriesService.endOpenAssignmentsByType(
                    workOrder.Id,
                    HISTORY_TYPE_RACK,
                    now
                );
            }
            return buildResult(
                WorkOrdersSelector.selectForCoordinatorActionsById(workOrder.Id),
                'Rack removed from ' + workOrder.WorkOrderNumber + '.'
            );
        }

        /**
         * @description GW-5231 - Clears the Service Team.
         * @param workOrderId Current Work Order Id
         * @return Updated assignment state
         */
        public ScanResult removeServiceTeam(Id workOrderId) {
            WorkOrder workOrder = WorkOrdersSelector.selectForCoordinatorActionsById(workOrderId);
            validateCurrentWorkOrder(workOrder);
            if (workOrder.ServiceTeam__c != null) {
                workOrder.ServiceTeam__c = null;
                Database.update(workOrder, AccessLevel.SYSTEM_MODE);
            }
            return buildResult(
                WorkOrdersSelector.selectForCoordinatorActionsById(workOrder.Id),
                'Service Team removed from ' + workOrder.WorkOrderNumber + '.'
            );
        }

        /**
         * @description GW-5231 / GW-5783 - Replaces the Rack only when it changes.
         *              Ends all open assignment history, then creates a Rack row when tracking.
         * @param workOrder Current Work Order
         * @param rack Rack to assign
         * @return Updated assignment state
         */
        private ScanResult assignRack(WorkOrder workOrder, Schema.Location rack) {
            Boolean sameRack = workOrder.Rack__c == rack.Id;
            if (!sameRack) {
                workOrder.Rack__c = rack.Id;
            }
            if (String.isNotBlank(rack.Repair_Category__c)) {
                workOrder.RepairCategory__c = rack.Repair_Category__c;
            }
            WorkOrdersService.applyRackStatusAssignment(workOrder, rack);

            Boolean hasRackAssignmentValues =
                String.isNotBlank(rack.Repair_Category__c) ||
                String.isNotBlank(rack.StatusAssignment__c);
            if (sameRack && !hasRackAssignmentValues) {
                return buildResult(
                    workOrder,
                    'Rack Successfully Assigned to ' + workOrder.WorkOrderNumber + '.'
                );
            }

            Datetime now = Datetime.now();
            WorkOrdersService.updateWorkOrderAfterRackAssignment(workOrder, rack);
            if (!sameRack) {
                WOAssignmentHistoriesService.endOpenAssignments(workOrder.Id, now);
                if (rack.TrackRackAssignmentHistory__c == true) {
                    WOAssignmentHistoriesService.createRackAssignment(workOrder.Id, rack.Id, now);
                }
            }

            return buildResult(
                WorkOrdersSelector.selectForCoordinatorActionsById(workOrder.Id),
                'Rack Successfully Assigned to ' + workOrder.WorkOrderNumber + '.'
            );
        }

        /**
         * @description GW-5231 - Replaces the Service Team.
         * @param workOrder Current Work Order
         * @param serviceTeam Service Team to assign
         * @return Updated assignment state
         */
        private ScanResult assignServiceTeam(
            WorkOrder workOrder,
            ServiceTeam__c serviceTeam
        ) {
            if (workOrder.ServiceTeam__c != serviceTeam.Id) {
                workOrder.ServiceTeam__c = serviceTeam.Id;
                Database.update(workOrder, AccessLevel.SYSTEM_MODE);
            }
            return buildResult(
                WorkOrdersSelector.selectForCoordinatorActionsById(workOrder.Id),
                'Service Team Successfully Assigned to ' + workOrder.WorkOrderNumber + '.'
            );
        }

        /**
         * @description GW-5231 - Keeps Service Teams whose Location matches the Work Order Repair Center.
         *              A match at another Repair Center is rejected when no Rack was scanned.
         * @param serviceTeamInput Service Team Id or Name
         * @param repairCenterId Work Order Repair Center Location Id
         * @param rejectOtherRepairCenter True when a team at another center should be an error
         * @return Service Teams at the Work Order Repair Center
         */
        private List<ServiceTeam__c> resolveServiceTeamsForAssignment(
            String serviceTeamInput,
            Id repairCenterId,
            Boolean rejectOtherRepairCenter
        ) {
            List<ServiceTeam__c> serviceTeams =
                ServiceTeamsService.getServiceTeamsByIdOrNameAtLocation(
                    serviceTeamInput,
                    repairCenterId
                );
            if (!serviceTeams.isEmpty() || rejectOtherRepairCenter != true) {
                return serviceTeams;
            }

            List<ServiceTeam__c> teamsAtAnyCenter =
                ServiceTeamsService.getServiceTeamsByIdOrName(serviceTeamInput);
            if (!teamsAtAnyCenter.isEmpty()) {
                throw new CoordinatorActionsException(SERVICE_TEAM_REPAIR_CENTER_MESSAGE);
            }
            return serviceTeams;
        }

        /**
         * @description GW-5231 - Builds Rack and Service Team choices for a scan.
         * @param rack Matching Rack, if any
         * @param serviceTeams Matching Service Teams
         * @return Assignment candidates
         */
        private List<AssignmentCandidate> buildCandidates(
            Schema.Location rack,
            List<ServiceTeam__c> serviceTeams
        ) {
            List<AssignmentCandidate> candidates = new List<AssignmentCandidate>();
            if (rack != null) {
                AssignmentCandidate rackCandidate = new AssignmentCandidate();
                rackCandidate.recordId = rack.Id;
                rackCandidate.assignmentType = TYPE_RACK;
                rackCandidate.label = 'Rack: ' + rack.Name;
                rackCandidate.detail = String.isBlank(rack.Repair_Category__c)
                    ? 'Repair Rack'
                    : 'Repair Category: ' + rack.Repair_Category__c;
                candidates.add(rackCandidate);
            }

            Set<Id> locationIds = new Set<Id>();
            for (ServiceTeam__c serviceTeam : serviceTeams) {
                if (serviceTeam.Location__c != null) {
                    locationIds.add(serviceTeam.Location__c);
                }
            }
            Map<Id, Schema.Location> locationsById = new Map<Id, Schema.Location>();
            for (Schema.Location location : LocationsService.getLocationsById(locationIds)) {
                locationsById.put(location.Id, location);
            }

            for (ServiceTeam__c serviceTeam : serviceTeams) {
                AssignmentCandidate teamCandidate = new AssignmentCandidate();
                teamCandidate.recordId = serviceTeam.Id;
                teamCandidate.assignmentType = TYPE_SERVICE_TEAM;
                teamCandidate.label = 'Service Team: ' + serviceTeam.Name;
                Schema.Location teamLocation = locationsById.get(serviceTeam.Location__c);
                String locationName = teamLocation?.Name;
                teamCandidate.detail = String.isBlank(locationName)
                    ? 'Record ID: ' + serviceTeam.Id
                    : 'Location: ' + locationName;
                candidates.add(teamCandidate);
            }
            return candidates;
        }

        /**
         * @description GW-5231 - Verifies that the selected Work Order still exists and is eligible.
         * @param workOrder Current Work Order
         */
        private void validateCurrentWorkOrder(WorkOrder workOrder) {
            if (workOrder == null) {
                throw new CoordinatorActionsException(
                    'The current Work Order is no longer available. Scan another Work Order.'
                );
            }
            validateWorkOrderStatus(workOrder);
        }

        /**
         * @description GW-5231 - Blocks pre–Ready for Repair lifecycle statuses.
         * @param workOrder Work Order to validate
         */
        private void validateWorkOrderStatus(WorkOrder workOrder) {
            if (BLOCKED_WORK_ORDER_STATUSES.contains(workOrder.Status)) {
                throw new CoordinatorActionsException(BLOCKED_STATUS_MESSAGE);
            }
        }

        /**
         * @description GW-5231 - Maps a Work Order to the LWC response DTO.
         * @param workOrder Current Work Order
         * @param message Optional user-facing message
         * @return LWC response DTO
         */
        private ScanResult buildResult(WorkOrder workOrder, String message) {
            ScanResult result = new ScanResult();
            result.workOrderId = workOrder.Id;
            result.workOrderNumber = workOrder.WorkOrderNumber;
            result.workOrderStatus = workOrder.Status;
            result.rackId = workOrder.Rack__c;
            result.rackName = resolveRackName(workOrder.Rack__c);
            result.serviceTeamId = workOrder.ServiceTeam__c;
            result.serviceTeamName = resolveServiceTeamName(workOrder.ServiceTeam__c);
            result.message = message;
            result.candidates = new List<AssignmentCandidate>();
            return result;
        }

        /**
         * @description GW-5231 - Resolves the assigned Rack name through LocationsService.
         * @param rackId Assigned Rack Id
         * @return Rack name, or null
         */
        private String resolveRackName(Id rackId) {
            if (rackId == null) {
                return null;
            }
            Schema.Location rack = LocationsService.getRackByIdOrName(String.valueOf(rackId));
            return rack?.Name;
        }

        /**
         * @description GW-5231 - Resolves the assigned Service Team name through ServiceTeamsService.
         * @param serviceTeamId Assigned Service Team Id
         * @return Service Team name, or null
         */
        private String resolveServiceTeamName(Id serviceTeamId) {
            if (serviceTeamId == null) {
                return null;
            }
            List<ServiceTeam__c> serviceTeams =
                ServiceTeamsService.getServiceTeamsByIdOrName(String.valueOf(serviceTeamId));
            return serviceTeams.isEmpty() ? null : serviceTeams[0].Name;
        }
    }
}