/**
 * @author Uptima
 * @date 2026-08-24
 * @group Services
 * @description Service class for WOAssignmentHistory__c business operations.
 *              Entry point for Repair Center assignment history create/update flows.
 *              Selectors for WAH may only be called from this service (or WAH Domain).
 */
public with sharing class WOAssignmentHistoriesService {
    private static final String TYPE_RACK = 'Rack';
    private static final String TYPE_TECHNICIAN = 'Technician';
    private static final String RECORD_TYPE_REPAIR_CENTER = 'RepairCenter';

    /**
     * @description GW-3816 - Creates an open Rack WO Assignment History row for a Work Order.
     *              Uses SYSTEM_MODE so scanner profiles without full WAH FLS can still record history.
     * @param workOrderId Work Order Id
     * @param rackId Rack Location Id
     * @param startDateTime Assignment start
     * @return Created WO Assignment History Id
     * @throws WOAssignmentHistoriesServiceException when inputs are blank/null or DML fails
     */
    public static Id createRackAssignment(Id workOrderId, Id rackId, Datetime startDateTime) {
        if (workOrderId == null || rackId == null || startDateTime == null) {
            throw new WOAssignmentHistoriesServiceException(
                'Work Order, Rack, and Start Date/Time are required to create Rack assignment history.'
            );
        }

        Logger.setScenario('WO Assignment History');
        try {
            WOAssignmentHistory__c assignment = new WOAssignmentHistory__c(
                WorkOrder__c = workOrderId,
                Type__c = TYPE_RACK,
                Rack__c = rackId,
                StartDateTime__c = startDateTime
            );
            Id repairCenterRtId = getRepairCenterRecordTypeId();
            if (repairCenterRtId != null) {
                assignment.RecordTypeId = repairCenterRtId;
            }
            Database.insert(assignment, AccessLevel.SYSTEM_MODE);
            return assignment.Id;
        } catch (WOAssignmentHistoriesServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('WOAssignmentHistoriesService.createRackAssignment failed.', e);
            throw new WOAssignmentHistoriesServiceException(
                'Unable to create Rack assignment history: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-3816 - Creates an open Technician WO Assignment History row for a Work Order.
     *              Uses SYSTEM_MODE so scanner profiles without full WAH FLS can still record history.
     * @param workOrderId Work Order Id
     * @param technicianUserId Assigned Technician User Id
     * @param startDateTime Assignment start
     * @return Created WO Assignment History Id
     * @throws WOAssignmentHistoriesServiceException when inputs are blank/null or DML fails
     */
    public static Id createTechnicianAssignment(
        Id workOrderId,
        Id technicianUserId,
        Datetime startDateTime
    ) {
        if (workOrderId == null || technicianUserId == null || startDateTime == null) {
            throw new WOAssignmentHistoriesServiceException(
                'Work Order, Technician, and Start Date/Time are required to create Technician assignment history.'
            );
        }

        Logger.setScenario('WO Assignment History');
        try {
            WOAssignmentHistory__c assignment = new WOAssignmentHistory__c(
                WorkOrder__c = workOrderId,
                Type__c = TYPE_TECHNICIAN,
                Technician__c = technicianUserId,
                StartDateTime__c = startDateTime
            );
            Id repairCenterRtId = getRepairCenterRecordTypeId();
            if (repairCenterRtId != null) {
                assignment.RecordTypeId = repairCenterRtId;
            }
            Database.insert(assignment, AccessLevel.SYSTEM_MODE);
            return assignment.Id;
        } catch (WOAssignmentHistoriesServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error('WOAssignmentHistoriesService.createTechnicianAssignment failed.', e);
            throw new WOAssignmentHistoriesServiceException(
                'Unable to create Technician assignment history: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-3816 - Ends open Technician assignment history rows for a Work Order.
     * @param workOrderId Work Order Id
     * @param endDateTime End Date/Time to apply
     */
    public static void endOpenTechnicianAssignments(Id workOrderId, Datetime endDateTime) {
        endOpenAssignmentsByType(workOrderId, TYPE_TECHNICIAN, endDateTime);
    }

    /**
     * @description GW-3816 / GW-5783 - Ends all open assignment history rows for a Work Order
     *              (any Type). Used by Assign Rack when the Rack actually changes.
     * @param workOrderId Work Order Id
     * @param endDateTime End Date/Time to apply
     */
    public static void endOpenAssignments(Id workOrderId, Datetime endDateTime) {
        if (workOrderId == null || endDateTime == null) {
            return;
        }

        Logger.setScenario('WO Assignment History');
        try {
            List<WOAssignmentHistory__c> openAssignmentList =
                WOAssignmentHistoriesSelector.selectOpenByWorkOrderId(workOrderId);
            if (openAssignmentList.isEmpty()) {
                return;
            }
            for (WOAssignmentHistory__c row : openAssignmentList) {
                row.EndDateTime__c = endDateTime;
            }
            Database.update(openAssignmentList, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            Logger.error('WOAssignmentHistoriesService.endOpenAssignments failed.', e);
            throw new WOAssignmentHistoriesServiceException(
                'Unable to end open assignment history: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Ends open assignment history rows for a Work Order and Type.
     *              Uses SYSTEM_MODE so scanner profiles can close history without full WAH FLS.
     * @param workOrderId Work Order Id
     * @param assignmentType Type__c value (e.g. Technician, Rack)
     * @param endDateTime End Date/Time to apply
     */
    public static void endOpenAssignmentsByType(
        Id workOrderId,
        String assignmentType,
        Datetime endDateTime
    ) {
        if (workOrderId == null || String.isBlank(assignmentType) || endDateTime == null) {
            return;
        }

        Logger.setScenario('WO Assignment History');
        try {
            List<WOAssignmentHistory__c> openAssignmentList =
                WOAssignmentHistoriesSelector.selectOpenByWorkOrderIdAndType(
                    workOrderId,
                    assignmentType
                );
            if (openAssignmentList.isEmpty()) {
                return;
            }
            for (WOAssignmentHistory__c row : openAssignmentList) {
                row.EndDateTime__c = endDateTime;
            }
            Database.update(openAssignmentList, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            Logger.error('WOAssignmentHistoriesService.endOpenAssignmentsByType failed.', e);
            throw new WOAssignmentHistoriesServiceException(
                'Unable to end open assignment history: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5455 / GW-5497 - Ends open Rack assignment history, ends open Technician
     *              rows owned by other users, and leaves or creates an open Technician row for
     *              the running user. Used by Assign Technician and Quality Inspection.
     * @param workOrderId Work Order Id
     * @return Existing or newly created open Technician WO Assignment History Id
     * @throws WOAssignmentHistoriesServiceException when workOrderId is null or DML fails
     */
    public static Id assignCurrentUserAsTechnician(Id workOrderId) {
        if (workOrderId == null) {
            throw new WOAssignmentHistoriesServiceException('Work Order is required.');
        }
        Datetime nowValue = System.now();
        Id currentUserId = UserInfo.getUserId();
        Logger.setScenario('WO Assignment History');
        try {
            endOpenAssignmentsByType(workOrderId, TYPE_RACK, nowValue);
            List<WOAssignmentHistory__c> technicians =
                WOAssignmentHistoriesSelector.selectOpenByWorkOrderIdAndType(
                    workOrderId,
                    TYPE_TECHNICIAN
                );
            Id currentUserAssignmentId = null;
            List<WOAssignmentHistory__c> rowsToEnd = new List<WOAssignmentHistory__c>();
            for (WOAssignmentHistory__c technician : technicians) {
                if (technician.Technician__c == currentUserId) {
                    currentUserAssignmentId = technician.Id;
                } else {
                    technician.EndDateTime__c = nowValue;
                    rowsToEnd.add(technician);
                }
            }
            if (!rowsToEnd.isEmpty()) {
                Database.update(rowsToEnd, AccessLevel.SYSTEM_MODE);
            }
            if (currentUserAssignmentId != null) {
                return currentUserAssignmentId;
            }
            return createTechnicianAssignment(workOrderId, currentUserId, nowValue);
        } catch (WOAssignmentHistoriesServiceException exceptionValue) {
            throw exceptionValue;
        } catch (Exception exceptionValue) {
            Logger.error(
                'WOAssignmentHistoriesService.assignCurrentUserAsTechnician failed.',
                exceptionValue
            );
            throw new WOAssignmentHistoriesServiceException(
                'Unable to update Technician assignment history.',
                exceptionValue
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-5497 - Ends the open Rack assignment, ends Technician assignments owned
     *              by other users, and ensures the current user has an open Technician assignment.
     * @param workOrderId Work Order entering Quality Inspection
     */
    public static void startQualityInspectionAssignment(Id workOrderId) {
        assignCurrentUserAsTechnician(workOrderId);
    }

    private static Id getRepairCenterRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> infos = Schema.SObjectType.WOAssignmentHistory__c
            .getRecordTypeInfosByDeveloperName();
        Schema.RecordTypeInfo info = infos.get(RECORD_TYPE_REPAIR_CENTER);
        return info == null ? null : info.getRecordTypeId();
    }

    /**
     * @description Thrown when a WO Assignment History service operation fails.
     */
    public class WOAssignmentHistoriesServiceException extends Exception {
    }
}