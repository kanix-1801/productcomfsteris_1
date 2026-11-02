/**
 * @description Server actions for the IMS Work Order debrief.
 *              without sharing: Field Service mobile cannot write Appointment Dependency,
 *              Service Appointment, or Assigned Resource through Lightning Data Service.
 *              Those writes fail on device with LightningDataService.SQLiteResult error 5.
 * @group Work Order Debrief
 * @see woDebriefIMS
 */
public without sharing class WoDebriefIMSController {
    /**
     * @description Creates or reassigns today's truck appointment for the selected truck.
     * @param technicianAppointmentId Service appointment assigned to the technician
     * @param truckAppointmentId Existing truck appointment. Null creates one from the technician appointment
     * @param serviceResourceId Service Resource Id of the selected truck
     * @return Truck service appointment Id
     */
    @AuraEnabled
    public static Id assignSelectedTruck(Id technicianAppointmentId, Id truckAppointmentId, Id serviceResourceId) {
        if (serviceResourceId == null || (technicianAppointmentId == null && truckAppointmentId == null)) {
            throw handledException('A service appointment and a truck are required.');
        }
        Map<Id, ServiceAppointment> appointments = queryAppointments(technicianAppointmentId, truckAppointmentId);
        ServiceAppointment technician = appointments.get(technicianAppointmentId);
        ServiceAppointment truck = appointments.get(truckAppointmentId);
        if (technicianAppointmentId != null && technician == null) {
            throw handledException('The technician appointment could not be found.');
        }
        if (truckAppointmentId != null && truck == null) {
            throw handledException('The truck appointment could not be found.');
        }
        try {
            if (truck == null) {
                truck = insertTruckAppointment(technician);
                assignResource(truck.Id, serviceResourceId, truck.SchedStartTime, truck.SchedEndTime);
                insertSameStartDependency(technician.Id, truck.Id);
            } else {
                truck = ensureTruckSchedule(truck, technician);
                assignResource(truck.Id, serviceResourceId, truck.SchedStartTime, truck.SchedEndTime);
            }
            stampSelectedTruck(technician, serviceResourceId);
        } catch (DmlException ex) {
            throw handledException(ex.getDmlMessage(0));
        }
        return truck.Id;
    }

    /**
     * @description Creates a Same Start dependency from the technician appointment to the truck appointment.
     * @param technicianAppointmentId Service appointment assigned to the technician
     * @param truckAppointmentId Service appointment assigned to the truck
     * @return Appointment Dependency Id
     */
    @AuraEnabled
    public static Id createTruckAppointmentDependency(Id technicianAppointmentId, Id truckAppointmentId) {
        if (technicianAppointmentId == null || truckAppointmentId == null) {
            throw handledException('A technician appointment and a truck appointment are required.');
        }
        try {
            return insertSameStartDependency(technicianAppointmentId, truckAppointmentId);
        } catch (DmlException ex) {
            throw handledException(ex.getDmlMessage(0));
        }
    }

    /**
     * @description Loads the technician and truck appointments used by a truck selection.
     * @param technicianAppointmentId Service appointment assigned to the technician
     * @param truckAppointmentId Existing truck appointment
     * @return Appointments keyed by Id
     */
    private static Map<Id, ServiceAppointment> queryAppointments(Id technicianAppointmentId, Id truckAppointmentId) {
        Set<Id> appointmentIds = new Set<Id>();
        if (technicianAppointmentId != null) {
            appointmentIds.add(technicianAppointmentId);
        }
        if (truckAppointmentId != null) {
            appointmentIds.add(truckAppointmentId);
        }
        return new Map<Id, ServiceAppointment>([
            SELECT Id, ParentRecordId, Subject, EarliestStartTime, DueDate,
                SchedStartTime, SchedEndTime, Duration, DurationType,
                ServiceTerritoryId, Truck__c
            FROM ServiceAppointment
            WHERE Id IN :appointmentIds
        ]);
    }

    /**
     * @description Inserts a truck appointment on the technician appointment's schedule.
     * @param technician Service appointment assigned to the technician
     * @return Inserted truck appointment
     */
    private static ServiceAppointment insertTruckAppointment(ServiceAppointment technician) {
        if (technician.ParentRecordId == null || technician.SchedStartTime == null || technician.SchedEndTime == null) {
            throw handledException('The current service appointment needs a scheduled start and end before a truck can be assigned.');
        }
        ServiceAppointment truck = new ServiceAppointment(
            ParentRecordId = technician.ParentRecordId,
            TruckAppointment__c = true,
            Subject = String.isBlank(technician.Subject) ? 'Truck appointment' : technician.Subject,
            EarliestStartTime = technician.EarliestStartTime != null ? technician.EarliestStartTime : technician.SchedStartTime,
            DueDate = technician.DueDate != null ? technician.DueDate : technician.SchedEndTime,
            SchedStartTime = technician.SchedStartTime,
            SchedEndTime = technician.SchedEndTime,
            ServiceTerritoryId = technician.ServiceTerritoryId,
            Duration = technician.Duration,
            DurationType = technician.DurationType
        );
        insert truck;
        return truck;
    }

    /**
     * @description Copies the technician schedule onto a truck appointment that has no schedule.
     * @param truck Truck service appointment
     * @param technician Technician service appointment. May be null
     * @return Truck appointment with a schedule
     */
    private static ServiceAppointment ensureTruckSchedule(ServiceAppointment truck, ServiceAppointment technician) {
        if (truck.SchedStartTime != null && truck.SchedEndTime != null) {
            return truck;
        }
        if (technician == null || technician.SchedStartTime == null || technician.SchedEndTime == null) {
            throw handledException('The service appointment needs a scheduled start and end before the assigned resource can be updated.');
        }
        truck.SchedStartTime = technician.SchedStartTime;
        truck.SchedEndTime = technician.SchedEndTime;
        if (truck.EarliestStartTime == null) {
            truck.EarliestStartTime = technician.EarliestStartTime != null
                ? technician.EarliestStartTime
                : technician.SchedStartTime;
        }
        if (truck.DueDate == null) {
            truck.DueDate = technician.DueDate != null ? technician.DueDate : technician.SchedEndTime;
        }
        if (truck.ServiceTerritoryId == null) {
            truck.ServiceTerritoryId = technician.ServiceTerritoryId;
        }
        update truck;
        return truck;
    }

    /**
     * @description Points the truck appointment at the selected truck.
     *              Field Service does not allow Service Resource to change, so a different truck replaces the row.
     * @param serviceAppointmentId Truck service appointment
     * @param serviceResourceId Selected truck
     * @param startTime Scheduled start to restore if the assigned resource is replaced
     * @param endTime Scheduled end to restore if the assigned resource is replaced
     */
    private static void assignResource(Id serviceAppointmentId, Id serviceResourceId, Datetime startTime, Datetime endTime) {
        List<AssignedResource> existing = [
            SELECT Id, ServiceResourceId
            FROM AssignedResource
            WHERE ServiceAppointmentId = :serviceAppointmentId
        ];
        if (existing.size() == 1 && existing[0].ServiceResourceId == serviceResourceId) {
            return;
        }
        if (!existing.isEmpty()) {
            delete existing;
            if (startTime != null && endTime != null) {
                update new ServiceAppointment(
                    Id = serviceAppointmentId,
                    SchedStartTime = startTime,
                    SchedEndTime = endTime
                );
            }
        }
        insert new AssignedResource(
            ServiceAppointmentId = serviceAppointmentId,
            ServiceResourceId = serviceResourceId
        );
    }

    /**
     * @description Stores the selected truck on the technician appointment.
     * @param technician Technician service appointment. May be null
     * @param serviceResourceId Selected truck
     */
    private static void stampSelectedTruck(ServiceAppointment technician, Id serviceResourceId) {
        if (technician == null || technician.Truck__c == serviceResourceId) {
            return;
        }
        update new ServiceAppointment(
            Id = technician.Id,
            Truck__c = serviceResourceId
        );
    }

    /**
     * @description Inserts a Same Start dependency from the technician appointment to the truck appointment.
     * @param technicianAppointmentId Service appointment assigned to the technician
     * @param truckAppointmentId Service appointment assigned to the truck
     * @return Appointment Dependency Id
     */
    private static Id insertSameStartDependency(Id technicianAppointmentId, Id truckAppointmentId) {
        FSL__Time_Dependency__c dependency = new FSL__Time_Dependency__c(
            FSL__Service_Appointment_1__c = technicianAppointmentId,
            FSL__Service_Appointment_2__c = truckAppointmentId,
            FSL__Dependency__c = 'Same Start',
            FSL__Same_Resource__c = false,
            FSL__Root_Service_Appointment__c = technicianAppointmentId
        );
        insert dependency;
        return dependency.Id;
    }

    /** @description Child work orders in these statuses do not block the site visit review. */
    private static final Set<String> SITE_VISIT_FINISHED_STATUSES = new Set<String>{
        'Completed', 'Closed', 'Canceled', 'Cannot Complete'
    };

    /**
     * @description GW-1353 - Result of Finish Review Child Work Order on an IMS site visit.
     */
    public class SiteVisitReviewResult {
        /** @description True when no child work order is still open and no repair-center line is waiting. */
        @AuraEnabled public Boolean canFinish;
        /** @description Child work order numbers that are not finished. */
        @AuraEnabled public List<String> openWorkOrders;
        /** @description Child lines still marked Send to Repair Center. */
        @AuraEnabled public List<String> returnOrderLines;
    }

    /**
     * @description GW-1353 - Checks that every child work order is finished and no child line
     *              is still waiting for a return order. When both pass, Child Work Order Review Done
     *              is checked on the site visit. No status is changed.
     * @param workOrderId Site visit Work Order Id
     * @return Review result
     */
    @AuraEnabled
    public static SiteVisitReviewResult checkSiteVisitReview(Id workOrderId) {
        if (workOrderId == null) {
            throw handledException('Work order could not be identified.');
        }
        List<WorkOrder> children = [
            SELECT Id, WorkOrderNumber, Status
            FROM WorkOrder
            WHERE ParentWorkOrderId = :workOrderId
            ORDER BY WorkOrderNumber
        ];
        List<WorkOrderLineItem> pendingReturnLines = [
            SELECT Id, LineItemNumber, Description, WorkOrder.WorkOrderNumber, Product2.Name
            FROM WorkOrderLineItem
            WHERE WorkOrder.ParentWorkOrderId = :workOrderId
                AND SendToRepairCenter__c = true
            ORDER BY WorkOrder.WorkOrderNumber, LineItemNumber
        ];

        SiteVisitReviewResult result = new SiteVisitReviewResult();
        result.openWorkOrders = new List<String>();
        result.returnOrderLines = new List<String>();
        for (WorkOrder child : children) {
            if (!SITE_VISIT_FINISHED_STATUSES.contains(child.Status)) {
                result.openWorkOrders.add(
                    String.isNotBlank(child.WorkOrderNumber) ? child.WorkOrderNumber : String.valueOf(child.Id)
                );
            }
        }
        for (WorkOrderLineItem line : pendingReturnLines) {
            result.returnOrderLines.add(returnOrderLineLabel(line));
        }
        result.canFinish = result.openWorkOrders.isEmpty() && result.returnOrderLines.isEmpty();
        if (result.canFinish) {
            try {
                update new WorkOrder(Id = workOrderId, ChildWorkOrderReviewDone__c = true);
            } catch (DmlException ex) {
                throw handledException(ex.getDmlMessage(0));
            }
        }
        return result;
    }

    /**
     * @description GW-1353 - Line label used when a return order is still required.
     * @param line Child work order line marked Send to Repair Center
     * @return Work order number, line number, and item name
     */
    private static String returnOrderLineLabel(WorkOrderLineItem line) {
        String workOrderNumber = String.isNotBlank(line.WorkOrder?.WorkOrderNumber)
            ? line.WorkOrder.WorkOrderNumber
            : 'Work order';
        String itemName = String.isNotBlank(line.Product2?.Name)
            ? line.Product2.Name
            : (String.isNotBlank(line.Description) ? line.Description : 'Line');
        String lineNumber = String.isNotBlank(line.LineItemNumber) ? line.LineItemNumber : '';
        String lineLabel = String.isBlank(lineNumber) ? itemName : 'Line ' + lineNumber + ' - ' + itemName;
        return workOrderNumber + ': ' + lineLabel;
    }

    /**
     * @description Aura exception whose message is returned to the LWC.
     * @param message Message shown in the debrief toast
     * @return Exception to throw
     */
    private static AuraHandledException handledException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}