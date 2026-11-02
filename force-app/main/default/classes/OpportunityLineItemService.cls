/**
 * @author PWC Developer
 * @date 2026/07/23
 *
 * @group Product Sub-Group Detail
 *
 * @description
 * GC-3129 - Derives Opportunity.ProductSubGroupDetailName__c from Opportunity Products and Quote Line Items
 * via Product2.PSAM__c and PSAM__c.ProductSubgroupDetailName__c. Applies to Capital and Consumables
 * Opportunities only; Instrument Processing is excluded.
 */
public with sharing class OpportunityLineItemService {
    public static final String SCENARIO = 'Opportunity Product Sub-Group Detail';
    public static final String LOGGER_TAG = 'OpportunityProductSubGroupDetail';

    @TestVisible
    private static final Set<String> ELIGIBLE_OPPORTUNITY_RECORD_TYPES = new Set<String>{
        'Healthcare_Sales',
        'HCSalesConsumables',
        'HCSalesLostBusinessConsumables'
    };

    @TestVisible
    private static Boolean recalculationDisabled = false;

    /**
     * @description Disables recalculation (used in tests or bulk data loads).
     * @param disabled When true, recalculateFromOpportunityIds is a no-op.
     */
    @TestVisible
    public static void setRecalculationDisabled(Boolean disabled) {
        recalculationDisabled = disabled;
    }

    /**
     * @description Returns whether recalculation is currently disabled.
     * @return True when recalculation is disabled.
     */
    public static Boolean isRecalculationDisabled() {
        return recalculationDisabled;
    }

    /**
     * @description After-insert orchestration for Opportunity Line Item trigger events.
     * @param lineItems Trigger.new rows.
     */
    public static void handleAfterInsert(List<OpportunityLineItem> lineItems) {
        recalculateProductSubGroupDetail(lineItems, null);
        /** Update Total Amount Based on the recurring frequency**/
        calculateRecurringFreqAmount(lineItems);
    }

    /**
     * @description After-update orchestration for Opportunity Line Item trigger events.
     * @param lineItems Trigger.new rows.
     * @param oldLineItemMap Trigger.oldMap.
     */
    public static void handleAfterUpdate(
        List<OpportunityLineItem> lineItems,
        Map<Id, OpportunityLineItem> oldLineItemMap
    ) {
        recalculateProductSubGroupDetail(lineItems, oldLineItemMap);
    }

    /**
     * @description After-delete orchestration for Opportunity Line Item trigger events.
     * @param lineItems Trigger.old rows.
     */
    public static void handleAfterDelete(List<OpportunityLineItem> lineItems) {
        recalculateProductSubGroupDetail(lineItems, null);
    }

    /**
     * @description After-undelete orchestration for Opportunity Line Item trigger events.
     * @param lineItems Trigger.new rows.
     */
    public static void handleAfterUndelete(List<OpportunityLineItem> lineItems) {
        recalculateProductSubGroupDetail(lineItems, null);
    }

    private static void recalculateProductSubGroupDetail(
        List<OpportunityLineItem> lineItems,
        Map<Id, OpportunityLineItem> oldLineItemMap
    ) {
        if (lineItems == null || lineItems.isEmpty()) {
            return;
        }

        if (isRecalculationDisabled()) {
            return;
        }

        try {
            Logger.info('OpportunityLineItemService: trigger recalculation started').addTag(LOGGER_TAG);

            Set<Id> opportunityIds = collectOpportunityIdsFromLineItems(lineItems, oldLineItemMap);
            recalculateFromOpportunityIds(opportunityIds);

            Logger.info('OpportunityLineItemService: trigger recalculation completed').addTag(LOGGER_TAG);
        } catch (Exception exceptionValue) {
            Logger.error('OpportunityLineItemService: ' + exceptionValue.getMessage()).addTag(LOGGER_TAG);
            throw exceptionValue;
        } finally {
            Logger.saveLog();
        }
    }

    @TestVisible
    private static Set<Id> collectOpportunityIdsFromLineItems(
        List<OpportunityLineItem> lineItems,
        Map<Id, OpportunityLineItem> oldLineItemMap
    ) {
        Set<Id> opportunityIds = new Set<Id>();

        for (OpportunityLineItem lineItem : lineItems) {
            if (lineItem.OpportunityId != null) {
                opportunityIds.add(lineItem.OpportunityId);
            }
        }

        if (oldLineItemMap != null) {
            for (OpportunityLineItem oldLineItem : oldLineItemMap.values()) {
                if (oldLineItem.OpportunityId != null) {
                    opportunityIds.add(oldLineItem.OpportunityId);
                }
            }
        }

        return opportunityIds;
    }

    /**
     * @description Recalculates ProductSubGroupDetailName__c for the given Opportunities.
     * @param opportunityIds Opportunity Id set.
     */
    public static void recalculateFromOpportunityIds(Set<Id> opportunityIds) {
        if (recalculationDisabled || opportunityIds == null || opportunityIds.isEmpty()) {
            return;
        }

        opportunityIds = filterEligibleOpportunityIds(opportunityIds);
        if (opportunityIds.isEmpty()) {
            return;
        }

        try {
            Logger.info(
                SCENARIO + ': recalculateFromOpportunityIds started, opportunityCount=' + opportunityIds.size()
            ).addTag(LOGGER_TAG);

            Map<Id, String> computedByOpportunityId = buildDetailNamesByOpportunityId(opportunityIds);
            List<Opportunity> opportunitiesToUpdate = buildOpportunityUpdates(
                opportunityIds,
                computedByOpportunityId
            );

            if (opportunitiesToUpdate.isEmpty()) {
                Logger.info(SCENARIO + ': no Opportunity updates required').addTag(LOGGER_TAG);
                return;
            }

            List<SObject> updateRecords = Security.stripInaccessible(
                AccessType.UPDATABLE,
                opportunitiesToUpdate
            ).getRecords();

            if (!updateRecords.isEmpty()) {
                update as user updateRecords;
            }

            Logger.info(
                SCENARIO + ': updated Opportunity count=' + updateRecords.size()
            ).addTag(LOGGER_TAG);
        } catch (Exception exceptionValue) {
            Logger.error(SCENARIO + ': ' + exceptionValue.getMessage()).addTag(LOGGER_TAG);
            throw exceptionValue;
        } finally {
            Logger.saveLog();
        }
    }

    @TestVisible
    private static Map<Id, String> buildDetailNamesByOpportunityId(Set<Id> opportunityIds) {
        Map<Id, String> resultByOpportunityId = new Map<Id, String>();
        Set<String> allowedPicklistValues = getAllowedPicklistValues();

        List<OpportunityLineItem> lineItems = OpportunityLineItemSelector.selectByOpportunityIds(
            opportunityIds
        );
        List<QuoteLineItem> quoteLineItems = QuoteLineItemSelector.selectByOpportunityIds(opportunityIds);

        Set<Id> product2Ids = new Set<Id>();
        for (OpportunityLineItem lineItem : lineItems) {
            if (lineItem.Product2Id != null) {
                product2Ids.add(lineItem.Product2Id);
            }
        }

        for (QuoteLineItem quoteLineItem : quoteLineItems) {
            if (quoteLineItem.Product2Id != null) {
                product2Ids.add(quoteLineItem.Product2Id);
            }
        }

        Map<Id, Id> psamIdByProduct2Id = mapPsamIdByProduct2Id(product2Ids);
        Set<Id> psamIds = new Set<Id>(psamIdByProduct2Id.values());
        Map<Id, String> detailNameByPsamId = mapDetailNameByPsamId(psamIds);

        Map<Id, Set<String>> detailNamesByOpportunityId = new Map<Id, Set<String>>();
        for (OpportunityLineItem lineItem : lineItems) {
            addDetailNameForProductLine(
                lineItem.OpportunityId,
                lineItem.Product2Id,
                psamIdByProduct2Id,
                detailNameByPsamId,
                allowedPicklistValues,
                detailNamesByOpportunityId
            );
        }

        for (QuoteLineItem quoteLineItem : quoteLineItems) {
            addDetailNameForProductLine(
                quoteLineItem.Quote.OpportunityId,
                quoteLineItem.Product2Id,
                psamIdByProduct2Id,
                detailNameByPsamId,
                allowedPicklistValues,
                detailNamesByOpportunityId
            );
        }

        for (Id opportunityId : opportunityIds) {
            Set<String> detailNames = detailNamesByOpportunityId.get(opportunityId);
            resultByOpportunityId.put(opportunityId, encodeMultiSelectPicklist(detailNames));
        }

        return resultByOpportunityId;
    }

    @TestVisible
    private static void addDetailNameForProductLine(
        Id opportunityId,
        Id product2Id,
        Map<Id, Id> psamIdByProduct2Id,
        Map<Id, String> detailNameByPsamId,
        Set<String> allowedPicklistValues,
        Map<Id, Set<String>> detailNamesByOpportunityId
    ) {
        if (opportunityId == null || product2Id == null) {
            return;
        }

        Id psamId = psamIdByProduct2Id.get(product2Id);
        if (psamId == null) {
            return;
        }

        String detailName = detailNameByPsamId.get(psamId);
        if (String.isBlank(detailName) || !allowedPicklistValues.contains(detailName)) {
            return;
        }

        if (!detailNamesByOpportunityId.containsKey(opportunityId)) {
            detailNamesByOpportunityId.put(opportunityId, new Set<String>());
        }
        detailNamesByOpportunityId.get(opportunityId).add(detailName);
    }

    private static List<Opportunity> buildOpportunityUpdates(
        Set<Id> opportunityIds,
        Map<Id, String> computedByOpportunityId
    ) {
        List<Opportunity> existingOpportunities = [
            SELECT Id, ProductSubGroupDetailName__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
            WITH USER_MODE
        ];

        List<Opportunity> updates = new List<Opportunity>();
        for (Opportunity existingOpportunity : existingOpportunities) {
            String computedValue = computedByOpportunityId.get(existingOpportunity.Id);
            String normalizedComputed = normalizeMultiSelect(computedValue);
            String normalizedExisting = normalizeMultiSelect(
                existingOpportunity.ProductSubGroupDetailName__c
            );

            if (normalizedComputed == normalizedExisting) {
                continue;
            }

            updates.add(
                new Opportunity(
                    Id = existingOpportunity.Id,
                    ProductSubGroupDetailName__c = normalizedComputed
                )
            );
        }

        return updates;
    }

    @TestVisible
    private static Map<Id, Id> mapPsamIdByProduct2Id(Set<Id> product2Ids) {
        Map<Id, Id> psamIdByProduct2Id = new Map<Id, Id>();
        if (product2Ids.isEmpty()) {
            return psamIdByProduct2Id;
        }

        for (Product2 product : Product2Selector.selectPsamByIds(product2Ids)) {
            if (product.PSAM__c != null) {
                psamIdByProduct2Id.put(product.Id, product.PSAM__c);
            }
        }

        return psamIdByProduct2Id;
    }

    @TestVisible
    private static Map<Id, String> mapDetailNameByPsamId(Set<Id> psamIds) {
        Map<Id, String> detailNameByPsamId = new Map<Id, String>();
        if (psamIds.isEmpty()) {
            return detailNameByPsamId;
        }

        for (PSAM__c psam : PsamSelector.selectByIds(psamIds)) {
            detailNameByPsamId.put(psam.Id, psam.ProductSubgroupDetailName__c);
        }

        return detailNameByPsamId;
    }

    @TestVisible
    private static Set<String> getAllowedPicklistValues() {
        Set<String> allowedValues = new Set<String>();
        for (
            Schema.PicklistEntry picklistEntry : Opportunity.ProductSubGroupDetailName__c.getDescribe()
                .getPicklistValues()
        ) {
            if (picklistEntry.isActive()) {
                allowedValues.add(picklistEntry.getValue());
            }
        }
        return allowedValues;
    }

    @TestVisible
    private static String encodeMultiSelectPicklist(Set<String> values) {
        if (values == null || values.isEmpty()) {
            return null;
        }

        List<String> sortedValues = new List<String>(values);
        sortedValues.sort();
        return String.join(sortedValues, ';');
    }

    @TestVisible
    private static String normalizeMultiSelect(String rawValue) {
        if (String.isBlank(rawValue)) {
            return null;
        }

        Set<String> uniqueValues = new Set<String>();
        for (String token : rawValue.split(';')) {
            if (String.isNotBlank(token)) {
                uniqueValues.add(token.trim());
            }
        }

        return encodeMultiSelectPicklist(uniqueValues);
    }

    @TestVisible
    private static Set<Id> filterEligibleOpportunityIds(Set<Id> opportunityIds) {
        Set<Id> eligibleOpportunityIds = new Set<Id>();
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return eligibleOpportunityIds;
        }

        for (Opportunity opportunityRecord : [
            SELECT Id, RecordType.DeveloperName
            FROM Opportunity
            WHERE Id IN :opportunityIds
            WITH USER_MODE
        ]) {
            if (
                ELIGIBLE_OPPORTUNITY_RECORD_TYPES.contains(
                    opportunityRecord.RecordType.DeveloperName
                )
            ) {
                eligibleOpportunityIds.add(opportunityRecord.Id);
            }
        }

        return eligibleOpportunityIds;
    }
    /** This method will calculate the total amount**/
    public static void calculateRecurringFreqAmount(List<OpportunityLineItem> lineItems){
        Set<Id> oppIds = new Set<Id>();
        for(OpportunityLineItem oli : lineItems){
            oppIds.add(oli.OpportunityId);
        }
        Set<Id> filteredOppIds = filterEligibleOpportunityIds(oppIds);
        List<OpportunityLineItem> lstOpportunityLineItemsToBeUpdated = new List<OpportunityLineItem>();
        for(OpportunityLineItem oli : [SELECT CalculatedAnnualRevenue_f__c,ConsumptionFrequency__c,UnitPrice,
                                              Quantity,TotalPrice
                                       FROM OpportunityLineItem  
                                       WHERE OpportunityId IN:filteredOppIds]){
               if(oli.ConsumptionFrequency__c == 'Weekly'){
                   oli.UnitPrice = 52 * oli.UnitPrice;
               }else if(oli.ConsumptionFrequency__c == 'Monthly'){
                   oli.UnitPrice = 12 * oli.UnitPrice;
               }else if(oli.ConsumptionFrequency__c == 'Annual'){
                   oli.UnitPrice = oli.UnitPrice;
               }
               lstOpportunityLineItemsToBeUpdated.add(oli);
         }
        try {
            Logger.info('OpportunityLineItemService: trigger unit price update started').addTag(LOGGER_TAG);
           // update lstOpportunityLineItemsToBeUpdated;

            Logger.info('OpportunityLineItemService: trigger unit price update completed').addTag(LOGGER_TAG);
        } catch (Exception exceptionValue) {
            Logger.error('OpportunityLineItemService: ' + exceptionValue.getMessage()).addTag(LOGGER_TAG);
            throw exceptionValue;
        } finally {
            Logger.saveLog();
        }
         
    }
}