/**
 * @description GCL-79 - Tests for the Life Sciences methods added to UserSelector.
 *              Healthcare UserSelector methods are not exercised here.
 */
@IsTest
private class LSUserSelectorTest {

    @IsTest
    static void lifeSciencesUserSearchReturnsOnlyThatProfile() {
        User lifeSciencesUser = insertUser(lifeSciencesProfileId(), 'lssearch', true);
        User otherUser = insertUser(minimumAccessProfileId(), 'other', true);

        Test.startTest();
        List<User> matches = UserSelector.selectActiveLifeSciencesSalesUsersBySearch(lifeSciencesUser.LastName);
        List<User> byId = UserSelector.selectActiveLifeSciencesSalesUsersByIds(
            new Set<Id>{ lifeSciencesUser.Id, otherUser.Id }
        );
        Test.stopTest();

        System.assertEquals(1, matches.size());
        System.assertEquals(lifeSciencesUser.Id, matches[0].Id);
        System.assertEquals(1, byId.size());
        System.assertEquals(lifeSciencesUser.Id, byId[0].Id);
    }

    @IsTest
    static void lifeSciencesUserMethodsRejectEmptyCriteria() {
        Test.startTest();
        System.assertEquals(0, UserSelector.selectActiveLifeSciencesSalesUsersBySearch(null).size());
        System.assertEquals(0, UserSelector.selectActiveLifeSciencesSalesUsersBySearch('   ').size());
        System.assertEquals(0, UserSelector.selectActiveLifeSciencesSalesUsersByIds(null).size());
        System.assertEquals(0, UserSelector.selectActiveLifeSciencesSalesUsersByIds(new Set<Id>()).size());
        Test.stopTest();
    }

    private static Id lifeSciencesProfileId() {
        return [SELECT Id FROM Profile WHERE Name = :UserSelector.LIFESCIENCES_SALES_PROFILE_NAME LIMIT 1].Id;
    }

    private static Id minimumAccessProfileId() {
        return [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1].Id;
    }

    private static User insertUser(Id profileId, String seed, Boolean active) {
        String uniqueSeed = seed + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User userRecord = new User(
            FirstName = 'LS',
            LastName = 'Selector' + uniqueSeed.right(6),
            Alias = ('l' + uniqueSeed).left(8),
            Email = 'ls.selector.' + uniqueSeed + '@example.com',
            Username = 'ls.selector.' + uniqueSeed + '@example.com',
            CommunityNickname = ('lssel' + uniqueSeed).left(40),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileId,
            IsActive = active
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert userRecord;
        }
        return userRecord;
    }
}