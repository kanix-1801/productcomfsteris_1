/**
 * @author Uptima Development Team
 * @date 2026-07-15
 * @description LWC controller entry point for Work Order debrief Allowed Unit evaluation.
 *              Delegates business logic to WorkOrderLineItemsService.
 * @group Work Order Debrief
 * @see WorkOrderLineItemsService
 * @see woDebriefES
 * @see woDebriefIMSchildWO
 */
public with sharing class WoDebriefAllowedUnitController {
    /**
     * @description Evaluates Allowed Unit for a Product Item on a Work Order.
     * @param workOrderId Work Order Id
     * @param productItemId Selected Product Item Id
     * @return Allowed Unit evaluation DTO
     */
    @AuraEnabled(cacheable=true)
    public static AllowedUnitEvaluationDTO evaluateAllowedUnit(Id workOrderId, Id productItemId) {
        try {
            return WorkOrderLineItemsService.evaluateAllowedUnit(workOrderId, productItemId);
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            // Service wraps query/unexpected failures; surface message to the LWC.
            Logger.error('WoDebriefAllowedUnitController.evaluateAllowedUnit failed', e);
            throw new AuraHandledException(e.getMessage());
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-4311 - Evaluates Allowed Unit for a Product2 (Customer Stock) on a Work Order.
     * @param workOrderId Work Order Id
     * @param product2Id Selected Product2 Id
     * @return Allowed Unit evaluation DTO
     */
    @AuraEnabled(cacheable=true)
    public static AllowedUnitEvaluationDTO evaluateAllowedUnitByProduct(Id workOrderId, Id product2Id) {
        try {
            return WorkOrderLineItemsService.evaluateAllowedUnitByProduct(workOrderId, product2Id);
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            Logger.error('WoDebriefAllowedUnitController.evaluateAllowedUnitByProduct failed', e);
            throw new AuraHandledException(e.getMessage());
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Service Code options for a Device Type / part product. Delegates to
     *              WoDebriefIMSchildWOController so Field Service users can call an Apex class
     *              they already have access to.
     * @param product2Id Device Type or part Product2 Id
     * @return Base service code and matching Service Code options
     */
    @AuraEnabled
    public static WoDebriefIMSchildWOController.RepairCodesForProductResult getRepairCodesForProduct(Id product2Id) {
        return WoDebriefIMSchildWOController.getRepairCodesForProduct(product2Id);
    }

    /**
     * @description Pricebook entry for a Device Type product on the Work Order pricebook.
     * @param workOrderId Work Order Id
     * @param product2Id Device Type Product2 Id
     * @return PricebookEntry Id, or null when no matching entry exists
     */
    @AuraEnabled
    public static Id resolvePricebookEntryId(Id workOrderId, Id product2Id) {
        if (workOrderId == null || product2Id == null) {
            return null;
        }

        List<WorkOrder> workOrders = [
            SELECT Pricebook2Id, CurrencyIsoCode
            FROM WorkOrder
            WHERE Id = :workOrderId
            LIMIT 1
        ];
        if (workOrders.isEmpty() || workOrders[0].Pricebook2Id == null) {
            return null;
        }

        String currencyIso = String.isNotBlank(workOrders[0].CurrencyIsoCode)
            ? workOrders[0].CurrencyIsoCode
            : UserInfo.getDefaultCurrency();

        List<PricebookEntry> entries = [
            SELECT Id
            FROM PricebookEntry
            WHERE Pricebook2Id = :workOrders[0].Pricebook2Id
                AND Product2Id = :product2Id
                AND IsActive = true
                AND CurrencyIsoCode = :currencyIso
            LIMIT 1
        ];
        return entries.isEmpty() ? null : entries[0].Id;
    }

    /**
     * @description GW-1738 / GW-2001: Billing Type for a Product2 on a Work Order.
     * @param workOrderId Current Work Order Id
     * @param product2Id Selected Product2 Id
     * @return Billable or SVC Warranty
     */
    @AuraEnabled(cacheable=true)
    public static String evaluateBillingType(Id workOrderId, Id product2Id) {
        try {
            return WorkOrderLineItemsService.evaluateBillingType(workOrderId, product2Id);
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            Logger.error('WoDebriefAllowedUnitController.evaluateBillingType failed', e);
            throw new AuraHandledException(e.getMessage());
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-1738 / GW-2001: Billing Type for a Product Item on a Work Order.
     * @param workOrderId Current Work Order Id
     * @param productItemId Selected Product Item Id
     * @return Billable or SVC Warranty
     */
    @AuraEnabled(cacheable=true)
    public static String evaluateBillingTypeForProductItem(Id workOrderId, Id productItemId) {
        try {
            return WorkOrderLineItemsService.evaluateBillingTypeForProductItem(workOrderId, productItemId);
        } catch (WorkOrderLineItemsService.WorkOrderLineItemsServiceException e) {
            Logger.error('WoDebriefAllowedUnitController.evaluateBillingTypeForProductItem failed', e);
            throw new AuraHandledException(e.getMessage());
        } finally {
            Logger.saveLog();
        }
    }
}