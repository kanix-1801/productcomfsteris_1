/**
 * @description Selector for Assigned Resource records on a Work Order's service appointments.
 */
public with sharing class AssignedResourcesSelector extends SoqlQueryBuilder {
    /**
     * @description Binds this selector to AssignedResource.
     */
    public AssignedResourcesSelector() {
        super('AssignedResource');
    }

    /**
     * @description Assignments whose service appointment belongs to the Work Order.
     * @param workOrderId Parent Work Order Id on ServiceAppointment.ParentRecordId.
     * @return Assignment Id, service appointment, and service resource.
     * @example
     * AssignedResourcesSelector.selectByWorkOrderId(workOrderId);
     */
    public static List<AssignedResource> selectByWorkOrderId(Id workOrderId) {
        if (workOrderId == null) {
            return new List<AssignedResource>();
        }
        return (List<AssignedResource>) new AssignedResourcesSelector()
            .selectFields(new List<String>{ 'Id', 'ServiceAppointmentId', 'ServiceResourceId' })
            .whereEquals('ServiceAppointment.ParentRecordId', workOrderId)
            .execute();
    }
}