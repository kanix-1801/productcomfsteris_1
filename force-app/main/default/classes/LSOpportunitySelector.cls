public with sharing class LSOpportunitySelector {
    


    /**
     * @author Sarthak Pani
     * @description GCL-66 - Selects Opportunity by Id, including Name for display.
     * @param opportunityId Opportunity Id.
     * @return List of Opportunities with Id, Name and Pricebook2Id.
     */

     public static Opportunity selectById(Id opportunityId) {
        if (opportunityId == null) {
            return null;
        }

        List<Opportunity> opportunityList = [
            SELECT Id, OnHold__c   //GCL-66
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];

        return opportunityList.isEmpty() ? null : opportunityList[0];
    }
}