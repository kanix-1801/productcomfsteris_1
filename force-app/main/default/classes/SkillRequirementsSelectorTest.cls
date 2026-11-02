/**
 * @author Sagar Anand
 * @date 2026-10-29
 * @description GW-6099 - Tests for SkillRequirementsSelector.
 * @group Field Service
 * @see SkillRequirementsSelector
 */
@IsTest
private class SkillRequirementsSelectorTest {
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
            List<SkillRequirement> rows = SkillRequirementsSelector.selectByRelatedRecordIds(
                new Set<Id>{ fakeId(WorkOrder.SObjectType) }
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
            List<SkillRequirement> blank1 = SkillRequirementsSelector.selectByRelatedRecordIds(null);
            List<SkillRequirement> blank2 = SkillRequirementsSelector.selectByRelatedRecordIds(new Set<Id>{ null });
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