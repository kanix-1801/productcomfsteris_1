/**
 * @description GCL-79 - Tests for the Life Sciences method added to AccountTeamMemberSelector.
 *              Healthcare Account Team methods are not exercised here.
 */
@IsTest
private class LSAccountTeamMemberSelectorTest {

    @IsTest
    static void lifeSciencesTeamLookupReturnsTheExistingRow() {
        Account accountRecord = insertAccount();
        User teamUser = insertUser();
        insert new AccountTeamMember(
            AccountId = accountRecord.Id,
            UserId = teamUser.Id,
            TeamMemberRole = 'Sales'
        );

        Test.startTest();
        List<AccountTeamMember> matches = AccountTeamMemberSelector.selectLifeSciencesByAccountsAndUsers(
            new Set<Id>{ accountRecord.Id },
            new Set<Id>{ teamUser.Id }
        );
        List<AccountTeamMember> otherUser = AccountTeamMemberSelector.selectLifeSciencesByAccountsAndUsers(
            new Set<Id>{ accountRecord.Id },
            new Set<Id>{ UserInfo.getUserId() }
        );
        Test.stopTest();

        System.assertEquals(1, matches.size());
        System.assertEquals(accountRecord.Id, matches[0].AccountId);
        System.assertEquals(teamUser.Id, matches[0].UserId);
        System.assertEquals(0, otherUser.size());
    }

    @IsTest
    static void lifeSciencesTeamLookupRejectsEmptyCriteria() {
        Test.startTest();
        System.assertEquals(0, AccountTeamMemberSelector.selectLifeSciencesByAccountsAndUsers(null, new Set<Id>{ UserInfo.getUserId() }).size());
        System.assertEquals(0, AccountTeamMemberSelector.selectLifeSciencesByAccountsAndUsers(new Set<Id>(), new Set<Id>{ UserInfo.getUserId() }).size());
        System.assertEquals(0, AccountTeamMemberSelector.selectLifeSciencesByAccountsAndUsers(new Set<Id>{ UserInfo.getUserId() }, null).size());
        System.assertEquals(0, AccountTeamMemberSelector.selectLifeSciencesByAccountsAndUsers(new Set<Id>{ UserInfo.getUserId() }, new Set<Id>()).size());
        Test.stopTest();
    }

    private static Account insertAccount() {
        Account accountRecord = new Account(
            Name = 'LS Team Selector Customer',
            AccountNumber = 'LS-TEAM-1',
            Type = 'Customer',
            CustomerClassCode__c = 'SC'
        );
        Database.insert(accountRecord, allowDuplicates());
        return accountRecord;
    }

    private static User insertUser() {
        Profile lifeSciencesProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = :UserSelector.LIFESCIENCES_SALES_PROFILE_NAME
            LIMIT 1
        ];
        String uniqueSeed = 'team' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User userRecord = new User(
            FirstName = 'LS',
            LastName = 'Team' + uniqueSeed.right(6),
            Alias = ('t' + uniqueSeed).left(8),
            Email = 'ls.team.' + uniqueSeed + '@example.com',
            Username = 'ls.team.' + uniqueSeed + '@example.com',
            CommunityNickname = ('lsteam' + uniqueSeed).left(40),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = lifeSciencesProfile.Id,
            IsActive = true
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert userRecord;
        }
        return userRecord;
    }

    private static Database.DMLOptions allowDuplicates() {
        Database.DMLOptions options = new Database.DMLOptions();
        options.DuplicateRuleHeader.allowSave = true;
        return options;
    }
}