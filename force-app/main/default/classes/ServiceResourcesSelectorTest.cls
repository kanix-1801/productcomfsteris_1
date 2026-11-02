/**
 * @description Tests for ServiceResourcesSelector (GW-3880).
 * @author Uptima Development Team
 * @date 2026-09-03
 */
@IsTest
private class ServiceResourcesSelectorTest {
    @IsTest
    static void testSelectActiveWithRepairCenterByUserId_nullUserId() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<ServiceResource> results =
                ServiceResourcesSelector.selectActiveWithRepairCenterByUserId(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(0, results.size());
        }
    }

    @IsTest
    static void testSelectActiveWithRepairCenterByUserId_noMatch() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<ServiceResource> results =
                ServiceResourcesSelector.selectActiveWithRepairCenterByUserId(UserInfo.getUserId());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(0, results.size());
        }
    }

    @IsTest
    static void testSelectActiveWithRepairCenterByUserId_returnsRepairCenterResource() {
        /********************************************
         * SETUP
         ********************************************/
        Schema.Location repairCenter = insertRepairCenter('SRS Selector RC');
        ServiceResource resource = insertServiceResource(
            UserInfo.getUserId(),
            repairCenter.Id,
            true
        );
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Assert.isNotNull(resource.Id);

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<ServiceResource> results =
                ServiceResourcesSelector.selectActiveWithRepairCenterByUserId(UserInfo.getUserId());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(1, results.size());
            Assert.areEqual(resource.Id, results[0].Id);
            Assert.areEqual(repairCenter.Id, results[0].get('RepairCenter__c'));
            Assert.areEqual(repairCenter.Name, results[0].RepairCenter__r.Name);
        }
    }

    @IsTest
    static void testSelectActiveWithRepairCenterByUserId_excludesInactive() {
        /********************************************
         * SETUP
         ********************************************/
        Schema.Location repairCenter = insertRepairCenter('SRS Selector Inactive RC');
        insertServiceResource(UserInfo.getUserId(), repairCenter.Id, false);
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<ServiceResource> results =
                ServiceResourcesSelector.selectActiveWithRepairCenterByUserId(UserInfo.getUserId());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(0, results.size());
        }
    }

    @IsTest
    static void testSelectActiveWithRepairCenterByUserId_excludesBlankRepairCenter() {
        /********************************************
         * SETUP
         ********************************************/
        insertServiceResource(UserInfo.getUserId(), null, true);
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<ServiceResource> results =
                ServiceResourcesSelector.selectActiveWithRepairCenterByUserId(UserInfo.getUserId());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(0, results.size());
        }
    }

    private static Schema.Location insertRepairCenter(String name) {
        Schema.Location repairCenter = new Schema.Location(
            Name = name,
            LocationType = 'Repair Center',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert repairCenter;
        return repairCenter;
    }

    private static ServiceResource insertServiceResource(
        Id userId,
        Id repairCenterId,
        Boolean isActive
    ) {
        ServiceResource resource = new ServiceResource(
            Name = 'SRS Selector Resource',
            RelatedRecordId = userId,
            LocationId = repairCenterId,
            IsActive = isActive,
            ResourceType = 'T'
        );
        insert resource;
        if (repairCenterId != null) {
            resource.put('RepairCenter__c', repairCenterId);
            update resource;
        }
        return resource;
    }
}