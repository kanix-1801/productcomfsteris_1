/**
 * @author Persistent Developer
 * @date 2026/26/10
 * For story : 1387.
* @description
* This class is used for adding toAddress and ccAddress for the email. 
 */
public with sharing class OrderLineContactSelector {
	/**
     * @description      
     * Method is used for getting order line contact related to the calling case.
     *
     * @param caseRecord.
     * @return List of sales reps email.
     */
    public static List<OrderLineContact__c> getOrderLineContact (Case c) {
        List<OrderLineContact__c> olContacts = [SELECT SalesRep__r.Email FROM OrderLineContact__c WHERE OrderLine__r.OrderId = :c.Order__c and (OrderLine__r.CreateSubcase__c = 'yes - Capital line' 
                                                                              OR OrderLine__r.CreateSubcase__c = 'yes - Service Installation') WITH USER_MODE];
        if(!olContacts.isEmpty())
            return olContacts;
        return NULL;
    }
}