/**
 * @description GW-5492 - Thin Aura controller for the Receiving LWC.
 */
public with sharing class ReceivingController {
    /**
     * @description Resolves Scan Order input to a receivable Return Order.
     * @param scanInput Salesforce Id or order number
     * @return Scan resolve DTO
     */
    @AuraEnabled
    public static ReceivingService.ScanResolveResult resolveScanInput(String scanInput) {
        try {
            return ReceivingService.resolveScanInput(scanInput);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Loads Receiving shell context for a Return Order.
     * @param returnOrderId Return Order Id
     * @return Shell context DTO
     */
    @AuraEnabled
    public static ReceivingService.ReceivingShellContext getReceivingShellContext(
        Id returnOrderId
    ) {
        try {
            return ReceivingService.getReceivingShellContext(returnOrderId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description GW-5968 - Saves Quantity Received from Scan Work Order verification.
     * @param workOrderId Work Order Id
     * @param quantityReceived Quantity entered on the verification screen
     */
    @AuraEnabled
    public static void saveWorkOrderQuantityReceived(Id workOrderId, Decimal quantityReceived) {
        try {
            ReceivingService.saveWorkOrderQuantityReceived(workOrderId, quantityReceived);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description GW-5968 - Loads Receiving shell context for a Work Order.
     * @param workOrderId Work Order Id
     * @return Shell context DTO
     */
    @AuraEnabled
    public static ReceivingService.ReceivingShellContext getWorkOrderReceivingShellContext(
        Id workOrderId
    ) {
        try {
            return ReceivingService.getWorkOrderReceivingShellContext(workOrderId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description GW-5968 - Submits Vendor Work Order receiving verification.
     * @param workOrderId Vendor Work Order Id
     */
    @AuraEnabled
    public static void submitVendorWorkOrderReceiving(Id workOrderId) {
        try {
            ReceivingService.submitVendorWorkOrderReceiving(workOrderId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Repair Center locations for Redirect (Location Name labels).
     * @return Picklist options
     */
    @AuraEnabled(cacheable=true)
    public static List<ReceivingService.PicklistOption> getRepairCenterOptions() {
        try {
            return ReceivingService.getRepairCenterOptions();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description GW-4348 / GW-5996 - Whether Create New Order is visible for the user.
     * @return true when the user's Repair Center Service Resource is eligible
     */
    @AuraEnabled(cacheable=true)
    public static Boolean canCreateNewOrder() {
        try {
            return ReceivingService.canCreateNewOrder();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Internal Accounts for Internal Repair (Account.Type = I).
     * @return Picklist options
     */
    @AuraEnabled(cacheable=true)
    public static List<ReceivingService.PicklistOption> getInternalAccountOptions() {
        try {
            return ReceivingService.getInternalAccountOptions();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Vendor Accounts for Outside Vendor (Account.Type = Vendor).
     * @return Picklist options
     */
    @AuraEnabled(cacheable=true)
    public static List<ReceivingService.PicklistOption> getVendorAccountOptions() {
        try {
            return ReceivingService.getVendorAccountOptions();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Stages a Mod Form photo on the Return Order.
     * @param returnOrderId Return Order Id
     * @param base64Data File payload
     * @param fileName Optional file name
     * @return Mod Form photo DTO
     */
    @AuraEnabled
    public static ReceivingService.ModFormPhoto stageModFormPhoto(
        Id returnOrderId,
        String base64Data,
        String fileName
    ) {
        try {
            return ReceivingService.stageModFormPhoto(returnOrderId, base64Data, fileName);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Removes a Mod Form photo from the Return Order.
     * @param returnOrderId Return Order Id
     * @param contentDocumentId ContentDocument Id
     */
    @AuraEnabled
    public static void deleteModFormPhoto(Id returnOrderId, Id contentDocumentId) {
        try {
            ReceivingService.deleteModFormPhoto(returnOrderId, contentDocumentId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Renames a Mod Form photo on the Return Order.
     * @param returnOrderId Return Order Id
     * @param contentDocumentId ContentDocument Id
     * @param newTitle New title
     * @return Updated Mod Form photo DTO
     */
    @AuraEnabled
    public static ReceivingService.ModFormPhoto renameModFormPhoto(
        Id returnOrderId,
        Id contentDocumentId,
        String newTitle
    ) {
        try {
            return ReceivingService.renameModFormPhoto(returnOrderId, contentDocumentId, newTitle);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Links staged Take a Pic files to a scanned Work Order.
     * @param workOrderId Work Order Id
     * @param contentDocumentIds Staged photo ContentDocument Ids
     */
    @AuraEnabled
    public static void attachReceivingPhotos(Id workOrderId, List<Id> contentDocumentIds) {
        try {
            ReceivingService.attachReceivingPhotos(workOrderId, contentDocumentIds);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Stages a Take a Pic file for Finish Receiving. Does not link the file.
     * @param base64Data File payload
     * @param fileName Optional file name
     * @return Staged photo DTO
     */
    @AuraEnabled
    public static ReceivingService.ModFormPhoto stageReceivingPhoto(
        String base64Data,
        String fileName
    ) {
        try {
            return ReceivingService.stageReceivingPhoto(base64Data, fileName);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Deletes a staged Take a Pic file that is not yet linked to a record.
     * @param contentDocumentId ContentDocument Id
     */
    @AuraEnabled
    public static void deleteReceivingPhoto(Id contentDocumentId) {
        try {
            ReceivingService.deleteReceivingPhoto(contentDocumentId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Renames a staged Take a Pic file.
     * @param contentDocumentId ContentDocument Id
     * @param newTitle New title
     * @return Updated photo DTO
     */
    @AuraEnabled
    public static ReceivingService.ModFormPhoto renameReceivingPhoto(
        Id contentDocumentId,
        String newTitle
    ) {
        try {
            return ReceivingService.renameReceivingPhoto(contentDocumentId, newTitle);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Applies a serial override of 2 characters or fewer.
     * @param lineItemId Return Order Line Item Id
     * @param correctedSerial Corrected serial number
     * @return Whether the line and Asset were updated
     */
    @AuraEnabled
    public static ReceivingService.OverrideSerialResult applySerialOverride(
        Id lineItemId,
        String correctedSerial
    ) {
        try {
            return ReceivingService.applySerialOverride(lineItemId, correctedSerial);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description GW-5968 - Applies a serial override of 2 characters or fewer on a
     *              Work Order Product Serviced line.
     * @param workOrderLineItemId Product Serviced Work Order Line Item Id
     * @param correctedSerial Corrected serial number
     * @param correctedModel Corrected model
     * @param customerCareReasonCodes Reason codes selected on the override
     * @param customerCareNotes Customer Care notes
     * @return Whether the line and Asset were updated
     */
    @AuraEnabled
    public static ReceivingService.OverrideSerialResult applyWorkOrderSerialOverride(
        Id workOrderLineItemId,
        String correctedSerial,
        String correctedModel,
        List<String> customerCareReasonCodes,
        String customerCareNotes
    ) {
        try {
            return ReceivingService.applyWorkOrderSerialOverride(
                workOrderLineItemId,
                correctedSerial,
                correctedModel,
                customerCareReasonCodes,
                customerCareNotes
            );
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description GW-5968 - Rerun Resi-Test action for a Repair Center Work Order.
     * @param workOrderId Scanned Work Order Id
     * @param workOrderLineItemId Product Serviced Work Order Line Item Id
     * @param resiTestPerformed Whether a Resi-Test was performed
     * @param disinfectedUiValue Clean / Contaminated
     * @param quantityReceived Disinfection line quantity
     * @param customerCareReasonCodes Reason codes flagged in this Receiving session
     * @return Created Resi-Test History / Disinfection line Ids
     */
    @AuraEnabled
    public static ReceivingService.RerunResiTestResult submitWorkOrderRerunResiTest(
        Id workOrderId,
        Id workOrderLineItemId,
        Boolean resiTestPerformed,
        String disinfectedUiValue,
        Decimal quantityReceived,
        List<String> customerCareReasonCodes
    ) {
        try {
            return ReceivingService.submitWorkOrderRerunResiTest(
                workOrderId,
                workOrderLineItemId,
                resiTestPerformed,
                disinfectedUiValue,
                quantityReceived,
                customerCareReasonCodes
            );
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description GW-5968 - Re-print Travel Tag / Bin Tag for a scanned Work Order.
     * @param workOrderId Scanned Work Order Id
     * @return Success message for the LWC toast
     */
    @AuraEnabled
    public static String reprintWorkOrderTravelTag(Id workOrderId) {
        try {
            return ReceivingService.reprintWorkOrderTravelTag(workOrderId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description GW-5492 - Finish Receiving for one item from the Actions menu.
     *              Accepts JSON so LWC nested DTO fields bind reliably (typed inner-class
     *              Aura params can arrive null without getters/setters / under LWS).
     * @param requestJson Serialized ReceivingService.FinishReceivingRequest
     * @return Finish result for badges and navigation
     */
    @AuraEnabled
    public static ReceivingService.FinishReceivingResult finishReceivingItem(String requestJson) {
        try {
            if (String.isBlank(requestJson)) {
                throw new AuraHandledException('Return Order is required.');
            }
            ReceivingService.FinishReceivingRequest request =
                (ReceivingService.FinishReceivingRequest) JSON.deserialize(
                    requestJson,
                    ReceivingService.FinishReceivingRequest.class
                );
            return ReceivingService.finishReceivingItem(request);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description GW-4348 / GW-5996 - Build Create Order review groups (PL / PO / Ship-To).
     * @param headerJson Account header JSON
     * @param itemsJson Serialized items JSON
     * @return Proposed order groups
     */
    @AuraEnabled
    public static List<ReceivingService.CreateOrderGroup> buildCreateOrderPlan(
        String headerJson,
        String itemsJson
    ) {
        try {
            return ReceivingService.buildCreateOrderPlan(headerJson, itemsJson);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description GW-4348 / GW-5996 - Create Return Orders from Create Order review.
     *              Call createWorkOrdersForCreateOrder once per RO afterward.
     * @param headerJson Account header JSON
     * @param itemsJson Serialized items JSON
     * @return Submit result with Return Order Ids
     */
    @AuraEnabled
    public static ReceivingService.CreateOrderSubmitResult submitCreateOrder(
        String headerJson,
        String itemsJson
    ) {
        try {
            return ReceivingService.submitCreateOrder(headerJson, itemsJson);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description GW-4348 / GW-5996 - Create Receiving WOs for one Create Order Return Order.
     * @param returnOrderId Return Order Id
     * @return Created parent Work Order Id and number
     */
    @AuraEnabled
    public static ReceivingService.CreateOrderCreatedWorkOrder createWorkOrdersForCreateOrder(
        Id returnOrderId
    ) {
        try {
            return ReceivingService.createWorkOrdersForCreateOrder(returnOrderId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}