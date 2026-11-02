/**
 * @description Tests for ROLIItemTypeandProductLineConfig. Custom Metadata Type records
 *              cannot be inserted via DML, so tests inject records through the @testVisible
 *              mock list and exercise the mock, override, and caching paths.
 * @author Dana Wolfe
 * @date 2026-07-29
 * @group Configuration Data
 */
@isTest
private class ROLIItemTypeandProductLineConfigTest {
    private static final String ITEM_TYPE = 'Serialized Part';
    private static final String PRODUCT_LINE = 'Surgical';
    private static final String RO_CATEGORY = 'Other (Serialized)';

    private static User buildTestUser() {
        User runningUser = [
            SELECT Id, ProfileId, TimeZoneSidKey, LocaleSidKey, EmailEncodingKey, LanguageLocaleKey
              FROM User
             WHERE Id = :UserInfo.getUserId()
        ];
        return new User(
            Alias = 'tstuser',
            Email = 'testuser@example.com.invalid',
            EmailEncodingKey = runningUser.EmailEncodingKey,
            LastName = 'TestUser',
            LanguageLocaleKey = runningUser.LanguageLocaleKey,
            LocaleSidKey = runningUser.LocaleSidKey,
            ProfileId = runningUser.ProfileId,
            TimeZoneSidKey = runningUser.TimeZoneSidKey,
            UserName = 'testuser.' + System.currentTimeMillis() + '@example.com.invalid'
        );
    }

    @isTest
    static void shouldReturnMockRecords_WhenInTestContext() {
        User testUser = buildTestUser();
        insert testUser;

        System.runAs(testUser) {
            // Given
            ROLIItemTypeandProductLineConfig.cmdtList_mock = new List<ROLIItemTypeandProductLine__mdt>{
                new ROLIItemTypeandProductLine__mdt(
                    DeveloperName = 'Mapping1',
                    ItemType__c = ITEM_TYPE,
                    ProductLine__c = PRODUCT_LINE,
                    ROCategory__c = RO_CATEGORY
                )
            };

            // When
            Test.startTest();
            List<ROLIItemTypeandProductLine__mdt> results = ROLIItemTypeandProductLineConfig.cmdtList;
            Test.stopTest();

            // Then
            Assert.areEqual(1, results.size(), 'Mock list should be returned in test context');
            Assert.areEqual(ITEM_TYPE, results[0].ItemType__c, 'ItemType should match injected mock');
            Assert.areEqual(PRODUCT_LINE, results[0].ProductLine__c, 'ProductLine should match injected mock');
            Assert.areEqual(RO_CATEGORY, results[0].ROCategory__c, 'ROCategory should match injected mock');
        }
    }

    @isTest
    static void shouldReturnEmptyList_WhenMockNotPopulated() {
        User testUser = buildTestUser();
        insert testUser;

        System.runAs(testUser) {
            // When
            Test.startTest();
            List<ROLIItemTypeandProductLine__mdt> results = ROLIItemTypeandProductLineConfig.cmdtList;
            Test.stopTest();

            // Then
            Assert.areEqual(0, results.size(), 'Empty mock list should yield no records');
        }
    }

    @isTest
    static void shouldQueryRealMetadata_WhenOverrideEnabled() {
        User testUser = buildTestUser();
        insert testUser;

        System.runAs(testUser) {
            // Given
            ROLIItemTypeandProductLineConfig.overrideIsRunningTest = true;

            // When
            Test.startTest();
            List<ROLIItemTypeandProductLine__mdt> results = ROLIItemTypeandProductLineConfig.cmdtList;
            Test.stopTest();

            // Then — real query path executes without error; result is org-dependent
            Assert.isNotNull(results, 'Override path should return a non-null list from the live query');
        }
    }

    @isTest
    static void shouldReuseCachedList_WhenAccessedTwice() {
        User testUser = buildTestUser();
        insert testUser;

        System.runAs(testUser) {
            // Given
            ROLIItemTypeandProductLineConfig.overrideIsRunningTest = true;

            // When
            Test.startTest();
            List<ROLIItemTypeandProductLine__mdt> firstCall = ROLIItemTypeandProductLineConfig.cmdtList;
            List<ROLIItemTypeandProductLine__mdt> secondCall = ROLIItemTypeandProductLineConfig.cmdtList;
            Test.stopTest();

            // Then — second access returns the same cached instance, proving no re-query
            Assert.isTrue(firstCall === secondCall, 'Second access should return the cached list instance');
        }
    }
}