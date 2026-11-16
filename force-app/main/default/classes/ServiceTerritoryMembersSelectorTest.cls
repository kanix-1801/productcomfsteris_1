/**
 * @author Sagar Anand
 * @date 2026-10-29
 * @description GW-6099 - Tests for ServiceTerritoryMembersSelector.
 * @group Field Service
 * @see ServiceTerritoryMembersSelector
 */
@IsTest
private class ServiceTerritoryMembersSelectorTest {
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
            List<ServiceTerritoryMember> rows = ServiceTerritoryMembersSelector.selectByServiceResourceIdsAndTypes(
                new Set<Id>{ fakeId(ServiceResource.SObjectType) },
                new List<String>{ 'P', 'S' }
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
            List<ServiceTerritoryMember> blank1 = ServiceTerritoryMembersSelector.selectByServiceResourceIdsAndTypes(
                null,
                null
            );
            List<ServiceTerritoryMember> blank2 = ServiceTerritoryMembersSelector.selectByServiceResourceIdsAndTypes(
                new Set<Id>{ null },
                new List<String>{ 'P' }
            );
            List<ServiceTerritoryMember> blank3 = ServiceTerritoryMembersSelector.selectByServiceResourceIdsAndTypes(
                new Set<Id>{ fakeId(ServiceResource.SObjectType) },
                new List<String>()
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

    /**
     * @description GW-2707: selectOpenByResourcesAndTerritories runs for unknown Ids and returns nothing for
     *              missing input.
     */
    @IsTest
    static void testSelectOpenByResourcesAndTerritories() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: Ids that do not exist, and missing inputs
            Set<Id> resourceIds = new Set<Id>{ fakeId(ServiceResource.SObjectType) };
            Set<Id> territoryIds = new Set<Id>{ fakeId(ServiceTerritory.SObjectType) };

            // WHEN
            Test.startTest();
            List<ServiceTerritoryMember> unknown = ServiceTerritoryMembersSelector.selectOpenByResourcesAndTerritories(
                resourceIds,
                territoryIds,
                Datetime.now()
            );
            List<ServiceTerritoryMember> noDate = ServiceTerritoryMembersSelector.selectOpenByResourcesAndTerritories(
                resourceIds,
                territoryIds,
                null
            );
            List<ServiceTerritoryMember> noIds = ServiceTerritoryMembersSelector.selectOpenByResourcesAndTerritories(
                null,
                new Set<Id>(),
                Datetime.now()
            );
            Test.stopTest();

            // THEN
            Assert.isTrue(unknown.isEmpty(), 'No rows expected for unknown Ids');
            Assert.isTrue(noDate.isEmpty(), 'Missing date should return no rows');
            Assert.isTrue(noIds.isEmpty(), 'Missing Ids should return no rows');
        }
    }
}