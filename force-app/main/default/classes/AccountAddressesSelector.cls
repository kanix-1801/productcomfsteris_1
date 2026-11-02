/**
 * Selector class for retrieving Address records.
 */
public with sharing class AccountAddressesSelector {
    /**
     * Returns Address records associated with the given Account Id.
     * @param accountId The Id of the Account to query addresses for.
     * @return A list of Address SObjects, or an empty list if accountId is null.
     */
        public static List<SObject> selectByAccountId(Id accountId) {
            if (accountId == null) {
                return new List<SObject>();
            }
            
            return [
            SELECT Id, Street, AddressType, City, State, PostalCode
            FROM Address
            WHERE Customer__c = :accountId
            WITH USER_MODE
            ORDER BY Street
            LIMIT 200
        ];
        }
        
         /**
    * @description
    * GC-3088 - Selects Address records whose AddressId__c matches TAS Address IDs.
    * 
    * @param tasAddressIdSet TASAddressID set
    * @return List of SObject (Address data)
    * 
    * @example
    * AccountAddressesSelector.selectByAddressIds(tasAddressIdSet);
    */
        public static List<SObject> selectByAddressIds(Set<String> tasAddressIdSet) {
            if (tasAddressIdSet == null || tasAddressIdSet.isEmpty()) {
                return new List<SObject>();
            }
            
            return Database.query(
                'SELECT Id, AddressId__c, Customer__c, Customer__r.Name ' +
                'FROM Address ' +
                'WHERE AddressId__c IN :tasAddressIdSet ' +
                'AND Customer__c != null ' +
                'WITH SECURITY_ENFORCED'
            );
        }
        /**
    * @description
    * GC-3088 - Selects Selects Address records related to selected Accounts.
    * 
    * @param accountIdSet AccountId set
    * @return List of SObject (Address data)
    * 
    * @example
    * AccountAddressesSelector.selectByAccountIds(accountIdSet);
    */
        public static List<SObject> selectByAccountIds(Set<Id> accountIdSet) {
            if (accountIdSet == null || accountIdSet.isEmpty()) {
                return new List<SObject>();
            }
            
            return Database.query(
                'SELECT Id, AddressId__c, Customer__c ' +
                'FROM Address ' +
                'WHERE Customer__c IN :accountIdSet ' +
                'AND AddressId__c != null ' +
                'WITH SECURITY_ENFORCED'
            );
        }
}