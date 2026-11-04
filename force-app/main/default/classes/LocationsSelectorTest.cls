/**
 * @description Tests for LocationsSelector (GW-2891 / GW-3816).
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
        // Repair_Category__c is RT-restricted; global describe [0] may not be valid on Service_Locations.
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

    /**
     * @description GW-2891 - Verifies blank Repair Category input returns no racks.
     */
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

    /**
     * @description GW-2891 - Verifies racks are returned for matching Repair Categories.
     */
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

    /**
     * @description GW-3816 - Verifies blank rack input returns null.
     */
    @IsTest
    static void testSelectRackByIdOrName_blankInputReturnsNull() {
        Test.startTest();
        Assert.isNull(LocationsSelector.selectRackByIdOrName(null));
        Assert.isNull(LocationsSelector.selectRackByIdOrName('  '));
        Test.stopTest();
    }

    /**
     * @description GW-3816 - Verifies a Rack can be resolved by Name or Id.
     */
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
    static void testSelectRepairCenters_returnsRepairCenters() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW5492 Repair Center Selector',
            LocationType = 'Repair Center'
        );
        insert repairCenter;

        Test.startTest();
        List<Schema.Location> centers = LocationsSelector.selectRepairCenters();
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