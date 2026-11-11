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

        return (List<Account>) SoqlQueryBuilder.fromObject('Account')
            .selectFields(
                new List<String>{
                    'Id',
                    'Name',
                    'AccountNumber',
                    'Type',
                    'OracleAddressId__c',
                    'ParentId',
                    'RecordTypeId',
                    'CustomerClassCode__c',
                    'OrgIDs__c',
                    'Price_List__c',
                    'BillingStreet',
                    'BillingCity',
                    'ShippingState',
                    'BillingState',
                    'BillingCountry',
                    'BillingPostalCode',
                    'TAS_Retry__c',
                    'TAS_Assignment_Status__c'
                }
            )
            .whereField('Id', 'IN', new List<Id>(accountIdSet))
            .execute();
    }

    /**
     * @description
     * GC-2868 AC3 - Selects direct child Accounts using the standard
     * Account.ParentId relationship.
     *
     * @param parentAccountIdSet Parent Account IDs.
     * @return Direct child Accounts.
     */
    public static List<Account> selectByParentIds(Set<Id> parentAccountIdSet) {
        if (parentAccountIdSet == null || parentAccountIdSet.isEmpty()) {
            return new List<Account>();
        }

        return (List<Account>) SoqlQueryBuilder.fromObject('Account')
            .selectFields(
                new List<String>{
                    'Id',
                    'Name',
                    'Type',
                    'ParentId',
                    'OracleAddressId__c',
                    'RecordTypeId'
                }
            )
            .whereField('ParentId', 'IN', new List<Id>(parentAccountIdSet))
            .execute();
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

        return (List<Account>) SoqlQueryBuilder.fromObject('Account')
            .selectFields(
                new List<String>{
                    'Id',
                    'Name',
                    'RecordTypeId',
                    'AccountSource',
                    'SourceSystemID__c',
                    'CustomerClassCode__c',
                    'OrgIDs__c',
                    'OracleAddressId__c',
                    'BillingStreet',
                    'BillingCity',
                    'BillingState',
                    'BillingStateCode',
                    'BillingCountry',
                    'BillingCountryCode',
                    'BillingPostalCode'
                }
            )
            .whereField('Id', 'IN', new List<Id>(accountIdSet))
            .execute();
    }

    /**
     * @description
     * GC-3088 - Loads Account records by OracleAddressId__c for overlay territory resolution.
     *              Map key matches OrderLineContact__c.TASAddressId__c.
     * @param tasAddressIds TAS address ids from OrderLineContact__c.TASAddressId__c
     * @return Map of OracleAddressId__c to Account
     */
    public static Map<String, Account> selectAccountsByOracleAddressId(Set<String> tasAddressIds) {
        Map<String, Account> accountByOracleAddressId = new Map<String, Account>();

        if (tasAddressIds == null || tasAddressIds.isEmpty()) {
            return accountByOracleAddressId;
        }

        List<Account> rows = (List<Account>) SoqlQueryBuilder.fromObject('Account')
            .selectFields(
                new List<String>{
                    'Id',
                    'Name',
                    'AccountNumber',
                    'Type',
                    'ParentId',
                    'OracleAddressId__c'
                }
            )
            .whereField('OracleAddressId__c', 'IN', new List<String>(tasAddressIds))
            .whereField('OracleAddressId__c', '!=', null)
            .execute();

        for (Account accountRecord : rows) {
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

        return (List<Account>) SoqlQueryBuilder.fromObject('Account')
            .selectFields(
                new List<String>{
                    'Id',
                    'Name',
                    'AccountNumber',
                    'Type',
                    'ParentId',
                    'OracleAddressId__c'
                }
            )
            .whereField('ParentId', 'IN', new List<Id>(parentAccountIds))
            .execute();
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

        return (List<Account>) SoqlQueryBuilder.fromObject('Account')
            .selectFields(new List<String>{ 'Id', 'OracleAddressId__c' })
            .whereField('Id', 'IN', new List<Id>(accountIds))
            .whereField('OracleAddressId__c', '!=', null)
            .execute();
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
        String searchTerm = String.isBlank(accountSearchKey)
            ? null
            : '%' + accountSearchKey.trim() + '%';
        Boolean hasSearchTerm = String.isNotBlank(accountSearchKey);
        Boolean hasAccountType = String.isNotBlank(accountType);

        if (!hasSearchTerm && !hasAccountType) {
            return (List<Account>) SoqlQueryBuilder.fromObject('Account')
                .selectFields(new List<String>{ 'Id', 'Name', 'AccountNumber', 'Type' })
                .orderBy('Name')
                .limitTo(5000)
                .execute();
        }

        SoqlQueryBuilder builder = SoqlQueryBuilder.fromObject('Account')
            .selectFields(new List<String>{ 'Id', 'Name', 'AccountNumber', 'Type' });

        if (hasSearchTerm && hasAccountType) {
            return (List<Account>) builder
                .whereField('Name', 'LIKE', searchTerm)
                .whereField('AccountNumber', 'LIKE', searchTerm)
                .whereEquals('Type', accountType)
                .withFilterLogic('((1 OR 2) AND 3)')
                .orderBy('Name')
                .limitTo(5000)
                .execute();
        }

        if (hasSearchTerm) {
            return (List<Account>) builder
                .whereField('Name', 'LIKE', searchTerm)
                .whereField('AccountNumber', 'LIKE', searchTerm)
                .withFilterLogic('(1 OR 2)')
                .orderBy('Name')
                .limitTo(5000)
                .execute();
        }

        return (List<Account>) builder
            .whereEquals('Type', accountType)
            .orderBy('Name')
            .limitTo(5000)
            .execute();
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

        return (Account) SoqlQueryBuilder.fromObject('Account')
            .selectFields(
                new List<String>{ 'Id', 'OracleAddressId__c', 'RecordType.DeveloperName' }
            )
            .whereEquals('Id', accountId)
            .first();
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

        return (List<Account>) SoqlQueryBuilder.fromObject('Account')
            .selectFields(new List<String>{ 'Id', 'OwnerId' })
            .whereField('OwnerId', 'IN', new List<Id>(ownerIds))
            .execute();
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

        return (List<Account>) SoqlQueryBuilder.fromObject('Account')
            .selectFields(
                new List<String>{ 'Id', 'Name', 'OracleAddressId__c', 'ParentId' }
            )
            .whereEquals('ParentId', parentAccountId)
            .whereField('OracleAddressId__c', '!=', null)
            .execute();
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

        return (List<Account>) SoqlQueryBuilder.fromObject('Account')
            .selectFields(
                new List<String>{ 'Id', 'Name', 'OracleAddressId__c', 'ParentId' }
            )
            .whereField('ParentId', 'IN', new List<Id>(parentAccountIds))
            .whereField('OracleAddressId__c', '!=', null)
            .execute();
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

        return (List<Account>) SoqlQueryBuilder.fromObject('Account')
            .selectFields(
                new List<String>{
                    'Id',
                    'Name',
                    'Type',
                    'ParentId',
                    'ShiptoAddressStatus__c',
                    'BillingStreet',
                    'BillingCity',
                    'BillingState',
                    'BillingStateCode',
                    'BillingPostalCode',
                    'BillingCountry',
                    'BillingCountryCode'
                }
            )
            .whereEquals('ParentId', parentAccountId)
            .whereEquals('Type', 'Address')
            .whereField('ShiptoAddressStatus__c', 'IN', new List<String>{ 'Active', 'Primary' })
            .orderByDesc('ShiptoAddressStatus__c')
            .orderBy('Name')
            .execute();
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

        List<Account> rows = (List<Account>) SoqlQueryBuilder.fromObject('Account')
            .selectFields(
                new List<String>{
                    'Id',
                    'AccountNumber',
                    'OrgIDs__c',
                    'OracleAddressId__c',
                    'Type',
                    'RecordType.DeveloperName',
                    'Price_List__c',
                    'Price_List__r.Price_List_ID__c',
                    'Parent.OrgIDs__c',
                    'Parent.AccountNumber'
                }
            )
            .whereField('Id', 'IN', new List<Id>(accountIds))
            .execute();
        return new Map<Id, Account>(rows);
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

        return (List<Account>) SoqlQueryBuilder.fromObject('Account')
            .selectFields(
                new List<String>{
                    'Id',
                    'AccountNumber',
                    'OrgIDs__c',
                    'OracleAddressId__c',
                    'Type',
                    'RecordType.DeveloperName',
                    'Price_List__c',
                    'Price_List__r.Price_List_ID__c',
                    'Parent.OrgIDs__c',
                    'Parent.AccountNumber',
                    'ShiptoAddressStatus__c'
                }
            )
            .whereEquals('ParentId', parentAccountId)
            .whereEquals('Type', 'Address')
            .whereField('AccountNumber', '!=', null)
            .whereField('ShiptoAddressStatus__c', 'IN', new List<String>{ 'Active', 'Primary' })
            .orderByDesc('ShiptoAddressStatus__c')
            .orderByDesc('LastModifiedDate')
            .limitTo(50)
            .execute();
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

    /**
     * @description GW-2710 - Address accounts for Tech Account Alignment, matched by Oracle Address Id.
     * @param oracleAddressIds Address IDs from the upload file.
     * @return Address accounts, including the parent fields the distributor check reads.
     */
    public static List<Account> selectAddressAccountsByOracleAddressIds(Set<String> oracleAddressIds) {
        if (oracleAddressIds == null || oracleAddressIds.isEmpty()) {
            return new List<Account>();
        }
        List<String> addressIds = new List<String>();
        addressIds.addAll(oracleAddressIds);
        return (List<Account>) new AccountSelector()
            .selectFields(
                new List<String>{
                    'Id',
                    'Name',
                    'Type',
                    'ParentId',
                    'OracleAddressId__c',
                    'ShiptoAddressStatus__c',
                    'BilltoAddressStatus__c',
                    'NotServiceable__c',
                    'SMI__c',
                    'CustomerProfileClass__c',
                    'Parent.Type',
                    'Parent.SMI__c',
                    'Parent.CustomerProfileClass__c'
                }
            )
            .whereEquals('Type', 'Address')
            .whereIn('OracleAddressId__c', addressIds)
            .execute();
    }

    /**
     * @description GW-1509 - Account fields used by Create Return Order account details.
     * @param accountId Account Id
     * @return Matching Account rows (LIMIT 1)
     */
    public static List<Account> selectForCreateReturnOrderById(Id accountId) {
        if (accountId == null) {
            return new List<Account>();
        }
        return (List<Account>) SoqlQueryBuilder.fromObject('Account')
            .selectFields(
                new List<String>{
                    'Id',
                    'Name',
                    'SystemID__c',
                    'OrgIDs__c',
                    'BillingState'
                }
            )
            .whereEquals('Id', accountId)
            .limitTo(1)
            .execute();
    }

}