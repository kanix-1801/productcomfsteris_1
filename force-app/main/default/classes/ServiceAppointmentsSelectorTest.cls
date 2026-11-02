/**
 * @author Sagar Anand
 * @date 2026-10-29
 * @description GW-6099 - Tests for ServiceAppointmentsSelector.
 * @group Field Service
 * @see ServiceAppointmentsSelector
 */
@IsTest
private class ServiceAppointmentsSelectorTest {
    /**
     * @description The realignment query runs (USER_MODE, field validation incl. the Work Order Ship-To path)
     *              and returns no rows for a territory that does not exist.
     */
    @IsTest
    static void testSelectForRealignmentQueryLocatorRunsQuery() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: a territory Id that does not exist in the org
            Id territoryId = Id.valueOf(ServiceTerritory.SObjectType.getDescribe().getKeyPrefix() + '000000000001');

            // WHEN
            Test.startTest();
            Database.QueryLocator locator = ServiceAppointmentsSelector.selectForRealignmentQueryLocator(
                new Set<Id>{ territoryId, null },
                Datetime.now(),
                ServiceAppointmentRealignmentConstants.ELIGIBLE_STATUSES
            );
            Test.stopTest();

            // THEN
            Assert.isFalse(locator.iterator().hasNext(), 'No appointments expected for an unknown territory');
            Assert.isTrue(locator.getQuery().contains('ShipToAddressAccount__c'), 'Ship-To Address should be selected');
        }
    }

    /**
     * @description Missing inputs return a locator that matches nothing.
     */
    @IsTest
    static void testSelectForRealignmentQueryLocatorBlankInputs() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: no territories, no start time, or no statuses
            Set<Id> territoryIdSet = new Set<Id>{
                Id.valueOf(ServiceTerritory.SObjectType.getDescribe().getKeyPrefix() + '000000000001')
            };

            // WHEN
            Test.startTest();
            Database.QueryLocator noTerritories = ServiceAppointmentsSelector.selectForRealignmentQueryLocator(
                null,
                Datetime.now(),
                ServiceAppointmentRealignmentConstants.ELIGIBLE_STATUSES
            );
            Database.QueryLocator noStart = ServiceAppointmentsSelector.selectForRealignmentQueryLocator(
                territoryIdSet,
                null,
                ServiceAppointmentRealignmentConstants.ELIGIBLE_STATUSES
            );
            Database.QueryLocator noStatuses = ServiceAppointmentsSelector.selectForRealignmentQueryLocator(
                territoryIdSet,
                Datetime.now(),
                new List<String>()
            );
            Test.stopTest();

            // THEN
            Assert.isFalse(noTerritories.iterator().hasNext(), 'No territories should match nothing');
            Assert.isFalse(noStart.iterator().hasNext(), 'No start time should match nothing');
            Assert.isFalse(noStatuses.iterator().hasNext(), 'No statuses should match nothing');
        }
    }
}