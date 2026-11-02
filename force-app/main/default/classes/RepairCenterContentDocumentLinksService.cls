/**
 * @description GW-5830 - Repair Center ContentDocumentLink automation for the
 *              PO Required substatus. When a file is linked to a parent Work Order
 *              that already has a Customer PO, advances PO Required children to
 *              Ready for Repair. Also exposed as an invocable for
 *              RepairCenterWorkOrder_Updated_AfterSave when Customer PO is filled
 *              and the parent already has an attachment.
 * @group WorkOrder
 */
public with sharing class RepairCenterContentDocumentLinksService {
    private static final String SUB_STATUS_PO_REQUIRED = 'PO Required';
    private static final String STATUS_READY_FOR_REPAIR = 'Ready for Repair';
    private static final Set<String> REPAIR_CENTER_RECORD_TYPE_DEVELOPER_NAMES = new Set<String>{
        'RepairCenterDevices',
        'RepairCenterInstruments',
        'RepairCenterOther'
    };

    /**
     * @description GW-5830 - Flow request for advancing a child Work Order when
     *              Customer PO is filled while Sub Status is PO Required.
     */
    public class CustomerPoAdvanceRequest {
        @InvocableVariable(required=true label='Work Order Id')
        public Id workOrderId;
    }

    /**
     * @description GW-5830 - After ContentDocumentLink insert, advances PO Required
     *              children when the link targets a Repair Center parent Work Order
     *              that has a Customer PO.
     * @param links Newly inserted ContentDocumentLink records
     */
    public static void handleNewContentDocumentLinks(List<ContentDocumentLink> links) {
        if (links == null || links.isEmpty()) {
            return;
        }

        Set<Id> linkedWorkOrderIds = new Set<Id>();
        for (ContentDocumentLink link : links) {
            if (link == null || link.LinkedEntityId == null) {
                continue;
            }
            if (link.LinkedEntityId.getSObjectType() == WorkOrder.SObjectType) {
                linkedWorkOrderIds.add(link.LinkedEntityId);
            }
        }

        if (linkedWorkOrderIds.isEmpty()) {
            return;
        }

        Set<Id> eligibleParentIds = new Set<Id>();
        for (WorkOrder workOrder : queryWorkOrdersById(linkedWorkOrderIds)) {
            if (isEligibleParentWorkOrder(workOrder)) {
                eligibleParentIds.add(workOrder.Id);
            }
        }

        advancePoRequiredChildren(eligibleParentIds);
    }

    /**
     * @description GW-5830 - Invocable used by RepairCenterWorkOrder_Updated_AfterSave
     *              when Customer PO is filled on a child with Sub Status PO Required
     *              and the parent Work Order already has an attachment.
     * @param requests Flow requests containing child Work Order Ids
     */
    @InvocableMethod(
        label='GW-5830 Advance PO Required When Customer PO Filled'
        description='Advances child Work Orders from PO Required to Ready for Repair when Customer PO is present and the parent has an attachment.'
        category='Repair Center'
    )
    public static void advancePoRequiredWhenCustomerPoFilled(List<CustomerPoAdvanceRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Set<Id> childWorkOrderIds = new Set<Id>();
        for (CustomerPoAdvanceRequest request : requests) {
            if (request != null && request.workOrderId != null) {
                childWorkOrderIds.add(request.workOrderId);
            }
        }

        if (childWorkOrderIds.isEmpty()) {
            return;
        }

        List<WorkOrder> children = queryWorkOrdersById(childWorkOrderIds);
        Set<Id> parentIdsNeedingAttachmentCheck = new Set<Id>();
        List<WorkOrder> candidates = new List<WorkOrder>();

        for (WorkOrder child : children) {
            if (!isPoRequiredChildWithCustomerPo(child)) {
                continue;
            }
            candidates.add(child);
            parentIdsNeedingAttachmentCheck.add(child.ParentWorkOrderId);
        }

        if (candidates.isEmpty()) {
            return;
        }

        Set<Id> parentsWithAttachment = parentsWithAttachment(parentIdsNeedingAttachmentCheck);
        List<WorkOrder> toUpdate = new List<WorkOrder>();
        for (WorkOrder child : candidates) {
            if (parentsWithAttachment.contains(child.ParentWorkOrderId)) {
                toUpdate.add(
                    new WorkOrder(
                        Id = child.Id,
                        Status = STATUS_READY_FOR_REPAIR,
                        SubStatus__c = null
                    )
                );
            }
        }

        updateWorkOrders(toUpdate);
    }

    /**
     * @description GW-5830 - Finds PO Required children under the given parents and
     *              sets Status to Ready for Repair with Sub Status cleared.
     * @param parentWorkOrderIds Parent Work Order Ids
     */
    @TestVisible
    private static void advancePoRequiredChildren(Set<Id> parentWorkOrderIds) {
        if (parentWorkOrderIds == null || parentWorkOrderIds.isEmpty()) {
            return;
        }

        List<WorkOrder> toUpdate = new List<WorkOrder>();
        for (WorkOrder child : queryPoRequiredChildren(parentWorkOrderIds)) {
            toUpdate.add(
                new WorkOrder(
                    Id = child.Id,
                    Status = STATUS_READY_FOR_REPAIR,
                    SubStatus__c = null
                )
            );
        }

        updateWorkOrders(toUpdate);
    }

    private static Boolean isEligibleParentWorkOrder(WorkOrder workOrder) {
        if (workOrder == null || workOrder.ParentWorkOrderId != null) {
            return false;
        }
        if (String.isBlank(workOrder.CustomerPO__c)) {
            return false;
        }
        String recordTypeDeveloperName = workOrder.RecordType != null
            ? workOrder.RecordType.DeveloperName
            : null;
        return REPAIR_CENTER_RECORD_TYPE_DEVELOPER_NAMES.contains(recordTypeDeveloperName);
    }

    private static Boolean isPoRequiredChildWithCustomerPo(WorkOrder workOrder) {
        if (workOrder == null || workOrder.ParentWorkOrderId == null) {
            return false;
        }
        if (String.isBlank(workOrder.CustomerPO__c)) {
            return false;
        }
        if (workOrder.SubStatus__c != SUB_STATUS_PO_REQUIRED) {
            return false;
        }
        String recordTypeDeveloperName = workOrder.RecordType != null
            ? workOrder.RecordType.DeveloperName
            : null;
        return REPAIR_CENTER_RECORD_TYPE_DEVELOPER_NAMES.contains(recordTypeDeveloperName);
    }

    private static Set<Id> parentsWithAttachment(Set<Id> parentIds) {
        Set<Id> result = new Set<Id>();
        if (parentIds == null || parentIds.isEmpty()) {
            return result;
        }

        for (ContentDocumentLink link : [
            SELECT LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :parentIds
            WITH USER_MODE
        ]) {
            if (link.LinkedEntityId != null) {
                result.add(link.LinkedEntityId);
            }
        }
        return result;
    }

    private static void updateWorkOrders(List<WorkOrder> workOrders) {
        if (workOrders == null || workOrders.isEmpty()) {
            return;
        }
        WorkOrdersService.updateWorkOrders(workOrders);
    }

    /**
     * @description GW-5830 - Loads Work Orders needed for PO Required advancement.
     *              Uses USER_MODE. Kept in this functional service so WorkOrdersSelector
     *              is not extended for this story.
     */
    private static List<WorkOrder> queryWorkOrdersById(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new List<WorkOrder>();
        }
        return [
            SELECT
                Id,
                CustomerPO__c,
                ParentWorkOrderId,
                Status,
                SubStatus__c,
                RecordType.DeveloperName
            FROM WorkOrder
            WHERE Id IN :workOrderIds
            WITH USER_MODE
        ];
    }

    /**
     * @description GW-5830 - Loads PO Required children for the given parent Ids.
     */
    private static List<WorkOrder> queryPoRequiredChildren(Set<Id> parentWorkOrderIds) {
        if (parentWorkOrderIds == null || parentWorkOrderIds.isEmpty()) {
            return new List<WorkOrder>();
        }
        return [
            SELECT Id, ParentWorkOrderId, SubStatus__c, Status
            FROM WorkOrder
            WHERE
                ParentWorkOrderId IN :parentWorkOrderIds
                AND SubStatus__c = :SUB_STATUS_PO_REQUIRED
            WITH USER_MODE
        ];
    }
}