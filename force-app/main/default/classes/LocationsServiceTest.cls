/**
 * @description Tests for LocationsService (GW-2891 / GW-3816).
 */
@IsTest
private class LocationsServiceTest {
    private static final String RACK_NAME = 'RACK-LOC-SVC-001';

    @TestSetup
    static void setupData() {
        /********************************************
         * SETUP
         ********************************************/
        adb_Location rackBuilder = new adb_Location()
            .name(RACK_NAME)
            .locationType('Rack');
        Schema.Location rack = (Schema.Location) rackBuilder.record;
        rack.TrackRackAssignmentHistory__c = false;
        rackBuilder.persist();
    }

    @IsTest
    static void testGetLocationById_blankReturnsNull() {
        Assert.isNull(LocationsService.getLocationById(null));
    }

    @IsTest
    static void testGetRackByIdOrName_WhenBlankOrMissing_ReturnsNull() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            Schema.Location blankResult = LocationsService.getRackByIdOrName('  ');
            Schema.Location missingResult = LocationsService.getRackByIdOrName('NO-SUCH-RACK');
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNull(blankResult);
            Assert.isNull(missingResult);
        }
    }

    @IsTest
    static void testGetRackByIdOrName_WhenNameOrIdExists_ReturnsRack() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        Schema.Location rack = [
            SELECT Id, Name
            FROM Location
            WHERE Name = :RACK_NAME
            LIMIT 1
        ];

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            Schema.Location byName = LocationsService.getRackByIdOrName(RACK_NAME);
            Schema.Location byId = LocationsService.getRackByIdOrName(String.valueOf(rack.Id));
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(rack.Id, byName.Id);
            Assert.areEqual(rack.Id, byId.Id);
        }
    }

    @IsTest
    static void testGetRacksByRepairCategories_WhenNullOrEmpty_ReturnsEmpty() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            List<Schema.Location> nullResult = LocationsService.getRacksByRepairCategories(null);
            List<Schema.Location> emptyResult =
                LocationsService.getRacksByRepairCategories(new Set<String>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(0, nullResult.size());
            Assert.areEqual(0, emptyResult.size());
        }
    }

    /**
     * @description GW-5231 - Verifies Locations are returned by Id and empty input is guarded.
     */
    @IsTest
    static void testGetLocationsById_WhenIdsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(Id = UserInfo.getUserId());
        Schema.Location rack = [
            SELECT Id, Name
            FROM Location
            WHERE Name = :RACK_NAME
            LIMIT 1
        ];

        System.runAs(testUser) {
            /********************************************
             * GIVEN / WHEN
             ********************************************/
            Test.startTest();
            List<Schema.Location> byId =
                LocationsService.getLocationsById(new Set<Id>{ rack.Id });
            List<Schema.Location> emptyResult = LocationsService.getLocationsById(new Set<Id>());
            List<Schema.Location> nullResult = LocationsService.getLocationsById(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(1, byId.size(), 'The Location should be returned');
            Assert.areEqual(rack.Id, byId[0].Id);
            Assert.areEqual(0, emptyResult.size());
            Assert.areEqual(0, nullResult.size());
        }
    }

    @IsTest
    static void testGetRepairCenters_returnsRepairCenters() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW5492 Repair Center Service',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        Test.startTest();
        List<Schema.Location> centers = LocationsService.getRepairCenters();
        Test.stopTest();

        Boolean found = false;
        for (Schema.Location row : centers) {
            if (row.Id == repairCenter.Id) {
                found = true;
                break;
            }
        }
        Assert.isTrue(found);
    }

}