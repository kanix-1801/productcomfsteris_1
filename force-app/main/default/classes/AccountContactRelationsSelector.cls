/**
 * @description Selector class for the AccountContactRelation SObject.
 *              Centralizes all SOQL queries for AccountContactRelations.
 *              Enforces security via WITH SECURITY_ENFORCED.
 */
public with sharing class AccountContactRelationsSelector {

    private static final String BASE_FIELDS =
        'Id, AccountId, ContactId, Roles, IsDirect, IsActive, ' +
        'StartDate, EndDate, CreatedDate, LastModifiedDate';

    /**
     * @description Retrieves AccountContactRelation records by their Ids.
     * @param ids Set of AccountContactRelation Ids to query.
     * @return List of AccountContactRelation records matching the given Ids.
     */
    public static List<AccountContactRelation> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<AccountContactRelation>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM AccountContactRelation' +
            ' WHERE Id IN :ids' +
            ' WITH SECURITY_ENFORCED'
        );
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
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM AccountContactRelation' +
            ' WHERE AccountId IN :accountIds' +
            ' WITH SECURITY_ENFORCED' +
            ' ORDER BY CreatedDate ASC'
        );
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
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM AccountContactRelation' +
            ' WHERE ContactId IN :contactIds' +
            ' WITH SECURITY_ENFORCED' +
            ' ORDER BY CreatedDate ASC'
        );
    }
}