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

    @IsTest
    static void remainingUserSelectorMethodsExecute() {
        User lifeSciencesUser = insertUser(lifeSciencesProfileId(), 'lsrest', true);
        String employeeNumber = ('LS' + String.valueOf(Math.abs(Crypto.getRandomInteger()))).left(20);
        lifeSciencesUser.EmployeeNumber__c = employeeNumber;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update lifeSciencesUser;
        }

        UserSelector.resetLifeSciencesSalesProfileIdCacheForTest();
        UserSelector.resetHealthcareSalesProfileIdCacheForTest();

        System.assertNotEquals(null, UserSelector.getLifeSciencesSalesProfileId());
        System.assertEquals(
            UserSelector.getLifeSciencesSalesProfileId(),
            UserSelector.getLifeSciencesSalesProfileId()
        );
        System.assertNotEquals(null, UserSelector.getLifeSciencesSalesProfileIdForOverlay());
        Id healthcareProfileId = UserSelector.getHealthcareSalesProfileId();

        System.assertEquals(0, UserSelector.selectActiveUsersBySearch(null).size());
        System.assertEquals(0, UserSelector.selectActiveUsersBySearch('   ').size());
        UserSelector.selectActiveUsersBySearch(lifeSciencesUser.LastName);

        System.assertEquals(0, UserSelector.selectByIds(null).size());
        System.assertEquals(0, UserSelector.selectByIds(new Set<Id>()).size());
        System.assertEquals(1, UserSelector.selectByIds(new Set<Id>{ lifeSciencesUser.Id }).size());

        System.assertEquals(0, UserSelector.selectByIdsForEmail(null).size());
        System.assertEquals(0, UserSelector.selectByIdsForEmail(new Set<Id>()).size());
        System.assertEquals(1, UserSelector.selectByIdsForEmail(new Set<Id>{ lifeSciencesUser.Id }).size());

        System.assertEquals(0, UserSelector.selectActiveLifeSciencesSalesUsersByEmployeeNumber(null).size());
        System.assertEquals(0, UserSelector.selectActiveLifeSciencesSalesUsersByEmployeeNumber(new Set<String>()).size());
        Map<String, User> lifeSciencesByEmployee = UserSelector.selectActiveLifeSciencesSalesUsersByEmployeeNumber(
            new Set<String>{ employeeNumber }
        );
        System.assertEquals(lifeSciencesUser.Id, lifeSciencesByEmployee.get(employeeNumber).Id);

        System.assertEquals(0, UserSelector.selectActiveHealthcareSalesUsersByEmployeeNumber(null).size());
        System.assertEquals(0, UserSelector.selectActiveHealthcareSalesUsersByEmployeeNumber(new Set<String>()).size());
        System.assertEquals(0, UserSelector.selectActiveUsersByEmployeeNumber(null).size());
        if (healthcareProfileId != null) {
            UserSelector.selectActiveHealthcareSalesUsersByEmployeeNumber(new Set<String>{ employeeNumber });
            UserSelector.selectActiveUsersByEmployeeNumber(new Set<String>{ employeeNumber });
            UserSelector.selectActiveHealthcareSalesUsersBySearch(lifeSciencesUser.LastName);
        }
        System.assertEquals(0, UserSelector.selectActiveHealthcareSalesUsersBySearch(null).size());
        System.assertEquals(0, UserSelector.selectActiveHealthcareSalesUsersBySearch('   ').size());

        System.assertEquals(0, UserSelector.getInactiveUsersByIds(new Set<Id>()).size());
        UserSelector.getInactiveUsersByIds(new Set<Id>{ lifeSciencesUser.Id });
        System.assertEquals(0, UserSelector.getActiveUsersByIds(new Set<Id>()).size());
        System.assertEquals(1, UserSelector.getActiveUsersByIds(new Set<Id>{ lifeSciencesUser.Id }).size());

        System.assert(UserSelector.selectActiveInternalUsersForCreateReturnOrder().size() > 0);
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
        // GCL-79 : Overlay functionality implementation
        // Life Sciences Sales users require a role in the Life Sciences role hierarchy.
        if (profileId == lifeSciencesProfileId()) {
            userRecord.UserRoleId = [
                SELECT Id
                FROM UserRole
                WHERE PortalType = 'None'
                LIMIT 1
            ].Id;
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert userRecord;
        }
        return userRecord;
    }
}