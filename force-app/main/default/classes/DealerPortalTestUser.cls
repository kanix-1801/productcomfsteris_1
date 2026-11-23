/**
 * @description Creates the Healthcare Dealer user that the dealer portal tests run as.
 * The user receives only DealerPortalUser. Dealer Admin is a separate persona and is not assigned here.
 */
@IsTest
public class DealerPortalTestUser {
    public static User create(String key) {
        User accountOwner;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            accountOwner = insertAccountOwner(key);
        }
        Account dealerAccount = insertPartnerAccount(accountOwner, key);
        Contact dealerContact = insertDealerContact(accountOwner, dealerAccount);
        User dealer;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            dealer = insertDealerUser(dealerContact, key);
            assignPortalAccess(dealer.Id);
        }
        return dealer;
    }

    public static User getUser(String key) {
        return [
            SELECT Id, Contact.AccountId
            FROM User
            WHERE Username = :username(key)
            LIMIT 1
        ];
    }

    private static User insertAccountOwner(String key) {
        UserRole dealerRole = new UserRole(
            Name = 'Dealer Test ' + key,
            DeveloperName = 'DealerTst' + key
        );
        insert dealerRole;
        User accountOwner = new User(
            Alias = 'downer',
            Email = 'dealer.owner.' + key + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Dealer Owner',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'America/New_York',
            UserRoleId = dealerRole.Id,
            Username = 'dealer.owner.' + key + '.' + UserInfo.getOrganizationId() + '@example.com'
        );
        insert accountOwner;
        return accountOwner;
    }

    private static Account insertPartnerAccount(User accountOwner, String key) {
        Account dealerAccount;
        System.runAs(accountOwner) {
            dealerAccount = new Account(Name = 'Dealer Portal ' + key);
            insert dealerAccount;
            dealerAccount.IsPartner = true;
            update dealerAccount;
        }
        return dealerAccount;
    }

    private static Contact insertDealerContact(User accountOwner, Account dealerAccount) {
        Contact dealerContact;
        System.runAs(accountOwner) {
            dealerContact = new Contact(
                LastName = 'Portal Dealer',
                AccountId = dealerAccount.Id,
                Email = 'portal.dealer@example.com'
            );
            insert dealerContact;
        }
        return dealerContact;
    }

    private static User insertDealerUser(Contact dealerContact, String key) {
        Profile dealerProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Healthcare Dealer'
            LIMIT 1
        ];
        User dealer = new User(
            Alias = 'dport',
            Email = 'portal.dealer.' + key + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Portal Dealer',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = dealerProfile.Id,
            TimeZoneSidKey = 'America/New_York',
            Username = username(key),
            ContactId = dealerContact.Id,
            CommunityNickname = 'dport' + key + UserInfo.getOrganizationId().right(6)
        );
        insert dealer;
        return dealer;
    }

    private static void assignPortalAccess(Id dealerUserId) {
        Map<String, PermissionSet> permissionSetsByName = new Map<String, PermissionSet>();
        for (PermissionSet permissionSet : [
            SELECT Id, Name
            FROM PermissionSet
            WHERE Name = 'DealerPortalUser'
        ]) {
            permissionSetsByName.put(permissionSet.Name, permissionSet);
        }
        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        for (PermissionSet permissionSet : permissionSetsByName.values()) {
            assignments.add(new PermissionSetAssignment(
                AssigneeId = dealerUserId,
                PermissionSetId = permissionSet.Id
            ));
        }
        insert assignments;
    }

    private static String username(String key) {
        return 'dealer.' + key + '.' + UserInfo.getOrganizationId() + '@example.com';
    }
}