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

    /**
     * @description GW-5874 - Finds every Contact whose phone fields contain any of the numbers, in one SOSL search.
     *              Runs as a system search (see PhoneSearch): the caller strips fields the user cannot read.
     * @param phoneSet Normalized phone numbers (digits only)
     * @return Contacts with every phone field, Email and Account Name, ordered by Name
     */
    public static List<Contact> searchByPhones(Set<String> phoneSet) {
        if (phoneSet == null || phoneSet.isEmpty()) {
            return new List<Contact>();
        }
        return new PhoneSearch().search(String.join(new List<String>(phoneSet), ' OR '));
    }

    /**
     * @description GW-5874 - Contact Management from SMS must find a customer's Contact whatever the running
     *              user's record access (agent or Genesys integration user), so this one search runs without sharing.
     *              It is read-only and limited to phone matching; field access is enforced by the caller.
     */
    private without sharing class PhoneSearch {
        private List<Contact> search(String searchTerm) {
            List<List<SObject>> searchResultList = [
                FIND :searchTerm
                IN PHONE FIELDS
                RETURNING Contact(
                    Id, Name, Phone, MobilePhone, HomePhone, OtherPhone, AssistantPhone, Fax,
                    Email, AccountId, Account.Name
                    ORDER BY Name
                )
            ];
            return (List<Contact>) searchResultList[0];
        }
    }

    /**
     * @description GW-1509 - Contact Id/Name/Email for Create Return Order picklists.
     * @param contactIds Contact Ids
     * @return Matching Contacts ordered by Name
     */
    public static List<Contact> selectNamesAndEmailsByIds(Set<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            return new List<Contact>();
        }
        return (List<Contact>) SoqlQueryBuilder.fromObject('Contact')
            .selectFields(new List<String>{ 'Id', 'Name', 'Email' })
            .whereField('Id', 'IN', new List<Id>(contactIds))
            .orderBy('Name')
            .execute();
    }

    /**
     * @description GW-1509 - Contact Id/Name/Email for a newly created Create Return Order contact.
     * @param contactId Contact Id
     * @return Matching Contact rows (LIMIT 1)
     */
    public static List<Contact> selectNameAndEmailById(Id contactId) {
        if (contactId == null) {
            return new List<Contact>();
        }
        return (List<Contact>) SoqlQueryBuilder.fromObject('Contact')
            .selectFields(new List<String>{ 'Id', 'Name', 'Email' })
            .whereEquals('Id', contactId)
            .limitTo(1)
            .execute();
    }

    /**
     * @description GW-1509 - Contact Ids directly related to an Account.
     * @param accountId Account Id
     * @return Matching Contact rows (Id only)
     */
    public static List<Contact> selectIdsByAccountId(Id accountId) {
        if (accountId == null) {
            return new List<Contact>();
        }
        return (List<Contact>) SoqlQueryBuilder.fromObject('Contact')
            .selectFields(new List<String>{ 'Id' })
            .whereEquals('AccountId', accountId)
            .execute();
    }

    /**
     * @description GW-1509 - Contact name fields used for Create Return Order duplicate checks.
     * @param contactIds Contact Ids
     * @return Matching Contacts
     */
    public static List<Contact> selectNameFieldsByIds(Set<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            return new List<Contact>();
        }
        return (List<Contact>) SoqlQueryBuilder.fromObject('Contact')
            .selectFields(new List<String>{ 'Id', 'Name', 'FirstName', 'LastName' })
            .whereField('Id', 'IN', new List<Id>(contactIds))
            .execute();
    }

    /**
     * @description GW-1509 - Contact names for Create Return Order line summaries.
     * @param contactIds Contact Ids
     * @return Matching Contacts
     */
    public static List<Contact> selectNamesByIds(Set<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            return new List<Contact>();
        }
        return (List<Contact>) SoqlQueryBuilder.fromObject('Contact')
            .selectFields(new List<String>{ 'Id', 'Name' })
            .whereField('Id', 'IN', new List<Id>(contactIds))
            .execute();
    }

}