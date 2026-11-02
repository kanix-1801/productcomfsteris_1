/**
 * @author Sagar Anand
 * @date 2026-10-29
 * @description GW-6099 - Tests for AddressResourcePreferencesSelector.
 * @group Field Service
 * @see AddressResourcePreferencesSelector
 */
@IsTest
private class AddressResourcePreferencesSelectorTest {
    /**
     * @description The query runs (USER_MODE, field validation) and returns no rows for Ids that do not exist.
     */
    @IsTest
    static void testQueryReturnsNoRowsForUnknownIds() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: Ids that do not exist in the org

            // WHEN
            Test.startTest();
            List<AddressResourcePreference__c> rows =
                AddressResourcePreferencesSelector.selectByAddressAccountIdsAndLevel(
                    new Set<Id>{ fakeId(Account.SObjectType) },
                    'Preferred'
                );
            Test.stopTest();

            // THEN
            Assert.isTrue(rows.isEmpty(), 'No rows expected');
        }
    }

    /**
     * @description Missing inputs return an empty list without querying.
     */
    @IsTest
    static void testBlankInputsReturnEmptyList() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: null, empty or blank inputs

            // WHEN
            Test.startTest();
            List<AddressResourcePreference__c> blank1 =
                AddressResourcePreferencesSelector.selectByAddressAccountIdsAndLevel(
                    null,
                    'Preferred'
                );
            List<AddressResourcePreference__c> blank2 =
                AddressResourcePreferencesSelector.selectByAddressAccountIdsAndLevel(
                    new Set<Id>{ null },
                    'Preferred'
                );
            List<AddressResourcePreference__c> blank3 =
                AddressResourcePreferencesSelector.selectByAddressAccountIdsAndLevel(
                    new Set<Id>{ fakeId(Account.SObjectType) },
                    ' '
                );
            Test.stopTest();

            // THEN
            Assert.isTrue(blank1.isEmpty(), 'Missing input should return no rows');
            Assert.isTrue(blank2.isEmpty(), 'Missing input should return no rows');
            Assert.isTrue(blank3.isEmpty(), 'Missing input should return no rows');
        }
    }

    private static Id fakeId(Schema.SObjectType sObjectType) {
        return Id.valueOf(sObjectType.getDescribe().getKeyPrefix() + '000000000001');
    }
}