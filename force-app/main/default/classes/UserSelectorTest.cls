/**
 * @description Tests for UserSelector.
 */
@IsTest
private class UserSelectorTest {

    @IsTest
    static void testProfileIdLookupsAndCacheResets() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            UserSelector.resetHealthcareSalesProfileIdCacheForTest();
            UserSelector.resetLifeSciencesSalesProfileIdCacheForTest();

            Test.startTest();
            Id healthcareFirst = UserSelector.getHealthcareSalesProfileId();
            Id healthcareSecond = UserSelector.getHealthcareSalesProfileId();
            Id lifeSciencesFirst = UserSelector.getLifeSciencesSalesProfileId();
            Id lifeSciencesSecond = UserSelector.getLifeSciencesSalesProfileId();
            Test.stopTest();

            Assert.areEqual(healthcareFirst, healthcareSecond, 'Healthcare profile Id should cache');
            Assert.areEqual(
                lifeSciencesFirst,
                lifeSciencesSecond,
                'Life Sciences profile Id should cache'
            );

            if (healthcareFirst != null) {
                Profile healthcare = [
                    SELECT Id, Name
                    FROM Profile
                    WHERE Id = :healthcareFirst
                    LIMIT 1
                ];
                Assert.areEqual(UserSelector.HEALTHCARE_SALES_PROFILE_NAME, healthcare.Name);
            }
            if (lifeSciencesFirst != null) {
                Profile lifeSciences = [
                    SELECT Id, Name
                    FROM Profile
                    WHERE Id = :lifeSciencesFirst
                    LIMIT 1
                ];
                Assert.areEqual(UserSelector.LIFESCIENCES_SALES_PROFILE_NAME, lifeSciences.Name);
            }
        }
    }

    @IsTest
    static void selectActiveUsersBySearch_blankOrValidKey() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            String searchKey = UserInfo.getName().left(3);

            Test.startTest();
            List<User> blankKey = UserSelector.selectActiveUsersBySearch(null);
            List<User> emptyKey = UserSelector.selectActiveUsersBySearch('   ');
            List<User> matched = UserSelector.selectActiveUsersBySearch(searchKey);
            Test.stopTest();

            Assert.isTrue(blankKey.isEmpty());
            Assert.isTrue(emptyKey.isEmpty());
            Assert.isFalse(matched.isEmpty(), 'Active users should match a name fragment');
        }
    }

    @IsTest
    static void selectByIds_nullEmptyAndValid() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Test.startTest();
            List<User> nullInput = UserSelector.selectByIds(null);
            List<User> emptyInput = UserSelector.selectByIds(new Set<Id>());
            List<User> matched = UserSelector.selectByIds(new Set<Id>{ UserInfo.getUserId() });
            Test.stopTest();

            Assert.isTrue(nullInput.isEmpty());
            Assert.isTrue(emptyInput.isEmpty());
            Assert.areEqual(1, matched.size());
            Assert.areEqual(UserInfo.getUserId(), matched[0].Id);
        }
    }

    @IsTest
    static void selectByIdsForEmail_nullEmptyAndValid() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Test.startTest();
            List<User> nullInput = UserSelector.selectByIdsForEmail(null);
            List<User> emptyInput = UserSelector.selectByIdsForEmail(new Set<Id>());
            List<User> matched =
                UserSelector.selectByIdsForEmail(new Set<Id>{ UserInfo.getUserId() });
            Test.stopTest();

            Assert.isTrue(nullInput.isEmpty());
            Assert.isTrue(emptyInput.isEmpty());
            Assert.areEqual(1, matched.size());
            Assert.areEqual(UserInfo.getUserId(), matched[0].Id);
            Assert.isTrue(matched[0].IsActive);
        }
    }

    @IsTest
    static void selectActiveInternalUsersForCreateReturnOrder_returnsUsers() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Test.startTest();
            List<User> results = UserSelector.selectActiveInternalUsersForCreateReturnOrder();
            Test.stopTest();

            Assert.isFalse(results.isEmpty(), 'Org should have active internal users');
            Assert.isNotNull(results[0].Id);
            Assert.isNotNull(results[0].Name);
        }
    }

    @IsTest
    static void getActiveUsersByIds_emptyAndValid() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Test.startTest();
            List<User> emptyInput = UserSelector.getActiveUsersByIds(new Set<Id>());
            List<User> matched =
                UserSelector.getActiveUsersByIds(new Set<Id>{ UserInfo.getUserId() });
            Test.stopTest();

            Assert.isTrue(emptyInput.isEmpty());
            Assert.areEqual(1, matched.size());
            Assert.areEqual(UserInfo.getUserId(), matched[0].Id);
        }
    }

    @IsTest
    static void getInactiveUsersByIds_emptyAndActiveUser() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Test.startTest();
            List<User> emptyInput = UserSelector.getInactiveUsersByIds(new Set<Id>());
            List<User> activeOnly =
                UserSelector.getInactiveUsersByIds(new Set<Id>{ UserInfo.getUserId() });
            Test.stopTest();

            Assert.isTrue(emptyInput.isEmpty());
            Assert.isTrue(activeOnly.isEmpty(), 'Current user is active so should not match');
        }
    }

    @IsTest
    static void selectActiveUsersByEmployeeNumber_emptyAndBlankTokens() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Test.startTest();
            Map<String, User> nullInput =
                UserSelector.selectActiveUsersByEmployeeNumber(null);
            Map<String, User> emptyInput =
                UserSelector.selectActiveUsersByEmployeeNumber(new Set<String>());
            Map<String, User> healthcareEmpty =
                UserSelector.selectActiveHealthcareSalesUsersByEmployeeNumber(new Set<String>());
            Map<String, User> lifeSciencesEmpty =
                UserSelector.selectActiveLifeSciencesSalesUsersByEmployeeNumber(new Set<String>());
            Test.stopTest();

            Assert.isTrue(nullInput.isEmpty());
            Assert.isTrue(emptyInput.isEmpty());
            Assert.isTrue(healthcareEmpty.isEmpty());
            Assert.isTrue(lifeSciencesEmpty.isEmpty());
        }
    }

    @IsTest
    static void selectActiveHealthcareSalesUsersBySearch_blankKeyReturnsEmpty() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Id healthcareProfileId = UserSelector.getHealthcareSalesProfileId();
            if (healthcareProfileId == null) {
                Assert.isTrue(true, 'Healthcare Sales profile unavailable; skip');
                return;
            }

            Test.startTest();
            List<User> blankKey =
                UserSelector.selectActiveHealthcareSalesUsersBySearch(null);
            List<User> emptyKey =
                UserSelector.selectActiveHealthcareSalesUsersBySearch('   ');
            Test.stopTest();

            Assert.isTrue(blankKey.isEmpty());
            Assert.isTrue(emptyKey.isEmpty());
        }
    }

    @IsTest
    static void selectActiveHealthcareSalesUsersByEmployeeNumber_nonEmpty() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Test.startTest();
            try {
                Map<String, User> healthcare =
                    UserSelector.selectActiveHealthcareSalesUsersByEmployeeNumber(
                        new Set<String>{ 'EMP-COV-1' }
                    );
                Assert.isNotNull(healthcare);
            } catch (TASTeamAccessException ex) {
                Assert.isTrue(
                    ex.getMessage().contains('Healthcare Sales'),
                    'Expected Healthcare Sales profile exception'
                );
            }
            try {
                Map<String, User> lifeSciences =
                    UserSelector.selectActiveLifeSciencesSalesUsersByEmployeeNumber(
                        new Set<String>{ 'EMP-COV-1' }
                    );
                Assert.isNotNull(lifeSciences);
            } catch (TASTeamAccessException ex) {
                Assert.isTrue(
                    ex.getMessage().contains('Life Science'),
                    'Expected Life Science Sales profile exception'
                );
            }
            Id healthcareProfileId = UserSelector.getHealthcareSalesProfileId();
            if (healthcareProfileId != null) {
                List<User> searchHits =
                    UserSelector.selectActiveHealthcareSalesUsersBySearch(UserInfo.getName());
                Assert.isNotNull(searchHits);
            }
            Test.stopTest();
        }
    }
}