/**
 * @author PWC Developer
 * @date 2026/07/07
 *
 * @group GC-2649 Generate Quote
 *
 * @description
 * Selector for PSAM__c product categorization master data (CBM-1003).
 * Uses SYSTEM_MODE because PSAM is read-only reference data.
 * GC-3129 - selectByIds supports Product Sub-Group Detail derivation on Opportunity.
 */
public with sharing class PsamSelector {
    /**
     * @description Selects PSAM records by Product FAM Code.
     * @param famCodes Set of Product FAM codes.
     * @return Matching PSAM records.
     */
    public static List<PSAM__c> selectByFamCodes(Set<String> famCodes) {
        if (famCodes == null || famCodes.isEmpty()) {
            return new List<PSAM__c>();
        }

        return [
            SELECT Id,
                Name,
                ProductFAMCode__c,
                ProductGroupName__c,
                ProductSubgroupName__c,
                ProductSubgroupDetailName__c
            FROM PSAM__c
            WHERE ProductFAMCode__c IN :famCodes
            WITH SYSTEM_MODE
        ];
    }

    /**
     * @description Selects PSAM records by Id (Product2.PSAM__c lookup target).
     * @param psamIds Set of PSAM record Ids.
     * @return PSAM__c rows with ProductSubgroupDetailName__c.
     */
    public static List<PSAM__c> selectByIds(Set<Id> psamIds) {
        if (psamIds == null || psamIds.isEmpty()) {
            return new List<PSAM__c>();
        }

        return [
            SELECT Id,
                Name,
                ProductFAMCode__c,
                ProductGroupName__c,
                ProductSubgroupName__c,
                ProductSubgroupDetailName__c
            FROM PSAM__c
            WHERE Id IN :psamIds
            WITH SYSTEM_MODE
        ];
    }
}