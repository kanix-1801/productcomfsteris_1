/**
 * @description Controller for the Cancel Return Order LWC (GW-1203).
 */
public with sharing class CancelReturnOrderController {

    private static final String STATUS_CREATED = 'Created';
    private static final String STATUS_RECEIVED = 'Received';
    private static final String STATUS_CANCELED = 'Canceled';
    private static final String STATUS_CLOSED = 'Closed';
    private static final String ROLI_STATUS_CANCELED = 'Canceled';

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    public class CancelContext {
        @AuraEnabled public String returnOrderId;
        @AuraEnabled public String returnOrderNumber;
        @AuraEnabled public String status;
        @AuraEnabled public Integer woCount;
        @AuraEnabled public Boolean canCancel;
        @AuraEnabled public String blockReason;
        @AuraEnabled public List<PicklistOption> cancelReasonOptions;
    }

    public class CancelResult {
        @AuraEnabled public String returnOrderId;
        @AuraEnabled public String status;
    }

    @AuraEnabled(cacheable=true)
    public static CancelContext getCancelContext(Id returnOrderId) {
        if (returnOrderId == null) {
            throw new AuraHandledException('Return Order Id is required.');
        }

        try {
            ReturnOrder returnOrder = [
                SELECT Id, ReturnOrderNumber, Status, WOCount__c
                FROM ReturnOrder
                WHERE Id = :returnOrderId
                WITH USER_MODE
                LIMIT 1
            ];

            CancelContext context = new CancelContext();
            context.returnOrderId = returnOrder.Id;
            context.returnOrderNumber = returnOrder.ReturnOrderNumber;
            context.status = returnOrder.Status;
            context.woCount = returnOrder.WOCount__c == null
                ? 0
                : Integer.valueOf(returnOrder.WOCount__c);
            context.cancelReasonOptions = getCancelReasonOptions();
            resolveCancelEligibility(returnOrder, context);
            return context;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(
                'Unable to load cancel context: ' + e.getMessage()
            );
        }
    }

    @AuraEnabled
    public static CancelResult cancelReturnOrder(
        Id returnOrderId,
        String cancelReason,
        String cancelReasonNotes
    ) {
        if (returnOrderId == null) {
            throw new AuraHandledException('Return Order Id is required.');
        }
        if (String.isBlank(cancelReason)) {
            throw new AuraHandledException(
                'Cancel Reason is required when canceling a Return Order.'
            );
        }

        try {
            ReturnOrder returnOrder = [
                SELECT Id, Status, WOCount__c
                FROM ReturnOrder
                WHERE Id = :returnOrderId
                WITH USER_MODE
                FOR UPDATE
            ];

            CancelContext eligibility = new CancelContext();
            resolveCancelEligibility(returnOrder, eligibility);
            if (!eligibility.canCancel) {
                throw new AuraHandledException(
                    eligibility.blockReason != null
                        ? eligibility.blockReason
                        : 'This Return Order cannot be canceled.'
                );
            }

            returnOrder.Status = STATUS_CANCELED;
            returnOrder.CancelReason__c = cancelReason;
            returnOrder.CancelReasonNotes__c = cancelReasonNotes;

            List<ReturnOrder> updatableReturnOrders = Security.stripInaccessible(
                AccessType.UPDATABLE,
                new List<ReturnOrder>{ returnOrder }
            ).getRecords();
            if (updatableReturnOrders.isEmpty()) {
                throw new AuraHandledException(
                    'Unable to cancel Return Order due to field access restrictions.'
                );
            }
            update as user updatableReturnOrders;

            cancelOpenLineItems(returnOrderId);

            CancelResult result = new CancelResult();
            result.returnOrderId = returnOrderId;
            result.status = STATUS_CANCELED;
            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException(
                'Unable to cancel Return Order: ' + e.getMessage()
            );
        }
    }

    private static void resolveCancelEligibility(
        ReturnOrder returnOrder,
        CancelContext context
    ) {
        context.canCancel = true;
        context.blockReason = null;

        if (returnOrder.Status == STATUS_CANCELED) {
            context.canCancel = false;
            context.blockReason = 'This Return Order is already canceled.';
            return;
        }
        if (returnOrder.Status == STATUS_CLOSED) {
            context.canCancel = false;
            context.blockReason = 'Closed Return Orders cannot be canceled.';
            return;
        }
        if (returnOrder.Status == STATUS_RECEIVED) {
            context.canCancel = false;
            context.blockReason =
                'This Return Order has been received and cannot be canceled.';
            return;
        }
        if (returnOrder.WOCount__c != null && returnOrder.WOCount__c > 0) {
            context.canCancel = false;
            context.blockReason =
                'This Return Order cannot be canceled because a Work Order has already been created.';
            return;
        }

        Integer receivedLineCount = [
            SELECT COUNT()
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrder.Id
            AND Status__c = :STATUS_RECEIVED
            WITH USER_MODE
        ];
        if (receivedLineCount > 0) {
            context.canCancel = false;
            context.blockReason =
                'This Return Order cannot be canceled because one or more line items have been received.';
        }
    }

    private static void cancelOpenLineItems(Id returnOrderId) {
        List<ReturnOrderLineItem> openLineItems = [
            SELECT Id, Status__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrderId
            AND Status__c = :STATUS_CREATED
            WITH USER_MODE
        ];
        if (openLineItems.isEmpty()) {
            return;
        }

        for (ReturnOrderLineItem lineItem : openLineItems) {
            lineItem.Status__c = ROLI_STATUS_CANCELED;
        }

        List<ReturnOrderLineItem> updatableLineItems = Security.stripInaccessible(
            AccessType.UPDATABLE,
            openLineItems
        ).getRecords();
        if (!updatableLineItems.isEmpty()) {
            update as user updatableLineItems;
        }
    }

    private static List<PicklistOption> getCancelReasonOptions() {
        List<PicklistOption> options = new List<PicklistOption>();
        for (
            Schema.PicklistEntry entry :
            ReturnOrder.CancelReason__c.getDescribe().getPicklistValues()
        ) {
            if (!entry.isActive()) {
                continue;
            }
            PicklistOption option = new PicklistOption();
            option.label = entry.getLabel();
            option.value = entry.getValue();
            options.add(option);
        }
        return options;
    }
}