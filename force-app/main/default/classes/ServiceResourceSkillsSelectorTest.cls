/**
 * @author Sagar Anand
 * @date 2026-10-29
 * @description GW-6099 - Tests for ServiceResourceSkillsSelector.
 * @group Field Service
 * @see ServiceResourceSkillsSelector
 */
@IsTest
private class ServiceResourceSkillsSelectorTest {
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
            List<ServiceResourceSkill> rows = ServiceResourceSkillsSelector.selectByServiceResourceIds(
                new Set<Id>{ fakeId(ServiceResource.SObjectType) }
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
            List<ServiceResourceSkill> blank1 = ServiceResourceSkillsSelector.selectByServiceResourceIds(null);
            List<ServiceResourceSkill> blank2 = ServiceResourceSkillsSelector.selectByServiceResourceIds(
                new Set<Id>{ null }
            );
            Test.stopTest();

            // THEN
            Assert.isTrue(blank1.isEmpty(), 'Missing input should return no rows');
            Assert.isTrue(blank2.isEmpty(), 'Missing input should return no rows');
        }
    }

    private static Id fakeId(Schema.SObjectType sObjectType) {
        return Id.valueOf(sObjectType.getDescribe().getKeyPrefix() + '000000000001');
    }
}