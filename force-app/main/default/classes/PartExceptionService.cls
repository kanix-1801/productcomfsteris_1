/**
 * @description GW-3329: Part exception checks and Customer Care case creation.
 * @group Work Order Debrief
 * @see woDebriefES
 */
public with sharing class PartExceptionService {
    public static final String STATUS_IN_APPROVALS = 'In Approvals';
    public static final String STATUS_APPROVED = 'Approved';
    public static final String STATUS_REJECTED = 'Rejected';
    public static final String MESSAGE_REJECTED =
        'This part has already been reviewed by Service Engineering and has been denied to be used on this equipment.';
    public static final String MESSAGE_IN_APPROVALS =
        'This part is already in approvals. You cannot add it until the current request is completed.';
    private static final String CASE_RECORD_TYPE_INBOX_SUPPORT = 'InboxSupport';
    private static final String CUSTOMER_CARE_QUEUE_DEVELOPER_NAME = 'QNAIMSCustCareCentralSupport';
    private static final String CASE_STATUS_NEW = 'New';
    private static final String CASE_ORIGIN_CENTRAL_REPAIR_SUPPORT = 'Central Repair Support';

    /**
     * @description Reads the Product Item approval status before a new exception can be saved.
     * @param productItemId Selected Product Item Id
     * @return Whether the part can be requested, and whether it was already approved
     */
    @AuraEnabled
    public static PartExceptionCheck checkProductItemApproval(Id productItemId) {
        try {
            return evaluateProductItem(productItemId);
        } catch (Exception e) {
            Logger.error('PartExceptionService.checkProductItemApproval failed', e);
            throw new AuraHandledException(e.getMessage());
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Creates the Inbox case for a saved part exception and marks the Product Item In Approvals.
     * @param workOrderLineItemId Work order line item that requested the part
     * @return Case Id
     */
    @AuraEnabled
    public static Id submitPartException(Id workOrderLineItemId) {
        try {
            if (workOrderLineItemId == null) {
                throw new AuraHandledException('Work order line item is required.');
            }
            List<WorkOrderLineItem> visibleLines = [
                SELECT Id
                FROM WorkOrderLineItem
                WHERE Id = :workOrderLineItemId
                WITH USER_MODE
                LIMIT 1
            ];
            if (visibleLines.isEmpty()) {
                throw new AuraHandledException('Work order line item was not found.');
            }
            return new PartExceptionCaseCreator().create(workOrderLineItemId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (DmlException e) {
            Logger.error('PartExceptionService.submitPartException failed', e);
            String detail = e.getMessage();
            if (e.getNumDml() > 0) {
                detail += ' Fields: ' + String.valueOf(e.getDmlFields(0));
            }
            AuraHandledException handled = new AuraHandledException(detail);
            handled.setMessage(detail);
            throw handled;
        } catch (Exception e) {
            Logger.error('PartExceptionService.submitPartException failed', e);
            String detail = e.getMessage();
            AuraHandledException handled = new AuraHandledException(detail);
            handled.setMessage(detail);
            throw handled;
        } finally {
            Logger.saveLog();
        }
    }

    private static PartExceptionCheck evaluateProductItem(Id productItemId) {
        PartExceptionCheck result = new PartExceptionCheck();
        result.allowed = true;
        result.alreadyApproved = false;
        if (productItemId == null) {
            return result;
        }

        List<ProductItem> items = [
            SELECT Id, ApprovalStatus__c
            FROM ProductItem
            WHERE Id = :productItemId
            WITH USER_MODE
            LIMIT 1
        ];
        if (items.isEmpty()) {
            return result;
        }

        String status = items[0].ApprovalStatus__c;
        result.status = status;
        if (status == STATUS_REJECTED) {
            result.allowed = false;
            result.message = MESSAGE_REJECTED;
        } else if (status == STATUS_IN_APPROVALS) {
            result.allowed = false;
            result.message = MESSAGE_IN_APPROVALS;
        } else if (status == STATUS_APPROVED) {
            result.alreadyApproved = true;
        }
        return result;
    }

    /**
     * @description LWC result for the Product Item approval check.
     */
    public class PartExceptionCheck {
        /** @description False when the part is rejected or already in approvals. */
        @AuraEnabled public Boolean allowed;
        /** @description True when this Product Item was already approved. */
        @AuraEnabled public Boolean alreadyApproved;
        /** @description Current Product Item approval status. */
        @AuraEnabled public String status;
        /** @description Message shown when the part cannot be saved. */
        @AuraEnabled public String message;
    }

    /**
     * @description Creates the case and sends the rejection notice without relying on technician case access.
     */
    private without sharing class PartExceptionCaseCreator {
        Id create(Id workOrderLineItemId) {
            List<Case> existingCases = [
                SELECT Id
                FROM Case
                WHERE WorkOrderLineItem__c = :workOrderLineItemId
                LIMIT 1
            ];
            if (!existingCases.isEmpty()) {
                markProductItemInApprovals(workOrderLineItemId);
                return existingCases[0].Id;
            }

            WorkOrderLineItem line = queryLine(workOrderLineItemId);
            markProductItemInApprovals(line);

            Case partExceptionCase = new Case();
            partExceptionCase.RecordTypeId = resolveInboxSupportRecordTypeId();
            partExceptionCase.OwnerId = resolveCustomerCareQueueId();
            partExceptionCase.BusinessHoursId = resolveDefaultBusinessHoursId();
            partExceptionCase.AccountId = line.WorkOrder.AccountId;
            partExceptionCase.ContactId = line.WorkOrder.ContactId;
            partExceptionCase.AssetId = line.WorkOrder.AssetId;
            partExceptionCase.WorkOrderLineItem__c = line.Id;
            partExceptionCase.Status = CASE_STATUS_NEW;
            partExceptionCase.Origin = CASE_ORIGIN_CENTRAL_REPAIR_SUPPORT;
            partExceptionCase.Subject = buildSubject(line);
            partExceptionCase.Description = buildDescription(line);
            Database.insert(partExceptionCase, AccessLevel.SYSTEM_MODE);
            return partExceptionCase.Id;
        }

        private void markProductItemInApprovals(Id workOrderLineItemId) {
            WorkOrderLineItem line = queryLine(workOrderLineItemId);
            markProductItemInApprovals(line);
        }

        private void markProductItemInApprovals(WorkOrderLineItem line) {
            if (line.ProductItem__c == null) {
                return;
            }
            List<ProductItem> items = [
                SELECT Id, ApprovalStatus__c
                FROM ProductItem
                WHERE Id = :line.ProductItem__c
                LIMIT 1
            ];
            if (items.isEmpty() || String.isNotBlank(items[0].ApprovalStatus__c)) {
                return;
            }
            items[0].ApprovalStatus__c = STATUS_IN_APPROVALS;
            Database.update(items[0], AccessLevel.SYSTEM_MODE);
        }

        private WorkOrderLineItem queryLine(Id workOrderLineItemId) {
            List<WorkOrderLineItem> lines = [
                SELECT
                    Id,
                    LineItemNumber,
                    WorkOrderId,
                    ProductItem__c,
                    NonApprovedPartResponse__c,
                    PartExceptionReason__c,
                    Product__r.Name,
                    ProductItem__r.Product2.Name,
                    WorkOrder.WorkOrderNumber,
                    WorkOrder.AccountId,
                    WorkOrder.ContactId,
                    WorkOrder.AssetId,
                    WorkOrder.Asset.Name,
                    AssignedResource__r.RelatedRecord.Name,
                    CreatedBy.Name
                FROM WorkOrderLineItem
                WHERE Id = :workOrderLineItemId
                LIMIT 1
            ];
            if (lines.isEmpty()) {
                throw new AuraHandledException('Work order line item was not found.');
            }
            return lines[0];
        }

        private String buildSubject(WorkOrderLineItem line) {
            String workOrderLabel = String.isNotBlank(line.WorkOrder.WorkOrderNumber)
                ? line.WorkOrder.WorkOrderNumber
                : String.valueOf(line.WorkOrderId);
            return 'Part exception - ' + workOrderLabel;
        }

        private String buildDescription(WorkOrderLineItem line) {
            String lineLabel = String.isNotBlank(line.LineItemNumber)
                ? line.LineItemNumber
                : String.valueOf(line.Id);
            String lineUrl = Url.getOrgDomainUrl().toExternalForm()
                + '/lightning/r/WorkOrderLineItem/'
                + line.Id
                + '/view';
            String productName = line.Product__r == null ? null : line.Product__r.Name;
            if (String.isBlank(productName)
                && line.ProductItem__r != null
                && line.ProductItem__r.Product2 != null) {
                productName = line.ProductItem__r.Product2.Name;
            }
            String technicianName = line.CreatedBy.Name;
            if (line.AssignedResource__r != null && line.AssignedResource__r.RelatedRecord != null) {
                technicianName = line.AssignedResource__r.RelatedRecord.Name;
            }

            List<String> descriptionLines = new List<String>{
                'A non-approved part was requested for this equipment.',
                'Work Order: ' + (String.isNotBlank(line.WorkOrder.WorkOrderNumber)
                    ? line.WorkOrder.WorkOrderNumber
                    : String.valueOf(line.WorkOrderId)),
                'Work Order Line Item: ' + lineLabel,
                'Open line item: ' + lineUrl
            };
            if (line.WorkOrder.Asset != null && String.isNotBlank(line.WorkOrder.Asset.Name)) {
                descriptionLines.add('Asset: ' + line.WorkOrder.Asset.Name);
            }
            if (String.isNotBlank(productName)) {
                descriptionLines.add('Product: ' + productName);
            }
            if (String.isNotBlank(technicianName)) {
                descriptionLines.add('Technician: ' + technicianName);
            }
            if (String.isNotBlank(line.PartExceptionReason__c)) {
                descriptionLines.add('Reason: ' + line.PartExceptionReason__c);
            }
            if (String.isNotBlank(line.NonApprovedPartResponse__c)) {
                descriptionLines.add('Response: ' + line.NonApprovedPartResponse__c);
            }
            return String.join(descriptionLines, '\n');
        }

        private Id resolveInboxSupportRecordTypeId() {
            List<RecordType> recordTypes = [
                SELECT Id
                FROM RecordType
                WHERE SobjectType = 'Case'
                AND DeveloperName = :CASE_RECORD_TYPE_INBOX_SUPPORT
                LIMIT 1
            ];
            if (recordTypes.isEmpty()) {
                throw new AuraHandledException(
                    'Unable to create the part exception case: Inbox Support record type was not found.'
                );
            }
            return recordTypes[0].Id;
        }

        private Id resolveCustomerCareQueueId() {
            List<Group> queues = [
                SELECT Id
                FROM Group
                WHERE Type = 'Queue'
                AND DeveloperName = :CUSTOMER_CARE_QUEUE_DEVELOPER_NAME
                LIMIT 1
            ];
            if (queues.isEmpty()) {
                throw new AuraHandledException(
                    'Unable to create the part exception case: Customer Care queue was not found.'
                );
            }
            return queues[0].Id;
        }

        private Id resolveDefaultBusinessHoursId() {
            List<BusinessHours> businessHours = [
                SELECT Id
                FROM BusinessHours
                WHERE IsDefault = TRUE
                LIMIT 1
            ];
            if (businessHours.isEmpty()) {
                throw new AuraHandledException(
                    'Unable to create the part exception case: default business hours were not found.'
                );
            }
            return businessHours[0].Id;
        }

    }
}