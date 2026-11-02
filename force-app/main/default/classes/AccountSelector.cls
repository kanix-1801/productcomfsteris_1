/**
 * @author PWC Developer
 * @date 2026/06/10
 *
 * @group Overlay Assignment
 *
* @description
* GC-3088 - SOQL - only selector for Account Object
 */
public with sharing class AccountSelector extends SoqlQueryBuilder {
    /**
     * @description Creates a selector for the Account object. Sets the object name that
     *              every query built by this selector runs against, so callers only
     *              add fields, filters, ordering and limits.
     * @example
     * List<Account> accounts = (List<Account>) new AccountSelector()
     *     .selectField('Id')
     *     .whereEquals('AccountNumber', accountNumber)
     *     .limitTo(2)
     *     .execute();
     */
    public AccountSelector() {
        this.objectName = 'Account';
    }
    
    /**
* @description
* GC-3088 - Selects Accounts by IDs.
* 
* @param accountIdSet Account ID set
* @return List of Accounts
* 
* @example
* AccountSelector.selectByIds(accountIdSet);
     */
    public static List<Account> selectByIds(Set<Id> accountIdSet) {
        if (accountIdSet == null || accountIdSet.isEmpty()) {
            return new List<Account>();
        }
        
        return [
            SELECT Id,
            Name,
            AccountNumber,
            Type,
            OracleAddressId__c,  //Update: GC-3112
            ParentId, // GC-2860
            RecordTypeId, //GC-2849-START
            CustomerClassCode__c,
            OrgIDs__c,//part of GC-3107
            Price_List__c,
            BillingStreet,
            BillingCity,
            ShippingState,
            BillingState,
            BillingCountry,
            BillingPostalCode,//GC-2849-END
            TAS_Retry__c, //GC-3091
            TAS_Assignment_Status__c // GC - 3143
            FROM Account
            WHERE Id IN :accountIdSet
        ];
    }
	 
    /**
     * @description
     * GC-2868 AC3 - Selects direct child Accounts using the standard
     * Account.ParentId relationship.
     *
     * @param parentAccountIdSet Parent Account IDs.
     * @return Direct child Accounts.
     */
    public static List<Account> selectByParentIds( Set<Id> parentAccountIdSet) {
        if (parentAccountIdSet == null ||parentAccountIdSet.isEmpty()) {
            return new List<Account>();
        }

        return [SELECT Id,Name,Type,ParentId,OracleAddressId__c,RecordTypeId
            FROM Account WHERE ParentId IN :parentAccountIdSet WITH SECURITY_ENFORCED];
    }

     
    /**
     * @description Selects Customer Accounts with fields required for realtime TAS callout.
     * @param accountIdSet Account Id set.
     * @return List of Accounts with TAS payload fields.
     * GC-3021
     */
    public static List<Account> selectCustomerAccountsForTasByIds(Set<Id> accountIdSet) {
        if (accountIdSet == null || accountIdSet.isEmpty()) {
            return new List<Account>();
        }

        return [
            SELECT Id,
                   Name,
                   RecordTypeId,
                   AccountSource,
                   SourceSystemID__c,
                   CustomerClassCode__c,
                   OrgIDs__c,
                   OracleAddressId__c,
                   BillingStreet,
                   BillingCity,
                   BillingState,
                   BillingStateCode,
                   BillingCountry,
                   BillingCountryCode,
                   BillingPostalCode
            FROM Account
            WHERE Id IN :accountIdSet
            WITH USER_MODE
        ];
    }
    
    /**
     * @description
     * GC-3088 - Loads Account records by OracleAddressId__c for overlay territory resolution.
     *              Map key matches OrderLineContact__c.TASAddressId__c.
     * @param tasAddressIds TAS address ids from OrderLineContact__c.TASAddressId__c
     * @return Map of OracleAddressId__c to Account
     */
    public static Map<String, Account> selectAccountsByOracleAddressId(Set<String> tasAddressIds) {  //Update: GC-3112
        Map<String, Account> accountByOracleAddressId = new Map<String, Account>();

        if (tasAddressIds == null || tasAddressIds.isEmpty()) {
            return accountByOracleAddressId;
        }

        for (Account accountRecord : [
            SELECT Id,
                   Name,
                   AccountNumber,
                   Type,
                   ParentId,
                   OracleAddressId__c
            FROM Account
            WHERE OracleAddressId__c IN :tasAddressIds
              AND OracleAddressId__c != null
            WITH SECURITY_ENFORCED
        ]) {
            if (String.isBlank(accountRecord.OracleAddressId__c)) {
                continue;
            }

            String oracleAddressKey = accountRecord.OracleAddressId__c.trim();

            if (!accountByOracleAddressId.containsKey(oracleAddressKey)) {
                accountByOracleAddressId.put(oracleAddressKey, accountRecord);
            }
        }

        return accountByOracleAddressId;
    }

    /**
     * @author Abhishek Mishra
     * @description GC-3180 - Selects child Address accounts for the given parent Account Ids.
     * @param parentAccountIds Parent Account Ids selected for overlay assignment.
     * @return Child Account records linked via ParentId.
     */
    public static List<Account> selectChildAccountsByParentIds(Set<Id> parentAccountIds) {
        if (parentAccountIds == null || parentAccountIds.isEmpty()) {
            return new List<Account>();
        }

        return [
            SELECT Id,
                   Name,
                   AccountNumber,
                   Type,
                   ParentId,
                   OracleAddressId__c
            FROM Account
            WHERE ParentId IN :parentAccountIds
            WITH SECURITY_ENFORCED
        ];
    }

    /**
     * @description
     * GC-3112 - Selects Account Id and OracleAddressId__c for duplicate match key resolution
     *              via Opportunity.AccountId.
     * @param accountIds Account Ids from Opportunity.AccountId
     * @return Account rows with Id and OracleAddressId__c
     */
    public static List<Account> selectOracleAddressIdByAccountIds(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<Account>();
        }

        return [
            SELECT Id, OracleAddressId__c
            FROM Account
            WHERE Id IN :accountIds
              AND OracleAddressId__c != null
            WITH SECURITY_ENFORCED
        ];
    }
     /**
* @description
* GC-3088 - Selects Accounts using Account Name/Number and Account Type filters.
* GC-3180 - Account name/number search excludes Address accounts and requires Oracle Customer ID
*              (SourceSystemID__c) except when filtering by IDN or GPO account type.
* 
* @param accountSearchKey Account Name or Account Number entered by the user.
* @param accountType Account Type selected by the user.
* @return List of Accounts
* 
* @example
* AccountSelector.selectBySearchCriteria(accountSearchKey, accountType);
     */
    public static List<Account> selectBySearchCriteria(String accountSearchKey, String accountType) {
        String searchTerm = String.isBlank(accountSearchKey) ? null : '%' + String.escapeSingleQuotes(accountSearchKey.trim()) + '%';
        Boolean hasSearchTerm = String.isNotBlank(accountSearchKey);
        Boolean hasAccountType = String.isNotBlank(accountType);
        Boolean requiresOracleCustomerId = hasSearchTerm && !isGpoOrIdnAccountType(accountType);

        if (!hasSearchTerm && !hasAccountType) {
            return [
                SELECT Id,
                       Name,
                       AccountNumber,
                       Type
                FROM Account
                ORDER BY Name
                LIMIT 5000
            ];
        }

        if (hasSearchTerm && hasAccountType) {
            return [
                SELECT Id,
                       Name,
                       AccountNumber,
                       Type
                FROM Account
                WHERE (Name LIKE :searchTerm OR AccountNumber LIKE :searchTerm)
                AND Type = :accountType
                ORDER BY Name
                LIMIT 5000
            ];
        }

        if (hasSearchTerm) {
            return [
                SELECT Id,
                       Name,
                       AccountNumber,
                       Type
                FROM Account
                WHERE Name LIKE :searchTerm OR AccountNumber LIKE :searchTerm
                ORDER BY Name
                LIMIT 5000
            ];
        }

        return [
            SELECT Id,
                   Name,
                   AccountNumber,
                   Type
            FROM Account
            WHERE Type = :accountType
            ORDER BY Name
            LIMIT 5000
        ];
    }

    private static Boolean isGpoOrIdnAccountType(String accountType) {
        return accountType == 'GPO' || accountType == 'IDN';
    }

    /**
     * @author Himanshu Chaurasia
     * @description GC-2642 Interim Generate Quote - Loads Account fields required to build Sales Connection URLs.
     * @param accountId Account Id.
     * @return Account with Oracle Address Id and record type, or null when not found.
     */
    public static Account selectAccountForSalesConnection(Id accountId) {
        if (accountId == null) {
            return null;
        }

        List<Account> accountList = [
            SELECT Id,
                OracleAddressId__c,
                RecordType.DeveloperName
            FROM Account
            WHERE Id = :accountId
            WITH USER_MODE
            LIMIT 1
        ];

        return accountList.isEmpty() ? null : accountList[0];
    }
    /**
     * @author Suraj Thapliyal
     * @description GC-2580 - Selects Accounts owned by the given user Ids.
     * @param ownerIds Owner user Ids.
     * @return Account rows with Id and OwnerId.
     */
    public static List<Account> selectByOwnerIds(Set<Id> ownerIds) {
        if (ownerIds == null || ownerIds.isEmpty()) {
            return new List<Account>();
        }

        return [
            SELECT Id, OwnerId
            FROM Account
            WHERE OwnerId IN :ownerIds
            WITH USER_MODE
        ];
    }
    /**
     * @description GC-2860 - Returns facility accounts whose immediate parent is the given account Id.
     * @param parentAccountId Parent account Id.
     * @return Direct child facility accounts only.
     */
    public static List<Account> selectFacilityAccountsByParentId(Id parentAccountId) {
        if (parentAccountId == null) {
            return new List<Account>();
        }

        return [
            SELECT Id,
                   Name,
                   OracleAddressId__c,
                   ParentId
            FROM Account
            WHERE ParentId = :parentAccountId
              AND OracleAddressId__c != null
            WITH USER_MODE
        ];
    }

    /**
     * @description GC-2860 - Returns facility accounts for multiple parent account Ids.
     * @param parentAccountIds Parent account Ids.
     * @return Direct child facility accounts only.
     */
    public static List<Account> selectFacilityAccountsByParentIds(Set<Id> parentAccountIds) {
        if (parentAccountIds == null || parentAccountIds.isEmpty()) {
            return new List<Account>();
        }

        return [
            SELECT Id,
                   Name,
                   OracleAddressId__c,
                   ParentId
            FROM Account
            WHERE ParentId IN :parentAccountIds
              AND OracleAddressId__c != null
            WITH USER_MODE
        ];
    }

    /**
     * @description GW-4786 - Address accounts eligible as Return Order Ship-To values.
     *              Matches ReturnOrder.ShipToAddressAccount__c lookup filter:
     *              ParentId, Type = Address, ShiptoAddressStatus Active or Primary.
     * @param parentAccountId Customer account on the Return Order.
     * @return Matching Address accounts with billing fields.
     */
    public static List<Account> selectShipToAddressAccountsByParentId(Id parentAccountId) {
        if (parentAccountId == null) {
            return new List<Account>();
        }

        return [
            SELECT
                Id,
                Name,
                Type,
                ParentId,
                ShiptoAddressStatus__c,
                BillingStreet,
                BillingCity,
                BillingState,
                BillingStateCode,
                BillingPostalCode,
                BillingCountry,
                BillingCountryCode
            FROM Account
            WHERE ParentId = :parentAccountId
                AND Type = 'Address'
                AND ShiptoAddressStatus__c IN ('Active', 'Primary')
            WITH USER_MODE
            ORDER BY ShiptoAddressStatus__c DESC, Name ASC
        ];
    }

    /**
     * @description GW-4585 - Accounts loaded for Oracle pricing (ship-to, bill-to, prospect).
     * @param accountIds Account Ids to query
     * @return Accounts keyed by Id
     */
    public static Map<Id, Account> selectForOraclePricingByIds(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new Map<Id, Account>();
        }

        return new Map<Id, Account>([
            SELECT
                Id,
                AccountNumber,
                OrgIDs__c,
                OracleAddressId__c,
                Type,
                RecordType.DeveloperName,
                Price_List__c,
                Price_List__r.Price_List_ID__c,
                Parent.OrgIDs__c,
                Parent.AccountNumber
            FROM Account
            WHERE Id IN :accountIds
        ]);
    }

    /**
     * @description GW-4585 - Active or Primary Address children used as Oracle ship-to.
     * @param parentAccountId Customer account Id
     * @return Address accounts ordered Primary before Active
     */
    public static List<Account> selectOracleAddressAccountsForPricing(Id parentAccountId) {
        if (parentAccountId == null) {
            return new List<Account>();
        }

        return [
            SELECT
                Id,
                AccountNumber,
                OrgIDs__c,
                OracleAddressId__c,
                Type,
                RecordType.DeveloperName,
                Price_List__c,
                Price_List__r.Price_List_ID__c,
                Parent.OrgIDs__c,
                Parent.AccountNumber,
                ShiptoAddressStatus__c
            FROM Account
            WHERE ParentId = :parentAccountId
                AND Type = 'Address'
                AND AccountNumber != null
                AND ShiptoAddressStatus__c IN ('Active', 'Primary')
            ORDER BY ShiptoAddressStatus__c DESC, LastModifiedDate DESC
            LIMIT 50
        ];
    }

    /**
     * @description GW-5492 - Internal Accounts for Receiving Internal Repair options (Type = I).
     * @return Internal accounts ordered by Name
     */
    public static List<Account> selectInternalAccountsForReceiving() {
        return (List<Account>) SoqlQueryBuilder.fromObject('Account')
            .selectFields(new List<String>{ 'Id', 'Name', 'AccountNumber' })
            .whereEquals('Type', 'I')
            .orderBy('Name')
            .execute();
    }

    /**
     * @description GW-5492 - Vendor Accounts for Receiving Outside Vendor options (Type = Vendor).
     * @return Vendor accounts ordered by Name
     */
    public static List<Account> selectVendorAccountsForReceiving() {
        return (List<Account>) SoqlQueryBuilder.fromObject('Account')
            .selectFields(new List<String>{ 'Id', 'Name' })
            .whereEquals('Type', 'Vendor')
            .orderBy('Name')
            .execute();
    }

    /**
     * @description Billing address and currency for Receiving work-order address mapping.
     * @param accountIds Address or internal Account Ids
     * @return Matching Accounts, or an empty list
     */
    public static List<Account> selectBillingAddressByIds(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<Account>();
        }
        // List<Id> must stay typed. whereIn(List<Object>) binds as ANY and is rejected for Id columns.
        return (List<Account>) SoqlQueryBuilder.fromObject('Account')
            .selectFields(
                new List<String>{
                    'Id',
                    'CurrencyIsoCode',
                    'BillingStreet',
                    'BillingCity',
                    'BillingState',
                    'BillingStateCode',
                    'BillingPostalCode',
                    'BillingCountry',
                    'BillingCountryCode'
                }
            )
            .whereField('Id', 'IN', new List<Id>(accountIds))
            .execute();
    }

    /**
     * @description GW-5492 - Loads Account Number for Receiving Bill-To resolution.
     * @param accountId Customer Account Id (RO.AccountId)
     * @return Matching Account with AccountNumber, or empty list
     */
    public static List<Account> selectAccountNumberByIdForReceiving(Id accountId) {
        if (accountId == null) {
            return new List<Account>();
        }
        return (List<Account>) SoqlQueryBuilder.fromObject('Account')
            .selectFields(new List<String>{ 'Id', 'AccountNumber' })
            .whereEquals('Id', accountId)
            .limitTo(1)
            .execute();
    }

    /**
     * @description GW-5492 - Primary Bill-To Address Account matching customer Account Number.
     * @param accountNumber Customer Account.AccountNumber
     * @return Matching Address account or empty list
     */
    public static List<Account> selectPrimaryBillToByAccountNumber(String accountNumber) {
        if (String.isBlank(accountNumber)) {
            return new List<Account>();
        }
        return (List<Account>) SoqlQueryBuilder.fromObject('Account')
            .selectFields(
                new List<String>{
                    'Id',
                    'Name',
                    'AccountNumber',
                    'Type',
                    'ParentId',
                    'BilltoAddressStatus__c',
                    'CurrencyIsoCode',
                    'BillingStreet',
                    'BillingCity',
                    'BillingState',
                    'BillingStateCode',
                    'BillingPostalCode',
                    'BillingCountry',
                    'BillingCountryCode'
                }
            )
            .whereEquals('AccountNumber', accountNumber)
            .whereEquals('Type', 'Address')
            .whereEquals('BilltoAddressStatus__c', 'Primary')
            .orderBy('Name')
            .limitTo(1)
            .execute();
    }
}