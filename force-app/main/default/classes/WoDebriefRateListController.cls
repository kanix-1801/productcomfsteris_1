/**
 * @description Retrieves the Rate List associated with a Work Order for ES debrief travel and labor pricing.
 * @group Work Order Debrief
 * @see woDebriefES
 */
public with sharing class WoDebriefRateListController {
    /**
     * @description Rate List price fields returned to the LWC.
     */
    public class RateListPrices {
        /** @description Rate List record Id. */
        @AuraEnabled public Id rateListId;
        /** @description Rate List Name. */
        @AuraEnabled public String name;
        /** @description Standard labor hourly rate. */
        @AuraEnabled public Decimal laborHour;
        /** @description Travel hourly (Actual Travel) rate. */
        @AuraEnabled public Decimal travelHour;
        /** @description Premium hourly rate. */
        @AuraEnabled public Decimal premiumRateHour;
        /** @description Extended overtime hourly rate. */
        @AuraEnabled public Decimal extendedOvertimeRatePerHour;
        /** @description Travel Zone 1 lump-sum price. */
        @AuraEnabled public Decimal travelZone1;
        /** @description Travel Zone 2 lump-sum price. */
        @AuraEnabled public Decimal travelZone2;
        /** @description Travel Zone 3 lump-sum price. */
        @AuraEnabled public Decimal travelZone3;
        /** @description Travel Zone 4 lump-sum price. */
        @AuraEnabled public Decimal travelZone4;
    }

    /**
     * @description Resolves the Rate List for a Work Order (WO Rate List, else Account Rate List).
     * @param workOrderId Work Order Id
     * @return Rate List prices, or null when none is assigned
     */
    @AuraEnabled(cacheable=true)
    public static RateListPrices getRateListForWorkOrder(Id workOrderId) {
        if (workOrderId == null) {
            return null;
        }

        List<WorkOrder> workOrders = WorkOrderSelector.selectByIdsForRateList(new Set<Id>{ workOrderId });
        if (workOrders.isEmpty()) {
            return null;
        }

        WorkOrder workOrder = workOrders[0];
        Id rateListId = workOrder.RateList__c != null
            ? workOrder.RateList__c
            : workOrder.Account?.RateList__c;
        if (rateListId == null) {
            return null;
        }

        List<RateList__c> rateLists = RateListSelector.selectByIdsForDebriefPricing(new Set<Id>{ rateListId });
        if (rateLists.isEmpty()) {
            return null;
        }

        RateList__c rateList = rateLists[0];
        RateListPrices dto = new RateListPrices();
        dto.rateListId = rateList.Id;
        dto.name = rateList.Name;
        dto.laborHour = rateList.LaborHour__c;
        dto.travelHour = rateList.TravelHour__c;
        dto.premiumRateHour = rateList.PremiumRateHour__c;
        dto.extendedOvertimeRatePerHour = rateList.ExtendedOvertimeRatePerHour__c;
        dto.travelZone1 = rateList.TravelZone1__c;
        dto.travelZone2 = rateList.TravelZone2__c;
        dto.travelZone3 = rateList.TravelZone3__c;
        dto.travelZone4 = rateList.TravelZone4__c;
        return dto;
    }
}