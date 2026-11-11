/**
 * @author Abhishek Mishra
 * @date 06-08-2026
 * @description SOQL-only selector for Lead records used by TAS processing.
 *
 * User Story - GC-3279
 */
public with sharing class LeadSelector {

    /**
     * @description Selects Lead records by Ids with fields required for the TAS request payload.
     * @param leadIdSet Lead Id set.
     * @return List of Leads.
     */
    public static List<Lead> selectByIds(Set<Id> leadIdSet) {
        if (leadIdSet == null || leadIdSet.isEmpty()) {
            return new List<Lead>();
        }

        return [
            SELECT Id,
                   FirstName,
                   LastName,
                   Company,
                   OwnerId,
                   Street,
                   City,
                   State,
                   PostalCode,
                   Country,
                   Org_ID__c,
                   Class_Code__c
            FROM Lead
            WHERE Id IN :leadIdSet
        ];
    }
}