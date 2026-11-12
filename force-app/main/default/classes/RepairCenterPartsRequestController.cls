/**
 * @description GW-5981 - Aura entry point for Repair Center parts requests
 *              on Device Evaluation and Instrument Evaluation.
 */
public with sharing class RepairCenterPartsRequestController {
    /**
     * @description Active Part BOM components for the Work Order product.
     * @param workOrderId Work Order Id
     * @return Parts the technician can select
     */
    @AuraEnabled
    public static List<RepairCenterPartsRequestService.PartOption> getBomParts(Id workOrderId) {
        try {
            return RepairCenterPartsRequestService.getBomParts(workOrderId);
        } catch (Exception e) {
            throw auraException(e);
        }
    }

    /**
     * @description Resolves a scanned Product Code or Product Id.
     * @param scanValue Barcode or typed value
     * @return The matching product
     */
    @AuraEnabled
    public static RepairCenterPartsRequestService.PartOption findScannedPart(String scanValue) {
        try {
            return RepairCenterPartsRequestService.findScannedPart(scanValue);
        } catch (Exception e) {
            throw auraException(e);
        }
    }

    /**
     * @description Product Requests already linked to the Work Order.
     * @param workOrderId Work Order Id
     * @return Table rows
     */
    @AuraEnabled
    public static List<RepairCenterPartsRequestService.RequestRow> getProductRequests(Id workOrderId) {
        try {
            return RepairCenterPartsRequestService.getProductRequests(workOrderId);
        } catch (Exception e) {
            throw auraException(e);
        }
    }

    /**
     * @description Creates the Repair Center parts request and its line items.
     * @param workOrderId Work Order Id
     * @param lines Selected parts and quantities
     * @return The new Product Request
     */
    @AuraEnabled
    public static RepairCenterPartsRequestService.CreateResult createPartsRequest(
        Id workOrderId,
        List<RepairCenterPartsRequestService.PartLineInput> lines
    ) {
        try {
            return RepairCenterPartsRequestService.createPartsRequest(workOrderId, lines);
        } catch (Exception e) {
            throw auraException(e);
        }
    }

    @TestVisible
    private static AuraHandledException auraException(Exception e) {
        String message = e instanceof RepairCenterPartsRequestService.RepairCenterPartsRequestException
            ? e.getMessage()
            : 'Unable to complete the parts request. Please try again.';
        AuraHandledException auraError = new AuraHandledException(message);
        auraError.setMessage(message);
        return auraError;
    }
}