/**
 * Author: Akash Dahinde
 * Story: GC-2868
 *
 * @description
 * Retrieves Contacts from child Accounts related to the current
 * IDN, GPO, or Customer Account through:
 *
 * 1. Account.ParentId
 * 2. AccountAccountRelationship__c
 *
 * IDN      -> ParentId + AAR
 * GPO      -> ParentId + AAR
 * Customer -> ParentId + AAR
 */
public with sharing class ChildAccountContactController {

    /**
     * @description Returns Contacts from all related child Accounts.
     * @param accountId Current IDN, GPO, or Customer Account ID.
     * @return ChildAccountContactResponse.
     */
    @AuraEnabled(cacheable=true)
    public static ChildAccountContactResponse getChildAccountContacts(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }

        ChildAccountContactResponse response = initializeResponse();
        Set<Id> currentAccountIds = new Set<Id>{ accountId };
        List<Account> currentAccounts = AccountSelector.selectByIds(currentAccountIds);

        if (currentAccounts.isEmpty()) {
            throw new AuraHandledException('The Account does not exist or you do not have access.');
        }

        Account currentAccount = currentAccounts[0];
        response.enterpriseAccountId = currentAccount.Id;
        response.enterpriseAccountName = currentAccount.Name;
        response.enterpriseAccountType = currentAccount.Type;

        if (!EnterpriseAccountEligibilityService.isSupportedAccount(currentAccount)) {
            return response;
        }

        response.displayComponent = true;

        Set<Id> childAccountIds = resolveChildAccountIds(currentAccountIds);
        response.childAccountCount = childAccountIds.size();

        if (childAccountIds.isEmpty()) {
            return response;
        }

        List<Contact> childContacts = ContactsSelector.selectByAccountIds(childAccountIds);
        Set<Id> accountsWithContacts = new Set<Id>();

        for (Contact contactRecord : childContacts) {
            response.contacts.add(createContactRow(contactRecord));

            if (contactRecord.AccountId != null) {
                accountsWithContacts.add(contactRecord.AccountId);
            }
        }

        response.accountsWithContactsCount = accountsWithContacts.size();
        response.totalContactCount = response.contacts.size();
        return response;
    }

    /**
     * @description Resolves unique child Account IDs through ParentId and AAR.
     * @param parentAccountIds Parent Account IDs.
     * @return Unique child Account IDs.
     */
    private static Set<Id> resolveChildAccountIds(Set<Id> parentAccountIds) {
        Set<Id> childAccountIds = new Set<Id>();

        for (Account childAccount : AccountSelector.selectByParentIds(parentAccountIds)) {
            childAccountIds.add(childAccount.Id);
        }

        List<AccountAccountRelationship__c> relationships =
            AccountAccountRelationshipSelector.selectMembersByParentIds(parentAccountIds);

        for (AccountAccountRelationship__c relationship : relationships) {
            if (relationship.ChildAccount__c != null) {
                childAccountIds.add(relationship.ChildAccount__c);
            }
        }

        return childAccountIds;
    }

    /**
     * @description Converts Contact to the LWC response row.
     * @param contactRecord Contact record.
     * @return ContactRow.
     */
    private static ContactRow createContactRow(Contact contactRecord) {
        ContactRow row = new ContactRow();
        row.contactId = contactRecord.Id;
        row.contactName = contactRecord.Name;
        row.firstName = contactRecord.FirstName;
        row.lastName = contactRecord.LastName;
        row.accountId = contactRecord.AccountId;
        row.accountName = contactRecord.Account != null ? contactRecord.Account.Name : null;
        row.accountType = contactRecord.Account != null ? contactRecord.Account.Type : null;
        row.email = contactRecord.Email;
        row.phone = contactRecord.Phone;
        row.mobilePhone = contactRecord.MobilePhone;
        row.title = contactRecord.Title;
        row.department = contactRecord.Department;
        row.ownerId = contactRecord.OwnerId;
        row.ownerName = contactRecord.Owner != null ? contactRecord.Owner.Name : null;
        row.mailingCity = contactRecord.MailingCity;
        row.mailingState = contactRecord.MailingState;
        row.mailingCountry = contactRecord.MailingCountry;
        row.createdDate = contactRecord.CreatedDate;
        row.lastModifiedDate = contactRecord.LastModifiedDate;
        return row;
    }

    /**
     * @description Initializes response values.
     * @return ChildAccountContactResponse.
     */
    private static ChildAccountContactResponse initializeResponse() {
        ChildAccountContactResponse response = new ChildAccountContactResponse();
        response.displayComponent = false;
        response.resultLimitReached = false;
        response.childAccountCount = 0;
        response.accountsWithContactsCount = 0;
        response.totalContactCount = 0;
        response.contacts = new List<ContactRow>();
        return response;
    }

    public class ChildAccountContactResponse {
        @AuraEnabled public Boolean displayComponent;
        @AuraEnabled public Boolean resultLimitReached;
        @AuraEnabled public Id enterpriseAccountId;
        @AuraEnabled public String enterpriseAccountName;
        @AuraEnabled public String enterpriseAccountType;
        @AuraEnabled public Integer childAccountCount;
        @AuraEnabled public Integer accountsWithContactsCount;
        @AuraEnabled public Integer totalContactCount;
        @AuraEnabled public List<ContactRow> contacts;
    }

    public class ContactRow {
        @AuraEnabled public Id contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String accountType;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String mobilePhone;
        @AuraEnabled public String title;
        @AuraEnabled public String department;
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String mailingCity;
        @AuraEnabled public String mailingState;
        @AuraEnabled public String mailingCountry;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Datetime lastModifiedDate;
    }
}