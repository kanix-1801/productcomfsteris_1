/**
 * @description Service for Repair Center Team Member signatures on Device Evaluation Work Performed.
 */
public with sharing class RepairCenterTeamMembersService {
    private static final String RECORD_TYPE_REPAIR_CENTER = 'RepairCenter';
    private static final String TYPE_WORK_ORDER_LINE = 'Work Order Line';

    public class RepairCenterTeamMembersServiceException extends Exception {
    }

    /**
     * @description Signatures for the Work Order, newest last.
     */
    public static List<RepairCenterTeamMember__c> getWorkOrderLineSignatures(Id workOrderId) {
        return RepairCenterTeamMembersSelector.selectWorkOrderLineSignatures(workOrderId);
    }

    /**
     * @description Adds the current user as a signature on the Repair Code WOLI when not already present.
     */
    public static List<RepairCenterTeamMember__c> addSignature(Id workOrderId, Id productId) {
        if (workOrderId == null || productId == null) {
            throw new RepairCenterTeamMembersServiceException(
                'Work Order and repair code are required to sign.'
            );
        }
        WorkOrder workOrder = requireWorkOrder(workOrderId);
        WorkOrderLineItem lineItem = requireRepairCodeWoli(workOrder.Id, productId);
        if (!hasCurrentUserSignature(workOrder.Id, lineItem.Id)) {
            insert buildSignature(workOrder, lineItem);
            assignCurrentUserToLineItem(lineItem.Id);
        }
        return getWorkOrderLineSignatures(workOrder.Id);
    }

    /**
     * @description Signs every supplied repair-code Product that does not already include the current user.
     */
    public static List<RepairCenterTeamMember__c> signAll(Id workOrderId, List<Id> productIds) {
        if (workOrderId == null) {
            throw new RepairCenterTeamMembersServiceException('Work Order is required.');
        }
        if (productIds == null || productIds.isEmpty()) {
            return getWorkOrderLineSignatures(workOrderId);
        }

        WorkOrder workOrder = requireWorkOrder(workOrderId);
        Id repairCodeRtId = WorkOrderLineItemsService.getRepairCodeRecordTypeId();
        List<WorkOrderLineItem> lineItems =
            WorkOrderLineItemsService.getRepairCodeByWorkOrderAndProducts(
                workOrder.Id,
                repairCodeRtId,
                new Set<Id>(productIds)
            );
        Set<Id> alreadySignedWoliIds = currentUserSignedWoliIds(workOrder.Id);
        List<RepairCenterTeamMember__c> toInsert = new List<RepairCenterTeamMember__c>();
        List<WorkOrderLineItem> toAssign = new List<WorkOrderLineItem>();
        for (WorkOrderLineItem lineItem : lineItems) {
            if (alreadySignedWoliIds.contains(lineItem.Id)) {
                continue;
            }
            toInsert.add(buildSignature(workOrder, lineItem));
            toAssign.add(new WorkOrderLineItem(
                Id = lineItem.Id,
                AssignedResourceUser__c = UserInfo.getUserId()
            ));
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
        if (!toAssign.isEmpty()) {
            update toAssign;
        }
        return getWorkOrderLineSignatures(workOrderId);
    }

    /**
     * @description GW-3400 - Adds the current user as a signature on a specific Repair Code WOLI.
     *              Prefer this over productId when the same repair code can appear on multiple items.
     */
    public static List<RepairCenterTeamMember__c> addSignatureForLineItem(
        Id workOrderId,
        Id workOrderLineItemId
    ) {
        if (workOrderId == null || workOrderLineItemId == null) {
            throw new RepairCenterTeamMembersServiceException(
                'Work Order and repair code line are required to sign.'
            );
        }
        WorkOrder workOrder = requireWorkOrder(workOrderId);
        WorkOrderLineItem lineItem = requireRepairCodeWoliById(workOrder.Id, workOrderLineItemId);
        if (!hasCurrentUserSignature(workOrder.Id, lineItem.Id)) {
            insert buildSignature(workOrder, lineItem);
            assignCurrentUserToLineItem(lineItem.Id);
        }
        return getWorkOrderLineSignatures(workOrder.Id);
    }

    /**
     * @description GW-3400 - Signs every supplied Repair Code WOLI the current user has not signed.
     */
    public static List<RepairCenterTeamMember__c> signAllForLineItems(
        Id workOrderId,
        List<Id> workOrderLineItemIds
    ) {
        if (workOrderId == null) {
            throw new RepairCenterTeamMembersServiceException('Work Order is required.');
        }
        if (workOrderLineItemIds == null || workOrderLineItemIds.isEmpty()) {
            return getWorkOrderLineSignatures(workOrderId);
        }

        WorkOrder workOrder = requireWorkOrder(workOrderId);
        Id repairCodeRtId = WorkOrderLineItemsService.getRepairCodeRecordTypeId();
        List<WorkOrderLineItem> lineItems = [
            SELECT Id
            FROM WorkOrderLineItem
            WHERE Id IN :workOrderLineItemIds
                AND WorkOrderId = :workOrderId
                AND RecordTypeId = :repairCodeRtId
        ];
        Set<Id> alreadySignedWoliIds = currentUserSignedWoliIds(workOrder.Id);
        List<RepairCenterTeamMember__c> toInsert = new List<RepairCenterTeamMember__c>();
        List<WorkOrderLineItem> toAssign = new List<WorkOrderLineItem>();
        for (WorkOrderLineItem lineItem : lineItems) {
            if (alreadySignedWoliIds.contains(lineItem.Id)) {
                continue;
            }
            toInsert.add(buildSignature(workOrder, lineItem));
            toAssign.add(new WorkOrderLineItem(
                Id = lineItem.Id,
                AssignedResourceUser__c = UserInfo.getUserId()
            ));
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
        if (!toAssign.isEmpty()) {
            update toAssign;
        }
        return getWorkOrderLineSignatures(workOrderId);
    }

    /**
     * @description Deletes a signature record for the Work Order.
     */
    public static List<RepairCenterTeamMember__c> removeSignature(Id workOrderId, Id signatureId) {
        if (workOrderId == null || signatureId == null) {
            throw new RepairCenterTeamMembersServiceException(
                'Work Order and signature are required to remove a signature.'
            );
        }
        RepairCenterTeamMember__c signature =
            RepairCenterTeamMembersSelector.selectByIdForWorkOrder(signatureId, workOrderId);
        if (signature == null) {
            throw new RepairCenterTeamMembersServiceException(
                'Signature was not found for this Work Order.'
            );
        }
        if (signature.Person__c != UserInfo.getUserId()) {
            throw new RepairCenterTeamMembersServiceException(
                'You can only remove your own signature.'
            );
        }
        delete signature;
        return getWorkOrderLineSignatures(workOrderId);
    }

    private static WorkOrder requireWorkOrder(Id workOrderId) {
        List<WorkOrder> workOrders = [
            SELECT Id, ParentWorkOrderId
            FROM WorkOrder
            WHERE Id = :workOrderId
            LIMIT 1
        ];
        if (workOrders.isEmpty()) {
            throw new RepairCenterTeamMembersServiceException('Work Order was not found.');
        }
        return workOrders[0];
    }

    private static WorkOrderLineItem requireRepairCodeWoli(Id workOrderId, Id productId) {
        Id repairCodeRtId = WorkOrderLineItemsService.getRepairCodeRecordTypeId();
        List<WorkOrderLineItem> lineItems =
            WorkOrderLineItemsService.getRepairCodeByWorkOrderAndProducts(
                workOrderId,
                repairCodeRtId,
                new Set<Id>{ productId }
            );
        if (lineItems.isEmpty()) {
            throw new RepairCenterTeamMembersServiceException(
                'Save the evaluation before signing so a Repair Code line exists.'
            );
        }
        return lineItems[0];
    }

    private static WorkOrderLineItem requireRepairCodeWoliById(
        Id workOrderId,
        Id workOrderLineItemId
    ) {
        Id repairCodeRtId = WorkOrderLineItemsService.getRepairCodeRecordTypeId();
        List<WorkOrderLineItem> lineItems = [
            SELECT Id
            FROM WorkOrderLineItem
            WHERE Id = :workOrderLineItemId
                AND WorkOrderId = :workOrderId
                AND RecordTypeId = :repairCodeRtId
            LIMIT 1
        ];
        if (lineItems.isEmpty()) {
            throw new RepairCenterTeamMembersServiceException(
                'Repair Code line was not found for this Work Order.'
            );
        }
        return lineItems[0];
    }

    private static Boolean hasCurrentUserSignature(Id workOrderId, Id workOrderLineItemId) {
        return currentUserSignedWoliIds(workOrderId).contains(workOrderLineItemId);
    }

    private static Set<Id> currentUserSignedWoliIds(Id workOrderId) {
        Set<Id> signedIds = new Set<Id>();
        Id currentUserId = UserInfo.getUserId();
        for (RepairCenterTeamMember__c signature : getWorkOrderLineSignatures(workOrderId)) {
            if (signature.Person__c == currentUserId && signature.WorkOrderLineItem__c != null) {
                signedIds.add(signature.WorkOrderLineItem__c);
            }
        }
        return signedIds;
    }

    private static RepairCenterTeamMember__c buildSignature(
        WorkOrder workOrder,
        WorkOrderLineItem lineItem
    ) {
        RepairCenterTeamMember__c signature = new RepairCenterTeamMember__c();
        signature.Name = UserInfo.getName();
        signature.Person__c = UserInfo.getUserId();
        signature.WorkOrder__c = workOrder.Id;
        signature.ParentWorkOrder__c = workOrder.ParentWorkOrderId;
        signature.WorkOrderLineItem__c = lineItem.Id;
        signature.Type__c = TYPE_WORK_ORDER_LINE;
        signature.RecordTypeId = getRepairCenterRecordTypeId();
        return signature;
    }

    private static void assignCurrentUserToLineItem(Id workOrderLineItemId) {
        update new WorkOrderLineItem(
            Id = workOrderLineItemId,
            AssignedResourceUser__c = UserInfo.getUserId()
        );
    }

    private static Id getRepairCenterRecordTypeId() {
        Schema.RecordTypeInfo recordType = Schema.SObjectType.RepairCenterTeamMember__c.getRecordTypeInfosByDeveloperName()
            .get(RECORD_TYPE_REPAIR_CENTER);
        return recordType != null ? recordType.getRecordTypeId() : null;
    }
}