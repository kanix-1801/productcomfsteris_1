/**
 * @description Tests for ServiceResourcesService (GW-3880).
 * @author Uptima Development Team
 * @date 2026-09-03
 */
@IsTest
private class ServiceResourcesServiceTest {
    @IsTest
    static void testGetRepairCenterIdForCurrentUser_whenNone_returnsNull() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            Id repairCenterId = ServiceResourcesService.getRepairCenterIdForCurrentUser();
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNull(repairCenterId);
        }
    }

    @IsTest
    static void testGetRepairCenterIdForCurrentUser_whenActiveResource_returnsRepairCenter() {
        /********************************************
         * SETUP
         ********************************************/
        Schema.Location repairCenter = new Schema.Location(
            Name = 'SRS Service RC',
            LocationType = 'Repair Center',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert repairCenter;

        ServiceResource resource = new ServiceResource(
            Name = 'SRS Service Resource',
            RelatedRecordId = UserInfo.getUserId(),
            LocationId = repairCenter.Id,
            IsActive = true,
            ResourceType = 'T'
        );
        insert resource;
        resource.put('RepairCenter__c', repairCenter.Id);
        update resource;

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
            Id repairCenterId = ServiceResourcesService.getRepairCenterIdForCurrentUser();
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(repairCenter.Id, repairCenterId);
        }
    }

    @IsTest
    static void testGetRepairCenterNameForCurrentUser_whenNone_returnsNull() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            String repairCenterName = ServiceResourcesService.getRepairCenterNameForCurrentUser();
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNull(repairCenterName);
        }
    }

    @IsTest
    static void testGetRepairCenterNameForCurrentUser_whenActiveResource_returnsName() {
        /********************************************
         * SETUP
         ********************************************/
        Schema.Location repairCenter = new Schema.Location(
            Name = 'CAPITAL EQUIPMENT REPAIR CENTER',
            LocationType = 'Repair Center',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert repairCenter;

        ServiceResource resource = new ServiceResource(
            Name = 'SRS Name Resource',
            RelatedRecordId = UserInfo.getUserId(),
            LocationId = repairCenter.Id,
            IsActive = true,
            ResourceType = 'T'
        );
        insert resource;
        resource.put('RepairCenter__c', repairCenter.Id);
        update resource;

        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            String repairCenterName = ServiceResourcesService.getRepairCenterNameForCurrentUser();
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual('CAPITAL EQUIPMENT REPAIR CENTER', repairCenterName);
        }
    }

    @IsTest
    static void testGetRepairCenterIdForCurrentUser_whenInactive_returnsNull() {
        /********************************************
         * SETUP
         ********************************************/
        Schema.Location repairCenter = new Schema.Location(
            Name = 'SRS Service Inactive RC',
            LocationType = 'Repair Center',
            IsInventoryLocation = true,
            IsMobile = true
        );
        insert repairCenter;

        ServiceResource resource = new ServiceResource(
            Name = 'SRS Service Inactive Resource',
            RelatedRecordId = UserInfo.getUserId(),
            LocationId = repairCenter.Id,
            IsActive = true,
            ResourceType = 'T'
        );
        insert resource;
        resource.put('RepairCenter__c', repairCenter.Id);
        resource.IsActive = false;
        update resource;

        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            Id repairCenterId = ServiceResourcesService.getRepairCenterIdForCurrentUser();
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNull(repairCenterId);
        }
    }
}