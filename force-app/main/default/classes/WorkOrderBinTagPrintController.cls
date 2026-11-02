/**
 * @description GW-4637 - Lightning action entry point that prints a Repair Center bin tag
 *              through PrinterService. Allowed on Repair Center - Instruments and
 *              Repair Center - Devices Work Orders.
 * @group GW-4637
 */
public with sharing class WorkOrderBinTagPrintController {
    private static final String DEVICES_RECORD_TYPE_NAME = 'Repair Center - Devices';
    private static final String INSTRUMENTS_RECORD_TYPE_NAME = 'Repair Center - Instruments';

    /**
     * @description Prints a Zebra bin tag for an eligible Repair Center Work Order.
     * @param workOrderId Work Order Id from the record page action
     * @return Success message for the Lightning action
     */
    @AuraEnabled
    public static String printBinTag(Id workOrderId) {
        try {
            validatePrintableWorkOrder(workOrderId);
            PrinterService.PrintLabelResult result = PrinterService.printBinTags(workOrderId);
            return 'Bin tag sent to printer ' + resolvePrintedPrinterName(result) + '.';
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw PlatformUtilities.buildAuraException(
                String.isBlank(e.getMessage()) ? 'Unable to print bin tag.' : e.getMessage()
            );
        }
    }

    private static void validatePrintableWorkOrder(Id workOrderId) {
        if (workOrderId == null) {
            throw PlatformUtilities.buildAuraException('Work Order Id is required.');
        }

        WorkOrder workOrder = (WorkOrder) new WorkOrdersSelector()
            .selectFields(new List<String>{ 'Id', 'RecordTypeId' })
            .whereEquals('Id', workOrderId)
            .first();
        if (workOrder == null) {
            throw PlatformUtilities.buildAuraException(
                'Work Order was not found or is not accessible.'
            );
        }

        String recordTypeName = resolveRecordTypeName(workOrder);
        if (
            recordTypeName != INSTRUMENTS_RECORD_TYPE_NAME &&
            recordTypeName != DEVICES_RECORD_TYPE_NAME
        ) {
            throw PlatformUtilities.buildAuraException(
                'Bin tags can only be printed for Repair Center - Instruments or Repair Center - Devices Work Orders.'
            );
        }
    }

    private static String resolveRecordTypeName(WorkOrder workOrder) {
        if (workOrder == null || workOrder.RecordTypeId == null) {
            return null;
        }
        Schema.RecordTypeInfo info = Schema.SObjectType.WorkOrder.getRecordTypeInfosById()
            .get(workOrder.RecordTypeId);
        return info == null ? null : info.getName();
    }

    private static String resolvePrintedPrinterName(PrinterService.PrintLabelResult result) {
        if (
            result != null &&
            result.request != null &&
            String.isNotBlank(result.request.PrinterName)
        ) {
            return result.request.PrinterName;
        }
        return 'the mapped travel-tag printer';
    }
}