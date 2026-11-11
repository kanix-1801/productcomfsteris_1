/**
 * @description Tests for LocationsSelector (GW-2891 / GW-3816).
 *              Constructor covers the thin SoqlQueryBuilder bind; legacy static methods
 *              remain covered for QACBM parity.
 */
@IsTest
private class LocationsSelectorTest {
    /**
     * @description GW-2891 / GW-3816 - Creates a Rack Location for selector tests.
     */
    @TestSetup
    static void setupData() {
        Id serviceLocationsRtId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Location'
                AND DeveloperName = 'Service_Locations'
            LIMIT 1
        ]
        .Id;
        Set<String> serviceLocationCategories = new Set<String>{
            'Bipolar',
            'Laps',
            'Machine Shop',
            'Optics',
            'Powder Coating',
            'Power',
            'Refiber',
            'Specialty',
            'Stainless',
            'Video'
        };
        String rackCategory;
        for (
            Schema.PicklistEntry picklistEntry : Schema.Location.Repair_Category__c.getDescribe()
                .getPicklistValues()
        ) {
            if (
                picklistEntry.isActive() &&
                serviceLocationCategories.contains(picklistEntry.getValue())
            ) {
                rackCategory = picklistEntry.getValue();
                break;
            }
        }
        insert new Schema.Location(
            Name = 'GW3891-RACK-001',
            RecordTypeId = serviceLocationsRtId,
            LocationType = 'Rack',
            Repair_Category__c = rackCategory,
            TrackRackAssignmentHistory__c = true,
            StatusAssignment__c = 'Repair',
            SubStatusAssignment__c = 'STERIS'
        );
    }

    @IsTest
    static void testConstructor_bindsLocationObject() {
        LocationsSelector selector = new LocationsSelector();
        Assert.isNotNull(selector);
    }

    @IsTest
    static void testSelectRacksByRepairCategories_WhenInputBlank_ReturnsEmpty() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            Test.startTest();
            List<Schema.Location> nullResult = LocationsSelector.selectRacksByRepairCategories(null);
            List<Schema.Location> emptyResult = LocationsSelector.selectRacksByRepairCategories(
                new Set<String>()
            );
            Test.stopTest();

            Assert.isTrue(nullResult.isEmpty(), 'Null categories should return empty');
            Assert.isTrue(emptyResult.isEmpty(), 'Empty categories should return empty');
        }
    }

    @IsTest
    static void testSelectRacksByRepairCategories_returnsMatchingRacks() {
        String category = [
            SELECT Repair_Category__c
            FROM Location
            WHERE Name = 'GW3891-RACK-001'
            LIMIT 1
        ]
        .Repair_Category__c;

        Test.startTest();
        List<Schema.Location> racks = LocationsSelector.selectRacksByRepairCategories(
            new Set<String>{ category, 'NonMatchingCategory' }
        );
        Test.stopTest();

        Assert.areEqual(1, racks.size(), 'Expected one rack for the matching category');
        Assert.areEqual('GW3891-RACK-001', racks[0].Name);
        Assert.areEqual(category, racks[0].Repair_Category__c);
    }

    @IsTest
    static void testSelectRackByIdOrName_blankInputReturnsNull() {
        Test.startTest();
        Assert.isNull(LocationsSelector.selectRackByIdOrName(null));
        Assert.isNull(LocationsSelector.selectRackByIdOrName('  '));
        Test.stopTest();
    }

    @IsTest
    static void testSelectRackByIdOrName_findsRackByNameAndId() {
        Schema.Location rack = [
            SELECT Id, Name
            FROM Location
            WHERE Name = 'GW3891-RACK-001'
            LIMIT 1
        ];

        Test.startTest();
        Schema.Location byName = LocationsSelector.selectRackByIdOrName(rack.Name);
        Schema.Location byId = LocationsSelector.selectRackByIdOrName(String.valueOf(rack.Id));
        Schema.Location missing = LocationsSelector.selectRackByIdOrName('MISSING-RACK-NAME');
        Test.stopTest();

        Assert.areEqual(rack.Id, byName.Id);
        Assert.areEqual(rack.Id, byId.Id);
        Assert.areEqual('Repair', byName.StatusAssignment__c);
        Assert.areEqual('STERIS', byName.SubStatusAssignment__c);
        Assert.areEqual('Repair', byId.StatusAssignment__c);
        Assert.areEqual('STERIS', byId.SubStatusAssignment__c);
        Assert.isNull(missing);
    }

    @IsTest
    static void testSelectByIdNullOrEmptyReturnsEmpty_sprint93Coverage() {
        Assert.areEqual(0, LocationsSelector.selectById(null).size());
        Assert.areEqual(0, LocationsSelector.selectById(new Set<Id>()).size());
    }

}