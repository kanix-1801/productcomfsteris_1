/**
 * @description Selector class for the Contact SObject.
 *              Centralizes all SOQL queries for Contacts.
 *              Enforces security via WITH SECURITY_ENFORCED.
 */
public with sharing class ContactsSelector {

    private static final String BASE_FIELDS =
        'Id, FirstName, LastName, Email, Phone, Title, Department, ' +
        'AccountId, OwnerId, MailingStreet, MailingCity, MailingState, ' +
        'MailingPostalCode, MailingCountry, Birthdate, LeadSource, ' +
        'CreatedDate, LastModifiedDate';

    /**
     * @description Retrieves Contact records by their Ids.
     * @param ids Set of Contact Ids to query.
     * @return List of Contact records matching the given Ids.
     */
    public static List<Contact> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<Contact>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM Contact' +
            ' WHERE Id IN :ids' +
            ' WITH SECURITY_ENFORCED'
        );
    }
    
    /**
     * @description
     * GC-2868 AC6 - Selects Contacts associated with the supplied
     * Customer/Address Account IDs.
     *
     * @param accountIdSet Customer/Address Account IDs.
     * @return Contacts associated with the Accounts.
     */
    public static List<Contact> selectByAccountIds(
        Set<Id> accountIdSet
    ) {
        if (
            accountIdSet == null ||
            accountIdSet.isEmpty()
        ) {
            return new List<Contact>();
        }

        return [
            SELECT Id,Name,FirstName,LastName,AccountId,Account.Name,Account.Type,
                   Email, Phone, MobilePhone,Title,Department,OwnerId,Owner.Name,
                   MailingCity,MailingState,MailingCountry,CreatedDate,LastModifiedDate
            FROM Contact WHERE AccountId IN :accountIdSet WITH SECURITY_ENFORCED
            ORDER BY Account.Name ASC,LastName ASC,FirstName ASC
        ];
    }
  

    /**
     * @description Retrieves Contact records by Account Id.
     * @param accountIds Set of Account Ids to filter by.
     * @return List of Contact records for the given Accounts.
     */
    public static List<Contact> selectByAccountId(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<Contact>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM Contact' +
            ' WHERE AccountId IN :accountIds' +
            ' WITH SECURITY_ENFORCED' +
            ' ORDER BY LastName ASC, FirstName ASC'
        );
    }

    /**
     * @description Retrieves Contact records by Email.
     * @param emails Set of email addresses to filter by.
     * @return List of Contact records matching the given emails.
     */
    public static List<Contact> selectByEmail(Set<String> emails) {
        if (emails == null || emails.isEmpty()) {
            return new List<Contact>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM Contact' +
            ' WHERE Email IN :emails' +
            ' WITH SECURITY_ENFORCED'
        );
    }
}