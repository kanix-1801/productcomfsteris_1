/**
* @author PSL
* @date 09/17/2026
* @description Returns OrderAndOrderLineHold__c records grouped by four common fields 
* and concatenates all distinct, nonblank values from the HoldCode__c field into one display row.
*/
public with sharing class CBMHoldsRelatedListController {

    public class GroupedRecordRow {
        @AuraEnabled public String rowKey { get; set; }
        @AuraEnabled public String lineNumber { get; set; }
        @AuraEnabled public String itemNumber { get; set; }
        @AuraEnabled public String productDescription { get; set; }
        @AuraEnabled public String quantity { get; set; }
        @AuraEnabled public String holdCodes { get; set; }
    }

    private class GroupAccumulator {
        GroupedRecordRow row;
        Set<String> holdCodeValues = new Set<String>();
    }

    /**
     * Gets records related to the current Lightning record page, groups records
     * having the same first four field values, and combines the holdCode values.
     *
     * @param recordId ID of the parent record currently displayed.
     * @return Aggregated rows for the LWC datatable.
     */
    @AuraEnabled(cacheable=true)
    public static List<GroupedRecordRow> getGroupedRecords(Id recordId) {
        if (recordId == null) {
            return new List<GroupedRecordRow>();
        }

        try {
            List<OrderAndOrderLineHold__c> sourceRecords = [SELECT HoldCode__c, LineNumber__c, ItemNumber__c, ProductDescription__c, Quantity__c FROM OrderAndOrderLineHold__c WHERE Order__r.ParentCase__c = :recordId AND Active__c = true AND OrderLine__c != null AND OrderLineType__c != 'BOM Component' AND HoldCode__c != null ORDER BY LineNumber__c ];

            Map<String, GroupAccumulator> groupedByFields =
                new Map<String, GroupAccumulator>();

            for (OrderAndOrderLineHold__c sourceRecord : sourceRecords) {
                String groupKey = buildGroupKey(sourceRecord);

                if (!groupedByFields.containsKey(groupKey)) {
                    GroupAccumulator accumulator = new GroupAccumulator();
                    accumulator.row = new GroupedRecordRow();
                    accumulator.row.rowKey = groupKey;
                    accumulator.row.lineNumber = toDisplayValue(sourceRecord.LineNumber__c);
                    accumulator.row.itemNumber = toDisplayValue(sourceRecord.ItemNumber__c);
                    accumulator.row.productDescription = toDisplayValue(sourceRecord.ProductDescription__c);
                    accumulator.row.quantity = toDisplayValue(sourceRecord.Quantity__c);
                    groupedByFields.put(groupKey, accumulator);
                }

                String holdCodeValue = toDisplayValue(sourceRecord.HoldCode__c);
                if (String.isNotBlank(holdCodeValue)) {
                    groupedByFields.get(groupKey).holdCodeValues.add(holdCodeValue.trim());
                }
            }

            List<GroupedRecordRow> result = new List<GroupedRecordRow>();
            for (GroupAccumulator accumulator : groupedByFields.values()) {
                List<String> sortedValues = new List<String>();
                sortedValues.addAll(accumulator.holdCodeValues);
                sortedValues.sort();
                accumulator.row.holdCodes = String.join(sortedValues, ', ');
                result.add(accumulator.row);
            }
            return result;
        } catch(Exception ex){
            ErrorLogger.logException(ex, 'CBMHoldsRelatedListController', 'getGroupedRecords');
            throw ex;
        }
    }

    private static String buildGroupKey(OrderAndOrderLineHold__c recordValue) {
        List<String> keyParts = new List<String>{
            toDisplayValue(recordValue.LineNumber__c),
            toDisplayValue(recordValue.ItemNumber__c),
            toDisplayValue(recordValue.ProductDescription__c),
            toDisplayValue(recordValue.Quantity__c)
        };

        // Length-prefixing avoids collisions when values contain delimiters.
        List<String> encodedParts = new List<String>();
        for (String keyPart : keyParts) {
            encodedParts.add(String.valueOf(keyPart.length()) + ':' + keyPart);
        }
        return String.join(encodedParts, '|');
    }

    private static String toDisplayValue(Object value) {
        return value == null ? '' : String.valueOf(value);
    }
}