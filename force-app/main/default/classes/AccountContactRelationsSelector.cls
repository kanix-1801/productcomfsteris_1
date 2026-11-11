/**
 * @description Selector class for the AccountContactRelation SObject.
 *              Centralizes all SOQL queries for AccountContactRelations.
 *              Queries use SoqlQueryBuilder (USER_MODE).
 */
public with sharing class AccountContactRelationsSelector {

    private static final List<String> BASE_FIELDS = new List<String>{
        'Id',
        'AccountId',
        'ContactId',
        'Roles',
        'IsDirect',
        'IsActive',
        'StartDate',
        'EndDate',
        'CreatedDate',
        'LastModifiedDate'
    };

    /**
     * @description Retrieves AccountContactRelation records by their Ids.
     * @param ids Set of AccountContactRelation Ids to query.
     * @return List of AccountContactRelation records matching the given Ids.
     */
    public static List<AccountContactRelation> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<AccountContactRelation>();
        }
        return (List<AccountContactRelation>) SoqlQueryBuilder.fromObject('AccountContactRelation')
            .selectFields(BASE_FIELDS)
            .whereField('Id', 'IN', new List<Id>(ids))
            .execute();
    }

    /**
     * @description Retrieves AccountContactRelation records by Account Id.
     * @param accountIds Set of Account Ids to filter by.
     * @return List of AccountContactRelation records for the given Accounts.
     */
    public static List<AccountContactRelation> selectByAccountId(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<AccountContactRelation>();
        }
        return (List<AccountContactRelation>) SoqlQueryBuilder.fromObject('AccountContactRelation')
            .selectFields(BASE_FIELDS)
            .whereField('AccountId', 'IN', new List<Id>(accountIds))
            .orderBy('CreatedDate')
            .execute();
    }

    /**
     * @description Retrieves AccountContactRelation records by Contact Id.
     * @param contactIds Set of Contact Ids to filter by.
     * @return List of AccountContactRelation records for the given Contacts.
     */
    public static List<AccountContactRelation> selectByContactId(Set<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            return new List<AccountContactRelation>();
        }
        return (List<AccountContactRelation>) SoqlQueryBuilder.fromObject('AccountContactRelation')
            .selectFields(BASE_FIELDS)
            .whereField('ContactId', 'IN', new List<Id>(contactIds))
            .orderBy('CreatedDate')
            .execute();
    }

    /**
     * @description GW-1509 - Existing AccountContactRelation for Create Return Order contact linking.
     * @param accountId Account Id
     * @param contactId Contact Id
     * @return Matching relation rows (LIMIT 1)
     */
    public static List<AccountContactRelation> selectByAccountAndContact(Id accountId, Id contactId) {
        if (accountId == null || contactId == null) {
            return new List<AccountContactRelation>();
        }
        return (List<AccountContactRelation>) SoqlQueryBuilder.fromObject('AccountContactRelation')
            .selectFields(new List<String>{ 'Id' })
            .whereEquals('AccountId', accountId)
            .whereEquals('ContactId', contactId)
            .limitTo(1)
            .execute();
    }

    /**
     * @description GW-1509 - Active related Contact Ids for an Account.
     * @param accountId Account Id
     * @return Matching AccountContactRelation rows
     */
    public static List<AccountContactRelation> selectActiveByAccountId(Id accountId) {
        if (accountId == null) {
            return new List<AccountContactRelation>();
        }
        return (List<AccountContactRelation>) SoqlQueryBuilder.fromObject('AccountContactRelation')
            .selectFields(new List<String>{ 'ContactId' })
            .whereEquals('AccountId', accountId)
            .whereEquals('IsActive', true)
            .whereField('ContactId', '!=', null)
            .execute();
    }

}